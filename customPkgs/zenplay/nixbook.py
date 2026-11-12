"""ZenPlay's unpacked app, adjusted for nixbook.

  - one instance: the window's close button (and niri's close) only hides it
    to the tray, and upstream takes no single-instance lock, so starting
    ZenPlay again from the launcher ran a second copy beside the hidden one.
    A second start now shows the window of the first (and is what
    nixbook-electron-app relies on: it hands over to the bridged instance).
  - hardware acceleration on unless the user turned it off in the app's menu
    (upstream starts with --disable-gpu until it is turned on: video decoded
    and composited on the CPU).

Each pattern must match exactly once: when a release changes that code, the
build stops here, and this script needs updating.

    python3 nixbook.py APP_DIR
"""

import os
import sys

app = sys.argv[1]

# (file, what it does, text, replacement)
PATCHES = [
    ("main.js", "one instance: a second start shows the first one's window",
     "app.whenReady().then(createWindow);",
     """if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (!mainWindow) return;
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.show();
    mainWindow.focus();
  });
  app.whenReady().then(createWindow);
}"""),
    ("settings-manager.js", "hardware acceleration on by default",
     "  hardwareAcceleration: false,", "  hardwareAcceleration: true,"),
]

failed = []
for name, what, text, replacement in PATCHES:
    path = os.path.join(app, name)
    with open(path, encoding="utf-8") as f:
        source = f.read()
    n = source.count(text)
    if n != 1:
        failed.append(f"{name}: {what}: found {n} times, expected once")
        continue
    with open(path, "w", encoding="utf-8") as f:
        f.write(source.replace(text, replacement))
    print(f"zenplay: {what}")

if failed:
    sys.exit("zenplay/nixbook.py: this release changed the code these patches expect:\n  " + "\n  ".join(failed))
