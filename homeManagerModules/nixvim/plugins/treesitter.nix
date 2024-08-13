{ config, lib, pkgs, ... }:
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
        grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
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
          ini
          http
          html
          helm
          hcl
          go
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
        ];
        languageRegister = { templ = "templ"; };
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
