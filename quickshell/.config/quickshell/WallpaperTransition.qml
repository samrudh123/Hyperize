// Animated wallpaper changes. The wallpaper itself is still swaybg (stills)
// or mpvpaper (videos), started by set-wallpaper.sh; this is a full-screen
// surface on the BOTTOM layer — above the wallpaper, under every window — that
// covers the switch:
//
//   set-wallpaper.sh  -> qs ipc call wallpaper transition <from> <to> <kind> <x> <y>
//                        (the overlay shows <from> at once, then animates to <to>)
//                     -> starts the new swaybg/mpvpaper underneath, kills the old
//                     -> qs ipc call wallpaper ready
//   when both the animation and the backend are done, the overlay fades out
//   and the real wallpaper is what you see.
//
// <from>/<to> are still images: the wallpaper file, or for a video a frame
// of it (set-wallpaper.sh grabs mpv's current frame / the new video's first).
// <kind> is one of `kinds` below; the picker (wallpaper-picker.py, `t`)
// writes the chosen one to ~/.config/hypr/wallpaper-transition.
// The effects are one shader: shaders/transition.frag (compile with qsb).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: wt

    // name -> shader mode + duration (ms). Keep in step with the picker's list.
    readonly property var kinds: ({
        circle:   { mode: 0,  ms: 1300 },
        cursor:   { mode: 1,  ms: 1300 },
        iris:     { mode: 2,  ms: 1250 },
        fade:     { mode: 3,  ms: 800 },
        wipe:     { mode: 4,  ms: 1000 },
        wave:     { mode: 5,  ms: 1400 },
        slide:    { mode: 6,  ms: 900 },
        zoom:     { mode: 7,  ms: 1000 },
        dissolve: { mode: 8,  ms: 1300 },
        pixelate: { mode: 9,  ms: 1100 },
        diamond:  { mode: 10, ms: 1100 }
    })

    property bool active: false
    property bool animDone: false
    property bool backendReady: false
    property string fromPath
    property string toPath
    property real mode: 0
    property vector2d origin: Qt.vector2d(0.5, 0.5)

    function start(from, to, kind, ox, oy) {
        if (kind === "random") {
            const names = Object.keys(kinds);
            kind = names[Math.floor(Math.random() * names.length)];
        }
        const k = kinds[kind] || kinds.circle;
        anim.stop();
        fadeOut.stop();
        cover.opacity = 0;                // until both images are decoded
        mode = k.mode;
        anim.duration = k.ms;
        origin = (k.mode === 1 && ox >= 0) ? Qt.vector2d(ox, oy) : Qt.vector2d(0.5, 0.5);
        animDone = false;
        backendReady = false;
        fx.progress = 0;
        fromPath = from;
        toPath = to;
        active = true;
        pending.restart();
        safety.restart();
    }

    function maybeFinish() {
        if (animDone && backendReady && active) fadeOut.restart();
    }

    IpcHandler {
        target: "wallpaper"
        function transition(from: string, to: string, kind: string, x: real, y: real): void {
            wt.start(from, to, kind, x, y);
        }
        // for debugging: qs ipc call wallpaper status
        function status(): string {
            return JSON.stringify({ active: wt.active, progress: fx.progress, animDone: wt.animDone,
                                    backendReady: wt.backendReady, from: fromImg.status, to: toImg.status,
                                    mode: wt.mode, opacity: cover.opacity });
        }
        function ready(): void {
            wt.backendReady = true;
            wt.maybeFinish();
        }
    }

    // Start once both images are decoded (local files: well under the 0.6 s
    // set-wallpaper.sh waits before killing the old wallpaper).
    Timer {
        id: pending
        interval: 16
        repeat: true
        onTriggered: {
            const s = [fromImg.status, toImg.status];
            if (s.includes(Image.Error)) { stop(); wt.active = false; return; }
            if (s.every(x => x === Image.Ready)) { stop(); cover.opacity = 1; anim.restart(); }
        }
    }

    // never leave a cover up if something goes wrong
    Timer {
        id: safety
        interval: 6000
        onTriggered: wt.active = false
    }

    NumberAnimation {
        id: anim
        target: fx
        property: "progress"
        from: 0
        to: 1
        easing.type: Easing.InOutCubic
        onFinished: { wt.animDone = true; wt.maybeFinish(); }
    }

    NumberAnimation {
        id: fadeOut
        target: cover
        property: "opacity"
        to: 0
        duration: 280
        easing.type: Easing.OutQuad
        onFinished: { wt.active = false; safety.stop(); }
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "qs-wallpaper-transition"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}                       // never takes a click
    color: "transparent"
    visible: active

    Item {
        id: cover
        anchors.fill: parent

        // Both drawn exactly like swaybg's `fill` (cover + crop), and
        // decoded at screen size — some wallpapers are 8K.
        Image {
            id: fromImg
            anchors.fill: parent
            source: wt.fromPath ? "file://" + wt.fromPath : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(wt.width, wt.height)
            cache: false
            asynchronous: true
            visible: false
        }
        Image {
            id: toImg
            anchors.fill: parent
            source: wt.toPath ? "file://" + wt.toPath : ""
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(wt.width, wt.height)
            cache: false
            asynchronous: true
            visible: false
        }

        ShaderEffectSource { id: fromSrc; sourceItem: fromImg; hideSource: true }
        ShaderEffectSource { id: toSrc; sourceItem: toImg; hideSource: true }

        ShaderEffect {
            id: fx
            anchors.fill: parent
            property real progress: 0
            property real mode: wt.mode
            property real aspect: width / Math.max(1, height)
            property vector2d origin: wt.origin
            property var fromTex: fromSrc
            property var toTex: toSrc
            fragmentShader: Qt.resolvedUrl("shaders/transition.frag.qsb")
        }
    }
}
