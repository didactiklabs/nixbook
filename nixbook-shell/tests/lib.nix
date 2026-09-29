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
  # -- themes (src/modules/common/themes.json) ----------------------------
  testLegacyKeysAreNotSettings = {
    expr = lib.filter (k: lib.elem k flatDefaults) shellLib.legacyKeys;
    expected = [ ];
  };
  testThemeDefaultIsAChoice = {
    expr = lib.elem shellLib.builtinDefaults.appearance.theme shellLib.themeIds;
    expected = true;
  };
  # Each theme with variants has its settings object, with a valid default.
  testEveryThemeVariantIsASetting = {
    expr = lib.filter (
      key:
      !(lib.elem key flatDefaults)
      || !(lib.elem (lib.attrByPath (lib.splitString "." key) null
        shellLib.builtinDefaults
      ) shellLib.enumKeys.${key})
    ) (lib.attrNames shellLib.enumKeys);
    expected = [ ];
  };
  testUnknownThemeFails = {
    expr = fails (evalSettings { appearance.theme = "nope"; }).appearance.theme;
    expected = true;
  };
  testUnknownVariantFails = {
    expr = fails (evalSettings { appearance.persona.variant = "p9"; }).appearance.persona.variant;
    expected = true;
  };
  testThemeRoundTrip = {
    expr = shellLib.pinnedSettings (evalSettings {
      appearance.theme = "persona";
      appearance.persona.variant = "p4";
    });
    expected = {
      appearance.theme = "persona";
      appearance.persona.variant = "p4";
    };
  };
  testLegacyPersonaEnableTranslated = {
    expr = shellLib.pinnedSettings (evalSettings {
      appearance.persona.enable = true;
    });
    expected = {
      appearance.theme = "persona";
    };
  };
  testLegacyPersonaDisableTranslated = {
    expr = shellLib.pinnedSettings (evalSettings {
      appearance.persona.enable = false;
    });
    expected = {
      appearance.theme = "material";
    };
  };
  testThemeWinsOverLegacy = {
    expr =
      (shellLib.pinnedSettings (evalSettings {
        appearance.persona.enable = true;
        appearance.theme = "material";
      })).appearance.theme;
    expected = "material";
  };
  testThemeOfDefaults = {
    expr = shellLib.themeOf (evalSettings { });
    expected = {
      id = "material";
      variant = null;
      palette = null;
      variantPalette = null;
    };
  };
  testThemeOfPersona = {
    expr =
      let
        t = shellLib.themeOf (evalSettings {
          appearance.theme = "persona";
          appearance.persona.variant = "p3r";
        });
      in
      [
        t.id
        t.variant
        t.palette.frame
      ];
    expected = [
      "persona"
      "p3r"
      "#07163a"
    ];
  };
  testThemeOfLegacyConfig = {
    expr = (shellLib.themeOf { appearance.persona.enable = true; }).variant;
    expected = "p5";
  };
  testThemeOfPaletteOff = {
    expr =
      let
        t = shellLib.themeOf {
          appearance.theme = "persona";
          appearance.persona.palette = false;
        };
      in
      [
        t.palette
        t.variantPalette.frame
      ];
    expected = [
      null
      "#0a0a0a"
    ];
  };
  testThemeOfDefaultVariant = {
    expr = (shellLib.themeOf { appearance.theme = "chiikawa"; }).variant;
    expected = "chiikawa";
  };
  testThemeOfEvaluatedDefaults = {
    expr =
      (shellLib.themeOf (evalSettings {
        appearance.theme = "chiikawa";
      })).palette.background;
    expected = "#fffaf6";
  };
  testThemeOfCyberpunk = {
    expr =
      let
        t = shellLib.themeOf (evalSettings {
          appearance.theme = "cyberpunk";
          appearance.cyberpunk.variant = "red";
        });
      in
      [
        t.variant
        t.palette.primary
      ];
    expected = [
      "red"
      "#ff5a4f"
    ];
  };
  testCyberpunkDefaultVariant = {
    expr = (shellLib.themeOf { appearance.theme = "cyberpunk"; }).variant;
    expected = "yellow";
  };
  testCyberpunkBadVariantFails = {
    expr = fails (evalSettings { appearance.cyberpunk.variant = "blue"; }).appearance.cyberpunk.variant;
    expected = true;
  };
}
