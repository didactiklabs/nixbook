{ pkgs }:
# Moonfin — Flutter-based Jellyfin & Emby client with native Wayland support.
#
# https://github.com/Moonfin-Client/Moonfin-Core
#
# Built from source using Flutter via npins-pinned Moonfin-Core repo.
# sqlite3_flutter_libs is patched out — on Linux the system libsqlite3.so
# is loaded via dart:ffi (sqlite3 package) without the native plugin.
let
  sources = import ../npins;
  moonfinSrc = sources.Moonfin-Core;
  version = "2.2.0";
  pubspecLock = pkgs.lib.importJSON ./moonfin-pubspec-lock.json;
in
pkgs.flutter344.buildFlutterApplication rec {
  pname = "moonfin";
  inherit version;

  src = moonfinSrc;

  inherit pubspecLock;

  nativeBuildInputs = with pkgs; [
    pkg-config
    wrapGAppsHook3
  ];

  buildInputs = with pkgs; [
    gtk3
    webkitgtk_4_1
    # media_kit loads libmpv via dlopen; mpv-unwrapped provides the headers
    # without the wrapped mpv's pkg-config pulling in unresolvable private deps
    # (libavcodec, libplacebo, ...) during the volume_controller CMake check.
    mpv-unwrapped
    alsa-lib
    libass
    libsecret
    sqlite
    glib
    pcre2
  ];

  # The volume_controller plugin's linux/CMakeLists.txt does
  # `find_package(ALSA REQUIRED)`, which is unavailable in the build sandbox.
  # Patch it to resolve ALSA via pkg-config (alsa-lib) instead — same approach
  # as nixpkgs' jellyflix.
  customSourceBuilders = {
    volume_controller =
      { version, src, ... }:
      pkgs.stdenv.mkDerivation {
        pname = "volume_controller";
        inherit version src;
        inherit (src) passthru;

        postPatch = ''
          substituteInPlace linux/CMakeLists.txt \
            --replace-fail '# ALSA dependency for volume control' 'find_package(PkgConfig REQUIRED)' \
            --replace-fail 'find_package(ALSA REQUIRED)' 'pkg_check_modules(ALSA REQUIRED alsa)'
        '';

        installPhase = ''
          runHook preInstall

          mkdir $out
          cp -r ./* $out/

          runHook postInstall
        '';
      };
  };

  # sqlite3_flutter_libs 0.6.0+eol dropped Linux support. On Linux, the
  # sqlite3 Dart package loads libsqlite3.so via FFI. Patch it out so the
  # nix build system doesn't try to build the unsupported native plugin.
  postPatch = ''
    sed -i '/sqlite3_flutter_libs/d' pubspec.yaml
  '';

  postInstall = ''
        mkdir -p $out/share/applications $out/share/icons/hicolor/512x512/apps $out/share/metainfo

        cat > $out/share/applications/org.moonfin.linux.desktop <<EOF
    [Desktop Entry]
    Type=Application
    Name=Moonfin
    Exec=moonfin
    Icon=org.moonfin.linux
    Categories=AudioVideo;Video;
    Comment=Jellyfin & Emby media client
    Terminal=false
    EOF

        cat > $out/share/metainfo/org.moonfin.linux.metainfo.xml <<EOF
    <?xml version="1.0" encoding="UTF-8"?>
    <component type="desktop-application">
      <id>org.moonfin.linux</id>
      <metadata_license>CC0-1.0</metadata_license>
      <project_license>GPL-3.0</project_license>
      <name>Moonfin</name>
      <developer_name>Moonfin Team</developer_name>
      <summary>Jellyfin &amp; Emby media client</summary>
      <description>
        <p>Moonfin is a media client for Jellyfin and Emby servers, available on mobile, TV, and desktop platforms.</p>
      </description>
      <url type="homepage">https://moonfin.app/</url>
      <launchable type="desktop-id">org.moonfin.linux.desktop</launchable>
      <releases>
        <release version="${version}" date="2026-06-19"/>
      </releases>
      <content_rating type="oars-1.1"/>
    </component>
    EOF
  '';

  meta = with pkgs.lib; {
    description = "Jellyfin & Emby media client with native Wayland support";
    homepage = "https://moonfin.app/";
    license = licenses.gpl3Only;
    mainProgram = "moonfin";
    platforms = [ "x86_64-linux" ];
  };
}
