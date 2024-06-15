{
  config,
  pkgs,
  ...
}: {
  environment.defaultPackages = with pkgs; [
    # tools
    python3
    nix-eval-jobs
    dogdns
    jq
    yq-go
    file
    unzip
    vim
    docker-client
    go
    tree
    pciutils
    btop # top replacer
    duf # df replacer
    sd # sd alternative

    # clouds
    kcl-cli
    kubectl
    k9s
    kubevirt
    fluxcd
    kind
    kubebuilder

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
