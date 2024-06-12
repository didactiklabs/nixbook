{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;

  rofi-repo = pkgs.fetchFromGitHub {
    owner = "adi1090x";
    repo = "rofi";
    rev = "master";
    sha256 = "sha256-G3sAyIZbq1sOJxf+NBlXMOtTMiBCn6Sat8PHryxRS0w=";
  };

  rofi-themes =
    pkgs.runCommand "rofi-themes" {
      buildInputs = [rofi-repo];
    } ''
      mkdir -p $out/files/colors
      cp -r ${rofi-repo}/files/applets $out/files
      cp -r ${rofi-repo}/files/images $out/files
      cp -r ${rofi-repo}/files/launchers $out/files
      cp -r ${rofi-repo}/files/powermenu $out/files
      cp -r ${rofi-repo}/files/scripts $out/files
      cp -r ${rofi-repo}/files/config.rasi $out/files
      cp -r ${rofi-repo}/files/colors/${cfg.rofiConfig.color}.rasi $out/files/colors/onedark.rasi
    '';
in {
  # https://github.com/adi1090x/rofi
  config = lib.mkIf cfg.rofiConfig.enable {
    home.packages =
      if cfg.sway.enable
      then [pkgs.rofi-wayland]
      else [pkgs.rofi];
    home.file.".config/rofi".source = "${rofi-themes}/files";
  };

  options.customHomeManagerModules.rofiConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable Rofi config globally or not.
      '';
    };
    launcher.type = lib.mkOption {
      type = lib.types.str;
      default = "type-1";
      description = ''
        Select launcher type.
      '';
    };
    launcher.style = lib.mkOption {
      type = lib.types.str;
      default = "style-1";
      description = ''
        Select launcher style.
      '';
    };
    color = lib.mkOption {
      type = lib.types.str;
      default = "onedark";
      description = ''
        Select color.
      '';
    };
  };
}
