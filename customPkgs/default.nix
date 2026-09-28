# Overlay: every package of this directory (<name>.nix, called with the final
# pkgs) as `pkgs.customPkgs.<name>`. Namespaced so they can never shadow a
# nixpkgs package of the same name. Added by lib/pkgs.nix.
final: _prev:
let
  inherit (final) lib;
  files = lib.filterAttrs (
    file: type: type == "regular" && file != "default.nix" && lib.hasSuffix ".nix" file
  ) (builtins.readDir ./.);
in
{
  customPkgs = lib.mapAttrs' (
    file: _: lib.nameValuePair (lib.removeSuffix ".nix" file) (import ./${file} { pkgs = final; })
  ) files;
}
