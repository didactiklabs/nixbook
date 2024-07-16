{ lib, ... }: {
  programs.kitty = {
    enable = true;
    shellIntegration.enableZshIntegration = true;
    settings = {
      copy_on_select = true;
      font_size = lib.mkForce "10.0";
      font_family = "Hack Nerd Font Bold";
    };
  };
}
