{ pkgs }:
let
  sources = import ../npins;
  # The AppImage release asset (URL + hash) is tracked by npins as a `url` pin
  # in npins/sources.json. To bump the version, update that pin's URL (npins
  # will refetch and record the new hash) — nothing here is hardcoded.
  pin = sources.meru;
  pname = "meru";
  # Extract the version from the pinned asset URL (.../download/vX.Y.Z/...).
  version = pkgs.lib.removePrefix "v" (
    builtins.head (builtins.match ".*/download/([^/]+)/.*" pin.url)
  );
  src = pkgs.fetchurl { inherit (pin) url hash; };
  appimageContents = pkgs.appimageTools.extract { inherit pname version src; };
  # Its Pro features on (meru/unlock.py: the licence check, the trial, the
  # updater, the settings' License and Updates pages; Meru is AGPL-3.0). The
  # app is unpacked into resources/app, which Electron loads when there is
  # no app.asar once two of its fuses are off (only from app.asar, the
  # asar's integrity). A release that changes the patched code fails the
  # build.
  unlocked = pkgs.runCommand "meru-${version}-unlocked" { nativeBuildInputs = [ pkgs.asar ]; } ''
    cp -r ${appimageContents} $out
    chmod -R u+w $out
    asar extract $out/resources/app.asar $out/resources/app
    rm -rf $out/resources/app.asar $out/resources/app.asar.unpacked
    ${pkgs.python3}/bin/python3 ${./meru/unlock.py} $out/resources/app $out/meru
  '';
in
pkgs.appimageTools.wrapAppImage {
  inherit pname version;
  src = unlocked;

  # Its launcher entry and icons. The entry offers it for mailto: links,
  # never for http(s) ones (it would be a browser candidate).
  extraInstallCommands = ''
    install -m 444 -D ${unlocked}/meru.desktop $out/share/applications/${pname}.desktop
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=AppRun %U' 'Exec=${pname} %U' \
      --replace-fail 'x-scheme-handler/http;x-scheme-handler/https;' ""
    for size in 16 32 48 64 128 256 512; do
      install -m 444 -D ${unlocked}/usr/share/icons/hicolor/''${size}x''${size}/apps/meru.png \
        $out/share/icons/hicolor/''${size}x''${size}/apps/meru.png
    done
  '';

  # It runs from the unpacked tree: how nixbook-electron-app recognises its
  # processes (lib/electronA11y.nix).
  passthru = {
    electronMarkers = [ "${unlocked}" ];
    inherit unlocked;
  };

  meta = {
    description = "Gmail as a desktop app (Electron), its Pro features on";
    homepage = "https://meru.so";
    license = pkgs.lib.licenses.agpl3Only;
    mainProgram = pname;
  };
}
