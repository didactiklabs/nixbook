{
  config,
  lib,
  pkgs,
  ...
}:
let
  sources = import ../npins;
  ytfzfSrc = sources.ytfzf;
  ytui = import ../customPkgs/ytui.nix { inherit pkgs; };
  cfg = config.customHomeManagerModules;
  ytfzfExtensions = "${ytfzfSrc}/addons/extensions";
  ytfzfConfig = ''
    thumbnail_viewer=kitty
    show_thumbnails=1
    thumbnail_quality=hqdefault
    scrape=youtube
    async_thumbnails=0
    pages_to_scrape=3
    sub_link_count=1000
    search_region=FR
    is_detach=1
    # url_handler_opts="--vo=kitty --vo-kitty-use-shm=yes --profile=sw-fast --vf-add=fps=24:round=near"
    load_extension smart-thumb-download
  '';
  mpvScripts = with pkgs.mpvScripts; [
    thumbfast
    mpris
    modernx
  ];
in
{
  config = lib.mkIf cfg.desktopApps.enable {
    programs = {
      mpv = {
        enable = true;
        scripts = mpvScripts;
        config = { };
      };
      zsh = {
        shellAliases = {
          yt = "ytfzf -l";
          yts = "ytfzf -l -c youtube-subscriptions --sort";
          yth = "ytfzf -l -H";
          ytt = "ytfzf -l -c youtube-trending";
        };
      };
    };
    home = {
      file = {
        ".config/ytfzf/conf.sh" = {
          text = ytfzfConfig;
        };
        ".config/ytfzf/thumbnails/.keep" = {
          text = "";
        };
        ".config/ytfzf/extensions" = {
          source = ytfzfExtensions;
        };
      };
      packages = [
        ytui
        (pkgs.ytfzf.override { mpv = pkgs.mpv.override { scripts = mpvScripts; }; })
      ];
    };
  };
}
