{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  options.customHomeManagerModules.stylixConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable stylix globally or not
      '';
    };
  };
  config = lib.mkIf cfg.stylixConfig.enable {
    stylix = {
      enable = true;
      polarity = "dark";
      image = config.profileCustomization.mainWallpaper;
    };
  };
}
