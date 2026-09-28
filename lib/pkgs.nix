# The nixpkgs every machine, the hive, the tests, the docs and the standalone
# Home Manager entry point evaluate with: the npins nixpkgs plus nixbook's
# overlays (lib/overlays.nix, and the custom packages as `pkgs.customPkgs`).
{
  sources ? import ../npins,
}:
import sources.nixpkgs {
  config = {
    allowUnfree = true;
    allowUnfreePredicate = true;
    permittedInsecurePackages = [
      "qtwebengine-5.15.19"
      "pnpm-10.29.2"
      "electron-40.10.5"
    ];
  };
  overlays = [
    (import ./overlays.nix { inherit sources; })
    (import ../customPkgs)
  ];
}
