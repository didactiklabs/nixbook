{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  sources = import ../../../npins;
  plugin-99 = pkgs.vimUtils.buildVimPlugin {
    name = "99";
    src = sources."99";
  };
in
{
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim = {
      extraPlugins = [
        plugin-99
      ];

      extraConfigLua = ''
        require("99").setup({
          provider = require("99").Providers.OpenCodeProvider,
          model = "google/gemini-3-flash-preview",
          completion = {
            source = "cmp",
          },
          tmp_dir = "./.tmp",
        })
      '';

      keymaps = [
        {
          mode = "v";
          key = "<leader>9v";
          action.__raw = ''function() require("99").visual() end'';
          options.desc = "99: Visual";
        }
        {
          mode = "n";
          key = "<leader>9x";
          action.__raw = ''function() require("99").stop_all_requests() end'';
          options.desc = "99: Stop all requests";
        }
        {
          mode = "n";
          key = "<leader>9s";
          action.__raw = ''function() require("99").search() end'';
          options.desc = "99: Search";
        }
        {
          mode = "n";
          key = "<leader>9m";
          action.__raw = ''function() require("99.extensions.telescope").select_model() end'';
          options.desc = "99: Select model";
        }
        {
          mode = "n";
          key = "<leader>9p";
          action.__raw = ''function() require("99.extensions.telescope").select_provider() end'';
          options.desc = "99: Select provider";
        }
      ];
    };
  };
}
