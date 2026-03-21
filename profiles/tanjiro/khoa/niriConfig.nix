{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.niriConfig.enable {
    programs.niri.settings.outputs = lib.mkForce {
      "eDP-1" = lib.mkForce {
        scale = 1.20;
        position = {
          x = 0;
          y = 750;
        };
      };
      "DP-9" = lib.mkForce {
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60.0;
        };
        position = {
          x = 1881;
          y = 237;
        };
      };
      "DP-10" = lib.mkForce {
        mode = {
          width = 2560;
          height = 1440;
          refresh = 143.91;
        };
        position = {
          x = 3801;
          y = 0;
        };
      };
    };
  };
}
