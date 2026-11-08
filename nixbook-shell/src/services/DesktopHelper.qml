pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * `nixbook-desktop-mcp helper`, kept running: the shell's quick commands
 * (the privacy mask and the personal context of each message, cues, a
 * bubble's answer, the initiative's decisions on a thread of their own…)
 * answered in a millisecond instead of starting Python
 * each time (~150 ms of CPU each). `run(argv, input, done)`: done(code,
 * stdout) once answered; the commands the helper doesn't take (see
 * desktop-mcp.py's HELPER_COMMANDS), and any while it isn't up, run as a
 * process as before. It also serves the side panel's privacy hooks over
 * HTTP on 127.0.0.1 (`hookUrl`, `hookToken`: Ai.privacyHooks).
 */
Singleton {
    id: root

    property bool ready: false
    property string hookUrl: ""
    property string hookToken: ""
    property int _next: 1
    property var _waiting: ({}) // id -> done
    // As HELPER_COMMANDS: those it answers.
    readonly property var _commands: ({
        privacy: null, context: null, sent: null, pause: null, resume: null, status: null, notify: null,
        personal: ["context", "show", "forget"], habits: ["cue", "alias", "status"],
        memory: ["show", "forget", "fire"], initiative: ["show", "pending", "answer", "notices", "unmute", "consider"],
        routine: ["list", "undone", "on", "off", "remove"],
        // The launcher's find prefix (services/FindAnything.qml).
        find: null,
        // The trust ladder (Trust.qml): its list and the user's clicks.
        trust: ["list", "check", "set"]
    })
    // The trust ladder's gate (the /trust hook, Claude's tool calls): a step
    // waiting for the user's OK, one done and to be said, the offer to stop
    // asking, an OK that came too late (Trust.qml routes them to chats).
    signal approvalAsked(var approval)
    signal approvalExpired(string id)
    signal stepTold(var told)
    signal trustSuggested(var suggestion)
    // The user's Allow / No (their click only) on a step the gate waits on.
    function answerApproval(id, allow) {
        if (root.ready) helper.write(JSON.stringify({ approvalAnswer: String(id), allow: allow === true }) + "\n");
    }

    function takes(argv) {
        if (!(argv[0] in root._commands)) return false;
        const subs = root._commands[argv[0]];
        return subs === null || (argv.length > 1 && subs.includes(argv[1]));
    }

    function run(argv, input, done) {
        if (root.ready && root.takes(argv)) {
            const id = root._next++;
            if (done) root._waiting[id] = done;
            helper.write(JSON.stringify({ id: id, argv: argv, stdin: input ?? "" }) + "\n");
            return;
        }
        if (!done && !input) {
            Quickshell.execDetached(["nixbook-desktop-mcp", ...argv]);
            return;
        }
        oneOff.createObject(root, { argv: argv, input: input ?? "", done: done ?? null });
    }

    Process {
        id: helper
        command: ["nixbook-desktop-mcp", "helper"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (msg.approval !== undefined) {
                    root.approvalAsked(msg.approval);
                    return;
                }
                if (msg.approvalExpired !== undefined) {
                    root.approvalExpired(String(msg.approvalExpired));
                    return;
                }
                if (msg.told !== undefined) {
                    root.stepTold(msg.told);
                    return;
                }
                if (msg.trustSuggest !== undefined) {
                    root.trustSuggested(msg.trustSuggest);
                    return;
                }
                if (msg.hook !== undefined) {
                    root.hookUrl = msg.hook;
                    root.hookToken = msg.token ?? "";
                    root.ready = true;
                    return;
                }
                const done = root._waiting[msg.id];
                delete root._waiting[msg.id];
                if (done) done(msg.code ?? 1, msg.stdout ?? "");
            }
        }
        // Gone (an update, a crash): what waited is answered as failed, the
        // rest runs as processes until it is back.
        onExited: {
            root.ready = false;
            root.hookUrl = "";
            const waiting = root._waiting;
            root._waiting = {};
            for (const id in waiting) waiting[id](1, "");
            restart.start();
        }
    }
    Timer {
        id: restart
        interval: 2000
        onTriggered: helper.running = true
    }

    Component {
        id: oneOff
        Process {
            id: proc
            property var argv: []
            property string input: ""
            property var done: null
            command: ["nixbook-desktop-mcp", ...proc.argv]
            stdinEnabled: proc.input.length > 0
            running: true
            onStarted: if (proc.input.length > 0) {
                write(proc.input);
                stdinEnabled = false;
            }
            stdout: StdioCollector { id: out }
            onExited: code => {
                if (proc.done) proc.done(code, out.text);
                proc.destroy();
            }
        }
    }
}
