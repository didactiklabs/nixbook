{ pkgs, ... }:
let
  sunshineAppsJson = ''
    {
      "env": {
        "PATH": "$(PATH):$(HOME)/.local/bin"
      },
      "apps": [
        {
          "name": "Desktop",
          "image-path": "desktop.png"
        }
      ]
    }
  '';
in
{
  config = {
    home = {
      packages = [ pkgs.sunshine ];
      file.".config/sunshine/apps.json" = {
        text = sunshineAppsJson;
      };
    };
  };
}
