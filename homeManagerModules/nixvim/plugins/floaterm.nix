{ config, lib, ... }:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim.plugins.floaterm = {
      enable = true;
      width = 0.8;
      height = 0.8;
      title = "";
      keymaps.toggle = "<leader>,";
    };
  };
}
