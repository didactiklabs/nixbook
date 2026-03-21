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
        Whether to enable font installation and fontconfig defaults.

        Installs a curated set of fonts and sets system-wide defaults:
          Default font families (fontconfig):
            - Monospace: Roboto Mono
            - Sans-serif: Roboto
            - Serif: Roboto Serif
            - Emoji: Noto Color Emoji

          Nerd Fonts (patched with icons for terminal use):
            - FiraCode Nerd Font
            - Hack Nerd Font
            - Iosevka Nerd Font
            - JetBrains Mono Nerd Font

          Regular fonts:
            - Inter                — clean sans-serif UI font
            - Roboto / Roboto Mono / Roboto Serif — primary font family
            - Material Design Icons — icon font used by DMS and other widgets
            - Font Awesome         — icon font used by various bars and prompts

        Enables fonts.fontconfig so the user-level fontconfig cache is managed
        by Home Manager.
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
        monospace = [ "Roboto Mono" ];
        sansSerif = [ "Roboto" ];
        serif = [ "Roboto Serif" ];
        emoji = [ "Noto Color Emoji" ];
      };
    };
    home.packages = with pkgs.nerd-fonts; [
      fira-code
      hack
      iosevka
      jetbrains-mono
      pkgs.inter
      pkgs.roboto
      pkgs.roboto-mono
      pkgs.roboto-serif
      pkgs.material-design-icons
      pkgs.font-awesome
    ];
  };
}
