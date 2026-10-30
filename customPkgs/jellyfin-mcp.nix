{ pkgs }:
# MCP server for the user's Jellyfin library and its players (search, details,
# continue watching, next up, what plays where; play, control, mark watched,
# favourites, playlists), plus the CLI nixbook-shell uses: its Settings
# (credentials, signing the player in) and the bubble's zero-model fast path
# (`jellyfin-mcp play-query "edgerunners s1e1"`). Stdlib Python, the source
# in ./jellyfin-mcp (no upstream). Playback goes to a player through the
# server: by default this computer's jellyfin-mpv-shim (the user service
# homeManagerModules/nixbookShellConfig.nix runs), Moonfin or a TV when named.
# Given only to the nixbook-shell side panel's DAI (assistant.mcpServers),
# never installed on the PATH. Its credential — a user's own token from
# `credentials login` (no admin needed) or an admin's API key — comes from
# JELLYFIN_API_KEY, the file JELLYFIN_API_KEY_FILE names, or the keyring
# (service=jellyfin-mcp).
pkgs.stdenvNoCC.mkDerivation {
  pname = "jellyfin-mcp";
  version = "0.1.0";
  src = ./jellyfin-mcp;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  nativeInstallCheckInputs = [
    pkgs.python3
    pkgs.jq
  ];

  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm644 server.py $out/share/jellyfin-mcp/server.py
    ${pkgs.python3}/bin/python3 -m py_compile $out/share/jellyfin-mcp/server.py
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/jellyfin-mcp \
      --add-flags "-I $out/share/jellyfin-mcp/server.py" \
      --suffix PATH : ${pkgs.lib.makeBinPath [ pkgs.libsecret ]} \
      --set-default JELLYFIN_SHIM_VERSION ${pkgs.jellyfin-mpv-shim.version}
    runHook postInstall
  '';

  # Every tool, the credentials and the player's login against a fake
  # Jellyfin on the loopback (stubbed secret-tool and systemctl).
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    patchShebangs tests
    JELLYFIN_MCP=$out/bin/jellyfin-mcp bash tests/test.sh
    runHook postInstallCheck
  '';

  meta = {
    description = "MCP server for a Jellyfin library and its players (jellyfin-mpv-shim, Moonfin, TVs)";
    license = pkgs.lib.licenses.mit;
    mainProgram = "jellyfin-mcp";
  };
}
