{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.sway.enable {
    home.packages = [
      pkgs.wofi
    ];
    ## https://github.com/Misterio77/nix-config
    ## https://cloudninja.pw/docs/wofi.html
    xdg.configFile."wofi/config".text = ''
      image_size=20
      allow_images=true
      insensitive=true
      term=${config.wayland.windowManager.sway.config.terminal}
      run-always_parse_args=true
      run-cache_file=/dev/null
      run-exec_search=true
    '';

    xdg.configFile."wofi/style.css".text = ''
      window {
        margin: 0px;
        border: 1px solid #bd93f9;
        background-color: #282a36;
      }

      #input {
        margin: 5px;
        border: none;
        color: #f8f8f2;
        background-color: #44475a;
      }

      #inner-box {
        margin: 5px;
        border: none;
        background-color: #282a36;
      }

      #outer-box {
        margin: 5px;
        border: none;
        background-color: #282a36;
      }

      #scroll {
        margin: 0px;
        border: none;
      }

      #text {
        margin: 5px;
        border: none;
        color: #f8f8f2;
      }

      #entry:selected {
        background-color: #44475a;
      }
    '';
  };
}
