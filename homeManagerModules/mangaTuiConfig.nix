{ config, lib, ... }:
let
  sources = import ../npins;
  pkgs-unstable = import sources.nixpkgs-unstable { };
  cfg = config.customHomeManagerModules;
  mangaTuiConfig = ''
    # The format of the manga downloaded
    # values : cbz , raw, epub
    # default : cbz
    download_type = "cbz"

    # Download image quality, low quality means images are compressed and is recommended for slow internet connections
    # values : low, high
    # default : low
    image_quality = "low"
  '';
in
{
  config = lib.mkIf cfg.desktopApps.enable {
    home = {
      file = {
        ".local/share/manga-tui/config/manga-tui-config.toml" = {
          text = mangaTuiConfig;
        };
      };
      packages = [ pkgs-unstable.manga-tui ];
    };
  };
}
