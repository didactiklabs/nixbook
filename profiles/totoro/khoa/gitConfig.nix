{ config, lib, ... }:
let
  cfg = config.customHomeManagerModules.gitConfig;
in
{
  config = lib.mkIf cfg.enable {
    programs.git = {
      settings = {
        user = {
          name = "Victor Hang";
          email = "vhvictorhang@gmail.com";
        };
      };
      signing = {
        signByDefault = lib.mkForce true;
      };
    };
  };
}
