{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  # Import niri-flake for the validated-config-for function
  # (same pattern as nixosModules/niri.nix)
  sources = import ../../npins;
  niri-flake =
    (import sources.flake-compat {
      src = sources.niri-flake;
    }).defaultNix;
  mainWallpaper = config.stylix.image;
  lockWallpaper = config.stylix.image;
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

  wpctl = "${pkgs.wireplumber}/bin/wpctl";
  pixelateAnimations = import ./pixelateAnimations.nix;

  # What niri shows before any client has drawn (the first frames after the
  # login screen): nixbook-shell's loading screen background, so the handover
  # to its splash is seamless (BootSplashArt.qml): Persona's frame colour
  # (themes.json), another theme's palette background, or the shell's default
  # Material background.
  shellSettings = config.programs.nixbook-shell.settings or { };
  shellTheme = (import ../../nixbook-shell/lib.nix { inherit lib; }).themeOf shellSettings;
  splashBackground =
    if !(config.programs.nixbook-shell.enable or false) then
      "#141313"
    else if shellTheme.id == "persona" then
      shellTheme.variantPalette.frame
    else if shellTheme.palette != null then
      shellTheme.palette.background
    else
      "#141313";
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
            if cfg.dmsConfig.enable then
              "dms ipc call lock lock"
            else if cfg.nixbookShellConfig.enable then
              "nixbook-shell ipc call lock activate"
            else
              "${pidof} ${hyprlock} || ${hyprlock}"; # avoid starting multiple hyprlock instances.
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

    # Enable hyprlock for screen locking (same styling as Hyprland config).
    # Only used as the fallback locker: DMS and nixbook-shell each ship their own.
    programs.hyprlock = lib.mkIf (!(cfg.dmsConfig.enable || cfg.nixbookShellConfig.enable)) {
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

    # Enable background blur by appending raw KDL to the validated niri config.
    # The niri-flake module on main branch doesn't yet have blur options,
    # so we use the validated-config-for escape hatch.
    # Remove this override once niri-flake merges blur support (PR #1731).
    # See: https://github.com/sodiboo/niri-flake/issues/1721
    xdg.configFile.niri-config.source =
      let
        inherit (config.programs.niri) finalConfig package;
      in
      lib.mkForce (
        niri-flake.lib.internal.validated-config-for pkgs package ''
          ${finalConfig}

          blur {
              passes 3
              offset 3.0
              noise 0.02
              saturation 1.5
          }

          // Every window, tiled or floating, uses xray blur: the wallpaper
          // (Background layer) blurred once and cached, instead of re-blurring
          // whatever is behind each window whenever it changes (measured: niri
          // 41% -> 25% of the GPU with the shell's visualizer running). With a
          // live wallpaper, windows show its blurred still frame (the video
          // plays on the Bottom layer, see the shell's live-wallpaper.sh).
          window-rule {
              background-effect {
                  blur true
                  xray true
              }
          }

        ''
      );

    programs.niri = {
      settings = {
        # niri draws its own cursor and exports it (XCURSOR_THEME/SIZE) to what
        # it spawns; niri-flake defaults it to the "default" theme, so follow
        # the Home Manager cursor (Stylix's, or a profile's own).
        cursor = lib.mkIf (config.home.pointerCursor.enable or false) {
          theme = config.home.pointerCursor.name;
          inherit (config.home.pointerCursor) size;
        };
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
        ++ lib.optionals (!cfg.nixbookShellConfig.enable) [
          # nixbook-shell paints its own wallpaper layer (and owns wallpaper
          # switching via its Settings panel), so swaybg would just burn a
          # second full-screen surface underneath it.
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
        # No xwayland-satellite or environment-import entries: niri (>= 25.08)
        # spawns xwayland-satellite itself on the first X11 client (found in
        # PATH via nixosModules/niri.nix) and restarts it if it dies, and
        # imports WAYLAND_DISPLAY, DISPLAY, XDG_CURRENT_DESKTOP,
        # XDG_SESSION_TYPE and NIRI_SOCKET into systemd and D-Bus on start.
        ++ [
          {
            # NM secret agent — handles WPA Enterprise credential prompts and
            # shows a tray icon for network status/connection management.
            command = [
              "${pkgs.networkmanagerapplet}/bin/nm-applet"
            ];
          }
        ];

        input = {
          keyboard = {
            numlock = true;
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

        gestures = {
          # Disable triggering the overview when the mouse hits a screen corner.
          hot-corners.enable = false;
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
          background-color = splashBackground;
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
            matches = [ { app-id = "^qemu$"; } ];
            opacity = 1.0;
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
            matches = [ { app-id = "^zoom$"; } ];
            opacity = 1.0;
          }
          {
            matches = [
              {
                app-id = "^vesktop$";
                title = "^$";
              }
            ];
            opacity = 1.0;
          }
          # nixbook-shell's Settings window (a normal app window): open floating like
          # a dialog; Mod+V tiles it.
          {
            matches = [
              {
                app-id = "^org\\.quickshell$";
                title = "^Shell settings$";
              }
            ];
            open-floating = true;
          }
          # Vesktop's floating video-call popup stays opaque. The main window
          # keeps its normal transparency when floated: floating windows get
          # the same opacity rules as tiled ones, and the main window is told
          # apart by its "(n) Discord | #channel | server" title.
          {
            matches = [
              {
                app-id = "^vesktop$";
                is-floating = true;
              }
            ];
            excludes = [ { title = "Discord \\| "; } ];
            opacity = 1.0;
          }
          {
            matches = [ { app-id = "^zen-twilight$"; } ];
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
            matches = [ { app-id = "^org\\.darktable\\.darktable$"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { app-id = "^ansel$"; } ];
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
            matches = [ { title = ".*Jellyfin.*"; } ];
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
          {
            matches = [ { app-id = "^thunderbird$"; } ];
            opacity = 1.0;
          }
          {
            matches = [ { app-id = "^com\\.github\\.th_ch\\.youtube_music$"; } ];
            opacity = 1.0;
          }
        ];

        animations = pixelateAnimations.animations // {
          slowdown = 1.0;

          horizontal-view-movement = {
            kind.spring = {
              damping-ratio = 1.0;
              stiffness = 800;
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

          # Floating window controls
          "Mod+V".action.toggle-window-floating = { };
          "Mod+Shift+V".action.switch-focus-between-floating-and-tiling = { };

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
            else if cfg.nixbookShellConfig.enable then
              [
                "nixbook-shell"
                "ipc"
                "call"
                "region"
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
          "XF86AudioRaiseVolume".action.spawn = [
            "${wpctl}"
            "set-volume"
            "@DEFAULT_SINK@"
            "3%+"
          ];
          "XF86AudioLowerVolume".action.spawn = [
            "${wpctl}"
            "set-volume"
            "@DEFAULT_SINK@"
            "3%-"
          ];
          "XF86AudioMute".action.spawn = [
            "${wpctl}"
            "set-mute"
            "@DEFAULT_SINK@"
            "toggle"
          ];
        }
        // (
          if cfg.dmsConfig.enable then
            {
              "Mod+N".action.spawn = [
                "dms"
                "ipc"
                "call"
                "notepad"
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
        // (
          # NOTE: Ctrl+Space is intentionally NOT bound here. fcitx5 handles
          # it internally as "enumerate forward" to cycle through all input
          # methods (see homeManagerModules/fcitx5Config.nix). Binding it at
          # the compositor level would shadow that and only toggle fcitx
          # on/off via `fcitx5-remote -t`.
          { })
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
        )
        // (
          # nixbook-shell panels. Upstream drives these with Hyprland global
          # shortcuts, which are inactive under niri (see
          # services/CompositorGlobalShortcut.qml), so everything goes through
          # the shell's IPC instead. Layout mirrors the DMS binds above so the
          # muscle memory carries over.
          lib.optionalAttrs cfg.nixbookShellConfig.enable (
            lib.mapAttrs
              (_name: call: {
                action.spawn = [
                  "nixbook-shell"
                  "ipc"
                  "call"
                ]
                ++ call;
              })
              {
                "Mod+B" = [
                  "bar"
                  "toggle"
                ];
                "Mod+D" = [
                  "search"
                  "toggle"
                ];
                "Mod+O" = [
                  "search"
                  "workspacesToggle"
                ];
                "Mod+Q" = [
                  "search"
                  "clipboardToggle"
                ];
                "Mod+L" = [
                  "session"
                  "toggle"
                ];
                "Mod+N" = [
                  "sidebarRight"
                  "toggle"
                ];
                "Mod+Space" = [
                  "sidebarLeft"
                  "toggle"
                ];
                "Mod+W" = [
                  "wallpaperSelector"
                  "toggle"
                ];
                "Mod+Escape" = [
                  "settings"
                  "toggle"
                ];
              }
          )
        )
        // (
          # Mod+I: idle-inhibit parity with DMS. nixbook-shell has the feature
          # (services/Idle.qml) but exposes no IpcHandler for it — only a quick
          # toggle in the right sidebar — so drive hypridle directly instead,
          # which is what actually locks/suspends this machine. Shadows niri's
          # focus-workspace-up on Mod+I exactly like the DMS bind does.
          lib.optionalAttrs cfg.nixbookShellConfig.enable {
            "Mod+I".action.spawn = [
              "bash"
              "-c"
              ''
                if ${systemctl} --user is-active --quiet hypridle; then
                  ${systemctl} --user stop hypridle && \
                    ${pkgs.libnotify}/bin/notify-send -h string:x-canonical-private-synchronous:idle-inhibit -u low -t 1500 'Idle inhibited' 'Auto-lock and suspend are off'
                else
                  ${systemctl} --user start hypridle && \
                    ${pkgs.libnotify}/bin/notify-send -h string:x-canonical-private-synchronous:idle-inhibit -u low -t 1500 'Idle inhibitor off' 'Auto-lock and suspend are back on'
                fi
              ''
            ];
          }
        );
      };
    };
  };
}
