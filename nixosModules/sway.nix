{ config, lib, ... }:
let cfg = config.customNixOSModules;
in {
  imports = [ ];
  config = lib.mkIf cfg.sway.enable { programs.sway.enable = true; };
  options.customNixOSModules.sway = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable sway config globally or not
      '';
    };
  };
}
