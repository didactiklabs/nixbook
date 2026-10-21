{ lib }:
# The unit names a list of option definitions (an option's
# definitionsWithLocations) gives in files under root: what this repository
# defines itself, for the desktop agent's fixer (nixbook-improve). Through
# mkIf (only when its condition holds), mkMerge, mkOverride and mkOrder.
root:
let
  names =
    v:
    if !builtins.isAttrs v then
      [ ]
    else if (v._type or null) == "if" then
      lib.optionals v.condition (names v.content)
    else if (v._type or null) == "merge" then
      lib.concatMap names v.contents
    else if
      lib.elem (v._type or null) [
        "override"
        "order"
      ]
    then
      names v.content
    else
      lib.attrNames v;
in
defs:
lib.unique (
  lib.concatMap (d: names d.value) (lib.filter (d: lib.hasPrefix root (toString d.file)) defs)
)
