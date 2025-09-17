{
  config,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules;
in
{
  config = lib.mkIf cfg.niriConfig.enable {
    programs.niri.settings.outputs = lib.mkForce {
      "*" = {
        scale = 1.0;
        position = {
          x = 0;
          y = 0;
        };
      };
      "eDP-1" = {
        scale = 1.6;
        position = {
          x = 0;
          y = 755;
        };
      };
      "DP-8" = {
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60.0;
        };
        position = {
          x = 1800;
          y = 230;
        };
      };
      "DP-9" = {
        mode = {
          width = 2560;
          height = 1440;
          refresh = 60.0;
        };
        position = {
          x = 3720;
          y = 0;
        };
      };
      "DP-10" = {
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60.0;
        };
        position = {
          x = 1800;
          y = 0;
        };
      };
      "DP-11" = {
        mode = {
          width = 1920;
          height = 1080;
          refresh = 60.0;
        };
        position = {
          x = 3720;
          y = 0;
        };
      };
    };

    # Port workspace assignments from hyprland to output assignments
    programs.niri.settings.window-rules = lib.mkAfter [
      # Apps that were on workspace 1 -> assign to main monitor (DP-9)
      {
        matches = [ { app-id = "^thunderbird$"; } ];
        open-on-output = "eDP-1";
      }
      {
        matches = [ { app-id = "^vesktop$"; } ];
        open-on-output = "eDP-1";
      }
      {
        matches = [ { title = "^Spotify Premium$"; } ];
        open-on-output = "eDP-1";
      }
      {
        matches = [ { app-id = "^spotify$"; } ];
        open-on-output = "eDP-1";
      }
      {
        matches = [ { app-id = "^signal$"; } ];
        open-on-output = "eDP-1";
      }
      # Apps that were on workspace 3 -> assign to secondary monitor (DP-10)
      {
        matches = [ { app-id = "^com\\.moonlight_stream\\.Moonlight$"; } ];
        open-on-output = "DP-9";
      }
      {
        matches = [ { app-id = "^mpv$"; } ];
        open-on-output = "DP-9";
      }
    ];
  };
}
