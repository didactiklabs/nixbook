import QtQuick;

/**
 * An AI model representation.
 * - name: Friendly name of the model
 * - icon: Icon name of the model
 * - description: Description of the model
 * - homepage: Link shown for the model
 * - model: Model code
 * - api_format: How Ai.qml answers with it: "config-assistant" or "claude-code"
 */

QtObject {
    property string name
    property string icon
    property string description
    property string homepage
    property string model
    property string api_format
}
