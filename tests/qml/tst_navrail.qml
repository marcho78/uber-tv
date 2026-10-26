import QtQuick
import QtTest
import "../../ui"
import "../../Look.js" as Look

// The nav rail in tablet mode (ui/NavRail.qml), on a short screen (1280×720,
// a 12 px unit) with the biggest finger (72 px): ten parts, an update to
// tell you about (three rows at its foot), the credits, Customize, with the
// key hints on and off. Every row is a finger tall; the parts never run
// into its foot (more than fit slide, the cursor's kept in view); its foot
// never runs into Customize; nothing runs off the screen.
Item {
  id: top
  width: 1280; height: 720

  readonly property var retro: ({ text: "#f2f4ff", textDim: "#9fb0f0", accent: "#ffd23f", timeline: "#ff4d4d", cell: "#1b3591", cellBorder: "#3b5bd1", channelCell: "#0f2470", selected: "#ffd23f", selectedText: "#141414", header: "#ffd23f", headerText: "#141414", band: "#030a2b", bandText: "#ffd23f", infoPanel: "#40000000", preview: "#000000", alert: "#ff4d4d", bgTop: "#071447", bgBottom: "#030a2b", ltBg: "#eb081447", ltBorder: "#3b5bd1", ltNumber: "#ffd23f", ltChannel: "#9fb0f0", ltTitle: "#f2f4ff", ltProgress: "#ffd23f", ltTrack: "#1b3591", ltClock: "#f2f4ff", ltTime: "#ffd23f", cardBackdrop: "#d1000000", cardName: "#ffd23f", cardStatus: "#9fb0f0", cardFrame: "#3b5bd1", boxBg: "#071447", boxBorder: "#ffd23f", scrim: "#bf030a2b", keyFace: "#e4e9ff", keyText: "#0b1550", keyEdge: "#46559a", miniBar: "#eb030a2b" })

  QtObject {
    id: guide
    property real u: 12
    property bool touchMode: true
    property real fingerPx: 72
    property bool showKeyHints: true
    property bool railOpen: true
    property bool railEditing: false
    property bool watching: false
    property bool railCredits: true
    property string railShows: "always"
    property int railCursor: 0
    property int railEditCursor: 0
    property string railCurrent: "tv"
    readonly property var railItems: ["search", "home", "tv", "movies", "ondemand", "videos", "recordings", "mylist", "apps", "settings"]
                                     .map(function(k) { return { key: k, label: k, icon: "tv" } })
    readonly property var railSystem: [{ key: "update", label: "Update", icon: "update" }, { key: "window", label: "Window", icon: "window" }, { key: "off", label: "Turn off", icon: "power" }]
    property var railPanelRows: []
    property var railAvailable: []
    property var railSetup: ({})
    property string railKind: ""
    property string railOffBecause: ""
    readonly property var colors: top.retro
    readonly property var fonts: ({ body: "Sans", display: "Sans", mono: "Monospace" })
    readonly property var look: Look.resolve({}, {}, guide.colors, guide.fonts, {})
    readonly property var layout: Look.effectiveLayout({}, {})
    readonly property var areaImages: ({})
    readonly property color ink: colors.text
    readonly property color dimInk: colors.textDim
    readonly property color marquee: colors.accent
    function inkOn(c) { return "#141414" }
    function isFinger(mouse) { return false }
    function railModeLabel(m) { return m }
    function railGo(i) {}
    function closeRail() {}
    function closeRailPanel() {}
    function railPanelAct(d) {}
    function openCredit(k) {}
    function openCreditSetting() {}
  }

  NavRail {
    id: rail
    anchors.fill: parent
    guide: guide
  }

  TestCase {
    name: "NavRail"
    when: windowShown

    function init() { guide.showKeyHints = true; guide.railCursor = 0; guide.railOpen = true; wait(30) }

    function find(item, pred) {
      var stack = [item]
      while (stack.length) {
        var it = stack.pop()
        if (pred(it)) return it
        for (var i = 0; i < it.children.length; i++) stack.push(it.children[i])
        if (it.contentItem && it.contentItem !== it) stack.push(it.contentItem)
      }
      return null
    }
    function topOf(item) { return item.mapToItem(top, 0, 0).y }
    function bottomOf(item) { return item.mapToItem(top, 0, item.height).y }
    function named(name) { return find(rail, function(x) { return x.objectName === name }) }
    function parts() { return named("railParts") }
    function foot() { return named("railFoot") }
    function customize() { return named("railCustomize") }

    function test_it_all_fits_data() { return [{ tag: "key hints on", hints: true }, { tag: "key hints off", hints: false }] }
    function test_it_all_fits(data) {
      guide.showKeyHints = data.hints
      wait(50)
      var p = parts(), f = foot(), c = customize()
      verify(p && f && c, "the parts, its foot, Customize")
      compare(rail.itemH, 72, "a row a finger tall")
      verify(c.visible, "Customize, in tablet mode, the key hints on or off")
      verify(bottomOf(p) <= topOf(f), "the parts end before its foot: " + bottomOf(p) + " ≤ " + topOf(f))
      verify(bottomOf(f) <= topOf(c), "its foot ends before Customize: " + bottomOf(f) + " ≤ " + topOf(c))
      verify(bottomOf(c) <= top.height, "nothing off the screen")
      verify(p.contentHeight > p.height, "ten finger-tall parts don't all fit here")
      verify(p.interactive, "so they slide")
    }

    function test_the_cursor_kept_in_view() {
      var p = parts()
      guide.railCursor = 9
      wait(30)
      verify(9 * (rail.itemH + guide.u * 0.5) + rail.itemH <= p.contentY + p.height + 0.5, "the last part in view")
      guide.railCursor = 0
      wait(30)
      compare(p.contentY, 0, "the first again")
    }

    function test_the_keys_size_unchanged() {
      guide.touchMode = false
      wait(30)
      compare(rail.itemH, Math.round(guide.u * 3), "3 units without tablet mode")
      guide.touchMode = true
    }
  }
}
