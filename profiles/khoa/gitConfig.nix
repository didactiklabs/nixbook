{
  config,
  pkgs,
  lib,
  username,
  ...
}: let
  cfg = config.customHomeManagerModules.gitConfig;
in {
  config = lib.mkIf cfg.enable {
    programs.git = {
      userName = "Victor Hang";
      userEmail = "vhvictorhang@gmail.com";
      extraConfig = {
        init = {
          defaultBranch = "main";
        };
        core = {
          editor = "vim";
          excludesFile = "";
        };
        remote = {
          prune = true;
        };
      };
    };
  };
}
