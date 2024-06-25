{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
  fontSize = "font='9'";
in {
  ## https://www.nerdfonts.com/cheat-sheet
  ## https://www.reddit.com/r/swaywm/comments/ni0vso/waybar_spotify_tracktitle/
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
    home.packages = [
      pkgs.pavucontrol
      pkgs.pulseaudio
      pkgs.networkmanagerapplet
    ];
    #services.network-manager-applet.enable = true;

    programs.waybar = {
      enable = true;
      ## see https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/applications/misc/waybar/default.nix#L46
      ## https://github.com/NixOS/nixpkgs/issues/14097#issuecomment-199088116
      #package = pkgs.waybar.override { withMediaPlayer = true; };
      package = pkgs.waybar;
      settings = {
        mainBar = {
          layer = "top";
          position = "top";
          height = 5;
          modules-left = [
            "sway/workspaces"
            "hyprland/workspaces"
            #"sway/window"
          ];
          modules-center = [
            "tray"
            "sway/mode"
            "custom/spotify"
            #"clock"
          ];
          modules-right = [
            "clock"
            "custom/separator"
            "temperature"
            #"cpu#usage"
            "cpu#load"
            "memory#ram"
            #"memory#swap"
            "disk"
            "custom/separator"
            "battery#BAT0"
            "battery#BAT1"
            "battery#BATT"
            "custom/separator"
            #"network"
            #"custom/separator"
            "pulseaudio"
            "idle_inhibitor"
          ];

          "custom/separator" = {
            format = "|";
            interval = "once";
            tooltip = false;
          };
          ## https://github.com/Alexays/Waybar/wiki/Module:-Workspaces
          "hyprland/workspaces" = {
            disable-scroll = true;
            all-outputs = true;
            format = "{icon}";
            format-icons = {
              "1" = "1";
              "2" = "2";
              "3" = "3";
              "4" = "4";
              "5" = "5";
              "6" = "6";
              "7" = "7";
              "8" = "8";
              "9" = "9";
              "10" = "10";
              #focused = "";
              #urgent = "";
              #default = "";
            };
          };
          "sway/workspaces" = {
            disable-scroll = true;
            all-outputs = true;
            format = "{icon}";
            format-icons = {
              "1" = "1";
              "2" = "2";
              "3" = "3";
              "4" = "4";
              "5" = "5";
              "6" = "6";
              "7" = "7";
              "8" = "8";
              "9" = "9";
              "10" = "10";
              #focused = "";
              #urgent = "";
              #default = "";
            };
          };

          ## https://github.com/Alexays/Waybar/wiki/Module:-Sway#window
          "sway/window" = {
            format = "{}";
            tooltip = false;
          };

          ## https://github.com/Alexays/Waybar/wiki/Module:-Sway#mode
          "sway/mode" = {
            format = "{}";
            max-length = 200;
            tooltip = false;
          };

          ## https://github.com/Alexays/Waybar/wiki/Module:-Custom#spotify
          ## https://github.com/Alexays/Waybar/wiki/Module:-Custom#module-custom-config-return-type
          ## https://github.com/Alexays/Waybar/wiki/Module:-Custom#style
          "custom/spotify" = {
            exec = ''
              ${pkgs.playerctl}/bin/playerctl --player=spotify metadata --format '{ "alt": "{{ status }}", "class": "{{ status }}", "text": "{{ artist }} - {{ title }}", "tooltip": "{{ artist }} - {{ title }}" }'  2> /dev/null
            '';
            return-type = "json";
            exec-if = "${pkgs.procps}/bin/pgrep spotify";
            format = "<span ${fontSize}> :</span>{icon} {}";
            format-icons = {
              Playing = "";
              Paused = "";
            };
            max-length = 55;
            interval = 1;
            tooltip = false;
            on-click = "${pkgs.playerctl}/bin/playerctl --player=spotify previous";
            on-click-middle = "${pkgs.playerctl}/bin/playerctl --player=spotify play-pause";
            on-click-right = "${pkgs.playerctl}/bin/playerctl --player=spotify next";
          };

          ## https://github.com/Alexays/Waybar/wiki/Module:-Clock
          clock = {
            timezone = "Europe/Paris";
            format = "<span ${fontSize}> :</span> {:%H:%M}";
            tooltip-format = ''
              <big>{:%Y %B}</big>
              <tt><small>{calendar}</small></tt>
            '';
            format-alt = "<span ${fontSize}>󰸘 :</span> {:%A, %d %B %Y | %H:%M}";
            calendar = {
              "mode" = "year";
              "mode-mon-col" = 3;
              "weeks-pos" = "right";
              "on-scroll" = 1;
              "on-click-right" = "mode";
              "format" = {
                "months" = "<span color='#ffead3'><b>{}</b></span>";
                "days" = "<span color='#ecc6d9'><b>{}</b></span>";
                "weeks" = "<span color='#99ffdd'><b>W{}</b></span>";
                "weekdays" = "<span color='#ffcc66'><b>{}</b></span>";
                "today" = "<span color='#ff6699'><b><u>{}</u></b></span>";
              };
            };
          };

          ## https://github.com/Alexays/Waybar/issues/350#issuecomment-495508523
          ## https://github.com/Alexays/Waybar/wiki/Module:-Temperature
          temperature = {
            thermal-zone = 4;
            critical-threshold = 70;
            format-critical = "<span ${fontSize}>:</span> {temperatureC}°C";
            format = "<span ${fontSize}>:</span> {temperatureC}°C";
          };

          ## https://github.com/Alexays/Waybar/wiki/Module:-CPU
          "cpu#usage" = {
            format = "<span ${fontSize}>::</span> {usage}%";
            #tooltip = false;
          };

          ## https://github.com/Alexays/Waybar/wiki/Module:-CPU
          "cpu#load" = {
            format = "<span ${fontSize}> :</span> {load}";
            tooltip = false;
          };

          ## https://github.com/Alexays/Waybar/wiki/Module:-Memory
          "memory#ram" = {
            format = "<span ${fontSize}> :</span> {used:0.1f}G/{total:0.1f}G";
            max-length = 30;
          };

          ## https://github.com/Alexays/Waybar/wiki/Module:-Memory
          "memory#swap" = {
            format = "<span ${fontSize}></span> : {swapUsed:0.1f}G";
            max-length = 30;
            tooltip = false;
          };

          ## https://github.com/Alexays/Waybar/wiki/Module:-Disk
          disk = {
            interval = 30;
            format = "<span ${fontSize}> :</span> {percentage_used}%";
            path = "/";
          };

          ## https://github.com/Alexays/Waybar/wiki/Module:-Battery
          ## TODO need to add charging status
          "battery#BAT0" = {
            bat = "BAT0";
            adapter = "AC";
            interval = 60;
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{icon} : {capacity}%";
            format-icons = [" " " " " " " " " "];
            max-length = 25;
            tooltip = false;
          };
          "battery#BATT" = {
            bat = "BATT";
            adapter = "AC";
            interval = 60;
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{icon} : {capacity}%";
            format-icons = [" " " " " " " " " "];
            max-length = 25;
            tooltip = false;
          };

          "battery#BAT1" = {
            bat = "BAT1";
            interval = 60;
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{icon} : {capacity}%";
            format-icons = [" " " " " " " " " "];
            max-length = 25;
            tooltip = false;
          };

          ## https://github.com/Alexays/Waybar/wiki/Module:-Network
          network = {
            format-wifi = "<span ${fontSize}> </span>: {ipaddr}/{cidr}";
            format-ethernet = "<span ${fontSize}> </span>: {ipaddr}/{cidr}";
            format-linked = "{ifname} (No IP) <span ${fontSize}></span>";
            format-disconnected = "<span ${fontSize}>睊 </span>: Not connected";
            tooltip-format = "{essid} {signalStrength}%";
            on-click-middle = "${pkgs.networkmanagerapplet}/bin/nm-connection-editor";
            tooltip = true;
            interval = 1;
          };

          ## https://github.com/Alexays/Waybar/wiki/Module:-PulseAudio
          pulseaudio = {
            format = "<span ${fontSize}>{icon}</span> : {volume}%";
            format-bluetooth = "<span ${fontSize}>{icon} </span> : {volume}%";
            format-muted = "<span ${fontSize}>󰖁</span> : {volume}%";
            format-icons = {
              headphone = "";
              hands-free = "";
              headset = "";
              phone = "";
              portable = "";
              car = "";
              default = ["" "" ""];
            };
            scroll-step = 1;
            on-click = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_SINK@ toggle";
            on-click-middle = "${pkgs.pavucontrol}/bin/pavucontrol";
          };

          ## https://github.com/Alexays/Waybar/wiki/Module:-Idle-Inhibitor
          idle_inhibitor = {
            format = "{icon}";
            format-icons = {
              activated = "";
              deactivated = "";
            };
            #on-click = "systemctl --user stop swayidle.service";
            #on-click-right = "systemctl --user start swayidle.service";
          };

          "custom/print" = {
            format = "";
            on-click = ''
              ${pkgs.sway-contrib.grimshot}/bin/grimshot --notify copy area
            '';
            tooltip = false;
          };

          ## https://github.com/Alexays/Waybar/wiki/Module%3A-Tray
          tray = {
            icon-size = 16;
            spacing = 5;
            tooltip = false;
          };
        };
      };
    };
    programs.waybar.style = ''

      /* The whole bar */
      #waybar {
          background: transparent;
          color: white;
          background-color: rgba(0,0,0,0);
          font-family: UbuntuMono;
          font-size: 14px;
      }
      * {
        border: none;
        font-family: Hack Nerd Font;
        font-size: 12px;
        font-weight: bold;
      }

      #custom-separator {
        color: #abb2bf;
        margin: 0 1px;
      }

      #workspaces {
        margin: 1px 2px 2px 2px;
        border-radius: 10px;
        background-clip: padding-box;
      }

      #workspaces button {
        color: #abb2bf;
      }

      #workspaces button:first-child {
        padding-left: 10px;
      }

      #workspaces button:last-child {
        padding-right: 10px;
      }

      #workspaces button:hover {
        background-color: rgba(0, 0, 0, 0.2)
      }

      #workspaces button.focused {
        color: #1DB954;
      }

      #workspaces button.urgent {
        color: #e06c75;
      }

      window#waybar {
        background-color: rgba(0,0,0,0);
        color: #abb2bf;
        transition-property: background-color;
        transition-duration: .5s;
      }

      window#waybar.hidden {
        opacity: 0.2;
      }

      #mode {
        color: #12151d;
        padding: 0 10px;
        margin: 1px 2px 2px 2px;
        border-radius: 10px;
        background-clip: padding-box;
      }

      #custom-spotify {
        padding: 0 10px;
        margin: 1px 2px 2px 2px;
        border-radius: 10px;
      }

      #custom-spotify.Playing {
          color: #1DB954;
      }

      #custom-spotify.Paused {
          color: #e06c75;
      }

      #window,
      #temperature,
      #cpu,
      #memory,
      #disk,
      #network,
      #battery {
        padding: 0 3px;
        margin: 1px;
      }

      #clock {
        padding: 0 10px;
        margin: 1px 2px 2px 2px;
        border-radius: 10px;
        color: #c678dd;
      }

      #window {
      }

      #temperature {
        color: #61afef;
      }
      #temperature.critical {
        background-color: #e06c75;
        color: #1e222a;
      }

      #cpu {
        color: #d19a66;
      }

      #memory {
        color: #d19a66;
      }

      #disk {
        color: #d19a66;
      }

      #battery {
        color: #1DB954;
      }
      #battery.charging {
        color: #61afef
      }
      #battery.plugged {
        color: #1DB954;
      }
      #battery.critical:not(.charging) {
        color: #e06c75;
        animation-name: blink;
        animation-duration: 0.5s;
        animation-timing-function: linear;
        animation-iteration-count: infinite;
        animation-direction: alternate;
      }

      #network {
        color: #1DB954
      }
      #network.disconnected {
        color: #1e222a;
      }

      #pulseaudio,
      #idle_inhibitor,
      #custom-print,
      #tray {
        margin: 1px 0;
        padding: 0 5px;
        background-color: rgba(0,0,0,0);
      }

      #pulseaudio {
        margin-left: 1px;
        border-top-left-radius: 10px;
        border-bottom-left-radius: 10px;
      }
      #pulseaudio.muted {
        color: #e06c75;
      }

      #idle_inhibitor,
      #custom-print {
        padding-left: 9px;
        padding-right: 9px;
      }

      #idle_inhibitor.activated {
        color: #abb2bf;
      }
      #idle_inhibitor.deactivated {
        color: #e06c75;
      }

      #tray {
        margin-right: 1px;
        border-top-right-radius: 10px;
        border-bottom-right-radius: 10px;
      }
    '';
  };
}
