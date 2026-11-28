# The base of every macOS machine: the Nix daemon (Lix, nixbook's cache, the
# pinned nixpkgs), Touch ID for sudo, zsh, fonts. The counterpart of the parts
# of nixosModules/core.nix that make sense on macOS.
{
  pkgs,
  lib,
  sources,
  ...
}:
{
  nix = {
    # nix-darwin manages the daemon: install Nix with the Lix installer (or
    # upstream Nix), not Determinate Nix, which runs its own daemon (then
    # nix.enable must be false and none of this applies).
    enable = true;
    package = pkgs.lixPackageSets.stable.lix;
    # <nixpkgs> (nix-shell -p) and the flake registry (nix shell nixpkgs#)
    # at the npins revision, as on NixOS.
    nixPath = [ "nixpkgs=${sources.nixpkgs}" ];
    registry.nixpkgs = {
      exact = true;
      to = {
        type = "path";
        path = "${sources.nixpkgs}";
      };
    };
    settings = {
      trusted-users = [
        "root"
        "@admin"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # The cache only holds Linux builds (build.yaml pushes the NixOS
      # machines' closures): it costs one lookup per path, and is there for
      # the day darwin builds are pushed too.
      substituters = [ "https://s3.didactiklabs.io/nix-cache" ];
      trusted-public-keys = [
        "didactiklabs-nixcache:PxLKN0+ZkP07M8g8/B6xbP6A4MYpqQg6LH7V3muiy/0="
      ];
      always-allow-substitutes = true;
      max-jobs = lib.mkDefault 4;
      cores = lib.mkDefault 4;
    };
    extraOptions = ''
      fallback = true
      connect-timeout = 5
      min-free = ${toString (10240 * 1024 * 1024)}
      max-free = ${toString (30720 * 1024 * 1024)}
    '';
    # Weekly, as NixOS's nh clean: old generations go after 14 days.
    gc = {
      automatic = true;
      interval = [
        {
          Weekday = 0;
          Hour = 3;
          Minute = 15;
        }
      ];
      options = "--delete-older-than 14d";
    };
    optimise.automatic = true;
  };

  # sudo with the fingerprint, also inside tmux/zellij (pam_reattach).
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true;
  };

  programs.zsh = {
    enable = true;
    # Home Manager's zsh (zshConfig) runs compinit already.
    enableGlobalCompInit = false;
  };

  environment.systemPackages = with pkgs; [
    git
    jq
    coreutils
  ];

  # nix-darwin's state version for the machines installed from this repository.
  system.stateVersion = 6;
}
