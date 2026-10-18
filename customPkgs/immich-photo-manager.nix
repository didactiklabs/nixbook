{ pkgs }:
# MCP server giving an AI agent the user's Immich library (search by place,
# date, text, faces; albums, tags, duplicates, sharing, video frames, PDF
# reports), from drolosoft/immich-photo-manager. nixbook-shell gives it to
# its own AI chat only (nixbookShellConfig.immichMcp).
#
# It is built on the MCP Python SDK 2 (`mcp.server.mcpserver`), and nixpkgs
# has mcp 1: mcp 2.2.0 and its mcp-types are packaged below from their PyPI
# wheels (2.3 wants httpx2 2.10, nixpkgs has 2.9). The credentials come from
# IMMICH_BASE_URL and IMMICH_API_KEY, or IMMICH_API_KEY_FILE (read by the
# wrapper, so the key never sits in the environment of a Nix-generated file),
# or what its update_credentials tool or nixbook-shell's Settings
# (immich-photo-manager-credentials) saved in ~/.immich-photo-manager, which
# wins over the environment.
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
  # Sourced by the wrapper: a writable home for update_credentials (the
  # default is next to the module, in the store), and the key from a file.
  credentialsEnv = pkgs.writeText "immich-photo-manager-env.sh" ''
    export IMMICH_CACHE_DIR="''${IMMICH_CACHE_DIR:-$HOME/.immich-photo-manager}"
    key_file=''${IMMICH_API_KEY_FILE:-}
    key_file=''${key_file/#\~\//$HOME/}
    if [ -z "''${IMMICH_API_KEY:-}" ] && [ -n "$key_file" ] && [ -r "$key_file" ]; then
      IMMICH_API_KEY=$(${pkgs.coreutils}/bin/tr -d '\n' < "$key_file")
      export IMMICH_API_KEY
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
  # Live tests need a running Immich; the others here start the server as a
  # subprocess, which doesn't get the build's PYTHONPATH.
  disabledTestPaths = [
    "tests/live"
    "tests/test_dual_era.py"
    "tests/test_e2e_both_eras.py"
  ];
  disabledTests = [ "test_the_launcher_serves_mcp_over_stdio_without_credentials" ];
  preCheck = ''
    export HOME=$(mktemp -d)
  '';

  # immich-photo-manager-credentials: show, set and clear the connection
  # from nixbook-shell's Settings (./immich-photo-manager/credentials.py).
  postInstall = ''
    install -Dm755 ${./immich-photo-manager/credentials.py} $out/bin/immich-photo-manager-credentials
    sed -i '1i #!/usr/bin/env python3' $out/bin/immich-photo-manager-credentials
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
