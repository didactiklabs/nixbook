{
  config = {
    programs.zsh = {
      shellAliases = {
        # One-shot boot into Windows through systemd-boot's auto-detected entry
        # (no hard-coded firmware entry number, which changes after a BIOS reset).
        windows = "systemctl reboot --boot-loader-entry=auto-windows";
      };
    };
  };
}
