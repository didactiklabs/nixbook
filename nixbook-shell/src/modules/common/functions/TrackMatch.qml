pragma Singleton
import Quickshell
import "track_match.js" as Match

/**
 * Listening along, in plain code (track_match.js): is the listener's player
 * on the host's song, and what to do about it (services/MeshListen.qml).
 */
Singleton {
    function sameSong(a, b) {
        return Match.sameSong(a, b)
    }
    function fresh() {
        return Match.fresh()
    }
    function followStep(f, x) {
        return Match.followStep(f, x)
    }
    function playStep(f, x) {
        return Match.playStep(f, x)
    }
}
