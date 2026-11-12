{ pkgs }:
# ZenPlay — YouTube as a desktop app (Electron, ISC;
# https://github.com/AX3ON/ZenPlay): a small window around youtube.com with
# an ad blocker (Ghostery's engine, uBlock/AdGuard/Brave lists fetched at
# the first start).
#
# Upstream only releases a .deb for Linux (the repository's sources are
# behind its releases: files the code needs are missing there). The app
# itself, resources/app.asar, is plain JavaScript: it is unpacked from the
# .deb and run on nixpkgs' Electron (a native Wayland client under
# NIXOS_OZONE_WL, GPU compositing), not on the Electron bundled in the .deb.
# zenplay/nixbook.py adjusts it: one instance, hardware acceleration on.
#
# With nixbook-shell it is bridged as "youtube" (lib/electronA11y.nix): the
# desktop agents' `youtube` tool, and the shell's colours in its window and
# in the YouTube page (Settings > Appearance > Color generation > Apps).
let
  inherit (pkgs) lib;
  sources = import ../npins;
  # The .deb release asset (URL + hash) is tracked by npins as a `url` pin in
  # npins/sources.json. To bump the version, update that pin's URL (npins
  # will refetch and record the new hash) — nothing here is hardcoded.
  pin = sources.zenplay;
  pname = "zenplay";
  # Extract the version from the pinned asset URL (.../download/vX.Y.Z/...).
  version = lib.removePrefix "v" (builtins.head (builtins.match ".*/download/([^/]+)/.*" pin.url));
  src = pkgs.fetchurl { inherit (pin) url hash; };
  # The release bundles Electron 41, end-of-life and marked insecure in
  # nixpkgs: the app (a window, a <webview>, a tray icon) runs as well on the
  # current one.
  inherit (pkgs) electron;
  # Its Wayland app-id (Electron's: the app's name in lower case): the
  # launcher entry is named after it so docks and window lists find its
  # icon, and niri's rule keeps its window opaque (niri/niriConfig.nix).
  appId = "zenplay";
in
pkgs.stdenvNoCC.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    pkgs.dpkg
    pkgs.asar
    pkgs.imagemagick
    pkgs.makeWrapper
    pkgs.python3
  ];

  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile $src | tar -x --no-same-owner --no-same-permissions
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/zenplay $out/share/applications $out/bin
    asar extract opt/ZenPlay/resources/app.asar $out/share/zenplay/app
    python3 ${./zenplay/nixbook.py} $out/share/zenplay/app

    for size in 48 128 256 512; do
      mkdir -p $out/share/icons/hicolor/''${size}x''${size}/apps
      magick usr/share/icons/hicolor/1536x1536/apps/zenplay.png -resize ''${size}x''${size} \
        $out/share/icons/hicolor/''${size}x''${size}/apps/zenplay.png
    done

    makeWrapper ${lib.getExe electron} $out/bin/zenplay \
      --add-flags $out/share/zenplay/app \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-wayland-ime=true}}"

    cat >$out/share/applications/${appId}.desktop <<'EOF'
    [Desktop Entry]
    Type=Application
    Name=ZenPlay
    GenericName=YouTube
    Comment=YouTube desktop app with an ad blocker
    Exec=zenplay %U
    Icon=zenplay
    StartupWMClass=${appId}
    Categories=AudioVideo;Video;Player;
    Keywords=youtube;video;zenplay;
    EOF
    runHook postInstall
  '';

  meta = {
    description = "YouTube as a desktop app (Electron), with an ad blocker";
    homepage = "https://github.com/AX3ON/ZenPlay";
    license = lib.licenses.isc;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
  };
}
