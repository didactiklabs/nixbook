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
      enableMan = false;
      enable = true;
      defaultEditor = true;
      opts = {
        completeopt = [
          "menu"
          "menuone"
          "noselect"
        ];
      };
      viAlias = true;
      vimAlias = true;
      luaLoader.enable = true;
      extraPlugins = with pkgs.vimPlugins; [
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
      extraConfigLua = "";
      keymaps = [
        {
          mode = "n";
          key = "<leader>a";
          action = ":lua vim.lsp.buf.code_action()<CR>";
          options.silent = true;
        }
        {
          mode = "n";
          key = "<S-h>";
          action = ":bprevious<CR>";
          options.silent = true;
        }
        {
          mode = "n";
          key = "<S-l>";
          action = ":bnext<CR>";
          options.silent = true;
        }
        {
          mode = "n";
          key = "<C-l>";
          action = ":nohlsearch<CR>";
          options.silent = true;
        }
        {
          mode = "n";
          key = "<C-S-Up>";
          action = ":resize +2<CR>";
          options.silent = true;
        }
        {
          mode = "n";
          key = "<C-S-Down>";
          action = ":resize -2<CR>";
          options.silent = true;
        }
        {
          mode = "n";
          key = "<C-S-Left>";
          action = ":vertical resize -2<CR>";
          options.silent = true;
        }
        {
          mode = "n";
          key = "<C-S-Right>";
          action = ":vertical resize +2<CR>";
          options.silent = true;
        }
      ];
    };
  };

  options.customHomeManagerModules.nixvimConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable NixVim — a fully declarative Neovim configuration.

        NixVim manages Neovim and all its plugins through the Nix module system,
        ensuring reproducibility.  This configuration sets up a complete IDE-like
        environment:

        Core settings (options.nix):
          - Space as leader/localleader key
          - System clipboard via wl-copy (Wayland)
          - Relative + absolute line numbers, scrolloff=8, cursorline/column
          - Undo history persistence, incremental search, smart case
          - 4-space tabs with auto-indent, no swap file
          - Disabled providers: ruby, perl, python2

        Plugins (plugins/):
          LSP & completion:   lsp (gopls, nil, ts-ls, pylsp, lua-ls…),
                              cmp (nvim-cmp with LSP/buffer/path sources),
                              none-ls (formatters/linters)
          Navigation:         telescope (fuzzy finder), neo-tree (file explorer),
                              trouble (diagnostics list)
          Editing:            comment, mini (surround, pairs, etc.),
                              git-conflict, trim, vim-better-whitespace
          UI:                 barbar (tabline), lualine (statusline),
                              noice (cmdline/messages UI), notify,
                              snacks, smear-cursor, neoscroll, colorizer,
                              markdown-preview, floaterm, startify
          Extras:             neocord (Discord Rich Presence),
                              treesitter (syntax highlighting),
                              opencode (AI coding assistant integration),
                              99 (custom utility plugin)

        French spell-check files (fr.utf-8 + fr.latin1) are pre-fetched and
        deployed to ~/.config/nvim/spell/.

        Keybindings: <leader>a (code action), Shift-H/L (prev/next buffer),
        Ctrl-L (clear highlight), Ctrl-Shift-arrows (resize splits).

        vi/vim aliases enabled, set as default editor.
      '';
    };
  };
}
