{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules.vim;
in {
  options.customHomeManagerModules.vim = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable vim globally or not
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.vim = {
      enable = true;
      plugins = [
        pkgs.vimPlugins.vim-addon-nix
        pkgs.vimPlugins.vim-nix
        pkgs.vimPlugins.vim-airline
        pkgs.vimPlugins.vim-better-whitespace
      ];
      settings = {
        ignorecase = true;
        number = true;
        copyindent = true;
      };
      extraConfig = ''
        set mouse=a
        syntax on
        "set listchars=eol:¬,tab:>·,trail:~,extends:>,precedes:<,space:.
        "set listchars=eol:¬
        "set list
        let g:better_whitespace_enabled=1
        let g:strip_whitespace_on_save=1
        let g:strip_whitelines_at_eof=1
        let g:show_spaces_that_precede_tabs=1
        set cursorcolumn
        set cursorline
      '';
    };
  };
}
