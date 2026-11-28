# talia: khoa's Mac (Apple Silicon, macOS 26+), on nix-darwin (darwin.nix).
# Deployed on the Mac itself with `darwin-switch` (darwinModules/tools.nix).
{
  pkgs,
  lib,
  sources,
  username,
  ...
}:
let
  userConfig = import ../../lib/darwinUserConfig.nix { inherit pkgs lib sources; };
in
{
  imports = [
    (userConfig.mkUser {
      inherit username;
      userImports = [ ./khoa ];
    })
  ];

  customDarwinModules.caCertificates = {
    didactiklabs.enable = true;
    bealv.enable = true;
    rpcu.enable = true;
  };

  # Connected by hand (`tailscale up`), as on the NixOS machines.
  services.tailscale.enable = true;
}
