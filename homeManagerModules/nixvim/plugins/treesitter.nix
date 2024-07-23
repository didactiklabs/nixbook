{ config, lib, ... }:
let cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim.plugins = {
      treesitter = {
        enable = true;

        nixvimInjections = true;
        nixGrammars = true;
        folding = true;
        indent = true;
      };

      treesitter-refactor = {
        enable = true;
        highlightDefinitions = {
          enable = true;
          # Set to false if you have an `updatetime` of ~100.
          clearOnCursorMove = false;
        };
      };

      hmts.enable = true;
    };
  };
}
