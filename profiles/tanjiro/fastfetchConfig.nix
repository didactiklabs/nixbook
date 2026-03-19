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
        url = "https://i.imgur.com/pn3fGAk.jpeg";
        sha256 = "sha256-JRnRcwlhRT27rcjxyh1ule1kVOpGAVhRv+exZ+Ag93k=";
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
