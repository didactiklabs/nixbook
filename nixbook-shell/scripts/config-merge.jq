# jq helpers shared by the `nixbook-shell config` CLI (the Home Manager activation
# itself only needs `$live * $pinned`: every key Nix sets wins, every other
# key is left alone).

def leaves:
  . as $in
  | if type == "object" and length > 0 then
      (keys_unsorted[] as $k | ($in[$k] | leaves | [$k] + .))
    else [] end;

def at($p): try getpath($p) catch null;

# Nix literal for a JSON value (for `nixbook-shell config diff`). Negative numbers
# are parenthesised so list elements can't read as a subtraction (`[ 1 -1 ]`).
def nixnum: tostring | if startswith("-") then "(" + . + ")" else . end;
def nixstr: "\"" + (gsub("\\\\"; "\\\\") | gsub("\""; "\\\"") | gsub("\\$\\{"; "\\${") | gsub("\n"; "\\n")) + "\"";
def nixkey: if test("^[A-Za-z_][A-Za-z0-9_'-]*$") then . else nixstr end;
def tonix:
  if type == "string" then nixstr
  elif type == "array" then (if length == 0 then "[ ]" else "[ " + (map(tonix) | join(" ")) + " ]" end)
  elif type == "object" then
    (if length == 0 then "{ }" else "{ " + (to_entries | map((.key | nixkey) + " = " + (.value | tonix) + ";") | join(" ")) + " }" end)
  elif type == "number" then nixnum
  elif type == "null" then "null"
  else tostring end;

def nixline($p; $v): ($p | map(nixkey) | join(".")) + " = " + ($v | tonix) + ";";

# Multi-line Nix expression for a JSON value (`nixbook-shell config dump`, a
# starting point for a `programs.nixbook-shell.settings` file).
def nixpp($ind):
  if type == "object" then
    if length == 0 then "{ }"
    else "{\n" + (to_entries | map($ind + "  " + (.key | nixkey) + " = " + (.value | nixpp($ind + "  ")) + ";") | join("\n")) + "\n" + $ind + "}"
    end
  elif type == "array" then
    if length == 0 then "[ ]"
    else "[\n" + (map($ind + "  " + nixpp($ind + "  ")) | join("\n")) + "\n" + $ind + "]"
    end
  elif type == "string" then nixstr
  elif type == "number" then nixnum
  elif type == "null" then "null"
  else tostring end;
