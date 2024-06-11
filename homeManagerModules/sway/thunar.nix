{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.customHomeManagerModules;
in {
  config = lib.mkIf cfg.sway.enable {
    home.packages = [
      (
        pkgs.xfce.thunar.override {
          thunarPlugins = [
            pkgs.xfce.thunar-archive-plugin
            pkgs.xfce.thunar-volman
            pkgs.xfce.xfconf
            pkgs.xfce.tumbler
            pkgs.xfce.exo
          ];
        }
      )
      pkgs.ntfs3g
      pkgs.gparted
      pkgs.gnome.file-roller
      ## image preview looks bugged atm
      (pkgs.ranger.override {
        imagePreviewSupport = true;
      })
    ];

    #services.udiskie.enable = true;
    home.file = {
      ".config/xfce4/helpers.rc".text = ''
        TerminalEmulator=alacritty
      '';
    };
  };
}
###
###        ${if (sysConfig.networking.hostName == "olp00002988"
###          || sysConfig.networking.hostName == "desktop") then ''
###            smb://oscaroad.com/partages/
###            smb://oscaroad.com/partages/Infra/Exploitation/3_KP/
###          '' else
###          ""}

