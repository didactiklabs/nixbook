{ config, lib, ... }:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim = {
      keymaps = [
        {
          mode = "n";
          key = "<leader>t";
          action = ":TroubleToggle<CR>";
          options.silent = true;
        }
        {
          mode = "n";
          key = "<leader>y";
          action = ":Trouble<CR>";
          options.silent = true;
        }
      ];
      plugins.trouble = {
        enable = true;
      };
    };
  };
}
