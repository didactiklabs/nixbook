{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
  fastfetchConfig = ''
    {
      "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
    	"logo": {
    		"source": "~/.config/fastfetch/ascsiiArt",

    		"type": "file",
    		"padding": {
    			"top": 0,
    			"left": 0
    		}
    	},
      "display": {
        "separator": "    "
      },
      "modules": [
        {
          "type": "custom",
          "format": "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
        },
        "break",
        {
          "type": "os",
          "key": "  ",
          "keyColor": "blue"
        },
        {
          "type": "kernel",
          "key": "  ",
          "keyColor": "white"
        },
        {
          "type": "packages",
          "key": "  󰮯",
          "keyColor": "yellow"
        },
        {
          "type": "wm",
          "key": "  󰨇",
          "keyColor": "blue"
        },
        {
          "type": "terminal",
          "key": "  ",
          "keyColor": "magenta"
        },
        {
          "type": "shell",
          "key": "  ",
          "keyColor": "yellow"
        },
        "break",
        {
          "type": "custom",
          "format": "┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
        },
        "break",
        {
          "type": "host",
          "key": "  ",
          "keyColor": "bright_blue"
        },
        {
          "type": "cpu",
          "key": "  ",
          "keyColor": "bright_green"
        },
        {
          "type": "gpu",
          "key": "  󱤓",
          "keyColor": "red"
        },
        {
          "type": "memory",
          "key": "  󰍛",
          "keyColor": "bright_yellow"
        },
        {
          "type": "disk",
          "key": "  ",
          "keyColor": "bright_cyan"
        },
        "break",
        {
          "type": "custom",
          "format": "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
        }
      ]
    }
  '';
  ascsiiArt = ''


    ⠀⢀⣣⠏⠀⠀⠀⠀⡟⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⠃⠀⠀⠀⣧⣀⡀
    ⠀⢼⠏⠀⠀⠀⠀⢠⡃⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠐⣗⠀⠀⠀⣰⡟⠀⠀
    ⠀⡾⠀⢀⣀⣰⣤⣼⣷⣼⣿⣷⣮⣕⡒⠤⠀⠀⠀⠀⠀⠀⠙⣦⣤⣴⡟⠀⠀⢠
    ⢰⡇⢐⣿⠏⠉⠉⠉⠙⠙⠋⠉⠁⠀⠈⠢⣄⡉⠑⠲⠶⣶⣾⣿⣿⣿⣿⣄⣠⣿
    ⢸⡇⣿⡿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⠷⣶⣮⣭⣽⣿⣿⣿⣿⣿⣿⣿
    ⢸⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠹⣿⣿⣿⣿⠿⢿⠟⢁⣭
    ⢸⣿⣿⡇⣀⠠⠀⡀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣄⣀⠀⡠⠨⡙⠻⣿⣿⠏⢠⣏⠳
    ⠘⢿⣿⣿⠀⢱⢉⠿⠳⣆⠀⠀⠀⠀⠩⠋⢲⡿⠈⢙⣶⠄⠘⢆⢹⡟⠀⣿⢿⠀
    ⠀⠈⠻⣿⡇⠈⠄⢿⣤⣬⠀⠀⠀⠀⠀⢀⡈⠻⠶⢾⡟⠀⠀⡸⠀⠀⢔⠅⢚⣴
    ⣄⣴⣾⣿⣿⠀⠀⢑⠒⠋⠀⠀⠀⠀⠀⠀⠀⠉⢏⠀⠀⠀⠔⠀⠀⠀⠁⡤⢿⣿
    ⠿⢿⣿⣿⣿⣷⢴⠟⠀⠀⢀⡀⠀⠀⠀⠀⠀⠀⠙⠵⠤⠊⠀⠀⣼⣿⡏⢀⠔⠁
    ⠀⠀⠹⣿⣿⠟⢮⠀⠀⠀⠈⠉⠁⠀⠀⠀⠀⠀⠀⠁⠀⠀⣠⣾⣿⣿⡷⠉⠀⠀
    ⣆⠀⠀⢿⡇⠀⠀⢱⣤⡀⠀⠉⠛⠋⠉⠁⠀⠀⠀⢀⣴⣾⣿⣿⠟⠛⠢⡄⠀⠀
    ⠈⠀⠀⠸⣿⣆⠀⠀⢿⣿⣦⣀⠀⠀⠀⠀⣀⢤⣾⣿⣿⡿⠟⠁⠀⠀⠀⠹⡄⠀
    ⠀⠀⠀⠀⠀⠈⠀⠀⠀⠛⠛⠿⠷⠒⠒⠯⠀⠀⠶⠾⠋⠀⠀⠀⠀⠀⠀⠀⠿⠄
  '';
in {
  config = lib.mkIf cfg.fastfetchConfig.enable {
    home.packages = [
      pkgs.fastfetch
    ];
    home.file.".config/fastfetch/config.jsonc" = {
      text = fastfetchConfig;
    };
    home.file.".config/fastfetch/ascsiiArt" = {
      text = ascsiiArt;
    };
  };

  options.customHomeManagerModules.fastfetchConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable fastfetchConfig config globally or not.
      '';
    };
  };
}
