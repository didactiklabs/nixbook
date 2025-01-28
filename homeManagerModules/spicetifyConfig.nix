{
  config,
  lib,
  pkgs,
  ...
}:
let
  sources = import ../npins;
  inherit (sources) flake-compat;
  spicetify-nix = (import flake-compat { src = sources.spicetify-nix; }).defaultNix;
  spicePkgs = spicetify-nix.legacyPackages.${pkgs.system};
  cfg = config.customHomeManagerModules;
in
{
  options.customHomeManagerModules.spicetifyConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable desktopApps globally or not
      '';
    };
  };
  imports = [ spicetify-nix.homeManagerModules.default ];
  config = lib.mkIf cfg.spicetifyConfig.enable {
    programs.spicetify = {
      enable = true;
      spotifyPackage = pkgs.spotify;
      spotifywmPackage = pkgs.spotifywm;
      windowManagerPatch = true;
      spicetifyPackage = pkgs.spicetify-cli;
      enabledExtensions = with spicePkgs.extensions; [
        fullAppDisplay
        volumePercentage
        history
      ];
      enabledCustomApps = with spicePkgs.apps; [
        lyricsPlus
        historyInSidebar
        betterLibrary
        newReleases
      ];
    };
  };
}
