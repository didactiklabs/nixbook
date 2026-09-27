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

  # Where ocm syncs the shared OpenCode tree inside every workspace container.
  workspaceAgentsFile = "/home/debian/.config/opencode/AGENTS.md";

  claudeCommands = lib.optionals cfg.claudeCode.importAgentInstructions [
    "mkdir -p /etc/claude-code && printf '%s\\n' '@${workspaceAgentsFile}' > /etc/claude-code/CLAUDE.md"
  ];

  defaultInstructions = lib.concatStringsSep "\n" (
    [
      "# Workspace guidelines"
      ""
      "These apply to every project in this workspace unless the project's own instructions say otherwise."
      ""
    ]
    ++ lib.optionals (cfg.nix.enable && cfg.nix.devenv) [
      "## Environment"
      ""
      "- Prefer devenv. If the project has a `devenv.nix`, run commands through it (`devenv shell -- <cmd>`, `devenv test`, `devenv tasks run <task>`) instead of whatever happens to be on PATH."
      "- If a project has no devenv setup and needs toolchains or services, propose adding a `devenv.nix` (`devenv init`) rather than installing them globally."
      "- For a one-off tool, use `nix shell nixpkgs#<pkg> -c <cmd>` or `nix run nixpkgs#<pkg>` instead of `apt`, `pip install --user`, `npm -g` or `curl | sh`."
      ""
    ]
    ++ [
      "## Working style"
      ""
      "- Read the project's README, AGENTS.md/CLAUDE.md and existing code before changing it; match its conventions."
      "- Run the project's tests, linters and formatters after a change, and report failures honestly."
      "- Do not commit or push unless asked."
    ]
  );

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
    ++ lib.optionals cfg.nix.enable [
      "chmod -R a+rwX /nix"
      # Nix resets these two to 0755 whenever it opens the store unless they
      # already are, and chmod fails for the workspace user, who doesn't own them.
      "mkdir -p /nix/var/nix/profiles/per-user /nix/var/nix/gcroots/per-user"
      "chmod 0755 /nix/var/nix/profiles/per-user /nix/var/nix/gcroots/per-user"
    ];
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

    agentInstructions = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = defaultInstructions;
      defaultText = lib.literalMD "generic guidelines (prefer devenv and `nix shell` when `nix.devenv` is on, match project conventions, run tests, don't commit unasked)";
      description = ''
        Instructions shared by every agent in every workspace.

        Written to `~/.config/opencode-manager/opencode/AGENTS.md`, which ocm
        syncs one way into each workspace as the global OpenCode `AGENTS.md`
        (`/home/debian/.config/opencode/AGENTS.md`). It is copied as a regular
        file by an activation step, not linked: ocm refuses symlinks in the
        shared tree and then fails the whole sync. Manual edits to that file are
        overwritten on the next activation.

        `null` leaves the file alone so it can be managed by hand.
      '';
    };

    claudeCode.importAgentInstructions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether Claude Code in the workspaces also reads the shared `AGENTS.md`.

        ocm only shares configuration with OpenCode; Claude Code keeps its own
        per-workspace `home/.claude/`. This bakes a managed
        `/etc/claude-code/CLAUDE.md` into the base image containing a single
        import of the synced `AGENTS.md`, so both agents follow the same
        file, and editing it needs no image rebuild.
      '';
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
            - put `/nix/var/nix/{profiles,gcroots}/per-user` back to `0755`:
              Nix chmods them to that mode on every store open unless they
              already have it, which fails ("Operation not permitted") for the
              workspace user, who doesn't own them.
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
        commands = nixCommands ++ claudeCommands ++ cfg.baseImage.commands;
      };
    };

    # Copied, not linked: ocm rejects symlinks in the shared OpenCode tree.
    # Only rewritten when it differs, since every write triggers a sync.
    home.activation.ocmAgentInstructions = lib.mkIf (cfg.agentInstructions != null) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        agents="$HOME/.config/opencode-manager/opencode/AGENTS.md"
        src=${pkgs.writeText "ocm-AGENTS.md" cfg.agentInstructions}
        if ! cmp -s "$src" "$agents"; then
          $DRY_RUN_CMD mkdir -p "$(dirname "$agents")"
          $DRY_RUN_CMD rm -f "$agents"
          $DRY_RUN_CMD install -m 0644 "$src" "$agents"
        fi
      ''
    );
  };
}
