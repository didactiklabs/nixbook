{
  config,
  pkgs,
  lib,
  osConfig ? null,
  ...
}:
let
  cfg = config.customHomeManagerModules.nixbookShellConfig;

  # The shell, its launcher, Quickshell and the settings helpers:
  # customPkgs/nixbook-shell/ (see default.nix there for the layout).
  nixbookShell = import ../customPkgs/nixbook-shell { inherit pkgs; };
  inherit (nixbookShell.passthru) settingsLib configName;

  jsonFormat = pkgs.formats.json { };

  # Everything set in Nix: applied on every activation with Nix winning, and
  # locked in the Settings menu. Keys Nix doesn't set are never touched: they
  # keep the shell's built-in default or the value chosen from the menu.
  pinnedSettings = settingsLib.setLeaves cfg.settings;
  pinnedFile = jsonFormat.generate "nixbook-shell-pinned.json" pinnedSettings;
  nixManagedFile = jsonFormat.generate "nix-managed.json" {
    paths = settingsLib.flattenPaths [ ] pinnedSettings;
  };

  # What this machine's Nix configuration sets up, for the Intelligence tab's
  # system prompt (services/Ai.qml appends it while ai.includeSystemContext is
  # on): the assistant can then answer "how do I change X" with the right
  # module, profile file and deploy command. Built from the evaluated
  # configuration, so it follows every switch. No secrets: it is a store path.
  systemContextFile =
    let
      os = osConfig;
      enabledIn =
        set:
        lib.sort lib.lessThan (
          lib.attrNames (lib.filterAttrs (_: v: builtins.isAttrs v && (v.enable or false) == true) set)
        );
      hostName = if os != null then os.networking.hostName else "unknown";
      user = config.home.username;
      names = pkgList: lib.unique (lib.sort lib.lessThan (map lib.getName pkgList));
      osModules = if os != null then enabledIn (os.customNixOSModules or { }) else [ ];
      hmModules = enabledIn (config.customHomeManagerModules or { });
      getPath = path: set: lib.attrByPath (lib.splitString "." path) null set;
      pinnedLines = map (path: "- `${path}` = `${builtins.toJSON (getPath path pinnedSettings)}`") (
        settingsLib.flattenPaths [ ] pinnedSettings
      );
      niriEnabled = config.customHomeManagerModules.niriConfig.enable or false;
      header = ''
        ## This machine (generated from its Nix configuration)
        You are also this user's assistant for their NixOS setup. It is fully
        declarative: the "nixbook" repository (git@github.com:didactiklabs/nixbook,
        revision in /etc/nixos/version) builds every machine. When asked to change
        something, answer with the Nix change in the right file and remind that it
        is applied with `colmena apply-local --sudo switch` from the repository.
        Don't suggest imperative changes (nix-env, editing /etc, pacman…) for
        things the configuration manages.

        - Host `${hostName}`${
          lib.optionalString (os != null)
            ", NixOS ${os.system.nixos.release}, kernel ${os.boot.kernelPackages.kernel.version}, ${pkgs.stdenv.hostPlatform.system}${
              lib.optionalString (os.time.timeZone != null) ", time zone ${os.time.timeZone}"
            }"
        }; user `${user}`
        - Machine profile: `profiles/${hostName}/default.nix` (system) and
          `profiles/${hostName}/${user}/default.nix` (this user's Home Manager
          settings: which modules are enabled and their options)
        - System modules live in `nixosModules/`, user modules in
          `homeManagerModules/`, custom packages in `customPkgs/`; keyboard
          shortcuts are documented in `KEYBINDS.md`
        - Enabled nixbook NixOS modules (`customNixOSModules.<name>.enable`): ${lib.concatStringsSep ", " osModules}
        - Enabled nixbook Home Manager modules (`customHomeManagerModules.<name>.enable`): ${lib.concatStringsSep ", " hmModules}
        ${lib.optionalString niriEnabled "- Compositor: niri (homeManagerModules/niri/niriConfig.nix; its keybinds are listed below)"}

        ## Desktop shell: nixbook-shell
        The bar, dock, sidebars, launcher, notifications, lock screen and desktop
        widgets are nixbook-shell, a Quickshell (QML) shell packaged in
        `customPkgs/nixbook-shell` (source in `src/`) and configured by the Home
        Manager module `customHomeManagerModules.nixbookShellConfig`
        (`homeManagerModules/nixbookShellConfig.nix`). Its settings live in
        `~/.config/nixbook-shell/config.json` and are edited from its Settings
        window (Mod+Escape, or "Shell settings" in the launcher). Settings set in
        Nix (shared ones in `homeManagerModules/nixbookShellConfig/settings.nix`,
        per machine in `nixbookShellConfig.settings` of the user profile) are
        locked in that window; everything else is editable there.
        `nixbook-shell config diff` prints the settings changed from the menu as
        Nix lines, `nixbook-shell ipc call <target> <function>` drives panels.

        Settings set in Nix on this machine:
        ${lib.concatStringsSep "\n" pinnedLines}

        ## Packages installed for this user (Home Manager)
        ${lib.concatStringsSep ", " (names config.home.packages)}
        ${lib.optionalString (os != null) ''

          ## System packages (NixOS)
          ${lib.concatStringsSep ", " (names os.environment.systemPackages)}
        ''}
      '';
    in
    pkgs.runCommand "nixbook-shell-system-context.md"
      {
        inherit header;
        niriKdl = if niriEnabled then (config.programs.niri.finalConfig or "") else "";
        passAsFile = [
          "header"
          "niriKdl"
        ];
      }
      ''
        cat "$headerPath" > "$out"
        if [ -s "$niriKdlPath" ]; then
          {
            printf '\n## Keyboard shortcuts (niri, rendered from the configuration)\n'
            printf 'Answer questions about shortcuts from this list (the authoritative one; Mod = the Super/Windows key). A spawn of nixbook-shell ipc call <target> <fn> opens a shell panel.\n```kdl\n'
            # Store paths only add noise: /nix/store/<hash>-kitty-0.49/bin/kitty -> kitty
            ${lib.getExe pkgs.gawk} '/^binds \{/,/^\}/' "$niriKdlPath" \
              | ${lib.getExe pkgs.gnused} -E 's#/nix/store/[a-z0-9]{32}-[^/ "]*/bin/##g'
            printf '```\n'
          } >> "$out"
        fi
      '';

  # The same, as retrievable one-sentence facts for the chat's config
  # assistant (services/ConfigAssistant.qml, no AI: it answers from these —
  # keys, enabled modules, installed packages, settings). Built by
  # customPkgs/nixbook-shell/scripts/assistant-facts.py.
  systemFactsFile =
    let
      os = osConfig;
      declared = set: lib.sort lib.lessThan (lib.attrNames set);
      enabledIn =
        set:
        lib.sort lib.lessThan (
          lib.attrNames (lib.filterAttrs (_: v: builtins.isAttrs v && (v.enable or false) == true) set)
        );
      names = pkgList: lib.unique (lib.sort lib.lessThan (map lib.getName pkgList));
      settingsPaths = settingsLib.flattenPaths [ ] pinnedSettings;
      info = {
        host = if os != null then os.networking.hostName else "unknown";
        user = config.home.username;
        osEnabled = if os != null then enabledIn (os.customNixOSModules or { }) else [ ];
        osAll = if os != null then declared (os.customNixOSModules or { }) else [ ];
        hmEnabled = enabledIn (config.customHomeManagerModules or { });
        hmAll = declared (config.customHomeManagerModules or { });
        pinned = lib.genAttrs settingsPaths (
          path: lib.attrByPath (lib.splitString "." path) null pinnedSettings
        );
        packages = names (config.home.packages ++ lib.optionals (os != null) os.environment.systemPackages);
        # Every setting the shell has (answers naming another are flagged).
        settingPaths = settingsLib.flattenPaths [ ] settingsLib.builtinDefaults ++ settingsLib.liveKeys;
      };
      niriEnabled = config.customHomeManagerModules.niriConfig.enable or false;
    in
    pkgs.runCommand "nixbook-shell-system-facts.json"
      {
        info = builtins.toJSON info;
        niriKdl = if niriEnabled then (config.programs.niri.finalConfig or "") else "";
        passAsFile = [
          "info"
          "niriKdl"
        ];
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        ${lib.getExe pkgs.gawk} '/^binds \{/,/^\}/' "$niriKdlPath" \
          | ${lib.getExe pkgs.gnused} -E 's#/nix/store/[a-z0-9]{32}-[^/ "]*/bin/##g' > binds.kdl
        python3 ${../customPkgs/nixbook-shell/scripts/assistant-facts.py} "$infoPath" binds.kdl > "$out"
      '';
in
{
  options.customHomeManagerModules.nixbookShellConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable nixbook-shell, nixbook's Quickshell (QML) desktop shell
        (forked from end-4's illogical-impulse via pctrade/end4-pC; packaged in
        customPkgs/nixbook-shell).

        This is an alternative to DankMaterialShell (`dmsConfig`) — the two are
        mutually exclusive, since both draw a top bar, own the lock screen and
        register overlapping layer-shell surfaces. Flip `dmsConfig.enable` off
        when turning this on.

        The shell runs as the `nixbook-shell` user service, bound to
        `graphical-session.target`. Works under niri and Hyprland; under niri
        every panel is driven through `nixbook-shell ipc call <target> <function>`
        keybinds (homeManagerModules/niri/niriConfig.nix, KEYBINDS.md).
      '';
    };

    settings = lib.mkOption {
      type = lib.types.submodule settingsLib.settingsModule;
      default = { };
      # ~450 generated leaves: document the option, not every leaf.
      visible = "shallow";
      example = lib.literalExpression ''
        {
          bar.bottom = true;
          background.screenList = [ "eDP-1" ];
          appearance.persona.enable = true;
        }
      '';
      description = ''
        nixbook-shell settings (the dot-paths of
        `~/.config/nixbook-shell/config.json`, as nested attributes).

        Every key set here is applied on each activation and **locked** in the
        shell's Settings menu (red lock, control disabled); every key left unset
        stays editable from the menu and persists across restarts, reboots and
        switches. Removing a key unlocks it in the running shell after the next
        switch. Shared values live in `homeManagerModules/nixbookShellConfig/settings.nix`
        (set here as defaults, so a profile overrides them key by key).

        The keys are typed options generated from the shell's built-in
        defaults (`customPkgs/nixbook-shell/builtin-defaults.json`), so a misspelt
        key fails evaluation. `nixbook-shell config diff` prints the settings changed
        from the menu as Nix lines; `nixbook-shell config pinned` lists the locked
        keys. Runtime state (wallpaper path, accent colour, avatar, preset
        metadata) has no option: the shell and its scripts own it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Shared settings, as defaults so a profile's `settings` win key by key.
    customHomeManagerModules.nixbookShellConfig.settings = lib.mapAttrsRecursive (_: lib.mkDefault) (
      import ./nixbookShellConfig/settings.nix
    );

    assertions = [
      {
        assertion = !config.customHomeManagerModules.dmsConfig.enable;
        message = ''
          customHomeManagerModules.nixbookShellConfig and customHomeManagerModules.dmsConfig
          cannot both be enabled: both shells draw a top bar, a lock screen and
          overlapping layer-shell surfaces. Pick one.
        '';
      }
    ];

    xdg.configFile."quickshell/${configName}".source = nixbookShell.passthru.shell;

    # The manifest the shell reads to know which settings Nix owns: every
    # pinned leaf path. Drives the red lock icon and the disabled control in
    # the Settings menu (modules/common/NixManaged.qml in the package).
    xdg.configFile."nixbook-shell/nix-managed.json".source = nixManagedFile;
    # ...and their values: NixManaged.qml restores any pinned key that gets
    # changed at runtime (menu, QuickConfig, IPC, scripts); `nixbook-shell config`
    # reads them too.
    xdg.configFile."nixbook-shell/nix-pinned-values.json".source = pinnedFile;
    # Machine context for the AI assistant's system prompt (see above).
    xdg.configFile."nixbook-shell/system-context.md".source = systemContextFile;
    xdg.configFile."nixbook-shell/system-facts.json".source = systemFactsFile;

    # Launcher entry for the Settings window (nixbook-shell's own launcher, fuzzel…).
    xdg.desktopEntries.nixbook-shell-settings = {
      name = "Shell settings";
      genericName = "Desktop shell settings";
      comment = "Settings of the nixbook-shell desktop shell (bar, dock, widgets, theme…)";
      exec = "${lib.getExe nixbookShell} ipc call settings open";
      icon = "preferences-desktop";
      terminal = false;
      categories = [
        "Settings"
        "DesktopSettings"
      ];
      settings.Keywords = "settings;preferences;shell;nixbook;bar;dock;theme;wallpaper;persona;";
    };

    home.packages = [
      nixbookShell
      nixbookShell.passthru.quickshell
      # Condensed display face used by the optional Persona style
      # (appearance.persona.fonts) for titles and numbers.
      pkgs.oswald
    ];

    # Rename from end4-pC: move the user's settings, presets, actions… from
    # ~/.config/illogical-impulse (and the account-picture cache) to the
    # nixbook-shell names, once, before Home Manager links the lock manifests
    # into the new directory. Home Manager's own two links are not moved: it
    # recreates them in the new directory and removes the old ones.
    home.activation.nixbookShellMigrate =
      lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
        ''
          shell_old="''${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse"
          shell_new="''${XDG_CONFIG_HOME:-$HOME/.config}/nixbook-shell"
          if [ -d "$shell_old" ] && [ ! -e "$shell_new/config.json" ]; then
            run mkdir -p "$shell_new"
            for shell_entry in "$shell_old"/* "$shell_old"/.[!.]*; do
              [ -e "$shell_entry" ] || [ -L "$shell_entry" ] || continue
              shell_name=$(basename "$shell_entry")
              case "$shell_name" in nix-managed.json | nix-pinned-values.json) continue ;; esac
              [ -e "$shell_new/$shell_name" ] || run mv "$shell_entry" "$shell_new/$shell_name"
            done
          fi
          shell_cache="''${XDG_CACHE_HOME:-$HOME/.cache}"
          if [ -d "$shell_cache/end4-pc" ] && [ ! -e "$shell_cache/nixbook-shell" ]; then
            run mv "$shell_cache/end4-pc" "$shell_cache/nixbook-shell"
          fi
        '';

    # The shell writes its settings, generated Material You palette and
    # wallpaper state into these; nothing creates them for us on a fresh user.
    #
    # config.json itself stays a real file (the shell rewrites it live from the
    # Settings panel, so it cannot be an xdg.configFile): every key Nix sets is
    # merged into it on each activation (Nix wins), every other key is left
    # alone. Runs after linkGeneration so the running shell, told to reload,
    # sees the new lock manifest too.
    home.activation.nixbookShellDirs = lib.hm.dag.entryAfter [ "writeBoundary" "linkGeneration" ] ''
      run mkdir -p \
        "''${XDG_CONFIG_HOME:-$HOME/.config}/nixbook-shell" \
        "''${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/wallpaper" \
        "''${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/user/generated"

      shell_config="''${XDG_CONFIG_HOME:-$HOME/.config}/nixbook-shell/config.json"
      # State of the former editable-defaults tier; no longer used.
      run rm -f "''${XDG_STATE_HOME:-$HOME/.local/state}/end4-pc/applied-defaults.json"
      [ -d "''${XDG_STATE_HOME:-$HOME/.local/state}/end4-pc" ] \
        && run rmdir --ignore-fail-on-non-empty "''${XDG_STATE_HOME:-$HOME/.local/state}/end4-pc"

      shell_tmp=$(mktemp -d)
      echo '{}' > "$shell_tmp/empty.json"
      shell_live="$shell_tmp/empty.json"
      shell_ok=1
      if [ -s "$shell_config" ]; then
        if ${lib.getExe pkgs.jq} -e 'type == "object"' "$shell_config" >/dev/null 2>&1; then
          shell_live="$shell_config"
        else
          warnEcho "nixbook-shell: $shell_config is not a valid JSON object, leaving it alone"
          shell_ok=0
        fi
      fi
      if [ "$shell_ok" = 1 ]; then
        if ${lib.getExe pkgs.jq} -n \
              --slurpfile live "$shell_live" \
              --slurpfile pinned ${pinnedFile} \
              '$live[0] * $pinned[0]' > "$shell_tmp/config.json"; then
          run install -m644 "$shell_tmp/config.json" "$shell_config"
        else
          warnEcho "nixbook-shell: failed to merge settings into $shell_config"
        fi
      fi
      rm -rf "$shell_tmp"

      # A running shell doesn't notice the swapped symlinks: have it re-read
      # the lock manifest, the pinned values and config.json. No-op when the
      # shell isn't running.
      if [ -z "''${DRY_RUN:-}" ]; then
        XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
          ${lib.getExe nixbookShell} ipc call nixManaged reload >/dev/null 2>&1 || true
      fi
    '';

    systemd.user.services.nixbook-shell = {
      Unit = {
        Description = "nixbook-shell Quickshell desktop shell";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = lib.getExe nixbookShell;
        Restart = "on-failure";
        RestartSec = 2;
        Slice = "app.slice";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.cliphist = {
      Unit = {
        Description = "Clipboard history store for nixbook-shell (cliphist)";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${nixbookShell.passthru.cliphistWatch}";
        Restart = "on-failure";
        RestartSec = 2;
        Slice = "background.slice";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
