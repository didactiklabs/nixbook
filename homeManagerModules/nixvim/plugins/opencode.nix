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
        providers = {
          terminal = {
            enable = true;
          };
        };
      };
    };
    programs.nixvim.plugins.opencode = {
      enable = true;
    };
  };
}
