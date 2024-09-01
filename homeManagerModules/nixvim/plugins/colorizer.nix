{ config, lib, ... }:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim.plugins = {
      nvim-autopairs.enable = true;
      gitsigns = {
        enable = true;
        settings.signs = {
          add.text = "+";
          change.text = "~";
        };
      };
      nvim-colorizer = {
        enable = true;
        userDefaultOptions.names = false;
      };
      which-key = {
        enable = true;
      };
    };
  };
}
