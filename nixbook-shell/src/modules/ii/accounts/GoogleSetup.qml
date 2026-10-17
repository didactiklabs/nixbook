pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.tasks
import QtQuick
import QtQuick.Layouts

// The one-time making of Google's OAuth client (nixbook-accounts uses the
// user's own; DankCalendar's built-in one is for DankCalendar only): the
// steps in Google Cloud, then the downloaded file or the two values.
ColumnLayout {
    id: root

    property bool showValues: false
    spacing: 10

    Step {
        number: 1
        text: Translation.tr("In Google Cloud, create a project, then enable the People API, the Tasks API (and the Calendar API, for later).")
        links: [
            { text: Translation.tr("Google Cloud"), url: Accounts.googleSetup.console },
            { text: "People API", url: Accounts.googleSetup.apis?.people ?? "" },
            { text: "Tasks API", url: Accounts.googleSetup.apis?.tasks ?? "" },
            { text: "Calendar API", url: Accounts.googleSetup.apis?.calendar ?? "" },
        ]
    }
    Step {
        number: 2
        text: Translation.tr("Google Auth Platform → Branding: an app name and your email. Audience: External, then Publish the app, so the sign-in doesn't expire after 7 days (Google will say it is unverified: it's your own app).")
    }
    Step {
        number: 3
        text: Translation.tr("Clients → Create client → Desktop app, then download its JSON (client_secret_….json).")
    }
    Step {
        number: 4
        text: Translation.tr("Use it here (once: every Google account you add uses it):")
    }
    RowLayout {
        Layout.leftMargin: 44
        spacing: 10
        PanelButton {
            filled: true
            icon: "download_done"
            text: Translation.tr("Use the downloaded file")
            onClicked: Accounts.setupGoogleFromDownloads(ok => {
                if (ok) Accounts.addGoogle()
            })
        }
        PanelButton {
            icon: "key"
            text: Translation.tr("Enter the ID and secret")
            toggled: root.showValues
            onClicked: root.showValues = !root.showValues
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 44
        visible: root.showValues
        spacing: 8
        MaterialTextField {
            id: idField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Client ID (….apps.googleusercontent.com)")
        }
        MaterialTextField {
            id: secretField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Client secret")
            echoMode: TextInput.Password
        }
        PanelButton {
            filled: true
            text: Translation.tr("Save and connect")
            onClicked: Accounts.setupGoogleFromValues(idField.text.trim(), secretField.text.trim(), ok => {
                if (!ok) return
                secretField.text = ""
                Accounts.addGoogle()
            })
        }
    }

    component Step: RowLayout {
        id: step
        property int number
        property string text
        property var links: []
        Layout.fillWidth: true
        spacing: 12
        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 32
            implicitHeight: 32
            radius: 16
            color: Appearance.colors.colPrimaryContainer
            StyledText {
                anchors.centerIn: parent
                text: step.number
                font.weight: Font.Medium
                color: Appearance.colors.colOnPrimaryContainer
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 5
                text: step.text
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnLayer0
            }
            Flow {
                Layout.fillWidth: true
                visible: step.links.length > 0
                spacing: 6
                Repeater {
                    model: step.links.filter(l => l.url)
                    delegate: PanelButton {
                        required property var modelData
                        compact: true
                        icon: "open_in_new"
                        text: modelData.text
                        onClicked: Qt.openUrlExternally(modelData.url)
                    }
                }
            }
        }
    }
}
