"""Build the fact file for the local configuration assistant
(services/ConfigAssistant.qml): one plain sentence per fact, which the shell
retrieves by keyword for each question and checks answers against.

  assistant-facts.py <input.json> <binds.kdl>  >  system-facts.json

input.json (from homeManagerModules/nixbookShellConfig.nix): host, user,
enabled/all NixOS and Home Manager module names, the shell settings pinned in
Nix ({"dot.path": value}), package names. binds.kdl: niri's rendered
`binds { ... }` block (may be empty). Small local models answer keybind
questions reliably from "Press Mod+D to open the app launcher." sentences;
they don't from raw KDL spawn commands.
"""

import json
import re
import sys

# nixbook-shell IPC targets bound in niriConfig.nix.
IPC = {
    ("search", "toggle"): "open the app launcher (search and start apps, calculator, commands)",
    ("search", "workspacesToggle"): "open the shell's workspace overview",
    ("search", "clipboardToggle"): "open the clipboard history",
    ("sidebarLeft", "toggle"): "open the left sidebar (AI assistant, translator)",
    ("sidebarRight", "toggle"): "open the right sidebar (quick settings, notifications, calendar)",
    ("settings", "toggle"): "open the shell settings window: the menu to configure the shell (bar, dock, widgets, theme, wallpaper, notifications)",
    ("session", "toggle"): "open the power menu: lock the screen, log out, suspend, reboot or shut down",
    ("wallpaperSelector", "toggle"): "open the wallpaper selector",
    ("region", "screenshot"): "take a screenshot of a screen region",
    ("region", "ocr"): "copy the text of a screen region (OCR)",
    ("region", "record"): "record a screen region",
    ("region", "search"): "search a screen region with Google Lens",
    ("bar", "toggle"): "show or hide the bar",
    ("lock", "activate"): "lock the screen",
    ("overlay", "toggle"): "open the overlay widgets",
    ("mediaControls", "toggle"): "open the media controls",
}

NIRI = {
    "toggle-window-floating": "toggle the focused window between floating and tiled",
    "toggle-overview": "open niri's overview of all workspaces and windows",
    "switch-preset-column-width": "cycle the column width presets",
    "switch-focus-between-floating-and-tiling": "move focus between floating and tiled windows",
    "close-window": "close the focused window",
    "fullscreen-window": "make the focused window fullscreen",
    "maximize-column": "maximize the column",
    "center-column": "center the column",
    "consume-or-expel-window-left": "move the window into or out of the column on the left",
    "consume-or-expel-window-right": "move the window into or out of the column on the right",
    "power-off-monitors": "turn the monitors off",
    "quit": "quit niri (log out)",
    "screenshot": "take a screenshot (niri)",
    "screenshot-window": "take a screenshot of the focused window (niri)",
    "screenshot-screen": "take a screenshot of the screen (niri)",
}


def describe(action: str) -> str:
    args = re.findall(r'"((?:[^"\\]|\\.)*)"', action)
    name = action.split()[0] if action else ""
    if name == "spawn" and args:
        if args[:3] == ["nixbook-shell", "ipc", "call"] and len(args) >= 5:
            return IPC.get((args[3], args[4]), f"nixbook-shell panel: {args[3]} {args[4]}")
        if args[0] == "wpctl":
            if "set-mute" in args:
                return "mute or unmute the audio"
            return "volume down" if args[-1].endswith("-") else "volume up"
        if args[0] == "brightnessctl":
            return "brightness down" if args[-1].endswith("-") else "brightness up"
        if args[0] in ("bash", "sh") and "hypridle" in action:
            return "toggle caffeine mode (idle inhibition): keeps the display on and disables automatic locking and suspend"
        if args[0] in ("bash", "sh"):
            return "run a script"
        if args[0] == "kitty":
            return "open a terminal (kitty)"
        return "launch " + " ".join(args)
    if name in NIRI:
        return NIRI[name]
    rest = " ".join(args) or " ".join(action.split()[1:])
    return (name.replace("-", " ") + (" " + rest if rest else "")).strip()


def binds(kdl: str):
    for line in kdl.splitlines():
        m = re.match(r'\s*"?([^"{\s]+)"?\s*(?:[^{]*)\{\s*(.*?);?\s*\}\s*$', line)
        if m:
            yield m.group(1), describe(m.group(2))


def main():
    info = json.load(open(sys.argv[1]))
    kdl = open(sys.argv[2]).read() if len(sys.argv) > 2 else ""
    host, user = info["host"], info["user"]
    core = (
        f'You help the user with their NixOS laptop "{host}" (user {user}). Answer briefly, '
        "using ONLY the facts below. If they don't contain the answer, say you don't know. "
        "Mod = the Super (Windows) key.\nFacts:\n"
        f"- Enabled NixOS modules: {', '.join(info['osEnabled'])}\n"
        f"- Enabled Home Manager modules: {', '.join(info['hmEnabled'])}\n"
        "- Any module not listed above is not enabled.\n"
        f"- To change the system: edit profiles/{host}/default.nix; user modules and their options: "
        f"profiles/{host}/{user}/default.nix. Shell (bar, dock, widgets…) settings set in Nix: "
        "homeManagerModules/nixbookShellConfig/settings.nix (shared) or nixbookShellConfig.settings in the "
        "user profile. Apply with `colmena apply-local --sudo switch` from the nixbook repository. "
        "Other shell settings: its Settings window."
    )
    facts = [f"Press {key} to {what}." for key, what in binds(kdl)]
    # The core statements as retrievable facts too, so questions about them
    # ("how do I apply my changes?") aren't mistaken for uncovered ones.
    facts += [
        "To apply a configuration change, run `colmena apply-local --sudo switch` from the nixbook repository.",
        f"System settings (NixOS modules and their options) are changed in profiles/{host}/default.nix.",
        f"This user's Home Manager modules and their options are changed in profiles/{host}/{user}/default.nix.",
        "Shell settings (bar, dock, widgets, notifications, theme) set in Nix are in homeManagerModules/nixbookShellConfig/settings.nix (shared) or nixbookShellConfig.settings in the user profile; the others are changed in the shell's Settings window.",
        "The keyboard shortcuts are documented in KEYBINDS.md in the nixbook repository.",
    ]
    facts += [f"The shell setting {path} is set in Nix to {json.dumps(value, ensure_ascii=False)}."
              for path, value in sorted(info["pinned"].items())]
    # Home Manager's desktop-entry shadows (hidden launcher entries) and
    # session scripts aren't things anyone asks about: only noise for retrieval.
    packages = [p for p in info["packages"] if not p.endswith((".desktop", ".sh"))]
    facts += [f"The package {p} is installed." for p in packages]
    json.dump({
        "host": host,
        "user": user,
        "core": core,
        "facts": facts,
        "modules": {"all": sorted(set(info["osAll"] + info["hmAll"])),
                    "enabled": sorted(set(info["osEnabled"] + info["hmEnabled"]))},
        "packages": packages,
        "settingPaths": sorted(set(info.get("settingPaths", []))),
    }, sys.stdout, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
