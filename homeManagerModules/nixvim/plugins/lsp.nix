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
      filetype.pattern = {
        ".*/templates/.*%.yaml" = "helm";
        ".*/templates/.*%.yml" = "helm";
        ".*/templates/.*%.tpl" = "helm";
        "helmfile.*%.yaml" = "helm";
      };
      plugins = {
        lsp-format = {
          enable = true;
          settings = {
            type = {
              sync = true;
            };
          };
        };
        # nvim-lspconfig ships the native `lsp/<server>.lua` default configs
        # (cmd, filetypes, root_markers) that the `vim.lsp` API consumes.
        lspconfig.enable = true;
      };

      # Native LSP via Neovim's `vim.lsp` API (replaces the old `plugins.lsp`).
      lsp = {
        keymaps = [
          # Navigate diagnostics
          {
            key = "<leader>k";
            action.__raw = "function() vim.diagnostic.jump({ count = -1, float = true }) end";
          }
          {
            key = "<leader>j";
            action.__raw = "function() vim.diagnostic.jump({ count = 1, float = true }) end";
          }
          # Buffer actions
          {
            key = "gd";
            lspBufAction = "definition";
          }
          {
            key = "gD";
            lspBufAction = "references";
          }
          {
            key = "gt";
            lspBufAction = "type_definition";
          }
          {
            key = "gi";
            lspBufAction = "implementation";
          }
          {
            key = "K";
            lspBufAction = "hover";
          }
          {
            key = "<F2>";
            lspBufAction = "rename";
          }
        ];
        servers = {
          templ = {
            enable = true;
            config.filetypes = [ "templ" ];
          };
          bashls.enable = true;
          cmake.enable = true;
          csharp_ls.enable = true;
          cssls.enable = true;
          dagger.enable = true;
          # nixd.enable = true;
          nil_ls.enable = true;
          yamlls = {
            enable = true;
            config.settings = {
              yaml = {
                format = {
                  enable = false;
                };
              };
            };
          };
          gopls.enable = true;
          golangci_lint_ls.enable = true;
          helm_ls = {
            enable = true;
            config.settings = {
              "helm-ls" = {
                yamlls = {
                  enabled = true;
                  path = "${pkgs.yaml-language-server}/bin/yaml-language-server";
                  diagnosticsLimit = 50;
                  showDiagnosticsDirectly = false;
                  config = {
                    schemas = { };
                    completion = true;
                    hover = true;
                  };
                };
              };
            };
          };
          html.enable = true;
          htmx.enable = true;
          nginx_language_server.enable = true;
          sqls.enable = true;
          terraformls.enable = true;
        };
      };
    };
  };
}
