pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Per-monitor desktop widgets. `background.widgets.perScreen` maps
 * "<widget>@<output>" to overrides of that widget's own config on that
 * monitor: position (x/y/z), size (sizeMode, ringSize, height, fontSize…) and
 * `enable`. Anything not overridden falls back to the widget's shared entry
 * (`background.widgets.<widget>`), so a single-monitor setup is unchanged.
 * The old position-only `screenPositions` map is still read as a fallback.
 *
 * Some widgets can be added several times (`multiInstance`): the plain name
 * ("customImage") is the first, the widget's own entry; "customImage:<id>"
 * names an extra one, stored in `background.widgets.customImage.instances`
 * (each a full entry with its own `id`). Read and write entries through
 * entry()/setEntry(), which handle both.
 */
Singleton {
    id: root

    function load() {}

    // Widgets that can be added more than once, with the settings a new one
    // starts from (Config.qml's defaults for that widget).
    readonly property var multiInstance: ({
        customImage: {
            enable: true, placementStrategy: "free", x: 400, y: 100, z: 0,
            path: "", shape: "Cookie4Sided", size: 200, zoom: 1, offsetX: 0, offsetY: 0,
            rotation: 0, opacity: 1, mirror: false, grayscale: false,
        },
    })

    // {base, id} for an extra instance's name, null for a plain widget name.
    function splitName(name) {
        const i = name.indexOf(":");
        return i < 0 ? null : { base: name.slice(0, i), id: name.slice(i + 1) };
    }
    // The widget's config entry (undefined for a removed instance).
    function entry(name) {
        const w = Config.options?.background?.widgets;
        const s = root.splitName(name);
        if (!s) return w?.[name];
        return (w?.[s.base]?.instances ?? []).find(e => e.id === s.id);
    }
    function setEntry(name, values) {
        const w = Config.options.background.widgets;
        const s = root.splitName(name);
        if (!s) {
            for (const prop in values) w[name][prop] = values[prop];
            return;
        }
        const current = root.entry(name);
        if (!current || Object.keys(values).every(prop => current[prop] === values[prop]))
            return;
        // A new list, so bindings (and the config file) see the change.
        w[s.base].instances = w[s.base].instances.map(e => e.id === s.id ? Object.assign({}, e, values) : e);
    }
    // The names of the widget's extra instances.
    function instanceNames(base) {
        return (Config.options?.background?.widgets?.[base]?.instances ?? []).map(e => `${base}:${e.id}`);
    }
    // Adds an instance of `base`, a little offset from the previous one, on
    // `screen` only (every monitor when not given); returns its name.
    function addInstance(base, screen) {
        const w = Config.options.background.widgets;
        const list = w[base].instances ?? [];
        // Unique even for several added within the same millisecond.
        let n = Date.now();
        while (list.some(e => e.id === n.toString(36)))
            n++;
        const id = n.toString(36);
        const step = 40 * (list.length + 1);
        const fresh = Object.assign({}, root.multiInstance[base], {
            id: id, x: (w[base].x ?? 400) + step, y: (w[base].y ?? 100) + step,
        });
        w[base].instances = [...list, fresh];
        const name = `${base}:${id}`;
        if (screen)
            root.setShownOn(name, [screen]);
        return name;
    }
    // Removes an extra instance and its per-monitor overrides.
    function removeInstance(name) {
        const s = root.splitName(name);
        if (!s) return;
        const w = Config.options.background.widgets;
        w[s.base].instances = (w[s.base].instances ?? []).filter(e => e.id !== s.id);
        const all = Object.assign({}, w.perScreen ?? {});
        let changed = false;
        for (const k in all) {
            if (k.startsWith(name + "@")) {
                delete all[k];
                changed = true;
            }
        }
        if (changed)
            w.perScreen = all;
    }

    function key(widget, screen) {
        return `${widget}@${screen}`;
    }
    function overrides(widget, screen) {
        if (!screen) return null;
        const w = Config.options?.background?.widgets;
        const k = root.key(widget, screen);
        return w?.perScreen?.[k] ?? w?.screenPositions?.[k] ?? null;
    }
    // The widget's `prop` on `screen`: its override there, else the shared value.
    function value(widget, screen, prop, fallback) {
        const o = root.overrides(widget, screen);
        if (o && o[prop] !== undefined) return o[prop];
        return root.entry(widget)?.[prop] ?? fallback;
    }
    // Store `values` ({prop: value}) for the widget on `screen` only (the
    // shared entry when no screen is known).
    function setValues(widget, screen, values) {
        const w = Config.options.background.widgets;
        if (!screen) {
            root.setEntry(widget, values);
            return;
        }
        const k = root.key(widget, screen);
        const all = Object.assign({}, w.perScreen ?? {});
        all[k] = Object.assign({}, root.overrides(widget, screen) ?? {}, values);
        w.perScreen = all; // a new object, so bindings see the change
    }
    // Where the widget shows: `screens` null hides it everywhere, [] shows it
    // on every monitor (of background.screenList), a list only on those
    // monitors. Replaces any per-monitor choice.
    function setShownOn(name, screens) {
        const w = Config.options.background.widgets;
        root.setEntry(name, { enable: Array.isArray(screens) && screens.length === 0 });
        const before = w.perScreen ?? {};
        const all = Object.assign({}, before);
        for (const k in all) {
            if (k.startsWith(name + "@") && all[k].enable !== undefined) {
                all[k] = Object.assign({}, all[k]);
                delete all[k].enable;
            }
        }
        for (const screen of screens ?? [])
            all[root.key(name, screen)] = Object.assign({}, root.overrides(name, screen) ?? {}, { enable: true });
        if (JSON.stringify(all) !== JSON.stringify(before))
            w.perScreen = all;
    }
    // Each widget's box on each monitor ("<widget>@<monitor>" -> {x, y,
    // width, height, z}), reported by the widgets themselves; runtime only.
    property var geometries: ({})
    function reportGeometry(widget, screen, box) {
        if (!screen) return;
        const all = Object.assign({}, root.geometries);
        if (box) all[root.key(widget, screen)] = box;
        else delete all[root.key(widget, screen)];
        root.geometries = all;
    }
    // Widgets `place` and friends take: the fixed ones, the visualizer, and
    // the extra instances (customImage:<id>).
    function placeable(name) {
        return root.names.includes(name) || name === "visualizer" || root.instanceNames("customImage").includes(name);
    }

    function shownAnywhere(name) {
        return Quickshell.screens.some(s => root.enabledOn(name, s.name));
    }

    // Whether the widget shows on `screen`: an explicit per-monitor choice
    // wins (even outside background.screenList); otherwise the shared switch,
    // on the monitors of screenList (all when empty).
    function enabledOn(widget, screen) {
        const o = root.overrides(widget, screen);
        if (o && o.enable !== undefined) return o.enable;
        const list = Config.options?.background?.screenList ?? [];
        return (root.entry(widget)?.enable ?? false)
            && (list.length === 0 || list.includes(screen));
    }

    // The desktop widgets WidgetsLoader shows, by config key.
    readonly property var names: ["customImage", "sticker", "calendar", "nextEvent", "musicRecognition", "weather", "clock", "notes", "media", "images",
        "resources", "worldClock", "userCard", "todo", "timers", "customText"]

    // `nixbook-shell ipc call widgets list|show|hide NAME`: for key bindings
    // and the desktop MCP server. show/hide set the shared switch and drop
    // the per-monitor ones, so the widget shows (or not) everywhere.
    IpcHandler {
        target: "widgets"

        function list(): string {
            const w = Config.options?.background?.widgets ?? {};
            return JSON.stringify(root.names.filter(n => w[n] !== undefined).map(n => ({
                name: n,
                enabled: w[n].enable ?? false,
                placement: w[n].placementStrategy ?? "",
            })));
        }
        function show(name: string): string {
            return root._setEnabled(name, true);
        }
        function hide(name: string): string {
            return root._setEnabled(name, false);
        }
        // The monitors (logical size) and the widgets showing on them, with
        // their boxes: to arrange them without overlaps.
        function layout(): string {
            const widgets = [];
            for (const k in root.geometries) {
                const at = k.lastIndexOf("@");
                const name = k.slice(0, at);
                widgets.push(Object.assign({ name: name, monitor: k.slice(at + 1),
                    placement: root.entry(name)?.placementStrategy ?? "free" }, root.geometries[k]));
            }
            return JSON.stringify({
                monitors: Quickshell.screens.map(s => ({ name: s.name, width: s.width, height: s.height })),
                widgets: widgets.sort((a, b) => a.monitor.localeCompare(b.monitor) || a.y - b.y || a.x - b.x),
            });
        }
        // Moves the widget to x, y (logical pixels from the monitor's top
        // left) on that monitor only, showing it there; its placement
        // becomes free (not following the wallpaper's busy areas).
        function place(name: string, monitor: string, x: int, y: int): string {
            if (!root.placeable(name)) return `error: no widget "${name}"`;
            const screen = Quickshell.screens.find(s => s.name === monitor);
            if (!screen) return `error: no monitor "${monitor}" (${Quickshell.screens.map(s => s.name).join(", ")})`;
            if (x < 0 || y < 0 || x >= screen.width || y >= screen.height)
                return `error: ${x}, ${y} is off ${monitor} (${screen.width}x${screen.height})`;
            if ((root.entry(name)?.placementStrategy ?? "free") !== "free")
                root.setEntry(name, { placementStrategy: "free" });
            root.setValues(name, monitor, { x: x, y: y, enable: true });
            return `ok: ${name} at ${x}, ${y} on ${monitor}`;
        }
        function hideOn(name: string, monitor: string): string {
            if (!root.placeable(name)) return `error: no widget "${name}"`;
            if (!Quickshell.screens.some(s => s.name === monitor)) return `error: no monitor "${monitor}"`;
            root.setValues(name, monitor, { enable: false });
            return `ok: ${name} hidden on ${monitor}`;
        }
        // In front of the other widgets on that monitor.
        function raise(name: string, monitor: string): string {
            if (!root.placeable(name)) return `error: no widget "${name}"`;
            let top = 0;
            for (const k in root.geometries)
                if (k.endsWith("@" + monitor)) top = Math.max(top, root.geometries[k].z ?? 0);
            root.setValues(name, monitor, { z: top + 1 });
            return `ok: ${name} raised on ${monitor}`;
        }
        // free (where it was put), leastBusy or mostBusy (the wallpaper's
        // calmest or busiest area, found by the shell).
        function placement(name: string, strategy: string): string {
            if (!root.placeable(name)) return `error: no widget "${name}"`;
            if (!["free", "leastBusy", "mostBusy"].includes(strategy)) return "error: placement is free, leastBusy or mostBusy";
            root.setEntry(name, { placementStrategy: strategy });
            return `ok: ${name} placement ${strategy}`;
        }
    }

    // `nixbook-shell ipc call images …`: the custom images (the first,
    // "customImage", and the ones added after it), for key bindings and the
    // desktop MCP server. An image is its number in `list` (1: the first) or
    // its name. Paths aren't checked here: the MCP server only passes files
    // from the folders the user shares with agents.
    readonly property var imageShapes: ["Circle", "Square", "Slanted", "Arch", "Arrow", "SemiCircle", "Oval", "Pill",
        "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny",
        "Cookie4Sided", "Cookie6Sided", "Cookie7Sided", "Cookie9Sided", "Cookie12Sided",
        "Ghostish", "Clover4Leaf", "Clover8Leaf", "Burst", "SoftBurst", "Flower",
        "Puffy", "PuffyDiamond", "PixelCircle", "Bun", "Heart"]
    // The settings `images set` takes: [min, max] for numbers, "bool", or a list.
    readonly property var imageSettings: ({
        zoom: [1, 4], offsetX: [-1, 1], offsetY: [-1, 1], rotation: [-360, 360],
        opacity: [0.1, 1], size: [80, 1000], mirror: "bool", grayscale: "bool",
    })
    function imageNames() {
        return ["customImage", ...root.instanceNames("customImage")];
    }
    function resolveImage(ref) {
        const names = root.imageNames();
        if (/^[0-9]+$/.test(ref)) return names[parseInt(ref) - 1] ?? null;
        return names.includes(ref) ? ref : null;
    }
    function screenNames() {
        return Quickshell.screens.map(s => s.name);
    }

    IpcHandler {
        target: "images"

        function list(): string {
            return JSON.stringify(root.imageNames().map((name, i) => {
                const e = root.entry(name) ?? {};
                return {
                    number: i + 1, name: name, path: e.path ?? "",
                    monitors: root.screenNames().filter(s => root.enabledOn(name, s)),
                    shape: e.shape, size: e.size, zoom: e.zoom, offsetX: e.offsetX, offsetY: e.offsetY,
                    rotation: e.rotation, opacity: e.opacity, mirror: e.mirror, grayscale: e.grayscale,
                };
            }));
        }
        // On `monitor` only ("": every monitor). The first image is used
        // while it shows nowhere and has no picture; else one is added.
        function add(path: string, monitor: string): string {
            if (monitor !== "" && !root.screenNames().includes(monitor))
                return `error: no monitor "${monitor}" (${root.screenNames().join(", ")})`;
            let name = "customImage";
            const first = root.entry(name);
            if (root.shownAnywhere(name) || (first?.path ?? "") !== "")
                name = root.addInstance("customImage", monitor);
            else
                root.setShownOn(name, monitor !== "" ? [monitor] : []);
            root.setEntry(name, { path: path, zoom: 1, offsetX: 0, offsetY: 0 });
            return `ok: image ${root.imageNames().indexOf(name) + 1} (${name})`;
        }
        // An added image is deleted; the first one is hidden everywhere.
        function remove(image: string): string {
            const name = root.resolveImage(image);
            if (!name) return `error: no image "${image}" (1 to ${root.imageNames().length})`;
            if (name === "customImage") {
                root.setShownOn(name, null);
                return "ok: image 1 hidden (the first image stays in the settings)";
            }
            root.removeInstance(name);
            return `ok: ${name} deleted`;
        }
        function set(image: string, key: string, value: string): string {
            const name = root.resolveImage(image);
            if (!name) return `error: no image "${image}" (1 to ${root.imageNames().length})`;
            let v;
            if (key === "shape") {
                v = root.imageShapes.find(s => s.toLowerCase() === value.toLowerCase());
                if (!v) return `error: no shape "${value}" (${root.imageShapes.join(", ")})`;
            } else if (key === "path") {
                v = value;
            } else if (root.imageSettings[key] === "bool") {
                if (value !== "true" && value !== "false") return `error: ${key} is true or false`;
                v = value === "true";
            } else if (root.imageSettings[key]) {
                const [min, max] = root.imageSettings[key];
                v = Number(value);
                if (value.trim() === "" || isNaN(v) || v < min || v > max) return `error: ${key} goes from ${min} to ${max}`;
            } else {
                return `error: no setting "${key}" (path, shape, ${Object.keys(root.imageSettings).join(", ")})`;
            }
            root.setEntry(name, { [key]: v });
            return `ok: ${name} ${key} = ${v}`;
        }
        function recenter(image: string): string {
            const name = root.resolveImage(image);
            if (!name) return `error: no image "${image}" (1 to ${root.imageNames().length})`;
            root.setEntry(name, { zoom: 1, offsetX: 0, offsetY: 0 });
            return `ok: ${name} recentered`;
        }
        // `names`: "all", "none", or monitors separated by commas.
        function monitors(image: string, names: string): string {
            const name = root.resolveImage(image);
            if (!name) return `error: no image "${image}" (1 to ${root.imageNames().length})`;
            if (names === "all") {
                root.setShownOn(name, []);
            } else if (names === "none") {
                root.setShownOn(name, null);
            } else {
                const list = names.split(",").map(n => n.trim()).filter(n => n !== "");
                const unknown = list.filter(n => !root.screenNames().includes(n));
                if (list.length === 0 || unknown.length > 0)
                    return `error: no monitor "${unknown[0] ?? names}" (all, none, or ${root.screenNames().join(", ")})`;
                root.setShownOn(name, list.length === root.screenNames().length ? [] : list);
            }
            return `ok: ${name} on ${root.screenNames().filter(s => root.enabledOn(name, s)).join(", ") || "no monitor"}`;
        }
    }

    function _setEnabled(name, on) {
        const w = Config.options?.background?.widgets;
        if (!w || !root.names.includes(name) || w[name] === undefined)
            return `error: no widget "${name}" (${root.names.filter(n => w?.[n] !== undefined).join(", ")})`;
        root.setShownOn(name, on ? [] : null);
        return `ok: ${name} ${on ? "shown" : "hidden"}`;
    }
}
