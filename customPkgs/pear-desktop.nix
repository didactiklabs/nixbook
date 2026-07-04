{ pkgs }:
let
  sources = import ../npins;
  # The AppImage release asset (URL + hash) is tracked by npins as a `url` pin
  # in npins/sources.json. To bump the version, update that pin's URL (npins
  # will refetch and record the new hash) — nothing here is hardcoded.
  pin = sources.pear-desktop;
  pname = "pear-desktop";
  # Extract the version from the pinned asset URL (.../download/vX.Y.Z/...).
  version = pkgs.lib.removePrefix "v" (
    builtins.head (builtins.match ".*/download/([^/]+)/.*" pin.url)
  );
  src = pkgs.fetchurl { inherit (pin) url hash; };
  appimageContents = pkgs.appimageTools.extract { inherit pname version src; };
in
pkgs.appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/youtube-music.desktop $out/share/applications/${pname}.desktop
    install -m 444 -D ${appimageContents}/usr/share/icons/hicolor/1024x1024/apps/youtube-music.png $out/share/pixmaps/${pname}.png
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=${pname} --no-sandbox %U'
  '';

  meta = with pkgs.lib; {
    description = "YouTube Music Desktop Player";
    homepage = "https://github.com/pear-devs/pear-desktop";
    license = licenses.mit;
    mainProgram = pname;
  };
}
