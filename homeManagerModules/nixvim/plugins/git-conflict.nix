{ config, lib, ... }:
let cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim = {
      plugins.git-conflict = {
        enable = true;
        settings = {
          default_mappings = true;
          default_commands = true;
          disable_diagnostics = false;
          list_opener = "copen";
          highlights = {
            incoming = "DiffAdd";
            current = "DiffText";
            ancestor = null;
          };
        };
      };
    };
  };
}
