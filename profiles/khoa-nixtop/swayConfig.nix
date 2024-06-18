{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
  swaymsg = "${pkgs.sway}/bin/swaymsg";
  mod = "Mod1";
  sunshine = "${pkgs.sunshine}/bin/sunshine";
in {
  config = lib.mkIf cfg.sway.enable {
    services.swayidle = {
      enable = lib.mkForce false;
    };
    wayland.windowManager.sway.config.keybindings = lib.filterAttrsRecursive (name: value: value != null) {
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
        exec $HOME/.config/rofiScripts/rofiLockScript.sh ${rofiPowermenuStyle} "${loginctl} lock-session $XDG_SESSION_ID"
      '';
      "${mod}+d" = lib.mkIf cfg.rofiConfig.enable ''
        exec "${rofi-wayland} -show drun -theme $HOME/.config/rofi/launchers/${rofiLauncherType}/${rofiLauncherStyle}.rasi"
      '';
      ## To allow a keybinding to be executed while the lockscreen is active add the --locked parameter to bindsym.
      # Audio
      "--locked ${mod}+equal" = "exec ${playerctl} next";
      "--locked ${mod}+minus" = "exec ${playerctl} previous";
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
      "${mod}+p" = "scratchpad show";
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
      "${mod}+q" = lib.mkIf cfg.copyqConfig.enable "exec ${pkgs.copyq}/bin/copyq toggle";
    };
    wayland.windowManager.sway.extraConfig = ''
      exec ${swaymsg} create_output HEADLESS-1 mode 3840x2160 position 5000,2000
      exec ${swaymsg} output HEADLESS-1 mode 3840x2160 position 5000,2000
      exec ${swaymsg} exec ${sunshine}
    '';
    wayland.windowManager.sway.extraSessionCommands = ''
      export WLR_BACKENDS="headless,libinput"
    '';
  };
}
