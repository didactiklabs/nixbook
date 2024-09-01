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
          key = "<leader>n";
          action = ":Neotree action=focus reveal<CR>";
          options.silent = true;
        }
      ];

      plugins.neo-tree = {
        enable = true;
        enableRefreshOnWrite = true;
        closeIfLastWindow = true;
        window = {
          width = 20;
          autoExpandWidth = true;
        };
      };
    };
  };
}
