import QtQuick
import QtTest
import "../../ui"
import "../../Look.js" as Look

// A Settings row in tablet mode (ui/MenuRow.qml): at least a finger tall; on
// a choice whose user handles them (touchParts), ‹ and › are their own
// targets, a finger's width round each, and the rest of the row is the row;
// a switch that also opens has its switch apart; a row whose user doesn't
// handle them (no touchParts) is one target as before, its arrows only where
// the keys show them.
Item {
  id: top
  width: 900; height: 500

  readonly property var retro: ({ text: "#f2f4ff", textDim: "#9fb0f0", accent: "#ffd23f", timeline: "#ff4d4d", cell: "#1b3591", cellBorder: "#3b5bd1", channelCell: "#0f2470", selected: "#ffd23f", selectedText: "#141414", header: "#ffd23f", headerText: "#141414", band: "#030a2b", bandText: "#ffd23f", infoPanel: "#40000000", preview: "#000000", alert: "#ff4d4d", bgTop: "#071447", bgBottom: "#030a2b", ltBg: "#eb081447", ltBorder: "#3b5bd1", ltNumber: "#ffd23f", ltChannel: "#9fb0f0", ltTitle: "#f2f4ff", ltProgress: "#ffd23f", ltTrack: "#1b3591", ltClock: "#f2f4ff", ltTime: "#ffd23f", cardBackdrop: "#d1000000", cardName: "#ffd23f", cardStatus: "#9fb0f0", cardFrame: "#3b5bd1", boxBg: "#071447", boxBorder: "#ffd23f", scrim: "#bf030a2b", keyFace: "#e4e9ff", keyText: "#0b1550", keyEdge: "#46559a", miniBar: "#eb030a2b" })

  QtObject {
    id: guide
    property bool touchMode: true
    property real fingerPx: 60
    property real u: 10          // a small screen: a row under a finger without tablet mode
    readonly property var colors: top.retro
    readonly property var fonts: ({ body: "Sans", display: "Sans", mono: "Monospace" })
    readonly property var look: Look.resolve({}, {}, guide.colors, guide.fonts, {})
    readonly property color ink: colors.text
    readonly property color dimInk: colors.textDim
    readonly property color marquee: colors.accent
  }

  property var did: []

  MenuRow {
    id: choice
    y: 10; width: 800; height: implicitHeight
    guide: guide
    label: "Card size"
    kind: "choice"
    value: "Medium"
    touchParts: true
    onActivated: top.did = top.did.concat(["row"])
    onStepped: function(dir) { top.did = top.did.concat([dir < 0 ? "less" : "more"]) }
  }
  MenuRow {
    id: plain
    y: 120; width: 800; height: implicitHeight
    guide: guide
    label: "Unlocks last"
    kind: "choice"
    value: "10 minutes"
    onActivated: top.did = top.did.concat(["plain"])
    onStepped: function(dir) { top.did = top.did.concat(["plain step"]) }
  }
  MenuRow {
    id: sw
    y: 230; width: 800; height: implicitHeight
    guide: guide
    label: "Trending"
    kind: "switch"
    more: true
    on: true
    touchParts: true
    onActivated: top.did = top.did.concat(["options"])
    onStepped: function(dir) {}
    onToggled: top.did = top.did.concat(["switch"])
  }

  TestCase {
    name: "MenuRowTouch"
    when: windowShown

    function init() { top.did = []; guide.touchMode = true }

    // the middle of a part of a row, in the row
    function at(row, id) {
      var part = findChild(row, id)
      return part.mapToItem(row, part.width / 2, part.height / 2)
    }

    function test_a_finger_tall() {
      verify(choice.height >= guide.fingerPx, "at least a finger: " + choice.height)
      guide.touchMode = false
      verify(choice.height < guide.fingerPx, "the keyboard's size again: " + choice.height)
    }

    function test_a_choice_steps_both_ways_and_the_rest_is_the_row() {
      var l = at(choice, "leftArrow"), r = at(choice, "rightArrow")
      verify(findChild(choice, "leftArrow").visible && findChild(choice, "rightArrow").visible, "‹ › shown, not only on the focused row")
      mouseClick(choice, r.x, r.y)
      mouseClick(choice, l.x, l.y)
      mouseClick(choice, r.x - guide.fingerPx * 0.4, r.y)
      mouseClick(choice, 40, choice.height / 2)
      compare(top.did, ["more", "less", "more", "row"], "› steps up, ‹ down (a finger's width round each), the label is the row")
    }

    function test_a_row_without_parts_is_one_target() {
      verify(!findChild(plain, "leftArrow").visible, "no ‹ unless focused, as with the keys")
      mouseClick(plain, plain.width - 30, plain.height / 2)
      mouseClick(plain, 40, plain.height / 2)
      compare(top.did, ["plain", "plain"], "anywhere: the row (never a dead arrow)")
    }

    function test_a_switch_that_opens_has_its_switch_apart() {
      var t = at(sw, "toggle")
      mouseClick(sw, t.x, t.y)
      mouseClick(sw, 40, sw.height / 2)
      compare(top.did, ["switch", "options"])
    }

    function test_with_the_keyboard_its_one_row_as_before() {
      guide.touchMode = false
      wait(50)
      mouseClick(choice, choice.width / 2, choice.height / 2)
      compare(top.did, ["row"], "no parts without the touch controls")
    }
  }
}
