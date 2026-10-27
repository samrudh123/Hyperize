// What the settings panel's pieces share: the sidebar search (every
// SettingsRow filters on it) and a way for a tab to close the panel
// (before opening another panel or picker).
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    property string query: ""
    signal closeRequested()
}
