/*
  Unit tests of the settings helpers (lib.nix). Evaluates to the list of
  failures (empty when everything passes):

    nix-instantiate --eval --strict --json --expr 'import ./tests/lib.nix { }'
*/
{
  lib ? (import (import ../npins).nixpkgs { }).lib,
}:
let
  sorted = lib.sort lib.lessThan;
  shellLib = import ../lib.nix { inherit lib; };
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

in
lib.runTests {
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
}
