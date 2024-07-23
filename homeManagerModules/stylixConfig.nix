{ config, pkgs, ... }: {
  config = {
    stylix = {
      enable = true;
      polarity = "dark";
      image = config.profileCustomization.mainWallpaper;
      cursor = {
        package = pkgs.phinger-cursors;
        name = "phinger-cursors-light";
      };
      fonts.monospace = {
        name = "Hack Nerd Font";
        package = pkgs.nerdfonts;
      };
    };
  };
}
