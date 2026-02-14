{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  notification_audio = "${config.profileCustomization.notification_audio}";
  soundNotification = pkgs.writeShellScriptBin "soundNotification" ''
    if [ $(${pkgs.swaynotificationcenter}/bin/swaync-client -D) == 'false' ]; then
      ${pkgs.mpg123}/bin/mpg123 ${notification_audio};
    fi
  '';
in
{
  options.customHomeManagerModules.swayncConfig = {
    enable = lib.mkEnableOption "swaync configuration";
  };

  config = lib.mkIf cfg.swayncConfig.enable {
    services.swaync = {
      enable = true;
      # The `style` attribute is added here
      style = ''
        /* --- General --- */
        * {
            font-family: Inter Display, sans-serif;
            font-size: 14px;
            color: #${config.stylix.base16Scheme.base05};
        }

        /* --- Main Windows --- */
        .control-center, .notification-window {
            background-color: alpha(#${config.stylix.base16Scheme.base00}, 0.8);
            border: 1px solid #${config.stylix.base16Scheme.base03};
            border-radius: 12px;
        }

        .control-center {
            padding: 10px;
        }

        /* --- Header & Title --- */
        .widget-title {
            font-size: 1.2rem;
            font-weight: bold;
            margin: 10px;
            color: #${config.stylix.base16Scheme.base0D};
        }

        /* --- Buttons --- */
        button {
            background-color: #${config.stylix.base16Scheme.base01};
            border: 1px solid #${config.stylix.base16Scheme.base02};
            border-radius: 8px;
            padding: 8px;
            margin: 5px;
            transition: all 0.2s ease-in-out;
        }

        button:hover {
            background-color: #${config.stylix.base16Scheme.base02};
            border-color: #${config.stylix.base16Scheme.base0D};
        }

        .notification-action-buttons button {
             background-color: #${config.stylix.base16Scheme.base0B};
             color: #${config.stylix.base16Scheme.base00};
        }

        .notification-action-buttons button:hover {
             background-color: alpha(#${config.stylix.base16Scheme.base0B}, 0.8);
        }

        /* --- Notifications --- */
        .notification {
            background-color: #${config.stylix.base16Scheme.base01};
            border-radius: 10px;
            padding: 10px;
            margin: 10px;
        }

        .notification-content {
            padding: 5px;
        }

        .app-name {
            font-weight: bold;
            color: #${config.stylix.base16Scheme.base0E};
        }

        .summary {
           font-weight: bold;
        }

        .time {
            color: #${config.stylix.base16Scheme.base04};
        }

        .notification.critical {
            background-color: alpha(#${config.stylix.base16Scheme.base08}, 0.4);
            border: 1px solid #${config.stylix.base16Scheme.base08};
        }

        /* --- Widgets (Volume, Backlight) --- */
        .widget-slider {
            background-color: #${config.stylix.base16Scheme.base01};
            border-radius: 8px;
            padding: 15px;
            margin: 10px;
        }

        .widget-slider label {
            font-size: 1.5rem;
            margin-right: 10px;
        }

        scale trough {
            background-color: #${config.stylix.base16Scheme.base02};
            border-radius: 5px;
            min-height: 10px;
        }

        scale highlight {
            background-color: #${config.stylix.base16Scheme.base0D};
            border-radius: 5px;
        }

        /* --- Do Not Disturb & Clear All --- */
        .widget-dnd, .widget-clear-all {
            margin: 10px;
        }

        /* --- MPRIS (Music Player) --- */
        .widget-mpris {
            background-color: #${config.stylix.base16Scheme.base01};
            border-radius: 8px;
            padding: 15px;
            margin: 10px;
        }
      '';
      settings = {
        scripts = {
          sound = {
            exec = "${soundNotification}/bin/soundNotification";
            app-name = ".*";
          };
        };
        positionX = "right";
        positionY = "top";
        control-center-margin-top = 10;
        control-center-margin-bottom = 10;
        control-center-margin-right = 10;
        control-center-margin-left = 10;
        notification-icon-size = 48;
        notification-body-image-height = 70;
        notification-body-image-width = 150;
        timeout = 3;
        timeout-low = 2;
        timeout-critical = 0;
        fit-to-screen = true;
        control-center-width = 500;
        control-center-height = 800;
        notification-window-width = 500;
        keyboard-shortcuts = true;
        image-visibility = "when-available";
        transition-time = 100;
        hide-on-clear = false;
        hide-on-action = true;
        script-fail-notify = true;
        widgets = [
          "title"
          "mpris"
          "volume"
          "backlight"
          "dnd"
          "notifications"
        ];
        widget-config = {
          title = {
            text = "Notification Center";
            clear-all-button = true;
            button-text = "󰆴 Clear All";
          };
          dnd = {
            text = "Do Not Disturb";
          };
          label = {
            max-lines = 1;
            text = "Notification Center";
          };
          mpris = {
            image-size = 96;
            image-radius = 12; # Match the border-radius
          };
          volume = {
            label = "󰕾";
          };
          backlight = {
            label = "󰃟";
          };
        };
      };
    };
  };
}
