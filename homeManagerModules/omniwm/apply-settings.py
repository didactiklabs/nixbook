"""Put the OmniWM settings set in Nix into OmniWM's own settings.toml.

usage: apply-settings.py PINNED.json SETTINGS.toml

OmniWM 0.8 rejects a settings.toml as a whole when a required key is missing,
so Nix can't write the file from the few keys it sets: OmniWM writes it (all
its keys, at first start or when its Settings window saves) and this merges
the Nix ones in, leaving every other key as it is. PINNED.json is
{"settings": {table: {key: value}}, "hotkeys": {action id: binding}}.

- settings: merged table by table; a value (lists included) replaces the
  file's.
- hotkeys: the [[hotkeys]] entry of each action gets the Nix binding; any
  other action on that same chord becomes "Unassigned" (two actions on one
  chord: only one of them would fire). An action id the file doesn't list is
  skipped with a message (it may not exist in this OmniWM), except
  `openApp.<bundle id>`, which OmniWM makes for any app and only lists once
  bound.

The file is only rewritten when something changes (renamed into place, so
OmniWM's live reload never reads half a file), and its first version is kept
once as settings.toml.before-nixbook. Run by the Home Manager activation and
by a launchd agent watching the file, so a Nix key changed in OmniWM's
Settings window is put back.
"""

import json
import os
import sys
import tempfile
import tomllib

import tomli_w

MODIFIERS = {"control", "option", "shift", "command", "hyper"}


def chord(binding):
    """A binding in a form two spellings of one chord share."""
    if binding.strip().lower() == "unassigned":
        return None
    parts = [p.strip() for p in binding.split("+")]
    key = parts[-1].lower()
    mods = []
    for p in parts[:-1]:
        words = p.lower().split()
        if words and words[-1] in MODIFIERS:
            mods.append(" ".join(words))
        else:
            mods.append(p.lower())
    return (tuple(sorted(mods)), key)


def like(value, current):
    """value with the number type of the file's current value: Nix writes 10.0
    to JSON as 10, and OmniWM's strict schema refuses an integer where it
    reads a float."""
    if isinstance(current, float) and isinstance(value, int) and not isinstance(value, bool):
        return float(value)
    if isinstance(value, list) and isinstance(current, list) and current:
        return [like(v, current[0]) for v in value]
    return value


def merge(into, settings, path=""):
    changed = False
    for key, value in settings.items():
        where = f"{path}{key}"
        if isinstance(value, dict) and isinstance(into.get(key), dict):
            changed |= merge(into[key], value, where + ".")
            continue
        value = like(value, into.get(key))
        if into.get(key) != value:
            into[key] = value
            changed = True
    return changed


def apply_hotkeys(doc, hotkeys):
    entries = doc.get("hotkeys")
    if not isinstance(entries, list):
        print("omniwm: settings.toml has no [[hotkeys]]: hotkeys left alone", file=sys.stderr)
        return False
    changed = False
    by_id = {e.get("id"): e for e in entries if isinstance(e, dict)}
    for action, binding in hotkeys.items():
        entry = by_id.get(action)
        if entry is None:
            if not action.startswith("openApp."):
                print(f"omniwm: no action {action!r} in this OmniWM: skipped", file=sys.stderr)
                continue
            entry = {"binding": "Unassigned", "id": action}
            entries.append(entry)
            by_id[action] = entry
            changed = True
        wanted = chord(binding)
        if wanted is not None:
            for other in entries:
                if other is not entry and chord(str(other.get("binding", ""))) == wanted:
                    other["binding"] = "Unassigned"
                    changed = True
        if chord(str(entry.get("binding", ""))) != wanted:
            entry["binding"] = binding
            changed = True
    return changed


def main():
    pinned_path, settings_path = sys.argv[1], sys.argv[2]
    with open(pinned_path) as f:
        pinned = json.load(f)
    try:
        with open(settings_path, "rb") as f:
            raw = f.read()
    except FileNotFoundError:
        print(
            f"omniwm: {settings_path} doesn't exist yet: the Nix settings are applied "
            "once OmniWM has written it (start OmniWM, or save its Settings once)",
            file=sys.stderr,
        )
        return 0
    try:
        doc = tomllib.loads(raw.decode())
    except (tomllib.TOMLDecodeError, UnicodeDecodeError) as e:
        print(f"omniwm: {settings_path} can't be read ({e}): left alone", file=sys.stderr)
        return 0

    changed = merge(doc, pinned.get("settings", {}))
    changed |= apply_hotkeys(doc, pinned.get("hotkeys", {}))
    if not changed:
        return 0

    backup = settings_path + ".before-nixbook"
    if not os.path.exists(backup):
        with open(backup, "wb") as f:
            f.write(raw)
    directory = os.path.dirname(os.path.abspath(settings_path))
    mode = os.stat(settings_path).st_mode & 0o777
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".settings.toml.")
    try:
        with os.fdopen(fd, "wb") as f:
            tomli_w.dump(doc, f)
        os.chmod(tmp, mode)
        os.replace(tmp, settings_path)
    except BaseException:
        os.unlink(tmp)
        raise
    print(f"omniwm: applied the Nix settings to {settings_path}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
