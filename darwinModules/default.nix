# nix-darwin modules (the macOS machines, darwin.nix): the counterpart of
# nixosModules/. Options live under `customDarwinModules`, except the ones
# shared with NixOS (getRevision keeps its `customNixOSModules` name).
{ ... }:
{
  imports = [
    ./caCertificates.nix
    ./core.nix
    ./defaults.nix
    ./tools.nix
    # Portable as it is: only environment.etc.
    ../nixosModules/getRevision.nix
  ];
}
