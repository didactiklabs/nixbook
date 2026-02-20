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
    fonts = {
      # cf https://nix-community.github.io/home-manager/options.html#opt-fonts.fontconfig.enable
      # cf https://github.com/nix-community/home-manager/blob/master/modules/misc/fontconfig.nix#blob-path
      # cf https://nixos.wiki/wiki/Fonts
      fontconfig.enable = true;
      fontconfig.defaultFonts = {
        monospace = [ "Hack Nerd Font" ];
        sansSerif = [ "Inter" ];
        serif = [ "Inter" ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
    home.packages = with pkgs.nerd-fonts; [
      fira-code
      hack
      iosevka
      jetbrains-mono
      pkgs.inter
      pkgs.font-awesome
    ];
  };
}
