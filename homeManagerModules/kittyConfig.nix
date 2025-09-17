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
        shellIntegration.enableZshIntegration = true;
        settings = {
          copy_on_select = true;
          font_size = lib.mkForce "10.0";
          font_family = "Hack Nerd Font Bold";
          confirm_os_window_close = 0;
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
