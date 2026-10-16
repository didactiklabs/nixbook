{ pkgs }:
# MCP server for pear-desktop (YouTube Music): search, play, queue and
# playback control through the app's own "API Server" plugin. The source lives
# in ./youtube-music-mcp (no upstream). To update a dependency, edit its
# package.json, run `npm install` there and refresh npmDepsHash with
# `prefetch-npm-deps package-lock.json`.
pkgs.buildNpmPackage {
  pname = "youtube-music-mcp";
  version = "0.1.0";
  src = ./youtube-music-mcp;
  npmDepsHash = "sha256-L0quSRX++XEOTIMg0vTCYp6So02j2HHVMkp68VzxsBk=";
  dontNpmBuild = true;
  # The tests run the server against a mock of the app's API on 127.0.0.1.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    npm test
    runHook postCheck
  '';

  meta = {
    description = "MCP server controlling the YouTube Music desktop app (pear-desktop) through its API Server plugin";
    license = pkgs.lib.licenses.mit;
    mainProgram = "youtube-music-mcp";
  };
}
