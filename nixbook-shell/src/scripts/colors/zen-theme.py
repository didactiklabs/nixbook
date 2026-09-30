#!/usr/bin/env python3
"""Zen Browser's side of the app colours (Settings > Appearance > Apps).

Usage: zen-theme.py profiles         print the profile directories
       zen-theme.py sync [CHANGED]   set the profiles up to load the colours;
                                     exit 3 when a running Zen needs a
                                     restart to show them (CHANGED: the
                                     generated CSS files that changed)
       zen-theme.py remove           undo `sync`, remove the generated CSS
       zen-theme.py restart          quit the running Zen, sync, start it again

Zen reads its chrome CSS only at startup: the generated
chrome/nixbook-shell.css is imported at the top of the profile's
userChrome.css, which Zen only loads with the
toolkit.legacyUserProfileCustomizations.stylesheets pref. That pref goes into
prefs.js, which a running Zen rewrites when it quits: it's only written while
the profile is closed (or during `restart`). A userChrome.css that is a
symlink (managed elsewhere, e.g. by Home Manager) is left alone.

`restart` quits Zen with SIGTERM (Firefox's normal quit), waits for it to exit
and starts the same executable again; Zen restores the session
(browser.startup.page = 3, its default).
"""
import configparser
import os
import re
import shutil
import signal
import subprocess
import sys
import time

CSS_NAME = "nixbook-shell.css"
IMPORT = f'@import url("{CSS_NAME}");'
PREF = "toolkit.legacyUserProfileCustomizations.stylesheets"
PREF_LINE = f'user_pref("{PREF}", true);'
PREF_RE = re.compile(r'^\s*user_pref\("' + re.escape(PREF) + r'",\s*(true|false)\);\s*$', re.M)
NEEDS_RESTART = 3


def roots():
    config = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return [os.path.join(config, "zen"), os.path.expanduser("~/.zen")]


def profiles():
    seen = []
    for root in roots():
        ini = configparser.ConfigParser(interpolation=None, strict=False)
        try:
            with open(os.path.join(root, "profiles.ini")) as f:
                ini.read_file(f)
        except (OSError, configparser.Error):
            continue
        for section in ini.sections():
            if not section.startswith("Profile") or "Path" not in ini[section]:
                continue
            path = ini[section]["Path"]
            if ini[section].get("IsRelative", "1") == "1":
                path = os.path.join(root, path)
            path = os.path.realpath(path)
            if os.path.isdir(path) and path not in seen:
                seen.append(path)
    return seen


def running_pid(profile):
    """The pid of the Zen that has PROFILE open: its `lock` symlink ("host:+pid")."""
    try:
        target = os.readlink(os.path.join(profile, "lock"))
    except OSError:
        return None
    match = re.search(r"\+(\d+)$", target)
    if match and os.path.exists(f"/proc/{match.group(1)}"):
        return int(match.group(1))
    return None


def write(path, text):
    tmp = f"{path}.nixbook-shell.tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)


def read(path):
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        return ""


def ensure_import(profile):
    """The import at the top of userChrome.css (@import must precede every
    other rule). False when it can't be added."""
    path = os.path.join(profile, "chrome", "userChrome.css")
    if os.path.islink(path):
        return IMPORT in read(path)
    text = read(path)
    if IMPORT in text:
        return True
    os.makedirs(os.path.dirname(path), exist_ok=True)
    write(path, IMPORT + "\n" + text)
    return True


def pref_set(profile):
    for name in ("user.js", "prefs.js"):
        values = PREF_RE.findall(read(os.path.join(profile, name)))
        if values:
            # user.js is applied over prefs.js at startup.
            return values[-1] == "true"
    return False


def ensure_pref(profile):
    """Only while the profile is closed: a running Zen rewrites prefs.js."""
    if pref_set(profile):
        return True
    path = os.path.join(profile, "prefs.js")
    text = read(path)
    if PREF_RE.search(text):
        text = PREF_RE.sub(PREF_LINE, text)
    else:
        text = text + ("" if text.endswith("\n") or not text else "\n") + PREF_LINE + "\n"
    write(path, text)
    return True


def sync(changed):
    """Exit status NEEDS_RESTART when a running Zen doesn't show the current
    colours yet: the CSS changed or the profile wasn't set up to load it."""
    changed = {os.path.realpath(p) for p in changed}
    status = 0
    for profile in profiles():
        css = os.path.join(profile, "chrome", CSS_NAME)
        if not os.path.exists(css):
            continue
        imported = ensure_import(profile)
        if running_pid(profile) is None:
            ensure_pref(profile)
        elif imported and (not pref_set(profile) or os.path.realpath(css) in changed):
            status = NEEDS_RESTART
    return status


def remove():
    for profile in profiles():
        path = os.path.join(profile, "chrome", "userChrome.css")
        if not os.path.islink(path):
            text = read(path)
            if IMPORT in text:
                write(path, text.replace(IMPORT + "\n", "").replace(IMPORT, ""))
        try:
            os.remove(os.path.join(profile, "chrome", CSS_NAME))
        except FileNotFoundError:
            pass
    return 0


def launch_command(pid):
    """The executable as it was started (the Nix wrapper keeps its path as
    argv[0]), with the profile options it was given."""
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        argv = [a.decode(errors="replace") for a in f.read().split(b"\0") if a]
    command, args = argv[:1], iter(argv[1:])
    for arg in args:
        if arg in ("-P", "-p", "--P", "-profile", "--profile"):
            command += [arg, next(args, "")]
    if command and "/" not in command[0]:
        command[0] = shutil.which(command[0]) or command[0]
    return command


def spawn(command):
    # niri starts it with the session's environment, not the shell's.
    if shutil.which("niri"):
        if subprocess.run(["niri", "msg", "action", "spawn", "--", *command]).returncode == 0:
            return
    subprocess.Popen(command, start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def restart():
    commands = {}
    for profile in profiles():
        pid = running_pid(profile)
        if pid is not None and pid not in commands:
            commands[pid] = launch_command(pid)
    for pid in commands:
        os.kill(pid, signal.SIGTERM)
    deadline = time.monotonic() + 30
    while any(os.path.exists(f"/proc/{pid}") for pid in commands):
        if time.monotonic() > deadline:
            print("Zen didn't quit within 30 s, not restarted", file=sys.stderr)
            return 1
        time.sleep(0.2)
    sync([])
    for command in commands.values():
        spawn(command)
    return 0


def main(args):
    if args == ["profiles"]:
        print("\n".join(profiles()))
        return 0
    if args[:1] == ["sync"]:
        return sync(args[1:])
    if args == ["remove"]:
        return remove()
    if args == ["restart"]:
        return restart()
    sys.exit(__doc__)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
