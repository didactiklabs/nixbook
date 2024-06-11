{
  pkgs,
  lib ? pkgs.lib,
}: let
  inherit (import ./extensionsList.nix) extensions;

  ## Returns a list with derivations for extensions not in nixpkgs
  extensionsToBuild = pkgs.vscode-utils.extensionsFromVscodeMarketplace extensions;
in
  extensionsToBuild
