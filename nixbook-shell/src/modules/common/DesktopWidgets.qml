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
    // Adds an instance of `base` (shown on every monitor), a little offset
    // from the previous one; returns its name.
    function addInstance(base) {
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
        return `${base}:${id}`;
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
    readonly property var names: ["sticker", "calendar", "nextEvent", "musicRecognition", "weather", "clock", "notes", "media", "images",
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
    }

    function _setEnabled(name, on) {
        const w = Config.options?.background?.widgets;
        if (!w || !root.names.includes(name) || w[name] === undefined)
            return `error: no widget "${name}" (${root.names.filter(n => w?.[n] !== undefined).join(", ")})`;
        w[name].enable = on;
        const all = Object.assign({}, w.perScreen ?? {});
        let changed = false;
        for (const k in all) {
            if (k.startsWith(name + "@") && all[k].enable !== undefined) {
                all[k] = Object.assign({}, all[k]);
                delete all[k].enable;
                changed = true;
            }
        }
        if (changed)
            w.perScreen = all;
        return `ok: ${name} ${on ? "shown" : "hidden"}`;
    }
}
