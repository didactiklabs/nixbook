{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
  rofi-themes = pkgs.fetchFromGitHub {
    owner = "adi1090x";
    repo = "rofi";
    rev = "master";
    sha256 = "sha256-G3sAyIZbq1sOJxf+NBlXMOtTMiBCn6Sat8PHryxRS0w=";
  };
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
        whether to enable rofi config globally or not
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
  };
}
