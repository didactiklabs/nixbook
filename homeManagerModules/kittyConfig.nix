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
        whether to enable kittyConfig globally or not
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
          enableFishIntegration = config.customHomeManagerModules.fishConfig.enable or false;
        };
        settings = {
          shell =
            if (config.customHomeManagerModules.fishConfig.enable or false) then
              "${pkgs.fish}/bin/fish"
            else
              "${pkgs.zsh}/bin/zsh";
          copy_on_select = true;
          font_size = lib.mkForce "10.0";
          font_family = "Hack Nerd Font Bold";
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

          # Enable remote control for opencode.nvim
          allow_remote_control = true;
          listen_on = "unix:@mykitty";
        };
        keybindings = {
          # Tab management
          "ctrl+shift+enter" = "new_window_with_cwd";
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
      fish = {
        shellAliases = {
          sshs = ''
            sshs --template "kitty +kitten ssh {{#if user}}{{user}}@{{/if}}{{destination}}{{#if port}} -p{{port}}{{/if}}"
          '';
        };
        shellInit = ''
          if test "$TERM" = "xterm-kitty"
              alias ssh="env TERM=xterm-256color ssh"
          end
        '';
      };
      vscode = {
        profiles.default.userSettings = {
          "terminal.external.linuxExec" = "kitty";
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
    programs.niri = {
      settings = {
        binds = {
          "Mod+Return".action.spawn = [ "${pkgs.kitty}/bin/kitty" ];
        };
      };
    };
  };
}
