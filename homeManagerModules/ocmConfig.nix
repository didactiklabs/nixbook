{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules.ocmConfig;
  yamlFormat = pkgs.formats.yaml { };
  opencode-manager = import ../customPkgs/opencode-manager.nix { inherit pkgs; };

  nixProfile = "/nix/var/nix/profiles/default";

  nixPackages = lib.optionals cfg.nix.enable [ "nix" ];

  nixCommands =
    lib.optionals cfg.nix.enable [
      "mkdir -p /nix"
      "mkdir -p /etc/nix && printf '%s\\n' 'experimental-features = nix-command flakes' 'build-users-group =' 'sandbox = false' > /etc/nix/nix.conf"
    ]
    ++ lib.optionals (cfg.nix.enable && cfg.nix.devenv) [
      "nix profile install --profile ${nixProfile} ${cfg.nix.nixpkgs}#devenv"
      "ln -sfn ${nixProfile}/bin/* /usr/local/bin/"
    ]
    ++ lib.optionals cfg.nix.enable [ "chmod -R a+rwX /nix" ];
in
{
  options.customHomeManagerModules.ocmConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable the opencode-manager (`ocm`) configuration.

        Writes `~/.config/opencode-manager/config.yaml` declaratively with:
          - `runtime` (podman by default — Podman is installed system-wide by
            `customNixOSModules.tools`, with the docker compatibility CLI)
          - the `baseImage` block that every workspace container is built from
            (see https://mickael-roger.github.io/opencode-manager/configuration/#base-image)

        The config file is a symlink into the Nix store, so `ocm config edit`
        cannot write it; remove `~/.config/opencode-manager/config.yaml` to take
        manual control of it again (it comes back on the next activation).

        Installs the opencode-manager package itself, so the module works on its
        own. Machines that already enable `devTools` get the same store path
        twice, which Home Manager merges without a collision. The built-in
        module catalogue is seeded into `~/.config/opencode-manager/modules` by
        the `devTools` activation, not by this module.

        Requires a container runtime on the host: `customNixOSModules.tools`
        provides Podman, which is what `runtime` defaults to.
      '';
    };

    runtime = lib.mkOption {
      type = lib.types.enum [
        "docker"
        "podman"
      ];
      default = "podman";
      description = ''
        Container runtime opencode-manager drives (`docker` or `podman`).

        Set to `podman` to match what nixbook installs system-wide through
        `customNixOSModules.tools`.
      '';
    };

    baseImage = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/mroger78/ocm-base:latest";
        description = ''
          Base image workspace containers are built from.

          Defaults to the published prebuilt `ocm-base`, which already ships
          `npx`, `uvx`, `git`, `ripgrep`, `jq`, `opencode`, `claude` and the
          manager scripts, so it is pulled rather than built. Extra `packages`
          and `commands` add a thin local overlay on top of it.
        '';
      };

      packages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Extra apt packages installed into the workspace base image, on top of
          anything the module adds itself (see `nix.enable`).
        '';
      };

      commands = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Extra shell commands run while the workspace base image is built,
          after `baseImage.packages` is installed. They are joined with `&&` and
          executed as a single build step as root, so a non-zero exit aborts the
          build. This module's own `nix`/`devenv` steps (see `nix.*`) run first;
          these are appended after them.
        '';
      };
    };

    nix = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to install Nix into the workspace base image.

          Adds Debian's `nix` package to `baseImage.packages` (the package name
          `nix` resolves to `nix-setup-systemd`, which pulls in `nix-bin`) and
          adds the `baseImage.commands` needed to make it usable inside a
          container:

            - create `/nix`, which Debian normally only creates through a
              `tmpfiles.d` rule that needs systemd and therefore never runs here
            - write `/etc/nix/nix.conf` with `nix-command`/`flakes`, an empty
              `build-users-group` (Debian defaults to `nixbld`; keeping it empty
              makes every build a plain single-user one) and `sandbox = false`
              (nested user namespaces are not guaranteed under rootless Podman)
            - `chmod -R a+rwX /nix` last, so the workspace process — which runs
              under the host UID, not root — can add store paths to what was
              filled in as root during the image build. The container already
              grants passwordless sudo to every user, so this does not weaken
              its isolation.
        '';
      };

      devenv = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to have that Nix install devenv into the workspace base image.

          Runs `nix profile install <nixpkgs>#devenv` into a shared profile under
          `/nix/var/nix/profiles` and symlinks its binaries into
          `/usr/local/bin`, which the base image already puts on every
          process's `PATH`, so `devenv` is available to the workspace user
          without any shell setup. Requires `nix.enable`.
        '';
      };

      nixpkgs = lib.mkOption {
        type = lib.types.str;
        default = "nixpkgs";
        description = ''
          Flake reference `nix profile install` resolves `devenv` from.

          Defaults to the `nixpkgs` flake registry entry; pin a revision (for
          example `github:NixOS/nixpkgs/<rev>`) to make the base image
          rebuild reproducibly.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.nix.enable || !cfg.nix.devenv;
        message = "customHomeManagerModules.ocmConfig.nix.devenv requires customHomeManagerModules.ocmConfig.nix.enable";
      }
    ];

    home.packages = [ opencode-manager ];

    xdg.configFile."opencode-manager/config.yaml".source = yamlFormat.generate "ocm-config.yaml" {
      inherit (cfg) runtime;
      baseImage = {
        inherit (cfg.baseImage) name;
        packages = nixPackages ++ cfg.baseImage.packages;
        commands = nixCommands ++ cfg.baseImage.commands;
      };
    };
  };
}
