{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim.plugins.noice = {
      enable = true;
    };
  };
}
