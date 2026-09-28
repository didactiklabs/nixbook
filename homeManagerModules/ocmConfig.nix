{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules.ocmConfig;
  yamlFormat = pkgs.formats.yaml { };
  jsonFormat = pkgs.formats.json { };
  inherit (pkgs.customPkgs) opencode-manager;

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

  hostDisplay = cfg.hostDisplay;

  # module.yml of the host-display module: its mount sources are host paths
  # (ocm expands no variables in them, only a leading "~/"), so it is generated
  # here.
  hostDisplayManifest = yamlFormat.generate "host-display-module.yml" {
    name = "host-display";
    version = 1;
    description = "Give the workspace this host's Wayland display (and XWayland), plus grim and an ocm-screenshot helper, so agents can run GUI apps and capture screenshots. The agent can see the whole desktop. Adding or removing it recreates the container.";
    mounts = [
      {
        source = hostDisplay.waylandSocket;
        # Inside the home, so ocm creates the mount point (and its 0700 parent,
        # used as XDG_RUNTIME_DIR) owned by the host user.
        target = "/home/debian/.cache/ocm-host-display/wayland-0";
        optional = true;
      }
    ]
    ++ lib.optional (hostDisplay.x11Display != null) {
      source = "/tmp/.X11-unix/X${toString hostDisplay.x11Display}";
      target = "/tmp/.X11-unix/X${toString hostDisplay.x11Display}";
      optional = true;
    };
  };

  hostDisplayModule = pkgs.runCommand "ocm-module-host-display" { } ''
    mkdir -p $out
    cp ${hostDisplayManifest} $out/module.yml
    cp ${./ocmModules/host-display}/{install,uninstall} $out/
    chmod 0644 $out/module.yml
    chmod 0755 $out/install $out/uninstall
  '';

  notificationHistory = cfg.notificationHistory;
  # Host directory the mirror service keeps a copy of the history in: the
  # shell's own directory also holds notes, todos and AI chats, and a mount of
  # the file itself would go stale on the shell's atomic (rename) rewrites.
  notificationHistoryMirror = "${config.xdg.stateHome}/ocm-notification-history";

  notificationHistoryManifest = yamlFormat.generate "notification-history-module.yml" {
    name = "notification-history";
    version = 1;
    description = "Share this host's nixbook-shell notification history (read-only, live) with the workspace, plus a host-notifications query helper. Adding or removing it recreates the container.";
    mounts = [
      {
        source = notificationHistoryMirror;
        target = "/home/debian/.local/share/host-notifications";
        readOnly = true;
        optional = true;
      }
    ];
  };

  notificationHistoryModule = pkgs.runCommand "ocm-module-notification-history" { } ''
    mkdir -p $out
    cp ${notificationHistoryManifest} $out/module.yml
    cp ${./ocmModules/notification-history}/{install,uninstall} $out/
    chmod 0644 $out/module.yml
    chmod 0755 $out/install $out/uninstall
  '';

  notificationHistoryMirrorScript = pkgs.writeShellScript "ocm-notification-history-mirror" ''
    # Copy the history next to its mirror, then rename it into place, so a
    # workspace never reads a half-written file.
    set -eu
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}:$PATH
    src=${lib.escapeShellArg notificationHistory.source}
    dest=${lib.escapeShellArg notificationHistoryMirror}
    [ -f "$src" ] || exit 0
    mkdir -p -m 0700 "$dest"
    cp "$src" "$dest/.notification-history.json.tmp"
    chmod 0600 "$dest/.notification-history.json.tmp"
    mv -f "$dest/.notification-history.json.tmp" "$dest/notification-history.json"
  '';

  # Modules nixbook used to install, deleted from ocm's moduleDir (see the
  # ocmModules activation). The two claude-auth modules handed the host's
  # Claude Code login to workspaces, which cannot work: refresh tokens rotate,
  # so a copy and the host log each other out, and Claude Code replaces
  # .credentials.json by rename, so a bind mount of that one file goes stale
  # on the host's next login or refresh. Each workspace logs in on its own.
  retiredOcmModules = [
    "tools/claude-auth"
    "tools/claude-auth-shared"
  ];

  # category/name -> module directory, installed into ocm's primary moduleDir
  # (the only one it runs resolve hooks from).
  ocmModules =
    lib.optionalAttrs cfg.kubeswitch.enable {
      "infra/kubeswitch" = kubeswitchModule;
    }
    // lib.optionalAttrs hostDisplay.enable {
      "tools/host-display" = hostDisplayModule;
    }
    // lib.optionalAttrs notificationHistory.enable {
      "tools/notification-history" = notificationHistoryModule;
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

    opencodeSettings = lib.mkOption {
      type = lib.types.nullOr jsonFormat.type;
      default = {
        "$schema" = "https://opencode.ai/config.json";
        plugin = config.programs.opencode.settings.plugin or [ "opencode-claude-auth@latest" ];
      };
      defaultText = lib.literalExpression ''
        {
          "$schema" = "https://opencode.ai/config.json";
          plugin = config.programs.opencode.settings.plugin or [ "opencode-claude-auth@latest" ];
        }
      '';
      description = ''
        Global OpenCode configuration shared by every workspace.

        Written to `~/.config/opencode-manager/opencode/opencode.json`, which
        ocm syncs one way into each workspace as
        `/home/debian/.config/opencode/opencode.json`. Copied as a regular file
        like `agentInstructions`, for the same reason.

        Defaults to the host's OpenCode plugins (the `opencodeConfig` auth
        plugins, including `opencode-claude-auth`), so workspaces authenticate
        the same way; OpenCode installs them on its first start in the
        workspace. Only the plugins are carried over: the host's providers
        (e.g. the local Ollama endpoint) are not reachable from a container.

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

    hostDisplay = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to install the `tools/host-display` ocm module, which gives a
          workspace this host's graphical session so agents can launch GUI apps
          and capture screenshots of them. Installing it only makes it
          available: add it per workspace from the module editor.

          Its `mounts` bind-mount `hostDisplay.waylandSocket` onto
          `~/.cache/ocm-host-display/wayland-0` in the container (the directory
          becomes `XDG_RUNTIME_DIR`) and, unless `hostDisplay.x11Display` is
          `null`, the XWayland socket onto `/tmp/.X11-unix/X<n>`. Both are
          optional, so a workspace started without a session runs without them.
          Rootless Podman runs the container under the host UID
          (`--userns keep-id`), so it can connect to the sockets as is.

          The container `install` puts grim, wl-clipboard, x11-utils and
          imagemagick in the workspace, adds `ocm-screenshot [GEOMETRY]` (saves
          a PNG under `~/screenshots` and prints its path), and exports
          `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY`, `DISPLAY`, toolkit backend
          hints and `LIBGL_ALWAYS_SOFTWARE=1` (no GPU is passed through) in a
          marked `~/.env` block that `uninstall` removes.

          A workspace with it can capture the whole desktop (wlr-screencopy)
          and, on sway and Hyprland, send input through virtual-keyboard and
          virtual-pointer: add it only to workspaces you trust with that. The
          socket is bound by inode, so after the compositor restarts (a new
          login) restart the workspaces that have it.
        '';
      };

      waylandSocket = lib.mkOption {
        type = lib.types.str;
        default = "/run/user/1000/wayland-1";
        description = ''
          Host Wayland socket to share, i.e. `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY`
          in the host session. niri, sway and Hyprland name theirs `wayland-1`
          when it is free; users without an explicit UID get 1000 when they are
          the first normal user.
        '';
      };

      x11Display = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = 0;
        description = ''
          XWayland display number (`:0` → `0`, as xwayland-satellite usually
          takes) whose `/tmp/.X11-unix/X<n>` socket is also shared, for X11-only
          apps. `null` shares no X11 display.
        '';
      };
    };

    notificationHistory = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.customHomeManagerModules.nixbookShellConfig.enable;
        defaultText = lib.literalExpression "config.customHomeManagerModules.nixbookShellConfig.enable";
        description = ''
          Whether to install the `tools/notification-history` ocm module, which
          gives a workspace read-only, live access to nixbook-shell's
          notification history. Installing it only makes it available: add it
          per workspace from the module editor.

          The shell rewrites `notificationHistory.source` by rename, in a
          directory that also holds its notes, todos and AI chats, so neither
          the file nor its directory is mounted. A `ocm-notification-history`
          user path unit copies the file, whenever it changes, into
          `$XDG_STATE_HOME/ocm-notification-history/` (0700, the copy renamed
          into place), and the module's `mounts` bind that directory read-only
          onto `~/.local/share/host-notifications` (optional: skipped until
          the first copy exists).

          The container `install` adds `host-notifications [-n COUNT] [-a APP]
          [-s HOURS] [--json]` and a marked `~/.claude/CLAUDE.md` block that
          tells Claude Code where the history is; `uninstall` removes both.
        '';
      };

      source = lib.mkOption {
        type = lib.types.str;
        default = "${config.xdg.stateHome}/quickshell/user/notification-history.json";
        defaultText = lib.literalExpression ''"''${config.xdg.stateHome}/quickshell/user/notification-history.json"'';
        description = "Notification history file nixbook-shell writes (`Directories.notificationHistoryPath`).";
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
    # and only the managed modules are touched. Retired modules are deleted, but
    # only once no workspace manifest lists them: ocm needs a module's scripts
    # to uninstall it or to reinstall it into a recreated container.
    home.activation.ocmModules = lib.hm.dag.entryAfter [ "writeBoundary" ] (
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
      + lib.concatMapStrings (path: ''
        dest="$HOME/.config/opencode-manager/modules/${path}"
        if [ -d "$dest" ]; then
          if grep -qsE '^[[:space:]]+(- )?name: "?${baseNameOf path}"?[[:space:]]*$' \
            "$HOME"/.local/share/opencode-manager/workspaces/*/workspace.yaml; then
            echo "ocm: keeping retired module ${path}: remove it from the workspaces that still use it" >&2
          else
            $DRY_RUN_CMD rm -rf "$dest"
          fi
        fi
      '') retiredOcmModules
    );

    systemd.user.paths.ocm-notification-history = lib.mkIf notificationHistory.enable {
      Unit.Description = "Mirror the nixbook-shell notification history for ocm workspaces";
      Path.PathChanged = notificationHistory.source;
      Install.WantedBy = [ "paths.target" ];
    };

    systemd.user.services.ocm-notification-history = lib.mkIf notificationHistory.enable {
      Unit.Description = "Mirror the nixbook-shell notification history for ocm workspaces";
      Service = {
        Type = "oneshot";
        ExecStart = "${notificationHistoryMirrorScript}";
      };
      # Also refresh once per login, whether or not the file changed since.
      Install.WantedBy = [ "default.target" ];
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

    home.activation.ocmOpencodeSettings = lib.mkIf (cfg.opencodeSettings != null) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settings="$HOME/.config/opencode-manager/opencode/opencode.json"
        src=${jsonFormat.generate "ocm-opencode.json" cfg.opencodeSettings}
        if ! cmp -s "$src" "$settings"; then
          $DRY_RUN_CMD mkdir -p "$(dirname "$settings")"
          $DRY_RUN_CMD rm -f "$settings"
          $DRY_RUN_CMD install -m 0644 "$src" "$settings"
        fi
      ''
    );
  };
}
