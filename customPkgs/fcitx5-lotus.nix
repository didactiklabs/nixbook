{ pkgs }:
# Fcitx5 Lotus: an open-source Vietnamese input method for fcitx5 aiming at a
# smooth, underline-free typing experience.
#
# https://github.com/LotusInputMethod/fcitx5-lotus
#
# Unlike a plain fcitx5 addon (e.g. unikey), Lotus ships a privileged uinput
# server plus udev rules and a per-user systemd service, so it needs the
# companion NixOS module in nixosModules/fcitx5-lotus.nix to function.
#
# Upstream's package expression (nix/packages/fcitx5-lotus/default.nix) fetches
# the v3.3.0 release itself via fetchFromGitHub (with submodules + a pinned Go
# vendor hash), so we just callPackage it as-is. The npins pin of the same tag
# is kept for provenance / update tracking.
let
  sources = import ../npins;
in
pkgs.callPackage (sources.fcitx5-lotus + "/nix/packages/fcitx5-lotus/default.nix") { }
