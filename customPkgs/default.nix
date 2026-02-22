{ pkgs, ... }:
{
  goji = import ./goji.nix { inherit pkgs; };
  songbird = import ./songbird.nix { inherit pkgs; };
  okada = import ./okada.nix { inherit pkgs; };
  ginx = import ./ginx.nix { inherit pkgs; };
  kl = import ./kl.nix { inherit pkgs; };
  witr = import ./witr.nix { inherit pkgs; };
  pvmigrate = import ./pvmigrate.nix { inherit pkgs; };
  jtui = import ./jtui.nix { inherit pkgs; };
  ytui = import ./ytui.nix { inherit pkgs; };
}
