pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

/**
 * The login screen's state and its greetd conversation (greeter.qml,
 * `nixbook-shell greeter`, run by greetd through nixbook-shell.greeter).
 *
 * $NB_GREETER_INFO (written by the greeter's start script, greeter.nix):
 *   { users: [{ name, realName, avatar }], sessions: [{ name, exec,
 *     desktopNames }], defaultUser, cache }
 * `cache` is a JSON file the greeter may write: the last user and session.
 *
 * Login: greetd asks PAM's questions (authMessage). The password answers the
 * secret prompt; info messages (pam_u2f's "touch your key", fingerprint) are
 * shown as a cue; a failure (authFailure) clears the field and shakes it.
 * Success launches the session (its Exec, with XDG_SESSION_* set).
 */
Scope {
    id: root

    FileView {
        id: infoFile
        path: Quickshell.env("NB_GREETER_INFO") ?? ""
        blockLoading: true
    }
    readonly property var info: {
        try {
            return JSON.parse(infoFile.text());
        } catch (e) {
            return {};
        }
    }
    readonly property var users: root.info.users ?? []
    readonly property var sessions: root.info.sessions ?? []

    FileView {
        id: cacheFile
        path: root.info.cache ?? ""
        blockLoading: true
        printErrors: false
    }
    readonly property var cache: {
        try {
            return JSON.parse(cacheFile.text() || "{}");
        } catch (e) {
            return {};
        }
    }

    property int userIndex: Math.max(0, root.users.findIndex(u => u.name === (root.cache.user ?? root.info.defaultUser)))
    property int sessionIndex: Math.max(0, root.sessions.findIndex(s => s.name === root.cache.session))
    readonly property var user: root.users[root.userIndex] ?? null
    readonly property var session: root.sessions[root.sessionIndex] ?? null

    property string currentText: ""
    property bool busy: false
    property bool failed: false
    // Latest info message from PAM (security key, fingerprint…).
    property string message: ""
    readonly property bool waitingForKey: /touch|security key|presence|tap your|insert your/i.test(root.message)
    // A password was sent in this conversation (the next secret prompt means
    // it was wrong or PAM asks again: wait for the user).
    property bool answered: false

    signal failure()

    function cycleUser(step) {
        if (root.users.length === 0 || root.busy)
            return;
        root.userIndex = (root.userIndex + step + root.users.length) % root.users.length;
        root.reset();
    }
    function cycleSession(step) {
        if (root.sessions.length === 0)
            return;
        root.sessionIndex = (root.sessionIndex + step + root.sessions.length) % root.sessions.length;
    }

    function reset() {
        if (Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        root.busy = false;
        root.answered = false;
        root.message = "";
    }

    // Enter / the arrow button.
    function login() {
        if (!root.user)
            return;
        root.failed = false;
        if (root.pendingPrompt) {
            root.answerPrompt();
            return;
        }
        if (root.busy)
            return;
        root.message = "";
        if (Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        root.busy = true;
        root.answered = false;
        Greetd.createSession(root.user.name);
    }

    // A further prompt waiting for the user's text (an OTP, a question…):
    // the field is cleared and shows it; `promptEcho` means not secret.
    property bool pendingPrompt: false
    property bool promptEcho: false
    function answerPrompt() {
        root.pendingPrompt = false;
        root.answered = true;
        root.busy = true;
        Greetd.respond(root.currentText);
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                // The password (or whatever PAM asks) is what was typed; a
                // second prompt in the same conversation waits for new text.
                if (!root.answered && (root.currentText.length > 0 || !echoResponse)) {
                    root.answerPrompt();
                } else {
                    root.pendingPrompt = true;
                    root.promptEcho = echoResponse;
                    root.busy = false;
                    root.currentText = "";
                    root.message = message || "";
                }
            } else if (message) {
                root.message = message;
            }
        }
        function onAuthFailure(message) {
            root.busy = false;
            root.answered = false;
            root.pendingPrompt = false;
            root.message = "";
            root.currentText = "";
            root.failed = true;
            root.failure();
        }
        function onReadyToLaunch() {
            root.remember();
            const s = root.session;
            const command = (s?.exec ?? "").replace(/%[a-zA-Z]/g, "").trim().split(/\s+/).filter(a => a.length > 0);
            const env = [
                "XDG_SESSION_TYPE=wayland",
                `XDG_SESSION_DESKTOP=${s?.name ?? ""}`,
                `XDG_CURRENT_DESKTOP=${s?.desktopNames || s?.name || ""}`
            ];
            Greetd.launch(command.length > 0 ? command : ["niri-session"], env, true);
        }
        function onError(error) {
            console.warn("[Greeter] greetd:", error);
            root.busy = false;
            root.answered = false;
            root.message = error;
        }
    }

    function remember() {
        if (!root.info.cache)
            return;
        cacheFile.setText(JSON.stringify({ user: root.user?.name ?? "", session: root.session?.name ?? "" }));
    }

    // Power buttons (logind lets the greeter's own seat session do these).
    // `powerAction` ("poweroff" / "reboot") while the machine goes down, for
    // the screen to say so; cleared if systemd refuses.
    property string powerAction: ""
    Process {
        id: powerProc
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("[Greeter]", root.powerAction, "refused, exit code", exitCode);
                root.powerAction = "";
            }
        }
    }
    function power(action) {
        if (root.powerAction !== "")
            return;
        root.powerAction = action;
        powerProc.exec({ command: ["systemctl", action] });
    }
    function poweroff() {
        root.power("poweroff");
    }
    function reboot() {
        root.power("reboot");
    }
    function suspend() {
        Quickshell.execDetached(["systemctl", "suspend"]);
    }
}
