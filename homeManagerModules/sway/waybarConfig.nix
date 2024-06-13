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

  config = lib.mkIf cfg.sway.enable {
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
            "sway/window"
          ];
          modules-center = [
            "sway/mode"
            "custom/spotify"
            #"clock"
          ];
          modules-right = [
            "clock"
            "temperature"
            #"cpu#usage"
            "cpu#load"
            "memory#ram"
            "memory#swap"
            "disk"
            "custom/separator"
            "battery#BAT0"
            "battery#BAT1"
            "network"
            "custom/separator"
            "pulseaudio"
            "idle_inhibitor"
            "custom/print"
            "tray"
          ];

          "custom/separator" = {
            format = "|";
            interval = "once";
            tooltip = false;
          };
          ## https://github.com/Alexays/Waybar/wiki/Module:-Workspaces
          "sway/workspaces" = {
            disable-scroll = true;
            all-outputs = true;
            format = "{icon} ";
            format-icons = {
              "1:Term " = "1: ";
              "2:Web " = "2: ";
              "3:IDE " = "3: ";
              "4:Steam " = "4: ";
              "5:Files " = "5: ";
              "6:Virt  /" = "6:  /";
              "7:Kindle 立" = "7: 立";
              "8:Mail " = "8: ";
              "9:WORK " = "9: ";
              "10:Media " = "10: ";
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
              ${pkgs.grim}/bin/grim -g "$(${pkgs.slurp}/bin/slurp)" - | ${pkgs.swappy}/bin/swappy -f -
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
  };
}
