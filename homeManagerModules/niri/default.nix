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
        Whether to enable Niri config globally or not.
        Niri is a scrollable-tiling Wayland compositor.
      '';
    };
  };
}
