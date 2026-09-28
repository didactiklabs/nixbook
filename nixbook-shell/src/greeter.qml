//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
// The login screen (`nixbook-shell greeter`, started by greetd through the
// nixbook-shell.greeter NixOS module, in niri or cage): the shell's own look —
// the theme and its variant, the palette, fonts and the wallpaper, read from
// the settings the login screen's user exported (greeter.nix sets
// XDG_CONFIG_HOME / XDG_STATE_HOME to a copy of them) — with a greetd login
// (modules/ii/greeter). It never writes those settings.
import "modules/common"
import "services"
import "modules/ii/greeter"
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
    id: root

    Component.onCompleted: {
        Config.blockWrites = true;
        MaterialThemeLoader.reapplyTheme();
    }

    GreeterContext {
        id: greeterContext
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            // The login card and the keyboard on the focused screen (the
            // first one until the compositor says), the wallpaper elsewhere.
            readonly property bool primary: (WM.focusedMonitor?.name ?? Quickshell.screens[0]?.name) === modelData.name

            WlrLayershell.namespace: "quickshell:greeter"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: win.primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            color: "transparent"

            GreeterSurface {
                anchors.fill: parent
                context: greeterContext
                primary: win.primary
            }
        }
    }
}
