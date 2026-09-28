{
  config,
  pkgs,
  lib,
  osConfig ? null,
  ...
}:
# programs.nixbook-shell: runs nixbook-shell as a user service, publishes the
# settings set in Nix (applied on every activation and locked in the shell's
# Settings menu) and the machine context its AI chat and config assistant use.
let
  cfg = config.programs.nixbook-shell;
  # Imported directly, not taken from cfg.package: the `settings` option type
  # is generated from it, and option types can't depend on config.
  settingsLib = import ./lib.nix { inherit lib; };
  inherit (cfg.package.passthru) configName;

  jsonFormat = pkgs.formats.json { };

  # Everything set in Nix: applied on every activation with Nix winning, and
  # locked in the Settings menu. Keys Nix doesn't set are never touched: they
  # keep the shell's built-in default or the value chosen from the menu.
  pinnedSettings = settingsLib.setLeaves cfg.settings;
  pinnedPaths = settingsLib.flattenPaths [ ] pinnedSettings;
  pinnedFile = jsonFormat.generate "nixbook-shell-pinned.json" pinnedSettings;
  nixManagedFile = jsonFormat.generate "nix-managed.json" {
    paths = pinnedPaths;
  };

  names = pkgList: lib.unique (lib.sort lib.lessThan (map lib.getName pkgList));
  packages =
    config.home.packages ++ lib.optionals (osConfig != null) osConfig.environment.systemPackages;

  # Machine context for the Intelligence tab's system prompt
  # (services/Ai.qml appends it while ai.includeSystemContext is on), plus the
  # niri keybinds when there are any. No secrets: it is a store path.
  systemContextFile =
    pkgs.runCommand "nixbook-shell-system-context.md"
      {
        header = cfg.assistant.context;
        niriKdl = cfg.assistant.niriConfig;
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
  # keys, modules, installed packages, settings). Built by
  # scripts/assistant-facts.py.
  systemFactsFile =
    let
      info = {
        host = if osConfig != null then osConfig.networking.hostName else "unknown";
        user = config.home.username;
        inherit (cfg.assistant) coreFacts modules;
        pinned = lib.genAttrs pinnedPaths (
          path: lib.attrByPath (lib.splitString "." path) null pinnedSettings
        );
        packages = names packages;
        # Every setting the shell has (answers naming another are flagged).
        settingPaths = settingsLib.flattenPaths [ ] settingsLib.builtinDefaults ++ settingsLib.liveKeys;
      };
    in
    pkgs.runCommand "nixbook-shell-system-facts.json"
      {
        info = builtins.toJSON info;
        niriKdl = cfg.assistant.niriConfig;
        passAsFile = [
          "info"
          "niriKdl"
        ];
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        ${lib.getExe pkgs.gawk} '/^binds \{/,/^\}/' "$niriKdlPath" \
          | ${lib.getExe pkgs.gnused} -E 's#/nix/store/[a-z0-9]{32}-[^/ "]*/bin/##g' > binds.kdl
        python3 ${./scripts/assistant-facts.py} "$infoPath" binds.kdl > "$out"
      '';

  # Four-language sentence, as scripts/assistant-facts.py expects.
  factType = lib.types.submodule {
    options = lib.genAttrs [ "en" "fr" "de" "vi" ] (lang: lib.mkOption { type = lib.types.str; });
  };
in
{
  options.programs.nixbook-shell = {
    enable = lib.mkEnableOption ''
      nixbook-shell, a Quickshell (QML) desktop shell (bar, dock, sidebars,
      launcher, notifications, lock screen, desktop widgets). It runs as the
      `nixbook-shell` user service, bound to `graphical-session.target`, under
      niri or Hyprland; bind keys to `nixbook-shell ipc call <target> <function>`
      to drive its panels'';

    package = lib.mkOption {
      type = lib.types.package;
      default = (import ./default.nix { inherit pkgs; }).package;
      defaultText = lib.literalExpression "(import ./nixbook-shell { inherit pkgs; }).package";
      description = ''
        The `nixbook-shell` launcher. Build it with your own quickshell pin
        through `import ./nixbook-shell { inherit pkgs quickshellSrc; }`.
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
        switch.

        The keys are typed options generated from the shell's built-in
        defaults (`builtin-defaults.json`), so a misspelt key fails
        evaluation. `nixbook-shell config diff` prints the settings changed
        from the menu as Nix lines; `nixbook-shell config pinned` lists the
        locked keys. Runtime state (wallpaper path, accent colour, avatar,
        preset metadata) has no option: the shell and its scripts own it.
      '';
    };

    cliphist.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run the cliphist store daemon the shell's clipboard history (search
        `clipboardToggle`) reads from. Turn it off if something else already
        runs `cliphist store`.
      '';
    };

    assistant = {
      context = lib.mkOption {
        type = lib.types.lines;
        default = ''
          ## Desktop shell: nixbook-shell
          The bar, dock, sidebars, launcher, notifications, lock screen and desktop
          widgets are nixbook-shell, a Quickshell (QML) shell configured by the Home
          Manager module `programs.nixbook-shell`. Its settings live in
          `~/.config/nixbook-shell/config.json` and are edited from its Settings
          window ("Shell settings" in the launcher). Settings set in Nix
          (`programs.nixbook-shell.settings`) are locked in that window; everything
          else is editable there. `nixbook-shell config diff` prints the settings
          changed from the menu as Nix lines, `nixbook-shell ipc call <target>
          <function>` drives panels.

          Settings set in Nix on this machine:
          ${cfg.assistant.pinnedLines}

          ## Packages installed (Home Manager${lib.optionalString (osConfig != null) " and NixOS"})
          ${lib.concatStringsSep ", " (names packages)}
        '';
        defaultText = lib.literalMD "a description of the shell, the settings set in Nix and the installed packages";
        description = ''
          Markdown appended to the AI chat's system prompt while
          `ai.includeSystemContext` is on: what the assistant should know about
          this machine and how its configuration is changed. The niri keybinds
          (`assistant.niriConfig`) are appended to it.
        '';
      };

      pinnedLines = lib.mkOption {
        type = lib.types.str;
        readOnly = true;
        internal = true;
        default = lib.concatStringsSep "\n" (
          map (
            path:
            "- `${path}` = `${builtins.toJSON (lib.attrByPath (lib.splitString "." path) null pinnedSettings)}`"
          ) pinnedPaths
        );
        description = "The settings set in Nix, one Markdown list item each (for `assistant.context`).";
      };

      coreFacts = lib.mkOption {
        type = lib.types.listOf factType;
        default = [
          {
            en = "Shell settings (bar, dock, widgets, notifications, theme) set in Nix are in programs.nixbook-shell.settings of the Home Manager configuration; the others are changed in the shell's Settings window.";
            fr = "Les réglages du shell (barre, dock, widgets, notifications, thème) définis dans Nix sont dans programs.nixbook-shell.settings de la configuration Home Manager ; les autres se changent dans la fenêtre des paramètres du shell.";
            de = "In Nix gesetzte Shell-Einstellungen (Leiste, Dock, Widgets, Benachrichtigungen, Design) stehen in programs.nixbook-shell.settings der Home-Manager-Konfiguration; die übrigen werden im Einstellungsfenster der Shell geändert.";
            vi = "Thiết lập shell (thanh, dock, widget, thông báo, giao diện) đặt trong Nix nằm ở programs.nixbook-shell.settings của cấu hình Home Manager; các thiết lập khác đổi trong cửa sổ cài đặt của shell.";
          }
        ];
        description = ''
          Core statements for the config assistant (no AI), in English, French,
          German and Vietnamese: where and how this machine's configuration is
          changed and applied.
        '';
      };

      modules = {
        all = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Configuration modules the config assistant knows of.";
        };
        enabled = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "The enabled ones among `modules.all`.";
        };
      };

      niriConfig = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = lib.literalExpression "config.programs.niri.finalConfig";
        description = ''
          The rendered niri configuration (KDL): its `binds { … }` block
          becomes keybind facts and is appended to the AI context. Empty: no
          keybinds.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile."quickshell/${configName}".source = cfg.package.passthru.shell;

    # The manifest the shell reads to know which settings Nix owns: every
    # pinned leaf path. Drives the red lock icon and the disabled control in
    # the Settings menu (src/modules/common/NixManaged.qml).
    xdg.configFile."nixbook-shell/nix-managed.json".source = nixManagedFile;
    # ...and their values: NixManaged.qml restores any pinned key that gets
    # changed at runtime (menu, QuickConfig, IPC, scripts); `nixbook-shell config`
    # reads them too.
    xdg.configFile."nixbook-shell/nix-pinned-values.json".source = pinnedFile;
    # Machine context for the AI assistant (see above).
    xdg.configFile."nixbook-shell/system-context.md".source = systemContextFile;
    xdg.configFile."nixbook-shell/system-facts.json".source = systemFactsFile;

    # Launcher entry for the Settings window (nixbook-shell's own launcher, fuzzel…).
    xdg.desktopEntries.nixbook-shell-settings = {
      name = "Shell settings";
      genericName = "Desktop shell settings";
      comment = "Settings of the nixbook-shell desktop shell (bar, dock, widgets, theme…)";
      exec = "${lib.getExe cfg.package} ipc call settings open";
      icon = "preferences-desktop";
      terminal = false;
      categories = [
        "Settings"
        "DesktopSettings"
      ];
      settings.Keywords = "settings;preferences;shell;nixbook;bar;dock;theme;wallpaper;persona;";
    };

    home.packages = [
      cfg.package
      cfg.package.passthru.quickshell
      # Condensed display face used by the optional Persona style
      # (appearance.persona.fonts) for titles and numbers.
      pkgs.oswald
    ];

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
          ${lib.getExe cfg.package} ipc call nixManaged reload >/dev/null 2>&1 || true
      fi
    '';

    systemd.user.services.nixbook-shell = {
      Unit = {
        Description = "nixbook-shell Quickshell desktop shell";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = lib.getExe cfg.package;
        Restart = "on-failure";
        RestartSec = 2;
        Slice = "app.slice";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.cliphist = lib.mkIf cfg.cliphist.enable {
      Unit = {
        Description = "Clipboard history store for nixbook-shell (cliphist)";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${cfg.package.passthru.cliphistWatch}";
        Restart = "on-failure";
        RestartSec = 2;
        Slice = "background.slice";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
