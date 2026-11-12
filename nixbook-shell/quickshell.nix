{ pkgs, quickshellSrc }:
# Quickshell for nixbook-shell: `quickshellSrc` (a quickshell checkout: the npins
# pin, see default.nix) plus two crash fixes and one for how animations are
# paced.
#
# patches/quickshell-screencopy-raw-wl-output.patch: the wlr-screencopy
# output-transform query bound a Qt-wrapped wl_output, which niri's
# wl_surface.enter made QtWayland mistake for a screen -> SIGSEGV in
# QWaylandSurface::oldestEnteredScreen on output changes (sleep/lock/DPMS) after
# any screenshot/region selection. With the shell dead the session stayed
# locked on niri's blank fallback screen. Upstream: quickshell issue #1202
# (open); drop the patch once it is fixed there.
#
# patches/quickshell-icon-loader-mutex.patch: Qt Quick runs the `image://icon`
# provider on its pixmap reader thread for asynchronous Images (Wayland reports
# ThreadedPixmaps) while the GUI thread loads icons too, and QIconLoader isn't
# thread-safe: two threads loading the same theme icon (at startup, YouTube
# Music's pear-desktop.png from the dock and an async Image) swapped its shared
# base pixmap under each other -> "pure virtual method called" in
# QPlatformPixmap::fromFile, SIGABRT a few seconds after (re)start. Every theme
# icon lookup in quickshell now holds one mutex.
#
# patches/quickshell-frame-synced-animations.patch: Qt Quick's threaded render
# loop steps animations with the frames of the window only while exactly one
# window is exposed. A shell has dozens of layer surfaces, so it used the
# fallback: a 16 ms system timer on a 60 Hz screen, 62.5 steps a second for 60
# frames. Measured on totoro over a 6 s linear animation: 14 of 347 frames
# showed a double step, the animation took 5.79 s, and each time an animation
# started from rest (a hover, the resources widget every 3 s, a progress line
# every second) the render loop made all ~25 mapped windows render and present
# a frame, ~50 ms of the GUI thread synchronizing them one by one. The patch
# installs its own animation driver (src/core/frameanimationdriver.cpp): one
# step after each frame a window was synchronized for, a timer only while
# nothing renders; 360 of 360 frames with a single step, 6.00 s, only the
# windows that change are drawn, and an animation started from rest shows in
# the next frame (its first changed frame is synchronized 1-2 ms after the
# start instead of 17-22 ms). QS_FRAME_SYNCED_ANIMATIONS=0 in the shell's
# environment gives Qt's driver back.
let
  quickshellOverlay = (import "${quickshellSrc}/overlay.nix") {
    rev = quickshellSrc.revision;
  };
  upstream = (quickshellOverlay pkgs pkgs).quickshell;
  unwrapped = upstream.unwrapped.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./patches/quickshell-screencopy-raw-wl-output.patch
      ./patches/quickshell-icon-loader-mutex.patch
      ./patches/quickshell-frame-synced-animations.patch
    ];
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
