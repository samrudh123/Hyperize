// A password prompt over the settings card (a joke gate: Settings ›
// Appearance asks before going Dark → Light). Shown while
// SettingsState.auth is set:
//
//     SettingsState.auth = { title, message, onSuccess: () => …, onCancel: () => … }
//
// The password is checked against the user's login (= sudo) password by
// /usr/sbin/unix_chkpwd — the pam_unix helper sudo itself ends up in — fed
// on stdin (never argv), so no sudo log entry / cached sudo ticket.
// Enter = authenticate · Esc / Cancel = back out · Tab cycles field/buttons.
// While it's up it's modal: Tab / Shift+Tab wrap inside it (KeyNavigation on
// each control — Qt moves Tab focus at the focused item itself, before a
// parent's Keys sees it), every other key stops here, the dim layer eats
// clicks, hover and the wheel, and focus that still leaks out is pulled back.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: auth

    readonly property var req: SettingsState.auth
    readonly property bool open: req !== null
    property bool checking: false
    property string error: ""
    readonly property color panelTint: Theme.accent

    anchors.fill: parent
    visible: opacity > 0.01
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: open ? 170 : 130; easing.type: Easing.OutCubic } }
    z: 500

    onOpenChanged: {
        if (open) {
            error = "";
            field.text = "";
            field.input.forceActiveFocus();
        } else {
            field.text = "";
        }
    }

    function cancel() {
        const r = req;
        SettingsState.auth = null;
        if (r && r.onCancel) r.onCancel();
    }
    function submit() {
        if (checking || !open) return;
        if (field.text === "") { error = "Type your password"; shake.restart(); return; }
        checking = true;
        error = "";
        check.pw = field.text;
        check.running = true;
    }

    Process {
        id: check
        property string pw: ""
        // read the password from stdin, hand it to unix_chkpwd NUL-terminated
        // (printf is a builtin: it never shows up in ps)
        command: ["/bin/sh", "-c",
                  "IFS= read -r p; printf '%s\\0' \"$p\" | /usr/sbin/unix_chkpwd \"$(id -un)\" nullok"]
        stdinEnabled: true
        onStarted: { write(pw + "\n"); pw = ""; }
        onExited: code => {
            auth.checking = false;
            if (!auth.open) return;
            if (code === 0) {
                const r = auth.req;
                SettingsState.auth = null;
                if (r && r.onSuccess) r.onSuccess();
            } else {
                auth.error = "Wrong password — the buffaloes remain protected";
                field.text = "";
                field.input.forceActiveFocus();
                shake.restart();
            }
        }
    }

    // keys stay in the dialog: Esc backs out (never closes Settings), Tab
    // cycles inside, the page behind doesn't scroll / switch tabs
    Keys.onPressed: ev => {
        if (!open) return;
        if (ev.key === Qt.Key_Escape) cancel();
        ev.accepted = true;                     // nothing reaches the card / page
    }

    // focus may not leave while open (a click, a stray Tab): back to the field
    readonly property Item winFocus: Window.activeFocusItem
    onWinFocusChanged: if (open) refocus.restart()
    Timer {
        id: refocus
        interval: 0
        onTriggered: {
            if (!auth.open) return;
            for (let x = auth.winFocus; x; x = x.parent)
                if (x === dlg) return;
            field.input.forceActiveFocus();
        }
    }

    // dim the card behind; clicks there do nothing (no closing by accident)
    Rectangle {
        anchors.fill: parent
        radius: 20
        color: Theme.alpha(Theme.crust, 0.55)
        MouseArea {
            anchors.fill: parent
            enabled: auth.open
            hoverEnabled: true
            acceptedButtons: Qt.AllButtons
            onWheel: ev => ev.accepted = true   // no scrolling the page behind
        }
    }

    Rectangle {
        id: dlg
        width: 420
        height: col.implicitHeight + 44
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: shakeX
        property real shakeX: 0
        radius: 18
        color: Theme.alpha(Theme.base, Math.max(0.94, Theme.panelOpacity))
        border.width: 1
        border.color: Theme.alpha(Theme.surface1, 0.9)

        scale: auth.open ? 1 : 0.94
        Behavior on scale { NumberAnimation { duration: auth.open ? 260 : 130; easing.type: auth.open ? Easing.OutBack : Easing.InCubic; easing.overshoot: 0.7 } }

        SequentialAnimation {
            id: shake
            NumberAnimation { target: dlg; property: "shakeX"; to: -10; duration: 45 }
            NumberAnimation { target: dlg; property: "shakeX"; to: 9; duration: 70 }
            NumberAnimation { target: dlg; property: "shakeX"; to: -6; duration: 60 }
            NumberAnimation { target: dlg; property: "shakeX"; to: 3; duration: 50 }
            NumberAnimation { target: dlg; property: "shakeX"; to: 0; duration: 40 }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onWheel: ev => ev.accepted = true
        }

        Column {
            id: col
            x: 22
            y: 22
            width: parent.width - 44
            spacing: 16

            // header — the settings sidebar's: accent tile + bold title
            Row {
                spacing: 12
                Rectangle {
                    width: 40
                    height: 40
                    radius: 12
                    color: Theme.accent
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f033e}"                       // md-lock
                        color: Theme.crust
                        font.family: Theme.font
                        font.pixelSize: 20
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        text: auth.req ? auth.req.title : ""
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 17
                        font.weight: Font.Bold
                    }
                    Text {
                        text: "Switching to Light mode"
                        color: Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }
            }

            // the warning — a yellow callout
            Rectangle {
                width: parent.width
                height: warn.implicitHeight + 24
                radius: 12
                color: Theme.alpha(Theme.yellow, 0.12)
                border.width: 1
                border.color: Theme.alpha(Theme.yellow, 0.45)
                Row {
                    id: warn
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f0026}"                       // md-alert
                        color: Theme.yellow
                        font.family: Theme.font
                        font.pixelSize: 20
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: auth.req ? auth.req.message : ""
                        color: Theme.yellow
                        font.family: Theme.font
                        font.pixelSize: 14
                        font.weight: Font.Bold
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f019a}"                       // md-cow (closest to a buffalo)
                        color: Theme.yellow
                        font.family: Theme.font
                        font.pixelSize: 20
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text {
                    text: "Password"
                    color: Theme.subtext0
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                SettingsField {
                    id: field
                    width: parent.width
                    height: 38
                    placeholder: "sudo password"
                    input.echoMode: TextInput.Password
                    input.passwordCharacter: "•"
                    input.readOnly: auth.checking
                    input.KeyNavigation.tab: cancelBtn
                    input.KeyNavigation.backtab: okBtn
                    onAccepted: auth.submit()
                    onEscaped: auth.cancel()
                    onEdited: auth.error = ""
                }
                Text {
                    width: parent.width
                    visible: auth.error !== ""
                    wrapMode: Text.Wrap
                    text: auth.error
                    color: Theme.red
                    font.family: Theme.font
                    font.pixelSize: 11
                }
            }

            Row {
                anchors.right: parent.right
                spacing: 10
                IconBtn {
                    id: cancelBtn
                    KeyNavigation.tab: okBtn
                    KeyNavigation.backtab: field.input
                    text: "Cancel"
                    icon: "\u{f0156}"
                    height: 36
                    onClicked: auth.cancel()
                }
                IconBtn {
                    id: okBtn
                    KeyNavigation.tab: field.input
                    KeyNavigation.backtab: cancelBtn
                    text: auth.checking ? "Checking…" : "Authenticate"
                    icon: "\u{f0306}"                           // md-key
                    height: 36
                    active: true
                    enabled: !auth.checking
                    onClicked: auth.submit()
                }
            }
        }
    }
}
