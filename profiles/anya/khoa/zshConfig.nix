{
  config = {
    programs.zsh = {
      shellAliases = {
        windows = "sudo efibootmgr -n 0002 && sudo reboot";
      };
    };
  };
}
