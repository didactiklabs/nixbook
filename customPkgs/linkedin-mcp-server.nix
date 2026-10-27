{ pkgs }:
# MCP server giving an AI agent the user's LinkedIn through their own browser
# session (profiles, messages, jobs, companies, the feed), from
# stickerdaniel/linkedin-mcp-server. LinkedIn's User Agreement forbids
# automated access: accounts using it can be restricted, so nixbook-shell
# gives it to its own AI chat only, behind a switch that starts off.
#
# 4.25.1 is the last release on fastmcp 3 / mcp 1 (4.26 moved to fastmcp 4,
# which nixpkgs doesn't have, and mcp 2). nixpkgs has moved to mcp 2, which
# marks its fastmcp 3 broken, so this builds in a scope where mcp is the last
# 1.x release (PyPI's wheel). It drives nixpkgs' Chromium
# (CHROME_PATH: the server then never downloads a browser of its own, which
# wouldn't run on NixOS) through patchright (below), and doesn't poll PyPI
# for updates. The session lives in ~/.linkedin-mcp/profile
# (`mcp-server-linkedin --login` signs in, `--logout` forgets it).
let
  py = pkgs.python313Packages.overrideScope (
    _: super: {
      mcp = super.buildPythonPackage rec {
        pname = "mcp";
        version = "1.30.0";
        format = "wheel";
        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/f5/f4/e58bc33317c92a0203664daaf00bf6f41166cc0149e5d6870a03f7cd004a/mcp-${version}-py3-none-any.whl";
          hash = "sha256-Zm7bUAlQPhBHydYDRqdW+UsmHwXMJiXyPUHHKP/EhNA=";
        };
        dependencies =
          with super;
          [
            anyio
            httpx
            httpx-sse
            jsonschema
            pydantic
            pydantic-settings
            pyjwt
            python-multipart
            sse-starlette
            starlette
            typing-extensions
            typing-inspection
            uvicorn
          ]
          ++ super.pyjwt.optional-dependencies.crypto;
        pythonImportsCheck = [ "mcp.server.fastmcp" ];
      };
      # The OAuth proxy's stored client gains a field with mcp 1.x; nothing
      # here uses the OAuth proxy.
      fastmcp = super.fastmcp.overridePythonAttrs (old: {
        disabledTests = (old.disabledTests or [ ]) ++ [ "test_storage_data_structure" ];
      });
    }
  );
  # nixpkgs' patchright is a placeholder (marked broken: the real package
  # is built from patched Playwright and its patched Node driver). This is
  # PyPI's wheel, its bundled Node (which wouldn't run on NixOS) swapped for
  # nixpkgs' one.
  patchright = py.buildPythonPackage rec {
    pname = "patchright";
    version = "1.64.1";
    format = "wheel";
    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/11/1a/2822f0f5a530d47161cc78fa35381023831e1068749378ecff3eb54a766d/patchright-${version}-py3-none-manylinux1_x86_64.whl";
      hash = "sha256-/19+L0a2yyYAjkAaLFLW/wnBwJuksk4sdbxQH2Kj8IQ=";
    };
    dependencies = with py; [
      greenlet
      pyee
    ];
    dontAutoPatchelf = true;
    postInstall = ''
      ln -sf ${pkgs.lib.getExe pkgs.nodejs} $out/${py.python.sitePackages}/patchright/driver/node
    '';
    pythonImportsCheck = [ "patchright.async_api" ];
    meta.platforms = [ "x86_64-linux" ];
  };
in
py.buildPythonApplication rec {
  pname = "mcp-server-linkedin";
  version = "4.25.1";
  pyproject = true;

  src = pkgs.fetchPypi {
    pname = "mcp_server_linkedin";
    inherit version;
    hash = "sha256-6yWnHNWdGwmItPF8tRkwdiryEegJ+c+qoXKjD9UTiSA=";
  };

  build-system = [ py.setuptools ];
  dependencies = [
    patchright
  ]
  ++ (with py; [
    anyio
    cryptography
    fastmcp
    inquirer
    mcp
    packaging
    pydantic-settings
    python-dotenv
    rich
    starlette
  ]);
  # A patch release behind each minimum (nixpkgs: cryptography 50.0.0,
  # pydantic-settings 2.12).
  pythonRelaxDeps = [
    "cryptography"
    "pydantic-settings"
  ];

  makeWrapperArgs = [
    "--set-default"
    "CHROME_PATH"
    (pkgs.lib.getExe pkgs.chromium)
    "--set-default"
    "LINKEDIN_MCP_CHECK_FOR_UPDATES"
    "false"
  ];

  passthru = { inherit patchright; };

  # Upstream's tests aren't in the sdist; this checks the server imports.
  pythonImportsCheck = [ "linkedin_mcp_server.cli_main" ];

  meta = {
    description = "MCP server for LinkedIn (profiles, messages, jobs, companies) through the user's own browser session";
    homepage = "https://github.com/stickerdaniel/linkedin-mcp-server";
    license = pkgs.lib.licenses.asl20;
    mainProgram = "mcp-server-linkedin";
  };
}
