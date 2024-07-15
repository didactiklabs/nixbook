{ config, pkgs, lib, ... }:
let
  cfg = config.customHomeManagerModules;
  mainWallpaper = "${config.profileCustomization.mainWallpaper}";
  lockWallpaper = "${config.profileCustomization.lockWallpaper}";
  swaylock = "${pkgs.swaylock}/bin/swaylock";
  swaymsg = "${pkgs.sway}/bin/swaymsg";
  terminal = "${pkgs.alacritty}/bin/alacritty";
  waybar = "${pkgs.waybar}/bin/waybar";
  rofi-wayland = "${pkgs.rofi-wayland}/bin/rofi";
  rofiLauncherType = "${cfg.rofiConfig.launcher.type}";
  rofiLauncherStyle = "${cfg.rofiConfig.launcher.style}";
  rofiPowermenuStyle = "${cfg.rofiConfig.powermenu.style}";
  playerctl = "${pkgs.playerctl}/bin/playerctl";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  grimshot = "${pkgs.sway-contrib.grimshot}/bin/grimshot";
  systemctl = "${pkgs.systemd}/bin/systemctl";
  waylandEnv = {
    CLUTTER_BACKEND = "wayland";
    SDL_VIDEODRIVER = "wayland";
    QT_QPA_PLATFORM = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    _JAVA_AWT_WM_NONREPARENTING = "1";
    MOZ_ENABLE_WAYLAND = "1";
    XDG_SESSION_TYPE = "wayland";
    XDG_SESSION_DESKTOP = "sway";
    XDG_CURRENT_DESKTOP = "sway";
    WLR_NO_HARDWARE_CURSORS = "1";
    #NIXOS_OZONE_WL = "1";
    #GTK_USE_PORTAL = "1";
  };
  mod = "Mod4";
  modeSystem =
    "System (l) lock, (e) logout, (s) suspend, (h) hibernate, (r) reboot, (Shift+s) shutdown, (Shift+r) BIOS";
  modeResize = "Resize";
  ## Custom Workspace
  ## cf https://fontawesome.com/cheatsheet
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
  colorBlack = "#000000";
  colorLightGrey = "#525865";
  colorDarkGrey = "#222222";
  colorRed = "#bb0000";
  colorWhite = "#f3f4f5";
  colorGreen = "#00ff00";
in {
  config = lib.mkIf cfg.swayConfig.enable {
    ## shrug https://github.com/nix-community/home-manager/issues/5311#issuecomment-2068042917
    wayland.windowManager.sway.checkConfig = false;

    home.sessionVariables = waylandEnv;
    ## https://git.sbruder.de/simon/nixos-config/src/branch/master/users/simon/modules/sway/default.nix#L242
    ## https://wiki.archlinux.org/title/Sway#Input_devices
    ## https://wiki.archlinux.org/title/Sway#Idle
    ## https://nix-community.github.io/home-manager/options.html#opt-services.swayidle.events
    services.swayidle = {
      enable = true;
      events = [{
        event = "lock";
        command = "${swaylock} -f --image '${lockWallpaper}'";
      }];
      timeouts = [
        {
          timeout = 60;
          command = "${swaylock} -f --image '${lockWallpaper}'";
        }
        {
          timeout = 300;
          command = "${swaymsg} 'output * dpms off'";
          resumeCommand = "${swaymsg} 'output * dpms on'";
        }
      ];
    };

    ## https://wiki.archlinux.org/title/Sway#Manage_Sway-specific_daemons_with_systemd
    ## https://nix-community.github.io/home-manager/options.html#opt-wayland.windowManager.sway.enable
    wayland.windowManager.sway = {
      package = pkgs.swayfx;
      enable = true;
      wrapperFeatures.base = true;
      wrapperFeatures.gtk = true;
      systemd.enable = true;
      swaynag.enable = true;
      xwayland = true;
      extraSessionCommands = ''
        export CLUTTER_BACKEND="wayland"
        export SDL_VIDEODRIVER="wayland"
        export QT_QPA_PLATFORM="wayland"
        export QT_WAYLAND_DISABLE_WINDOWDECORATION="1"
        export _JAVA_AWT_WM_NONREPARENTING="1"
        export MOZ_ENABLE_WAYLAND="1"
        export DESKTOP_SESSION="sway"
        export XDG_SESSION_TYPE="wayland"
        export XDG_SESSION_DESKTOP="sway"
        export XDG_CURRENT_DESKTOP="sway"
        export WLR_NO_HARDWARE_CURSORS="1"
        #export NIXOS_OZONE_WL="1"
        #export GTK_USE_PORTAL="1"
      '';
      extraConfig = ''
        ## Custom Workspace
        set $workspace1  ${workspace1}
        set $workspace2  ${workspace2}
        set $workspace3  ${workspace3}
        set $workspace4  ${workspace4}
        set $workspace5  ${workspace5}
        set $workspace6  ${workspace6}
        set $workspace7  ${workspace7}
        set $workspace8  ${workspace8}
        set $workspace9  ${workspace9}
        set $workspace10 ${workspace10}
        layer_effects waybar blur enable
        include /etc/sway/config.d/*
      '';
      config = {
        floating = {
          modifier = "Mod4";
          titlebar = true;
          border = 2;
        };
        window = {
          hideEdgeBorders = "none";
          titlebar = false;
          border = 2;
        };
        defaultWorkspace = "${workspace1}";
        terminal = "${terminal}";
        input = {
          "type:keyboard" = {
            xkb_numlock = "enabled";
            xkb_layout = "fr";
          };
          "type:touchpad" = {
            tap = "enabled";
            #natural_scroll = "disabled";
            #dwt = "enabled";
            accel_profile =
              "adaptive"; # disable mouse acceleration (enabled by default; to set it manually, use "adaptive" instead of "flat")
            pointer_accel = "0.3"; # set mouse sensitivity (between -1 and 1)
          };
        };

        ## cf https://github.com/colemickens/nixcfg/blob/main/mixins/sway.nix
        output = {
          "*" = {
            bg = "${mainWallpaper} fill";
            subpixel = "rgb";
            #adaptive_sync = "on";
          };
        };

        gaps = {
          #  bottom = 5;
          #  horizontal = 5;
          inner = 5;
          #  left = 5;
          outer = 5;
          #  right = 5;
          smartBorders = "off";
          smartGaps = false;
          #  top = 5;
          #  vertical = 5;
        };

        window.commands = [
          {
            command =
              "opacity 0.8, shadows enable, blur enable, blur_passes 5, blur_radius 6, corner_radius 10";
            criteria = { class = ".*"; };
          }
          {
            command =
              "floating enable, sticky enable, resize set height 600px width 550px, move position cursor, move down 330";
            criteria = { app_id = "copyq"; };
          }
          {
            command = "opacity 1.0";
            criteria = { app_id = "com.moonlight_stream.Moonlight"; };
          }
        ];

        fonts = {
          names = [ "Hack Nerd Font" "FontAwesome" ];
          style = "Bold";
          size = lib.mkForce 9.0;
        };

        colors = {
          background = lib.mkDefault "${colorWhite}";
          focused = {
            background = lib.mkForce "${colorLightGrey}";
            border = lib.mkForce "${colorBlack}";
            childBorder = lib.mkForce "${colorLightGrey}";
            indicator = lib.mkDefault "${colorGreen}";
            text = lib.mkDefault "${colorWhite}";
          };
          focusedInactive = {
            background = lib.mkDefault "${colorDarkGrey}";
            border = lib.mkForce "${colorBlack}";
            childBorder = lib.mkForce "${colorDarkGrey}";
            indicator = lib.mkDefault "${colorGreen}";
            text = lib.mkDefault "${colorWhite}";
          };
          unfocused = {
            background = lib.mkDefault "${colorDarkGrey}";
            border = lib.mkForce "${colorBlack}";
            childBorder = lib.mkForce "${colorDarkGrey}";
            indicator = lib.mkDefault "${colorGreen}";
            text = lib.mkDefault "${colorWhite}";
          };
          urgent = {
            background = lib.mkDefault "${colorRed}";
            border = lib.mkForce "${colorRed}";
            childBorder = lib.mkForce "${colorDarkGrey}";
            indicator = lib.mkDefault "${colorGreen}";
            text = lib.mkDefault "${colorWhite}";
          };
          placeholder = {
            background = lib.mkDefault "${colorBlack}";
            border = lib.mkForce "${colorBlack}";
            childBorder = lib.mkForce "${colorDarkGrey}";
            indicator = lib.mkDefault "${colorBlack}";
            text = lib.mkDefault "${colorWhite}";
          };
        };

        bars = lib.mkIf cfg.waybar.enable [{
          position = "top";
          command = "${waybar}";
          fonts = {
            names = [ "Hack Nerd Font" "FontAwesome" ];
            style = "Bold";
            size = 9.0;
          };
          colors = {
            background = "${colorDarkGrey}";
            separator = "${colorWhite}";
            activeWorkspace = {
              background = "${colorDarkGrey}";
              border = "${colorDarkGrey}";
              text = "${colorWhite}";
            };
            inactiveWorkspace = {
              background = "${colorDarkGrey}";
              border = "${colorDarkGrey}";
              text = "${colorWhite}";
            };
            focusedWorkspace = {
              background = "${colorLightGrey}";
              border = "${colorDarkGrey}";
              text = "${colorWhite}";
            };
            bindingMode = {
              background = "${colorRed}";
              border = "${colorRed}";
              text = "${colorWhite}";
            };
            urgentWorkspace = {
              background = "${colorRed}";
              border = "${colorRed}";
              text = "${colorWhite}";
            };
          };
        }];

        keybindings = lib.filterAttrsRecursive (name: value: value != null) {
          #lib.mkOptionDefault {
          "${mod}+Return" = "exec ${terminal}";
          # Focus
          "${mod}+Left" = "focus left";
          "${mod}+Down" = "focus down";
          "${mod}+Up" = "focus up";
          "${mod}+Right" = "focus right";

          "${mod}+Shift+Left" = "move left";
          "${mod}+Shift+Down" = "move down";
          "${mod}+Shift+Up" = "move up";
          "${mod}+Shift+Right" = "move right";

          "${mod}+l" = lib.mkIf cfg.rofiConfig.enable ''
            exec $HOME/.config/rofiScripts/rofiLockScript.sh ${rofiPowermenuStyle}
          '';
          "${mod}+d" = lib.mkIf cfg.rofiConfig.enable ''
            exec "${rofi-wayland} -show drun -theme $HOME/.config/rofi/launchers/${rofiLauncherType}/${rofiLauncherStyle}.rasi"
          '';

          # Brightness
          "XF86MonBrightnessDown" = "exec ${brightnessctl} set 10%-";
          "XF86MonBrightnessUp" = "exec ${brightnessctl} set +10%";

          ## To allow a keybinding to be executed while the lockscreen is active add the --locked parameter to bindsym.
          # Audio
          "--locked ${mod}+equal" = "exec ${playerctl} next";
          "--locked ${mod}+minus" = "exec ${playerctl} previous";
          "--locked XF86AudioNext" = "exec ${playerctl} next";
          "--locked XF86AudioPrev" = "exec ${playerctl} previous";
          "--locked XF86AudioPlay" = "exec ${playerctl} play-pause";
          "Print" = ''
            exec ${grimshot} --notify copy area
          '';
          "${mod}+ampersand" = "workspace $workspace1";
          "${mod}+eacute" = "workspace $workspace2";
          "${mod}+quotedbl" = "workspace $workspace3";
          "${mod}+apostrophe" = "workspace $workspace4";
          "${mod}+parenleft" = "workspace $workspace5";
          "${mod}+minus" = "workspace $workspace6";
          "${mod}+egrave" = "workspace $workspace7";
          "${mod}+underscore" = "workspace $workspace8";
          "${mod}+ccedilla" = "workspace $workspace9";
          "${mod}+agrave" = "workspace $workspace10";
          "${mod}+Shift+ampersand" = "move container to workspace $workspace1";
          "${mod}+Shift+eacute" = "move container to workspace $workspace2";
          "${mod}+Shift+quotedbl" = "move container to workspace $workspace3";
          "${mod}+Shift+apostrophe" = "move container to workspace $workspace4";
          "${mod}+Shift+parenleft" = "move container to workspace $workspace5";
          "${mod}+Shift+minus" = "move container to workspace $workspace6";
          "${mod}+Shift+egrave" = "move container to workspace $workspace7";
          "${mod}+Shift+underscore" = "move container to workspace $workspace8";
          "${mod}+Shift+ccedilla" = "move container to workspace $workspace9";
          "${mod}+Shift+agrave" = "move container to workspace $workspace10";

          "${mod}+Shift+p" = "move scratchpad";
          "${mod}+a" = "kill";
          "${mod}+c" = "reload";
          "${mod}+s" = "layout stacking";
          "${mod}+e" = "layout toggle split";
          "${mod}+z" = "layout tabbed";
          "${mod}+Shift+r" = "restart";
          "${mod}+Shift+space" = "floating toggle";

          "${mod}+x" = "move workspace to output right";
          "${mod}+r" = ''mode "${modeResize}"'';
          "${mod}+Shift+t" = ''mode "${modeSystem}"'';
          "${mod}+Shift+v" = "exec ${pkgs.wlprop}/bin/wlprop";
          "${mod}+q" = lib.mkIf cfg.copyqConfig.enable
            "exec ${pkgs.copyq}/bin/copyq toggle";
        };

        assigns = {
          "${workspace1}" = [ ];
          "${workspace2}" = [ ];
          "${workspace3}" = [ ];
          "${workspace4}" = [ ];
          "${workspace5}" = [ ];
          "${workspace6}" = [ ];
          "${workspace8}" = [ ];
          "${workspace9}" = [ ];
          "${workspace10}" = [ ];
        };

        modes = {
          "${modeSystem}" = {
            "l" = ''
              exec --no-startup-id ${swaylock} --color '${colorDarkGrey}', mode "default"'';
            "e" = ''exec --no-startup-id ${swaymsg} exit, mode "default"'';
            "s" = ''
              exec --no-startup-id ${swaylock} --color '${colorDarkGrey}' && sleep 1 && ${systemctl} suspend, mode "default"'';
            "h" =
              ''exec --no-startup-id ${systemctl} hibernate, mode "default"'';
            "r" = ''exec --no-startup-id ${systemctl} reboot, mode "default"'';
            "Shift+s" =
              ''exec --no-startup-id ${systemctl} poweroff -i, mode "default"'';
            "Shift+r" = ''
              exec --no-startup-id ${systemctl} reboot --firmware-setup, mode "default"'';
            # back to normal: Enter or Escape
            "Return" = ''mode "default"'';
            "Escape" = ''mode "default"'';
          };
          "${modeResize}" = {
            "j" = "resize shrink width 10 px";
            "k" = "resize grow height 10 px";
            "i" = "resize shrink height 10 px";
            "l" = "resize grow width 10 px ";
            "Left" = "resize shrink width 10 px";
            "Down" = "resize grow height 10 px ";
            "Up" = "resize shrink height 10 px ";
            "Right" = "resize grow width 10 px ";

            # back to normal: Enter or Escape or $mod+r
            "Return" = ''mode "default"'';
            "Escape" = ''mode "default"'';
            "${mod}+r" = ''mode "default"'';
          };
        };
      };
    };
  };
}
