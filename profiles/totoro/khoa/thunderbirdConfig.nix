{ config, lib, ... }:
let
  cfg = config.customHomeManagerModules.thunderbirdConfig;
in
{
  config = lib.mkIf cfg.enable {
    accounts.email.accounts.personal = {
      primary = true;
      address = "vhvictorhang@gmail.com";
      realName = "Victor Hang";
      thunderbird.enable = true;
    };

    programs.thunderbird = {
      enable = true;
      profiles = {
        personal = {
          isDefault = true;
        };
      };
    };
  };
}
