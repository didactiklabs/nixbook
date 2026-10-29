import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

RowLayout {
    id: root
    // A StyledToolTip inside shows while this is hovered (without a
    // `hovered` it took the row for always hovered: stuck on screen).
    readonly property alias hovered: rowHover.hovered
    HoverHandler {
        id: rowHover
    }
    property string text: ""
    property string icon: ""
    property list<var> options: [
        {
            "displayName": "Option 1",
            "icon": "check",
            "value": 1
        },
        {
            "displayName": "Option 2",
            "icon": "close",
            "value": 2
        },
    ]
    property var currentValue: null
    property string configKey: ""
    readonly property bool nixManaged: configKey !== "" && NixManaged.isPinned(configKey)
    // Settings menu "Editable only" filter: locked settings drop out of the
    // list (containers hide once empty, see NixManaged.allFiltered).
    readonly property bool filteredOut: nixManaged && NixManaged.hideLocked
    // Set `shown` (not `visible`) to hide this conditionally from a page: an
    // instance's `visible:` would replace the filter binding below.
    property bool shown: true
    visible: root.shown && !root.filteredOut
    // Pinned by Nix: locked regardless of what the usage site binds to
    // `enabled` (NixManaged also reverts any write to a pinned key).
    Binding on enabled {
        when: root.nixManaged
        value: false
    }

    signal selected(var newValue)

    spacing: 10
    Layout.leftMargin: 8
    Layout.rightMargin: 8

    // What the buttons need on one line, and the widest of them: the row
    // shares a narrow page between the label (which wraps) and the buttons
    // (which flow onto more lines) instead of growing past the page — a long
    // row used to widen its whole section, cropping options and texts.
    readonly property real buttonsOneLine: {
        let w = 0, n = 0;
        for (const c of buttonsFlow.children) {
            if (!c.visible || c.implicitWidth <= 0) continue;
            w += c.implicitWidth;
            n++;
        }
        return w + Math.max(0, n - 1) * buttonsFlow.spacing;
    }
    readonly property real widestButton: {
        let w = 0;
        for (const c of buttonsFlow.children) if (c.visible) w = Math.max(w, c.implicitWidth);
        return w;
    }

    RowLayout {
        spacing: 10
        visible: root.text !== ""
        Layout.fillWidth: true
        Layout.minimumWidth: Math.min(implicitWidth, 120)
        OptionalMaterialSymbol {
            icon: root.icon
            opacity: root.enabled ? 1 : 0.4
        }
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.text
            color: Appearance.colors.colOnSecondaryContainer
            opacity: root.enabled ? 1 : 0.4
        }
    }

    NixManagedBadge { pinned: root.nixManaged }
    Flow {
        id: buttonsFlow
        Layout.fillWidth: true
        Layout.preferredWidth: root.buttonsOneLine
        Layout.maximumWidth: root.text !== "" ? root.buttonsOneLine : Number.POSITIVE_INFINITY
        Layout.minimumWidth: root.widestButton
        Layout.alignment: Qt.AlignRight
        spacing: 2

        Repeater {
            model: root.options
            delegate: SelectionGroupButton {
                id: paletteButton
                required property var modelData
                required property int index
                onYChanged: {
                    if (index === 0) {
                        paletteButton.leftmost = true
                    } else {
                        var prev = buttonsFlow.children[index - 1]
                        var thisIsOnNewLine = prev && prev.y !== paletteButton.y
                        paletteButton.leftmost = thisIsOnNewLine
                        prev.rightmost = thisIsOnNewLine
                    }
                }
                leftmost: index === 0
                rightmost: index === root.options.length - 1
                buttonIcon: modelData.icon || ""
                buttonText: modelData.displayName
                toggled: root.currentValue == modelData.value
                onClicked: {
                    root.selected(modelData.value);
                }
            }
        }
    }
}