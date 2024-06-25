{
  config,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.nixvimConfig.enable {
    programs.nixvim = {
      plugins = {
        lsp-format = {
          enable = true;
          setup = {
            type = {
              sync = true;
            };
          };
        };
        lsp = {
          enable = true;
          keymaps = {
            silent = true;
            diagnostic = {
              # Navigate in diagnostics
              "<leader>k" = "goto_prev";
              "<leader>j" = "goto_next";
            };
            lspBuf = {
              gd = "definition";
              gD = "references";
              gt = "type_definition";
              gi = "implementation";
              K = "hover";
              "<F2>" = "rename";
            };
          };
          servers = {
            bashls.enable = true;
            cmake.enable = true;
            csharp-ls.enable = true;
            cssls.enable = true;
            dagger.enable = true;
            nixd.enable = true;
            nil-ls.enable = true;
            yamlls.enable = true;
            gopls.enable = true;
            golangci-lint-ls.enable = true;
            helm-ls.enable =true;
            html.enable = true;
            htmx.enable = true;
            jsonls.enable = true;
            nginx-language-server.enable = true;
            sqls.enable = true;
            terraformls.enable = true;
          };
        };
      };
    };
  };
}
