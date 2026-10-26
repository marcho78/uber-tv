import QtQuick
import QtTest
import "../../ui"
import "../../Look.js" as Look

// Tablet mode's keyboard (ui/TouchKeyboard.qml) against a stand-in guide: up
// only with the touch controls on and a text field with the keys (or Search
// taking what's typed); letters typed where the cursor is, Shift for one
// capital, ⌫ (a selection first), ?123 and ABC, the field's own length, its
// textEdited as for keys; Done runs what Enter does there (enterKey, or
// accepted); Hide puts it away until that field is tapped again; in Search
// the letters, ⌫ and Search go to Search; Paste; every key a finger tall and
// pressed by a screen reader as by a finger.
Item {
  id: top
  width: 900; height: 700

  readonly property var retro: ({ text: "#f2f4ff", textDim: "#9fb0f0", accent: "#ffd23f", timeline: "#ff4d4d", cell: "#1b3591", cellBorder: "#3b5bd1", channelCell: "#0f2470", selected: "#ffd23f", selectedText: "#141414", header: "#ffd23f", headerText: "#141414", band: "#030a2b", bandText: "#ffd23f", infoPanel: "#40000000", preview: "#000000", alert: "#ff4d4d", bgTop: "#071447", bgBottom: "#030a2b", ltBg: "#eb081447", ltBorder: "#3b5bd1", ltNumber: "#ffd23f", ltChannel: "#9fb0f0", ltTitle: "#f2f4ff", ltProgress: "#ffd23f", ltTrack: "#1b3591", ltClock: "#f2f4ff", ltTime: "#ffd23f", cardBackdrop: "#d1000000", cardName: "#ffd23f", cardStatus: "#9fb0f0", cardFrame: "#3b5bd1", boxBg: "#071447", boxBorder: "#ffd23f", scrim: "#bf030a2b", keyFace: "#e4e9ff", keyText: "#0b1550", keyEdge: "#46559a", miniBar: "#eb030a2b" })

  QtObject {
    id: guide
    property bool touchMode: true
    property real fingerPx: 56
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
    function searchBackspace() { searched = searched.concat(["⌫"]) }
    function searchEnter() { searched = searched.concat(["enter"]) }
  }

  property int entered: 0
  property int accepted: 0
  property int edits: 0

  // a field whose Enter is its own function, and one with only accepted
  TextInput {
    id: named
    x: 20; y: 20; width: 300; height: 40
    maximumLength: 8
    function enterKey() { top.entered++ }
    onTextEdited: top.edits++
  }
  TextInput { id: plainField; x: 20; y: 80; width: 300; height: 40; onAccepted: top.accepted++ }
  TextInput { id: source; x: 400; y: 20; width: 200; height: 40; text: "pasted" }
  Item { id: nowhere; focus: true }

  TouchKeyboard {
    id: kb
    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
    guide: guide
    screen: top
  }

  TestCase {
    name: "TouchKeyboard"
    when: windowShown

    function init() {
      guide.touchMode = true; guide.screen = "guide"; guide.searched = []
      top.entered = 0; top.accepted = 0; top.edits = 0
      named.text = ""; plainField.text = ""
      nowhere.forceActiveFocus()
      kb.hidden = false; kb.numbers = false; kb.shift = false
    }
    // a key by its layout and name: "q" (letters), "sign:1" (?123)
    function key(name) { var n = name.indexOf(":") > 0 ? name : "key:" + name; var k = findChild(kb, n); verify(k && k.visible !== false, "a key " + n); return k }
    function tap(name) { var k = key(name); mouseClick(k, k.width / 2, k.height / 2) }

    function test_only_with_a_field_and_the_touch_controls() {
      verify(!kb.up && kb.height === 0, "nothing to type in: down")
      named.forceActiveFocus()
      verify(kb.up && kb.height > 0, "a field with the keys: up")
      guide.touchMode = false
      verify(!kb.up, "no touch controls: down")
    }

    function test_typing_shift_and_backspace() {
      named.forceActiveFocus()
      waitForRendering(kb)
      tap("h"); tap("i")
      compare(named.text, "hi")
      tap("shift"); tap("a"); tap("b")
      compare(named.text, "hiAb", "Shift: one capital")
      tap("back")
      compare(named.text, "hiA")
      named.select(0, 2)
      tap("back")
      compare(named.text, "A", "a selection goes first")
      verify(top.edits >= 5, "each edit is the field's textEdited, as keys: " + top.edits)
    }

    function test_numbers_and_the_fields_length() {
      named.forceActiveFocus()
      tap("numbers"); tap("sign:1"); tap("sign:@")
      tap("sign:letters"); tap("x")
      compare(named.text, "1@x")
      for (var i = 0; i < 10; i++) tap("y")
      compare(named.text.length, 8, "never past the field's own length")
    }

    function test_done_is_the_fields_enter() {
      named.forceActiveFocus()
      tap("enter")
      compare(top.entered, 1, "enterKey: what Enter does in that field")
      plainField.forceActiveFocus()
      tap("enter")
      compare(top.accepted, 1, "else its accepted")
    }

    function test_hide_until_the_field_is_tapped_again() {
      named.forceActiveFocus()
      tap("hide")
      verify(!kb.up, "Hide puts it away")
      kb.tappedAt(Qt.point(named.x + 10, named.y + 10))
      verify(kb.up, "a tap on that field brings it back")
      tap("hide")
      kb.tappedAt(Qt.point(500, 300))
      verify(!kb.up, "a tap elsewhere doesn't")
      plainField.forceActiveFocus()
      verify(kb.up, "another field: up again")
    }

    function test_search_takes_the_letters() {
      guide.screen = "search"
      verify(kb.up, "Search, nothing focused: up")
      tap("w"); tap("back"); tap("enter")
      compare(guide.searched, ["w", "⌫", "enter"])
      guide.searchInResults = true
      verify(!kb.up, "in the results: down")
      guide.searchInResults = false
    }

    function test_changing_layouts_remakes_no_key() {
      named.forceActiveFocus()
      var q = key("q")
      tap("numbers")
      tap("sign:letters")
      verify(key("q") === q, "the same key: nothing remade under a finger")
      tap("numbers"); tap("sign:7")
      compare(named.text, "7", "the first tap after a change lands on its key")
    }

    function test_paste() {
      source.selectAll(); source.copy()
      named.forceActiveFocus()
      tap("paste")
      compare(named.text, "pasted")
    }

    function test_finger_sized_and_screen_readers() {
      named.forceActiveFocus()
      var k = key("q")
      verify(k.height >= guide.fingerPx, "a finger tall: " + k.height)
      compare(key("back").Accessible.name, "Backspace")
      key("q").Accessible.pressAction()
      compare(named.text, "q", "a screen reader's press types as a tap")
    }
  }
}
