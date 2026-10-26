import QtQuick
import QtTest
import "../../ui"
import "../../Look.js" as Look
import "../../Touch.js" as Touch

// The channel lock's box in tablet mode (ui/LockBox.qml): a pad under the
// dots, each key what its key on a keyboard does (the digits typed, ⌫, OK
// as Enter), through the lock's own keys; the lock's buttons in the box (its
// shade covers the guide's); no pad without tablet mode. Tapped for real.
Item {
  id: top
  width: 1280; height: 800

  readonly property var retro: ({ text: "#f2f4ff", textDim: "#9fb0f0", accent: "#ffd23f", timeline: "#ff4d4d", cell: "#1b3591", cellBorder: "#3b5bd1", channelCell: "#0f2470", selected: "#ffd23f", selectedText: "#141414", header: "#ffd23f", headerText: "#141414", band: "#030a2b", bandText: "#ffd23f", infoPanel: "#40000000", preview: "#000000", alert: "#ff4d4d", bgTop: "#071447", bgBottom: "#030a2b", ltBg: "#eb081447", ltBorder: "#3b5bd1", ltNumber: "#ffd23f", ltChannel: "#9fb0f0", ltTitle: "#f2f4ff", ltProgress: "#ffd23f", ltTrack: "#1b3591", ltClock: "#f2f4ff", ltTime: "#ffd23f", cardBackdrop: "#d1000000", cardName: "#ffd23f", cardStatus: "#9fb0f0", cardFrame: "#3b5bd1", boxBg: "#071447", boxBorder: "#ffd23f", scrim: "#bf030a2b", keyFace: "#e4e9ff", keyText: "#0b1550", keyEdge: "#46559a", miniBar: "#eb030a2b" })

  // the lock, its keys recorded (what they'd do is ChannelLock.qml's, tested there)
  QtObject {
    id: lock
    property bool boxUp: true
    property bool typing: true
    property bool busy: false
    property bool authBusy: false
    property int wait: 0
    property string code: ""
    property string step: "enter"
    property string title: "Enter the passcode"
    property string prompt: "The channel lock's passcode."
    property string problem: ""
    property var rows: []
    property int cursor: 0
    property string rowNote: ""
    property var listed: []
    property int listCursor: 0
    property string query: ""
    property var keys: []
    property int canceled: 0
    readonly property var hints: [{ keys: ["0", "–", "9"], label: "Type" }, { keys: ["ESC"], label: "Cancel", touch: { key: Qt.Key_Escape, back: true } }]
    function key(event) { keys = keys.concat([event.text ? event.text : event.key === Qt.Key_Backspace ? "back" : event.key === Qt.Key_Return ? "ok" : "key " + event.key]) }
    function cancel() { canceled++ }
    function rowOn(k) { return false }
    function rowValue(k) { return "" }
  }
  QtObject {
    id: guide
    property bool touchMode: true
    property real fingerPx: 52
    property real u: 13
    property string dialog: "lockCode"
    property var touchMore: null
    readonly property var channelLock: lock
    readonly property var colors: top.retro
    readonly property var fonts: ({ body: "Sans", display: "Sans", mono: "Monospace" })
    readonly property var look: Look.resolve({}, {}, guide.colors, guide.fonts, {})
    readonly property var areaImages: ({})
    readonly property real touchKeyboardHeight: 0
    readonly property color ink: colors.text
    readonly property color dimInk: colors.textDim
    readonly property color marquee: colors.accent
    property var pressed: []
    function inkOn(c) { return "#141414" }
    function isFinger(mouse) { return guide.touchMode && Touch.byFinger(mouse) }
    function touchPress(t) { pressed = pressed.concat([t.key]); return true }
    function openTouchMore(list) {}
    function closeTouchMore() {}
    function showTouchKeyboard() {}
  }

  LockBox { id: box; guide: guide }

  TestCase {
    name: "LockPad"
    when: windowShown

    function init() { guide.touchMode = true; lock.keys = []; guide.pressed = []; wait(20) }
    function all(pred) {
      var out = [], stack = [box]
      while (stack.length) { var it = stack.pop(); if (pred(it)) out.push(it); for (var i = 0; i < it.children.length; i++) stack.push(it.children[i]) }
      return out
    }
    function button(label) { var b = all(function(x) { return x.label === label && x.tapped !== undefined && x.visible })[0]; verify(!!b, "a button " + label); return b }
    function tap(label) { var b = button(label); var t = touchEvent(b); t.press(0, b, b.width / 2, b.height / 2).commit(); t.release(0, b, b.width / 2, b.height / 2).commit() }

    function test_the_pad_types_as_the_keys() {
      tap("4"); tap("2"); tap("⌫"); tap("0"); tap("OK")
      compare(lock.keys, ["4", "2", "back", "0", "ok"], "each as its key does, through the lock's own keys")
      compare(button("⌫").accessibleName, "Backspace")
      verify(button("7").height >= guide.fingerPx, "a finger tall")
    }

    function test_its_buttons_in_the_box() {
      var cancel = all(function(x) { return x.label === "Cancel" && x.tapped !== undefined && x.visible })
      compare(cancel.length, 1, "Cancel, in the box")
      var c = cancel[0]
      var t = touchEvent(c); t.press(0, c, c.width / 2, c.height / 2).commit(); t.release(0, c, c.width / 2, c.height / 2).commit()
      compare(guide.pressed, [Qt.Key_Escape], "as Esc")
    }

    function test_no_pad_without_tablet_mode() {
      guide.touchMode = false
      wait(20)
      compare(all(function(x) { return x.label === "5" && x.tapped !== undefined && x.visible }).length, 0)
    }
  }
}
