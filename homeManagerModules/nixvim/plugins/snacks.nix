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
    programs.nixvim.plugins.snacks = {
      enable = true;
      settings = {
        terminal = {
          enabled = true;
        };
        input = {
          enabled = true;
        };
        picker = {
          enabled = true;
        };
      };
    };
  };
}
