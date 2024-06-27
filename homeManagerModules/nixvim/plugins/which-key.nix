{
  config,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim = {
      plugins.which-key = {
        enable = true;
        hidden = [
          "<silent>"
          "<cmd>"
          "<Cmd>"
          "<CR>"
          "^:"
          "^ "
          "^call "
          "^lua "
        ];
      };
      opts = {
        timeout = true;
        timeoutlen = 300;
      };
    };
  };
}
