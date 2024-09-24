{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  betterTransition = "all 0.3s cubic-bezier(.55,-0.68,.48,1.682)";
  rofi-wayland = "${pkgs.rofi-wayland}/bin/rofi";
  rofiLauncherType = "${cfg.rofiConfig.launcher.type}";
  rofiLauncherStyle = "${cfg.rofiConfig.launcher.style}";
  rofiPowermenuStyle = "${cfg.rofiConfig.powermenu.style}";
in
{
  options.customHomeManagerModules.waybar = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable waybar config globally or not
      '';
    };
  };

  config = lib.mkIf cfg.waybar.enable {
    programs.waybar = {
      enable = true;
      package = pkgs.waybar;
      settings = [
        {
          layer = "top";
          position = "top";
          modules-center = [
            "hyprland/workspaces"
            "sway/workspaces"
          ];
          modules-left = [
            "custom/startmenu"
            "hyprland/window"
            "pulseaudio"
            "backlight"
            "custom/spotify"
            "idle_inhibitor"
          ];
          modules-right = [
            #"custom/hyprbindings"
            "cpu"
            "memory"
            "battery"
            "tray"
            "custom/notification"
            "custom/exit"
            "clock"
          ];

          "hyprland/workspaces" = {
            format = "{name}";
            format-icons = {
              default = " ";
              active = " ";
              urgent = " ";
            };
            on-scroll-up = "hyprctl dispatch workspace e+1";
            on-scroll-down = "hyprctl dispatch workspace e-1";
          };
          "sway/workspaces" = {
            format = "{name}";
            format-icons = {
              default = " ";
              active = " ";
              urgent = " ";
            };
            # on-scroll-up = "hyprctl dispatch workspace e+1";
            # on-scroll-down = "hyprctl dispatch workspace e-1";
          };

          "clock" = {
            format = " {:L%H:%M}";
            tooltip = true;
            tooltip-format = ''
              <big>{:%A, %d.%B %Y }</big>
              <tt><small>{calendar}</small></tt>'';
          };
          "hyprland/window" = {
            max-length = 22;
            separate-outputs = false;
            rewrite = {
              "" = " 🙈 No Windows? ";
            };
          };
          "memory" = {
            interval = 5;
            format = " {}%";
            tooltip = true;
          };
          "cpu" = {
            interval = 5;
            format = " {usage:2}%";
            tooltip = true;
          };
          "disk" = {
            format = " {free}";
            tooltip = true;
          };
          "network" = {
            format-icons = [
              "󰤯"
              "󰤟"
              "󰤢"
              "󰤥"
              "󰤨"
            ];
            format-ethernet = " {bandwidthDownOctets}";
            format-wifi = "{icon} {signalStrength}%";
            format-disconnected = "󰤮";
            tooltip = false;
          };
          "tray" = {
            spacing = 12;
          };
          "backlight" = {
            "device" = "intel_backlight";
            "format" = "{percent}% {icon}";
            "format-icons" = [
              ""
              ""
            ];
          };
          "pulseaudio" = {
            format = "{icon} {volume}% {format_source}";
            format-bluetooth = "{volume}% {icon} {format_source}";
            format-bluetooth-muted = " {icon} {format_source}";
            format-muted = " {format_source}";
            format-source = " {volume}%";
            format-source-muted = "";
            format-icons = {
              headphone = "";
              hands-free = "";
              headset = "";
              phone = "";
              portable = "";
              car = "";
              default = [
                ""
                ""
                ""
              ];
            };
            on-click = "sleep 0.1 && ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_SINK@ toggle";
            on-click-middle = "${pkgs.pavucontrol}/bin/pavucontrol";
          };
          "custom/exit" = {
            tooltip = false;
            format = "";
            on-click = lib.mkIf cfg.rofiConfig.enable "sleep 0.1 && $HOME/.config/rofiScripts/rofiLockScript.sh ${rofiPowermenuStyle}";
          };
          "custom/startmenu" = {
            tooltip = false;
            format = "";
            # exec = "rofi -show drun";
            on-click = lib.mkIf cfg.rofiConfig.enable "sleep 0.1 && ${rofi-wayland} -show drun -theme $HOME/.config/rofi/launchers/${rofiLauncherType}/${rofiLauncherStyle}.rasi";
          };
          "custom/hyprbindings" = {
            tooltip = false;
            format = "󱕴";
            on-click = "sleep 0.1 && list-hypr-bindings";
          };
          "idle_inhibitor" = {
            format = "{icon}";
            format-icons = {
              activated = "";
              deactivated = "";
            };
            tooltip = "true";
          };
          "custom/spotify" = {
            exec = ''
              ${pkgs.playerctl}/bin/playerctl --player=spotify metadata --format '{ "alt": "{{ status }}", "class": "{{ status }}", "text": "{{ artist }} - {{ title }}", "tooltip": "{{ artist }} - {{ title }}" }'  2> /dev/null
            '';
            return-type = "json";
            exec-if = "${pkgs.procps}/bin/pgrep spotify";
            format = "<span> :</span>{icon} {}";
            format-icons = {
              Playing = "";
              Paused = "";
            };
            max-length = 55;
            interval = 5;
            tooltip = false;
            on-click = "${pkgs.playerctl}/bin/playerctl --player=spotify previous";
            on-click-middle = "${pkgs.playerctl}/bin/playerctl --player=spotify play-pause";
            on-click-right = "${pkgs.playerctl}/bin/playerctl --player=spotify next";
          };
          "custom/notification" = {
            tooltip = false;
            format = "{icon} {}";
            format-icons = {
              notification = "<span foreground='red'><sup></sup></span>";
              none = "";
              dnd-notification = "<span foreground='red'><sup></sup></span>";
              dnd-none = "";
              inhibited-notification = "<span foreground='red'><sup></sup></span>";
              inhibited-none = "";
              dnd-inhibited-notification = "<span foreground='red'><sup></sup></span>";
              dnd-inhibited-none = "";
            };
            return-type = "json";
            exec-if = "which swaync-client";
            exec = "swaync-client -swb";
            on-click = "sleep 0.1 && ${pkgs.swaynotificationcenter}/bin/swaync-client -t &";
            escape = true;
          };
          "battery" = {
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{icon} {capacity}%";
            format-charging = "󰂄 {capacity}%";
            format-plugged = "󱘖 {capacity}%";
            format-icons = [
              "󰁺"
              "󰁻"
              "󰁼"
              "󰁽"
              "󰁾"
              "󰁿"
              "󰂀"
              "󰂁"
              "󰂂"
              "󰁹"
            ];
            tooltip = false;
          };
        }
      ];
      style = lib.concatStrings [
        ''
          * {
            font-family: Hack Nerd Font;
            font-size: 8px;
            font-weight: bold;
            border-radius: 0px;
            border: none;
            min-height: 0px;
          }
          window#waybar {
            background: rgba(0,0,0,0);
          }
          #workspaces {
            color: #${config.stylix.base16Scheme.base00};
            background: #${config.stylix.base16Scheme.base01};
            margin: 4px 4px;
            padding: 5px 5px;
            border-radius: 16px;
          }
          #workspaces button {
            font-weight: bold;
            padding: 0px 5px;
            margin: 0px 3px;
            border-radius: 16px;
            color: #${config.stylix.base16Scheme.base00};
            background: linear-gradient(45deg, #${config.stylix.base16Scheme.base08}, #${config.stylix.base16Scheme.base0D});
            opacity: 0.5;
            transition: ${betterTransition};
          }
          #workspaces button.active {
            font-weight: bold;
            padding: 0px 5px;
            margin: 0px 3px;
            border-radius: 16px;
            color: #${config.stylix.base16Scheme.base00};
            background: linear-gradient(45deg, #${config.stylix.base16Scheme.base08}, #${config.stylix.base16Scheme.base0D});
            transition: ${betterTransition};
            opacity: 1.0;
            min-width: 40px;
          }
          #workspaces button:hover {
            font-weight: bold;
            border-radius: 16px;
            color: #${config.stylix.base16Scheme.base00};
            background: linear-gradient(45deg, #${config.stylix.base16Scheme.base08}, #${config.stylix.base16Scheme.base0D});
            opacity: 0.8;
            transition: ${betterTransition};
          }
          tooltip {
            background: #${config.stylix.base16Scheme.base00};
            border: 1px solid #${config.stylix.base16Scheme.base08};
            border-radius: 12px;
          }
          tooltip label {
            color: #${config.stylix.base16Scheme.base08};
          }
          #window, #pulseaudio, #backlight, #idle_inhibitor {
            font-weight: bold;
            margin: 4px 0px;
            margin-left: 7px;
            padding: 0px 18px;
            background: #${config.stylix.base16Scheme.base04};
            color: #${config.stylix.base16Scheme.base00};
            border-radius: 24px 10px 24px 10px;
          }
          #custom-spotify {
            font-weight: bold;
            margin: 4px 0px;
            margin-left: 7px;
            padding: 0px 18px;
            background: #${config.stylix.base16Scheme.base04};
            border-radius: 24px 10px 24px 10px;
          }
          #custom-spotify.Playing {
            background: #77DD77;
            color: #FFFFFF;
          }
          #custom-spotify:hover, #pulseaudio:hover, #idle_inhibitor:hover, #custom-startmenu:hover,
          #custom-notification:hover, #custom-exit:hover, #custom-hyprbindings:hover{
            transition: ${betterTransition};
            opacity: 0.8;
          }
          #custom-spotify.Paused {
            background: #FF6961;
            color: #FFFFFF;
          }
          #custom-startmenu {
            color: #${config.stylix.base16Scheme.base0B};
            background: #${config.stylix.base16Scheme.base02};
            font-size: 28px;
            margin: 0px;
            padding: 0px 30px 0px 15px;
            border-radius: 0px 0px 40px 0px;
          }
          #custom-hyprbindings, #network, #battery,
          #custom-notification, #tray, #custom-exit, #cpu, #memory {
            font-weight: bold;
            background: #${config.stylix.base16Scheme.base0F};
            color: #${config.stylix.base16Scheme.base00};
            margin: 4px 0px;
            margin-right: 7px;
            border-radius: 10px 24px 10px 24px;
            padding: 0px 18px;
          }
          #clock {
            font-weight: bold;
            color: #0D0E15;
            background: linear-gradient(90deg, #${config.stylix.base16Scheme.base0E}, #${config.stylix.base16Scheme.base0C});
            margin: 0px;
            padding: 0px 15px 0px 30px;
            border-radius: 0px 0px 0px 40px;
          }
        ''
      ];
    };
  };
}
