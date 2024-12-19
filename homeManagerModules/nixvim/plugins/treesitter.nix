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
    home.packages = [ pkgs.gcc ];
    programs.nixvim.plugins = {
      cmp-treesitter.enable = true;
      treesitter = {
        enable = true;
        nixvimInjections = true;
        nixGrammars = true;
        folding = true;
        settings = {
          indent.enable = false;
        };
        grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
          regex
          c
          lua
          vimdoc
          templ
          yaml
          xml
          typescript
          terraform
          ssh_config
          sql
          python
          promql
          php
          perl
          passwd
          nix
          ninja
          nickel
          mermaid
          markdown_inline
          markdown
          make
          latex
          kotlin
          jq
          javascript
          java
          properties
          ini
          http
          html
          htmldjango
          helm
          hcl
          go
          gotmpl
          gosum
          gomod
          gitignore
          git_rebase
          git_config
          gitcommit
          gitattributes
          dockerfile
          cue
          css
          cpp
          cmake
          bash
          awk
          angular
          comment
          fish
          diff
          csv
          jsonnet
          jsonc
          json
          hyprlang
          matlab
          zig
          toml
        ];
        languageRegister = {
          templ = "templ";
        };
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
