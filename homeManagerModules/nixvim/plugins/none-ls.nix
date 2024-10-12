{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
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
            pylint.enable = true;
            ansiblelint.enable = true;
            staticcheck.enable = true;
            stylelint.enable = true;
            hadolint.enable = true;
          };
          formatting = {
            terraform_fmt.enable = true;
            hclfmt.enable = true;
            gofumpt.enable = true;
            golines = {
              enable = true;
              withArgs = ''
                {
                  extra_args = { "--max-len=140" },
                }
              '';
            };
            goimports_reviser.enable = true;
            goimports.enable = true;
            alejandra.enable = true;
            black = {
              # python
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
            markdownlint.enable = true;
            nixfmt = {
              enable = true;
              package = pkgs.nixfmt-rfc-style;
            };
          };
        };
      };
    };
  };
}
