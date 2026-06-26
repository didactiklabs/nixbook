{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.fcitx5Config;

  # fcitx5 addon for German umlaut input via hold-letter + Space gesture.
  schnelle-umlaute = import ../customPkgs/schnelle-umlaute.nix { inherit pkgs; };

  # Vietnamese input method addon (needs the system-level NixOS module
  # customNixOSModules.fcitx5-lotus for its uinput server).
  fcitx5-lotus = import ../customPkgs/fcitx5-lotus.nix { inherit pkgs; };

  # Build the numbered "Groups/0/Items/N" attrset from the ordered list of
  # input-method engine names (e.g. [ "keyboard-us" "keyboard-de" "unikey" ]).
  itemsAttrs = lib.listToAttrs (
    lib.imap0 (i: name: {
      name = "Groups/0/Items/${toString i}";
      value.Name = name;
    }) cfg.inputMethods
  );
in
{
  options.customHomeManagerModules.fcitx5Config = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Fcitx5 input method framework.

        Fcitx5 is a modern input method framework for CJK (Chinese, Japanese,
        Korean), Vietnamese and other complex scripts on Linux.

        This configuration:
          - Input method type: fcitx5 with Wayland frontend
          - Addons and input methods are configurable via the `addons`,
            `inputMethods`, `defaultLayout` and `defaultIM` options below.

          Environment variables set:
            - QT_IM_MODULE=fcitx   — Qt application input method
            - XMODIFIERS=@im=fcitx — X11 input method (for XWayland apps)
            - INPUT_METHOD=fcitx   — generic fallback

        Switch input methods at runtime with Ctrl+Space. The trigger key
        cycles forward through all input methods in the group (not just the
        last two), via globalOptions.Hotkey.EnumerateWithTriggerKeys.

        Used on: totoro, nishinoya (Japanese), hanamichi (German + Vietnamese).
      '';
    };

    addons = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        fcitx5-mozc-ut
        fcitx5-gtk
      ];
      defaultText = lib.literalExpression "with pkgs; [ fcitx5-mozc-ut fcitx5-gtk ]";
      description = ''
        Fcitx5 addon packages to install (IME engines and integrations).
        Defaults to the Japanese Mozc engine plus GTK integration.
      '';
    };

    inputMethods = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "keyboard-us"
        "mozc"
      ];
      description = ''
        Ordered list of fcitx5 input-method engine names making up the
        "Default" input group. The first entry is used as the active default.

        Common values:
          - "keyboard-us"  US/English XKB layout
          - "keyboard-de"  German XKB layout
          - "keyboard-fr"  French XKB layout
          - "mozc"         Japanese
          - "unikey"       Vietnamese (Telex/VNI)
      '';
    };

    defaultLayout = lib.mkOption {
      type = lib.types.str;
      default = "us";
      description = "XKB layout used as the group's default layout.";
    };

    defaultIM = lib.mkOption {
      type = lib.types.str;
      default = "keyboard-us";
      description = ''
        Name of the input method activated by default (should be one of the
        entries in `inputMethods`).
      '';
    };

    schnelleUmlaute = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to install the "Schnelle Umlaute" fcitx5 addon, which types
        umlauts and eszett with a hold-letter + Space gesture, Telex-style:

          hold a + Space → ä    hold o + Space → ö
          hold u + Space → ü    hold s + Space → ß
          (Shift+letter + Space → uppercase Ä/Ö/Ü)

        Releasing the key without Space types the normal letter, so ordinary
        typing is unaffected.

        Mappings/leader keys can be tweaked with the bundled
        `schnelle-umlaute-editor` GUI.

        https://github.com/Maik-0000FF/schnelle-umlaute
      '';
    };

    lotus = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to add the Fcitx5 Lotus Vietnamese input method addon.

        When enabled, the Lotus addon is appended to `addons`; add "lotus" to
        `inputMethods` to put it in the switch cycle.

        IMPORTANT: Lotus also needs system-level support (a uinput server,
        udev rule and per-user service). Enable the matching NixOS module on
        the host: customNixOSModules.fcitx5-lotus = {
          enable = true; users = [ "<username>" ];
        };

        https://github.com/LotusInputMethod/fcitx5-lotus
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    i18n.inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5 = {
        addons =
          cfg.addons
          ++ lib.optional cfg.schnelleUmlaute schnelle-umlaute
          ++ lib.optional cfg.lotus fcitx5-lotus;
        waylandFrontend = true;
        settings = {
          # Make Ctrl+Space cycle forward through *all* input methods in the
          # group on each press, instead of only toggling between the last two.
          #
          # The default trigger key (Ctrl+Space) only switches between the two
          # most-recently-used IMs. We instead bind Ctrl+Space directly to the
          # "enumerate forward" action, which advances to the next IM each
          # press and wraps around. EnumerateSkipFirst=false keeps the first
          # IM (the default layout) in the cycle.
          #
          # fcitx5 stores key lists as indexed subsections, so these are
          # written as e.g. `[Hotkey/EnumerateForwardKeys]` with `0=...`.
          globalOptions = {
            "Hotkey" = {
              EnumerateWithTriggerKeys = true;
              EnumerateSkipFirst = false;
            };
            "Hotkey/EnumerateForwardKeys"."0" = "Control+space";
            "Hotkey/EnumerateBackwardKeys"."0" = "Control+Shift+space";
          };
          inputMethod = {
            GroupOrder."0" = "Default";
            "Groups/0" = {
              Name = "Default";
              "Default Layout" = cfg.defaultLayout;
              DefaultIM = cfg.defaultIM;
            };
          }
          // itemsAttrs;
        };
      };
    };

    # Set environment variables for input method
    home.sessionVariables = {
      QT_IM_MODULE = "fcitx";
      XMODIFIERS = "@im=fcitx";
      INPUT_METHOD = "fcitx";
    };
  };
}
