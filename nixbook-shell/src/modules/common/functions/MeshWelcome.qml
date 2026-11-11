pragma Singleton
import Quickshell
import "mesh_welcome.js" as Welcome

/**
 * The mesh's welcome back, in plain code (mesh_welcome.js): which nudges
 * wait for it and how they are grouped (services/Mesh.qml).
 */
Singleton {
    readonly property int shown: Welcome.SHOWN
    function waits(m, x) {
        return Welcome.waits(m, x)
    }
    function groups(messages, x) {
        return Welcome.groups(messages, x)
    }
    function heldIds(messages) {
        return Welcome.heldIds(messages)
    }
}
