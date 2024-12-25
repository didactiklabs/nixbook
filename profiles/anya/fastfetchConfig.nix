{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.customHomeManagerModules;
  logo =
    let
      image = pkgs.fetchurl {
        url = "https://i.imgur.com/bZErzRg.jpeg";
        sha256 = "sha256-Q/kcNUUxjEs6mO1M/2GRB0jjfkMbs5xra9nHIdlMw+A=";
      };
    in
    "${image}";
in
{
  config = lib.mkIf cfg.fastfetchConfig.enable {
    home.file.".config/fastfetch/logo" = {
      source = lib.mkForce logo;
    };
  };
}
