{ pkgs, gkeepapiSrc }:
# The Google Keep sync of the shell's notes: gkeepapi (the unofficial Keep
# API client, pinned in npins/) and the `nixbook-keep` command (the script
# scripts/keep-sync.py, which the shell's KeepSync service calls).
#
# gkeepapi is not in nixpkgs, and PyPI has no source distribution for it
# (only a wheel), so it is built from the GitHub checkout instead: it is a
# flit project, like the wheel it is built from.
let
  inherit (pkgs) lib;

  gkeepapi = pkgs.python3Packages.buildPythonPackage {
    pname = "gkeepapi";
    version = "0.17.1";
    src = gkeepapiSrc;
    pyproject = true;
    build-system = [ pkgs.python3Packages.flit-core ];
    dependencies = [ pkgs.python3Packages.gpsoauth ];
    # `future` is a Python 2 leftover the code never imports; it is only in
    # the package's metadata, and it doesn't build on Python 3.14.
    dontCheckRuntimeDeps = true;
    pythonImportsCheck = [ "gkeepapi" ];
    meta = {
      description = "An unofficial client for the Google Keep API";
      homepage = "https://github.com/kiwiz/gkeepapi";
      license = lib.licenses.mit;
      platforms = lib.platforms.unix;
    };
  };

  # The script's own environment: gkeepapi (with gpsoauth and requests).
  pythonEnv = pkgs.python3.withPackages (ps: [ gkeepapi ]);
in
pkgs.writeShellScriptBin "nixbook-keep" ''
  export PATH="${
    lib.makeBinPath (
      with pkgs;
      [
        libsecret # secret-tool: the account's master token in the keyring
      ]
    )
  }:$PATH"
  exec ${pythonEnv}/bin/python3 ${./scripts/keep-sync.py} "$@"
''
# The Python environment, for the tests (they import gkeepapi).
// {
  inherit pythonEnv;
}
