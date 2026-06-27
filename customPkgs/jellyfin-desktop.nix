{ pkgs }:
# Jellyfin Desktop Client — CEF + mpv based native client.
#
# https://github.com/xaltsc/jellyfin-desktop (fork of jellyfin/jellyfin-desktop)
#
# Pinned via npins. Built from source using the upstream Nix derivation files
# with dependencies resolved from this system's nixpkgs.
let
  sources = import ../npins;
  src = sources.jellyfin-desktop;

  cef-binary = pkgs.cef-binary.override {
    version = "149.0.5";
    gitRevision = "6770623";
    chromiumVersion = "149.0.7827.197";
    srcHashes = {
      aarch64-linux = "sha256-cBAvcvs1rAg5EKJkCt81RZYupCWpUNIC/nLt3PJow7Q=";
      x86_64-linux = "sha256-OPGMBJmvvLiLdBDniBQwx7LmTGGI59AcesJdILSeqcs=";
    };
  };

  cef-lib = pkgs.stdenv.mkDerivation {
    pname = "cef-lib";
    inherit (cef-binary) version;
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out
      cp -r ${cef-binary}/Release/* $out/
      cp -r ${cef-binary}/Resources/* $out/
    '';
  };

  mpv-external-prefix = pkgs.symlinkJoin {
    pname = "mpv-external-prefix";
    inherit (pkgs.mpv-unwrapped) version;
    paths = [
      (pkgs.lib.getDev pkgs.mpv-unwrapped)
      (pkgs.lib.getLib pkgs.mpv-unwrapped)
    ];
  };

  wl-proxy-hash = "sha256-8NMNPhBSW2gLXc9bwyg2kmHb12XIaV6b4PjM62xLldQ=";
in
pkgs.rustPlatform.buildRustPackage {
  inherit src;
  pname = "jellyfin-desktop";
  version = "3.0.0-dev-20260627";

  cargoRoot = "src";
  cargoLock = {
    lockFile = "${src}/src/Cargo.lock";
    outputHashes = {
      "wl-proxy-0.1.2" = wl-proxy-hash;
    };
  };

  strictDeps = true;

  nativeBuildInputs = with pkgs; [
    wrapGAppsHook4
    rustPlatform.bindgenHook
    pkg-config
  ];

  buildInputs = with pkgs; [
    libxcb
    libxkbcommon
    ffmpeg
  ];

  buildPhase = ''
    runHook preBuild
    cargo xtask build \
      --cef-path ${cef-lib} \
      --external-mpv ${mpv-external-prefix} \
      --out build/
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 \
      build/jellyfin-desktop \
      $out/bin/jellyfin-desktop

    install -Dm644 \
      resources/linux/org.jellyfin.JellyfinDesktop.desktop \
      $out/share/applications/org.jellyfin.JellyfinDesktop.desktop
    install -Dm644 \
      resources/linux/org.jellyfin.JellyfinDesktop.metainfo.xml \
      $out/share/metainfo/org.jellyfin.JellyfinDesktop.metainfo.xml
    install -Dm644 \
      resources/linux/org.jellyfin.JellyfinDesktop.svg \
      $out/share/icons/hicolor/scalable/apps/org.jellyfin.JellyfinDesktop.svg

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath [ pkgs.libGL ]}" \
    )
  '';

  doCheck = false;

  meta = with pkgs.lib; {
    description = "Jellyfin desktop client";
    homepage = "https://github.com/xaltsc/jellyfin-desktop";
    license = licenses.gpl2Only;
    mainProgram = "jellyfin-desktop";
  };
}
