{ config, lib, ... }:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim = {
      plugins.copilot-cmp = {
        enable = true;
      };
      plugins.copilot-lua = {
        enable = true;
        suggestion = {
          enabled = false;
        };
        panel = {
          enabled = false;
        };
      };
      extraConfigLua = ''
        require("copilot").setup({
          suggestion = { enabled = false },
          panel = { enabled = false },
        })
      '';
    };
  };
}
