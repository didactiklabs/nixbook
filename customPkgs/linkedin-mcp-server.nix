{ pkgs }:
# MCP server giving an AI agent the user's LinkedIn through their own browser
# session (profiles, messages, jobs, companies, the feed), from
# stickerdaniel/linkedin-mcp-server. LinkedIn's User Agreement forbids
# automated access: accounts using it can be restricted, so nixbook-shell
# gives it to its own AI chat only, behind a switch that starts off.
#
# 4.25.1 is the last release on fastmcp 3 / mcp 1, the versions nixpkgs has
# (4.26 moved to fastmcp 4 and mcp 2). It drives nixpkgs' Chromium
# (CHROME_PATH: the server then never downloads a browser of its own, which
# wouldn't run on NixOS) through patchright (below), and doesn't poll PyPI
# for updates. The session lives in ~/.linkedin-mcp/profile
# (`mcp-server-linkedin --login` signs in, `--logout` forgets it).
#
# Patched (./linkedin-mcp-server/gecko-import.patch) so that importing a
# session from a signed-in browser (`--import-from-browser [zen|firefox|…]`,
# and the import tried on the first call needing a session) also reads
# Firefox-family browsers (Zen, Firefox, LibreWolf, Floorp): their
# profiles.ini and plain-text cookies.sqlite. Upstream reads Chromium
# browsers only.
#
# Its browser runs headed on an invisible X display (Xvfb), never on the
# user's screen, like upstream's container image: headless Chromium calls
# itself HeadlessChrome, which LinkedIn throttles (HTTP 429). `--login`
# alone opens on the user's screen. (./linkedin-mcp-server/virtual-display.patch:
# LINKEDIN_MCP_VIRTUAL_DISPLAY=1 turns every launch headed.)
let
  py = pkgs.python313Packages;
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

  patches = [
    ./linkedin-mcp-server/gecko-import.patch
    ./linkedin-mcp-server/virtual-display.patch
  ];

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

  # mcp-server-linkedin: the server on its own Xvfb display (stdio passes
  # through xvfb-run untouched), Wayland left out so Chromium uses it;
  # `--login` runs it directly, on the user's screen.
  postFixup = ''
    mv $out/bin/mcp-server-linkedin $out/bin/.mcp-server-linkedin-direct
    cat > $out/bin/mcp-server-linkedin <<EOF
    #!${pkgs.runtimeShell}
    for arg in "\$@"; do
      if [ "\$arg" = --login ]; then exec $out/bin/.mcp-server-linkedin-direct "\$@"; fi
    done
    export HEADLESS=false LINKEDIN_MCP_VIRTUAL_DISPLAY=1
    unset WAYLAND_DISPLAY NIXOS_OZONE_WL
    exec ${pkgs.lib.getExe pkgs.xvfb-run} -a -s "-screen 0 1920x1080x24 -nolisten tcp" $out/bin/.mcp-server-linkedin-direct "\$@"
    EOF
    chmod +x $out/bin/mcp-server-linkedin
  '';

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
