# The nixpkgs every machine, the hive, the tests, the docs and the standalone
# Home Manager entry point evaluate with: the npins nixpkgs plus nixbook's
# overlays (lib/overlays.nix, and the custom packages as `pkgs.customPkgs`).
# `system` is for the macOS machines (darwin.nix: "aarch64-darwin", also when
# evaluated on Linux by the tests); null = the machine evaluating.
{
  sources ? import ../npins,
  system ? null,
}:
import sources.nixpkgs {
  ${if system == null then null else "localSystem"} = system;
  config = {
    allowUnfree = true;
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
