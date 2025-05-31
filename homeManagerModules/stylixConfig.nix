{
  config,
  pkgs,
  ...
}:
{
  config = {
    stylix = {
      enable = true;
      polarity = "dark";
      image = config.profileCustomization.mainWallpaper;
      cursor = {
        package = pkgs.phinger-cursors;
        name = "phinger-cursors-light";
        size = 24;
      };
      fonts = {
        monospace = {
          name = "Hack Nerd Font";
          package = pkgs.nerd-fonts.fira-code;
        };
      };
    };
  };
}
