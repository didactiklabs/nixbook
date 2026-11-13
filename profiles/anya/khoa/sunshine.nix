{ config, pkgs, ... }:
let
  swaymsg = "${pkgs.swayfx}/bin/swaymsg";
  # The headless output's resting mode, set in ./swayConfig.nix.
  restingMode = config.wayland.windowManager.sway.config.output."HEADLESS-1".mode;
  # Each stream gets the client's own size and frame rate: the headless
  # output (no monitor) can take any mode, so a 1080p laptop or a 120 Hz
  # tablet is sent native frames instead of a 2560x1440@60 picture rescaled
  # on its side. Sunshine sets SUNSHINE_CLIENT_* for the app's commands.
  matchClient = pkgs.writeShellScript "sunshine-match-client" ''
    w=''${SUNSHINE_CLIENT_WIDTH:-}
    h=''${SUNSHINE_CLIENT_HEIGHT:-}
    fps=''${SUNSHINE_CLIENT_FPS:-60}
    [ -n "$w" ] && [ -n "$h" ] || exit 0
    exec ${swaymsg} output HEADLESS-1 mode "''${w}x''${h}@''${fps}Hz"
  '';
  sunshineApps = {
    env.PATH = "$(PATH):$(HOME)/.local/bin";
    apps = [
      {
        name = "Desktop";
        image-path = "desktop.png";
        prep-cmd = [
          {
            do = "${matchClient}";
            undo = "${swaymsg} output HEADLESS-1 mode ${restingMode}";
          }
        ];
      }
    ];
  };
in
{
  config = {
    home = {
      packages = [ pkgs.sunshine ];
      file.".config/sunshine/apps.json".text = builtins.toJSON sunshineApps;
    };
  };
}
