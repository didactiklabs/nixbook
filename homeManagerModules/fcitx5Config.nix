{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.fcitx5Config;
in
{
  options.customHomeManagerModules.fcitx5Config = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Fcitx5 input method framework with Japanese support.

        Fcitx5 is a modern input method framework for CJK (Chinese, Japanese,
        Korean) and other complex scripts on Linux.

        This configuration:
          - Input method type: fcitx5 with Wayland frontend
          - Addons: fcitx5-mozc-ut (Japanese IME with extended dictionary),
            fcitx5-gtk (GTK integration for application compatibility)
          - Input group "Default":
              Item 0: keyboard-us  (English/US layout, default)
              Item 1: mozc         (Japanese input, toggled via Ctrl+Space)

          Environment variables set:
            - QT_IM_MODULE=fcitx   — Qt application input method
            - XMODIFIERS=@im=fcitx — X11 input method (for XWayland apps)
            - INPUT_METHOD=fcitx   — generic fallback

        Used on: totoro, nishinoya (machines with Japanese input needs).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    i18n.inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5 = {
        addons = with pkgs; [
          fcitx5-mozc-ut
          fcitx5-gtk
        ];
        waylandFrontend = true;
        settings = {
          inputMethod = {
            GroupOrder."0" = "Default";
            "Groups/0" = {
              Name = "Default";
              "Default Layout" = "us";
              DefaultIM = "keyboard-us";
            };
            "Groups/0/Items/0".Name = "keyboard-us";
            "Groups/0/Items/1".Name = "mozc";
          };
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
