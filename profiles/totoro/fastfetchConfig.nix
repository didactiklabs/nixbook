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
        url = "https://i.imgur.com/xCusJ6d.jpeg";
        sha256 = "sha256-VSOsCTiZP9IEMN69qmhxs4obRVNxpbLf0zUOzz2vjoQ=";
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
