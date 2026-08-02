// dictado overlay — a Quickshell instance independent from your main shell.
// Launch with:   qs -c dictado
// Control with:  qs -c dictado ipc call overlay listening|working|hide
//
// Colours below are Catppuccin Mocha. Change them to match your own theme.

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    // idle | listening | working
    property string mode: "idle"

    readonly property color cBg:      "#201f23"  // surfaceContainer
    readonly property color cBorder:  "#47464f"  // outlineVariant
    readonly property color cText:    "#e5e1e7"  // onSurface
    readonly property color cSub:     "#c8c5d1"  // onSurfaceVariant
    readonly property color cAccent:  "#c2c1ff"  // primary
    readonly property color cWorking: "#f5b2e0"  // tertiary

    IpcHandler {
        target: "overlay"

        function listening(): void {
            root.mode = "listening";
        }

        function working(): void {
            root.mode = "working";
        }

        function hide(): void {
            root.mode = "idle";
        }
    }

    PanelWindow {
        id: win

        visible: root.mode !== "idle"
        color: "transparent"

        // No anchors -> layer-shell centres it on screen.
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "dictado-overlay"
        // Never steal the keyboard: the text must reach the window that ALREADY
        // has focus.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        WlrLayershell.exclusionMode: ExclusionMode.Ignore

        implicitWidth: 440
        implicitHeight: 168

        Rectangle {
            id: card

            anchors.fill: parent
            anchors.margins: 8
            radius: 24
            color: root.cBg
            border.width: 1
            border.color: root.cBorder

            opacity: win.visible ? 1 : 0
            scale: win.visible ? 1 : 0.92

            Behavior on opacity {
                NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
                NumberAnimation { duration: 220; easing.type: Easing.OutBack }
            }

            Column {
                anchors.centerIn: parent
                spacing: 18

                // ---- Audio waveform ----
                Row {
                    id: wave

                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4
                    height: 56

                    Repeater {
                        model: 28

                        Rectangle {
                            id: bar

                            required property int index

                            width: 5
                            radius: 3
                            color: root.mode === "working" ? root.cWorking : root.cAccent

                            // Small base height; the Timer pushes it while listening.
                            property real target: 6
                            height: target
                            y: (wave.height - height) / 2

                            Behavior on height {
                                NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
                            }
                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }
                    }
                }

                // ---- Status label ----
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.mode === "working" ? "Transcribing…" : "Listening…"
                    color: root.mode === "working" ? root.cSub : root.cText
                    font.pixelSize: 15
                    font.family: "Cascadia Code"
                    font.letterSpacing: 0.5

                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                }
            }

            // Animates the bars. While listening: random heights (waveform).
            // While transcribing: a travelling sine wave, calmer.
            Timer {
                running: win.visible
                interval: 90
                repeat: true

                property real phase: 0

                onTriggered: {
                    phase += 0.45;
                    const bars = wave.children;
                    for (let i = 0; i < bars.length; i++) {
                        const b = bars[i];
                        if (b.target === undefined)
                            continue;
                        if (root.mode === "working") {
                            b.target = 10 + 14 * (1 + Math.sin(phase + i * 0.5)) / 2;
                        } else {
                            // Bell shape: taller in the middle, like a real equaliser.
                            const centre = 1 - Math.abs(i - bars.length / 2) / (bars.length / 2);
                            b.target = 6 + Math.random() * 46 * (0.35 + centre * 0.65);
                        }
                    }
                }
            }
        }
    }
}
