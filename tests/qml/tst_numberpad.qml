import QtQuick
import QtTest
import "../../ui"

// Tablet mode's number pad (123, ui/NumberPad.qml), tapped: the digits as
// typed, ⌫ takes one back, five at most; Watch is dim and does nothing until
// they're a channel's number, then watches that channel (as Enter does); a
// tap on the shade closes it, a tap between its keys doesn't; it starts
// empty each time; it's there only in tablet mode.
Item {
  id: top
  width: 900; height: 600

  QtObject {
    id: guide
    property bool touchMode: true
    property bool numberPad: true
    property real fingerPx: 48
    property var numbers: [1, 2, 3, 101, 102, 205]
    property var watched: []
    property int closed: 0
    readonly property var colors: ({ scrim: "#bf030a2b", boxBg: "#071447", boxBorder: "#ffd23f", cellBorder: "#3b5bd1" })
    readonly property var fonts: ({ body: "Sans" })
    readonly property color marquee: "#ffd23f"
    readonly property color ink: "#f2f4ff"
    function inkOn(c) { return "#141414" }
    function closeNumberPad() { closed++; numberPad = false }
    function numberWatch(r) { watched = watched.concat([r]); numberPad = false }
  }

  NumberPad {
    id: pad
    anchors.fill: parent
    guide: guide
  }

  TestCase {
    name: "NumberPad"
    when: windowShown

    function init() { guide.touchMode = true; guide.numberPad = true; guide.watched = []; guide.closed = 0; pad.typed = ""; wait(10) }

    function button(label) {
      var stack = [pad]
      while (stack.length) {
        var it = stack.pop()
        if (it.label === label && it.tapped !== undefined) return it
        for (var i = 0; i < it.children.length; i++) stack.push(it.children[i])
      }
      fail("no button " + label)
    }
    function tap(label) { var b = button(label); mouseClick(b, b.width / 2, b.height / 2) }

    function test_digits_and_watch() {
      tap("1"); tap("0"); tap("2")
      compare(pad.typed, "102")
      compare(pad.row, 4, "channel 102's row")
      compare(button("Watch").opacity, 1)
      tap("Watch")
      compare(guide.watched, [4], "watched as Enter does")
    }

    function test_not_a_channel_yet() {
      tap("9")
      compare(pad.row, -1)
      compare(button("Watch").opacity, 0.4, "dim")
      tap("Watch")
      compare(guide.watched, [], "nothing to watch")
      verify(guide.numberPad, "still open")
    }

    function test_backspace_and_five_at_most() {
      tap("2"); tap("0"); tap("5"); tap("⌫")
      compare(pad.typed, "20")
      for (var i = 0; i < 6; i++) tap("7")
      compare(pad.typed, "20777", "five digits at most")
      compare(button("⌫").accessibleName, "Backspace")
    }

    function test_shade_closes_the_panel_doesnt() {
      var b = button("5")
      mouseClick(pad, 10, 10)
      compare(guide.closed, 1, "a tap on the shade closes it")
      guide.numberPad = true
      wait(10)
      var panel = b.parent.parent   // the panel, around the grid
      mouseClick(panel, 2, 2)
      compare(guide.closed, 1, "a tap between the keys doesn't")
    }

    function test_starts_empty() {
      tap("3")
      guide.numberPad = false
      wait(10)
      guide.numberPad = true
      wait(10)
      compare(pad.typed, "", "empty again")
    }

    function test_only_in_tablet_mode() {
      verify(pad.visible)
      guide.touchMode = false
      verify(!pad.visible)
    }
  }
}
