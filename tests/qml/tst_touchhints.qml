import QtQuick
import QtTest
import "../../ui"

// Tablet mode's buttons (ui/KeyHints.qml, ui/TouchButton.qml,
// ui/TouchMore.qml) against a stand-in guide: with a keyboard the hints are
// keycaps as before; with the touch controls on, Back comes first, then the
// hints with their own touch key, then the words with no key; what a finger
// does itself (↑ ↓) is no button; past the room the rest go under ⋯; a tap
// runs a button's own touch (once), ⋯ opens the panel, a tap there runs one,
// the shade closes it. Each button is at least a finger tall and wide.
Item {
  id: top
  width: 1200; height: 700

  QtObject {
    id: guide
    property bool touchMode: false
    property real fingerPx: 56
    property var colors: ({ boxBg: "#10131f", cellBorder: "#2d3450", boxBorder: "#82fb9c", scrim: "#c006060c" })
    property color marquee: "#82fb9c"
    property color ink: "#ddf7ff"
    property var fonts: ({ body: "monospace" })
    property var touchMore: null
    property var pressed: []
    property var look: ({ keycap: { fill: "#e6eef6", depth: 0.08 }, keyLabel: { text: { color: "#b5c5db" } } })
    function inkOn(c) { return "#0b0c16" }
    function touchPress(t) { pressed = pressed.concat([t]); touchMore = null; return true }
    function openTouchMore(list) { touchMore = Array.isArray(list) && list.length ? list : null }
    function closeTouchMore() { touchMore = null }
  }

  readonly property var footer: [
    { keys: ["↑", "↓"], label: "Channel" },
    { keys: ["←", "→"], label: "Program" },
    { keys: ["ENTER"], label: "Watch", touch: { key: Qt.Key_Return, primary: true } },
    { keys: ["V"], label: "Library", touch: { key: Qt.Key_V } },
    { keys: ["/"], label: "Search", touch: { key: Qt.Key_Slash, icon: "search" } },
    { keys: ["P"], label: "Mini player", touch: { key: Qt.Key_P } },
    { keys: ["S"], label: "Style", touch: { key: Qt.Key_S } },
    { keys: [","], label: "Settings", touch: { key: Qt.Key_Comma } },
    { keys: ["?"], label: "All keys" },
    { keys: ["←"], label: "Nav rail", touchOnly: true, touch: { run: function() {}, icon: "menu" } },
    { keys: ["ESC"], label: "Home", touch: { key: Qt.Key_Escape, back: true } },
    { keys: [], label: "Checking it…" }
  ]

  Rectangle { anchors.fill: parent; color: "#06060c" }

  KeyHints {
    id: hints
    x: 20; y: 20
    touchGuide: guide
    model: top.footer
    size: 24
    touchWidth: 1160
    labelStyle: ({ text: { color: "#b5c5db" } })
  }

  // a hint row as most screens have one: no touchGuide, its styles from the
  // screen's own guide property (KeyHints' own properties mustn't hide it,
  // as they would a screen's property; an id would win anyway)
  component ScreenLike: Item {
    property var guide: null
    property alias row: plainRow
    KeyHints {
      id: plainRow
      model: [{ keys: ["ENTER"], label: "Watch" }]
      capStyle: guide ? guide.look.keycap : undefined
      labelStyle: guide ? guide.look.keyLabel : undefined
    }
  }
  ScreenLike { id: screenLike; y: 120; guide: guide }

  TouchMore {
    id: morePanel
    anchors.fill: parent
    guide: guide
  }

  TestCase {
    name: "TouchHints"
    when: windowShown

    function init() {
      guide.touchMode = false; guide.touchMore = null; guide.pressed = []
      hints.touchWidth = 1160
    }

    // the touch buttons in the row, in order (Back's and ⋯'s from their loaders)
    function buttons() {
      var out = []
      for (var i = 0; i < hints.children.length; i++) {
        var c = hints.children[i]
        if (!c.visible) continue
        var b = c.item !== undefined ? c.item : c
        if (b && b.hasOwnProperty("primary") && b.hasOwnProperty("lit")) out.push(b)
      }
      out.sort(function(a, b) { return a.mapToItem(top, 0, 0).x - b.mapToItem(top, 0, 0).x })
      return out
    }
    function labels() { return buttons().map(function(b) { return b.label || ("[" + b.icon + "]") }) }

    function test_a_row_without_touch_keeps_the_outer_guides_styles() {
      compare(screenLike.row.capStyle, guide.look.keycap, "guide there is the screen's, not KeyHints' own")
      compare(screenLike.row.labelStyle, guide.look.keyLabel)
      guide.touchMode = true
      waitForRendering(screenLike)
      verify(!screenLike.row.touching, "no touchGuide: keycaps even with the touch controls on")
    }

    function test_a_keyboard_sees_keycaps_as_before() {
      compare(buttons().length, 0, "no buttons")
      verify(hints.implicitWidth > 0)
      // the keycap rows: every hint but a touch-only one (Nav rail's button)
      var rows = 0
      for (var i = 0; i < hints.children.length; i++) if (hints.children[i].hasOwnProperty("modelData") && hints.children[i].visible) rows++
      compare(rows, top.footer.length - 1, "Nav rail's button is no key")
    }

    function test_touch_back_first_then_its_buttons() {
      guide.touchMode = true
      waitForRendering(hints)
      compare(labels(), ["Home", "Watch", "Library", "Search", "Mini player", "Style", "Settings", "Nav rail"], "Back first; ↑ ↓, ← → and All keys are no buttons")
      var b = buttons()
      compare(b[0].icon, "back")
      verify(b[1].primary, "Watch is the main one")
      for (var i = 0; i < b.length; i++) {
        verify(b[i].height >= guide.fingerPx && b[i].width >= guide.fingerPx, b[i].label + " is finger-sized: " + b[i].width + "x" + b[i].height)
      }
      var shot = grabImage(hints)
      shot.save("/tmp/claude-1000/-home-marcho-projects-omarchy-plugins-om-pg/7ff86474-6d7f-4124-92be-1bc5de7b1344/scratchpad/touch-row-wide.png")
    }

    function test_a_tap_runs_its_own_touch_once() {
      guide.touchMode = true
      waitForRendering(hints)
      var watch = buttons()[1]
      var t = touchEvent(top)
      var p = watch.mapToItem(top, watch.width / 2, watch.height / 2)
      t.press(0, top, p.x, p.y).commit()
      compare(guide.pressed.length, 0, "nothing until the finger lets go")
      t.release(0, top, p.x, p.y).commit()
      compare(guide.pressed.length, 1, "once")
      compare(guide.pressed[0].key, Qt.Key_Return, "Watch's own key, not what it shows")
      mouseClick(buttons()[0])
      compare(guide.pressed[1].back, true, "Back's own touch")
    }

    function test_a_finger_that_slides_off_runs_nothing() {
      guide.touchMode = true
      waitForRendering(hints)
      var lib = buttons()[2]
      var p = lib.mapToItem(top, lib.width / 2, lib.height / 2)
      var t = touchEvent(top)
      t.press(0, top, p.x, p.y).commit()
      t.move(0, top, p.x, p.y + 200).commit()
      t.release(0, top, p.x, p.y + 200).commit()
      compare(guide.pressed.length, 0, "let go off it: nothing")
    }

    function test_past_the_room_the_rest_go_under_more() {
      guide.touchMode = true
      hints.touchWidth = 620
      waitForRendering(hints)
      var l = labels()
      compare(l[0], "Home")
      compare(l[l.length - 1], "[more]", "⋯ last")
      verify(hints.implicitWidth <= 620 + 1, "the row stays in its room: " + hints.implicitWidth)
      var shown = l.slice(1, l.length - 1)
      compare(shown.concat(hints.touchRest.map(function(h) { return h.label })), ["Watch", "Library", "Search", "Mini player", "Style", "Settings", "Nav rail"], "nothing lost: shown, then under ⋯")
      var shot = grabImage(hints)
      shot.save("/tmp/claude-1000/-home-marcho-projects-omarchy-plugins-om-pg/7ff86474-6d7f-4124-92be-1bc5de7b1344/scratchpad/touch-row-narrow.png")
      mouseClick(buttons()[buttons().length - 1])
      compare(guide.touchMore.length, hints.touchRest.length, "⋯ opens the panel with the rest")
      waitForRendering(morePanel)
      verify(morePanel.visible)
      var shot2 = grabImage(top)
      shot2.save("/tmp/claude-1000/-home-marcho-projects-omarchy-plugins-om-pg/7ff86474-6d7f-4124-92be-1bc5de7b1344/scratchpad/touch-more.png")
    }

    function test_the_panel_runs_one_and_its_shade_closes_it() {
      guide.touchMode = true
      guide.openTouchMore([{ label: "Style", touch: { key: Qt.Key_S } }, { label: "Settings", touch: { key: Qt.Key_Comma } }])
      waitForRendering(morePanel)
      var grid = findChild(morePanel, "")
      var found = []
      function walk(it) { for (var i = 0; i < it.children.length; i++) { var c = it.children[i]; if (c.hasOwnProperty("lit") && c.visible) found.push(c); walk(c) } }
      walk(morePanel)
      compare(found.length, 2)
      mouseClick(found[1])
      compare(guide.pressed[0].key, Qt.Key_Comma, "a tap in the panel runs that one")
      compare(guide.touchMore, null, "and closes it")
      guide.openTouchMore([{ label: "Style", touch: { key: Qt.Key_S } }])
      mouseClick(morePanel, 10, 10)
      compare(guide.touchMore, null, "the shade closes it")
      compare(guide.pressed.length, 1, "running nothing")
    }
  }
}
