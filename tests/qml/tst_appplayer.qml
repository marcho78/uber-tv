import QtQuick
import QtTest
import "../../ui"
import "../../Look.js" as Look
import "../../Touch.js" as Touch

// An app's video in tablet mode (ui/AppPlayer.qml), for real: a finger
// along the bar goes there when it lets go; a mouse's press on the bar is
// the picture's, as before (a click pauses, nothing seeks), tablet mode on
// or not; a finger's tap shows or hides the bar, a mouse's click pauses.
Item {
  id: top
  width: 1280; height: 720

  readonly property var retro: ({ text: "#f2f4ff", textDim: "#9fb0f0", accent: "#ffd23f", timeline: "#ff4d4d", cell: "#1b3591", cellBorder: "#3b5bd1", channelCell: "#0f2470", selected: "#ffd23f", selectedText: "#141414", header: "#ffd23f", headerText: "#141414", band: "#030a2b", bandText: "#ffd23f", infoPanel: "#40000000", preview: "#000000", alert: "#ff4d4d", bgTop: "#071447", bgBottom: "#030a2b", ltBg: "#eb081447", ltBorder: "#3b5bd1", ltNumber: "#ffd23f", ltChannel: "#9fb0f0", ltTitle: "#f2f4ff", ltProgress: "#ffd23f", ltTrack: "#1b3591", ltClock: "#f2f4ff", ltTime: "#ffd23f", cardBackdrop: "#d1000000", cardName: "#ffd23f", cardStatus: "#9fb0f0", cardFrame: "#3b5bd1", boxBg: "#071447", boxBorder: "#ffd23f", scrim: "#bf030a2b", keyFace: "#e4e9ff", keyText: "#0b1550", keyEdge: "#46559a", miniBar: "#eb030a2b" })

  QtObject {
    id: pb
    property var session: ({ app: "tv.example.app", title: "A video", subtitle: "", live: false })
    property bool paused: false
    property real position: 100
    property real duration: 1000
    property bool buffering: false
    property string error: ""
    property bool closing: false
    property var videoOutput: null
    property int toggled: 0
    property var seeks: []
    function togglePause() { toggled++ }
    function seekTo(s) { seeks = seeks.concat([Math.round(s)]) }
  }
  QtObject {
    id: guide
    property bool touchMode: true
    property real fingerPx: 52
    property real u: 13
    property bool showKeyHints: true
    property bool muted: false
    property var touchMore: null
    readonly property var appPlayback: pb
    readonly property var apps: ({ record: function(id) { return { name: "Example" } } })
    readonly property string fontFamily: "Sans"
    readonly property var colors: top.retro
    readonly property var fonts: ({ body: "Sans", display: "Sans", mono: "Monospace" })
    readonly property var look: Look.resolve({}, {}, guide.colors, guide.fonts, {})
    readonly property color ink: colors.text
    readonly property color marquee: colors.accent
    function inkOn(c) { return "#141414" }
    function isFinger(mouse) { return guide.touchMode && Touch.byFinger(mouse) }
    function touchPress(t) { return true }
    function openTouchMore(l) {}
    function closeTouchMore() {}
  }

  AppPlayer { id: player; anchors.fill: parent; guide: guide }

  TestCase {
    name: "AppPlayerTouch"
    when: windowShown

    function init() { guide.touchMode = true; pb.toggled = 0; pb.seeks = []; player.poke(); wait(20) }
    function track() {
      var stack = [player]
      while (stack.length) {
        var it = stack.pop()
        if (it.preventStealing === true) return it
        for (var i = 0; i < it.children.length; i++) stack.push(it.children[i])
      }
      return null
    }

    function test_a_finger_along_the_bar_goes_there() {
      var t = track()
      verify(t && t.enabled, "the bar takes a finger")
      var c = t.mapToItem(top, t.width / 2, t.height / 2)
      var e = touchEvent(top)
      e.press(0, top, c.x - t.width * 0.25, c.y).commit()
      e.move(0, top, c.x, c.y).commit()
      e.release(0, top, c.x, c.y).commit()
      compare(pb.seeks.length, 1, "it went there")
      verify(Math.abs(pb.seeks[0] - 500) < 30, "the middle of a 1000 s video: " + pb.seeks[0])
      compare(pb.toggled, 0, "no pause")
    }

    function test_a_mouse_on_the_bar_pauses_as_before() {
      var t = track()
      var c = t.mapToItem(top, t.width / 2, t.height / 2)
      mouseClick(top, c.x, c.y)
      compare(pb.seeks.length, 0, "a mouse doesn't seek, tablet mode on")
      compare(pb.toggled, 1, "its click pauses, as before")
    }

    function test_a_finger_shows_and_hides_the_bar() {
      player.barShown = true
      var e = touchEvent(top)
      e.press(0, top, 600, 200).commit(); e.release(0, top, 600, 200).commit()
      verify(!player.barShown, "a tap: the bar away")
      compare(pb.toggled, 0, "no pause")
      wait(400)
      e = touchEvent(top)
      e.press(0, top, 600, 200).commit(); e.release(0, top, 600, 200).commit()
      verify(player.barShown, "a tap again: the bar")
    }
  }
}
