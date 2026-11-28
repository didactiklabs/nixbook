{ config, lib, ... }:
let
  cfg = config.customHomeManagerModules.gitConfig;
in
{
  # totoro's identity. Commits aren't signed by default here (totoro's are):
  # turn signByDefault on once talia has the signing key.
  config = lib.mkIf cfg.enable {
    programs.git.settings.user = {
      name = "Victor Hang";
      email = "vhvictorhang@gmail.com";
    };
  };
}
