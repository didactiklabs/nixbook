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
        url = "https://i.imgur.com/tNCwJVw.jpeg";
        sha256 = "sha256-PDxukLoOUvlQQy7C0UtOqi+G2G/KXTuD+J62IphMLFw=";
      };
    in
    "${image}";
in
{
  config = lib.mkIf cfg.fastfetchConfig.enable {
    home = {
      file.".config/fastfetch/logo" = {
        source = lib.mkForce logo;
      };
    };
  };
}
