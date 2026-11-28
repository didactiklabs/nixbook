# What every nixbook Home Manager user starts from, on NixOS
# (lib/userConfig.nix) and on macOS (lib/darwinUserConfig.nix): the external
# Home Manager modules the repository's modules expect, its own modules, and
# the `profileCustomization` options. Some of these modules are for Linux
# desktops only; they stay importable everywhere so that every option exists,
# and are only enabled where they work.
{ pkgs, sources }:
let
  dmsFlake = import sources.flake-compat {
    src = sources.dms;
  };
  dmsPluginRegistryFlake = import sources.flake-compat {
    src = sources.dms-plugin-registry;
  };
  zenBrowserFlake = import sources.flake-compat {
    src = sources.zen-browser-flake;
  };
  defaultImagePath = pkgs.runCommand "default-images" { src = ../assets/images; } ''
    mkdir -p $out
    cp -r $src/* $out
  '';
in
{
  imports = [
    (import sources.stylix).homeModules.stylix
    (import sources.nixvim).homeModules.nixvim
    (import "${sources.agenix}/modules/age-home.nix")
    dmsFlake.defaultNix.homeModules.dank-material-shell
    dmsPluginRegistryFlake.defaultNix.homeModules.default
    zenBrowserFlake.defaultNix.homeModules.twilight
    ../homeManagerModules
  ];

  profileCustomizationOptions = {
    mainWallpaper = pkgs.lib.mkOption {
      type = pkgs.lib.types.str;
      default = "${defaultImagePath}/nixos-wallpaper.png";
      description = "Image to set as main wallpaper.";
    };
    lockWallpaper = pkgs.lib.mkOption {
      type = pkgs.lib.types.str;
      default = "${defaultImagePath}/nixos-wallpaper.png";
      description = "Image to set as lock wallpaper.";
    };
  };
}
