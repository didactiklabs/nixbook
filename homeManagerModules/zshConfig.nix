{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules.zshConfig;
  common = import ./commonShellConfig.nix { inherit pkgs; };
in
{
  options.customHomeManagerModules.zshConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Zsh with full shell integrations and common tooling.

        Enables programs.zsh with:
          - oh-my-zsh-style defaults (keybindings, completion menu, dir options)
            without oh-my-zsh itself, to keep shell startup fast
          - zsh-syntax-highlighting plugin (v0.8.0) — real-time command colouring
          - zsh-bat plugin — replaces `cat` output with bat syntax highlighting
          - Autosuggestions (fish-style inline suggestions)
          - any-nix-shell integration: preserves the Zsh shell inside `nix shell`
            and `nix develop` environments instead of dropping to bash

        Shell integrations (from commonShellConfig):
          - atuin    — shell history search/sync (up-arrow disabled, manual Ctrl-R)
          - yazi     — terminal file manager (y alias)
          - zoxide   — smarter `cd` replacement (cd aliased to `z`)
          - fzf      — fuzzy finder with tmux integration
          - eza      — modern `ls` replacement
          - direnv   — per-directory environment loading (nix-direnv enabled)

        Common packages installed: ginx, trippy, any-nix-shell, duf, sd, viddy, witr,
        dgop, devenv (see commonShellConfig.nix for the full list).

        Common aliases: ks=kswitch, watch=viddy, y=yazi, top=dgop, df=duf, cd=z,
        neofetch=fastfetch, gfix/gfeat/gchore (goji shortcuts).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = common.commonPackages;
    programs = common.commonPrograms // {
      atuin = {
        enableZshIntegration = true;
        flags = [ "--disable-up-arrow" ];
      };
      yazi = common.commonPrograms.yazi // {
        enableZshIntegration = true;
      };
      zoxide = common.commonPrograms.zoxide // {
        enableZshIntegration = true;
      };
      fzf = common.commonPrograms.fzf // {
        enableZshIntegration = true;
        historyWidget.zsh.command = "";
      };
      eza = common.commonPrograms.eza // {
        enableZshIntegration = true;
      };
      direnv = common.commonPrograms.direnv // {
        enableZshIntegration = true;
      };
      zsh = {
        autosuggestion.enable = true;
        plugins = [
          {
            # will source zsh-autosuggestions.plugin.zsh
            name = "zsh-syntax-highlighting";
            src = pkgs.fetchFromGitHub {
              owner = "zsh-users";
              repo = "zsh-syntax-highlighting";
              rev = "refs/tags/0.8.0";
              sha256 = "sha256-iJdWopZwHpSyYl5/FQXEW7gl/SrKaYDEtTH9cGP7iPo=";
            };
          }
          {
            # will source zsh-autosuggestions.plugin.zsh
            name = "zsh-bat";
            src = pkgs.fetchFromGitHub {
              owner = "fdellwing";
              repo = "zsh-bat";
              rev = "master";
              sha256 = "sha256-TTuYZpev0xJPLgbhK5gWUeGut0h7Gi3b+e00SzFvSGo=";
            };
          }
        ];
        enable = true;
        shellAliases = common.commonShellAliases;
        initContent = ''
          ${common.anyNixShellInit "zsh"}
          # any-nix-shell's precmd forks nix-shell-info + sed on every prompt, but it only
          # prints something inside a nix shell; skip it everywhere else.
          functions[__any_nix_shell_precmd]=$functions[precmd]
          precmd() {
            if [[ -n $IN_NIX_SHELL$IN_NIX_RUN ]]; then
              __any_nix_shell_precmd
            else
              RPROMPT=
            fi
          }

          # The parts of oh-my-zsh's lib we actually used, without its ~65ms startup cost.
          setopt auto_cd auto_pushd pushd_ignore_dups pushdminus
          setopt complete_in_word always_to_end auto_menu interactive_comments
          unsetopt menu_complete flow_control

          zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'r:|=*' 'l:|=* r:|=*'
          zstyle ':completion:*:*:*:*:*' menu select
          zstyle ':completion:*' special-dirs true
          zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
          zstyle ':completion:*' use-cache yes
          zstyle ':completion:*' cache-path "''${XDG_CACHE_HOME:-$HOME/.cache}/zsh"

          # Up/Down: search history for lines starting with what's already typed
          autoload -U up-line-or-beginning-search down-line-or-beginning-search edit-command-line
          zle -N up-line-or-beginning-search
          zle -N down-line-or-beginning-search
          zle -N edit-command-line
          bindkey '^[[A' up-line-or-beginning-search
          bindkey '^[OA' up-line-or-beginning-search
          bindkey '^[[B' down-line-or-beginning-search
          bindkey '^[OB' down-line-or-beginning-search
          bindkey '^[[1;5C' forward-word
          bindkey '^[[1;5D' backward-word
          bindkey '^[[3;5~' kill-word
          bindkey '^[[Z' reverse-menu-complete
          bindkey ' ' magic-space
          bindkey '^x^e' edit-command-line

          alias -g ...='../..'
          alias -g ....='../../..'
          alias -g .....='../../../..'
          alias -- -='cd -'
          alias md='mkdir -p'
        '';
      };
    };
  };
}
