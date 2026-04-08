{ sources }:
final: prev: {
  jiratui = prev.jiratui.overrideAttrs (old: {
    version = "1.7.0";
    src = sources.jiratui;
    dependencies = (old.dependencies or [ ]) ++ [
      prev.python3Packages.puremagic
      prev.python3Packages.textual-autocomplete
      prev.python3Packages.urllib3
    ];
    pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [
      "pydantic-settings"
    ];
  });
}
