pragma Singleton
import Quickshell
import "clipboard_kinds.js" as Kinds

/**
 * What a copied text is (clipboard_kinds.js, plain code, a few ms): the
 * smart clipboard's classifier (services/SmartClipboard.qml).
 */
Singleton {
    readonly property var kinds: Kinds.KINDS
    function classify(text, opts) {
        return Kinds.classify(text, opts)
    }
}
