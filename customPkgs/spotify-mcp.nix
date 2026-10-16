{ pkgs }:
# MCP server for the Spotify desktop app: playback through its MPRIS
# interface (playerctl), plus search, queue and playlists through the Spotify
# Web API once logged in with the user's own developer app (OAuth PKCE). The
# source lives in ./spotify-mcp (no upstream). To update a dependency, edit its
# package.json, run `npm install` there and refresh npmDepsHash with
# `prefetch-npm-deps package-lock.json`.
pkgs.buildNpmPackage {
  pname = "spotify-mcp";
  version = "0.1.0";
  src = ./spotify-mcp;
  npmDepsHash = "sha256-EX7BH6raHPWyPVxiikjagxKK2dKdnZszTfZn95mXv3E=";
  dontNpmBuild = true;
  nativeBuildInputs = [ pkgs.makeWrapper ];
  # The tests use a fake playerctl and a mock of Spotify's API on 127.0.0.1.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    npm test
    runHook postCheck
  '';
  postInstall = ''
    wrapProgram $out/bin/spotify-mcp \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.playerctl
          pkgs.xdg-utils
        ]
      }
  '';

  meta = {
    description = "MCP server controlling the Spotify desktop app (MPRIS) and the Spotify Web API";
    license = pkgs.lib.licenses.mit;
    mainProgram = "spotify-mcp";
  };
}
