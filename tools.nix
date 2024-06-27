{pkgs, ...}: {
  environment.defaultPackages = with pkgs; [
    # tools
    python3
    nix-eval-jobs
    dig
    jq
    yq-go
    tig
    unzip
    go
    tree
    openvpn
    btop # top replacer
    duf # df replacer
    sd # sed alternative
  ];
}
