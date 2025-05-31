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
    programs.nixvim.plugins = {
      nvim-autopairs.enable = true;
      gitsigns = {
        enable = true;
        settings.signs = {
          add.text = "+";
          change.text = "~";
        };
      };
      colorizer = {
        enable = true;
        settings = {
          user_default_options.names = false;
        };
      };
      which-key = {
        enable = true;
      };
    };
  };
}
