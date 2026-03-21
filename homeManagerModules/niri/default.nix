{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  imports = [
    ./niriConfig.nix
  ];
  config = lib.mkIf cfg.niriConfig.enable {
  };
  options.customHomeManagerModules.niriConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable per-user Niri compositor configuration.

        Manages the full Niri scrollable-tiling user environment via Home Manager:
          - niriConfig.nix: programs.niri.settings — keybindings, window rules,
            output/monitor configuration (via kanshi-style prefer-output rules),
            input device settings, animations, environment variables,
            spawn-at-startup commands, and workspace configuration

        Niri arranges windows in an infinite horizontal scrollable strip.
        Key concepts: columns (vertical stacks), workspaces (virtual desktops),
        and outputs (physical monitors).

        Requires the system-level nixosModules/niri.nix to be enabled
        (customNixOSModules.niri.enable = true).

        Used on: totoro (primary), nishinoya (primary).
      '';
    };
  };
}
