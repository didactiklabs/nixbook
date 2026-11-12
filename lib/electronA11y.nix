# A Chromium/Electron app for nixbook-shell's desktop agents.
#
# With its accessibility tree on: started with --force-renderer-accessibility,
# it exposes its buttons, fields and text over AT-SPI like a GTK or Qt app
# does, so the desktop agents read and act on it through the app itself
# (desktop-mcp's ui_read/ui_act), in any window, focused or not, without the
# pointer. Without the switch Chromium only builds the tree when a screen
# reader announces itself, and agents see an empty window. It costs the app
# some CPU and memory (the tree is kept up to date), so nixbook-shell's
# machines use it (nixbookShellConfig.electronAccessibility).
#
# Bridged (nixbookShellConfig.electronBridge, the apps it lists): started
# through nixbook-shell's `nixbook-electron-app APP -- BINARY`, which holds
# the app's DevTools protocol on a private pipe and lets the agents read and
# use its pages like Zen's tabs (desktop-mcp's page_* tools, Discord's own
# `discord` tool), the accessibility flag included.
#
#   electronA11y = import ../lib/electronA11y.nix { inherit pkgs config; };
#   home.packages = [ (electronA11y pkgs.slack "slack") ];
#
# Called with a Home Manager `config`, it decides from nixbookShellConfig:
# the app as it is where nixbook-shell is off, bridged when its binary is in
# electronBridge.apps, its accessibility tree on otherwise. Without `config`
# (`{ pkgs; }`) it only turns the tree on.
#
# Bridged packages carry `nixbookElectronBridge` {app, command, markers,
# a11y, openHosts}: nixbookShellConfig.nix hands the ones installed to the
# watcher (programs.nixbook-shell.electronBridge.apps). `openHosts` are the
# hosts of the links the app opens itself (passed to the launcher as
# --open-host: Electron apps ignore a URL on their command line, the bridge
# navigates the app to it), and `nixbookOpenLinks` (host → the wrapped
# binary) is what a profile hands to zenBrowserConfig.openInApps so those
# links open in the app, from Zen and from other apps.
#
# The launchers (.desktop files) that run the original binary by its store
# path run the wrapped one instead.
{
  pkgs,
  config ? null,
}:
pkg: bin:
let
  inherit (pkgs) lib;
  shell = config.customHomeManagerModules.nixbookShellConfig;
  app = shell.electronBridge.apps.${bin} or null;
  bridged = config != null && shell.electronBridge.enable && app != null;
  a11y = config == null || shell.electronAccessibility;
  launcher = config.programs.nixbook-shell.package.passthru.electronBridge;
  # The links each bridged app opens itself (by its bridge name).
  openHosts =
    {
      youtube-music = [ "music.youtube.com" ];
      gmail = [ "mail.google.com" ];
      youtube = [
        "www.youtube.com"
        "youtube.com"
        "m.youtube.com"
        "youtu.be"
      ];
    }
    .${app} or [ ];
  # What the app's processes name (its store paths, and the ones its package
  # says it runs from: passthru.electronMarkers), for the launcher catching a
  # relaunch and the watcher (programs.nixbook-shell.electronBridge.apps).
  bridge = {
    inherit app a11y;
    command = [ "${pkg}/bin/${bin}" ];
    markers = [ "${pkg}" ] ++ (pkg.electronMarkers or [ ]);
    inherit openHosts;
  };
  wrapped = pkgs.symlinkJoin {
    name = "${pkg.pname or (lib.getName pkg)}-${
      if bridged then "bridged" else "a11y"
    }-${pkg.version or ""}";
    paths = [ pkg ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      ${
        if bridged then
          ''
            rm $out/bin/${bin}
            makeWrapper ${launcher}/bin/nixbook-electron-app $out/bin/${bin} \
              --add-flags "${lib.optionalString (!a11y) "--no-a11y "}${
                lib.concatMapStrings (m: "--marker ${m} ") bridge.markers
              }${lib.concatMapStrings (h: "--open-host ${h} ") openHosts}${app} -- ${pkg}/bin/${bin}"
          ''
        else
          "wrapProgram $out/bin/${bin} --add-flags --force-renderer-accessibility"
      }
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
    passthru =
      (pkg.passthru or { })
      // {
        unwrapped = pkg;
      }
      // lib.optionalAttrs bridged {
        nixbookElectronBridge = bridge;
        nixbookOpenLinks = lib.genAttrs openHosts (_: "${wrapped}/bin/${bin}");
      };
  };
in
if config != null && !shell.enable then
  pkg
else if bridged || a11y then
  wrapped
else
  pkg
