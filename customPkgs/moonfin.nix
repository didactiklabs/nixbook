{ pkgs }:
# Moonfin — Flutter Jellyfin & Emby client (https://github.com/Moonfin-Client/Moonfin-Core).
# Uses the upstream prebuilt AppImage instead of building from source: the
# Flutter build (pubspec IFD, patched plugins) was slow and broke on bumps.
let
  sources = import ../npins;
  # The AppImage release asset (URL + hash) is tracked by npins as a `url` pin
  # in npins/sources.json. To bump the version, update that pin's URL (npins
  # will refetch and record the new hash) — nothing here is hardcoded.
  pin = sources.moonfin;
  pname = "moonfin";
  # Extract the version from the pinned asset URL (.../download/X.Y.Z/...).
  version = pkgs.lib.removePrefix "v" (
    builtins.head (builtins.match ".*/download/([^/]+)/.*" pin.url)
  );
  src = pkgs.fetchurl { inherit (pin) url hash; };
  appimageContents = pkgs.appimageTools.extract { inherit pname version src; };
in
pkgs.appimageTools.wrapType2 {
  inherit pname version src;

  # The sqlite3 Dart package dlopens the system libsqlite3.so (AppRun refuses
  # to start without it). libepoxy and libXv are linked but neither bundled nor
  # in the default AppImage FHS env.
  extraPkgs = p: [
    p.sqlite
    p.libepoxy
    p.libXv
  ];

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/org.moonfin.linux.desktop $out/share/applications/org.moonfin.linux.desktop
    install -m 444 -D ${appimageContents}/org.moonfin.linux.png $out/share/icons/hicolor/512x512/apps/org.moonfin.linux.png
  '';

  meta = with pkgs.lib; {
    description = "Jellyfin & Emby media client";
    homepage = "https://moonfin.app/";
    license = licenses.gpl3Only;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
  };
}
