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
  options.customHomeManagerModules.networkManagerApplet = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = !cfg.dmsConfig.enable;
      description = "Enable network manager applet";
    };
  };

  config = lib.mkIf cfg.networkManagerApplet.enable {
    services.network-manager-applet.enable = true;
  };
}
