{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  sources = import ../../npins;
  niri-flake-src = sources.niri-flake;
  niri-flake =
    (import sources.flake-compat {
      src = niri-flake-src;
    }).defaultNix;
  mainWallpaper = "${config.profileCustomization.mainWallpaper}";
  startup_audio = "${config.profileCustomization.startup_audio}";
  rofi-wayland = "${pkgs.rofi-wayland}/bin/rofi";
  waybar = "${pkgs.waybar}/bin/waybar";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  grimshot = "${pkgs.grimblast}/bin/grimblast";
  pidof = "${pkgs.sysvtools}/bin/pidof";

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
          {
            command = [ "${waybar}" ];
          }
          {
            command = [
              "${pkgs.swaybg}/bin/swaybg"
              "-m"
              "fill"
              "-i"
              mainWallpaper
            ];
          }
          {
            command = [
              "${pkgs.bash}/bin/bash"
              "-c"
              "sleep 2 && ${pkgs.swaynotificationcenter}/bin/swaync-client --reload-css && ${pkgs.swaynotificationcenter}/bin/swaync-client --reload-config"
            ];
          }
          {
            command = [ "${pkgs.xwayland-satellite}/bin/xwayland-satellite" ];
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

        layer-rules = [
          {
            matches = [ { namespace = "^wallpaper$"; } ];
            place-within-backdrop = true;
          }
        ];

        window-rules = [
          {
            matches = [ { } ];
            opacity = 0.85;
            open-maximized = false;
            default-column-width = {
              proportion = 4.0 / 5.0;
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
            matches = [ { app-id = "^com\\.github\\.hluk\\.copyq$"; } ];
            default-column-width = {
              proportion = 0.4;
            };
            open-floating = true;
          }
          {
            matches = [ { app-id = "^mpv$"; } ];
            block-out-from = "screen-capture";
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
            block-out-from = "screen-capture";
            opacity = 1.0;
          }
          {
            matches = [ { app-id = "^com\\.github\\.iwalton3\\.jellyfin-media-player$"; } ];
            block-out-from = "screen-capture";
            opacity = 1.0;
          }
          {
            matches = [ { app-id = "^com\\.moonlight_stream\\.Moonlight$"; } ];
            block-out-from = "screen-capture";
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

          "Mod+Comma".action.consume-window-into-column = { };
          "Mod+Period".action.expel-window-from-column = { };

          "Mod+R".action.switch-preset-column-width = { };
          "Mod+Z".action.maximize-column = { };
          "Mod+F".action.fullscreen-window = { };
          "Mod+C".action.center-column = { };

          # "Mod+Minus".action.set-column-width = "-10%";
          # "Mod+Plus".action.set-column-width = "+10%";

          # "Mod+Shift+Minus".action.set-window-height = "-10%";
          # "Mod+Shift+Plus".action.set-window-height = "+10%";

          # Screenshots (Wayland-compatible)
          "Print".action.spawn = [
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
          "XF86AudioRaiseVolume".action.spawn = [
            "${volume}/bin/volume-niri"
            "--inc"
          ];
          "XF86AudioLowerVolume".action.spawn = [
            "${volume}/bin/volume-niri"
            "--dec"
          ];
          "XF86AudioMute".action.spawn = [
            "${volume}/bin/volume-niri"
            "--toggle"
          ];

          "Mod+N".action.spawn = [
            "${pkgs.swaynotificationcenter}/bin/swaync-client"
            "-t"
          ];
          "Mod+B".action.spawn = [
            "${pkgs.toybox}/bin/pkill"
            "-SIGUSR1"
            "waybar"
          ];
        }
        // (lib.optionalAttrs cfg.copyqConfig.enable {
          "Mod+Q".action.spawn = [
            "${pkgs.copyq}/bin/copyq"
            "toggle"
          ];
        })
        // (lib.optionalAttrs cfg.rofiConfig.enable {
          "Mod+D".action.spawn = [
            "${rofi-wayland}"
            "-show"
            "drun"
            "-theme"
            ".config/rofi/launchers/type-1/style-landscape.rasi"
          ];
          "Mod+L".action.spawn = [
            "bash"
            "-c"
            "~/.config/rofiScripts/rofiLockScript.sh style-1"
          ];
        });
      };
    };
  };
}
