{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  options.customHomeManagerModules.desktopApps = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable a curated set of GUI desktop applications.

        Installs and configures:
          Documents / media viewers:
            - zathura   — lightweight keyboard-driven PDF viewer
            - imv       — minimal Wayland image viewer (set as default for images)

          Communication & entertainment:
            - vesktop    — custom Discord client (Vencord-patched)
            - spotify    — music streaming client

          Creation & recording:
            - obs-studio — screen/audio recording and streaming
            - pinta      — simple Paint-like image editor

          Display management:
            - wdisplays  — Wayland display arrangement GUI (arandr equivalent)

          Browser:
            - firefox    — set as default for http/https/text/html MIME types

          File management (dolphinConfig.nix, active when this is enabled):
            - dolphin + dolphin-plugins, ark, kio-admin, ffmpegthumbs,
              kpeople, kservice, ntfs3g, gparted

          Media playback (mpvConfig.nix, active when this is enabled):
            - mpv with thumbfast, mpris, and modernx scripts
            - yt-dlp (YouTube/media downloader)
            - ytui (YouTube TUI), jtui (JSON viewer TUI)
      '';
    };
  };
  config = lib.mkIf cfg.desktopApps.enable {
    programs = {
      zathura.enable = true;
      imv.enable = true;
    };
    home.packages = with pkgs; [
      # apps
      spotify
      obs-studio
      wdisplays # display manager
      vesktop # discord
      pinta # paint
      firefox
    ];
  };
}
