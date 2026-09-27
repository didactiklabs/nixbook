{ lib }:
# Nix helpers behind customHomeManagerModules.nixbookShellConfig.settings: the typed
# option tree generated from the shell's built-in defaults, and the functions
# that turn the settings set in Nix into the files the shell reads.
rec {
  # The shell's built-in default config (upstream modules/common/Config.qml),
  # minus `liveKeys`. Regenerate after changing Config.qml:
  #   nixbook-shell config builtin > customPkgs/nixbook-shell/builtin-defaults.json
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
        lib.mkOption {
          type = lib.types.nullOr (settingType v);
          default = null;
          description = "`${lib.concatStringsSep "." path}` (built-in default: `${builtins.toJSON v}`).";
        }
    );

  settingsModule = {
    options = settingOptions [ ] builtinDefaults;
  };

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
        if builtins.isAttrs value then
          flattenPaths (prefix ++ [ name ]) value
        else
          [ (lib.concatStringsSep "." (prefix ++ [ name ])) ]
      ) set
    );
}
