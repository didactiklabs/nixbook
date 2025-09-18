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
        position = "center";
        width = 0.9;
        height = 0.9;
        title = "";
        keymap_toggle = "<leader>,";
        shell = if (cfg.fishConfig.enable or false) then "fish" else "zsh";
      };
    };
  };
}
