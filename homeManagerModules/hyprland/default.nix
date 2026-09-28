{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  imports = [
    ./hyprlandConfig.nix
    ./hyprlockConfig.nix
  ];
  config = lib.mkIf cfg.hyprlandConfig.enable { };
  options.customHomeManagerModules.hyprlandConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable per-user Hyprland compositor configuration.

        Manages the full Hyprland user environment via Home Manager:
          - hyprlandConfig.nix: wayland.windowManager.hyprland settings —
            keybindings, animations, decorations, workspace rules,
            monitor layout, exec-once startup commands, environment
            variables, and input device configuration
          - hyprlockConfig.nix: hypridle (locks through DMS or nixbook-shell
            when enabled) and the fallback hyprlock screen locker —
            background blur, clock widget, password input field styling
            (not installed under nixbook-shell, which ships its own)

        Requires the system-level nixosModules/hyprland.nix to be enabled
        (customNixOSModules.hyprland.enable = true).

        Used on: totoro (fallback), nishinoya (fallback).
      '';
    };
  };
}
