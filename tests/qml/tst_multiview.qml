import QtQuick
import QtTest
import "../../ui"
import "../../Look.js" as Look

// Multiview (ui/Multiview.qml) against a stand-in guide: it starts with the
// channel on and the Add a channel list (the TV off first); each pick adds a
// tile and the layout fits the count; each tile asks for its quality; the
// list leaves out what's on screen and jumps to a typed number; a locked
// channel asks for the passcode first; taking off down to one, or Esc with
// nothing added, plays that channel full screen; teardown stops every tile;
// the lock changing stops a tile on a channel locked now; the phone's power
// and media keys' stop are TV off; an app's media takes over; the gear holds
// the background's four (a color kept only with Enter).
Item {
  id: top
  width: 1280
  height: 720

  readonly property var retro: ({ text: "#f2f4ff", textDim: "#9fb0f0", accent: "#ffd23f", timeline: "#ff4d4d", cell: "#1b3591", cellBorder: "#3b5bd1", channelCell: "#0f2470", selected: "#ffd23f", selectedText: "#141414", header: "#ffd23f", headerText: "#141414", band: "#030a2b", bandText: "#ffd23f", infoPanel: "#40000000", preview: "#000000", alert: "#ff4d4d", bgTop: "#071447", bgBottom: "#030a2b", ltBg: "#eb081447", ltBorder: "#3b5bd1", ltNumber: "#ffd23f", ltChannel: "#9fb0f0", ltTitle: "#f2f4ff", ltProgress: "#ffd23f", ltTrack: "#1b3591", ltClock: "#f2f4ff", ltTime: "#ffd23f", cardBackdrop: "#d1000000", cardName: "#ffd23f", cardStatus: "#9fb0f0", cardFrame: "#3b5bd1", boxBg: "#071447", boxBorder: "#ffd23f", scrim: "#bf030a2b", keyFace: "#e4e9ff", keyText: "#0b1550", keyEdge: "#46559a", miniBar: "#eb030a2b" })
  property var lockedUrls: ({})
  property var unlockThen: null

  QtObject {
    id: guide
    property string lastInput: "keyboard"
    function noteInput(kind) { lastInput = kind }   // tablet mode: what was used last
    function keyFirst(event) { noteInput("keyboard"); return false }   // (Guide.qml: and the ⋯ panel)
    property real u: 16
    readonly property var colors: top.retro
    readonly property var fonts: ({ body: "Sans", display: "Sans", mono: "Monospace" })
    readonly property var look: Look.resolve({}, {}, guide.colors, guide.fonts, {})
    readonly property color ink: colors.text
    readonly property color dimInk: colors.textDim
    readonly property color marquee: colors.accent
    readonly property color cellEdge: colors.cellBorder
    readonly property string fontFamily: "Sans"
    readonly property var pickerSwatches: ["#000000", "#ffffff"]
    property var channels: [
      { url: "u/sky", name: "Sky News", state: "ready", items: [], live: { id: "skylive0001", title: "Sky News Live" } },
      { url: "u/nasa", name: "NASA", state: "ready", items: [], live: { id: "nasalive001", title: "ISS" } },
      { url: "u/lofi", name: "Lofi", state: "ready", items: [], live: { id: "lofilive001", title: "beats" } },
      { url: "u/cam", name: "EarthCam", state: "ready", items: [], live: { id: "camlive0001", title: "Times Square" } },
      { url: "u/bears", name: "Bears", state: "ready", items: [], live: { id: "bearlive001", title: "Brooks Falls" } }
    ]
    property var numbers: [101, 501, 801, 1001, 701]
    property var visibleRows: [0, 1, 2, 3, 4]
    property string streamBase: "http://127.0.0.1:9/secret"
    property bool muted: false
    property bool showKeyHints: true
    property real now: 1792400000
    property bool appPlaying: false
    property var multiviewBackground: ({ mode: "none", image: "", color: "", dim: 0.6 })
    readonly property string multiviewBackdrop: ""
    property string pickerOpened: ""
    function setMultiviewBackground(c) { var b = { mode: multiviewBackground.mode, image: multiviewBackground.image, color: multiviewBackground.color, dim: multiviewBackground.dim }; for (var k in c) b[k] = c[k]; multiviewBackground = b }
    function openPicker(images, area) { pickerOpened = area }
    property int focused: 0
    function focusKeys() { focused++ }
    property int turnOffs: 0
    property int dismissed: 0
    property var watched: []
    property var channelLock: QtObject {
      function blocks(ch) { return !!ch && !!top.lockedUrls[ch.url] }
      function askUnlock(ch, then) { top.unlockThen = then; return true }
    }
    function indexOf(url) { for (var i = 0; i < channels.length; i++) if (channels[i].url === url) return i; return -1 }
    function airs(ch) { return !!ch }
    // a channel a recording's provider would stream twice (Recordings)
    property var secondStreams: ({})
    property var allowed: []
    function secondStreamOf(ch) { return !!ch && !!secondStreams[ch.url] }
    function allowStream(ch) { allowed = allowed.concat([ch.url]) }
    function rollDay() {}
    function airing(ch, t) { return { id: ch.live.id, title: ch.live.title, start: t, end: t + 21600, live: true } }
    function startStreamer() {}
    function liveEnded(r) {}
    function clock(t) { return "9:41 PM" }
    function showTitle(t) { return t }
    function turnOff() { turnOffs++; view.teardown() }
    // the TV's pause and rewind buffer (Timeshift.qml): busy while its writer's going; whenGone once it's gone
    property var pauser: QtObject {
      property bool busy: false
      property var waiting: []
      function whenGone(done) { if (!busy) done(); else waiting = waiting.concat([done]) }
      function gone() { busy = false; var w = waiting; waiting = []; for (var i = 0; i < w.length; i++) w[i]() }
    }
    function watch(r) { watched = watched.concat([r]) }
    function dismiss() { dismissed++; turnOff() }
    function showGuide() {}
    function setKeyHints(on) { showKeyHints = on }
  }

  // the screen under Multiview (the guide, Home, the rail): it must never get a click meant for Multiview's background
  property int underneath: 0
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    onClicked: top.underneath++
    onWheel: function(wheel) { top.underneath++ }
  }

  Multiview {
    id: view
    anchors.fill: parent
    guide: guide
  }

  TestCase {
    name: "Multiview"
    when: windowShown

    function init() {
      view.teardown()
      top.lockedUrls = ({})
      top.unlockThen = null
      guide.turnOffs = 0
      guide.dismissed = 0
      guide.watched = []
      guide.appPlaying = false
      guide.multiviewBackground = { mode: "none", image: "", color: "", dim: 0.6 }
      guide.pickerOpened = ""
      guide.focused = 0
      top.underneath = 0
    }

    function key(k) { view.key({ key: k }) }
    function tile(slot) { return view.tileIn(slot) }
    function urls() { return view.order.map(function(s) { return view.slots[s] }) }

    function test_starts_with_the_channel_on_and_the_list() {
      compare(view.start("u/sky"), "ok")
      compare(guide.turnOffs, 1, "the TV goes off first")
      verify(view.active)
      compare(view.mode, "picker")
      compare(urls(), ["u/sky"])
      verify(view.pickRows.indexOf(0) < 0, "the channel on isn't in the list")
      compare(view.layout, "single")
    }

    function test_each_pick_adds_a_tile_and_the_layout_fits() {
      view.start("u/sky")
      key(Qt.Key_Return)
      compare(urls(), ["u/sky", "u/nasa"])
      compare(view.layout, "side")
      compare(view.mode, "picker", "the list stays open")
      key(Qt.Key_Return)
      compare(view.count, 3)
      compare(view.layout, "featured")
      key(Qt.Key_Return)
      compare(view.count, 4)
      compare(view.layout, "grid")
      compare(view.mode, "tiles", "at four the list closes")
    }

    function test_each_tile_asks_for_its_quality() {
      view.start("u/sky")
      key(Qt.Key_Return)
      compare(view.qualityOf(view.order[0]), 720, "side by side: 720p")
      compare(tile(view.order[1]).player.source.toString(), "http://127.0.0.1:9/secret/play/nasalive001.m3u8?h=720")
      key(Qt.Key_Return)
      compare(view.qualityOf(view.order[0]), 1080, "featured: the big one 1080p")
      compare(view.qualityOf(view.order[2]), 360, "and the small ones 360p")
      key(Qt.Key_Return)
      compare(view.qualityOf(view.order[3]), 480, "grid: 480p")
      key(Qt.Key_Return)   // full screen
      compare(view.mode, "full")
      compare(view.qualityOf(view.sel), 1080, "full screen: 1080p")
    }

    function test_the_list_jumps_to_a_typed_number() {
      view.start("u/sky")
      key(Qt.Key_1); key(Qt.Key_0); key(Qt.Key_0); key(Qt.Key_1)
      compare(guide.channels[view.pickRows[view.pick]].name, "EarthCam")
    }

    function test_a_locked_channel_asks_first() {
      top.lockedUrls = { "u/nasa": true }
      view.start("u/sky")
      key(Qt.Key_Return)
      compare(view.count, 1, "not added before the passcode")
      verify(top.unlockThen !== null, "the passcode is asked for")
      top.lockedUrls = ({})
      top.unlockThen()
      compare(urls(), ["u/sky", "u/nasa"], "added once unlocked")
    }

    function test_esc_with_nothing_added_plays_the_channel() {
      view.start("u/sky")
      key(Qt.Key_Escape)
      verify(!view.active)
      compare(guide.watched, [0])
    }

    function test_taking_off_down_to_one_plays_it_full_screen() {
      view.start("u/sky")
      key(Qt.Key_Return); key(Qt.Key_Return); key(Qt.Key_Escape)
      compare(view.count, 3)
      view.remove(view.order[0])
      compare(view.count, 2)
      compare(view.layout, "side")
      verify(view.sel === view.order[0], "the sound moves to a tile still on")
      view.remove(view.order[0])
      verify(!view.active)
      compare(guide.watched, [2], "the one left plays full screen")
    }

    function test_teardown_stops_every_tile() {
      view.start("u/sky")
      key(Qt.Key_Return); key(Qt.Key_Return)
      var slots = view.order.slice()
      view.teardown()
      verify(!view.active)
      for (var i = 0; i < slots.length; i++) {
        compare(tile(slots[i]).reception, "off")
        compare(tile(slots[i]).player.source.toString(), "")
      }
      compare(view.count, 0)
    }

    function test_a_channel_locked_now_stops() {
      view.start("u/sky")
      key(Qt.Key_Return)
      var s = view.order[1]
      compare(tile(s).reception, "tuning")
      top.lockedUrls = { "u/nasa": true }
      view.enforceLock()
      compare(tile(s).reception, "locked")
      compare(tile(s).player.source.toString(), "")
    }

    function test_the_phone_and_media_keys() {
      view.start("u/sky")
      key(Qt.Key_Return); key(Qt.Key_Escape)
      verify(view.remote("tune", 801), "a number goes on the selected tile")
      compare(view.slots[view.sel], "u/lofi")
      verify(view.remote("power", 0))
      compare(guide.dismissed, 1, "power: the TV off")
      verify(!view.active)
      view.start("u/sky")
      key(Qt.Key_Return); key(Qt.Key_Escape)
      view.media("stop")
      verify(!view.active, "media stop: the TV off")
    }

    function test_the_phones_other_buttons_stay_in_multiview() {
      view.start("u/sky")
      verify(view.remote("tune", 1001), "in the Add a channel list a number jumps there")
      compare(view.pickRows[view.pick], 3, "to EarthCam")
      compare(urls(), ["u/sky"], "nothing added or changed")
      key(Qt.Key_Escape); view.start("u/sky")
      key(Qt.Key_Return); key(Qt.Key_Escape)   // sky, nasa; sound on sky
      verify(view.remote("chup", 0), "CH+ is Multiview's")
      compare(view.slots[view.sel], "u/lofi", "the selected tile's next channel (past the one on the other tile)")
      verify(view.remote("chdown", 0))
      compare(view.slots[view.sel], "u/sky")
      verify(view.active, "CH+/CH- never leave Multiview")
      key(Qt.Key_Return)
      compare(view.mode, "full")
      verify(view.remote("options", 0), "⋯ is Multiview's")
      verify(view.bannerUp, "full screen: the tile's banner, as I")
      verify(!view.remote("mute", 0), "mute stays the guide's")
    }

    function test_the_phone_on_a_full_screen_tile() {
      view.start("u/sky")
      key(Qt.Key_Return); key(Qt.Key_Escape)   // sky, nasa; sound on sky
      key(Qt.Key_Return)
      compare(view.mode, "full")
      verify(view.remote("right", 0), "▶ is Multiview's")
      compare(view.slots[view.sel], "u/lofi", "▶: the tile's next channel (past the one on the other tile)")
      view.remote("left", 0)
      compare(view.slots[view.sel], "u/sky", "◀: back")
      view.remote("down", 0)
      compare([view.slots[view.sel], view.bannerUp, view.mode], ["u/sky", false, "full"], "▼ with nothing up: nothing")
      view.remote("up", 0)
      verify(view.bannerUp, "▲: the banner's choices")
      view.remote("up", 0)
      verify(view.bannerUp, "▲ again: they stay")
      compare(view.slots[view.sel], "u/sky", "▲ never changes the channel")
      view.remote("right", 0)
      compare([view.bannerAct, view.slots[view.sel]], [1, "u/sky"], "▶ with the choices up: the next choice, not the channel")
      view.remote("left", 0)
      compare(view.bannerAct, 0)
      view.remote("down", 0)
      verify(!view.bannerUp, "▼ closes them")
      compare(view.mode, "full")
      view.remote("up", 0); view.remote("ok", 0)
      compare(view.mode, "tiles", "OK picks the first: back to Multiview")
      view.remote("up", 0)
      compare(view.mode, "bar", "in the tiles ▲ works as the key, as before: up to the bar")
    }

    function test_a_2nd_stream_asks_first() {
      view.start("u/sky")
      key(Qt.Key_Return); key(Qt.Key_Escape)   // sky, nasa; sound on sky
      guide.secondStreams = { "u/lofi": true }
      view.media("next")
      compare(view.slots[view.sel], "u/sky", "the tile keeps its channel")
      compare(view.mode, "picker", "the Change channel list opens instead")
      compare(view.pickMode, "replace")
      compare(guide.channels[view.pickRows[view.pick]].url, "u/lofi", "on that channel, marked 2nd stream")
      key(Qt.Key_Return)
      compare(view.slots[view.sel], "u/lofi", "picked there: it's on")
      compare(guide.allowed, ["u/lofi"], "and that's a yes for its provider")
      guide.secondStreams = ({})
      guide.allowed = []
    }

    function test_next_skips_whats_on_other_tiles() {
      view.start("u/sky")
      key(Qt.Key_Return); key(Qt.Key_Escape)   // sky, nasa; sound on sky
      view.media("next")
      compare(view.slots[view.sel], "u/lofi", "nasa is on the other tile: skipped")
    }

    function test_an_apps_media_takes_over() {
      view.start("u/sky")
      key(Qt.Key_Return)
      guide.appPlaying = true
      verify(!view.active)
    }

    function openGear() {
      view.start("u/sky")
      key(Qt.Key_Return); key(Qt.Key_Escape)
      key(Qt.Key_Up)
      compare(view.mode, "bar")
      key(Qt.Key_Right); key(Qt.Key_Right); key(Qt.Key_Right)   // past Add, Layout, Exit: the gear
      key(Qt.Key_Return)
      compare(view.mode, "look")
    }
    function labels() { return view.lookRows.map(function(r) { return r.label }) }

    function test_the_gear_holds_the_backgrounds_four() {
      openGear()
      compare(labels(), ["As it is", "A color", "The theme's background", "A custom wallpaper"], "only the background, nothing else")
      verify(view.lookRows[0].on, "as it is, to start")
      key(Qt.Key_Down); key(Qt.Key_Down); key(Qt.Key_Return)
      compare(guide.multiviewBackground.mode, "theme", "the theme's background")
      verify(view.lookRows[2].on && !view.lookRows[0].on)
      key(Qt.Key_Down); key(Qt.Key_Return)
      compare(labels(), ["Omarchy wallpaper", "A picture of your own…"], "a custom wallpaper: Omarchy's, or one of your own")
      compare(guide.multiviewBackground.mode, "theme", "nothing changed by opening it")
      key(Qt.Key_Return)
      compare(guide.multiviewBackground.mode, "wallpaper", "the Omarchy wallpaper")
      key(Qt.Key_Down); key(Qt.Key_Return)
      compare(guide.pickerOpened, "multiview", "one of your own: the picture picker")
      key(Qt.Key_Escape)
      compare(view.lookStep, "", "Esc: back to the four")
      compare(view.lookCursor, 3, "on A custom wallpaper")
      verify(view.lookRows[3].on, "the wallpaper's on")
      key(Qt.Key_Up); key(Qt.Key_Up); key(Qt.Key_Up); key(Qt.Key_Return)
      compare(guide.multiviewBackground.mode, "none", "as it is again")
      compare(guide.multiviewBackground.dim, 0.6, "how dark a picture is: not in the gear")
      key(Qt.Key_Escape)
      compare(view.mode, "tiles")
      guide.multiviewBackground = { mode: "image", image: "/p.jpg", color: "", dim: 0.6 }
      key(Qt.Key_Up); key(Qt.Key_Right); key(Qt.Key_Right); key(Qt.Key_Right); key(Qt.Key_Return)
      compare(view.lookCursor, 3, "the gear opens on the background that's on")
    }

    function test_a_color_is_kept_only_with_enter() {
      openGear()
      key(Qt.Key_Down); key(Qt.Key_Return)
      compare(view.lookStep, "color", "A color: the color picker")
      compare(view.pickedColor, Qt.color(guide.colors.bgBottom), "it starts at the theme's dark background")
      keyClick(Qt.Key_Right); keyClick(Qt.Key_Up)
      verify(view.pickedColor !== Qt.color(guide.colors.bgBottom), "the arrows change it, shown as you pick")
      compare(guide.multiviewBackground.mode, "none", "not kept yet")
      keyClick(Qt.Key_Escape)
      compare(view.lookStep, "", "Esc: the four again")
      compare(guide.multiviewBackground.mode, "none", "and the background as it was")
      compare(guide.focused, 1, "the keys back to the guide")
      key(Qt.Key_Return)
      compare(view.lookStep, "color")
      keyClick(Qt.Key_Right); keyClick(Qt.Key_Right)
      var picked = view.pickedColor.toString()
      keyClick(Qt.Key_Return)
      compare(guide.multiviewBackground.mode, "color", "Enter keeps it")
      compare(guide.multiviewBackground.color, picked)
      verify(/^#[0-9a-f]{6}$/.test(guide.multiviewBackground.color), "as #rrggbb")
      verify(view.lookRows[1].on)
      key(Qt.Key_Return)
      compare(view.pickedColor.toString(), picked, "opened again: at the color you kept")
      verify(view.remote("right", 0), "the phone's d-pad drives the picker too")
      verify(view.pickedColor.toString() !== picked, "in big steps")
      verify(view.remote("back", 0))
      compare(view.lookStep, "", "BACK: the four again")
      compare(guide.multiviewBackground.color, picked, "the color kept before stays")
      key(Qt.Key_Return)
      view.teardown()
      compare(view.lookStep, "", "Multiview closing while you pick: the picker goes")
      compare(guide.multiviewBackground.color, picked, "and what you kept stays")
      compare(guide.focused, 4, "the keys back to the guide")
    }

    function test_the_tvs_buffer_goes_first() {
      guide.pauser.busy = true
      var offs = guide.turnOffs
      compare(view.start("u/sky"), "ok")
      verify(guide.turnOffs > offs, "the TV off, its buffer told to go")
      verify(!view.active, "no tile opens the provider while its writer's still going")
      guide.pauser.gone()
      verify(view.active, "then Multiview")
      compare(urls(), ["u/sky"])
      view.teardown()
      guide.pauser.busy = true
      compare(view.startWith(["u/sky", "u/nasa"]), "ok")
      verify(!view.active, "an agent's too")
      guide.pauser.gone()
      compare(urls(), ["u/sky", "u/nasa"])
      view.teardown()
    }

    function test_an_agents_multiview() {
      compare(view.startWith(["u/sky", "u/nasa", "u/lofi"]), "ok")
      compare(guide.turnOffs, 1, "the TV goes off first")
      verify(view.active)
      compare(view.mode, "tiles", "two or more: the tiles, no list")
      compare(urls(), ["u/sky", "u/nasa", "u/lofi"])
      compare(view.layout, "featured", "three: featured first")
      compare(view.sel, 0, "the first has the sound")
      compare(view.qualityOf(view.order[0]), 1080)
      compare(view.addTile("u/nasa"), -1, "on already")
      compare(view.addTile("u/cam"), 3)
      compare(view.layout, "grid", "four: grid first")
      compare(view.addTile("u/bears"), -1, "four: full")
      verify(!view.setLayout("row"), "row isn't one for four")
      compare(view.layout, "grid")
      verify(view.setLayout("featured"))
      compare(view.layout, "featured")
      compare(view.startWith(["u/cam"]), "ok")
      compare(view.mode, "picker", "one alone: as from the banner, with the list")
      compare(urls(), ["u/cam"])
    }

    function test_the_full_screen_banner() {
      view.start("u/sky")
      key(Qt.Key_Return); key(Qt.Key_Return); key(Qt.Key_Escape)   // three tiles
      key(Qt.Key_Return)
      compare(view.mode, "full")
      key(Qt.Key_Space)
      verify(view.bannerUp, "Space: the banner with its choices")
      key(Qt.Key_Right); key(Qt.Key_Return)
      compare(view.mode, "picker", "Change channel: the list, for this tile")
      compare(view.pickMode, "replace")
      key(Qt.Key_Escape)
      compare(view.mode, "full", "Esc: back to the tile full screen")
      key(Qt.Key_I); key(Qt.Key_Right); key(Qt.Key_Right); key(Qt.Key_Return)
      compare(view.count, 2, "Take off Multiview: this one off, the others stay")
      compare(view.mode, "tiles")
      key(Qt.Key_Return); key(Qt.Key_I); key(Qt.Key_Escape)
      verify(!view.bannerUp, "Esc hides the banner")
      compare(view.mode, "full")
      key(Qt.Key_Escape)
      compare(view.mode, "tiles", "and Esc again goes back to the tiles")
    }

    function test_pause_is_kept_while_tiles_load_again() {
      view.start("u/sky")
      key(Qt.Key_Return); key(Qt.Key_Escape)   // two: side by side
      view.media("pause")
      verify(view.paused)
      verify(tile(view.order[0]).paused && tile(view.order[1]).paused, "every tile held paused")
      view.cycleLayout()                         // featured: new qualities, the tiles load again
      verify(tile(view.order[0]).paused && tile(view.order[1]).paused, "still paused after the layout changed")
      key(Qt.Key_Return)                         // full screen: 1080p
      verify(tile(view.sel).paused, "and full screen")
      view.media("playpause")
      verify(!view.paused && !tile(view.sel).paused, "play: on again")
      view.media("pause"); view.teardown(); view.start("u/nasa")
      verify(!view.paused, "a new Multiview starts playing")
    }

    function test_background_clicks_stay_in_multiview() {
      view.start("u/sky")
      key(Qt.Key_Return); key(Qt.Key_Escape)
      top.underneath = 0
      mouseClick(view, 10, 100)
      mouseWheel(view, 10, 100, 0, -120)
      compare(top.underneath, 0, "nothing reaches the screen underneath")
    }

    function test_up_from_the_top_row_reaches_the_bar() {
      view.start("u/sky")
      key(Qt.Key_Return); key(Qt.Key_Return); key(Qt.Key_Return)   // four: grid, list closed
      compare(view.mode, "tiles")
      var first = view.sel
      key(Qt.Key_Right)
      verify(view.sel !== first, "→ moves the sound")
      key(Qt.Key_Up)
      compare(view.mode, "bar")
      key(Qt.Key_Right); key(Qt.Key_Return)
      compare(view.layout, "featured", "Layout switches it")
    }
  }
}
