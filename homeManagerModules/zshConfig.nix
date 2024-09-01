{ pkgs, ... }:
{
  config = {
    home.packages = [
      pkgs.any-nix-shell
      pkgs.btop # top replacer
      pkgs.duf # df replacer
      pkgs.sd # sed alternative
    ];
    programs = {
      atuin = {
        enable = true; # history
        enableZshIntegration = true;
        flags = [ "--disable-up-arrow" ];
      };
      ranger = {
        enable = true;
      };
      zoxide = {
        enable = true;
        enableZshIntegration = true;
      };
      bat = {
        enable = true;
        ## cf https://github.com/sharkdp/bat#customization
        config = {
          map-syntax = [
            "*.jenkinsfile:Groovy"
            "*.props:Java Properties"
          ];
        };
      };
      fzf = {
        enable = true;
        enableZshIntegration = true;
        tmux.enableShellIntegration = true;
      };
      tmux = {
        enable = true;
        mouse = true;
        plugins = with pkgs; [
          tmuxPlugins.sensible
          {
            plugin = tmuxPlugins.resurrect;
            extraConfig = "set -g @resurrect-strategy-nvim 'session'";
          }
          {
            plugin = tmuxPlugins.continuum;
            extraConfig = ''
              set -g @continuum-restore 'on'
              set -g @continuum-save-interval '60' # minutes
            '';
          }
        ];
        extraConfig = ''
          set-option -ga terminal-overrides ",*:Tc"
          # visual
          set -g visual-activity off
          set -g visual-bell off
          set -g visual-silence off
          setw -g monitor-activity off
          set -g bell-action none
          # statusbar
          set -g status-position bottom
          set -g status-justify left
          set -g status-style 'fg=colour1'
          set -g status-left ""
          set -g status-right "%Y-%m-%d %H:%M "
          set -g status-right-length 50
          set -g status-left-length 10
          setw -g window-status-current-style 'fg=colour0 bg=colour1 bold'
          setw -g window-status-current-format ' #I #W #F '
          setw -g window-status-style 'fg=colour1 dim'
          setw -g window-status-format ' #I #[fg=colour7]#W #[fg=colour1]#F '
          setw -g window-status-bell-style 'fg=colour2 bg=colour1 bold'
          # messages
          set -g message-style 'fg=colour2 bg=colour0 bold'
        '';
      };
      eza = {
        enable = true;
        enableZshIntegration = true;
      };
      ripgrep = {
        enable = true;
      };
      fd = {
        enable = true;
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
              sha256 = "sha256-7TL47mX3eUEPbfK8urpw0RzEubGF2x00oIpRKR1W43k=";
            };
          }
        ];
        enable = true;
        shellAliases = {
          vpn = "sudo ${pkgs.openvpn}/bin/openvpn --up ${pkgs.update-systemd-resolved}/libexec/openvpn/update-systemd-resolved --down ${pkgs.update-systemd-resolved}/libexec/openvpn/update-systemd-resolved --config";
          k = "kubectl";
          top = "btop";
          df = "duf";
          cd = "z";
          neofetch = "fastfetch";
          grep = "rg";
        };
        initExtra = ''
          any-nix-shell zsh --info-right | source /dev/stdin
          [[ "$TERM" == "xterm-kitty" ]] && alias ssh="TERM=xterm-256color ssh"
        '';
        oh-my-zsh = {
          enable = true;
        };
      };
    };
  };
}
