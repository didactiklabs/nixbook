# khoa on talia: the shell, editor, Kubernetes and AI tools of the NixOS
# machines, and OmniWM (niri-like scrolling tiling) instead of niri. Linux
# desktop modules (niri, nixbook-shell, DMS, GTK, fcitx5…) are left off: they
# don't exist on macOS.
{ ... }:
{
  imports = [
    ./gitConfig.nix
  ];

  customHomeManagerModules = {
    cliTools.enable = true;
    devTools.enable = true;
    fontConfig.enable = true;
    gitConfig.enable = true;
    sshConfig.enable = true;
    starship.enable = true;
    fastfetchConfig.enable = true;
    kubeTools.enable = true;
    kubeConfig = {
      didactiklabs.enable = true;
      bealv.enable = true;
      rpcu.enable = true;
    };
    nixvimConfig.enable = true;
    gojiConfig.enable = true;
    atuinConfig.didactiklabs.enable = true;
    kittyConfig.enable = true;
    zshConfig.enable = true;
    kubeswitchConfig.enable = true;
    opencodeConfig.enable = true;
    rtk.enable = true;
    omniwmConfig.enable = true;
  };
}
