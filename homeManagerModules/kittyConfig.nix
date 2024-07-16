{ lib, ... }: {
  programs = {
    kitty = {
      enable = true;
      shellIntegration.enableZshIntegration = true;
      settings = {
        copy_on_select = true;
        font_size = lib.mkForce "10.0";
        font_family = "Hack Nerd Font Bold";
      };
    };
    ranger = {
      extraConfig = ''
        set preview_images true
        set preview_images_method kitty
        set preview_files true
      '';
    };
    zsh.shellAliases = { ssh = "kitten ssh"; };
  };
}
