{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules.ghosttyConfig;
in
{
  options.customHomeManagerModules.ghosttyConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable ghosttyConfig globally or not
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    programs = {
      ghostty = {
        enable = true;
        enableZshIntegration = true;
        installBatSyntax = true;
        installVimSyntax = true;
      };
      ranger = {
        extraConfig = ''
          set preview_images true
          set preview_images_method kitty
          set preview_files true
        '';
      };

      vscode = {
        userSettings = {
          "terminal.external.linuxExec" = "ghostty";
        };
      };
    };
    home.file = {
      ".config/xfce4/helpers.rc".text = ''
        TerminalEmulator=ghostty
      '';
    };
    wayland.windowManager.hyprland = {
      settings = {
        bind = [
          "$mod, RETURN, exec, ${pkgs.ghostty}/bin/ghostty"
        ];
      };
    };
    wayland.windowManager.sway = {
      config = {
        terminal = "${pkgs.ghostty}/bin/ghostty";
        keybindings = {
          "Mod4+Return" = "exec ${pkgs.ghostty}/bin/ghostty";
        };
      };
    };
  };
}
