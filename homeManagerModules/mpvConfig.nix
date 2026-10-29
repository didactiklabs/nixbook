{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.customPkgs) ytui jtui;
  cfg = config.customHomeManagerModules;
  # modernx, patched (mpv/modernx-nixbook.patch): an HD button left of info
  # opening mpv/upscale.lua's picture menu (right click: upscaling off; the
  # icon dimmed while nothing is on), and the audio and subtitle buttons
  # opening mpv's own track picker (select.lua; right click: the next one)
  # instead of stepping through the tracks. Its source has Windows line
  # endings: made plain before the patch.
  modernx = pkgs.mpvScripts.modernx.overrideAttrs (old: {
    prePatch = (old.prePatch or "") + ''
      sed -i 's/\r$//' modernx.lua
    '';
    patches = (old.patches or [ ]) ++ [ ./mpv/modernx-nixbook.patch ];
  });
  # The shaders, in one folder: Anime4K, FSRCNNX (live action), adaptive-
  # sharpen and chroma from luma (always on: cleaner colour edges), each
  # pinned at its author's release or commit.
  shaderFile =
    url: sha256:
    pkgs.fetchurl {
      inherit url sha256;
    };
  extraShaders = {
    "CfL_Prediction.glsl" =
      shaderFile "https://raw.githubusercontent.com/Artoriuz/glsl-chroma-from-luma-prediction/066dff964b83aa34e893de25d590874bf8c8e94f/CfL_Prediction.glsl" "05mp2zrs471cigyj4bi1jrrr1jmd3z484nbb4vdxkd5sshw2vlgr";
    "FSRCNNX_x2_8-0-4-1.glsl" =
      shaderFile "https://github.com/igv/FSRCNN-TensorFlow/releases/download/1.1/FSRCNNX_x2_8-0-4-1.glsl" "1bn2ilzg007nxrbg4y81i3rgagsk4ivmjv11hb68alf9q72xn078";
    "FSRCNNX_x2_16-0-4-1.glsl" =
      shaderFile "https://github.com/igv/FSRCNN-TensorFlow/releases/download/1.1/FSRCNNX_x2_16-0-4-1.glsl" "0rcr3hp3mk2pgn2p1xzp7idw4i0a8q61afq5g9zkz6jx3qklm8nm";
    "adaptive-sharpen.glsl" =
      shaderFile "https://gist.githubusercontent.com/igv/8a77e4eb8276753b54bb94c1c50c317e/raw/572f59099cd0e3eb5e321a6da0a3d90a7382e2dc/adaptive-sharpen.glsl" "1r5qgzxlv5fvkiqvlnarv031rg0xdvz1g4ay0ys936mccbbb6zw2";
  };
  # Linked at build time (no readDir of a derivation while evaluating).
  shaders = pkgs.runCommand "mpv-shaders" { } (
    ''
      mkdir $out
      ln -s ${pkgs.anime4k}/*.glsl $out/
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: file: ''
        ln -s ${file} $out/${name}
      '') extraShaders
    )
  );
  # Picture modes on demand: off until the menu or a key (mpv/upscale.lua).
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
      Which networks mpv's picture modes (modernx's HD menu, Ctrl+1…5) load:
      `fast` (Anime4K's M and S, FSRCNNX 8-0-4-1; for integrated GPUs such as
      a Radeon 680M) or `hq` (Anime4K's VL and M, FSRCNNX 16-0-4-1; for a
      dedicated GPU).
    '';
  };

  config = lib.mkIf cfg.desktopApps.enable {
    programs = {
      mpv = {
        enable = true;
        scripts = mpvScripts;
        scriptOpts.upscale = {
          shaders = "${shaders}";
          base = "CfL_Prediction.glsl";
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
