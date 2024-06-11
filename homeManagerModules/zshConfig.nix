{
  lib,
  config,
  pkgs,
  ...
}: {
  programs.bat = {
    enable = true;
    ## cf https://github.com/sharkdp/bat#customization
    config = {
      map-syntax = ["*.jenkinsfile:Groovy" "*.props:Java Properties"];
      theme = "ansi";
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
      alias vpn="sudo /run/current-system/sw/bin/openvpn --up ${pkgs.update-systemd-resolved}/libexec/openvpn/update-systemd-resolved --down ${pkgs.update-systemd-resolved}/libexec/openvpn/update-systemd-resolved --pkcs11-providers ${pkgs.opensc}/lib/opensc-pkcs11.so --config"
    '';
    oh-my-zsh = {
      enable = true;
    };
  };
  programs.bash = {
    enable = lib.mkForce false;
  };
  home.packages = [
    pkgs.shellcheck
  ];
}
