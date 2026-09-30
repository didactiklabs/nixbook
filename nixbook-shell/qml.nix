{ pkgs }:
# nixbook-shell's QML tree as installed (store-path fixups, Persona art).
#
# nixbook-shell is its own project, niri-only, developed here in src/ (no
# upstream to track). It began as a fork of pctrade/end4-pC
# (https://github.com/pctrade/end4-pC), itself a fork of end-4's
# illogical-impulse (https://github.com/end-4/dots-hyprland); GPL-3.0 like
# them (src/LICENSE).
#
# What can NOT live in src/ and stays in postPatch below: the transforms that
# reference Nix store paths (matugen config, the python interpreter, the
# thumbgen typelib) plus the venv activate/deactivate neutralisation. Runtime
# *binaries* are injected via PATH by the `nixbook-shell` launcher
# (package.nix).
let
  inherit (pkgs) lib;
  src = ./src;

  # Quickshell config directory name, i.e. the `qs -c <name>` argument.
  # Already baked into the vendored scripts (QUICKSHELL_CONFIG_NAME).
  configName = "nixbook-shell";

  # Everything the bundled python scripts import. Upstream gets these from a
  # virtualenv built by its Arch installer.
  pythonEnv = pkgs.python3.withPackages (ps: [
    ps.pillow # generate_colors_material.py
    ps.materialyoucolor # generate_colors_material.py
    ps.numpy # scheme_for_image.py, images/*.py
    ps.opencv4 # scheme_for_image.py, images/*.py
    ps.click # thumbnails/thumbgen.py
    ps.loguru # thumbnails/thumbgen.py
    ps.tqdm # thumbnails/thumbgen.py
    ps.pygobject3 # thumbnails/thumbgen.py
    ps.google-auth # services/gCloud/token_from_key.py
    ps.requests # services/gCloud/token_from_key.py
  ]);

  # thumbgen.py pulls Gio + GnomeDesktop through gobject-introspection.
  typelibPath = lib.makeSearchPath "lib/girepository-1.0" [
    pkgs.glib.out
    pkgs.gnome-desktop
  ];

  # Trimmed matugen setup.
  #
  # illogical-impulse's matugen config also rewrites ~/.config/gtk-{3,4}.0/gtk.css,
  # ~/.config/fuzzel/fuzzel_theme.ini and the compositor config. Every one of those
  # is Home Manager / stylix managed here (read-only store symlinks), so matugen
  # would fail on them and, worse, fight stylix over the GTK theme. We keep only
  # the outputs the shell itself reads back (see Directories.qml:
  # generatedMaterialThemePath / generatedWallpaperCategoryPath).
  matugenColorsTemplate = pkgs.writeText "nixbook-shell-colors.json" ''
    {
      "background": "{{colors.background.default.hex}}",
      "error": "{{colors.error.default.hex}}",
      "error_container": "{{colors.error_container.default.hex}}",
      "inverse_on_surface": "{{colors.inverse_on_surface.default.hex}}",
      "inverse_primary": "{{colors.inverse_primary.default.hex}}",
      "inverse_surface": "{{colors.inverse_surface.default.hex}}",
      "on_background": "{{colors.on_background.default.hex}}",
      "on_error": "{{colors.on_error.default.hex}}",
      "on_error_container": "{{colors.on_error_container.default.hex}}",
      "on_primary": "{{colors.on_primary.default.hex}}",
      "on_primary_container": "{{colors.on_primary_container.default.hex}}",
      "on_primary_fixed": "{{colors.on_primary_fixed.default.hex}}",
      "on_primary_fixed_variant": "{{colors.on_primary_fixed_variant.default.hex}}",
      "on_secondary": "{{colors.on_secondary.default.hex}}",
      "on_secondary_container": "{{colors.on_secondary_container.default.hex}}",
      "on_secondary_fixed": "{{colors.on_secondary_fixed.default.hex}}",
      "on_secondary_fixed_variant": "{{colors.on_secondary_fixed_variant.default.hex}}",
      "on_surface": "{{colors.on_surface.default.hex}}",
      "on_surface_variant": "{{colors.on_surface_variant.default.hex}}",
      "on_tertiary": "{{colors.on_tertiary.default.hex}}",
      "on_tertiary_container": "{{colors.on_tertiary_container.default.hex}}",
      "on_tertiary_fixed": "{{colors.on_tertiary_fixed.default.hex}}",
      "on_tertiary_fixed_variant": "{{colors.on_tertiary_fixed_variant.default.hex}}",
      "outline": "{{colors.outline.default.hex}}",
      "outline_variant": "{{colors.outline_variant.default.hex}}",
      "primary": "{{colors.primary.default.hex}}",
      "primary_container": "{{colors.primary_container.default.hex}}",
      "primary_fixed": "{{colors.primary_fixed.default.hex}}",
      "primary_fixed_dim": "{{colors.primary_fixed_dim.default.hex}}",
      "scrim": "{{colors.scrim.default.hex}}",
      "secondary": "{{colors.secondary.default.hex}}",
      "secondary_container": "{{colors.secondary_container.default.hex}}",
      "secondary_fixed": "{{colors.secondary_fixed.default.hex}}",
      "secondary_fixed_dim": "{{colors.secondary_fixed_dim.default.hex}}",
      "shadow": "{{colors.shadow.default.hex}}",
      "surface": "{{colors.surface.default.hex}}",
      "surface_bright": "{{colors.surface_bright.default.hex}}",
      "surface_container": "{{colors.surface_container.default.hex}}",
      "surface_container_high": "{{colors.surface_container_high.default.hex}}",
      "surface_container_highest": "{{colors.surface_container_highest.default.hex}}",
      "surface_container_low": "{{colors.surface_container_low.default.hex}}",
      "surface_container_lowest": "{{colors.surface_container_lowest.default.hex}}",
      "surface_dim": "{{colors.surface_dim.default.hex}}",
      "surface_tint": "{{colors.surface_tint.default.hex}}",
      "surface_variant": "{{colors.surface_variant.default.hex}}",
      "tertiary": "{{colors.tertiary.default.hex}}",
      "tertiary_container": "{{colors.tertiary_container.default.hex}}",
      "tertiary_fixed": "{{colors.tertiary_fixed.default.hex}}",
      "tertiary_fixed_dim": "{{colors.tertiary_fixed_dim.default.hex}}"
    }
  '';
  matugenSourceColorTemplate = pkgs.writeText "nixbook-shell-color.txt" ''
    {{colors.source_color.default.hex}}
  '';
  matugenWallpaperTemplate = pkgs.writeText "nixbook-shell-wallpaper.txt" ''
    {{image}}
  '';
  matugenConfig = pkgs.writeText "nixbook-shell-matugen.toml" ''
    [config]
    version_check = false

    [templates.m3colors]
    input_path = '${matugenColorsTemplate}'
    output_path = '~/.local/state/quickshell/user/generated/colors.json'

    [templates.kde_colors]
    input_path = '${matugenSourceColorTemplate}'
    output_path = '~/.local/state/quickshell/user/generated/color.txt'

    # The palette's source colour, left alone by generate_colors_material.py
    # (which rewrites color.txt): switchwall.sh keeps it when the palette
    # doesn't follow the wallpaper (wallpaperTheming.enableAppsAndShell off).
    [templates.source_color]
    input_path = '${matugenSourceColorTemplate}'
    output_path = '~/.local/state/quickshell/user/generated/source-color.txt'

    [templates.wallpaper]
    input_path = '${matugenWallpaperTemplate}'
    output_path = '~/.local/state/quickshell/user/generated/wallpaper/path.txt'
  '';

in
pkgs.stdenvNoCC.mkDerivation {
  pname = "nixbook-shell";
  version = "vendored-0ff392bc";
  inherit src;

  dontConfigure = true;

  # Persona background art (assets/persona/*.svg, generated by generate.py) is
  # rasterised here, at 2.5x its viewBox: PNGs are decoded at their own size
  # whatever the screen scale, so modules/common/Persona.qml can keep the
  # current variant's three textures cached and every panel reuses them.
  # (Qt keys SVG rasters by size x device pixel ratio, so each panel/screen
  # used to re-render its SVG — ~0.5 s before the art appeared.)
  nativeBuildInputs = [
    pkgs.resvg
    pkgs.python3
  ];
  buildPhase = ''
    runHook preBuild
    for svg in assets/persona/p*-{panel,tall,wide}.svg; do
      resvg --zoom 2.5 "$svg" "''${svg%.svg}.png"
    done
    # Chiikawa theme art (assets/chiikawa/*.svg, generate.py): the sidebar
    # patterns and the wallpapers (1920x1080 viewBox: 4K). The character is
    # momonga.gif, shipped as is.
    for svg in assets/chiikawa/*.svg; do
      resvg --zoom 2 "$svg" "''${svg%.svg}.png"
    done
    # ...and its sounds, synthesized (assets/chiikawa/sounds.py).
    python3 assets/chiikawa/sounds.py assets/chiikawa/sounds
    # Cyberpunk 2077 theme art (assets/cyberpunk/*.svg, generate.py): the
    # wallpapers (1920x1080 viewBox: 4K), and its synthesized sounds.
    for svg in assets/cyberpunk/*.svg; do
      resvg --zoom 2 "$svg" "''${svg%.svg}.png"
    done
    python3 assets/cyberpunk/sounds.py assets/cyberpunk/sounds
    # The launcher's emoji list (services/Emojis.qml): Unicode's emojis with
    # CLDR's English keywords.
    python3 ${./scripts/emojis.py} \
      ${pkgs.unicode-emoji}/share/unicode/emoji/emoji-test.txt \
      ${pkgs.cldr-annotations}/share/unicode/cldr/common/annotations/en.xml \
      ${pkgs.cldr-annotations}/share/unicode/cldr/common/annotationsDerived/en.xml \
      >assets/emojis.txt
    runHook postBuild
  '';

  # Only the store-path-dependent transforms remain here; every feature change
  # is already baked into src/. See the header for why.
  postPatch = ''
    # 1. matugen: use our trimmed config instead of ~/.config/matugen/config.toml.
    substituteInPlace scripts/colors/switchwall.sh \
      --replace-fail 'matugen "''${matugen_args[@]}"' \
                     'matugen --config ${matugenConfig} "''${matugen_args[@]}"'

    # 2. Point every python shebang at a Nix interpreter that already carries
    #    what the illogical-impulse virtualenv would have provided. Upstream
    #    uses an `env -S ... source $ILLOGICAL_IMPULSE_VIRTUAL_ENV/bin/activate`
    #    shebang, which is a no-op here.
    find . -name '*.py' -type f -print0 | while IFS= read -r -d "" f; do
      sed -i "1s|^#!.*|#!${pythonEnv}/bin/python3|" "$f"
    done

    # 3. ...and neutralise the matching activate/deactivate calls in the shell
    #    wrappers (`scripts/**/*-venv.sh`, switchwall.sh).
    find . -name '*.sh' -type f -print0 | while IFS= read -r -d "" f; do
      sed -i \
        -e '1!s|^\([[:space:]]*\)source .*ILLOGICAL_IMPULSE_VIRTUAL_ENV.*/bin/activate.*$|\1:|' \
        -e 's|^\([[:space:]]*\)deactivate[[:space:]]*$|\1:|' \
        "$f"
    done

    # 4. thumbgen.py needs gobject-introspection typelibs (Gio, GnomeDesktop).
    substituteInPlace scripts/thumbnails/thumbgen-venv.sh \
      --replace-fail 'GIO_USE_VFS=local' 'GI_TYPELIB_PATH=${typelibPath} GIO_USE_VFS=local'
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r . "$out/"
    runHook postInstall
  '';

  passthru = {
    inherit
      configName
      matugenConfig
      pythonEnv
      ;
  };

  meta = {
    description = "nixbook's Quickshell desktop shell for niri";
    homepage = "https://github.com/didactiklabs/nixbook";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
