{
  config,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim.plugins.trouble = {
      enable = true;
    };
  };
}
