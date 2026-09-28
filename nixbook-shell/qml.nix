{ pkgs }:
# nixbook-shell's QML tree as installed (store-path fixups, Persona art). It started as a fork of
# pctrade/end4-pC (https://github.com/pctrade/end4-pC), itself a fork of end-4's
# illogical-impulse (https://github.com/end-4/dots-hyprland), and is maintained
# here independently since (GPL-3.0, like upstream; src/LICENSE).
#
# VENDORED: the whole QML tree lives under src/ and
# is edited directly — this is a hard fork, no longer a live npins pin.
#
# All of our feature changes are baked into the vendored source (the former
# postPatch scripts nixbook-shell-*.{py,go} are gone): the NixOS update
# port (services/UpdateState.qml, modules/ii/bar/UpdatesCount.qml + the About/
# Services/Config rewires), the pointing-hand cursor sweep, the Nix-managed
# settings support (modules/common/NixManaged.qml + NixManagedBadge.qml +
# configKey/enabled guards on every settings control), the brightness
# write-back debounce, the AI chat stream fixes, and the AnthropicUsage / VpnStatus
# bar widgets. The two upstream QML bug fixes (ThumbnailImage temp-file quoting,
# niri MonitorConfigOption scale) are baked in too.
#
# To resync with upstream: diff src/ against a fresh checkout
# of pctrade/end4-pC and merge by hand. Last synced from revision
# 0ff392bc69bdda1d795819c4bb8ec65e2b3658df.
#
# What still can NOT be baked in and therefore stays in postPatch below: the
# handful of transforms that reference Nix store paths (matugen config, the
# python interpreter, the hyprctl→niri monitor shim, the thumbgen typelib) plus
# the venv activate/deactivate neutralisation. Runtime *binaries* are injected
# via PATH by the `nixbook-shell` launcher (package.nix)
# (upstream calls ~40 different tools and probes most with `command -v`).
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
  # ~/.config/fuzzel/fuzzel_theme.ini and ~/.config/hypr/**. Every one of those
  # is Home Manager / stylix managed here (read-only store symlinks), so matugen
  # would fail on them and, worse, fight stylix over the GTK theme. We keep only
  # the three outputs the shell itself reads back (see Directories.qml:
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

    [templates.wallpaper]
    input_path = '${matugenWallpaperTemplate}'
    output_path = '~/.local/state/quickshell/user/generated/wallpaper/path.txt'
  '';

  # `hyprctl monitors -j` shim. Upstream uses it purely to read screen
  # dimensions; under niri it does not exist, which would make the wallpaper
  # switcher blow up. Emits the same `[{width,height},...]` shape so the
  # upstream jq expressions keep working unchanged.
  monitorsJson = pkgs.writeShellScript "nixbook-shell-monitors-json" ''
    set -u
    if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1; then
      exec hyprctl monitors -j
    elif command -v niri >/dev/null 2>&1 && niri msg -j outputs >/dev/null 2>&1; then
      focused=$(niri msg -j focused-output 2>/dev/null | ${lib.getExe pkgs.jq} -r '.name // ""')
      niri msg -j outputs | ${lib.getExe pkgs.jq} --arg focused "$focused" \
        '[ to_entries[].value | { name: .name, focused: (.name == $focused), x: (.logical.x // 0), y: (.logical.y // 0), scale: (.logical.scale // 1), width: (.logical.width // 0), height: (.logical.height // 0) } ]'
    else
      echo '[]'
    fi
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
  nativeBuildInputs = [ pkgs.resvg ];
  buildPhase = ''
    runHook preBuild
    for svg in assets/persona/p*-{panel,tall,wide}.svg; do
      resvg --zoom 2.5 "$svg" "''${svg%.svg}.png"
    done
    # Chiikawa theme art (assets/chiikawa/*.svg, generate.py): the characters
    # (200px viewBox, shown up to ~180px on HiDPI) and the sidebar patterns.
    for svg in assets/chiikawa/*.svg; do
      resvg --zoom 2 "$svg" "''${svg%.svg}.png"
    done
    runHook postBuild
  '';

  # Only the store-path-dependent transforms remain here; every feature change
  # is already baked into src/. See the header for why.
  postPatch = ''
    # 1. matugen: use our trimmed config instead of ~/.config/matugen/config.toml,
    #    and drop the kde-material-you-colors hook (not in nixpkgs, and its
    #    wrapper script lives in illogical-impulse's matugen templates).
    substituteInPlace scripts/colors/switchwall.sh \
      --replace-fail 'matugen "''${matugen_args[@]}"' \
                     'matugen --config ${matugenConfig} "''${matugen_args[@]}"' \
      --replace-fail '"$XDG_CONFIG_HOME"/matugen/templates/kde/kde-material-you-colors-wrapper.sh --scheme-variant "$kde_scheme_variant"' \
                     ': "$kde_scheme_variant"'

    # 2. hyprctl is hyprland-only; route monitor geometry and the focused
    #    output (switchwall.sh, record.sh) through the shim.
    substituteInPlace scripts/colors/switchwall.sh scripts/videos/record.sh \
      --replace-fail 'hyprctl monitors -j' '${monitorsJson}'

    # 3. Point every python shebang at a Nix interpreter that already carries
    #    what the illogical-impulse virtualenv would have provided. Upstream
    #    uses an `env -S ... source $ILLOGICAL_IMPULSE_VIRTUAL_ENV/bin/activate`
    #    shebang, which is a no-op here.
    find . -name '*.py' -type f -print0 | while IFS= read -r -d "" f; do
      sed -i "1s|^#!.*|#!${pythonEnv}/bin/python3|" "$f"
    done

    # 4. ...and neutralise the matching activate/deactivate calls in the shell
    #    wrappers (`scripts/**/*-venv.sh`, switchwall.sh).
    find . -name '*.sh' -type f -print0 | while IFS= read -r -d "" f; do
      sed -i \
        -e '1!s|^\([[:space:]]*\)source .*ILLOGICAL_IMPULSE_VIRTUAL_ENV.*/bin/activate.*$|\1:|' \
        -e 's|^\([[:space:]]*\)deactivate[[:space:]]*$|\1:|' \
        "$f"
    done

    # 5. thumbgen.py needs gobject-introspection typelibs (Gio, GnomeDesktop).
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
    description = "nixbook's Quickshell desktop shell (fork of end-4's illogical-impulse via pctrade/end4-pC)";
    homepage = "https://github.com/didactiklabs/nixbook";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
