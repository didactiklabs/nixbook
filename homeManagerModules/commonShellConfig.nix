{ pkgs, ... }:
let
  ginx = import ../customPkgs/ginx.nix { inherit pkgs; };
  okada = import ../customPkgs/okada.nix { inherit pkgs; };
  witr = import ../customPkgs/witr.nix { inherit pkgs; };
in
{
  commonPackages = [
    ginx
    pkgs.trippy # debug network
    pkgs.any-nix-shell
    pkgs.btop # top replacer
    pkgs.duf # df replacer
    pkgs.sd # sed alternative
    pkgs.viddy # watch alternative
    witr
    # okada
  ];

  commonShellAliases = {
    ks = "kswitch";
    watch = "viddy";
    y = "yazi";
    top = "btop";
    df = "duf";
    cd = "z";
    neofetch = "fastfetch";
    gfix = "goji -t fix -a -m";
    gfeat = "goji -t feat -a -m";
    gchore = "goji -t chore -a -m";
  };

  commonPrograms = {
    atuin = {
      enable = true; # history
    };
    yazi = {
      enable = true;
    };
    zoxide = {
      enable = true;
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
    };
    ripgrep = {
      enable = true;
    };
    fd = {
      enable = true;
    };
  };

  anyNixShellInit =
    shell:
    "any-nix-shell ${shell} --info-right | source" + (if shell == "fish" then "" else " /dev/stdin");
}
