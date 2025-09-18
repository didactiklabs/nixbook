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
        {
          mode = "n";
          key = "<leader>c";
          action = ":Neotree toggle<CR>";
          options.silent = true;
        }
        {
          mode = "n";
          key = "<leader>nt";
          action.__raw = ''
            function()
              local neotree = require("neo-tree.command")
              local manager = require("neo-tree.sources.manager")
              local renderer = require("neo-tree.ui.renderer")
              
              local state = manager.get_state("filesystem")
              if state.winid and vim.api.nvim_win_is_valid(state.winid) then
                local current_width = vim.api.nvim_win_get_width(state.winid)
                local new_width = current_width <= 25 and 40 or 20
                vim.api.nvim_win_set_width(state.winid, new_width)
              end
            end
          '';
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
