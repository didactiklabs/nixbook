pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.tasks
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

// The accounts (services/Accounts.qml): each with what it syncs and its
// last failure, sign in again, remove (after a confirmation); then "Add an
// account": Google (its one-time OAuth client setup first) or a
// CalDAV/CardDAV server (iCloud, Fastmail, Nextcloud, another: a user name
// and an app password). Shown by the accounts window, and by the apps while
// no account is added (Contacts).
Item {
    id: root

    // The account asked to be removed, waiting for the confirmation.
    property string removing: ""
    // Google's setup steps shown (no client yet, or asked for).
    property bool googleSteps: false
    // The CalDAV/CardDAV form: its server kind ("" closed).
    property string davPreset: ""
    readonly property var davInfo: Accounts.davPresets[root.davPreset] ?? ({})

    // The form, for that account signed out (its server, its user).
    function signInAgain(account) {
        if (account.provider === "google") {
            Accounts.addGoogle()
            return
        }
        root.davPreset = account.preset || "custom"
        davUrl.text = account.preset === "icloud" || account.preset === "fastmail" ? "" : (account.url ?? "")
        davUser.text = account.username ?? ""
        davName.text = account.name ?? ""
        davPassword.text = ""
        davPassword.forceActiveFocus()
    }
    function describe(account) {
        if (account.provider === "local") return Translation.tr("Kept on this computer only, not synced")
        const kind = account.provider === "google" ? "Google" : (Accounts.davPresets[account.preset]?.name ?? "CalDAV/CardDAV")
        const has = account.contacts && account.tasks ? Translation.tr("contacts and tasks")
            : account.contacts ? Translation.tr("contacts") : account.tasks ? Translation.tr("tasks") : ""
        return has ? `${kind} · ${has}` : kind
    }

    Flickable {
        anchors.fill: parent
        contentHeight: column.implicitHeight + 60
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.vertical: StyledScrollBar {}

        ColumnLayout {
            id: column
            width: Math.min(parent.width - 40, 640)
            x: (parent.width - width) / 2
            y: 30
            spacing: 14

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                text: "manage_accounts"
                iconSize: 64
                color: Appearance.colors.colPrimary
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Accounts")
                font.pixelSize: Appearance.font.pixelSize.hugeass
                color: Appearance.colors.colOnLayer0
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                text: Accounts.syncing
                    ? Translation.tr("Your contacts, tasks and calendars from every account, together in the shell.")
                    : Translation.tr("Your contacts, tasks and calendars are kept on this computer. Add an account to sync them with Google, iCloud, Fastmail or Nextcloud.")
            }

            // The accounts
            Repeater {
                model: Accounts.accounts
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    readonly property string problem: !modelData.connected ? Translation.tr("Signed out: sign in again")
                        : (modelData.contactsError || modelData.tasksError || "")
                    Layout.fillWidth: true
                    implicitHeight: cardColumn.implicitHeight + 24
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer1Base

                    ColumnLayout {
                        id: cardColumn
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 16; rightMargin: 10 }
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Rectangle {
                                implicitWidth: 40
                                implicitHeight: 40
                                radius: 20
                                color: Appearance.colors.colSecondaryContainer
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: card.modelData.provider === "local"
                                    text: "computer"
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                                StyledText {
                                    anchors.centerIn: parent
                                    visible: card.modelData.provider !== "local"
                                    text: card.modelData.provider === "google" ? "G" : (Accounts.davPresets[card.modelData.preset]?.name ?? card.modelData.name)[0]?.toUpperCase() ?? "?"
                                    font.pixelSize: Appearance.font.pixelSize.larger
                                    font.weight: Font.Bold
                                    color: Appearance.colors.colOnSecondaryContainer
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: card.modelData.name
                                    elide: Text.ElideRight
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: card.problem || root.describe(card.modelData)
                                    wrapMode: Text.Wrap
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: card.problem ? Appearance.colors.colError : Appearance.colors.colSubtext
                                }
                            }
                            PanelButton {
                                visible: !card.modelData.connected
                                compact: true
                                filled: true
                                icon: "login"
                                text: Translation.tr("Sign in")
                                onClicked: root.signInAgain(card.modelData)
                            }
                            RoundButton {
                                visible: card.modelData.provider !== "local"
                                icon: "delete"
                                tip: Translation.tr("Remove this account")
                                onClicked: root.removing = card.modelData.id
                            }
                        }
                        // Remove?
                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.removing === card.modelData.id
                            spacing: 8
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Remove %1? Its contacts and tasks leave the shell (they stay in the account).").arg(card.modelData.name)
                                wrapMode: Text.Wrap
                                color: Appearance.colors.colOnLayer1
                            }
                            PanelButton {
                                compact: true
                                text: Translation.tr("Cancel")
                                onClicked: root.removing = ""
                            }
                            PanelButton {
                                compact: true
                                filled: true
                                icon: "delete"
                                text: Translation.tr("Remove")
                                onClicked: {
                                    root.removing = ""
                                    Accounts.remove(card.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            // Add an account
            StyledText {
                Layout.topMargin: 10
                text: Translation.tr("Add an account")
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer0
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: addColumn.implicitHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1Base

                ColumnLayout {
                    id: addColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; leftMargin: 16 }
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: "Google"
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                text: Accounts.googleConfigured
                                    ? Translation.tr("Contacts and Google Tasks. The browser opens Google's sign-in.")
                                    : Translation.tr("Contacts and Google Tasks, through your own Google Cloud app: make it once (about 5 minutes).")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                        PanelButton {
                            filled: true
                            icon: Accounts.connecting ? "hourglass_top" : "add"
                            text: Accounts.connecting ? Translation.tr("Waiting for the browser…")
                                : Accounts.googleConfigured ? Translation.tr("Add") : Translation.tr("Set up")
                            onClicked: {
                                if (Accounts.googleConfigured) Accounts.addGoogle()
                                else root.googleSteps = !root.googleSteps
                            }
                        }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        visible: Accounts.connecting
                        spacing: 10
                        PanelButton {
                            compact: true
                            visible: Accounts.authUrl !== ""
                            icon: "content_copy"
                            text: Translation.tr("Copy the sign-in link")
                            onClicked: Quickshell.clipboardText = Accounts.authUrl
                        }
                        PanelButton {
                            compact: true
                            icon: "close"
                            text: Translation.tr("Cancel")
                            onClicked: Accounts.cancelAdd()
                        }
                    }
                    GoogleSetup {
                        Layout.fillWidth: true
                        visible: !Accounts.googleConfigured && root.googleSteps
                    }
                    StyledText {
                        visible: Accounts.googleConfigured && !Accounts.connecting
                        text: Translation.tr("Use another Google Cloud app")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.underline: true
                        color: Appearance.colors.colSubtext
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Accounts.googleConfigured = false
                                root.googleSteps = true
                            }
                        }
                    }
                }
            }

            // A CalDAV/CardDAV server
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: davColumn.implicitHeight + 28
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1Base

                ColumnLayout {
                    id: davColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; leftMargin: 16 }
                    spacing: 10

                    StyledText {
                        text: Translation.tr("iCloud, Fastmail, Nextcloud, another server")
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("Contacts (CardDAV) and the task lists of your calendars (CalDAV), with your user name and an app password.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: ["icloud", "fastmail", "nextcloud", "custom"]
                            delegate: PanelButton {
                                required property string modelData
                                compact: true
                                toggled: root.davPreset === modelData
                                text: Accounts.davPresets[modelData]?.name ?? modelData
                                onClicked: {
                                    root.davPreset = root.davPreset === modelData ? "" : modelData
                                    davPassword.text = ""
                                }
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.davPreset !== ""
                        spacing: 8
                        MaterialTextField {
                            id: davUrl
                            Layout.fillWidth: true
                            visible: !!root.davInfo.needsUrl
                            placeholderText: root.davPreset === "nextcloud" ? Translation.tr("Your Nextcloud's address (cloud.example.org)")
                                : Translation.tr("The server's address (https://dav.example.org)")
                            inputMethodHints: Qt.ImhUrlCharactersOnly
                        }
                        MaterialTextField {
                            id: davUser
                            Layout.fillWidth: true
                            placeholderText: root.davPreset === "icloud" ? Translation.tr("Apple ID (email)") : Translation.tr("User name or email")
                            inputMethodHints: Qt.ImhNoAutoUppercase
                        }
                        MaterialTextField {
                            id: davPassword
                            Layout.fillWidth: true
                            placeholderText: root.davInfo.passwordHelp ? Translation.tr("App password") : Translation.tr("Password (or app password)")
                            echoMode: TextInput.Password
                            onAccepted: addDavButton.clicked()
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: !!root.davInfo.passwordHelp
                            wrapMode: Text.Wrap
                            text: Translation.tr("%1 needs an app password, not your account's: make one in its settings.").arg(root.davInfo.name ?? "")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                        MaterialTextField {
                            id: davName
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Name for this account (optional)")
                        }
                        RowLayout {
                            spacing: 10
                            PanelButton {
                                visible: !!root.davInfo.passwordHelp
                                compact: true
                                icon: "open_in_new"
                                text: Translation.tr("Make an app password")
                                onClicked: Qt.openUrlExternally(root.davInfo.passwordHelp)
                            }
                            PanelButton {
                                id: addDavButton
                                filled: true
                                icon: Accounts.addingDav ? "hourglass_top" : "add"
                                text: Accounts.addingDav ? Translation.tr("Checking…") : Translation.tr("Add")
                                onClicked: {
                                    if (Accounts.addingDav || !davUser.text.trim() || !davPassword.text) return
                                    Accounts.addDav(root.davPreset, davUrl.text.trim(), davUser.text.trim(), davPassword.text, davName.text.trim(), ok => {
                                        davPassword.text = ""
                                        if (ok) root.davPreset = ""
                                    })
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: Accounts.lastError !== ""
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Accounts.lastError
                color: Appearance.colors.colError
            }
        }
    }

    // A round icon button with its tooltip.
    component RoundButton: Rectangle {
        id: button
        property string icon
        property string tip
        signal clicked()
        implicitWidth: 40
        implicitHeight: 40
        radius: 20
        color: buttonMouse.containsMouse ? Appearance.colors.colLayer1Hover : "transparent"
        MaterialSymbol {
            anchors.centerIn: parent
            text: button.icon
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnLayer1
        }
        MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
        PopupToolTip {
            text: button.tip
            extraVisibleCondition: buttonMouse.containsMouse
        }
    }
}
