{ lib, ... }: {
  programs = {
    kitty = {
      enable = true;
      shellIntegration.enableZshIntegration = true;
      settings = {
        copy_on_select = true;
        font_size = lib.mkForce "10.0";
        font_family = "Hack Nerd Font Bold";
        confirm_os_window_close = 0;
      };
    };
    ranger = {
      extraConfig = ''
        set preview_images true
        set preview_images_method kitty
        set preview_files true
      '';
    };
    zsh.shellAliases = {
      ssh = "kitten ssh";
      sshs = ''
        sshs --template "kitty +kitten ssh {{#if user}}{{user}}@{{/if}}{{destination}}{{#if port}} -p{{port}}{{/if}}"
      '';
    };
  };
}
