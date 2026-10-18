{ pkgs }:
# MCP server giving an AI agent the user's Immich library (search by place,
# date, text, faces; albums, tags, duplicates, sharing, video frames, PDF
# reports), from drolosoft/immich-photo-manager. nixbook-shell gives it to
# its own AI chat only (Settings > Desktop agents, the ai.immich settings).
#
# It is built on the MCP Python SDK 2 (`mcp.server.mcpserver`), and nixpkgs
# has mcp 1: mcp 2.2.0 and its mcp-types are packaged below from their PyPI
# wheels (2.3 wants httpx2 2.10, nixpkgs has 2.9). The server comes from
# IMMICH_BASE_URL, the API key from the environment, a file or the keyring
# (credentialsEnv below), so it never has to be on a command line.
let
  py = pkgs.python313Packages;
  mcp-types = py.buildPythonPackage rec {
    pname = "mcp-types";
    version = "2.2.0";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/8f/d7/6ffba5d8cd5dd9b8a19478875c50e04945314ba5074e84d749283f27f62d/mcp_types-${version}-py3-none-any.whl";
      hash = "sha256-6kdrc+6GcJq1q8lFI4XtNswFkH5YI1ViLilFlcmgTxM=";
    };
    dependencies = with py; [
      pydantic
      typing-extensions
    ];
    pythonImportsCheck = [ "mcp_types" ];
  };
  mcp = py.buildPythonPackage rec {
    pname = "mcp";
    version = "2.2.0";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/1b/ff/8e7eade68b8a28f7da0ed1085544341b51f9c935dbf6b95c76b7edfea6a0/mcp-${version}-py3-none-any.whl";
      hash = "sha256-vemCWJRzoGCuFF40BumlMz/lOMlyKbqEH1p/kr4AT4E=";
    };
    dependencies = [
      mcp-types
    ]
    ++ (with py; [
      anyio
      httpx2
      jsonschema
      opentelemetry-api
      pydantic
      pyjwt
      cryptography
      python-multipart
      sse-starlette
      starlette
      typing-extensions
      typing-inspection
      uvicorn
    ]);
    pythonImportsCheck = [ "mcp.server.mcpserver" ];
  };
  # Sourced by the wrapper. The API key: IMMICH_API_KEY, else the file
  # IMMICH_API_KEY_FILE names (`~/` allowed), else the keyring's
  # service=immich-photo-manager secret (nixbook-shell's Settings saves it
  # there); IMMICH_API_KEY_SOURCE says which. What its update_credentials
  # tool saves (and then prefers to the environment) lives in the session's
  # runtime directory, so it lasts until logout instead of overriding the
  # settings for good (the default is next to the module, in the store).
  credentialsEnv = pkgs.writeText "immich-photo-manager-env.sh" ''
    runtime="''${XDG_RUNTIME_DIR:-$HOME/.cache}/immich-photo-manager"
    export IMMICH_CACHE_DIR="''${IMMICH_CACHE_DIR:-$runtime}"
    export IMMICH_CONFIG_HOME="''${IMMICH_CONFIG_HOME:-$runtime}"
    key_file=''${IMMICH_API_KEY_FILE:-}
    key_file=''${key_file/#\~\//$HOME/}
    if [ -n "''${IMMICH_API_KEY:-}" ]; then
      export IMMICH_API_KEY_SOURCE=env
    elif [ -n "$key_file" ] && [ -r "$key_file" ]; then
      IMMICH_API_KEY=$(${pkgs.coreutils}/bin/tr -d '\n' < "$key_file")
      export IMMICH_API_KEY IMMICH_API_KEY_SOURCE=file
    elif IMMICH_API_KEY=$(${pkgs.libsecret}/bin/secret-tool lookup service immich-photo-manager 2>/dev/null) && [ -n "$IMMICH_API_KEY" ]; then
      export IMMICH_API_KEY IMMICH_API_KEY_SOURCE=keyring
    else
      unset IMMICH_API_KEY
    fi
  '';
in
py.buildPythonApplication rec {
  pname = "immich-photo-manager";
  version = "2.0.13";
  pyproject = true;

  src = pkgs.fetchFromGitHub {
    owner = "drolosoft";
    repo = "immich-photo-manager";
    tag = "v${version}";
    hash = "sha256-x0g7TApM3jydaYRl65hXxtYw+xMbH3D1nPwzqBTn9mg=";
  };

  build-system = [ py.hatchling ];
  dependencies = [
    mcp
  ]
  ++ (with py; [
    av
    fpdf2
    httpx
    uvicorn
  ]);

  nativeCheckInputs = with py; [
    pytestCheckHook
    pytest-asyncio
    pypdf
    respx
  ];
  # Live tests need a running Immich; the next two start the server as a
  # subprocess, which doesn't get the build's PYTHONPATH; the last runs
  # upstream's Claude plugin setup script (not shipped here) with a bash
  # the sandbox doesn't have.
  disabledTestPaths = [
    "tests/live"
    "tests/test_dual_era.py"
    "tests/test_e2e_both_eras.py"
    "tests/test_setup_script.py"
  ];
  disabledTests = [ "test_the_launcher_serves_mcp_over_stdio_without_credentials" ];
  preCheck = ''
    export HOME=$(mktemp -d)
  '';

  # immich-photo-manager-credentials: check a server and key, save or
  # forget the key, for nixbook-shell's Settings
  # (./immich-photo-manager/credentials.py).
  postInstall = ''
    install -Dm755 ${./immich-photo-manager/credentials.py} $out/bin/immich-photo-manager-credentials
    sed -i '1i #!/usr/bin/env python3' $out/bin/immich-photo-manager-credentials
    substituteInPlace $out/bin/immich-photo-manager-credentials \
      --replace-fail @secretTool@ ${pkgs.libsecret}/bin/secret-tool
  '';
  postFixup = ''
    for program in immich-photo-manager immich-photo-manager-credentials; do
      wrapProgram $out/bin/$program --run ". ${credentialsEnv}"
    done
  '';

  pythonImportsCheck = [ "immich_mcp_server.server" ];

  passthru = { inherit mcp mcp-types; };

  meta = {
    description = "MCP server for managing an Immich photo library";
    homepage = "https://github.com/drolosoft/immich-photo-manager";
    license = pkgs.lib.licenses.mit;
    mainProgram = "immich-photo-manager";
  };
}
