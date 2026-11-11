import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// YouTube Music in the background (services/YouTubeMusic.qml): signing in
// with the YouTube session of a browser (or of the YouTube Music app), what
// to do first when there is none, and Last.fm scrobbling (its desktop
// sign-in, or the YouTube Music app's own). In Settings > Services >
// YouTube Music and in the right sidebar's YouTube Music tab while signed out.
ColumnLayout {
    id: root
    spacing: 6
    // Shorter texts (the sidebar tab).
    property bool compact: false

    component SmallButton: RippleButtonWithIcon {
        buttonRadius: Appearance.rounding.small
    }

    property bool busy: false
    property string status: ""
    property bool statusError: false
    // The browsers with a YouTube login (and the YouTube Music app); "" = the
    // most recent.
    property var browsers: []
    property string browser: ""
    // {on, user, fromApp, appKey, newKey}
    property var lastfm: ({})
    // The Last.fm page is open: waiting for "I've allowed it".
    property bool lastfmPending: false
    property bool lastfmOwnKey: false

    function say(text, error) {
        root.status = text;
        root.statusError = !!error;
    }
    function refreshBrowsers() {
        YouTubeMusic.browsers((ok, answer) => root.browsers = ok ? (answer.browsers ?? []) : []);
    }
    function refreshLastfm() {
        YouTubeMusic.lastfm("status", "", (ok, answer) => {
            if (ok) root.lastfm = answer;
        });
    }
    Component.onCompleted: {
        YouTubeMusic.refresh();
        root.refreshBrowsers();
        root.refreshLastfm();
    }

    StyledText {
        Layout.fillWidth: true
        visible: !root.compact
        wrapMode: Text.WordWrap
        color: Appearance.colors.colSubtext
        text: Translation.tr("Your YouTube Music playlists in the right sidebar's YouTube Music tab, played in the background without a window (mpv, audio only), with shuffle, repeat and synced lyrics; listening along in the Mesh uses it too. It signs in with the YouTube session of your browser or of the YouTube Music app: the session stays in your keyring.")
    }

    // -- YouTube -------------------------------------------------------------
    StyledText {
        Layout.fillWidth: true
        visible: YouTubeMusic.signedIn
        wrapMode: Text.WordWrap
        text: YouTubeMusic.state?.browser
            ? Translation.tr("Signed in as %1 (the session of %2).").arg(YouTubeMusic.account).arg(YouTubeMusic.state.browser)
            : Translation.tr("Signed in as %1.").arg(YouTubeMusic.account)
    }
    // Not signed in: what to do first.
    StyledText {
        Layout.fillWidth: true
        visible: !YouTubeMusic.signedIn
        wrapMode: Text.WordWrap
        textFormat: Text.StyledText
        text: Translation.tr("<b>1.</b> Sign in to YouTube Music in your browser (Zen, Firefox, Chrome, Brave, Vivaldi, Edge…) or in the YouTube Music app.<br><b>2.</b> Then click <b>Use my browser's session</b>: this computer uses that session (it stays in your keyring).")
    }
    // Which one, when several have a login.
    Flow {
        Layout.fillWidth: true
        visible: !YouTubeMusic.signedIn && root.browsers.length > 1
        spacing: 6
        Repeater {
            model: ["", ...root.browsers]
            delegate: RippleButton {
                id: chip
                required property string modelData
                implicitHeight: 28
                implicitWidth: chipText.implicitWidth + 20
                buttonRadius: Appearance.rounding.full
                toggled: root.browser === chip.modelData
                onClicked: root.browser = chip.modelData
                contentItem: StyledText {
                    id: chipText
                    horizontalAlignment: Text.AlignHCenter
                    text: chip.modelData === "" ? Translation.tr("The most recent") : chip.modelData
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: chip.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                }
            }
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        SmallButton {
            visible: !YouTubeMusic.signedIn
            materialIcon: "open_in_new"
            mainText: Translation.tr("Open YouTube Music")
            onClicked: AppLaunch.openUrl("https://music.youtube.com")
        }
        SmallButton {
            enabled: !root.busy
            materialIcon: YouTubeMusic.signedIn ? "sync" : "login"
            mainText: root.busy ? Translation.tr("Reading the session…")
                : YouTubeMusic.signedIn ? Translation.tr("Read the session again") : Translation.tr("Use my browser's session")
            onClicked: {
                root.busy = true;
                root.say("", false);
                YouTubeMusic.login(root.browser, (ok, answer) => {
                    root.busy = false;
                    root.refreshBrowsers();
                    root.say(ok ? Translation.tr("Signed in as %1 (the session of %2).").arg(answer.account).arg(answer.browser)
                        : (answer?.error ?? ""), !ok);
                });
            }
        }
        SmallButton {
            visible: YouTubeMusic.signedIn
            enabled: !root.busy
            materialIcon: "logout"
            mainText: Translation.tr("Sign out")
            onClicked: YouTubeMusic.forget(() => root.say(Translation.tr("Signed out: the session is out of the keyring (your browser stays signed in)."), false))
        }
    }

    // -- Last.fm --------------------------------------------------------------
    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 6
        text: Translation.tr("Last.fm")
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnLayer1
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: root.lastfm.on ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
        text: root.lastfm.on ? Translation.tr("Scrobbling to Last.fm as %1.").arg(root.lastfm.user || "?")
            : root.lastfmPending ? Translation.tr("Allow nixbook on the Last.fm page that just opened in your browser, then click I've allowed it.")
            : Translation.tr("Songs played here can be scrobbled to your Last.fm profile: sign in once.")
    }
    // Your own API key: when the YouTube Music app has none to lend.
    ColumnLayout {
        Layout.fillWidth: true
        visible: !root.lastfm.on && !root.lastfmPending && (root.lastfmOwnKey || root.lastfm.appKey === false)
        spacing: 4
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Last.fm needs an API key for this computer: create one (free, at once) on its API account page, then paste the key and the secret here.")
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            MaterialTextField {
                id: apiKey
                Layout.fillWidth: true
                placeholderText: Translation.tr("API key")
            }
            MaterialTextField {
                id: apiSecret
                Layout.fillWidth: true
                placeholderText: Translation.tr("Shared secret")
                echoMode: TextInput.Password
            }
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        SmallButton {
            visible: !root.lastfm.on && !root.lastfmPending
            enabled: !root.busy && (root.lastfm.appKey === true && !root.lastfmOwnKey
                || /^[0-9a-f]{32}$/.test(apiKey.text.trim()) && /^[0-9a-f]{32}$/.test(apiSecret.text.trim()))
            materialIcon: "login"
            mainText: Translation.tr("Sign in to Last.fm")
            onClicked: {
                root.busy = true;
                const own = apiKey.text.trim() !== "" ? JSON.stringify({ apiKey: apiKey.text.trim(), secret: apiSecret.text.trim() }) : "";
                YouTubeMusic.lastfm("start", own, (ok, answer) => {
                    root.busy = false;
                    root.lastfmPending = ok;
                    root.say(ok ? "" : (answer?.error ?? ""), !ok);
                });
            }
        }
        SmallButton {
            visible: root.lastfmPending
            enabled: !root.busy
            materialIcon: "check"
            mainText: Translation.tr("I've allowed it")
            onClicked: {
                root.busy = true;
                YouTubeMusic.lastfm("finish", "", (ok, answer) => {
                    root.busy = false;
                    if (ok) {
                        root.lastfmPending = false;
                        apiKey.text = "";
                        apiSecret.text = "";
                    }
                    root.say(ok ? Translation.tr("Scrobbling to Last.fm as %1.").arg(answer.user || "?") : (answer?.error ?? ""), !ok);
                    root.refreshLastfm();
                });
            }
        }
        SmallButton {
            visible: root.lastfmPending
            materialIcon: "close"
            mainText: Translation.tr("Cancel")
            onClicked: root.lastfmPending = false
        }
        SmallButton {
            visible: !root.lastfm.on && !root.lastfmPending && root.lastfm.fromApp === true
            enabled: !root.busy
            materialIcon: "sync_alt"
            mainText: Translation.tr("Use the YouTube Music app's sign-in")
            onClicked: YouTubeMusic.lastfm("import", "", (ok, answer) => {
                root.say(ok ? Translation.tr("Scrobbling to Last.fm as %1.").arg(answer.user || "?") : (answer?.error ?? ""), !ok);
                root.refreshLastfm();
            })
        }
        SmallButton {
            visible: !root.lastfm.on && !root.lastfmPending && root.lastfm.appKey === true
            materialIcon: "key"
            mainText: root.lastfmOwnKey ? Translation.tr("Use the app's API key") : Translation.tr("Use my own API key")
            onClicked: root.lastfmOwnKey = !root.lastfmOwnKey
        }
        SmallButton {
            visible: !root.lastfm.on && (root.lastfmOwnKey || root.lastfm.appKey === false)
            materialIcon: "open_in_new"
            mainText: Translation.tr("Create an API key")
            onClicked: AppLaunch.openUrl(root.lastfm.newKey || "https://www.last.fm/api/account/create")
        }
        SmallButton {
            visible: root.lastfm.on === true
            materialIcon: "logout"
            mainText: Translation.tr("Sign out of Last.fm")
            onClicked: YouTubeMusic.lastfm("forget", "", () => root.refreshLastfm())
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.status !== ""
        wrapMode: Text.WordWrap
        color: root.statusError ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
        text: root.status
    }
}
