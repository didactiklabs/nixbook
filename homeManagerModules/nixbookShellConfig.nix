{
  config,
  pkgs,
  lib,
  osConfig ? null,
  ...
}:
# nixbook's side of nixbook-shell (nixbook-shell/, a self-contained package +
# Home Manager module `programs.nixbook-shell`): the nixbookShellConfig toggle,
# the settings shared by every nixbook machine, the repository's quickshell
# pin, and the machine context (hosts, modules, colmena) for the shell's
# assistants.
let
  cfg = config.customHomeManagerModules.nixbookShellConfig;
  sources = import ../npins;

  os = osConfig;
  hostName = if os != null then os.networking.hostName else "unknown";
  user = config.home.username;
  enabledIn =
    set:
    lib.sort lib.lessThan (
      lib.attrNames (lib.filterAttrs (_: v: builtins.isAttrs v && (v.enable or false) == true) set)
    );
  declared = set: lib.sort lib.lessThan (lib.attrNames set);
  names = pkgList: lib.unique (lib.sort lib.lessThan (map lib.getName pkgList));
  osModules = if os != null then enabledIn (os.customNixOSModules or { }) else [ ];
  hmModules = enabledIn (config.customHomeManagerModules or { });
  niriEnabled = config.customHomeManagerModules.niriConfig.enable or false;

  # What this machine's Nix configuration sets up, for the Intelligence tab's
  # system prompt: the assistant can then answer "how do I change X" with the
  # right module, profile file and deploy command. Built from the evaluated
  # configuration, so it follows every switch.
  context = ''
    ## This machine (generated from its Nix configuration)
    You are also this user's assistant for their NixOS setup. It is fully
    declarative: the "nixbook" repository (git@github.com:didactiklabs/nixbook,
    revision in /etc/nixos/version) builds every machine. When asked to change
    something, prefer the Nix change in the right file, applied with
    `colmena apply-local --sudo switch` from the repository: imperative
    changes (nix-env, editing /etc…) to things the configuration manages are
    undone by the next switch.

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
    `nixbook-shell/` (source in `src/`, Home Manager module
    `programs.nixbook-shell` in `hm-module.nix`) and configured by
    `customHomeManagerModules.nixbookShellConfig`
    (`homeManagerModules/nixbookShellConfig.nix`). Its settings live in
    `~/.config/nixbook-shell/config.json` and are edited from its Settings
    window (Mod+Escape, or "Shell settings" in the launcher). Settings set in
    Nix (shared ones in `homeManagerModules/nixbookShellConfig/settings.nix`,
    per machine in `nixbookShellConfig.settings` of the user profile) are
    locked in that window; everything else is editable there.
    `nixbook-shell config diff` prints the settings changed from the menu as
    Nix lines, `nixbook-shell ipc call <target> <function>` drives panels.

    Settings set in Nix on this machine:
    ${config.programs.nixbook-shell.assistant.pinnedLines}

    ## Packages installed for this user (Home Manager)
    ${lib.concatStringsSep ", " (names config.home.packages)}
    ${lib.optionalString (os != null) ''

      ## System packages (NixOS)
      ${lib.concatStringsSep ", " (names os.environment.systemPackages)}
    ''}
  '';
in
{
  imports = [
    ../nixbook-shell/hm-module.nix
    # Profiles set the shell's settings as nixbookShellConfig.settings.
    (lib.mkAliasOptionModule
      [ "customHomeManagerModules" "nixbookShellConfig" "settings" ]
      [ "programs" "nixbook-shell" "settings" ]
    )
  ];

  options.customHomeManagerModules.nixbookShellConfig.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Whether to enable nixbook-shell, nixbook's Quickshell (QML) desktop shell
      (`programs.nixbook-shell`, packaged in nixbook-shell/), with the settings
      shared by every nixbook machine (nixbookShellConfig/settings.nix, as
      defaults a profile's `nixbookShellConfig.settings` override key by key).

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

  config = lib.mkIf cfg.enable {
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

    programs.nixbook-shell = {
      enable = true;
      # The repository's quickshell pin, shared with dmsConfig.nix so the two
      # shells never disagree on the QML runtime.
      package =
        (import ../nixbook-shell {
          inherit pkgs;
          quickshellSrc = sources.quickshell;
          # DankCalendar (the shell's calendar and task sync), the same pin
          # as dmsConfig's.
          dankcalendarSrc = sources.dankcalendar;
          flakeCompatSrc = sources.flake-compat;
        }).package;
      # Shared settings, as defaults so a profile's `settings` win key by key.
      settings = lib.mapAttrsRecursive (_: lib.mkDefault) (import ./nixbookShellConfig/settings.nix);

      # Qt apps can follow the palette the shell shows (the wallpaper's or the
      # theme variant's) instead of stylix's (stylixConfig.nix turns its qt and
      # zen-browser targets off for this). Which apps do (Qt/KDE, Vesktop,
      # Zen) is switched in the shell: Settings > Appearance > Color
      # generation > Apps.
      appTheming.qt.enable = true;

      assistant = {
        inherit context;
        niriConfig = if niriEnabled then (config.programs.niri.finalConfig or "") else "";
        modules = {
          all =
            lib.optionals (os != null) (declared (os.customNixOSModules or { }))
            ++ declared (config.customHomeManagerModules or { });
          enabled = osModules ++ hmModules;
        };
        # nixbook's own way of applying and updating (the other how-tos keep
        # nixbook-shell's generic NixOS answers).
        howTo = {
          apply = {
            en = "To apply a configuration change, run `colmena apply-local --sudo switch` from the nixbook repository.";
            fr = "Pour appliquer une modification de la configuration, lancez `colmena apply-local --sudo switch` depuis le dépôt nixbook.";
            de = "Um eine Konfigurationsänderung anzuwenden, führe `colmena apply-local --sudo switch` im nixbook-Repository aus.";
            vi = "Để áp dụng thay đổi cấu hình, chạy `colmena apply-local --sudo switch` trong kho nixbook.";
          };
          update = lib.mkIf (os != null && (os.customNixOSModules.tools.enable or false)) {
            en = "To update the system, run `osupdate`: it applies the latest nixbook main branch (git@github.com:didactiklabs/nixbook).";
            fr = "Pour mettre à jour le système, lancez `osupdate` : il applique la dernière version de la branche main de nixbook (git@github.com:didactiklabs/nixbook).";
            de = "Um das System zu aktualisieren, führe `osupdate` aus: es wendet den neuesten Stand des nixbook-Branches main an (git@github.com:didactiklabs/nixbook).";
            vi = "Để cập nhật hệ thống, chạy `osupdate`: nó áp dụng bản mới nhất của nhánh main của nixbook (git@github.com:didactiklabs/nixbook).";
          };
        };
        coreFacts = [
          {
            en = "System settings (NixOS modules and their options) are changed in profiles/${hostName}/default.nix.";
            fr = "Les réglages système (modules NixOS et leurs options) se changent dans profiles/${hostName}/default.nix.";
            de = "Systemeinstellungen (NixOS-Module und ihre Optionen) werden in profiles/${hostName}/default.nix geändert.";
            vi = "Thiết lập hệ thống (module NixOS và tùy chọn) được đổi trong profiles/${hostName}/default.nix.";
          }
          {
            en = "This user's Home Manager modules and their options are changed in profiles/${hostName}/${user}/default.nix.";
            fr = "Les modules Home Manager de cet utilisateur et leurs options se changent dans profiles/${hostName}/${user}/default.nix.";
            de = "Die Home-Manager-Module dieses Benutzers und ihre Optionen werden in profiles/${hostName}/${user}/default.nix geändert.";
            vi = "Module Home Manager của người dùng này và tùy chọn được đổi trong profiles/${hostName}/${user}/default.nix.";
          }
          {
            en = "Shell settings (bar, dock, widgets, notifications, theme) set in Nix are in homeManagerModules/nixbookShellConfig/settings.nix (shared) or nixbookShellConfig.settings in the user profile; the others are changed in the shell's Settings window.";
            fr = "Les réglages du shell (barre, dock, widgets, notifications, thème) définis dans Nix sont dans homeManagerModules/nixbookShellConfig/settings.nix (communs) ou nixbookShellConfig.settings dans le profil utilisateur ; les autres se changent dans la fenêtre des paramètres du shell.";
            de = "In Nix gesetzte Shell-Einstellungen (Leiste, Dock, Widgets, Benachrichtigungen, Design) stehen in homeManagerModules/nixbookShellConfig/settings.nix (gemeinsam) oder nixbookShellConfig.settings im Benutzerprofil; die übrigen werden im Einstellungsfenster der Shell geändert.";
            vi = "Thiết lập shell (thanh, dock, widget, thông báo, giao diện) đặt trong Nix nằm ở homeManagerModules/nixbookShellConfig/settings.nix (dùng chung) hoặc nixbookShellConfig.settings trong hồ sơ người dùng; các thiết lập khác đổi trong cửa sổ cài đặt của shell.";
          }
          {
            en = "The keyboard shortcuts are documented in KEYBINDS.md in the nixbook repository.";
            fr = "Les raccourcis clavier sont documentés dans KEYBINDS.md dans le dépôt nixbook.";
            de = "Die Tastenkürzel sind in KEYBINDS.md im nixbook-Repository dokumentiert.";
            vi = "Các phím tắt được ghi trong KEYBINDS.md của kho nixbook.";
          }
        ];
      };
    };
  };
}
