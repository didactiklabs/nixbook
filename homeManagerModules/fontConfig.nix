{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.customHomeManagerModules.fontConfig;
in
{
  options.customHomeManagerModules.fontConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        whether to enable font config globally or not
      '';
    };
  };
  config = lib.mkIf cfg.enable {
    # cf https://nix-community.github.io/home-manager/options.html#opt-fonts.fontconfig.enable
    # cf https://github.com/nix-community/home-manager/blob/master/modules/misc/fontconfig.nix#blob-path
    # cf https://nixos.wiki/wiki/Fonts
    fonts.fontconfig.enable = true;
    home.packages = [
      (pkgs.nerdfonts.override {
        fonts = [
          "FiraCode"
          "Hack"
          "Iosevka"
          "JetBrainsMono"
        ];
      })
      pkgs.font-awesome
    ];
  };
}
