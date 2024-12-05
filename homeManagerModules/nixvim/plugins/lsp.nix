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
    home.packages = [ pkgs.golangci-lint ];
    programs.nixvim = {
      filetype.extension.templ = "templ";
      plugins = {
        lsp-format = {
          enable = true;
          settings = {
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
            templ = {
              enable = true;
              filetypes = [ "templ" ];
            };
            bashls.enable = true;
            cmake.enable = true;
            csharp_ls.enable = true;
            cssls.enable = true;
            dagger.enable = true;
            nixd.enable = true;
            nil_ls.enable = true;
            yamlls.enable = true;
            gopls.enable = true;
            golangci_lint_ls.enable = true;
            helm_ls.enable = true;
            html.enable = true;
            htmx.enable = true;
            nginx_language_server.enable = true;
            sqls.enable = true;
            terraformls.enable = true;
          };
        };
      };
    };
  };
}
