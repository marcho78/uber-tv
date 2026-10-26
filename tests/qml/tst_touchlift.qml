import QtQuick
import QtTest
import "../../ui"
import "../../Look.js" as Look

// Tablet mode's keyboard keeps the field you type in above it
// (ui/TouchKeyboard.qml relift): on the smallest window (900x560), with the
// smallest and the biggest finger, a field low on a surface (a panel inside
// a screen, as an app's sign-in box or the style panel's) is lifted with its
// whole surface just above the keyboard, and put back when it goes; a field
// already above it doesn't move; Search's box brings back a hidden keyboard.
Item {
  id: top
  width: 900; height: 560

  readonly property var retro: ({ text: "#f2f4ff", textDim: "#9fb0f0", accent: "#ffd23f", timeline: "#ff4d4d", cell: "#1b3591", cellBorder: "#3b5bd1", channelCell: "#0f2470", selected: "#ffd23f", selectedText: "#141414", header: "#ffd23f", headerText: "#141414", band: "#030a2b", bandText: "#ffd23f", infoPanel: "#40000000", preview: "#000000", alert: "#ff4d4d", bgTop: "#071447", bgBottom: "#030a2b", ltBg: "#eb081447", ltBorder: "#3b5bd1", ltNumber: "#ffd23f", ltChannel: "#9fb0f0", ltTitle: "#f2f4ff", ltProgress: "#ffd23f", ltTrack: "#1b3591", ltClock: "#f2f4ff", ltTime: "#ffd23f", cardBackdrop: "#d1000000", cardName: "#ffd23f", cardStatus: "#9fb0f0", cardFrame: "#3b5bd1", boxBg: "#071447", boxBorder: "#ffd23f", scrim: "#bf030a2b", keyFace: "#e4e9ff", keyText: "#0b1550", keyEdge: "#46559a", miniBar: "#eb030a2b" })

  QtObject {
    id: guide
    property bool touchMode: true
    property real fingerPx: 44
    property string screen: "guide"
    property bool searchInResults: false
    property bool watching: false
    property string dialog: ""
    property var searched: []
    readonly property var colors: top.retro
    readonly property var fonts: ({ body: "Sans", display: "Sans", mono: "Monospace" })
    readonly property var look: Look.resolve({}, {}, guide.colors, guide.fonts, {})
    readonly property color marquee: colors.accent
    function inkOn(c) { return "#141414" }
    function searchType(c) { searched = searched.concat([c]) }
    function searchBackspace() {}
    function searchEnter() {}
    function showTouchKeyboard() { kb.hidden = false }   // (as Guide.qml's)
  }

  // a screen (a Loader's item, say) with a panel low on it, its field at the
  // bottom; and a field near the top of another surface
  Item {
    id: surface
    anchors.fill: parent
    Rectangle {
      id: panel
      x: 200; y: 330; width: 500; height: 200
      TextInput { id: low; x: 20; y: 150; width: 400; height: 36 }
    }
  }
  Item {
    id: upper
    anchors.fill: parent
    TextInput { id: high; x: 20; y: 30; width: 300; height: 36 }
  }
  Item { id: nowhere; focus: true }

  TouchKeyboard {
    id: kb
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    guide: guide
    screen: top
  }

  TestCase {
    name: "TouchLift"
    when: windowShown

    function init() { guide.touchMode = true; guide.screen = "guide"; nowhere.forceActiveFocus(); kb.hidden = false; wait(20) }
    function bottomOf(f) { return f.mapToItem(top, 0, f.height).y }

    function test_low_field_lifted_above_the_keyboard_data() { return [{ tag: "44 px finger", finger: 44 }, { tag: "72 px finger", finger: 72 }] }
    function test_low_field_lifted_above_the_keyboard(data) {
      guide.fingerPx = data.finger
      var unmoved = bottomOf(low)
      low.forceActiveFocus()
      tryVerify(function() { return kb.up && kb.lift > 0 }, 1000, "the keyboard's up and lifts")
      verify(kb.height > 200, "a real keyboard: " + kb.height)
      // (a new finger size: its keys settle first, the lift a frame after)
      tryVerify(function() { return bottomOf(low) <= top.height - kb.height }, 1000, "the field above the keyboard")
      compare(Math.round(bottomOf(low)), Math.round(unmoved - kb.lift), "its whole surface moved, by the lift")
      nowhere.forceActiveFocus()
      tryVerify(function() { return !kb.up && kb.lift === 0 }, 1000)
      compare(surface.transform.length, 0, "the surface put back as it was")
      compare(Math.round(bottomOf(low)), Math.round(unmoved), "where it was")
    }

    function test_a_field_above_the_keyboard_doesnt_move() {
      guide.fingerPx = 72
      var was = bottomOf(high)
      high.forceActiveFocus()
      tryVerify(function() { return kb.up }, 1000)
      wait(50)
      compare(kb.lift, 0)
      compare(bottomOf(high), was)
    }

    function test_from_one_field_to_another() {
      guide.fingerPx = 60
      low.forceActiveFocus()
      tryVerify(function() { return kb.lift > 0 }, 1000)
      high.forceActiveFocus()
      tryVerify(function() { return kb.lift === 0 && surface.transform.length === 0 }, 1000, "the first surface back when another field takes the keys")
    }

    function test_search_hide_then_its_box_brings_it_back() {
      guide.screen = "search"
      verify(kb.up)
      var hide = findChild(kb, "key:hide")
      mouseClick(hide, hide.width / 2, hide.height / 2)
      verify(!kb.up, "hidden")
      guide.showTouchKeyboard()    // Search's box, tapped (ui/SearchScreen.qml)
      verify(kb.up, "back")
      var w = findChild(kb, "key:w")
      mouseClick(w, w.width / 2, w.height / 2)
      compare(guide.searched, ["w"], "and it types")
    }
  }
}
