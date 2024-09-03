{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  ytfzfConfig = ''
    thumbnail_viewer=kitty
    show_thumbnails=1
    search_again=1
    scrape=youtube
    async_thumbnails=1
    pages_to_scrape=10
    sub_link_count=10000
    search_region=FR
    fancy_subs=1
    is_detach=0
    url_handler_opts="--vo=kitty --vo-kitty-use-shm=yes --profile=sw-fast --vf-add=fps=24:round=near"
  '';
  mpvScripts = with pkgs.mpvScripts; [
    thumbfast
    modernx
    mpris
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
          yt = "ytfzf";
          yts = "ytfzf -c youtube-subscriptions --sort";
          yth = "ytfzf -H";
          ytt = "ytfzf -c youtube-trending";
        };
      };
    };
    home = {
      file = {
        ".config/ytfzf/conf.sh" = {
          text = ytfzfConfig;
        };
      };
      packages = [
        (pkgs.ytfzf.override { mpv = pkgs.mpv.override { scripts = [ pkgs.mpvScripts.mpris ]; }; })
      ];
    };
  };
}
