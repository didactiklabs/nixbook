{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules.kittyConfig;
in
{
  options.customHomeManagerModules.kittyConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Kitty terminal emulator configuration.

        Kitty is a GPU-accelerated terminal emulator with tiling support.

        Configures:
          Appearance & behaviour:
            - Roboto Mono 10pt font, copy-on-select, no OS window close prompt
            - Cursor blink interval 0.5s, cursor trail effect with smooth decay
            - Bottom powerline tab bar (shown even for a single tab)
            - Splits layout only (kitty's built-in window splitting, no tmux needed)

          Keybindings:
            - Ctrl+Shift+S / Ctrl+Shift+Enter — vertical / horizontal split
            - Ctrl+Shift+W — close tab; Ctrl+Shift+←/→ — previous/next tab
            - Alt+←/→/↑/↓ — navigate between splits
            - Shift+←/→/↑/↓ — move/reorder splits

          Compositor integration (spawn kitty on Mod+Return):
            - Hyprland: $mod+RETURN keybind
            - Niri: Mod+Return bind
            - Sway: terminal = kitty, Mod4+Return keybind

          Shell integration:
            - Zsh integration enabled inside kitty
            - `ssh` aliased to TERM=xterm-256color inside kitty (fixes remote terms)
            - `sshs` alias uses kitty+kitten ssh for seamless remote kitty sessions

          VSCode integration:
            - Sets kitty as the external terminal (terminal.external.linuxExec)

          ranger:
            - Configures image previews via the kitty graphics protocol
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    home.file = {
      ".config/xfce4/helpers.rc".text = ''
        TerminalEmulator=kitty
      '';
    };
    programs = {
      kitty = {
        enable = true;
        shellIntegration = {
          enableZshIntegration = true;
        };
        settings = {
          shell = "${pkgs.zsh}/bin/zsh";
          copy_on_select = true;
          font_size = lib.mkForce "10.0";
          font_family = "Roboto Mono";
          confirm_os_window_close = 0;
          cursor_blink_interval = "0.5";
          mouse_hide_wait = "3.0";

          # Tab bar configuration
          tab_bar_edge = "bottom";
          tab_bar_style = "powerline";
          tab_powerline_style = "round";
          tab_title_template = "{title}{' :{}:'.format(num_windows) if num_windows > 1 else ''}";
          tab_bar_min_tabs = 1; # Show tab bar even with single tab

          # Cursor trail effect
          cursor_trail = 1;
          cursor_trail_decay = "0.1 0.8";
          cursor_trail_start_on = "key_or_mouse";
          enabled_layouts = "splits";
        };

        keybindings = {
          # Tab management
          "ctrl+shift+s" = "launch --location=vsplit --cwd=current";
          "ctrl+shift+enter" = "launch --location=hsplit --cwd=current";
          "ctrl+shift+w" = "close_tab";
          "ctrl+shift+right" = "next_tab";
          "ctrl+shift+left" = "previous_tab";

          # Window/split navigation
          "alt+left" = "neighboring_window left";
          "alt+right" = "neighboring_window right";
          "alt+up" = "neighboring_window up";
          "alt+down" = "neighboring_window down";

          # Move/reorder split windows
          "shift+left" = "move_window left";
          "shift+right" = "move_window right";
          "shift+up" = "move_window up";
          "shift+down" = "move_window down";
        };
      };
      ranger = {
        extraConfig = ''
          set preview_images true
          set preview_images_method kitty
          set preview_files true
        '';
      };
      zsh = {
        shellAliases = {
          sshs = ''
            sshs --template "kitty +kitten ssh {{#if user}}{{user}}@{{/if}}{{destination}}{{#if port}} -p{{port}}{{/if}}"
          '';
        };
        initContent = ''
          [[ "$TERM" == "xterm-kitty" ]] && alias ssh="TERM=xterm-256color ssh"
        '';
      };
      vscode = {
        profiles.default.userSettings = {
          "terminal.external.linuxExec" = "kitty";
        };
      };
      niri = {
        settings = {
          binds = {
            "Mod+Return".action.spawn = [ "${pkgs.kitty}/bin/kitty" ];
          };
        };
      };
    };
    wayland.windowManager.hyprland = {
      settings = {
        bind = [
          "$mod, RETURN, exec, ${pkgs.kitty}/bin/kitty"
        ];
      };
    };
    wayland.windowManager.sway = {
      config = {
        terminal = "${pkgs.kitty}/bin/kitty";
        keybindings = {
          "Mod4+Return" = "exec ${pkgs.kitty}/bin/kitty";
        };
      };
    };
  };
}
