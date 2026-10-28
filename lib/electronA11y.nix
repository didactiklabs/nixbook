# A Chromium/Electron app with its accessibility tree on: started with
# --force-renderer-accessibility, it exposes its buttons, fields and text
# over AT-SPI like a GTK or Qt app does, so the desktop agents read and act
# on it through the app itself (desktop-mcp's ui_read/ui_act), in any
# window, focused or not, without the pointer. Without the switch Chromium
# only builds the tree when a screen reader announces itself, and agents
# see an empty window. It costs the app some CPU and memory (the tree is
# kept up to date), so nixbook-shell's machines use it
# (nixbookShellConfig.electronAccessibility).
#
#   electronA11y pkgs.slack "slack"
#
# The launchers (.desktop files) that run the original binary by its store
# path run the wrapped one instead.
{ pkgs }:
pkg: bin:
pkgs.symlinkJoin {
  name = "${pkg.pname or (pkgs.lib.getName pkg)}-a11y-${pkg.version or ""}";
  paths = [ pkg ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/${bin} --add-flags --force-renderer-accessibility
    if [ -d $out/share/applications ]; then
      for f in $out/share/applications/*.desktop; do
        [ -L "$f" ] || continue
        target=$(readlink -f "$f")
        rm "$f"
        sed "s|${pkg}/bin/${bin}|$out/bin/${bin}|g" "$target" > "$f"
      done
    fi
  '';
  inherit (pkg) meta;
  passthru = (pkg.passthru or { }) // {
    unwrapped = pkg;
  };
}
