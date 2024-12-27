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
        url = "https://i.imgur.com/Rihm7pX.jpeg";
        sha256 = "sha256-ERsn/IJXrx87n4om66A9ajYczCRSJHXaqSfBKzOVOz0=";
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
