{ pkgs }:
# The mesh between people's desktops (`nixbook-mesh`, scripts/mesh.py,
# services/Mesh.qml): messages and status through an ntfy server, end-to-end
# encrypted with the mesh's key, which every member holds.
let
  inherit (pkgs) lib;
  # The script's own environment: cryptography (AES-GCM).
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.cryptography ]);
in
pkgs.writeShellScriptBin "nixbook-mesh" ''
  export PATH="${
    lib.makeBinPath [
      pkgs.libsecret # secret-tool: the access token and the mesh key in the keyring
    ]
  }:$PATH"
  # -P: not /nix/store (the script's directory) on sys.path: see package.nix.
  exec ${pythonEnv}/bin/python3 -P ${./scripts/mesh.py} "$@"
''
# The Python environment, for the tests.
// {
  inherit pythonEnv;
}
