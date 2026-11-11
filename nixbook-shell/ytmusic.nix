{ pkgs }:
# YouTube Music in the background, without a window (`nixbook-ytmusic`,
# scripts/ytmusic.py, services/YouTubeMusic.qml): the library through
# ytmusicapi with the browser's YouTube session, played by mpv (audio only,
# through yt-dlp), an MPRIS player on the session bus, Last.fm scrobbling.
let
  inherit (pkgs) lib;
  # ytmusicapi (the library), dbus-python and PyGObject (the MPRIS player).
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.ytmusicapi
    ps.dbus-python
    ps.pygobject3
  ]);
in
pkgs.writeShellScriptBin "nixbook-ytmusic" ''
  export PATH="${
    lib.makeBinPath [
      pkgs.libsecret # secret-tool: the YouTube session and the Last.fm sign-in in the keyring
      pkgs.openssl # Chromium-family browsers' cookies (AES-128-CBC)
      pkgs.systemd # systemctl: the player started on demand
    ]
  }:$PATH"
  export NIXBOOK_YTMUSIC_MPV="''${NIXBOOK_YTMUSIC_MPV:-${lib.getExe pkgs.mpv}}"
  export NIXBOOK_YTMUSIC_YT_DLP="''${NIXBOOK_YTMUSIC_YT_DLP:-${lib.getExe pkgs.yt-dlp}}"
  # -P: not /nix/store (the script's directory) on sys.path: see package.nix.
  exec ${pythonEnv}/bin/python3 -P ${./scripts/ytmusic.py} "$@"
''
# The Python environment, for the tests.
// {
  inherit pythonEnv;
}
