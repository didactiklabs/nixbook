{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  sourceVimSpellUrl = "ftp.nluug.nl";
  nvim-spell-fr-utf8-dictionary = builtins.fetchurl {
    url = "https://${sourceVimSpellUrl}/vim/runtime/spell/fr.utf-8.spl";
    sha256 = "abfb9702b98d887c175ace58f1ab39733dc08d03b674d914f56344ef86e63b61";
  };

  nvim-spell-fr-utf8-suggestions = builtins.fetchurl {
    url = "https://${sourceVimSpellUrl}/vim/runtime/spell/fr.utf-8.sug";
    sha256 = "0294bc32b42c90bbb286a89e23ca3773b7ef50eff1ab523b1513d6a25c6b3f58";
  };

  nvim-spell-fr-latin1-dictionary = builtins.fetchurl {
    url = "https://${sourceVimSpellUrl}/vim/runtime/spell/fr.latin1.spl";
    sha256 = "086ccda0891594c93eab143aa83ffbbd25d013c1b82866bbb48bb1cb788cc2ff";
  };

  nvim-spell-fr-latin1-suggestions = builtins.fetchurl {
    url = "https://${sourceVimSpellUrl}/vim/runtime/spell/fr.latin1.sug";
    sha256 = "5cb2c97901b9ca81bf765532099c0329e2223c139baa764058822debd2e0d22a";
  };
in
{
  imports = [
    ./options.nix
    ./autocmd.nix
    ./plugins
  ];
  config = lib.mkIf cfg.nixvimConfig.enable {
    home.file = {
      "${config.xdg.configHome}/nvim/spell/fr.utf-8.spl".source = nvim-spell-fr-utf8-dictionary;
      "${config.xdg.configHome}/nvim/spell/fr.utf-8.sug".source = nvim-spell-fr-utf8-suggestions;
      "${config.xdg.configHome}/nvim/spell/fr.latin1.spl".source = nvim-spell-fr-latin1-dictionary;
      "${config.xdg.configHome}/nvim/spell/fr.latin1.sug".source = nvim-spell-fr-latin1-suggestions;
    };
    programs.nixvim = {
      enable = true;
      defaultEditor = true;
      opts.completeopt = [
        "menu"
        "menuone"
        "noselect"
      ];
      viAlias = true;
      vimAlias = true;
      luaLoader.enable = true;
      extraPlugins = with pkgs.vimPlugins; [
        #vim-nix
        #vim-addon-nix
        #vim-airline
        vim-better-whitespace
      ];
      extraConfigVim = ''
        syntax on
        "set listchars=eol:¬,tab:>·,trail:~,extends:>,precedes:<,space:.
        "set listchars=eol:¬
        "set list
        let g:better_whitespace_enabled=1
        let g:strip_whitespace_on_save=1
        let g:strip_whitelines_at_eof=1
        let g:show_spaces_that_precede_tabs=1
        let g:neovide_remember_window_size = v:false
        let g:neovide_scale_factor = 0.8
        let g:neovide_fullscreen = v:false
      '';
    };
  };

  options.customHomeManagerModules.nixvimConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable nixvimConfig globally or not
      '';
    };
  };
}
