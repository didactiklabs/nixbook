{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  mainWallpaper = "${config.profileCustomization.mainWallpaper}";
  lockWallpaper = "${config.profileCustomization.lockWallpaper}";
  startup_audio = "${config.profileCustomization.startup_audio}";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  pidof = "${pkgs.sysvtools}/bin/pidof";
  hyprlock = "${pkgs.hyprlock}/bin/hyprlock";
  systemctl = "${pkgs.systemd}/bin/systemctl";
  loginctl = "${pkgs.systemd}/bin/loginctl";
  niri = "${pkgs.niri}/bin/niri";
  whatsong = pkgs.writeShellScriptBin "whatsong" ''
    song_info=$(${pkgs.playerctl}/bin/playerctl metadata --format '{{title}}   {{artist}}')
    echo "$song_info"
  '';

  # Use volume script from PATH (should be available when scripts module is enabled)
  # This assumes the scripts module is imported separately
  volume = pkgs.writeShellScriptBin "volume-niri" ''
    # Use the volume script from PATH or fall back to a simple implementation
    if command -v volume >/dev/null 2>&1; then
      exec volume "$@"
    else
      # Simple fallback using pamixer directly
      case "$1" in
        --inc)
          ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 3%+
          ;;
        --dec)
          ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_SINK@ 3%-
          ;;
        --toggle)
          ${pkgs.pamixer}/bin/pamixer -t
          ;;
        *)
          echo "Volume control: use --inc, --dec, or --toggle"
          ;;
      esac
    fi
  '';
in
{
  config = lib.mkIf cfg.niriConfig.enable {
    home.packages = [ whatsong ];

    # Enable hypridle for idle management (same as Hyprland config)
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd =
            if cfg.dmsConfig.enable then "dms ipc call lock lock" else "${pidof} ${hyprlock} || ${hyprlock}"; # avoid starting multiple hyprlock instances.
          before_sleep_cmd = "${loginctl} lock-session"; # lock before suspend.
          after_sleep_cmd = "${niri} msg action power-on-monitors"; # turn on monitors after sleep
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
            on-timeout = "${niri} msg action power-off-monitors"; # screen off when timeout has passed
            on-resume = "${niri} msg action power-on-monitors"; # screen on when activity is detected after timeout has fired.
          }

          {
            timeout = 600;
            on-timeout = "${systemctl} suspend"; # suspend pc
          }
        ];
      };
    };

    # Enable hyprlock for screen locking (same styling as Hyprland config)
    programs.hyprlock = lib.mkIf (!cfg.dmsConfig.enable) {
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
          font_family = "Roboto";
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
            font_family = "Roboto";
            position = "0, -300";
            halign = "center";
            valign = "top";
          }
          {
            text = "Logged in as $USER";
            # color = "$foreground";
            #color = rgba(255, 255, 255, 0.6)
            font_size = 25;
            font_family = "Roboto";
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
            font_family = "Roboto";
            position = "0, 10";
            halign = "center";
            valign = "bottom";
          }
        ];
      };
    };

    programs.niri = {
      settings = {
        prefer-no-csd = true;
        hotkey-overlay.skip-at-startup = true;

        screenshot-path = "~/Pictures/Screenshots/Screenshot-%Y-%m-%d-%H-%M-%S.png";

        environment = {
          "XDG_CURRENT_DESKTOP" = "niri";
          "XDG_SESSION_TYPE" = "wayland";
          "XDG_SESSION_DESKTOP" = "niri";
          "QT_AUTO_SCREEN_SCALE_FACTOR" = "1";
          "QT_QPA_PLATFORM" = "wayland;xcb";
          "QT_WAYLAND_DISABLE_WINDOWDECORATION" = "1";
          "QT_QPA_PLATFORMTHEME" = "qt6ct";
          "SDL_VIDEODRIVER" = "wayland";
          "_JAVA_AWT_WM_NONEREPARENTING" = "1";
          "CLUTTER_BACKEND" = "wayland";
          "GDK_BACKEND" = "wayland,x11";
          "NIXOS_OZONE_WL" = "1";
        };

        spawn-at-startup = [
          {
            command = [
              "${pkgs.mpg123}/bin/mpg123"
              startup_audio
            ];
          }
        ]
        ++ [
          {
            command = [
              "${pkgs.swaybg}/bin/swaybg"
              "-m"
              "fill"
              "-i"
              mainWallpaper
            ];
          }
        ]
        ++ [
          {
            command = [ "${pkgs.xwayland-satellite}/bin/xwayland-satellite" ];
          }
          {
            command = [ "systemctl --user import-environment XDG_SESSION_TYPE XDG_CURRENT_DESKTOP" ];
          }
          {
            command = [ "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP" ];
          }
        ];

        input = {
          keyboard = {
            xkb = {
              layout = "fr";
              options = "numpad:microsoft";
            };
          };

          touchpad = {
            tap = true;
            dwt = true;
            natural-scroll = true;
            click-method = "clickfinger";
          };

          focus-follows-mouse = {
            enable = true;
            max-scroll-amount = "10%";
          };
        };

        outputs = {
          "*" = {
            scale = 1.0;
            position = {
              x = 0;
              y = 0;
            };
          };
        };

        layout = {
          gaps = 10;
          center-focused-column = "never";
          preset-column-widths = [
            { proportion = 1.0 / 3.0; }
            { proportion = 1.0 / 2.0; }
            { proportion = 2.0 / 3.0; }
            { proportion = 4.0 / 5.0; }
          ];
          default-column-width = {
            proportion = 4.0 / 5.0;
          };
          focus-ring = {
            enable = true;
            width = 2;
            active.color = config.lib.stylix.colors.base0D;
            inactive.color = config.lib.stylix.colors.base03;
          };
          border = {
            enable = true;
            width = 1;
            active.color = config.lib.stylix.colors.base0D;
            inactive.color = config.lib.stylix.colors.base03;
          };
        };

        # layer-rules = [
        #   {
        #     matches = [ { namespace = "^wallpaper$"; } ];
        #     place-within-backdrop = true;
        #   }
        # ];

        window-rules = [
          {
            matches = [ { } ];
            opacity = 0.85;
            open-maximized = false;
            default-column-width = {
              proportion = 1.0 / 2.0;
            };
            geometry-corner-radius = {
              top-left = 12.0;
              top-right = 12.0;
              bottom-left = 12.0;
              bottom-right = 12.0;
            };
            clip-to-geometry = true;
            draw-border-with-background = false;
          }
          {
            matches = [ { app-id = "^mpv$"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { app-id = "^firefox$"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { app-id = "^org\\.mozilla\\.firefox$"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { app-id = "^firefox-esr$"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { app-id = "^imv$"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { app-id = "^com\\.github\\.iwalton3\\.jellyfin-media-player$"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { app-id = "^com\\.moonlight_stream\\.Moonlight$"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { title = "^ranger$"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { title = ".*Immich — Mozilla Firefox"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { title = ".*YouTube — Mozilla Firefox"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { title = ".*Jellyfin — Mozilla Firefox"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { title = ".*Facebook — Mozilla Firefox"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { title = ".*Instagram — Mozilla Firefox"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { title = ".*Nexus - Mods and community — Mozilla Firefox"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { title = ".*Imgur: The magic of the Internet — Mozilla Firefox"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { title = "^Discord Popout"; } ];
            opacity = 1.0;
          }
        ];

        animations = {
          slowdown = 1.0;

          window-open = {
            kind.spring = {
              damping-ratio = 0.8;
              stiffness = 1000;
              epsilon = 0.0001;
            };
          };

          window-close = {
            kind.spring = {
              damping-ratio = 0.8;
              stiffness = 1000;
              epsilon = 0.0001;
            };
          };

          horizontal-view-movement = {
            kind.spring = {
              damping-ratio = 1.0;
              stiffness = 800;
              epsilon = 0.0001;
            };
          };

          workspace-switch = {
            kind.spring = {
              damping-ratio = 1.0;
              stiffness = 1000;
              epsilon = 0.0001;
            };
          };

          window-movement = {
            kind.spring = {
              damping-ratio = 1.0;
              stiffness = 800;
              epsilon = 0.0001;
            };
          };

          window-resize = {
            kind.spring = {
              damping-ratio = 1.0;
              stiffness = 800;
              epsilon = 0.0001;
            };
          };

          config-notification-open-close = {
            kind.spring = {
              damping-ratio = 0.6;
              stiffness = 1000;
              epsilon = 0.001;
            };
          };
        };

        binds = {
          "Mod+A".action.close-window = { };

          # Show overview (global windows view)
          "Mod+Tab".action.toggle-overview = { };

          # Column navigation (left/right)
          "Mod+Left".action.focus-column-left = { };
          "Mod+Right".action.focus-column-right = { };

          # Workspace navigation (up/down - vertical scrolling)
          "Mod+Up".action.focus-workspace-up = { };
          "Mod+Down".action.focus-workspace-down = { };

          # Monitor navigation with Ctrl+Alt+arrows
          "Ctrl+Alt+Left".action.focus-monitor-left = { };
          "Ctrl+Alt+Right".action.focus-monitor-right = { };
          "Ctrl+Alt+Up".action.focus-monitor-up = { };
          "Ctrl+Alt+Down".action.focus-monitor-down = { };

          # Move column/window between monitors with Ctrl+Alt+Shift+arrows
          "Ctrl+Alt+Shift+Left".action.move-column-to-monitor-left = { };
          "Ctrl+Alt+Shift+Right".action.move-column-to-monitor-right = { };
          "Ctrl+Alt+Shift+Up".action.move-column-to-monitor-up = { };
          "Ctrl+Alt+Shift+Down".action.move-column-to-monitor-down = { };

          # Free up Shift+arrows for other uses (window/column movement)
          "Mod+Shift+Left".action.move-column-left = { };
          "Mod+Shift+Right".action.move-column-right = { };
          "Mod+Shift+Up".action.move-column-to-workspace-up = { };
          "Mod+Shift+Down".action.move-column-to-workspace-down = { };

          "Mod+Page_Down".action.focus-workspace-down = { };
          "Mod+Page_Up".action.focus-workspace-up = { };
          "Mod+U".action.focus-workspace-down = { };
          "Mod+I".action.focus-workspace-up = { };

          "Mod+Ctrl+Page_Down".action.move-column-to-workspace-down = { };
          "Mod+Ctrl+Page_Up".action.move-column-to-workspace-up = { };
          "Mod+Ctrl+U".action.move-column-to-workspace-down = { };
          "Mod+Ctrl+I".action.move-column-to-workspace-up = { };

          "Mod+Shift+Page_Down".action.move-workspace-down = { };
          "Mod+Shift+Page_Up".action.move-workspace-up = { };
          "Mod+Shift+U".action.move-workspace-down = { };
          "Mod+Shift+I".action.move-workspace-up = { };

          "Mod+E".action.consume-or-expel-window-left = { };

          # Window navigation within column (up/down with Ctrl)
          "Mod+Ctrl+Up".action.focus-window-up = { };
          "Mod+Ctrl+Down".action.focus-window-down = { };

          "Mod+R".action.switch-preset-column-width = { };
          "Mod+Z".action.maximize-column = { };
          "Mod+F".action.fullscreen-window = { };
          "Mod+C".action.center-column = { };

          # "Mod+Minus".action.set-column-width = "-10%";
          # "Mod+Plus".action.set-column-width = "+10%";

          # "Mod+Shift+Minus".action.set-window-height = "-10%";
          # "Mod+Shift+Plus".action.set-window-height = "+10%";

          # Screenshots (Wayland-compatible)
          "Print".action.spawn =
            if cfg.dmsConfig.enable then
              [
                "dms"
                "screenshot"
              ]
            else
              [
                "bash"
                "-c"
                "grim -g \"$(slurp)\" - | wl-copy && ${pkgs.libnotify}/bin/notify-send -h string:x-canonical-private-synchronous:sys-notify -u low -t 555 'Screenshot' 'Area copied to clipboard'"
              ];

          "Mod+Shift+E".action.quit = { };
          "Mod+Shift+P".action.power-off-monitors = { };

          "XF86MonBrightnessDown".action.spawn = [
            "${brightnessctl}"
            "set"
            "10%-"
          ];
          "XF86MonBrightnessUp".action.spawn = [
            "${brightnessctl}"
            "set"
            "+10%"
          ];

          # Audio controls
          "XF86AudioRaiseVolume".action.spawn =
            if cfg.dmsConfig.enable then
              [
                "${pkgs.wireplumber}/bin/wpctl"
                "set-volume"
                "@DEFAULT_SINK@"
                "3%+"
              ]
            else
              [
                "${volume}/bin/volume-niri"
                "--inc"
              ];
          "XF86AudioLowerVolume".action.spawn =
            if cfg.dmsConfig.enable then
              [
                "${pkgs.wireplumber}/bin/wpctl"
                "set-volume"
                "@DEFAULT_SINK@"
                "3%-"
              ]
            else
              [
                "${volume}/bin/volume-niri"
                "--dec"
              ];
          "XF86AudioMute".action.spawn = [
            "${volume}/bin/volume-niri"
            "--toggle"
          ];
        }
        // (
          if cfg.dmsConfig.enable then
            {
              "Mod+N".action.spawn = [
                "dms"
                "ipc"
                "call"
                "notifications"
                "toggle"
              ];
            }
          else
            { }
        )
        // (
          if cfg.dmsConfig.enable then
            if cfg.dmsConfig.showDock then
              {
                "Mod+B".action.spawn = [
                  "bash"
                  "-c"
                  "dms ipc call bar toggle index 0 && dms ipc call dock toggle"
                ];
              }
            else
              {
                "Mod+B".action.spawn = [
                  "dms"
                  "ipc"
                  "call"
                  "bar"
                  "toggle"
                  "index"
                  "0"
                ];
              }
          else
            { }
        )
        // (
          if cfg.dmsConfig.enable then
            {
              "Mod+Q".action.spawn = [
                "dms"
                "ipc"
                "call"
                "clipboard"
                "toggle"
              ];
            }
          else
            { }
        )
        // (
          if cfg.dmsConfig.enable then
            {
              "Mod+D".action.spawn = [
                "dms"
                "ipc"
                "call"
                "spotlight"
                "toggle"
              ];
            }
          else
            { }
        )
        // (
          if cfg.dmsConfig.enable then
            {
              "Mod+L".action.spawn = [
                "dms"
                "ipc"
                "call"
                "powermenu"
                "toggle"
              ];
            }
          else
            { }
        )
        // (lib.optionalAttrs cfg.fcitx5Config.enable {
          "Ctrl+Space".action.spawn = [
            "${pkgs.fcitx5}/bin/fcitx5-remote"

            "-t"
          ];
        })
        // (
          if cfg.dmsConfig.enable then
            {
              "Mod+I".action.spawn = [
                "dms"
                "ipc"
                "call"
                "inhibit"
                "toggle"
              ];
            }
          else
            { }
        )
        // (
          if cfg.dmsConfig.enable then
            {
              "Mod+W".action.spawn = [
                "dms"
                "ipc"
                "call"
                "dankdash"
                "wallpaper"
              ];
            }
          else
            { }
        )
        // (
          if cfg.dmsConfig.enable then
            {
              "Mod+O".action.spawn = [
                "dms"
                "ipc"
                "call"
                "dash"
                "toggle"
                "overview"
              ];
            }
          else
            { }
        )
        // (
          if cfg.dmsConfig.enable then
            {
              "Mod+Space".action.spawn = [
                "dms"
                "ipc"
                "call"
                "widget"
                "toggle"
                "sathiAi"
              ];
            }
          else
            { }
        );
      };
    };
  };
}
