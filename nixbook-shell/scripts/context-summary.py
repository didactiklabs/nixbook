"""The short machine context DAI's system prompt carries (bubble and side
panel), made from the whole system-context.md: the host, the shell, the
enabled modules, the operating system's main facts and the niri key bindings
one line each; what is left out (the how-tos, packages, Neovim keymaps, the
shell's Nix-set settings) is named at the end, for the machine_help tool,
which searches the whole file. Deterministic (no clock, nothing live): the
prompt it goes into must stay byte-stable for the model's prompt cache.

    context-summary.py SYSTEM_CONTEXT_MD [MAX_CHARS]   > summary.md
"""
import re
import sys

MAX = 6000
# Per kind of section, at most (before the overall cap).
CAPS = {"machine": 2200, "shell": 1100, "os": 900, "keys": 2600}


def sections(text):
    """[(title, body)] for each "## " section (the "# " preamble dropped)."""
    out, title, body = [], None, []
    for line in text.splitlines():
        if line.startswith("## "):
            if title is not None:
                out.append((title, "\n".join(body).strip("\n")))
            title, body = line[3:].strip(), []
        elif title is not None:
            body.append(line)
    if title is not None:
        out.append((title, "\n".join(body).strip("\n")))
    return out


def kind(title):
    t = title.lower()
    if t.startswith("this machine"):
        return "machine"
    if t.startswith("desktop shell"):
        return "shell"
    if t.startswith("operating system"):
        return "os"
    if t.startswith("keyboard shortcuts") or "keybind" in t or "key bindings" in t:
        return "keys"
    return "other"


def cap(text, limit):
    """At most `limit` chars, cut at a line end (else a word) with "…"."""
    if len(text) <= limit:
        return text
    cut = text[: limit - 1]
    nl = cut.rfind("\n")
    if nl > limit // 2:
        return cut[:nl] + "\n…"
    sp = cut.rfind(" ")
    return (cut[:sp] if sp > limit // 2 else cut) + "…"


def shell_part(body):
    # The description, without the list of settings set in Nix.
    head = re.split(r"\n\s*Settings set in Nix on this machine:", body, maxsplit=1)[0]
    head = re.sub(r"\s*\n\s*", " ", head).strip()
    pinned = len(re.findall(r"^- `[^`]+` = ", body, flags=re.M))
    if pinned:
        head += f" Settings set in Nix on this machine (locked in its Settings window): {pinned}."
    return head


def os_part(body):
    lines = []
    for line in body.splitlines():
        line = line.rstrip()
        # The long lists (every option set enabled…) stay for machine_help.
        if not line or len(line) > 220:
            continue
        lines.append(line)
    return "\n".join(lines)


SPAWN_ARG = re.compile(r'"((?:[^"\\]|\\.)*)"|(\S+)')


def bind_line(line):
    """`Mod+A { close-window; }` -> `Mod+A close-window`; a spawn of the
    shell's IPC -> `shell <target> <fn>`; other spawns -> `run <command>`."""
    m = re.match(r'\s*"?([^"\s{]+)"?((?:\s+[\w-]+=(?:"[^"]*"|\S+))*)\s*\{\s*(.*?)\s*;?\s*\}\s*$', line)
    if not m:
        return None
    key, action = m.group(1), m.group(3).strip().rstrip(";").strip()
    if action.startswith("spawn") or action.startswith("spawn-sh"):
        words = [a or b for a, b in SPAWN_ARG.findall(action.split(None, 1)[1] if " " in action else "")]
        if words[:4] == ["nixbook-shell", "ipc", "call", words[3] if len(words) > 3 else ""] and len(words) >= 5:
            what = "shell " + " ".join(words[3:5])
        elif words[:1] == ["bash"] or words[:1] == ["sh"]:
            what = "run a shell script"
        else:
            what = "run " + " ".join(words)
        if len(what) > 60:
            what = what[:59] + "…"
    else:
        what = re.sub(r"\s+", " ", action)
    return f"{key} {what}"


def keys_part(body):
    binds = []
    inside = False
    for line in body.splitlines():
        s = line.strip()
        if s.startswith("binds"):
            inside = True
            continue
        if not inside or s.startswith("```"):
            continue
        if s == "}":
            inside = False
            continue
        b = bind_line(s)
        if b:
            binds.append(b)
    if not binds:
        return ""
    return ("Mod = the Super key; \"shell X Y\" = nixbook-shell ipc call X Y.\n" + "\n".join(binds))


def summary(text, limit=MAX):
    kept, left = [], []
    for title, body in sections(text):
        k = kind(title)
        if k == "machine":
            part = body
        elif k == "shell":
            part = shell_part(body)
        elif k == "os":
            part = os_part(body)
        elif k == "keys":
            part = keys_part(body)
            title = "Key bindings (niri)"
        else:
            left.append(re.sub(r"\s*\(.*\)$", "", title))
            continue
        if part:
            kept.append((k, title, cap(part, CAPS[k])))
    head = "# About this machine (summary)\n"
    tail = ("\nFor anything else about this machine, call machine_help with the question: it searches the whole "
            "reference (" + "; ".join(left + ["the details of the sections above"]) + ").") if left or kept else ""
    out = head + "".join(f"\n## {t}\n{p}\n" for _, t, p in kept) + tail
    # Over the cap: the biggest parts shortened, the key bindings last.
    for k in ["os", "shell", "machine", "keys"]:
        if len(out) <= limit:
            break
        over = len(out) - limit
        kept = [(kk, t, cap(p, max(200, len(p) - over - 2)) if kk == k else p) for kk, t, p in kept]
        out = head + "".join(f"\n## {t}\n{p}\n" for _, t, p in kept) + tail
    return cap(out, limit)


def main():
    text = open(sys.argv[1], encoding="utf-8").read()
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else MAX
    sys.stdout.write(summary(text, limit).rstrip("\n") + "\n")


if __name__ == "__main__":
    main()
