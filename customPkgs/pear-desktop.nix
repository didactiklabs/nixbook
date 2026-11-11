# YouTube Music (pear-desktop): nixpkgs' build (from source, on nixpkgs'
# Electron, in cache.nixos.org) wrapped for nixbook. It replaced the upstream
# AppImage, which ran under XWayland with no GPU process: software
# compositing, and the window never throttled while hidden (renderer ~23% CPU
# paused, ~43% playing, versus ~5% / ~8% for this build). nixpkgs' wrapper
# starts it as a native Wayland client under NIXOS_OZONE_WL.
#
# The wrapper adds:
# - the launcher entry named "YouTube Music" (nixpkgs calls it "Pear
#   Desktop"), under the desktop id matching the Wayland app-id
#   (com.github.th-ch.youtube-music) so docks and window lists find its icon,
#   plus a hidden `pear-desktop.desktop` alias: saved window layouts and the
#   desktop agents' memory launch it by that id.
# - the "performance-improvement" plugin ("Performance improvement [Beta]")
#   turned off at every start. Its "CPU Tamer by AnimationFrame" runs a 1 ms
#   infinite CSS animation on a hidden element as a timer clock: a style
#   recalc on every frame while the window shows (measured on totoro's
#   2880x1800 at 1.6, the home page idle: renderer 22 % CPU with it, 8 %
#   without; over a day of use it averaged 25 %). Its name makes it look
#   worth turning on, so a choice made in the Plugins menu doesn't stick.
# - the menu bar hidden once (Options > hide menu, Alt shows it): Electron
#   draws it itself on Wayland, a light strip over the dark app. Shown again
#   from the app, it stays (.nixbook-defaults remembers what was set once).
{ pkgs }:
let
  inherit (pkgs) lib;
  app = pkgs.pear-desktop;
  appId = "com.github.th-ch.youtube-music";
  launcher = pkgs.writeShellScript "pear-desktop" ''
    dir="''${XDG_CONFIG_HOME:-$HOME/.config}/YouTube Music"
    cfg="$dir/config.json" once="$dir/.nixbook-defaults"
    # config.json is written by the app on its first start: from the next one.
    if [ -f "$cfg" ]; then
      filter='.plugins["performance-improvement"].enabled = false'
      ${lib.getExe pkgs.gnugrep} -qx hideMenu "$once" 2>/dev/null || filter="$filter | .options.hideMenu = true"
      tmp=$(mktemp "$cfg.XXXXXX") \
        && ${lib.getExe pkgs.jq} "$filter" "$cfg" >"$tmp" \
        && { ${pkgs.diffutils}/bin/cmp -s "$tmp" "$cfg" && rm -f "$tmp" || mv "$tmp" "$cfg"; } \
        && { ${lib.getExe pkgs.gnugrep} -qx hideMenu "$once" 2>/dev/null || echo hideMenu >>"$once"; } \
        || rm -f "$tmp"
    fi
    exec ${lib.getExe app} "$@"
  '';
  desktopEntry =
    extra:
    lib.generators.toINI { } {
      "Desktop Entry" = {
        Type = "Application";
        Name = "YouTube Music";
        GenericName = "Music Player";
        Comment = "YouTube Music desktop app (pear-desktop)";
        Exec = "pear-desktop %u";
        Icon = "pear-desktop";
        StartupWMClass = appId;
        Categories = "AudioVideo;Audio;Player;";
        Keywords = "youtube;music;pear;";
      }
      // extra;
    };
in
pkgs.runCommand "pear-desktop-${app.version}"
  {
    inherit (app) version;
    # Its processes run from nixpkgs' pear-desktop: how nixbook-electron-app
    # recognises them (lib/electronA11y.nix).
    passthru.electronMarkers = [ "${app}" ];
    meta = app.meta // {
      mainProgram = "pear-desktop";
    };
  }
  ''
    mkdir -p $out/bin $out/share/applications
    ln -s ${launcher} $out/bin/pear-desktop
    ln -s ${app}/share/icons $out/share/icons
    cat >$out/share/applications/${appId}.desktop <<'EOF'
    ${desktopEntry { }}
    EOF
    cat >$out/share/applications/pear-desktop.desktop <<'EOF'
    ${desktopEntry { NoDisplay = true; }}
    EOF
  ''
