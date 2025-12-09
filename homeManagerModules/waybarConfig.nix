{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  betterTransition = "all 0.3s cubic-bezier(.55,-0.68,.48,1.682)";
  rofi = "${pkgs.rofi}/bin/rofi";
  playerctl = "${pkgs.playerctl}/bin/playerctl";

  # Helper script to show a Play or Pause icon based on Spotify's status
  spotify-playpause = pkgs.writeShellScriptBin "spotify-playpause" ''
    #!/bin/sh
    STATUS=$(${playerctl} --player=spotify status 2>/dev/null)
    if [ "$STATUS" = "Playing" ]; then
        printf '{"text": "", "tooltip": "Pause"}'
    else
        printf '{"text": "", "tooltip": "Play"}'
    fi
  '';

  # Helper script to show song info and a text-based equalizer
  spotify-info = pkgs.writeShellScriptBin "spotify-info" ''
    #!/bin/sh
    STATUS=$(${playerctl} --player=spotify status 2>/dev/null)
    if [ "$STATUS" = "Playing" ]; then
        ARTIST=$(${playerctl} --player=spotify metadata artist)
        ARTIST_CLEANED=$(playerctl --player=spotify metadata artist | tr '[:punct:]' '-')
        TITLE=$(${playerctl} --player=spotify metadata title)
        TITLE_CLEANED=$(playerctl --player=spotify metadata title | tr '[:punct:]' '-')
        printf '{"text": "%s - %s", "class": "playing", "tooltip": "%s - %s"}' "$ARTIST_CLEANED" "$TITLE_CLEANED" "$ARTIST_CLEANED" "$TITLE_CLEANED"
    elif [ "$STATUS" = "Paused" ]; then
        printf '{"text": "Paused", "class": "paused", "tooltip": "Music Paused"}'
    else
        printf '{"text": "Offline", "class": "stopped", "tooltip": "Spotify is not running"}'
    fi
  '';

  # Niri vertical position script
  niri-vertical = pkgs.writeShellScriptBin "niri-vertical" ''
    #!/bin/sh
    export PATH="$PATH:${lib.makeBinPath [ pkgs.jq ]}"

    # Get current output from environment or parameter
    OUTPUT="$1"
    if [ -z "$OUTPUT" ]; then
        OUTPUT=$(echo "$WAYBAR_OUTPUT_NAME")
    fi

    # Get workspaces for this output
    WORKSPACES=$(niri msg -j workspaces 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$WORKSPACES" ]; then
        printf '{"text": "?", "tooltip": "Niri not available"}'
        exit 0
    fi

    # Get workspace info for this output
    OUTPUT_WORKSPACES=$(echo "$WORKSPACES" | jq -r --arg output "$OUTPUT" '
      [.[] | select(.output == $output)] | sort_by(.idx)
    ')

    CURRENT_WS=$(echo "$OUTPUT_WORKSPACES" | jq -r '.[] | select(.is_active == true) | .idx')
    TOTAL_WS=$(echo "$OUTPUT_WORKSPACES" | jq -r 'length')

    if [ -z "$CURRENT_WS" ] || [ "$CURRENT_WS" = "null" ]; then
        printf '{"text": "?", "tooltip": "No active workspace"}'
        exit 0
    fi

    # Calculate position in workspace list
    POSITION=$(echo "$OUTPUT_WORKSPACES" | jq -r --arg current "$CURRENT_WS" '
      [.[] | .idx] | to_entries | .[] | select(.value == ($current | tonumber)) | .key + 1
    ')

    HAS_UP=false
    HAS_DOWN=false

    if [ "$POSITION" -gt 1 ]; then
        HAS_UP=true
    fi
    if [ "$POSITION" -lt "$TOTAL_WS" ]; then
        HAS_DOWN=true
    fi

    # Create display text with vertical layout
    TEXT=""
    if [ "$HAS_UP" = "true" ]; then
        TEXT="▲\\n"
    fi
    TEXT="$TEXT$POSITION"
    if [ "$HAS_DOWN" = "true" ]; then
        TEXT="$TEXT\\n▼"
    fi

    TOOLTIP="Workspace $POSITION/$TOTAL_WS on $OUTPUT"
    if [ "$HAS_UP" = "true" ]; then
        TOOLTIP="$TOOLTIP (workspaces above)"
    fi
    if [ "$HAS_DOWN" = "true" ]; then
        TOOLTIP="$TOOLTIP (workspaces below)"
    fi

    printf '{"text": "%s", "tooltip": "%s"}' "$TEXT" "$TOOLTIP"
  '';

  tsWaybar = pkgs.writeShellScriptBin "tswaybar" ''
      export PATH="$PATH:${
        lib.makeBinPath (
          with pkgs;
          [
            tailscale
            jq
          ]
        )
      }"
    STATUS_KEY="BackendState"
    RUNNING="Running"
    tailscale_status () {
        status="$(tailscale status --json | jq -r '.'$STATUS_KEY)"
        if [ "$status" = $RUNNING ]; then
            return 0
        fi
        return 1
    }

    toggle_status () {
        if tailscale_status; then
            tailscale down
        else
            tailscale up
        fi
        sleep 5
    }
    tailnet=$(tailscale switch --list | grep '*' | awk '{print $2}')
    case $1 in
        --status)
            if tailscale_status; then
                #TODO: find a way to format output
                peers=$(echo "$(tailscale status)" | tr -d "\n")
                printf "{\"text\":\"%s\",\"class\":\"connected\",\"alt\":\"connected\", \"tooltip\": \"%s\"}\n" "$tailnet" "$peers"
            else
                printf "{\"text\":\"%s\",\"class\":\"stopped\",\"alt\":\"stopped\"}\n" "$tailnet"
            fi
        ;;
        --toggle)
            toggle_status
        ;;
    esac
  '';
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
          height = 40;
          modules-center = [
            "hyprland/workspaces"
            "sway/workspaces"
          ];
          modules-left = [
            "custom/startmenu"
            "hyprland/window"
            "pulseaudio"
            "backlight"
            # Replaced the single spotify module with the new widget group
            "custom/spotify-prev"
            "custom/spotify-playpause"
            "custom/spotify-info"
            "custom/spotify-next"
            "idle_inhibitor"
          ];
          modules-right = [
            #"custom/hyprbindings"
            "custom/tailscale"
            "cpu"
            "memory"
            "battery"
            "tray"
            "custom/notification"
            "custom/exit"
            "clock"
          ];

          # New Spotify Widget Modules
          "custom/spotify-prev" = {
            format = "";
            tooltip = true;
            tooltip-format = "Previous";
            on-click = "${playerctl} --player=spotify previous";
          };
          "custom/spotify-playpause" = {
            exec = "${spotify-playpause}/bin/spotify-playpause";
            return-type = "json";
            interval = 1;
            on-click = "${playerctl} --player=spotify play-pause";
          };
          "custom/spotify-info" = {
            exec = "${spotify-info}/bin/spotify-info";
            return-type = "json";
            interval = 1; # Fast interval
            max-length = 15;
          };
          "custom/spotify-next" = {
            format = "";
            tooltip = true;
            tooltip-format = "Next";
            on-click = "${playerctl} --player=spotify next";
          };

          "custom/tailscale" = {
            exec = "${tsWaybar}/bin/tswaybar --status";
            exec-if = "${pkgs.procps}/bin/pgrep tailscaled";
            on-click = "exec ${tsWaybar}/bin/tswaybar --toggle";
            tooltip = true;
            interval = 3;
            format = "{}";
            return-type = "json";
          };
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
          };
          "clock" = {
            format = "         {:L%H:%M}";
            tooltip = true;
            tooltip-format = ''
              <big>{:%A, %d.%B %Y }</big>
              <tt><small>{calendar}</small></tt>'';
          };
          "hyprland/window" = {
            max-length = 15;
            separate-outputs = false;
            rewrite = {
              "" = " 🙈 No Windows? ";
            };
          };
          "memory" = {
            interval = 5;
            format = "       {}%";
            tooltip = true;
          };
          "cpu" = {
            interval = 5;
            format = "          {usage:2}%";
            tooltip = true;
          };
          "disk" = {
            format = "          {free}";
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
            format-ethernet = "         {bandwidthDownOctets}";
            format-wifi = "{icon}        {signalStrength}%";
            format-disconnected = "󰤮 ";
            tooltip = false;
          };
          "tray" = {
            spacing = 12;
          };
          "backlight" = {
            "device" = "intel_backlight";
            "format" = "{percent}%   {icon}";
            "format-icons" = [
              ""
              ""
            ];
          };
          "pulseaudio" = {
            format = "{icon}       {volume}% {format_source}";
            format-bluetooth = "{volume}%      {icon}  {format_source}";
            format-bluetooth-muted = "{icon}      {format_source}";
            format-muted = "     {format_source}";
            format-source = "      {volume}%";
            format-source-muted = "  ";
            format-icons = {
              headphone = " ";
              hands-free = " ";
              headset = " ";
              phone = " ";
              portable = " ";
              car = " ";
              default = [
                " "
                " "
                " "
              ];
            };
            on-click = "sleep 0.1 && ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_SINK@ toggle";
            on-click-middle = "${pkgs.pavucontrol}/bin/pavucontrol";
          };
          "custom/exit" = {
            tooltip = false;
            format = " ";
            on-click = lib.mkIf cfg.rofiConfig.enable "sleep 0.1 && $HOME/.config/rofiScripts/rofiLockScript.sh style-1";
          };
          "custom/startmenu" = {
            tooltip = false;
            format = " ";
            on-click = lib.mkIf cfg.rofiConfig.enable "sleep 0.1 && ${rofi} -show drun -theme $HOME/.config/rofi/launchers/type-1/style-landscape.rasi";
          };
          "custom/hyprbindings" = {
            tooltip = false;
            format = "󱕴 ";
            on-click = "sleep 0.1 && list-hypr-bindings";
          };
          "idle_inhibitor" = {
            format = "{icon} ";
            format-icons = {
              activated = " ";
              deactivated = " ";
            };
            tooltip = "true";
            on-click = "${pkgs.libnotify}/bin/notify-send 'idle inhibitor toggled' ";
          };
          "custom/notification" = {
            tooltip = false;
            format = "{icon}  {}";
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
            interval = 5;
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{icon}  {capacity}%";
            format-charging = "󰂄  {capacity}%";
            format-plugged = "󱘖    {capacity}%";
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
      ]
      ++ lib.optionals cfg.niriConfig.enable [
        # Vertical waybar for niri workspace position
        {
          layer = "overlay";
          position = "left";
          width = 50;
          exclusive = false;
          passthrough = true;
          margin-top = 0;
          margin-bottom = 0;
          margin-left = 0;
          margin-right = 0;
          modules-center = [
            "custom/niri-vertical"
          ];

          "custom/niri-vertical" = {
            exec = "${niri-vertical}/bin/niri-vertical";
            return-type = "json";
            interval = 1;
            format = "{}";
          };
        }
      ];
      style = lib.concatStrings (
        [
          ''
            /* --- Global & Base Module Styles --- */
            * {
                font-family: Inter Display, FontAwesome, sans-serif;
                font-weight: 500;
                font-size: 13px;
                border: none;
                border-radius: 12px;
                min-height: 0;
            }
            window#waybar {
                background: transparent;
                color: #${config.stylix.base16Scheme.base05};
            }
            #workspaces, #window, #pulseaudio, #backlight, #idle_inhibitor,
            #custom-tailscale, #cpu, #memory, #battery, #tray, #custom-notification,
            #custom-exit, #clock, #network, #custom-hyprbindings, #custom-startmenu {
                background-color: alpha(#${config.stylix.base16Scheme.base00}, 0.7);
                padding: 4px 15px;
                margin: 6px 4px;
                transition: ${betterTransition};
            }

            /* --- Spotify Widget Group Styling --- */
            #custom-spotify-prev, #custom-spotify-playpause, #custom-spotify-info, #custom-spotify-next {
                background-color: alpha(#${config.stylix.base16Scheme.base01}, 0.8);
                color: #${config.stylix.base16Scheme.base05};
                margin-top: 6px;
                margin-bottom: 6px;
            }
            #custom-spotify-info.playing {
                color: #${config.stylix.base16Scheme.base0B};
            }
            /* Remove space between modules to merge them */
            #custom-spotify-prev {
                margin-left: 4px;
                margin-right: 0px;
                padding: 4px 10px 4px 15px;
                border-radius: 12px 0 0 12px;
            }
            #custom-spotify-playpause {
                margin-left: 0px;
                margin-right: 0px;
                padding: 4px 10px;
                font-size: 16px;
                border-radius: 0;
            }
            #custom-spotify-info {
                margin-left: 0px;
                margin-right: 0px;
                padding: 4px 10px;
                border-radius: 0;
            }
            #custom-spotify-next {
                margin-left: 0px;
                margin-right: 4px;
                padding: 4px 15px 4px 10px;
                border-radius: 0 12px 12px 0;
            }
            #custom-spotify-prev:hover, #custom-spotify-playpause:hover, #custom-spotify-next:hover {
                background-color: alpha(#${config.stylix.base16Scheme.base02}, 0.9);
                color: #${config.stylix.base16Scheme.base0D};
            }
            /* End Spotify Widget Styling */

            /* --- Other Module Styling --- */
            #workspaces {
                background-color: alpha(#${config.stylix.base16Scheme.base01}, 0.8);
                padding: 2px 5px;
            }
            #workspaces button {
                background: transparent;
                color: #${config.stylix.base16Scheme.base04};
                padding: 5px;
                margin: 2px 1px;
                font-weight: bold;
            }
            #workspaces button.active {
                color: #${config.stylix.base16Scheme.base00};
                background: #${config.stylix.base16Scheme.base0D};
            }
            #custom-startmenu {
                color: #${config.stylix.base16Scheme.base00};
                background-color: alpha(#${config.stylix.base16Scheme.base0B}, 0.85);
                font-size: 18px;
            }
            #clock {
                color: #${config.stylix.base16Scheme.base00};
                background: alpha(#${config.stylix.base16Scheme.base0C}, 0.85);
            }
            #custom-exit {
                color: #${config.stylix.base16Scheme.base00};
                background-color: alpha(#${config.stylix.base16Scheme.base08}, 0.85);
            }
            #custom-tailscale.connected {
                background-color: alpha(#1DB954, 0.85);
                color: #${config.stylix.base16Scheme.base00};
            }
            #idle_inhibitor.activated {
                background-color: alpha(#${config.stylix.base16Scheme.base0B}, 0.85);
                color: #${config.stylix.base16Scheme.base00};
            }
            #battery.charging, #battery.plugged {
                background-color: alpha(#${config.stylix.base16Scheme.base0B}, 0.85);
                color: #${config.stylix.base16Scheme.base00};
            }
            #battery.warning:not(.charging) {
                background-color: alpha(#${config.stylix.base16Scheme.base0A}, 0.85);
                color: #${config.stylix.base16Scheme.base00};
            }
            #battery.critical:not(.charging) {
                background-color: alpha(#${config.stylix.base16Scheme.base08}, 0.85);
                color: #${config.stylix.base16Scheme.base00};
                animation-name: blink;
                animation-duration: 0.8s;
                animation-timing-function: linear;
                animation-iteration-count: infinite;
                animation-direction: alternate;
            }
            @keyframes blink { to { opacity: 0.6; } }
          ''
        ]
        ++ lib.optionals cfg.niriConfig.enable [
          ''
            /* --- Niri Module Styling --- */
            #custom-niri-vertical {
              background: linear-gradient(135deg, #${config.stylix.base16Scheme.base00} 0%, #${config.stylix.base16Scheme.base01} 100%);
              color: #${config.stylix.base16Scheme.base05};
              border: 2px solid #${config.stylix.base16Scheme.base0D};
              border-radius: 8px;
              padding: 8px 6px;
              margin: 4px 2px;
              font-size: 16px;
              font-weight: bold;
              text-shadow: 1px 1px 2px #${config.stylix.base16Scheme.base00};
              box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
              transition: ${betterTransition};
            }
            #custom-niri-vertical:hover {
              background: linear-gradient(135deg, #${config.stylix.base16Scheme.base01} 0%, #${config.stylix.base16Scheme.base02} 100%);
              border-color: #${config.stylix.base16Scheme.base0C};
            }
          ''
        ]
      );
    };
  };
}
