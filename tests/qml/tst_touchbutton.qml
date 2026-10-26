import QtQuick
import QtTest
import "../../ui"
import "../../Look.js" as Look

// Tablet mode's button (ui/TouchButton.qml) styled by the touch button
// element (Look.js): Retro's colors by default (the box's fill, the cell
// border, the accent for the primary one); a theme's fill (a gradient too),
// border, its width, corners, text color and text size reach it; its words
// go through the guide's readability (textOn); and whatever the theme, it
// stays a finger tall.
Item {
  id: top
  width: 600; height: 300

  readonly property var retro: ({ text: "#f2f4ff", textDim: "#9fb0f0", accent: "#ffd23f", timeline: "#ff4d4d", cell: "#1b3591", cellBorder: "#3b5bd1", channelCell: "#0f2470", selected: "#ffd23f", selectedText: "#141414", header: "#ffd23f", headerText: "#141414", band: "#030a2b", bandText: "#ffd23f", infoPanel: "#40000000", preview: "#000000", alert: "#ff4d4d", bgTop: "#071447", bgBottom: "#030a2b", ltBg: "#eb081447", ltBorder: "#3b5bd1", ltNumber: "#ffd23f", ltChannel: "#9fb0f0", ltTitle: "#f2f4ff", ltProgress: "#ffd23f", ltTrack: "#1b3591", ltClock: "#f2f4ff", ltTime: "#ffd23f", cardBackdrop: "#d1000000", cardName: "#ffd23f", cardStatus: "#9fb0f0", cardFrame: "#3b5bd1", boxBg: "#071447", boxBorder: "#ffd23f", scrim: "#bf030a2b", keyFace: "#e4e9ff", keyText: "#0b1550", keyEdge: "#46559a", miniBar: "#eb030a2b" })

  QtObject {
    id: guide
    property real fingerPx: 50
    property var overrides: ({})
    property var asked: []
    readonly property var colors: top.retro
    readonly property var fonts: ({ body: "Sans", display: "Sans", mono: "Monospace" })
    readonly property var look: Look.resolve({}, guide.overrides, guide.colors, guide.fonts, {})
    readonly property color marquee: colors.accent
    readonly property color ink: colors.text
    function inkOn(c) { return "#141414" }
    // (the guide's own picks a readable color; here it says what it was asked)
    function textOn(fill, normal) { asked = asked.concat([String(fill) + " " + String(normal)]); return String(fill) === "#ffd23f" ? "#141414" : normal }
  }

  TouchButton { id: plain; x: 20; y: 20; guide: guide; label: "Library" }
  TouchButton { id: main; x: 20; y: 120; guide: guide; label: "Watch"; primary: true }

  TestCase {
    name: "TouchButtonStyle"
    when: windowShown

    function init() { guide.overrides = ({}); guide.asked = []; guide.fingerPx = 50; wait(10) }
    function face(b) { return b.children[0] }     // its Rectangle
    function words(b) { var row = b.children[1]; return row.children[1] }   // the Label in its Row

    function test_retros_by_default() {
      compare(String(face(plain).color), "#071447", "the box's fill")
      compare(String(face(plain).border.color), "#3b5bd1", "the cell border")
      compare(face(plain).border.width, 1, "a finger's 0.025, in whole pixels")
      compare(String(face(main).color), "#ffd23f", "the primary one: the accent")
      compare(String(words(main).color), "#141414", "its words read on it")
      compare(face(plain).radius, 50 * 0.22)
      verify(!face(plain).gradient, "a plain fill")
      compare(words(plain).font.pixelSize, 15, "a finger's 0.3")
      compare(words(plain).font.weight, Font.Medium)
    }

    function test_a_themes_style_reaches_it() {
      guide.overrides = { touchButton: { fill: "#202020", border: { color: "#ff00ff" }, radius: 0.5, text: { color: "#ff8800", size: 0.4, case: "upper" } } }
      wait(10)
      compare(String(face(plain).color), "#202020")
      compare(String(face(plain).border.color), "#ff00ff")
      compare(face(plain).radius, 25, "corners: a fraction of the finger")
      compare(String(words(plain).color), "#ff8800")
      compare(words(plain).font.pixelSize, 20)
      compare(words(plain).font.capitalization, Font.AllUppercase)
      verify(guide.asked.indexOf("#202020 #ff8800") >= 0, "its words through the guide's readability")
    }

    function test_its_border_width() {
      guide.fingerPx = 80
      wait(10)
      compare(face(plain).border.width, 2, "today's: 0.025 of a bigger finger")
      guide.overrides = { touchButton: { border: { width: 0.1 } } }
      wait(10)
      compare(face(plain).border.width, 8, "a theme's fraction of the finger")
      guide.overrides = { touchButton: { border: { width: "3px" } } }
      wait(10)
      compare(face(plain).border.width, 3, "or pixels")
      guide.overrides = { touchButton: { border: { width: 0 } } }
      wait(10)
      compare(face(plain).border.width, 0, "none")
    }

    function test_a_gradient_fill() {
      guide.overrides = { touchButton: { fill: { from: "#ff0000", to: "#0000ff" } } }
      wait(10)
      verify(face(plain).gradient !== null, "drawn as the gradient")
      compare(face(plain).gradient.orientation, Gradient.Vertical)
      compare(String(face(plain).gradient.stops[0].color), "#ff0000")
      compare(String(face(plain).gradient.stops[1].color), "#0000ff")
      compare(String(plain.fill), "#ff0000", "its words read on where it starts")
      guide.overrides = { touchButton: { fill: { from: "#ff0000", to: "#0000ff", direction: "left" } } }
      wait(10)
      compare(face(plain).gradient.orientation, Gradient.Horizontal)
      compare(String(face(plain).gradient.stops[0].color), "#0000ff", "leftward: from on the right")
    }

    function test_always_a_finger_tall() {
      guide.overrides = { touchButton: { radius: 0, text: { size: 0.05 } } }
      wait(10)
      compare(plain.height, 50, "a finger, whatever the theme")
      verify(plain.width >= 50)
    }
  }
}
