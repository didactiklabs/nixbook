{
  config,
  pkgs,
  lib,
  username,
  ...
}: let
in {
  config = {
    services.greetd = {
      enable = true;
      settings = rec {
        initial_session = {
          command = "${pkgs.swayfx}/bin/sway";
          user = "${username}";
        };
        default_session = initial_session;
      };
    };
  };
}
