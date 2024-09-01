{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.bluetooth;
in
{
  options.customHomeManagerModules.bluetooth = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable bluetooth applet for the user or not
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.blueman-applet.enable = true;
    home.packages = [ pkgs.blueman ];
  };
}
