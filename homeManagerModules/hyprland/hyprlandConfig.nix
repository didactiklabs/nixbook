{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  mainWallpaper = "${config.profileCustomization.mainWallpaper}";
  startup_audio = "${config.profileCustomization.startup_audio}";
  rofi-wayland = "${pkgs.rofi-wayland}/bin/rofi";
  waybar = "${pkgs.waybar}/bin/waybar";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  grimshot = "${pkgs.grimblast}/bin/grimblast";
  pidof = "${pkgs.sysvtools}/bin/pidof";
in
{
  config = lib.mkIf cfg.hyprlandConfig.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      # xwayland.enable = false;
      plugins = with pkgs.hyprlandPlugins; [
        hy3
        hyprexpo
      ];
      settings = {
        debug = {
          disable_logs = false;
        };
        "$mod" = "SUPER";
        misc = {
          disable_hyprland_logo = true;
          vfr = true;
        };
        plugin = {
          hy3 = {
            tabs = {
              "rounding" = 20;
              "col.active" = "rgb(${config.lib.stylix.colors.base02})"; # to move to stylix module
              "col.text.active" = "rgb(${config.lib.stylix.colors.base07})";
              "col.urgent" = "rgb(${config.lib.stylix.colors.base04})";
            };
          };
          hyprexpo = {
            columns = 4;
            gap_size = 5;
            #bg_col = rgb(111111);
            workspace_method = "center current"; # [center/first] [workspace] e.g. first 1 or center m+1
            enable_gesture = true; # laptop touchpad
            gesture_fingers = 3; # 3 or 4
            gesture_distance = 300; # how far is the "max"
            gesture_positive = true; # positive = swipe down. Negative = swipe up.
          };
        };
        general = {
          # See https://wiki.hyprland.org/Configuring/Variables/ for more
          gaps_in = 5;
          gaps_out = 10;
          border_size = 0;
          resize_on_border = true;
          layout = "hy3";
        };
        decoration = {
          rounding = 10;
          active_opacity = 0.85;
          inactive_opacity = 0.85;
          dim_inactive = false;
          dim_strength = 0.2;
          blur = {
            enabled = true;
            size = 9;
            passes = 1;
            new_optimizations = true;
            ignore_opacity = true;
          };
        };
        animations = {
          enabled = true;
          bezier = [
            "wind, 0.05, 0.9, 0.1, 1.05"
            "winIn, 0.1, 1.1, 0.1, 1.1"
            "winOut, 0.3, -0.3, 0, 1"
            "liner, 1, 1, 1, 1"
          ];
          animation = [
            "windows, 1, 6, wind, slide"
            "windowsIn, 1, 6, winIn, slide"
            "windowsOut, 1, 5, winOut, slide"
            "windowsMove, 1, 5, wind, slide"
            "border, 1, 1, liner"
            "borderangle, 1, 180, liner, loop #used by rainbow borders and rotating colors"
            "fade, 1, 10, default"
            "workspaces, 1, 5, wind"
          ];
        };
        layerrule = [
          "blur,rofi"
          "dimaround,rofi"
        ];

        windowrulev2 = [
          "float,class:(com.github.hluk.copyq)"
          "center 1,class:(com.github.hluk.copyq)"
          "size 40% 60%, class:(com.github.hluk.copyq)"
          "opaque, class:(mpv)"
          "opaque, class:(imv)"
          "opaque, class:(com.github.iwalton3.jellyfin-media-player)"
          "opaque, class:(com.moonlight_stream.Moonlight)"
          "opaque, title:(ranger)"
          "opaque, title:(.*)(Immich — Mozilla Firefox)"
          "opaque, title:(.*)(YouTube — Mozilla Firefox)"
          "opaque, title:(.*)(Jellyfin — Mozilla Firefox)"
          "opaque, title:(.*)(Facebook — Mozilla Firefox)"
          "opaque, title:(.*)(Instagram — Mozilla Firefox)"
          "opaque, title:(.*)(Nexus - Mods and community — Mozilla Firefox)"
          "opaque, title:(.*)(Imgur: The magic of the Internet — Mozilla Firefox)"
          "opaque, initialTitle:(Discord Popout)"
        ];

        monitor = [ ",preferred,auto,1" ];
        env = [
          "XDG_CURRENT_DESKTOP,Hyprland"
          "XDG_SESSION_TYPE,wayland"
          "XDG_SESSION_DESKTOP,Hyprland"
          "QT_AUTO_SCREEN_SCALE_FACTOR,1"
          "QT_QPA_PLATFORM=wayland;xcb"
          "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
          "QT_QPA_PLATFORMTHEME,qt6ct"
          "SDL_VIDEODRIVER,wayland"
          "_JAVA_AWT_WM_NONEREPARENTING,1"
          "CLUTTER_BACKEND,wayland"
          "GDK_BACKEND,wayland,x11"
        ];
        exec-once = [
          "systemctl --user import-environment XDG_SESSION_TYPE XDG_CURRENT_DESKTOP"
          "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"
          "${pkgs.mpg123}/bin/mpg123 ${startup_audio}"
          "${pidof} ${waybar} || ${waybar}"
        ];
        exec = [
          "${pkgs.swaybg}/bin/swaybg -m fill -i ${mainWallpaper}"
          "${pkgs.swaynotificationcenter}/bin/swaync-client --reload-css"
          "${pkgs.swaynotificationcenter}/bin/swaync-client --reload-config"

          "killall -SIGUSR2 waybar"
        ];
        input = {
          kb_layout = "fr";
          numlock_by_default = true;
        };
        bind = [
          "$mod, TAB, hyprexpo:expo, toggle"
          "$mod, Z, hy3:changegroup, toggletab"
          "$mod, E, hy3:changegroup, opposite"

          "$mod, ampersand, workspace, 1"
          "$mod, eacute, workspace, 2"
          "$mod, quotedbl, workspace, 3"
          "$mod, apostrophe, workspace, 4"
          "$mod, parenleft, workspace, 5"
          "$mod, minus, workspace, 6"
          "$mod, egrave, workspace, 7"
          "$mod, underscore, workspace, 8"
          "$mod, ccedilla, workspace, 9"
          "$mod, agrave, workspace, 10"

          "$mod SHIFT, ampersand, movetoworkspace, 1"
          "$mod SHIFT, eacute, movetoworkspace, 2"
          "$mod SHIFT, quotedbl, movetoworkspace, 3"
          "$mod SHIFT, apostrophe, movetoworkspace, 4"
          "$mod SHIFT, parenleft, movetoworkspace, 5"
          "$mod SHIFT, minus, movetoworkspace, 6"
          "$mod SHIFT, egrave, movetoworkspace, 7"
          "$mod SHIFT, underscore, movetoworkspace, 8"
          "$mod SHIFT, ccedilla, movetoworkspace, 9"
          "$mod SHIFT, agrave, movetoworkspace, 10"

          "$mod, left, hy3:movefocus, l"
          "$mod, right, hy3:movefocus, r"
          "$mod, up, hy3:movefocus, u"
          "$mod, down, hy3:movefocus, d"

          "$mod SHIFT, left, hy3:movewindow, l"
          "$mod SHIFT, right, hy3:movewindow, r"
          "$mod SHIFT, up, hy3:movewindow, u"
          "$mod SHIFT, down, hy3:movewindow, d"

          "$mod, A, killactive"
          ", PRINT, exec, ${grimshot} --notify copy area"
          "$mod, N, exec, ${pkgs.swaynotificationcenter}/bin/swaync-client -t"
          "$mod, B, exec, ${pkgs.toybox}/bin/pkill -SIGUSR1 'waybar'"

          ",XF86MonBrightnessDown, exec, ${brightnessctl} set 10%-"
          ",XF86MonBrightnessUp, exec, ${brightnessctl} set +10%"
        ]
        ++ (if cfg.copyqConfig.enable then [ "$mod, Q, exec, ${pkgs.copyq}/bin/copyq toggle" ] else [ ])
        ++ (
          if cfg.rofiConfig.enable then
            [
              "$mod, D, exec, ${rofi-wayland} -show drun -theme $HOME/.config/rofi/launchers/type-1/style-landscape.rasi"
              ''
                $mod, L, exec, $HOME/.config/rofiScripts/rofiLockScript.sh style-1
              ''
            ]
          else
            [ ]
        );
      };
    };
  };
}
