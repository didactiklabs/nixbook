{
  config = {
    programs.zsh = {
      shellAliases = {
        windows = "sudo efibootmgr -n 0006 && sudo reboot";
      };
    };
  };
}
