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
    enable = true;
    initExtra = ''
      source <(${pkgs.kubeswitch}/bin/switcher init zsh)
      # alias
      alias vpn="sudo /run/current-system/sw/bin/openvpn --up ${pkgs.update-systemd-resolved}/libexec/openvpn/update-systemd-resolved --down ${pkgs.update-systemd-resolved}/libexec/openvpn/update-systemd-resolved"
      alias k=kubectl
      complete -o default -F __start_kubectl k
    '';
    oh-my-zsh = {
      enable = true;
    };
  };
  programs.bash = {
    enable = false;
  };
  home.packages = [
    pkgs.shellcheck
  ];
}
