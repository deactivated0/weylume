import QtQuick
import QtQuick.Controls
import QtQml.Models
import qs
SettingsButton {
    id: root
    property var choices: []
    property string value: ""
    signal selected(string value)
    buttonText: {
        if (!choices || choices.length === 0) return root.value || "Choose";
        for (let i = 0; i < choices.length; i++) {
            if (String(choices[i].value) === String(root.value)) {
                return choices[i].label || choices[i].value;
            }
        }
        return root.value || "Choose";
    }
    onClicked: menu.popup()
    Menu {
        id: menu
        Instantiator {
            model: root.choices
            delegate: MenuItem {
                required property var modelData
                text: modelData.label || modelData.value
                enabled: modelData.available !== false
                checkable: true
                checked: modelData.value === root.value
                onTriggered: root.selected(modelData.value)
            }
            onObjectAdded: (index, object) => menu.insertItem(index, object)
            onObjectRemoved: (index, object) => menu.removeItem(object)
        }
    }
}
