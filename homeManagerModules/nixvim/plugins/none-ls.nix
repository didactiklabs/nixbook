{
  config,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim.plugins = {
      none-ls = {
        enable = true;
        enableLspFormat = true;
        updateInInsert = false;
        sources = {
          code_actions = {
            gitsigns.enable = true;
            statix.enable = true;
          };
          diagnostics = {
            statix.enable = true;
            yamllint.enable = true;
          };
          formatting = {
            alejandra.enable = true;
            black = {
              enable = true;
              withArgs = ''
                {
                  extra_args = { "--fast" },
                }
              '';
            };
            prettier = {
              enable = true;
              disableTsServerFormatter = true;
              withArgs = ''
                {
                  extra_args = { "--no-semi", "--single-quote" },
                }
              '';
            };
            stylua.enable = true;
            yamlfmt.enable = true;
          };
        };
      };
    };
  };
}
