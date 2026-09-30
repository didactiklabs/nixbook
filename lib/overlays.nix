{ sources }:
final: prev:
let
  lixStable = prev.lixPackageSets.stable;
  pkgs-stable = import sources.nixpkgs-stable {
    localSystem = prev.stdenv.hostPlatform.system;
  };
in
{
  bluez-stable = pkgs-stable.bluez;
  inherit (lixStable)
    nixpkgs-review
    nix-eval-jobs
    nix-fast-build
    ;

  # Fix upstream hash mismatch: the GitHub-generated patch for PR #23326
  # changed content, breaking the pinned hash in nixpkgs.
  openapi-generator-cli = prev.openapi-generator-cli.overrideAttrs (oldAttrs: {
    patches = [
      (prev.fetchpatch {
        url = "https://github.com/OpenAPITools/openapi-generator/pull/23326.patch";
        hash = "sha256-E1VgtaIW1V+8ch2RpW850fVNl5Iqitjog+0b8DKFgZw=";
      })
    ];
  });

  # Foxblat — Moza Racing config tool, fork of boxflat with extra protocols/devices.
  # Built modeled on nixpkgs' boxflat derivation but with foxblat-specific names,
  # paths, and udev rule. `trayer` is an optional runtime dep; foxblat falls back
  # gracefully when not present, so we skip it (not in nixpkgs).
  foxblat = prev.python3Packages.buildPythonPackage {
    pname = "foxblat";
    version = "unstable-${sources.foxblat.revision}";
    pyproject = true;
    src = sources.foxblat;

    build-system = [ prev.python3Packages.setuptools ];

    propagatedBuildInputs = [
      prev.gtk4
      prev.libadwaita

      prev.python3Packages.pyyaml
      prev.python3Packages.psutil
      prev.python3Packages.pyserial
      prev.python3Packages.pycairo
      prev.python3Packages.pygobject3
      prev.python3Packages.evdev
      prev.python3Packages.dbus-python
    ];

    nativeBuildInputs = [
      prev.copyDesktopItems
      prev.wrapGAppsHook4
      prev.gobject-introspection
      prev.udevCheckHook
    ];

    pythonRelaxDeps = [
      "psutil"
      "evdev"
      "pycairo"
      "pygobject"
      "PyYAML"
      "dbus-python"
    ];

    preBuild = ''
      cat > setup.py << EOF
      import shutil
      from setuptools import setup

      with open('requirements.txt') as f:
          install_requires = [
              line for line in f.read().splitlines()
              if not line.startswith('trayer')
          ]

      shutil.copyfile('entrypoint.py', 'foxblat/entrypoint.py')

      setup(
        name='foxblat',
        packages=['foxblat', 'foxblat.panels', 'foxblat.widgets'],
        version='0.0.0',
        install_requires=install_requires,
        entry_points={
          'console_scripts': ['foxblat=foxblat.entrypoint:main']
        },
      )
      EOF
    '';

    preInstall = ''
      mkdir -p $out/{usr/share/foxblat,lib/udev/rules.d,share/icons}
      cp -r data "$out/usr/share/foxblat/"
      cp -r icons "$out/share/icons/hicolor"
      cp -r udev "$out/usr/share/foxblat"
      cp udev/99-foxblat.rules "$out/lib/udev/rules.d/"
    '';

    dontWrapGApps = true;
    preFixup = ''
      makeWrapperArgs+=("''${gappsWrapperArgs[@]}")
      makeWrapperArgs+=(--add-flags "--data-path $out/usr/share/foxblat/data")
    '';

    desktopItems = [
      (prev.makeDesktopItem {
        name = "Foxblat";
        desktopName = "Foxblat";
        genericName = "settings";
        comment = "Moza Racing settings app (foxblat fork)";
        exec = "foxblat";
        icon = "io.github.giantorth.foxblat";
        startupWMClass = "io.github.giantorth.foxblat";
        startupNotify = true;
        categories = [
          "Game"
          "Utility"
        ];
        keywords = [
          "game"
          "racing"
          "cars"
          "wheels"
          "moza"
        ];
      })
    ];

    meta = {
      homepage = "https://github.com/giantorth/foxblat";
      description = "Control your Moza gear settings (foxblat fork of boxflat)";
      license = prev.lib.licenses.gpl3Only;
      platforms = prev.lib.platforms.linux;
      mainProgram = "foxblat";
    };
  };
}
