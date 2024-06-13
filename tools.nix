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
    btop # top replacer
    eza # ls replacer
    duf # df replacer

    # apps
    wdisplays # display manager
    vesktop # discord
    firefox
    spotify
    openvpn
    geeqie # image viewer
    mpv # video player
  ];
}
