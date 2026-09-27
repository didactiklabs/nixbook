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

  # Host-side hooks of the kubeswitch ocm module. ocm runs them on the host, so
  # they can use the host's kubeswitch, its SwitchConfig and Nix store tools.
  kubeswitchHookPath = lib.makeBinPath [
    cfg.kubeswitch.package
    pkgs.kubectl
    pkgs.yq-go
    pkgs.coreutils
  ];

  kubeswitchListContexts = pkgs.writeShellScript "ocm-kubeswitch-list-contexts" ''
    # optionsCommand: one kubeswitch context ("<store dir>/<context>") per line.
    # Silent on failure, so the picker just shows "No options available".
    export PATH=${kubeswitchHookPath}:$PATH
    switcher --config-path ${lib.escapeShellArg cfg.kubeswitch.configPath} list-contexts 2>/dev/null || true
  '';

  kubeswitchResolve = pkgs.writeShellScript "ocm-kubeswitch-resolve" ''
    # resolve: turn the selected kubeswitch context ($OCM_CONTEXT) into a
    # self-contained single-context kubeconfig, printed as "kubeconfig=<base64>".
    # The context, cluster and user are renamed to the kubeswitch name so imports
    # from different kubeconfig files never collide in the workspace config.
    # Prints nothing when the context cannot be found.
    set -u
    export PATH=${kubeswitchHookPath}:$PATH
    [ -n "''${OCM_CONTEXT:-}" ] || exit 0

    # A throwaway state directory keeps these lookups out of the host's kswitch
    # history; the kubeconfig copy kubeswitch writes is removed afterwards.
    state="$(mktemp -d)"
    trap 'rm -rf "$state"' EXIT
    out="$(switcher --config-path ${lib.escapeShellArg cfg.kubeswitch.configPath} \
      --state-directory "$state" set-context "$OCM_CONTEXT" 2>/dev/null)" || exit 0
    tmp="''${out#__ }"
    tmp="''${tmp%%,*}"
    [ -f "$tmp" ] || exit 0

    cfg="$(kubectl --kubeconfig "$tmp" config view --minify --flatten 2>/dev/null)"
    rm -f "$tmp"
    [ -n "$cfg" ] || exit 0

    cfg="$(printf '%s' "$cfg" | NAME="$OCM_CONTEXT" yq '
      (.clusters[].name) = strenv(NAME) |
      (.users[].name) = strenv(NAME) |
      (.contexts[].name) = strenv(NAME) |
      (.contexts[].context.cluster) = strenv(NAME) |
      (.contexts[].context | select(.user != null) | .user) = strenv(NAME) |
      .["current-context"] = strenv(NAME)
    ')" || exit 0

    printf 'kubeconfig=%s\n' "$(printf '%s' "$cfg" | base64 -w0)"
  '';

  # Real files, not links into the store: the module tree is bind-mounted into
  # every workspace, where host store paths do not exist.
  kubeswitchModule = pkgs.runCommand "ocm-module-kubeswitch" { } ''
    mkdir -p $out
    cp ${./ocmModules/kubeswitch}/{module.yml,install,uninstall} $out/
    cp ${kubeswitchListContexts} $out/list-contexts
    cp ${kubeswitchResolve} $out/resolve
    chmod 0755 $out/install $out/uninstall $out/list-contexts $out/resolve
  '';

  claudeCredentials = cfg.claudeCode.credentials;

  # module.yml of the shared-login module: its source depends on
  # claudeCode.credentials.path, so it is generated here.
  claudeAuthSharedManifest = yamlFormat.generate "claude-auth-shared-module.yml" {
    name = "claude-auth-shared";
    version = 1;
    description = "Share this host's Claude Code subscription login with the workspace (bind mount, so both refresh the same tokens). Adding or removing it recreates the container.";
    mounts = [
      {
        source = claudeCredentials.path;
        target = "/home/debian/.claude/.credentials.json";
        optional = true;
      }
    ];
  };

  claudeAuthResolve = pkgs.writeShellScript "ocm-claude-auth-resolve" ''
    # resolve: hand the host's Claude Code OAuth credentials to the container
    # install as "credentials=<base64>". Prints nothing when import is off or the
    # host has no Claude login, so the install writes nothing.
    set -u
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}:$PATH
    case "''${OCM_IMPORT_AUTH:-yes}" in
      yes | true | 1) ;;
      *) exit 0 ;;
    esac
    creds=${lib.escapeShellArg claudeCredentials.path}
    [ -s "$creds" ] || exit 0
    printf 'credentials=%s\n' "$(base64 -w0 "$creds")"
  '';

  # Real files, not links into the store (see kubeswitchModule).
  claudeAuthModule = pkgs.runCommand "ocm-module-claude-auth" { } ''
    mkdir -p $out
    cp ${./ocmModules/claude-auth}/{module.yml,install,uninstall} $out/
    cp ${claudeAuthResolve} $out/resolve
    chmod 0755 $out/install $out/uninstall $out/resolve
  '';

  claudeAuthSharedModule = pkgs.runCommand "ocm-module-claude-auth-shared" { } ''
    mkdir -p $out
    cp ${claudeAuthSharedManifest} $out/module.yml
    cp ${./ocmModules/claude-auth-shared}/{install,uninstall} $out/
    chmod 0644 $out/module.yml
    chmod 0755 $out/install $out/uninstall
  '';

  # category/name -> module directory, installed into ocm's primary moduleDir
  # (the only one it runs resolve hooks from).
  ocmModules =
    lib.optionalAttrs cfg.kubeswitch.enable {
      "infra/kubeswitch" = kubeswitchModule;
    }
    // lib.optionalAttrs claudeCredentials.enable {
      "tools/claude-auth" = claudeAuthModule;
      "tools/claude-auth-shared" = claudeAuthSharedModule;
    };

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

    claudeCode.credentials = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to install the two ocm modules that give a workspace this
          host's Claude Code subscription login, so neither `claude` nor
          OpenCode's `opencode-claude-auth` plugin has to log in again inside it.
          Installing them only makes them available: each is added per
          workspace from the module editor, so you pick which workspaces get
          the login.

          `claude-auth-shared` (recommended) shares the login itself: the
          module declares an ocm `mounts` entry that bind-mounts
          `claudeCode.credentials.path` read-write onto
          `/home/debian/.claude/.credentials.json` in the containers of the
          workspaces that have it, so the host and those workspaces read and
          refresh one login (Claude Code notices when the file changes on
          disk). Adding or removing it recreates that workspace's container.
          The mount is optional: while the host has no login it is skipped, and
          it is added on the first start after you log in. A symlink would not
          do: Claude Code refuses a symlinked credentials file.

          `claude-auth` imports a copy instead. Its `resolve` hook runs on
          the host and reads `claudeCode.credentials.path`; the container
          `install` writes it to the workspace `~/.claude/.credentials.json`
          (mode 0600). Nothing is stored in `workspace.yaml`, and the hook re-runs
          on every add and reconcile, so the workspace picks up the host's
          current login. A workspace login that is already newer (by
          `claudeAiOauth.expiresAt`) is kept rather than rolled back.

          An imported copy refreshes its tokens on its own. OAuth refresh tokens
          rotate, so a copy and the host can end up invalidating each other's
          login, which `claude-auth-shared` avoids. When both are added,
          `claude-auth` sees the mount and leaves it alone.
        '';
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/.claude/.credentials.json";
        defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.claude/.credentials.json"'';
        description = ''
          Host file holding Claude Code's subscription login. Claude Code
          writes it on Linux after `claude /login` (under `CLAUDE_CONFIG_DIR`
          when that is set).
        '';
      };
    };

    kubeswitch = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.customHomeManagerModules.kubeswitchConfig.enable;
        defaultText = lib.literalExpression "config.customHomeManagerModules.kubeswitchConfig.enable";
        description = ''
          Whether to install the `kubeswitch` ocm module
          (`~/.config/opencode-manager/modules/infra/kubeswitch`).

          In a workspace's module editor it lists every context from the host's
          kubeswitch stores (as `kswitch` shows them, e.g. `configs/admin@prod`)
          and imports each selected one into the workspace `~/.kube/config`:

            - `list-contexts` and `resolve` run on the host with the host's
              kubeswitch and `kubeswitch.configPath`, so nothing is mounted and
              the container only ever receives the selected contexts
            - the context is exported minified and flattened (credentials
              inlined), with its context, cluster and user renamed to the
              kubeswitch name so same-named contexts from different kubeconfig
              files don't collide
            - `install` puts kubectl and kubelogin (`kubectl oidc-login`) in the
              container; OIDC contexts log in again from there, since the host
              token cache is not shared

          The files are copied on activation (ocm bind-mounts the module tree
          into the containers, where store links would dangle) and replaced
          whenever they differ from the Nix-built ones.
        '';
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = config.programs.kubeswitch.package;
        defaultText = lib.literalExpression "config.programs.kubeswitch.package";
        description = "kubeswitch package whose `switcher` the host hooks run.";
      };

      configPath = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/.kube/switch-config.yaml";
        defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.kube/switch-config.yaml"'';
        description = ''
          SwitchConfig the host hooks read the kubeconfig stores from. Defaults
          to the file `kubeswitchConfig` writes.
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

    # Copied, not linked (see kubeswitchModule). Only rewritten when it differs,
    # and only the managed modules are touched.
    home.activation.ocmModules = lib.mkIf (ocmModules != { }) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatStrings (
          lib.mapAttrsToList (path: src: ''
            dest="$HOME/.config/opencode-manager/modules/${path}"
            if ! diff -rq ${src} "$dest" >/dev/null 2>&1; then
              $DRY_RUN_CMD mkdir -p "$(dirname "$dest")"
              $DRY_RUN_CMD rm -rf "$dest"
              $DRY_RUN_CMD cp -R ${src} "$dest"
              $DRY_RUN_CMD chmod -R u+w "$dest"
            fi
          '') ocmModules
        )
      )
    );

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
