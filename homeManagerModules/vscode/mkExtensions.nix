{
  pkgs,
  lib ? pkgs.lib,
}:
## cf https: //github.com/viperML/dotfiles/blob/master/modules/home-manager/vscode/extensions/default.nix
let
  inherit (import ./extensionsList.nix) extensions;

  ## Takes a extension (attribute set from ./extensionsList.nix)
  ## return true or false if it is packaged in nixpkgs(pkgs.vscode-extensions)
  isInNixpkgs = ext: (
    if builtins.hasAttr (lib.toLower ext.publisher) pkgs.vscode-extensions
    then
      builtins.hasAttr (lib.toLower ext.name)
      pkgs.vscode-extensions."${lib.toLower ext.publisher}"
    else false
  );

  ## Filter extensionsList.nix
  ## Returns a list with derivations for extensions not in nixpkgs
  extensionsNotInNixpkgs = pkgs.vscode-utils.extensionsFromVscodeMarketplace (builtins.filter (n: !(isInNixpkgs n)) extensions);

  ## Filter extensionsList.nix
  ## Returns a list with the derivation for the extensions that are in nixpkgs
  extensionsInNixpkgs = map (
    v:
      pkgs
      .vscode-extensions
      ."${lib.toLower v.publisher}"
      ."${lib.toLower v.name}"
  ) (builtins.filter isInNixpkgs extensions);
in
  extensionsNotInNixpkgs ++ extensionsInNixpkgs
