{ ... }:
{
  imports = [
    ./core.nix
    ./bluetoothAutoConnect.nix
    ./caCertificates.nix
    ./fcitx5-lotus.nix
    ./firewall.nix
    ./gamingConfig.nix
    ./getRevision.nix
    ./greetd.nix
    ./laptopProfile.nix
    ./lanzaboote.nix
    ./netbird-tools.nix
    ./niri.nix
    ./ollama.nix
    ./printTools.nix
    ./simracing.nix
    ./sunshine.nix
    ./sway.nix
    ./tailscale.nix
    ./tools.nix
    ./vmSupport.nix
    ./wolf.nix
    # The system toggles for nixbook-shell's config assistant (read by its
    # Home Manager module through osConfig).
    ../nixbook-shell/nixos-module.nix
  ];
}
