{ pkgs }:
# MCP server for the user's Seerr (Overseerr / Jellyseerr): search films and
# series and see what is available or on its way, request them (a film, a
# series' seasons, 4K), follow, cancel, approve or decline requests,
# trending and upcoming. Stdlib Python, the source in ./seerr-mcp (no
# upstream). Your own login: after you signed in to Seerr in your browser
# (OpenID Connect included), `login-from-browser` takes only its session
# cookie from Zen/Firefox's or Chrome/Chromium's cookie file (the latter
# decrypted with the browser's key from the keyring). Or an admin's API key,
# sent with X-API-User so requests go out as the user chosen in Settings.
# Given only to the nixbook-shell side panel's V (assistant.mcpServers),
# never installed on the PATH. The credential comes from SEERR_SESSION,
# SEERR_API_KEY, the file SEERR_API_KEY_FILE names, or the keyring
# (service=seerr-mcp).
pkgs.stdenvNoCC.mkDerivation {
  pname = "seerr-mcp";
  version = "0.1.0";
  src = ./seerr-mcp;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  nativeInstallCheckInputs = [
    pkgs.python3
    pkgs.jq
    pkgs.openssl # encrypts the test's fake Chrome cookies
  ];

  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm644 server.py $out/share/seerr-mcp/server.py
    ${pkgs.python3}/bin/python3 -m py_compile $out/share/seerr-mcp/server.py
    makeWrapper ${pkgs.python3}/bin/python3 $out/bin/seerr-mcp \
      --add-flags "-I $out/share/seerr-mcp/server.py" \
      --suffix PATH : ${pkgs.lib.makeBinPath [ pkgs.libsecret ]}
    runHook postInstall
  '';

  # Every tool, the credentials and the browser login against a fake Seerr
  # on the loopback (a stubbed secret-tool, fake Firefox and Chrome cookie
  # files).
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    patchShebangs tests
    SEERR_MCP=$out/bin/seerr-mcp bash tests/test.sh
    runHook postInstallCheck
  '';

  meta = {
    description = "MCP server for a Seerr (Overseerr / Jellyseerr) server: search, request, follow requests";
    license = pkgs.lib.licenses.mit;
    mainProgram = "seerr-mcp";
  };
}
