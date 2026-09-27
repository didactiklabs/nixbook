pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Dot-notation paths of every config.json leaf pinned by Home Manager
    // (customHomeManagerModules.nixbookShellConfig, minus its liveKeys). Written at
    // activation to ~/.config/nixbook-shell/nix-managed.json.
    property var pinned: []

    function isPinned(key) {
        if (!key) return false
        const paths = root.pinned
        for (let i = 0; i < paths.length; i++) {
            const p = paths[i]
            // Exact leaf match, or prefix match: pinning a whole object
            // (e.g. "ai") locks every setting underneath it too.
            if (p === key || p.startsWith(key + ".")) return true
        }
        return false
    }

    // ------------------------------------------------------- enforcement
    // The pinned *values* (nix-pinned-values.json, same keys as the manifest).
    // Whenever the config changes — Settings menu, QuickConfig cards, IPC,
    // scripts, a file reload — any pinned leaf that drifted is put back, so a
    // setting set in Nix can't be changed live by any path (the menu controls
    // are also disabled, see Config*.qml `Binding on enabled`).
    property var pinnedValues: ({})

    function leafEntries(obj, prefix, out) {
        for (const k in obj) {
            const v = obj[k];
            const path = prefix ? `${prefix}.${k}` : k;
            if (v !== null && typeof v === "object" && !Array.isArray(v) && Object.keys(v).length > 0)
                root.leafEntries(v, path, out);
            else
                out.push([path, v]);
        }
        return out;
    }

    function readPath(path) {
        let o = Config.options;
        for (const k of path.split(".")) {
            if (o === undefined || o === null) return undefined;
            o = o[k];
        }
        return o;
    }

    function writePath(path, value) {
        const keys = path.split(".");
        let o = Config.options;
        for (let i = 0; i < keys.length - 1; i++) {
            if (o[keys[i]] === undefined || o[keys[i]] === null) return; // unknown to this shell version
            o = o[keys[i]];
        }
        o[keys[keys.length - 1]] = value;
    }

    function same(a, b) {
        return JSON.stringify(a) === JSON.stringify(b);
    }

    function enforce() {
        if (!Config.ready) return;
        for (const [path, value] of root.leafEntries(root.pinnedValues, "", [])) {
            const cur = root.readPath(path);
            // QML list properties compare as arrays after a copy
            const curPlain = (cur !== null && typeof cur === "object") ? JSON.parse(JSON.stringify(cur)) : cur;
            if (!root.same(curPlain, value)) {
                console.log(`[NixManaged] ${path} is set in Nix; restoring it`);
                root.writePath(path, value);
            }
        }
    }
    function scheduleEnforce() {
        enforceTimer.restart();
    }
    Timer {
        id: enforceTimer
        interval: 30
        onTriggered: root.enforce()
    }
    Connections {
        target: Config
        function onReadyChanged() { root.scheduleEnforce() }
    }

    // Home Manager swaps these files' symlinks on every switch, which a file
    // watch does not survive; the nixbookShellConfig activation calls
    // `nixbook-shell ipc call nixManaged reload` afterwards so locks added or
    // removed in Nix apply to the running shell without a restart.
    function reload() {
        managedFileView.reload();
        pinnedValuesView.reload();
        Config.reloadFile();
    }
    IpcHandler {
        target: "nixManaged"
        function reload(): void {
            root.reload();
        }
    }

    FileView {
        id: pinnedValuesView
        path: Directories.shellConfig + "/nix-pinned-values.json"
        watchChanges: true
        onFileChanged: pinnedValuesView.reload()
        onLoaded: {
            try {
                root.pinnedValues = JSON.parse(pinnedValuesView.text()) ?? {};
            } catch (e) {
                root.pinnedValues = {};
            }
            root.scheduleEnforce();
        }
        onLoadFailed: error => root.pinnedValues = {}
    }

    FileView {
        id: managedFileView
        path: Directories.shellConfig + "/nix-managed.json"
        watchChanges: true
        onFileChanged: managedFileView.reload()
        onLoaded: root.pinned = managedAdapter.paths
        // Not generated (nixbookShellConfig disabled / first run): nothing pinned.
        onLoadFailed: error => root.pinned = []

        JsonAdapter {
            id: managedAdapter
            // Key must match the manifest's JSON key ("paths"), see
            // nixbookShellConfig.nix nixManagedFile — JsonAdapter maps by name.
            property list<string> paths: []
        }
    }
}
