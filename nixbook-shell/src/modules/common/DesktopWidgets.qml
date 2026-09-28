pragma Singleton

import QtQuick
import Quickshell

/**
 * Per-monitor desktop widgets. `background.widgets.perScreen` maps
 * "<widget>@<output>" to overrides of that widget's own config on that
 * monitor: position (x/y/z), size (sizeMode, ringSize, height, fontSize…) and
 * `enable`. Anything not overridden falls back to the widget's shared entry
 * (`background.widgets.<widget>`), so a single-monitor setup is unchanged.
 * The old position-only `screenPositions` map is still read as a fallback.
 */
Singleton {
    id: root

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
        return Config.options?.background?.widgets?.[widget]?.[prop] ?? fallback;
    }
    // Store `values` ({prop: value}) for the widget on `screen` only (the
    // shared entry when no screen is known).
    function setValues(widget, screen, values) {
        const w = Config.options.background.widgets;
        if (!screen) {
            for (const prop in values) w[widget][prop] = values[prop];
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
        return (Config.options?.background?.widgets?.[widget]?.enable ?? false)
            && (list.length === 0 || list.includes(screen));
    }
}
