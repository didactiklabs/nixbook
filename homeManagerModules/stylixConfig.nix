{
  config,
  pkgs,
  lib,
  ...
}: let
  stylix = pkgs.fetchFromGitHub {
    owner = "danth";
    repo = "stylix";
    rev = "release-22.11";
    sha256 = "103gcprgc6fpbkc9rpnk0rwlcaxi0brkkxls9v75lp1wg68jrz2c";
  };
in {
  imports = [(import stylix).homeManagerModules.stylix];

  stylix = {
    enable = true;
    image = /home/khoa/Wallpapers/001.jpg;
  };
}
