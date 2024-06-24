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
    openvpn
    btop # top replacer
    duf # df replacer
    sd # sed alternative
  ];
}
