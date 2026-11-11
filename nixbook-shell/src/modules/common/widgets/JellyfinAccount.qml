import QtQuick
import QtQuick.Layouts
import qs
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// The Jellyfin account of this computer (services/Jellyfin.qml): its server,
// signing in as the user (or an admin's API key), the player (mpv through
// jellyfin-mpv-shim). Shown in Settings > Apps & accounts > Jellyfin and in
// Settings > Assistant.
// Jellyfin: its server is a setting (ai.jellyfin.url, locked
// when set in Nix). This computer signs in as the user (`jellyfin-mcp
// credentials login`, the password — an app password with 2FA —
// on stdin, never kept): its own token, in the keyring, no
// admin needed; the player of this computer (jellyfin-mpv-shim)
// is signed in with it, with a token of its own. An admin's
// API key instead (`credentials save`, for ai.jellyfin.user;
// or a key file set in Nix, ai.jellyfin.apiKeyFile).
ColumnLayout {
    id: jellyfin
    visible: Jellyfin.available
    spacing: 6
    readonly property string bin: Jellyfin.bin

    component SmallButton: RippleButtonWithIcon {
        buttonRadius: Appearance.rounding.small
    }
    readonly property string url: jellyfinUrl.value.trim().replace(/\/+$/, "")
    // {has_key, key_source: env|file|keyring|null, kind: token|apikey|null, signed_in_as}
    property var conn: ({})
    readonly property bool signedIn: jellyfin.conn.kind === "token"
    // The admin API key's fields: asked for, or that's what is set.
    property bool useKey: false
    readonly property bool keyMode: jellyfin.useKey || jellyfin.conn.kind === "apikey"
    // {signed_in, user, device, service}
    property var player: ({})
    property string status: ""
    property string playerStatus: ""
    property bool busy: false

    function run(args, secret) {
        if (jellyfin.busy || !jellyfin.bin) return
        jellyfin.busy = true
        jellyfinProc.secret = secret ?? ""
        jellyfinProc.args = args
        jellyfinProc.command = [jellyfin.bin, ...args]
        jellyfinProc.environment = Jellyfin.env
        jellyfinProc.stdinEnabled = ["save", "test", "login", "shim-login"].includes(args[0] === "credentials" ? args[1] : args[0])
        jellyfinProc.running = true
    }
    function refresh() {
        jellyfin.run(["credentials", "status"])
    }
    // The helper's path is read asynchronously (Jellyfin.bin).
    Component.onCompleted: refresh()
    onBinChanged: refresh()

    Process {
        id: jellyfinProc
        property string secret: ""
        property var args: []
        stdout: StdioCollector { id: jellyfinOut }
        onRunningChanged: {
            if (!jellyfinProc.running || !jellyfinProc.stdinEnabled) return
            jellyfinProc.write(jellyfinProc.secret + "\n")
            jellyfinProc.secret = ""
            jellyfinProc.stdinEnabled = false
        }
        onExited: code => {
            jellyfin.busy = false
            const what = jellyfinProc.args[0] === "credentials" ? jellyfinProc.args[1] : jellyfinProc.args[0]
            let result = null
            try {
                result = JSON.parse(jellyfinOut.text)
            } catch (e) {}
            const player = what.startsWith("shim")
            if (code !== 0 || !result) {
                const why = result?.error ?? Translation.tr("Couldn't reach the Jellyfin helper")
                if (player) jellyfin.playerStatus = why
                else jellyfin.status = why
                return
            }
            if (player) {
                jellyfin.player = result
                if (what === "shim-login") {
                    jellyfinPassword.text = ""
                    jellyfin.playerStatus = Translation.tr("Player connected as %1 (%2).").arg(result.user).arg(result.device)
                } else if (what === "shim-logout") {
                    jellyfin.playerStatus = Translation.tr("Player disconnected.")
                }
                if (what !== "shim-status") Qt.callLater(() => jellyfin.run(["shim-status"]))
                return
            }
            jellyfin.conn = result
            jellyfinKey.text = ""
            if (what === "login") {
                jellyfinSignPassword.text = ""
                jellyfin.useKey = false
                if (result.player?.error)
                    jellyfin.playerStatus = Translation.tr("The player couldn't sign in: %1").arg(result.player.error)
            }
            jellyfin.status = result.server
                ? Translation.tr("Connected to %1 as %2: %3 films, %4 series, %5 songs").arg(result.server)
                    .arg(result.user).arg(result.movies ?? 0).arg(result.series ?? 0).arg(result.songs ?? 0)
                : what === "forget" ? (result.signed_out ? Translation.tr("Signed out (its session ended on the server too).") : Translation.tr("Forgotten."))
                : ""
            if (what === "login" || what === "forget") Qt.callLater(() => jellyfin.run(["shim-status"]))
            // Its player next (and the bubble's instant "play …" sees the change).
            Jellyfin.refresh()
            if (what === "status") Qt.callLater(() => jellyfin.run(["shim-status"]))
        }
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Appearance.colors.colSubtext
        text: Translation.tr("Jellyfin: your films, series and music, played fullscreen in mpv on this computer (watching along in the Mesh, and DAI when it is on). Sign in with your own Jellyfin account, no admin needed: this computer and its player each get their own login, and your password isn't kept. With two-factor authentication (e.g. the JellyfinSecurity plugin), use an app password made for this.")
    }
    ConfigTextArea {
        id: jellyfinUrl
        configKey: "ai.jellyfin.url"
        Layout.fillWidth: true
        fieldWidth: 320
        buttonIcon: "dns"
        text: Translation.tr("Jellyfin server")
        placeholderText: Translation.tr("e.g. https://jellyfin.example.org")
        value: Config.options.ai.jellyfin.url ?? ""
        Connections {
            target: jellyfinUrl.textArea
            function onEditingFinished() {
                Config.options.ai.jellyfin.url = jellyfinUrl.value.trim().replace(/\/+$/, "")
            }
        }
    }
    // This computer's sign-in: the user's token (and the player's).
    StyledText {
        Layout.fillWidth: true
        visible: jellyfin.signedIn
        wrapMode: Text.WordWrap
        text: Translation.tr("Signed in as %1.").arg(jellyfin.conn.signed_in_as ?? "?")
    }
    RowLayout {
        Layout.fillWidth: true
        visible: !jellyfin.signedIn && !jellyfin.keyMode
        spacing: 6
        MaterialTextField {
            id: jellyfinSignUser
            Layout.fillWidth: true
            placeholderText: Translation.tr("Username")
            text: Config.options.ai.jellyfin.user ?? ""
        }
        MaterialTextField {
            id: jellyfinSignPassword
            Layout.fillWidth: true
            placeholderText: Translation.tr("Password or app password")
            echoMode: TextInput.Password
            onAccepted: jellyfinSignIn.clicked()
        }
    }
    Flow {
        Layout.fillWidth: true
        visible: !jellyfin.keyMode
        spacing: 6
        SmallButton {
            id: jellyfinSignIn
            visible: !jellyfin.signedIn
            enabled: !jellyfin.busy && jellyfin.url !== "" && jellyfinSignUser.text.trim() !== ""
                && jellyfinSignPassword.text !== ""
            materialIcon: "login"
            mainText: jellyfin.busy ? Translation.tr("Signing in…") : Translation.tr("Sign in")
            onClicked: {
                if (!jellyfinUrl.nixManaged) Config.options.ai.jellyfin.url = jellyfin.url
                jellyfin.run(["credentials", "login", jellyfin.url, jellyfinSignUser.text.trim(), "--player"],
                    jellyfinSignPassword.text)
            }
        }
        SmallButton {
            visible: jellyfin.signedIn
            enabled: !jellyfin.busy && jellyfin.url !== ""
            materialIcon: "network_check"
            mainText: Translation.tr("Test")
            onClicked: jellyfin.run(["credentials", "test", jellyfin.url], "")
        }
        SmallButton {
            visible: jellyfin.signedIn
            enabled: !jellyfin.busy
            materialIcon: "logout"
            mainText: Translation.tr("Sign out")
            onClicked: jellyfin.run(["credentials", "forget"])
        }
        SmallButton {
            visible: !jellyfin.signedIn
            enabled: !jellyfin.busy
            materialIcon: "key"
            mainText: Translation.tr("Use an admin API key instead")
            onClicked: jellyfin.useKey = true
        }
    }

    // Or an admin's API key (Dashboard > API Keys), for a user
    // picked by name.
    StyledText {
        Layout.fillWidth: true
        visible: jellyfin.keyMode
        wrapMode: Text.WordWrap
        color: Appearance.colors.colSubtext
        text: Translation.tr("An admin's API key (Jellyfin: Dashboard > API Keys) reaches every user's library: this computer then acts as the user named here.")
    }
    ConfigTextArea {
        id: jellyfinUser
        configKey: "ai.jellyfin.user"
        shown: jellyfin.keyMode
        Layout.fillWidth: true
        fieldWidth: 320
        buttonIcon: "person"
        text: Translation.tr("Jellyfin user")
        placeholderText: Translation.tr("empty: the first administrator")
        value: Config.options.ai.jellyfin.user ?? ""
        Connections {
            target: jellyfinUser.textArea
            function onEditingFinished() {
                Config.options.ai.jellyfin.user = jellyfinUser.value.trim()
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: jellyfin.conn.key_source === "file"
        wrapMode: Text.WordWrap
        color: Appearance.colors.colSubtext
        text: Translation.tr("API key: read from %1 (ai.jellyfin.apiKeyFile).").arg(Config.options.ai.jellyfin.apiKeyFile)
    }
    MaterialTextField {
        id: jellyfinKey
        Layout.fillWidth: true
        visible: jellyfin.keyMode && jellyfin.conn.key_source !== "file"
        placeholderText: jellyfin.conn.has_key
            ? Translation.tr("API key (saved: leave empty to keep it)")
            : Translation.tr("API key")
        echoMode: TextInput.Password
        onAccepted: jellyfinSave.clicked()
    }
    Flow {
        Layout.fillWidth: true
        visible: jellyfin.keyMode
        spacing: 6
        SmallButton {
            id: jellyfinSave
            enabled: !jellyfin.busy && jellyfin.url !== ""
                && (jellyfinKey.text !== "" || jellyfin.conn.has_key === true)
            materialIcon: "link"
            mainText: jellyfin.busy ? Translation.tr("Checking…") : Translation.tr("Save and check")
            onClicked: {
                // The fields save when they lose focus, which a click may not take.
                if (!jellyfinUrl.nixManaged) Config.options.ai.jellyfin.url = jellyfin.url
                if (!jellyfinUser.nixManaged) Config.options.ai.jellyfin.user = jellyfinUser.value.trim()
                jellyfin.run(["credentials", "save", jellyfin.url, jellyfinUser.value.trim()], jellyfinKey.text)
            }
        }
        SmallButton {
            enabled: !jellyfin.busy && jellyfin.url !== ""
                && (jellyfinKey.text !== "" || jellyfin.conn.has_key === true)
            materialIcon: "network_check"
            mainText: Translation.tr("Test")
            onClicked: jellyfin.run(["credentials", "test", jellyfin.url, jellyfinUser.value.trim()], jellyfinKey.text)
        }
        SmallButton {
            visible: jellyfin.conn.key_source === "keyring"
            enabled: !jellyfin.busy
            materialIcon: "key_off"
            mainText: Translation.tr("Forget the key")
            onClicked: jellyfin.run(["credentials", "forget"])
        }
        SmallButton {
            visible: jellyfin.useKey && jellyfin.conn.kind !== "apikey"
            enabled: !jellyfin.busy
            materialIcon: "login"
            mainText: Translation.tr("Sign in with my account instead")
            onClicked: jellyfin.useKey = false
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: jellyfin.status !== ""
        wrapMode: Text.WordWrap
        color: Appearance.colors.colSubtext
        text: jellyfin.status
    }

    // The player of this computer (jellyfin-mpv-shim).
    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 4
        wrapMode: Text.WordWrap
        color: Appearance.colors.colSubtext
        text: jellyfin.player.signed_in
            ? Translation.tr("Player (mpv on this computer): connected as %1, %2.").arg(jellyfin.player.user ?? "?")
                .arg(jellyfin.player.service === "active" ? Translation.tr("running") : Translation.tr("not running"))
            : Translation.tr("Connect the player (jellyfin-mpv-shim): sign in once with your Jellyfin username and password (an app password with two-factor authentication). The password isn't kept; the player keeps its own login, and saves progress and plays the next episode itself.")
    }
    RowLayout {
        Layout.fillWidth: true
        visible: !jellyfin.player.signed_in
        spacing: 6
        MaterialTextField {
            id: jellyfinLogin
            Layout.fillWidth: true
            placeholderText: Translation.tr("Username")
            text: Config.options.ai.jellyfin.user ?? ""
        }
        MaterialTextField {
            id: jellyfinPassword
            Layout.fillWidth: true
            placeholderText: Translation.tr("Password")
            echoMode: TextInput.Password
            onAccepted: jellyfinConnect.clicked()
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        SmallButton {
            id: jellyfinConnect
            visible: !jellyfin.player.signed_in
            enabled: !jellyfin.busy && jellyfin.url !== "" && jellyfinLogin.text.trim() !== ""
            materialIcon: "cast"
            mainText: jellyfin.busy ? Translation.tr("Connecting…") : Translation.tr("Connect the player")
            onClicked: jellyfin.run(["shim-login", jellyfin.url, jellyfinLogin.text.trim()], jellyfinPassword.text)
        }
        SmallButton {
            visible: jellyfin.player.signed_in === true
            enabled: !jellyfin.busy
            materialIcon: "cast_connected"
            mainText: Translation.tr("Disconnect the player")
            onClicked: jellyfin.run(["shim-logout"])
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: jellyfin.playerStatus !== ""
        wrapMode: Text.WordWrap
        color: Appearance.colors.colSubtext
        text: jellyfin.playerStatus
    }
}
