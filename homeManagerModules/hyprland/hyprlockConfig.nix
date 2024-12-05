{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  lockWallpaper = "${config.profileCustomization.lockWallpaper}";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  pidof = "${pkgs.sysvtools}/bin/pidof";
  hyprlock = "${pkgs.hyprlock}/bin/hyprlock";
  systemctl = "${pkgs.systemd}/bin/systemctl";
  loginctl = "${pkgs.systemd}/bin/loginctl";
  hyprctl = "${pkgs.hyprland}/bin/hyprctl";
  whatsong = pkgs.writeShellScriptBin "whatsong" ''
    song_info=$(${pkgs.playerctl}/bin/playerctl metadata --format '{{title}}   {{artist}}')
    echo "$song_info"
  '';
in
{
  config = lib.mkIf cfg.hyprlandConfig.enable {
    home.packages = [ whatsong ];
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "${pidof} ${hyprlock} || ${hyprlock}"; # avoid starting multiple hyprlock instances.
          before_sleep_cmd = "${loginctl} lock-session"; # lock before suspend.
          after_sleep_cmd = "${hyprctl} dispatch dpms on"; # to avoid having to press a key twice to turn on the display.
        };

        listener = [
          {
            timeout = 30;
            on-timeout = "${brightnessctl} -s set 10"; # set monitor backlight to minimum, avoid 0 on OLED monitor.
            on-resume = "${brightnessctl} -r"; # monitor backlight restore.
          }

          # turn off keyboard backlight, comment out this section if you dont have a keyboard backlight.
          {
            timeout = 30;
            on-timeout = "${brightnessctl} -sd rgb:kbd_backlight set 0"; # turn off keyboard backlight.
            on-resume = "${brightnessctl} -rd rgb:kbd_backlight"; # turn on keyboard backlight.
          }

          {
            timeout = 60;
            on-timeout = "${loginctl} lock-session"; # lock screen when timeout has passed
          }

          {
            timeout = 300;
            on-timeout = "${hyprctl} dispatch dpms off"; # screen off when timeout has passed
            on-resume = "${hyprctl} dispatch dpms on"; # screen on when activity is detected after timeout has fired.
          }

          {
            timeout = 600;
            on-timeout = "${systemctl} suspend"; # suspend pc
          }
        ];
      };
    };

    programs.hyprlock = {
      enable = true;
      settings = {
        general = {
          disable_loading_bar = false;
          #grace = 300;
          hide_cursor = true;
          no_fade_in = false;
        };

        background = {
          path = lib.mkForce "${lockWallpaper}";
          blur_passes = 0;
          blur_size = 8;
        };
        input-field = {
          size = "250, 60";
          outline_thickness = 2;
          dots_size = 0.2; # Scale of input-field height, 0.2 - 0.8
          dots_spacing = 0.2; # Scale of dots' absolute size, 0.0 - 1.0
          dots_center = true;
          outer_color = lib.mkForce "rgba(0, 0, 0, 0)";
          inner_color = lib.mkForce "rgba(0, 0, 0, 0.5)";
          font_color = lib.mkForce "rgb(200, 200, 200)";
          fade_on_empty = false;
          font_family = "JetBrains Mono Nerd Font Mono";
          placeholder_text = ''
            <i><span foreground="##cdd6f4">Enter Password or Press Enter (Yubikey)</span></i>
          '';
          hide_input = false;
          position = "0, -120";
          halign = "center";
          valign = "center";
        };
        label = [
          {
            text = ''
              cmd[update:1000] date +"%-I:%M%p"
            '';
            # color = "$foreground";
            #color = rgba(255, 255, 255, 0.6)
            font_size = 120;
            font_family = "JetBrains Mono Nerd Font Mono ExtraBold";
            position = "0, -300";
            halign = "center";
            valign = "top";
          }
          {
            text = "Logged in as $USER";
            # color = "$foreground";
            #color = rgba(255, 255, 255, 0.6)
            font_size = 25;
            font_family = "JetBrains Mono Nerd Font Mono";
            position = "0, -40";
            halign = "center";
            valign = "center";
          }
          {
            text = ''
              cmd[update:1000] echo "$(${whatsong}/bin/whatsong)"
            '';
            #color = "$foreground";
            #color = rgba(255, 255, 255, 0.6)
            font_size = 18;
            font_family = "Hack Nerd Font";
            position = "0, 0";
            halign = "center";
            valign = "bottom";
          }
        ];
      };
    };
  };
}
