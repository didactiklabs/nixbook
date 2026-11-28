# The macOS machines (nix-darwin): the counterpart of hive.nix, which only
# deploys NixOS (colmena has no macOS support).
#
#   nix-build darwin.nix -A talia.system     build talia's system
#   darwin-switch                            build and activate it (on talia,
#                                            darwinModules/tools.nix)
#
# `withUser HOST USER` is the same machine for another account (where `khoa`
# doesn't exist): the GitHub macOS runner's (tests/darwin-switch.sh), a tart
# VM's or a rented Mac's (tests/darwin-try.sh):
#   nix-build -E '((import ./darwin.nix).withUser "talia" "runner").system'
let
  sources = import ./npins;
  # Each machine: its user (the account it is for) and system.
  hosts = {
    talia = {
      username = "khoa";
    };
  };
  mkDarwin =
    {
      hostName,
      system ? "aarch64-darwin",
      username,
    }:
    let
      pkgs = import ./lib/pkgs.nix { inherit sources system; };
    in
    import "${sources.nix-darwin}/eval-config.nix" {
      inherit (pkgs) lib;
      specialArgs = {
        inherit sources username;
        hostname = hostName;
      };
      modules = [
        {
          # One nixpkgs instance, as base.nix does for NixOS: config and
          # overlays belong in lib/pkgs.nix, not in nixpkgs.* options.
          nixpkgs = {
            inherit pkgs;
            source = sources.nixpkgs;
          };
          networking = {
            inherit hostName;
            localHostName = hostName;
            computerName = hostName;
          };
        }
        (import "${sources.home-manager}/nix-darwin")
        (import "${sources.agenix}/modules/age.nix")
        ./darwinModules
        ./profiles/${hostName}/configuration.nix
      ];
    };
  withUser =
    host: username:
    mkDarwin (
      hosts.${host}
      // {
        hostName = host;
        inherit username;
      }
    );
in
builtins.mapAttrs (host: args: withUser host args.username) hosts
// {
  inherit withUser;
}
