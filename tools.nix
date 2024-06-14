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
    git
    jq
    yq-go
    file
    unzip
    vim
    docker-client
    go
    tree
    pciutils
    neofetch
    btop # top replacer
    eza # ls replacer
    duf # df replacer

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
    ranger # file manager, terminal cli
    mpv # video player
  ];
}
