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
    programs.niri.settings.window-rules = lib.mkAfter [
      {
        matches = [ { is-active = true; } ];
        opacity = 0.96;
      }
      {
        matches = [ { is-active = false; } ];
        opacity = 0.92;
      }
    ];
    programs.niri.settings.outputs = lib.mkForce {
      "*" = {
        scale = 1.0;
        position = {
          x = 0;
          y = 0;
        };
      };

      # Configuration for Home bellow
      "eDP-1" = {
        scale = 2;
        position = {
          x = 3000;
          y = 0;
        };
      };
      # AOC monitor (center) - using model name for stability
      "PNP(AOC) 32G1WG4 0x000008DA" = {
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60.0;
        };
        position = {
          x = 1080;
          y = 0;
        };
      };
      # BenQ ZOWIE monitor (left, vertical) - using model name for stability
      "PNP(BNQ) ZOWIE RL LCD X6G00926SL0" = {
        mode = {
          width = 1920;
          height = 1080;
        };
        transform.rotation = 90;
        position = {
          x = 0;
          y = 0;
        };
      };
    };
  };
}
