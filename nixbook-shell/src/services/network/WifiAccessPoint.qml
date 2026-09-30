import QtQuick

QtObject {
    required property var lastIpcObject
    readonly property string ssid: lastIpcObject.ssid
    readonly property string bssid: lastIpcObject.bssid
    readonly property int strength: lastIpcObject.strength
    readonly property int frequency: lastIpcObject.frequency
    readonly property bool active: lastIpcObject.active
    readonly property string security: lastIpcObject.security
    readonly property bool isSecure: security.length > 0
    // WPA/WPA2/WPA3-Enterprise: nmcli lists the key management as "802.1X"
    readonly property bool isEnterprise: security.includes("802.1X")

    property bool askingPassword: false
}
