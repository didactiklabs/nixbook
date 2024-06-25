{pkgs, ...}: let
  sunshineAppsJson = ''
    {
      "env": {
        "PATH": "$(PATH):$(HOME)/.local/bin"
      },
      "apps": [
        {
          "name": "Desktop",
          "image-path": "desktop.png"
        },
        {
          "name": "Steam Big Picture",
          "detached": [
            "setsid steam steam://open/bigpicture"
          ],
          "image-path": "steam.png"
        }
      ]
    }
  '';
in {
  config = {
    home.packages = [pkgs.sunshine];
    home.file.".config/sunshine/apps.json" = {
      text = sunshineAppsJson;
    };
  };
}
