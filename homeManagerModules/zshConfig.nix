{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  programs.bat = {
    enable = true;
    ## cf https://github.com/sharkdp/bat#customization
    config = {
      map-syntax = ["*.jenkinsfile:Groovy" "*.props:Java Properties"];
      theme = lib.mkIf (!cfg.stylixConfig.enable) "ansi";
    };
  };
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
  programs.zsh = {
    plugins = [
      {
        # will source zsh-autosuggestions.plugin.zsh
        name = "zsh-autosuggestions";
        src = pkgs.fetchFromGitHub {
          owner = "zsh-users";
          repo = "zsh-autosuggestions";
          rev = "refs/tags/v0.7.0";
          sha256 = "sha256-KLUYpUu4DHRumQZ3w59m9aTW6TBKMCXl2UcKi4uMd7w=";
        };
      }
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
    ];
    enable = true;
    initExtra = ''
      source <(${pkgs.kubeswitch}/bin/switcher init zsh)
      # alias
      alias vpn="sudo /run/current-system/sw/bin/openvpn --up ${pkgs.update-systemd-resolved}/libexec/openvpn/update-systemd-resolved --down ${pkgs.update-systemd-resolved}/libexec/openvpn/update-systemd-resolved --config"
      alias k=kubectl
      alias cat='bat -p'
      alias top='btop'
      alias ll='eza -lTs old -L 2'
      alias l='eza -las old'
      alias df='duf'
      complete -o default -F __start_kubectl k
    '';
    oh-my-zsh = {
      enable = true;
    };
  };
}
