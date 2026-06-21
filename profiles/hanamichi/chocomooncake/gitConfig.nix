{ config, lib, ... }:
let
  cfg = config.customHomeManagerModules.gitConfig;
in
{
  config = lib.mkIf cfg.enable {
    programs.git = {
      settings = {
        user = {
          name = "dieu";
          email = "dieu@example.com";
        };
      };
    };
  };
}
