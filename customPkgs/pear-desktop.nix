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
# - the "performance-improvement" plugin (on by default) turned off once, the
#   first time it is launched with a config that doesn't mention it (a choice
#   made in its Plugins menu is kept). Its "CPU Tamer by AnimationFrame" runs
#   a 1 ms infinite CSS animation on a hidden element as a timer clock: a
#   style recalc on every frame, ~45% CPU on the page's main thread. It skips
#   itself without WebGL, which is why the AppImage never paid for it.
{ pkgs }:
let
  inherit (pkgs) lib;
  app = pkgs.pear-desktop;
  appId = "com.github.th-ch.youtube-music";
  launcher = pkgs.writeShellScript "pear-desktop" ''
    cfg="''${XDG_CONFIG_HOME:-$HOME/.config}/YouTube Music/config.json"
    if [ -f "$cfg" ] && ! ${lib.getExe pkgs.jq} -e '.plugins | has("performance-improvement")' "$cfg" >/dev/null 2>&1; then
      tmp=$(mktemp "$cfg.XXXXXX") \
        && ${lib.getExe pkgs.jq} '.plugins["performance-improvement"] = {enabled: false}' "$cfg" >"$tmp" \
        && mv "$tmp" "$cfg" || rm -f "$tmp"
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
