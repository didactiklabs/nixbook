{
  config,
  pkgs,
  lib,
  username,
  ...
}: let
  cfg = config.customHomeManagerModules;
  mainWallpaper = "${config.profileCustomization.mainWallpaper}";
  lockWallpaper = "${config.profileCustomization.lockWallpaper}";
  terminal = "${pkgs.alacritty}/bin/alacritty";
  rofi-wayland = "${pkgs.rofi-wayland}/bin/rofi";
  rofiLauncherType = "${cfg.rofiConfig.launcher.type}";
  rofiLauncherStyle = "${cfg.rofiConfig.launcher.style}";
  rofiPowermenuStyle = "${cfg.rofiConfig.powermenu.style}";
  loginctl = "${pkgs.systemd}/bin/loginctl";
  waybar = "${pkgs.waybar}/bin/waybar";
  wpctl = "${pkgs.wireplumber}/bin/wpctl";
  notify-send = "${pkgs.libnotify}/bin/notify-send";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  swaylock = "${pkgs.swaylock}/bin/swaylock";
  hyprctl = "${pkgs.hyprland}/bin/hyprctl";
  grimshot = "${pkgs.grimblast}/bin/grimblast";

  workspace1 = "1";
  workspace2 = "2";
  workspace3 = "3";
  workspace4 = "4";
  workspace5 = "5";
  workspace6 = "6";
  workspace7 = "7";
  workspace8 = "8";
  workspace9 = "9";
  workspace10 = "10";
in {
  config = lib.mkIf cfg.hyprlandConfig.enable {
    services.swayidle = {
      enable = true;
      systemdTarget = "hyprland-session.target";
      events = [
        {
          event = "lock";
          command = "${swaylock} -f --image '${lockWallpaper}'";
        }
      ];
      timeouts = [
        {
          timeout = 60;
          command = "${swaylock} -f --image '${lockWallpaper}'";
        }
        {
          timeout = 300;
          command = "${hyprctl} dispatch dpms off";
          resumeCommand = "${hyprctl} dispatch dpms on";
        }
      ];
    };
    wayland.windowManager.hyprland.enable = true;
    wayland.windowManager.hyprland.plugins = [
      pkgs.hyprlandPlugins.hy3
    ];
    wayland.windowManager.hyprland.settings = {
      "$mod" = "SUPER";
      misc = {
        disable_hyprland_logo = true;
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
        dim_inactive = true;
        dim_strength = 0.2;
        blur = {
          enabled = true;
          size = 6;
          passes = 2;
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
        "blur,waybar"
      ];

      monitor = [
        ",preferred,auto,1"
        "eDP-1,preferred,0x587,2.0"
        "DP-8,1920x1080,1440x0,auto"
        "DP-9,1920x1080,3360x0,auto"
      ];
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
        "${waybar}"
      ];
      exec = [
        "${pkgs.swaybg}/bin/swaybg -m fill -i ${mainWallpaper}"
        "killall -SIGUSR2 waybar"
      ];
      input = {
        kb_layout = "fr";
        numlock_by_default = true;
      };
      bind =
        [
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

          "$mod, RETURN, exec, ${terminal}"
          "$mod, A, killactive"
          ", PRINT, exec, ${grimshot} --notify copy area"

          ",XF86AudioRaiseVolume, exec, ${wpctl} set-volume @DEFAULT_SINK@ 3%+ && ${notify-send} '󰕾 +3%'"
          ",XF86AudioLowerVolume, exec, ${wpctl} set-volume @DEFAULT_SINK@ 3%- && ${notify-send} '󰕾 -3%'"
          ",XF86AudioMute, exec, ${wpctl} set-mute @DEFAULT_SINK@ toggle"
          ",XF86AudioMicMute, exec, ${wpctl} set-mute @DEFAULT_SINK@ toggle"
          ",XF86MonBrightnessDown, exec, ${brightnessctl} set 10%-"
          ",XF86MonBrightnessUp, exec, ${brightnessctl} set +10%"
        ]
        ++ (
          if cfg.copyqConfig.enable
          then [
            "$mod, Q, exec, ${pkgs.copyq}/bin/copyq toggle"
          ]
          else []
        )
        ++ (
          if cfg.rofiConfig.enable
          then [
            "$mod, D, exec, ${rofi-wayland} -show drun -theme $HOME/.config/rofi/launchers/${rofiLauncherType}/${rofiLauncherStyle}.rasi"
            ''
              $mod, L, exec, $HOME/.config/rofiScripts/rofiLockScript.sh ${rofiPowermenuStyle}
            ''
          ]
          else []
        );
    };
  };
}
