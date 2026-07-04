{ pkgs }:
let
  sources = import ../npins;
  # The AppImage release asset (URL + hash) is tracked by npins as a `url` pin
  # in npins/sources.json. To bump the version, update that pin's URL (npins
  # will refetch and record the new hash) — nothing here is hardcoded.
  pin = sources.actual-budget;
  pname = "actual-budget";
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
    install -m 444 -D ${appimageContents}/actual.desktop $out/share/applications/${pname}.desktop
    install -m 444 -D ${appimageContents}/actual.png $out/share/pixmaps/${pname}.png
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=${pname}'
  '';

  meta = {
    description = "A local-first personal finance app";
    homepage = "https://actualbudget.org";
    mainProgram = pname;
  };
}
