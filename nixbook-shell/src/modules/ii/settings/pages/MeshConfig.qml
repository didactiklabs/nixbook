import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

// Settings > Mesh: talking with a few people's desktops (services/Mesh.qml;
// moved from the General page).
ContentPage {
    id: page
    forceWidth: true

    component SmallButton: RippleButtonWithIcon {
        buttonRadius: Appearance.rounding.small
    }

    function goTo(term) {
        const t = term.toLowerCase().trim()

        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                let child = rootItem.children[i]
                if (child.title && child.title.toLowerCase().includes(t)) {
                    return child
                }
            }

            for (let i = 0; i < rootItem.children.length; i++) {
                let found = findTarget(rootItem.children[i])
                if (found) return found
            }
            return null
        }

        let target = findTarget(mainLayout)
        if (target) {
            let pos = target.mapToItem(mainLayout, 0, 0)
            page.contentY = Math.max(0, pos.y - 0)
        }
    }
    
    ColumnLayout {
        id: mainLayout 
        Layout.fillWidth: true   
        Layout.fillHeight: true
        spacing: 20

        // The mesh between people's desktops (services/Mesh.qml): the
        // server and your name are settings, the access token and the mesh
        // key go to the keyring through `nixbook-mesh`, on stdin.
        ContentSection {
            id: meshSection
            icon: "hub"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Mesh")
            property string status: ""
            property string code: ""
            // The token and the mesh code by hand, instead of an invite.
            property bool byHand: false
            // The admin: the last invite made.
            property string invite: ""
            property string invited: ""

            function check() {
                meshSection.status = Translation.tr("Checking…")
                Mesh.run(["test", Mesh.server], "", (ok, answer) => {
                    meshSection.status = ok
                        ? (answer.joined ? Translation.tr("Connected as %1, in the mesh.").arg(answer.user)
                            : Translation.tr("The token works (%1). Now create a mesh or enter a member's code.").arg(answer.user))
                        : answer.error
                })
            }
            Component.onCompleted: Mesh.refreshStatus()

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("Talk with the people you choose, desktop to desktop, over the internet: messages to everyone or to one person, and everyone's status (free, in a meeting, gaming, busy, do not disturb, away; never which app). Everything is encrypted on this computer with the mesh's key, which only members have: the server only passes on what it can't read. To join, paste the invite code someone gave you. The server's admin invites people from here.")
            }
            ConfigTextArea {
                id: meshServer
                configKey: "mesh.server"
                Layout.fillWidth: true
                fieldWidth: 320
                buttonIcon: "dns"
                text: Translation.tr("Server")
                placeholderText: Translation.tr("e.g. https://ntfy.example.org")
                value: Config.options.mesh.server ?? ""
                Connections {
                    target: meshServer.textArea
                    function onEditingFinished() {
                        Config.options.mesh.server = meshServer.value.trim().replace(/\/+$/, "")
                    }
                }
            }
            ConfigTextArea {
                id: meshName
                configKey: "mesh.name"
                Layout.fillWidth: true
                fieldWidth: 320
                buttonIcon: "badge"
                text: Translation.tr("Your name")
                placeholderText: Mesh.myName
                value: Config.options.mesh.name ?? ""
                Connections {
                    target: meshName.textArea
                    function onEditingFinished() {
                        Config.options.mesh.name = meshName.value.trim()
                    }
                }
            }

            // Joining with an invite: one code, nothing else.
            ColumnLayout {
                Layout.fillWidth: true
                visible: !Mesh.configured && !meshSection.byHand
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    font.weight: Font.DemiBold
                    text: Translation.tr("Got an invite? Paste it here and click Join: that's all.")
                }
                MaterialTextField {
                    id: meshInvite
                    Layout.fillWidth: true
                    placeholderText: Translation.tr("nixbook-mesh-invite:…")
                    echoMode: TextInput.Password
                    onAccepted: meshAccept.clicked()
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    SmallButton {
                        id: meshAccept
                        enabled: !Mesh.busy && meshInvite.text.trim() !== ""
                        materialIcon: "group_add"
                        mainText: Mesh.busy ? Translation.tr("Joining…") : Translation.tr("Join")
                        onClicked: {
                            meshSection.status = Translation.tr("Joining…")
                            Mesh.accept(meshInvite.text.trim(), (ok, answer) => {
                                meshInvite.text = ""
                                meshSection.status = ok ? Translation.tr("You're in, as %1.").arg(answer.user) : answer.error
                            })
                        }
                    }
                    SmallButton {
                        enabled: !Mesh.busy
                        materialIcon: "tune"
                        mainText: Translation.tr("Set it up by hand instead")
                        onClicked: meshSection.byHand = true
                    }
                }
            }

            // By hand: the access token, then create a mesh or enter its code.
            ColumnLayout {
                Layout.fillWidth: true
                visible: Mesh.configured || meshSection.byHand
                spacing: 6
                // The access token.
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Mesh.setup.token
                        ? Translation.tr("Access token: saved (%1).").arg(Mesh.setup.tokenSource === "file"
                            ? Translation.tr("in ~/.config/nixbook-shell/mesh/token") : Translation.tr("in your keyring"))
                        : Translation.tr("Access token: none yet. Paste the one the server's admin gave you (tk_…).")
                }
                MaterialTextField {
                    id: meshToken
                    Layout.fillWidth: true
                    placeholderText: Mesh.setup.token ? Translation.tr("A new access token (saved: leave empty to keep it)")
                        : Translation.tr("Access token (tk_…)")
                    echoMode: TextInput.Password
                    onAccepted: meshTokenSave.clicked()
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    SmallButton {
                        id: meshTokenSave
                        enabled: !Mesh.busy && meshToken.text.trim() !== ""
                        materialIcon: "key"
                        mainText: Translation.tr("Save the token")
                        onClicked: {
                            Mesh.run(["token", "set"], meshToken.text.trim(), (ok, answer) => {
                                meshToken.text = ""
                                if (!ok) {
                                    meshSection.status = answer.error
                                    return
                                }
                                Mesh.reconnect()
                                if (Mesh.server !== "") meshSection.check()
                            })
                        }
                    }
                    SmallButton {
                        enabled: !Mesh.busy && !!Mesh.setup.token && Mesh.server !== ""
                        materialIcon: "network_check"
                        mainText: Translation.tr("Test")
                        onClicked: meshSection.check()
                    }
                    SmallButton {
                        visible: !!Mesh.setup.token
                        enabled: !Mesh.busy
                        materialIcon: "key_off"
                        mainText: Translation.tr("Forget the token")
                        onClicked: Mesh.run(["token", "forget"], "", () => Mesh.reconnect())
                    }
                }

                // The mesh key.
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Mesh.setup.joined
                        ? (Mesh.connected ? Translation.tr("In the mesh, connected. Members seen: %1.").arg(Mesh.memberList.length)
                            : Translation.tr("In the mesh, not connected yet.") + (Mesh.lastError ? ` ${Mesh.lastError}` : ""))
                        : Translation.tr("Not in a mesh yet: create one (then show its code to the others), or enter the code a member shows you.")
                }
                MaterialTextField {
                    id: meshCode
                    Layout.fillWidth: true
                    visible: !Mesh.setup.joined
                    placeholderText: Translation.tr("A member's mesh code (XXXXX-XXXXX-…)")
                    onAccepted: meshJoin.clicked()
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    SmallButton {
                        id: meshJoin
                        visible: !Mesh.setup.joined
                        enabled: !Mesh.busy && meshCode.text.trim() !== ""
                        materialIcon: "group_add"
                        mainText: Translation.tr("Join")
                        onClicked: {
                            Mesh.run(["mesh", "join"], meshCode.text.trim(), (ok, answer) => {
                                if (!ok) {
                                    meshSection.status = answer.error
                                    return
                                }
                                meshCode.text = ""
                                meshSection.status = Translation.tr("Joined.")
                                Mesh.reconnect()
                            })
                        }
                    }
                    SmallButton {
                        visible: !Mesh.setup.joined
                        enabled: !Mesh.busy
                        materialIcon: "add_circle"
                        mainText: Translation.tr("Create a mesh")
                        onClicked: {
                            Mesh.run(["mesh", "create"], "", (ok, answer) => {
                                if (!ok) {
                                    meshSection.status = answer.error
                                    return
                                }
                                meshSection.code = answer.code
                                meshSection.status = Translation.tr("Created. Show this code to the others.")
                                Mesh.reconnect()
                            })
                        }
                    }
                    SmallButton {
                        visible: !!Mesh.setup.joined
                        enabled: !Mesh.busy
                        materialIcon: meshSection.code !== "" ? "visibility_off" : "qr_code"
                        mainText: meshSection.code !== "" ? Translation.tr("Hide the code") : Translation.tr("Show the mesh code")
                        onClicked: {
                            if (meshSection.code !== "") {
                                meshSection.code = ""
                                return
                            }
                            Mesh.run(["mesh", "code"], "", (ok, answer) => {
                                if (ok) meshSection.code = answer.code
                                else meshSection.status = answer.error
                            })
                        }
                    }
                    SmallButton {
                        visible: meshSection.code !== ""
                        materialIcon: "content_copy"
                        mainText: Translation.tr("Copy")
                        onClicked: Clipboard.copy(meshSection.code)
                    }
                    SmallButton {
                        visible: !!Mesh.setup.joined
                        enabled: !Mesh.busy
                        materialIcon: "logout"
                        mainText: Translation.tr("Leave the mesh")
                        onClicked: {
                            meshSection.code = ""
                            Mesh.run(["mesh", "leave"], "", () => Mesh.reconnect())
                        }
                    }
                }
            }

            // The server's admin: who is in, inviting and removing people.
            ColumnLayout {
                Layout.fillWidth: true
                visible: Mesh.isAdmin && !!Mesh.setup.joined
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    font.weight: Font.DemiBold
                    text: Translation.tr("People (you are the server's admin)")
                }
                Repeater {
                    model: Mesh.people
                    delegate: RowLayout {
                        id: person
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            text: person.modelData.role === "admin" ? "shield_person" : "person"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: person.modelData.name + (person.modelData.name === Mesh.account.user ? Translation.tr(" (you)") : "")
                                + (person.modelData.role === "admin" ? ` · ${Translation.tr("admin")}` : "")
                        }
                        SmallButton {
                            visible: person.modelData.role !== "admin"
                            enabled: !Mesh.busy
                            materialIcon: "person_remove"
                            mainText: Translation.tr("Remove")
                            onClicked: Mesh.removePerson(person.modelData.name, (ok, answer) => {
                                meshSection.status = ok ? Translation.tr("%1 is out: their desktop can't reach the mesh any more.").arg(answer.name) : answer.error
                            })
                        }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    MaterialTextField {
                        id: meshInviteName
                        Layout.fillWidth: true
                        placeholderText: Translation.tr("Their name (lower case, e.g. choco)")
                        onAccepted: meshInviteButton.clicked()
                    }
                    SmallButton {
                        id: meshInviteButton
                        enabled: !Mesh.busy && meshInviteName.text.trim() !== ""
                        materialIcon: "person_add"
                        mainText: Translation.tr("Invite")
                        onClicked: {
                            Mesh.invite(meshInviteName.text.trim().toLowerCase(), (ok, answer) => {
                                if (!ok) {
                                    meshSection.status = answer.error
                                    return
                                }
                                meshInviteName.text = ""
                                meshSection.invite = answer.code
                                meshSection.invited = answer.name
                                meshSection.status = ""
                            })
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: meshSection.invite !== ""
                    wrapMode: Text.WordWrap
                    text: Translation.tr("Send this to %1 privately (it holds the mesh's key). It works once; inviting %1 again makes a new one.").arg(meshSection.invited)
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: meshSection.invite !== ""
                    wrapMode: Text.WrapAnywhere
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: meshSection.invite
                }
                Flow {
                    Layout.fillWidth: true
                    visible: meshSection.invite !== ""
                    spacing: 6
                    SmallButton {
                        materialIcon: "content_copy"
                        mainText: Translation.tr("Copy the invite")
                        onClicked: Clipboard.copy(meshSection.invite)
                    }
                    SmallButton {
                        materialIcon: "visibility_off"
                        mainText: Translation.tr("Hide it")
                        onClicked: {
                            meshSection.invite = ""
                            meshSection.invited = ""
                        }
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: meshSection.code !== ""
                wrapMode: Text.WrapAnywhere
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.large
                text: meshSection.code
            }
            StyledText {
                Layout.fillWidth: true
                visible: Mesh.myFingerprint !== "" && !!Mesh.setup.joined
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: Translation.tr("This desktop's key (private messages are sealed for it): %1. The others see it in your private conversation; compare it to be sure no one poses as you.").arg(Mesh.myFingerprint)
            }
            StyledText {
                Layout.fillWidth: true
                visible: meshSection.status !== ""
                wrapMode: Text.WordWrap
                color: Appearance.colors.colSubtext
                text: meshSection.status
            }
            GroupedList {
                ConfigSwitch {
                    configKey: "mesh.sharePresence";
                    enabled: !nixManaged;
                    buttonIcon: "radio_button_checked"
                    text: Translation.tr("Share my status (free, in a meeting, gaming, busy, away)")
                    checked: Config.options.mesh.sharePresence
                    onCheckedChanged: {
                        Config.options.mesh.sharePresence = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "mesh.shareAvatar";
                    enabled: !nixManaged;
                    buttonIcon: "account_circle"
                    text: Translation.tr("Show my account picture to the others")
                    checked: Config.options.mesh.shareAvatar
                    onCheckedChanged: {
                        Config.options.mesh.shareAvatar = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "mesh.nudgeCutIn";
                    enabled: !nixManaged;
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("Show the nudges I receive as a cut-in")
                    checked: Config.options.mesh.nudgeCutIn
                    onCheckedChanged: {
                        Config.options.mesh.nudgeCutIn = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "mesh.notify";
                    enabled: !nixManaged;
                    buttonIcon: "notifications"
                    text: Translation.tr("A notification for each message")
                    checked: Config.options.mesh.notify
                    onCheckedChanged: {
                        Config.options.mesh.notify = checked;
                    }
                }
                ConfigSwitch {
                    configKey: "mesh.enable";
                    enabled: !nixManaged;
                    buttonIcon: "power_settings_new"
                    text: Translation.tr("Connected to the mesh")
                    checked: Config.options.mesh.enable
                    onCheckedChanged: {
                        Config.options.mesh.enable = checked;
                    }
                }
            }
        }
    }
}
