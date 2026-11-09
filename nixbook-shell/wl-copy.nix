# `wl-copy` that keeps text as text (scripts/wl-copy-text.sh), with the rest
# of wl-clipboard (wl-paste) beside it. Put before wl-clipboard on the PATH:
# the shell's runtime PATH (package.nix) and, in nixbook, the system's
# (nixosModules/niri.nix, with a higher priority than wl-clipboard).
{ pkgs }:
let
  wlCopy = pkgs.writeShellScriptBin "wl-copy" ''
    NB_WL_COPY=${pkgs.wl-clipboard}/bin/wl-copy
    NB_FILE=${pkgs.file}/bin/file
    ${builtins.readFile ./scripts/wl-copy-text.sh}
  '';
in
pkgs.symlinkJoin {
  name = "wl-clipboard-text-${pkgs.wl-clipboard.version}";
  paths = [
    wlCopy
    pkgs.wl-clipboard
  ];
  # symlinkJoin keeps the first path's file when two have the same name.
  inherit (pkgs.wl-clipboard) meta;
}
