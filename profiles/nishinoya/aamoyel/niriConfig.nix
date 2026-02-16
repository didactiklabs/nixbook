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
  };
}
