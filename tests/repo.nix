/*
  Fast repository checks: pure evaluation, nothing is built.

    tests/run.sh repo
    # or one check: nix-instantiate --eval --strict --json tests/repo.nix -A <name>

  Each attribute is an independent check that evaluates to "ok" (or, for
  `packages.<name>`, the .drv path) and throws with the reason otherwise:
    - machines: hive.nix nodes and profiles/ directories agree (a machine can't be
      half-added or half-removed);
    - orphans: every module file under nixosModules/ and homeManagerModules/ is
      referenced somewhere (an unimported module silently does nothing);
    - packages.<name>: every custom package in customPkgs/ instantiates (its .drv evaluates),
      including the ones no profile uses;
    - shellLib: unit tests of the nixbook-shell settings helpers (customPkgs/nixbook-shell/lib.nix).
*/
let
  sources = import ../npins;
  pkgs = import sources.nixpkgs {
    config = {
      allowUnfree = true;
      permittedInsecurePackages = [
        "qtwebengine-5.15.19"
        "pnpm-10.29.2"
        "electron-40.10.5"
      ];
    };
    overlays = [ (import ../nixosModules/overlays.nix { inherit sources; }) ];
  };
  inherit (pkgs) lib;

  sorted = lib.sort lib.lessThan;
  dirsIn =
    dir: sorted (lib.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir dir)));
  nixFilesIn =
    dir:
    sorted (
      lib.attrNames (
        lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n) (builtins.readDir dir)
      )
    );

  # -- Machines -----------------------------------------------------------------
  hiveNodes = sorted (lib.attrNames (removeAttrs (import ../hive.nix) [ "meta" ]));
  profiles = dirsIn ../profiles;

  # -- Orphan modules -----------------------------------------------------------
  # All Nix sources outside VCS/tooling state and the vendored nixbook-shell
  # tree (symlinks such as `result` are never followed).
  skippedDirs = [
    ".git"
    ".devenv"
    ".direnv"
    ".tmp"
    ".gcroots"
    "src"
  ];
  nixSourcesUnder =
    dir:
    lib.concatLists (
      lib.mapAttrsToList (
        name: type:
        if type == "directory" && !lib.elem name skippedDirs then
          nixSourcesUnder (dir + "/${name}")
        else if type == "regular" && lib.hasSuffix ".nix" name then
          [ (dir + "/${name}") ]
        else
          [ ]
      ) (builtins.readDir dir)
    );
  searchable = nixSourcesUnder ../.;
  # Read each file once; search file by file (one regex over the whole repo
  # overflows the regex engine's stack).
  contents = map (p: {
    path = p;
    text = builtins.readFile p;
  }) searchable;
  mentions = needle: text: lib.length (builtins.split (lib.escapeRegex needle) text) > 1;
  # A module is referenced when another file mentions `/<name>` (or, for
  # `<name>.nix` and directories, `/<stem>` followed by a delimiter).
  isReferenced =
    dir: entry:
    let
      self = dir + "/${entry}";
      stem = lib.removeSuffix ".nix" entry;
      needles = [
        "/${entry}"
      ]
      ++ map (end: "/${stem}${end}") [
        "\n"
        " "
        ")"
        ";"
        "\""
      ];
    in
    lib.any (f: f.path != self && lib.any (n: mentions n f.text) needles) contents;
  moduleEntries =
    dir:
    lib.filter (e: e != "default.nix") (
      lib.attrNames (
        lib.filterAttrs (n: t: t == "directory" || lib.hasSuffix ".nix" n) (builtins.readDir dir)
      )
    );
  # Entry points imported from outside the repo, by design.
  externalEntryPoints = [
    # Standalone Home Manager entry for non-NixOS hosts (see README.md).
    "homeManagerModules/entrypoint.nix"
  ];
  orphansIn =
    prefix: dir:
    lib.filter (e: !lib.elem e externalEntryPoints) (
      map (e: "${prefix}/${e}") (lib.filter (e: !isReferenced dir e) (moduleEntries dir))
    );
  orphans =
    orphansIn "nixosModules" ../nixosModules ++ orphansIn "homeManagerModules" ../homeManagerModules;

  # -- Custom packages ----------------------------------------------------------
  customPkgFiles = nixFilesIn ../customPkgs;
  customPkgDirs = dirsIn ../customPkgs;

  # -- nixbook-shell settings helpers ------------------------------------------
  shellLib = import ../customPkgs/nixbook-shell/lib.nix { inherit lib; };
  typeName = v: (shellLib.settingType v).description;
  inherit (lib) types;
  evalSettings =
    settings:
    (lib.evalModules {
      modules = [
        shellLib.settingsModule
        { config = settings; }
      ];
    }).config;
  fails = x: !(builtins.tryEval (builtins.deepSeq x x)).success;
  leafCount =
    set:
    lib.foldl' (n: v: n + (if builtins.isAttrs v && v != { } then leafCount v else 1)) 0 (
      lib.attrValues set
    );
  flatDefaults = shellLib.flattenPaths [ ] shellLib.builtinDefaults;

  shellLibFailures = lib.runTests {
    testSettingTypeBool = {
      expr = typeName true;
      expected = types.bool.description;
    };
    testSettingTypeInt = {
      expr = typeName 3;
      expected = types.number.description;
    };
    testSettingTypeFloat = {
      expr = typeName 0.5;
      expected = types.number.description;
    };
    testSettingTypeString = {
      expr = typeName "x";
      expected = types.str.description;
    };
    testSettingTypeStringList = {
      expr = typeName [
        "a"
        "b"
      ];
      expected = (types.listOf types.str).description;
    };
    testSettingTypeMixedList = {
      expr = typeName [
        1
        "a"
      ];
      expected = (types.listOf types.anything).description;
    };
    testSettingTypeEmptyList = {
      expr = typeName [ ];
      expected = (types.listOf types.anything).description;
    };
    testSetLeavesDropsNullsAndEmptyBranches = {
      expr = shellLib.setLeaves {
        a = null;
        b = {
          c = null;
          d = {
            e = null;
          };
        };
        f = {
          g = 1;
          h = null;
        };
        i = false;
        j = [ ];
      };
      expected = {
        f.g = 1;
        i = false;
        j = [ ];
      };
    };
    testFlattenPaths = {
      expr = sorted (
        shellLib.flattenPaths [ ] {
          bar.layouts.left = [ "a" ];
          dock.enable = true;
          x = 1;
        }
      );
      expected = [
        "bar.layouts.left"
        "dock.enable"
        "x"
      ];
    };
    testOneOptionPerDefaultLeaf = {
      expr = lib.length flatDefaults;
      expected = leafCount shellLib.builtinDefaults;
    };
    testLiveKeysAreNotSettings = {
      expr = lib.filter (k: lib.elem k flatDefaults) shellLib.liveKeys;
      expected = [ ];
    };
    testUnsetSettingsAreNull = {
      expr = shellLib.setLeaves (evalSettings { });
      expected = { };
    };
    testSettingRoundTrip = {
      expr = shellLib.setLeaves (evalSettings {
        ai.includeSystemContext = true;
      });
      expected = {
        ai.includeSystemContext = true;
      };
    };
    testMisspeltSettingFails = {
      expr = fails (evalSettings {
        bar.definitelyNotASetting = true;
      });
      expected = true;
    };
    testWronglyTypedSettingFails = {
      expr = fails (evalSettings { ai.includeSystemContext = "yes"; }).ai.includeSystemContext;
      expected = true;
    };
  };

  check = what: ok: if ok then "ok" else throw "tests/repo.nix: ${what}";
in
{
  machines =
    check "hive.nix nodes (${toString hiveNodes}) differ from profiles/ (${toString profiles})"
      (hiveNodes == profiles);
  orphans = check "modules referenced from nowhere: ${toString orphans}" (orphans == [ ]);
  shellLib = check "nixbook-shell lib.nix unit tests failed:\n${
    lib.generators.toPretty { } shellLibFailures
  }" (shellLibFailures == [ ]);
  # Not a check: the node names, for CI's host matrix.
  inherit hiveNodes;
  packages = lib.genAttrs (map (lib.removeSuffix ".nix") customPkgFiles ++ customPkgDirs) (
    name:
    let
      path = ../customPkgs + "/${if lib.elem name customPkgDirs then name else "${name}.nix"}";
    in
    (import path { inherit pkgs; }).drvPath
  );
}
