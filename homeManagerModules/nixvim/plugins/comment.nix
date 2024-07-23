{ config, lib, ... }:
let cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim.plugins.comment = {
      enable = true;
      settings = {
        opleader.line = "<C-b>";
        toggler.line = "<C-b>";
      };
    };
  };
}
