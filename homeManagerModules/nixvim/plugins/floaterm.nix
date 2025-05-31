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
    programs.nixvim.plugins.floaterm = {
      enable = true;
      settings = {
        width = 0.8;
        height = 0.8;
        title = "";
        keymap_toggle = "<leader>,";
      };
    };
  };
}
