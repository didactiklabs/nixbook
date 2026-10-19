pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.tasks
import QtQuick
import QtQuick.Layouts

// The Google Keep sync of the notes (services/KeepSync.qml), in the Notes
// app: the account, the sync on demand, and what the last sync did.
//
// Google has no public Keep API, so the sync goes through an unofficial
// client (gkeepapi): it needs the account's email and its master token,
// which are kept in the keyring (never in the notes nor in the settings).
// The master token is the one gpsoauth's alternative flow explains.
ColumnLayout {
    id: root

    spacing: 10

    // The app asks for the sync: it saves what is being typed first.
    signal syncRequested()

    // "14:32" today, "Oct 3", "Oct 3, 2025".
    function when(ms) {
        if (!ms) return Translation.tr("never")
        const d = new Date(ms)
        const now = new Date()
        const fmt = Config.options?.time?.format ?? "hh:mm"
        if (d.getFullYear() === now.getFullYear()) return Qt.locale().toString(d, "MMM d, " + fmt)
        return Qt.locale().toString(d, "MMM d, yyyy")
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: KeepSync.configured
            ? Translation.tr("The notes are synced with Google Keep: what changes here goes there, and what changes there comes back. Deleted notes stay where they were deleted.")
            : Translation.tr("Google Keep has no public API, so the sync goes through an unofficial client: it needs your account's email and its master token (gpsoauth's alternative flow). They are kept in the keyring, never in the notes.")
    }

    // Not signed in yet.
    ColumnLayout {
        Layout.fillWidth: true
        visible: !KeepSync.configured
        spacing: 8

        MaterialTextField {
            id: emailField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Google account (you@example.com)")
        }
        MaterialTextField {
            id: tokenField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Master token")
            echoMode: TextInput.Password
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            PanelButton {
                filled: true
                text: Translation.tr("Connect")
                onClicked: {
                    KeepSync.login(emailField.text, tokenField.text, ok => {
                        if (ok) tokenField.text = ""
                    })
                }
            }
            PanelButton {
                icon: "help"
                text: Translation.tr("How to get a master token")
                onClicked: AppLaunch.openUrl("https://github.com/simon-weber/gpsoauth#alternative-flow")
            }
        }
    }

    // Signed in.
    ColumnLayout {
        Layout.fillWidth: true
        visible: KeepSync.configured
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            text: KeepSync.email
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            Layout.fillWidth: true
            text: KeepSync.lastSync
                ? Translation.tr("Last sync: %1").arg(root.when(KeepSync.lastSync))
                : Translation.tr("Not synced yet")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.fillWidth: true
            visible: root._summary() !== ""
            text: root._summary()
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            PanelButton {
                filled: true
                icon: "sync"
                text: KeepSync.syncing ? Translation.tr("Syncing…") : Translation.tr("Sync now")
                enabled: !KeepSync.syncing
                onClicked: root.syncRequested()
            }
            PanelButton {
                icon: "logout"
                text: Translation.tr("Disconnect")
                onClicked: KeepSync.logout()
            }
        }
    }

    // What went wrong.
    StyledText {
        Layout.fillWidth: true
        visible: KeepSync.lastError !== ""
        text: KeepSync.lastError
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colError
    }

    // What the last sync did, in a sentence.
    function _summary() {
        const s = KeepSync.stats
        if (!s) return ""
        const parts = []
        if (s.created) parts.push(Translation.tr("%1 new notes sent").arg(s.created))
        if (s.imported) parts.push(Translation.tr("%1 notes from Keep").arg(s.imported))
        if (s.pushed) parts.push(Translation.tr("%1 notes updated").arg(s.pushed))
        if (s.pulled) parts.push(Translation.tr("%1 notes updated from Keep").arg(s.pulled))
        if (s.conflicts) parts.push(Translation.tr("%1 conflicts (the newest won)").arg(s.conflicts))
        return parts.join(" · ")
    }
}
