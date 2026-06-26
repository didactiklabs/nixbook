{ pkgs }:
# Schnelle Umlaute: a native fcitx5 addon for fast accent/umlaut input using a
# hold-letter + Space gesture (hold "a", tap Space -> ä; release without Space
# -> normal "a"). PowerToys Quick Accent alternative for Linux.
#
# https://github.com/Maik-0000FF/schnelle-umlaute
#
# Upstream ships `nix/package.nix` as a plain callPackage derivation that takes
# the whole repo as `src`. We pin the repo via npins and build it against this
# system's nixpkgs (so it links the same fcitx5/Qt as the rest of the config).
let
  sources = import ../npins;
in
pkgs.callPackage (sources.schnelle-umlaute + "/nix/package.nix") {
  src = sources.schnelle-umlaute;
}
