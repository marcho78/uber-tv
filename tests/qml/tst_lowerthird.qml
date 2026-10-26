import QtQuick
import QtTest
import "../../ui"
import "../../Look.js" as Look

// The channel banner in tablet mode (ui/LowerThird.qml, touchPx): its
// choices and the player controls up at once, the choices above the
// controls, each choice at least a finger, the controls' buttons a thumb's,
// the bar a finger along; tapped and dragged for real. Without tablet mode,
// the keys' sizes.
Item {
  id: top
  width: 1280; height: 800

  readonly property var retro: ({ text: "#f2f4ff", textDim: "#9fb0f0", accent: "#ffd23f", timeline: "#ff4d4d", cell: "#1b3591", cellBorder: "#3b5bd1", channelCell: "#0f2470", selected: "#ffd23f", selectedText: "#141414", header: "#ffd23f", headerText: "#141414", band: "#030a2b", bandText: "#ffd23f", infoPanel: "#40000000", preview: "#000000", alert: "#ff4d4d", bgTop: "#071447", bgBottom: "#030a2b", ltBg: "#eb081447", ltBorder: "#3b5bd1", ltNumber: "#ffd23f", ltChannel: "#9fb0f0", ltTitle: "#f2f4ff", ltProgress: "#ffd23f", ltTrack: "#1b3591", ltClock: "#f2f4ff", ltTime: "#ffd23f", cardBackdrop: "#d1000000", cardName: "#ffd23f", cardStatus: "#9fb0f0", cardFrame: "#3b5bd1", boxBg: "#071447", boxBorder: "#ffd23f", scrim: "#bf030a2b", keyFace: "#e4e9ff", keyText: "#0b1550", keyEdge: "#46559a", miniBar: "#eb030a2b" })
  readonly property var look: Look.resolve({}, {}, top.retro, ({ body: "Sans", display: "Sans", mono: "Monospace" }), {})

  property var did: []
  LowerThird {
    id: lt
    anchors.fill: parent
    look: top.look
    unit: 13
    number: "101"
    channel: "WeatherNation"
    title: "Severe Weather Coverage"
    clock: "7:22 PM"
    options: [{ key: "multiview", label: "Multiview", icon: "apps" }, { key: "mini", label: "Mini player", icon: "window" }, { key: "mute", label: "Mute", icon: "" }]
    optionFocus: 0
    controls: true
    controlsAt: 0.5
    touchPx: 48
    onOptionPicked: function(i) { top.did = top.did.concat(["option " + i]) }
    onControlsPicked: function(what) { top.did = top.did.concat([what]) }
    onControlsPressed: function(f) { top.did = top.did.concat(["press"]) }
    onControlsMoved: function(f) { top.did = top.did.concat(["move"]) }
    onControlsReleased: top.did = top.did.concat(["release"])
  }

  TestCase {
    name: "LowerThirdTouch"
    when: windowShown

    function init() { top.did = []; lt.touchPx = 48; wait(20) }
    function all(pred) {
      var out = [], stack = [lt]
      while (stack.length) { var it = stack.pop(); if (pred(it)) out.push(it); for (var i = 0; i < it.children.length; i++) stack.push(it.children[i]) }
      return out
    }
    function tapAt(item, x, y) { var t = touchEvent(item); t.press(0, item, x, y).commit(); t.release(0, item, x, y).commit() }
    function buttons() { return all(function(x) { return x.Accessible.role === Accessible.Button && x.modelData && x.modelData.what }).sort(function(a, b) { return a.mapToItem(top, 0, 0).x - b.mapToItem(top, 0, 0).x }) }
    function options() { return all(function(x) { return x.inside !== undefined && x.modelData && x.modelData.label !== undefined }).sort(function(a, b) { return a.index - b.index }) }

    function test_finger_sizes_and_the_choices_above_the_controls() {
      var b = buttons()
      compare(b.length, 3, "back 30 s, pause, forward 30 s")
      for (var i = 0; i < b.length; i++) verify(b[i].width >= 60 && b[i].height >= 60, "a thumb's: " + b[i].width)
      compare(b.map(function(x) { return x.Accessible.name }), ["Back 30 seconds", "Pause", "Forward 30 seconds"])
      var o = options()
      compare(o.length, 3)
      for (var k = 0; k < o.length; k++) verify(o[k].height >= 48 && o[k].width >= 48, "a finger: " + o[k].width + "x" + o[k].height)
      var box = b[0].parent.parent   // the controls' box
      verify(o[0].mapToItem(top, 0, o[0].height).y <= box.mapToItem(top, 0, 0).y, "the choices end above the controls")
    }

    function test_tapped_and_dragged() {
      var b = buttons()
      tapAt(b[0], b[0].width / 2, b[0].height / 2)
      tapAt(b[1], b[1].width / 2, b[1].height / 2)
      var o = options()
      tapAt(o[1], o[1].width / 2, o[1].height / 2)
      compare(top.did, ["back", "pause", "option 1"])
      top.did = []
      // along the bar: a finger 20 px off its line still takes it
      var bar = all(function(x) { return x.preventStealing === true })[0]
      var c = bar.mapToItem(top, bar.width / 2, bar.height / 2)
      var t = touchEvent(top)
      t.press(0, top, c.x, c.y - 20).commit()
      t.move(0, top, c.x + 30, c.y - 20).commit()
      t.move(0, top, c.x + 60, c.y - 20).commit()
      t.release(0, top, c.x + 60, c.y - 20).commit()
      compare(top.did[0], "press", "a finger 20 px off the line takes the bar")
      verify(top.did.indexOf("move") > 0 && top.did[top.did.length - 1] === "release", JSON.stringify(top.did))
    }

    function test_the_keys_sizes_without_tablet_mode() {
      lt.touchPx = 0
      wait(20)
      var b = buttons()
      verify(b[0].width < 40, "the keys' size: " + b[0].width)
    }
  }
}
