{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.customPkgs) ytui jtui;
  cfg = config.customHomeManagerModules;
  # modernx with an "Upscale" button left of info (mpv/upscale.lua's modes:
  # left click the next one, right click off; the HD icon dimmed while off).
  # Its source has Windows line endings: made plain before the patch.
  modernx = pkgs.mpvScripts.modernx.overrideAttrs (old: {
    prePatch = (old.prePatch or "") + ''
      sed -i 's/\r$//' modernx.lua
    '';
    patches = (old.patches or [ ]) ++ [ ./mpv/modernx-upscale-button.patch ];
  });
  # Anime4K on demand: off until the button or Ctrl+1/2/3 (Ctrl+0: off).
  upscale = pkgs.mpvScripts.buildLua {
    pname = "nixbook-upscale";
    version = "1";
    src = ./mpv;
    scriptPath = "upscale.lua";
  };
  mpvScripts = with pkgs.mpvScripts; [
    thumbfast
    mpris
    modernx
    upscale
  ];
in
{
  options.customHomeManagerModules.desktopApps.mpvUpscaleQuality = lib.mkOption {
    type = lib.types.enum [
      "fast"
      "hq"
    ];
    default = "fast";
    description = ''
      Which Anime4K networks mpv's Upscale button (modernx, Ctrl+1/2/3) loads:
      `fast` (the M and S ones, for integrated GPUs such as a Radeon 680M) or
      `hq` (VL and M, for a dedicated GPU).
    '';
  };

  config = lib.mkIf cfg.desktopApps.enable {
    programs = {
      mpv = {
        enable = true;
        scripts = mpvScripts;
        scriptOpts.upscale = {
          shaders = "${pkgs.anime4k}";
          quality = cfg.desktopApps.mpvUpscaleQuality;
        };
        config = {
          # Hardware decoding (VA-API on AMD/Intel, NVDEC on NVIDIA) instead
          # of the CPU: far less power and heat for video. auto-safe only
          # picks decoders known to be correct, and falls back to software.
          hwdec = "auto-safe";
          vo = "gpu-next";
          # modernx draws the controls: mpv's own OSC off, or both show.
          osc = "no";
          # mpv's built-in quality profile (ewa_lanczossharp upscaling, HDR
          # peak detection), and debanding: anime's gradients band.
          profile = "high-quality";
          deband = "yes";
          # Direct play over the network (Jellyfin through a VPN): a deeper
          # buffer rides out a slow moment.
          cache = "yes";
          demuxer-max-bytes = "1GiB";
          demuxer-readahead-secs = 120;
        };
      };
    };
    home = {
      packages = [
        jtui
        ytui
        pkgs.yt-dlp
      ];
    };
  };
}
