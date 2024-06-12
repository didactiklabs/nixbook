{
  config,
  pkgs,
  ...
}: {
  environment.defaultPackages = with pkgs; [
    # tools
    python3
    kubectl
    k9s
    kubeswitch
    kubevirt
    dig
    git
    jq
    yq-go
    file
    unzip
    usbutils
    vim
    docker-client
    go
    tree
    pciutils
    neofetch

    # apps
    wdisplays # display manager
    vesktop # discord
    firefox
    spotify
    openvpn
    geeqie # image viewer
    mpv
  ];
}
