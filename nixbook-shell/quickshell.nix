{ pkgs, quickshellSrc }:
# Quickshell for nixbook-shell: `quickshellSrc` (a quickshell checkout: the npins
# pin, see default.nix) plus one crash fix.
#
# patches/quickshell-screencopy-raw-wl-output.patch: the wlr-screencopy
# output-transform query bound a Qt-wrapped wl_output, which niri's
# wl_surface.enter made QtWayland mistake for a screen -> SIGSEGV in
# QWaylandSurface::oldestEnteredScreen on output changes (sleep/lock/DPMS) after
# any screenshot/region selection. With the shell dead the session stayed
# locked on niri's blank fallback screen. Upstream: quickshell issue #1202
# (open); drop the patch once it is fixed there.
let
  quickshellOverlay = (import "${quickshellSrc}/overlay.nix") {
    rev = quickshellSrc.revision;
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
