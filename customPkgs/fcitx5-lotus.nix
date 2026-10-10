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
# We callPackage upstream's package expression (nix/packages/fcitx5-lotus/
# default.nix) but build the npins source instead of the one it fetches: its
# hard-coded version/hash lag behind the release tags (v5.0.0 still fetched
# v4.0.1, whose data/CMakeLists.txt needs rsvg-convert, not in its inputs).
let
  sources = import ../npins;
  pin = sources.fcitx5-lotus;
in
(pkgs.callPackage (pin + "/nix/packages/fcitx5-lotus/default.nix") { }).overrideAttrs {
  version = pkgs.lib.removePrefix "v" pin.version;
  src = pin;
}
