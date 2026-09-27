{ pkgs }:
# Quickshell for nixbook-shell: the npins pin (the same one dmsConfig.nix uses, so the
# two modules never disagree on the QML runtime) plus one crash fix.
#
# patches/quickshell-screencopy-raw-wl-output.patch: the wlr-screencopy
# output-transform query bound a Qt-wrapped wl_output, which niri's
# wl_surface.enter made QtWayland mistake for a screen -> SIGSEGV in
# QWaylandSurface::oldestEnteredScreen on output changes (sleep/lock/DPMS) after
# any screenshot/region selection. With the shell dead the session stayed
# locked on niri's blank fallback screen. Upstream: quickshell issue #1202
# (open); drop the patch once it is fixed there.
let
  sources = import ../../npins;
  quickshellOverlay = (import "${sources.quickshell}/overlay.nix") {
    rev = sources.quickshell.revision;
  };
  upstream = (quickshellOverlay pkgs pkgs).quickshell;
  unwrapped = upstream.unwrapped.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./patches/quickshell-screencopy-raw-wl-output.patch ];
  });
in
# The wrapper copies `unwrapped` by direct reference (it has no source of its
# own to patch), so repoint it at the patched build.
upstream.overrideAttrs (old: {
  installPhase = ''
    mkdir -p $out
    cp -r ${unwrapped}/* $out
  '';
  passthru = old.passthru // {
    inherit unwrapped;
  };
})
