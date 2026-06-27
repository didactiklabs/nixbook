{ pkgs }:
let
  pname = "pear-desktop";
  version = "3.11.0";
  src = pkgs.fetchurl {
    url = "https://github.com/pear-devs/pear-desktop/releases/download/v${version}/YouTube-Music-${version}.AppImage";
    hash = "sha256-z8Cg1b5iReLGW/5UN0c5m2v3wCpJzifharmdFDtoBW0=";
  };
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
