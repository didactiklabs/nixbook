{ lib }:
# Nix helpers behind programs.nixbook-shell.settings (hm-module.nix): the typed
# option tree generated from the shell's built-in defaults, and the functions
# that turn the settings set in Nix into the files the shell reads.
rec {
  # The shell's built-in default config (upstream modules/common/Config.qml),
  # minus `liveKeys`. Regenerate after changing Config.qml:
  #   nixbook-shell config builtin > nixbook-shell/builtin-defaults.json
  builtinDefaults = lib.importJSON ./builtin-defaults.json;

  # Runtime state the shell and its scripts rewrite (wallpaper path, accent
  # colour, avatar, preset metadata, per-monitor widget positions). Not settings: they are left out of
  # builtin-defaults.json, so they have no option and can't be set (and
  # locked) from Nix — pinning any of them would break wallpaper switching,
  # palette regeneration or preset import. Also skipped by
  # `nixbook-shell config diff/dump/builtin`.
  liveKeys = [
    "background.wallpaperPath"
    "background.thumbnailPath"
    "appearance.palette.accentColor"
    "profile.avatarPath"
    "profile.avatarPicture"
    "background.widgets.screenPositions"
    "background.widgets.perScreen"
    "_presetMeta"
  ];

  # Settings the shell still reads but only to migrate them: no option, left
  # out of builtin-defaults.json and `config diff`. Old Nix settings setting
  # them are translated by `legacyModule`.
  legacyKeys = [
    "appearance.persona.enable"
  ]
  ++ removedKeys;

  # Settings that did nothing (or only did something under Hyprland) and were
  # removed: still accepted in Nix (so an old configuration evaluates) but
  # ignored, with a warning (hm-module.nix).
  removedKeys = [
    "apps.manageUser"
    "background.hideWhenFullscreen"
    "background.parallax.autoVertical"
    "background.parallax.enableSidebar"
    "background.parallax.enableWorkspace"
    "background.parallax.vertical"
    "background.parallax.widgetsFactor"
    "background.parallax.workspaceZoom"
    "background.widgets.clock.cookie.dateInClock"
    "background.widgets.media.backgroundShape"
    "background.widgets.media.showControls"
    "background.widgets.media.showTitles"
    "bar.autoHide.showWhenPressingSuper"
    "bar.floatStyleShadow"
    "bar.topLeftIcon"
    "bar.workspaces.showNumberDelay"
    "hyprland"
    "interactions.deadPixelWorkaround"
    "light.antiFlashbang"
    "overview"
    "regionSelector.targetRegions.layers"
    "regionSelector.targetRegions.windows"
    "search.prefix.keybinds"
    "settings.borderColor"
    "settings.borderSize"
  ];

  # The removed keys set in a settings tree (for the warning).
  removedKeysSet =
    settings:
    lib.filter (key: lib.attrByPath (lib.splitString "." key) null settings != null) removedKeys;

  # Keys `config builtin` / `config diff` skip.
  skippedKeys = liveKeys ++ legacyKeys;

  # The themes (src/modules/common/themes.json, also read by the shell's
  # Themes.qml and the login screen).
  themes = lib.importJSON ./src/modules/common/themes.json;
  themeIds = map (t: t.id) themes.themes;
  themeById = id: lib.findFirst (t: t.id == id) null themes.themes;

  # Settings that are a choice among fixed values: `appearance.theme` and
  # each theme's `appearance.<id>.variant`, from the registry.
  enumKeys = {
    "appearance.theme" = themeIds;
  }
  // lib.listToAttrs (
    map (t: lib.nameValuePair "appearance.${t.id}.variant" (map (v: v.id) t.variants)) (
      lib.filter (t: t.variants != [ ]) themes.themes
    )
  );

  # The theme a settings tree selects (unset keys: the shell's defaults):
  # { id, variant (null without variants), palette (null: the wallpaper's),
  # variantPalette (the variant's own, even with `palette = false`) }.
  # Accepts the legacy `appearance.persona.enable`.
  themeOf =
    settings:
    let
      appearance = settings.appearance or { };
      legacy = appearance.persona.enable or null;
      chosen = appearance.theme or null;
      id =
        if legacy == true then
          "persona"
        else if chosen != null && themeById chosen != null then
          chosen
        else
          themes.default;
      theme = themeById id;
      opts = appearance.${id} or { };
      variantIds = map (v: v.id) theme.variants;
      variantId =
        if theme.variants == [ ] then
          null
        else if lib.elem (opts.variant or null) variantIds then
          opts.variant
        else if lib.elem (theme.defaultVariant or null) variantIds then
          theme.defaultVariant
        else
          lib.head variantIds;
      variant = lib.findFirst (v: v.id == variantId) null theme.variants;
      variantPalette = if variant == null then null else variant.palette or null;
    in
    {
      inherit id variantPalette;
      variant = variantId;
      palette = if (opts.palette or true) == false then null else variantPalette;
    };

  # Option type for a setting, inferred from its built-in default.
  settingType =
    v:
    if builtins.isBool v then
      lib.types.bool
    else if builtins.isInt v || builtins.isFloat v then
      lib.types.number
    else if builtins.isString v then
      lib.types.str
    else if builtins.isList v && v != [ ] && lib.all builtins.isString v then
      lib.types.listOf lib.types.str
    else if builtins.isList v then
      lib.types.listOf lib.types.anything
    else
      lib.types.anything;

  # One option per leaf of the default tree, each `nullOr <type>` defaulting to
  # null (= not set in Nix: editable in the menu). A misspelt key therefore
  # fails evaluation like any other module option.
  settingOptions =
    prefix:
    lib.mapAttrs (
      name: v:
      let
        path = prefix ++ [ name ];
      in
      if builtins.isAttrs v && v != { } then
        settingOptions path v
      else
        let
          key = lib.concatStringsSep "." path;
        in
        lib.mkOption {
          type = lib.types.nullOr (
            if enumKeys ? ${key} then lib.types.enum enumKeys.${key} else settingType v
          );
          default = null;
          description = "`${lib.concatStringsSep "." path}` (built-in default: `${builtins.toJSON v}`).";
        }
    );

  settingsModule = {
    imports = [ legacyModule ];
    options = settingOptions [ ] builtinDefaults;
  };

  # The legacy keys as deprecated options, translated to their replacement
  # (hm-module.nix warns about them). `pinnedSettings` leaves them out.
  legacyModule =
    { config, ... }:
    {
      options =
        lib.foldl' lib.recursiveUpdate
          {
            appearance.persona.enable = lib.mkOption {
              type = lib.types.nullOr lib.types.bool;
              default = null;
              visible = false;
              description = "Deprecated: `appearance.theme = \"persona\"` (true) or `\"material\"` (false).";
            };
          }
          (
            map (
              key:
              lib.setAttrByPath (lib.splitString "." key) (
                lib.mkOption {
                  type = lib.types.nullOr lib.types.anything;
                  default = null;
                  visible = false;
                  description = "Removed: `${key}` did nothing; ignored.";
                }
              )
            ) removedKeys
          );
      config.appearance.theme = lib.mkIf (config.appearance.persona.enable != null) (
        lib.mkDefault (if config.appearance.persona.enable then "persona" else "material")
      );
    };

  # The settings set in Nix, as written to config.json and locked in the
  # menu: set leaves, minus the legacy keys (already translated).
  pinnedSettings =
    settings:
    setLeaves (
      lib.foldl' (
        s: key:
        let
          path = lib.splitString "." key;
        in
        lib.updateManyAttrsByPath [
          {
            path = lib.init path;
            update = old: if builtins.isAttrs old then removeAttrs old [ (lib.last path) ] else old;
          }
        ] s
      ) settings legacyKeys
    );

  # The settings actually set: drop unset (null) leaves and the empty branches
  # they leave behind.
  setLeaves =
    set:
    lib.filterAttrs (_: v: v != null && v != { }) (
      lib.mapAttrs (_: v: if builtins.isAttrs v then setLeaves v else v) set
    );

  # Dot-notation leaf paths ("bar.layouts.leftLayout"; lists are leaves) — the
  # lock manifest the shell's NixManaged singleton reads.
  flattenPaths =
    prefix: set:
    lib.concatLists (
      lib.mapAttrsToList (
        name: value:
        if builtins.isAttrs value && value != { } then
          flattenPaths (prefix ++ [ name ]) value
        else
          [ (lib.concatStringsSep "." (prefix ++ [ name ])) ]
      ) set
    );
}
