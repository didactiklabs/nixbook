{ config, lib, pkgs, ... }:
let cfg = config.customHomeManagerModules.gitConfig;
in {
  config = lib.mkIf cfg.enable {
    programs.git = {
      userName = "Victor Hang";
      userEmail = "vhvictorhang@gmail.com";
      signing = {
        signByDefault = true;
        gpgPath = "${pkgs.gnupg}/bin/gpg2";
        key = null;
      };
    };
  };
}
