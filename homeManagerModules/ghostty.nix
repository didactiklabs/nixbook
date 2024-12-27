{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.desktopApps;
  sources = import ../npins;
  ghostty = import sources.ghostty {
    config = {
      allowUnfree = true;
      allowUnfreePredicate = true;
    };
  };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ ghostty.ghostty ];
  };
}
