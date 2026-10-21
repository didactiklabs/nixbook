pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.modules.common as C

NestableObject {
    id: root

    required property var screen
    readonly property string monitorName: screen?.name ?? ""

    readonly property int shownCount: C.Config.options.bar.workspaces.shown

    readonly property int activeNumber: {
        const ws = WM.workspaces.find(w => w.output === root.monitorName && w.is_active)
        return ws?.idx ?? 1
    }

    readonly property int group: Math.floor((activeNumber - 1) / shownCount)

    property list<bool> occupied: []
    readonly property bool shouldShowAppIcons: Boolean(C.Config.options.bar?.workspaces?.showAppIcons || C.Config.options.bar?.workspaces?.indicatorStyle === "icon")
    // Filled by updateWorkspaceOccupied, reassigned only when what it shows
    // changes: niri republishes the window list on every frame of a layout
    // animation, and every workspace button binds to these.
    property list<var> biggestWindow: []
    onShouldShowAppIconsChanged: updateWorkspaceOccupied()

    function getWorkspaceId(group, index) {
        return group * root.shownCount + index + 1
    }
    function getWorkspaceIdAt(index) {
        return root.getWorkspaceId(root.group, index)
    }

    function _niriRealId(number) {
        const ws = WM.workspaces.find(w => w.output === root.monitorName && w.idx === number)
        return ws?.id ?? null
    }

    function biggestWindowForNumber(number) {
        const realId = root._niriRealId(number)
        if (realId === null) return null
        const winsInWs = WM.windowList.filter(w => w.workspaceId === realId)
        if (winsInWs.length === 0) return null
        const win = winsInWs.find(w => w.focused) ?? winsInWs[0]
        return { class: win.appId, title: win.title, id: win.id }
    }

    function updateWorkspaceOccupied() {
        const count = root.shownCount;
        let newOccupied = new Array(count);
        const winList = WM.windowList || [];
        for (let i = 0; i < count; i++) {
            const number = getWorkspaceId(root.group, i);
            const realId = root._niriRealId(number);
            newOccupied[i] = (realId !== null) && winList.some(w => w.workspaceId === realId);
        }
        if (newOccupied.length !== root.occupied.length || newOccupied.some((o, i) => o !== root.occupied[i]))
            root.occupied = newOccupied;
        const newBiggest = root.shouldShowAppIcons
            ? newOccupied.map((_, i) => root.biggestWindowForNumber(getWorkspaceId(root.group, i))) : [];
        const same = (a, b) => a === b || (a !== null && b !== null && a !== undefined && b !== undefined
            && a.id === b.id && a.class === b.class && a.title === b.title);
        if (newBiggest.length !== root.biggestWindow.length || newBiggest.some((b, i) => !same(b, root.biggestWindow[i])))
            root.biggestWindow = newBiggest;
    }

    Component.onCompleted: updateWorkspaceOccupied()

    Connections {
        target: WM
        function onWorkspacesChanged() {
            root.updateWorkspaceOccupied()
        }
        function onWindowListChanged() {
            root.updateWorkspaceOccupied()
        }
    }

    onGroupChanged: {
        updateWorkspaceOccupied()
    }
}
