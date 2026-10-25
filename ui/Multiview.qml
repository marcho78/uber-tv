import QtQuick
import "../Look.js" as Look

// Multiview: two to four channels at once, the picture from each, the sound
// from the selected one (the plan: uber-tv-plans/multiview.md). It starts
// with the channel that was on and the Add a channel list; each pick adds a
// tile, up to four, and the layout fits how many there are. The arrows move
// the sound, ↑ from the top row reaches Add channel, Layout and Exit, Enter
// shows a tile full screen, Del takes one off (down to one, Multiview closes
// and that channel plays full screen), Esc exits to the channel with the
// sound. TV off, closing Uber TV and anything played instead stop every tile
// (teardown). Four tiles stay made; a channel keeps its tile while others
// come and go, so nothing reloads that didn't change.
Item {
  id: mv

  required property var guide
  readonly property real u: guide.u

  property bool active: false
  property var slots: ["", "", "", ""]   // each tile's channel (its address), "" for none
  property var order: []                 // the tiles on screen, in layout order (Featured: the first is big)
  property int sel: 0                    // the tile with the sound
  property string layout: "single"
  property string mode: "tiles"          // tiles, bar, picker, look, full
  property int bar: 0                    // the options bar: Add channel, Layout, Exit, then the look's gear
  property int lookCursor: 0             // the gear's row: As it is, A color, The theme's background, A custom wallpaper
  property string lookStep: ""           // in the gear: "" its four, "color" the color picker, "wallpaper" the wallpaper's two
  property color pickedColor: "black"    // the color picker's color, shown as you pick (kept only with Enter)
  property bool bannerUp: false          // a tile full screen: its banner with what you can do (I or Space)
  property int bannerAct: 0
  readonly property var fullActions: [{ label: "Back to Multiview", icon: "apps" }, { label: "Change channel", icon: "pencil" },
                                      { label: "Take off Multiview", icon: "close" }, { label: "Guide", icon: "tv" }]
  property string pickMode: "add"        // add, or replace the selected tile's channel
  property string pickBack: "tiles"
  property int pick: 0
  property string typed: ""              // a channel number being typed in the list
  property string message: ""
  property bool paused: false            // paused by you (media keys): kept while tiles load again, until play
  readonly property int count: order.length

  // A visible tile really playing (keep-awake and the screen saver): full
  // screen, only the one shown counts
  readonly property bool playing: active && (mode === "full" ? tileIn(sel).playing : anyPlaying())

  visible: active

  function tileIn(slot) { var d = tiles.itemAt(slot); return d ? d.tile : { playing: false } }
  function anyPlaying() {
    for (var k = 0; k < order.length; k++) if (tileIn(order[k]).playing) return true
    return false
  }

  function rowOf(slot) { return slots[slot] ? guide.indexOf(slots[slot]) : -1 }
  function nameOf(slot) {
    var r = rowOf(slot), ch = guide.channels[r]
    return ch ? (guide.numbers[r] ? guide.numbers[r] + " " : "") + ch.name : ""
  }

  function layoutsFor(n) { return n <= 1 ? ["single"] : n === 2 ? ["side", "featured"] : n === 3 ? ["featured", "grid", "row"] : ["grid", "featured"] }
  function layoutName(l) { return ({ single: "One channel", side: "Side by side", featured: "Featured", grid: "Grid", row: "Row" })[l] || l }

  // What each tile asks for: enough for its size (the plan's numbers)
  function qualityOf(slot) {
    var k = order.indexOf(slot)
    if (k < 0) return 720
    if (mode === "full" && slot === sel) return 1080
    if (layout === "grid" || layout === "row") return 480
    if (layout === "featured") return k === 0 ? 1080 : 360
    return 720
  }

  // ---- where the tiles go ----

  readonly property real headH: u * 5
  readonly property real footH: guide.showKeyHints ? u * 5.2 : u * 2.6
  readonly property real drawerW: Math.min(width * 0.36, u * 36)
  readonly property var area: ({ x: u * 1.5, y: headH, w: width - u * 3 - (mode === "picker" || mode === "look" ? drawerW + u : 0), h: height - headH - footH })

  function fit(c) {
    var w = c.w, h = w * 9 / 16
    if (h > c.h) { h = c.h; w = h * 16 / 9 }
    return { x: c.x + (c.w - w) / 2, y: c.y + (c.h - h) / 2, w: w, h: h }
  }

  function cells(n, A) {
    var g = u * 0.6
    if (layout === "single" || n <= 1) return [A]
    if (layout === "side") { var sw = (A.w - g) / 2; return [{ x: A.x, y: A.y, w: sw, h: A.h }, { x: A.x + sw + g, y: A.y, w: sw, h: A.h }] }
    if (layout === "row") { var rw = (A.w - 2 * g) / 3; return [0, 1, 2].map(function(i) { return { x: A.x + i * (rw + g), y: A.y, w: rw, h: A.h } }) }
    if (layout === "grid") {
      var gw = (A.w - g) / 2, gh = (A.h - g) / 2
      var c = [{ x: A.x, y: A.y, w: gw, h: gh }, { x: A.x + gw + g, y: A.y, w: gw, h: gh }]
      if (n === 3) c.push({ x: A.x + (A.w - gw) / 2, y: A.y + gh + g, w: gw, h: gh })
      else { c.push({ x: A.x, y: A.y + gh + g, w: gw, h: gh }); c.push({ x: A.x + gw + g, y: A.y + gh + g, w: gw, h: gh }) }
      return c
    }
    var bw = A.w * 0.7, smw = A.w - bw - g, kk = n - 1, smh = (A.h - g * (kk - 1)) / kk
    var f = [{ x: A.x, y: A.y, w: bw, h: A.h }]
    for (var i = 0; i < kk; i++) f.push({ x: A.x + bw + g, y: A.y + i * (smh + g), w: smw, h: smh })
    return f
  }

  function rectOf(slot) {
    var k = order.indexOf(slot)
    if (k < 0) return { x: 0, y: 0, w: 0, h: 0, shown: false }
    if (mode === "full") return slot === sel ? { x: 0, y: 0, w: width, h: height, shown: true } : { x: 0, y: 0, w: 0, h: 0, shown: false }
    var c = cells(order.length, area)[k]
    if (!c) return { x: 0, y: 0, w: 0, h: 0, shown: false }   // mid-change: the layout catches up
    var r = fit(c)
    r.shown = true
    return r
  }

  // ---- what you do ----

  function say(text) { mv.message = text; messageTimer.restart() }

  // From the channel that's on: Multiview with it, and the list to add more
  function start(url) {
    if (!url) return "no channel"
    // the TV's pause and rewind buffer goes first, its writer gone, so a tile
    // never opens the provider beside it
    if (guide.pauser.busy) { guide.turnOff(); guide.pauser.whenGone(function() { mv.start(url) }); return "ok" }
    guide.turnOff()
    mv.slots = [url, "", "", ""]
    mv.order = [0]
    mv.sel = 0
    mv.layout = "single"
    mv.pickMode = "add"
    mv.pick = 0
    mv.typed = ""
    mv.mode = "picker"
    mv.paused = false
    mv.active = true
    mv.say("Pick a channel to add. Enter adds it, Esc when you have enough.")
    return "ok"
  }

  // An agent's Multiview (Commands.qml multiview): these channels (their
  // addresses, 1 to 4) as tiles in their count's first layout; one alone
  // opens as from the banner, with the Add a channel list
  function startWith(urls) {
    if (urls.length <= 1) return mv.start(urls[0])
    if (guide.pauser.busy) { guide.turnOff(); guide.pauser.whenGone(function() { mv.startWith(urls) }); return "ok" }
    guide.turnOff()
    mv.layout = mv.layoutsFor(urls.length)[0]
    mv.slots = [0, 1, 2, 3].map(function(i) { return urls[i] || "" })
    mv.order = urls.map(function(u, i) { return i })
    mv.sel = 0
    mv.pickMode = "add"
    mv.typed = ""
    mv.mode = "tiles"
    mv.paused = false
    mv.active = true
    mv.say(mv.count + " channels. The arrows move the sound; ↑ from the top row for Add, Layout and Exit.")
    return "ok"
  }

  // Everything off: every tile stopped, Multiview gone (TV off, closing,
  // something else playing). Nothing else starts.
  function teardown() {
    for (var s = 0; s < 4; s++) { var d = tiles.itemAt(s); if (d) d.tile.stop() }
    mv.active = false
    mv.slots = ["", "", "", ""]
    mv.order = []
    mv.mode = "tiles"
    mv.message = ""
    mv.typed = ""
    mv.paused = false
    if (mv.lookStep === "color") mv.endColor(false)
    mv.lookStep = ""
  }

  // Out of Multiview: that tile's channel full screen, with its sound
  function exitTo(slot) {
    var url = mv.slots[slot]
    mv.teardown()
    var r = guide.indexOf(url)
    if (r >= 0) guide.watch(r)
  }
  function exit() { mv.exitTo(mv.sel) }

  readonly property var pickRows: {
    var taken = []
    for (var s = 0; s < 4; s++) if (mv.slots[s] && !(mv.pickMode === "replace" && s === mv.sel)) taken.push(mv.slots[s])
    var current = mv.pickMode === "replace" ? mv.slots[mv.sel] : ""
    return guide.visibleRows.filter(function(r) { var ch = guide.channels[r]; return ch && taken.indexOf(ch.url) < 0 && ch.url !== current })
  }

  function openPicker(how) {
    if (how === "add" && mv.count >= 4) { mv.say("Multiview holds four channels. Take one off first (Del)."); return }
    mv.pickBack = mv.mode === "full" ? "full" : "tiles"
    mv.pickMode = how
    mv.pick = 0
    mv.typed = ""
    mv.mode = "picker"
  }

  function choose(k) {
    var r = mv.pickRows[k]
    var ch = guide.channels[r]
    if (!ch) return
    if (guide.channelLock.blocks(ch)) { guide.channelLock.askUnlock(ch, function() { mv.chooseUrl(ch.url) }); return }
    if (guide.secondStreamOf(ch)) guide.allowStream(ch)   // picked though marked 2nd stream: yes, for that provider
    mv.chooseUrl(ch.url)
  }

  function chooseUrl(url) {
    if (!mv.active || mv.mode !== "picker") return
    var s = mv.slots.slice()
    if (mv.pickMode === "replace") {
      s[mv.sel] = url
      mv.slots = s
      mv.mode = mv.pickBack
      mv.say("This tile: " + mv.nameOf(mv.sel) + ".")
      return
    }
    var free = mv.addTile(url)
    if (free < 0) return
    mv.pick = Math.min(mv.pick, Math.max(0, mv.pickRows.length - 1))
    if (mv.count >= 4) { mv.mode = "tiles"; mv.say("Added " + mv.nameOf(free) + ". Four channels: Multiview is full.") }
    else mv.say("Added " + mv.nameOf(free) + ": " + mv.count + " of 4. Enter adds another, Esc when you have enough.")
  }

  // A channel on the next free tile, in its new count's first layout (L
  // switches): the tile, or -1 (four already, or it's on one)
  function addTile(url) {
    var s = mv.slots.slice()
    var free = s.indexOf("")
    if (free < 0 || s.indexOf(url) >= 0) return -1
    s[free] = url
    mv.layout = mv.layoutsFor(mv.count + 1)[0]
    mv.slots = s
    mv.order = mv.order.concat([free])
    return free
  }

  function closePicker() {
    if (mv.pickMode === "replace") { mv.mode = mv.pickBack; return }
    if (mv.count <= 1) { mv.say(""); mv.exitTo(mv.order[0]); return }   // nothing added: back to the channel
    mv.mode = "tiles"
    mv.say(mv.count + " channels. The arrows move the sound; ↑ from the top row for Add, Layout and Exit.")
  }

  function remove(slot) {
    if (mv.order.indexOf(slot) < 0) return
    if (mv.count <= 2) {   // one left: Multiview closes, that one full screen
      var left = mv.order.filter(function(x) { return x !== slot })[0]
      mv.exitTo(left)
      return
    }
    var gone = mv.nameOf(slot)
    var s = mv.slots.slice()
    s[slot] = ""
    mv.layout = mv.layoutsFor(mv.count - 1)[0]
    mv.order = mv.order.filter(function(x) { return x !== slot })
    mv.slots = s
    if (mv.sel === slot) mv.sel = mv.order[0]
    mv.mode = "tiles"
    mv.say("Took off " + gone + ".")
  }

  function cycleLayout() {
    var ok = mv.layoutsFor(mv.count)
    if (ok.length < 2) return
    mv.layout = ok[(ok.indexOf(mv.layout) + 1) % ok.length]
    mv.say(mv.layoutName(mv.layout) + ".")
  }

  // A layout by name, if it's one for how many there are (an agent's)
  function setLayout(name) {
    if (mv.layoutsFor(mv.count).indexOf(name) < 0) return false
    mv.layout = name
    mv.say(mv.layoutName(mv.layout) + ".")
    return true
  }

  function select(slot) {
    if (mv.order.indexOf(slot) < 0 || slot === mv.sel) return
    mv.sel = slot
    mv.say("Sound from " + mv.nameOf(slot) + ".")
  }

  // The nearest tile that way; ↑ from the top row: the options bar
  function moveSel(dir) {
    var me = mv.rectOf(mv.sel), cx = me.x + me.w / 2, cy = me.y + me.h / 2
    var best = -1, bd = 1e9
    for (var k = 0; k < mv.order.length; k++) {
      var s = mv.order[k]
      if (s === mv.sel) continue
      var r = mv.rectOf(s), dx = r.x + r.w / 2 - cx, dy = r.y + r.h / 2 - cy
      var ok = dir === "left" ? dx < -mv.u : dir === "right" ? dx > mv.u : dir === "up" ? dy < -mv.u : dy > mv.u
      if (!ok) continue
      var d = dir === "left" || dir === "right" ? Math.abs(dx) + 2 * Math.abs(dy) : Math.abs(dy) + 2 * Math.abs(dx)
      if (d < bd) { bd = d; best = s }
    }
    if (best >= 0) mv.select(best)
    else if (dir === "up") { mv.bar = 0; mv.mode = "bar" }
  }

  // The selected tile's channel up or down, skipping the ones on other tiles
  function flip(d) {
    var v = guide.visibleRows, n = v.length
    if (!n) return
    var others = mv.slots.filter(function(u, s) { return u && s !== mv.sel })
    var p = v.indexOf(mv.rowOf(mv.sel))
    for (var k = 1; k <= n; k++) {
      var r = v[((p + d * k) % n + n) % n]
      var ch = guide.channels[r]
      if (!ch || others.indexOf(ch.url) >= 0) continue
      if (mv.askFirst(r)) return
      var s = mv.slots.slice()
      s[mv.sel] = ch.url
      mv.slots = s
      return
    }
  }

  // A channel a recording's provider would stream twice: not put on the
  // tile; the Change channel list opens on it instead, marked 2nd stream
  // (picking it there is saying yes). True if it did.
  function askFirst(r) {
    if (!guide.secondStreamOf(guide.channels[r])) return false
    mv.openPicker("replace")
    mv.pick = Math.max(0, mv.pickRows.indexOf(r))
    mv.say("That one takes a 2nd stream from a provider that's recording: Enter puts it on anyway.")
    return true
  }

  // The lock changed (or an unlock ran out): a tile on a channel that's
  // blocked now stops and shows the lock, the silent ones too
  function enforceLock() {
    if (!mv.active) return
    for (var k = 0; k < mv.order.length; k++) {
      var s = mv.order[k], t = mv.tileIn(s), ch = guide.channels[mv.rowOf(s)]
      if (ch && guide.channelLock.blocks(ch) && (t.reception === "tuning" || t.reception === "on")) t.halt("locked")
    }
  }

  // Enter on a tile: full screen; a locked one asks for the passcode, a lost one tunes again
  function enter() {
    var t = mv.tileIn(mv.sel)
    var ch = guide.channels[mv.rowOf(mv.sel)]
    if (t.reception === "locked" && ch) { guide.channelLock.askUnlock(ch, function() { mv.tileIn(mv.sel).tune() }); return }
    if (t.reception === "lost") { t.tune(); return }
    mv.mode = "full"
  }

  // The full-screen tile's banner: back, another channel on it, off
  // Multiview (the others stay), or the guide with this channel on
  function fullAct(i) {
    mv.bannerUp = false
    if (i === 0) mv.mode = "tiles"
    else if (i === 1) mv.openPicker("replace")
    else if (i === 2) mv.remove(mv.sel)
    else { mv.exitTo(mv.sel); guide.showGuide() }
  }

  onModeChanged: {
    if (mode !== "full") bannerUp = false
    if (mode !== "look") { endColor(false); lookStep = "" }
  }

  function barDo(i) {
    if (i === 0) mv.openPicker("add")
    else if (i === 1) { mv.mode = "tiles"; mv.cycleLayout() }
    else if (i === 2) mv.exit()
    else {   // the gear, on the background that's on
      mv.lookStep = ""
      mv.lookCursor = Math.max(0, mv.lookRows.findIndex(function(r) { return r.on }))
      mv.mode = "look"
    }
  }

  // The gear: Multiview's background, as it is (the theme's), a color, the
  // theme's background, or a custom wallpaper (Omarchy's, or a picture of
  // your own). How dark a picture is and the tiles' look are for agents
  // and themes (multiviewBackground, the MULTIVIEW parts).
  readonly property var lookRows: mv.lookStep === "wallpaper"
    ? [{ label: "Omarchy wallpaper", kind: "action", on: guide.multiviewBackground.mode === "wallpaper" },
       { label: "A picture of your own…", kind: "opens", on: guide.multiviewBackground.mode === "image" }]
    : [{ label: "As it is", kind: "action", on: guide.multiviewBackground.mode === "none" },
       { label: "A color", kind: "opens", on: guide.multiviewBackground.mode === "color" },
       { label: "The theme's background", kind: "action", on: guide.multiviewBackground.mode === "theme" },
       { label: "A custom wallpaper", kind: "opens", on: guide.multiviewBackground.mode === "wallpaper" || guide.multiviewBackground.mode === "image" }]
  function lookAct() {
    var i = mv.lookCursor
    if (mv.lookStep === "wallpaper") {
      if (i === 0) guide.setMultiviewBackground({ mode: "wallpaper" })
      else guide.openPicker(true, "multiview")
    } else if (i === 0) guide.setMultiviewBackground({ mode: "none" })
    else if (i === 1) mv.startColor()
    else if (i === 2) guide.setMultiviewBackground({ mode: "theme" })
    else { mv.lookStep = "wallpaper"; mv.lookCursor = guide.multiviewBackground.mode === "image" ? 1 : 0 }
  }
  function lookBack() {
    if (mv.lookStep === "wallpaper") { mv.lookStep = ""; mv.lookCursor = 3 }
    else mv.mode = "tiles"
  }
  // The color picker has the keys while it's open; Enter keeps the color,
  // Esc leaves the background as it was
  function startColor() {
    var b = guide.multiviewBackground
    mv.pickedColor = b.mode === "color" && b.color ? b.color : guide.colors.bgBottom
    mv.lookStep = "color"
    colorPicker.start(mv.pickedColor)
  }
  function endColor(keep) {
    if (mv.lookStep !== "color") return
    mv.lookStep = ""
    if (keep) guide.setMultiviewBackground({ mode: "color", color: colorPicker.hex(mv.pickedColor) })
    guide.focusKeys()
  }

  function typeDigit(d) {
    mv.typed = (mv.typed + d).slice(-4)
    typedTimer.restart()
    var want = Number(mv.typed)
    for (var k = 0; k < mv.pickRows.length; k++)
      if (guide.numbers[mv.pickRows[k]] === want) { mv.pick = k; return }
  }

  // The keys while Multiview is up (GuideKeys hands them over)
  function key(event) {
    var k = event.key
    if (k === Qt.Key_M) { guide.muted = !guide.muted; return }
    if (k === Qt.Key_K) { guide.setKeyHints(!guide.showKeyHints); return }
    if (mv.mode === "picker") {
      if (k >= Qt.Key_0 && k <= Qt.Key_9) mv.typeDigit(String(k - Qt.Key_0))
      else if (k === Qt.Key_Up) mv.pick = Math.max(0, mv.pick - 1)
      else if (k === Qt.Key_Down) mv.pick = Math.min(mv.pickRows.length - 1, mv.pick + 1)
      else if (k === Qt.Key_PageUp) mv.pick = Math.max(0, mv.pick - 8)
      else if (k === Qt.Key_PageDown) mv.pick = Math.min(mv.pickRows.length - 1, mv.pick + 8)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) mv.choose(mv.pick)
      else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) mv.closePicker()
      return
    }
    if (mv.mode === "look" && mv.lookStep === "color") {
      // the phone's d-pad (the keyboard's keys go to the picker itself), in big steps
      if (k === Qt.Key_Left) colorPicker.nudge(-1, 0, true)
      else if (k === Qt.Key_Right) colorPicker.nudge(1, 0, true)
      else if (k === Qt.Key_Up) colorPicker.nudge(0, -1, true)
      else if (k === Qt.Key_Down) colorPicker.nudge(0, 1, true)
      else if (k === Qt.Key_PageUp || k === Qt.Key_PageDown) {
        colorPicker.hue = (colorPicker.hue + (k === Qt.Key_PageUp ? -0.05 : 0.05) + 1) % 1
        colorPicker.report()
      }
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) mv.endColor(true)
      else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) mv.endColor(false)
      return
    }
    if (mv.mode === "look") {
      if (k === Qt.Key_Up) mv.lookCursor = Math.max(0, mv.lookCursor - 1)
      else if (k === Qt.Key_Down) mv.lookCursor = Math.min(mv.lookRows.length - 1, mv.lookCursor + 1)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) mv.lookAct()
      else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) mv.lookBack()
      return
    }
    if (mv.mode === "bar") {
      if (k === Qt.Key_Left) mv.bar = Math.max(0, mv.bar - 1)
      else if (k === Qt.Key_Right) mv.bar = Math.min(3, mv.bar + 1)   // the gear last
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) mv.barDo(mv.bar)
      else if (k === Qt.Key_Down || k === Qt.Key_Escape || k === Qt.Key_Backspace) mv.mode = "tiles"
      return
    }
    if (mv.mode === "full" && mv.bannerUp) {
      if (k === Qt.Key_Left) { mv.bannerAct = Math.max(0, mv.bannerAct - 1); bannerTimer.restart() }
      else if (k === Qt.Key_Right) { mv.bannerAct = Math.min(mv.fullActions.length - 1, mv.bannerAct + 1); bannerTimer.restart() }
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) mv.fullAct(mv.bannerAct)
      else if (k === Qt.Key_Escape || k === Qt.Key_Backspace || k === Qt.Key_Down || k === Qt.Key_I || k === Qt.Key_Space) mv.bannerUp = false
      else if (k === Qt.Key_Up || k === Qt.Key_PageUp) { mv.flip(1); bannerTimer.restart() }
      else if (k === Qt.Key_PageDown) { mv.flip(-1); bannerTimer.restart() }
      return
    }
    if (mv.mode === "full") {
      if (k === Qt.Key_I || k === Qt.Key_Space) { mv.bannerAct = 0; mv.bannerUp = true; bannerTimer.restart() }
      else if (k === Qt.Key_Escape || k === Qt.Key_Backspace || k === Qt.Key_Return || k === Qt.Key_Enter) mv.mode = "tiles"
      else if (k === Qt.Key_Up || k === Qt.Key_PageUp) mv.flip(1)
      else if (k === Qt.Key_Down || k === Qt.Key_PageDown) mv.flip(-1)
      return
    }
    if (k === Qt.Key_Left) mv.moveSel("left")
    else if (k === Qt.Key_Right) mv.moveSel("right")
    else if (k === Qt.Key_Up) mv.moveSel("up")
    else if (k === Qt.Key_Down) mv.moveSel("down")
    else if (k === Qt.Key_Return || k === Qt.Key_Enter) mv.enter()
    else if (k === Qt.Key_PageUp) mv.flip(1)
    else if (k === Qt.Key_PageDown) mv.flip(-1)
    else if (k === Qt.Key_Delete || k === Qt.Key_X) mv.remove(mv.sel)
    else if (k === Qt.Key_L) mv.cycleLayout()
    else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) mv.exit()
  }

  // The phone remote while Multiview is up: its arrows, OK, BACK, CH+ and
  // CH- work as the keys (↑ ↓ ← →, Enter, Esc, PgUp, PgDn), ⋯ as I (a
  // full-screen tile's banner); on a full-screen tile, as the phone does in
  // full screen, ▲ opens the banner's choices, ▼ closes them and ◀ ▶ change
  // its channel (choose, while they're up); a channel number goes on the selected tile
  // (in the Add a channel list it jumps there, as typing it does); GUIDE
  // leaves for the guide; POWER is the TV off. Mute stays the guide's. True
  // if it took the button.
  function remote(cmd, number) {
    var keyOf = { up: Qt.Key_Up, down: Qt.Key_Down, left: Qt.Key_Left, right: Qt.Key_Right, ok: Qt.Key_Return, back: Qt.Key_Escape,
                  chup: Qt.Key_PageUp, chdown: Qt.Key_PageDown, options: Qt.Key_I }
    if (mv.mode === "full" && ["up", "down", "left", "right"].indexOf(cmd) >= 0) {
      if (cmd === "up") { if (!mv.bannerUp) mv.key({ key: Qt.Key_I }) }
      else if (cmd === "down") { if (mv.bannerUp) mv.key({ key: Qt.Key_Escape }) }
      else if (mv.bannerUp) mv.key({ key: keyOf[cmd] })
      else mv.flip(cmd === "left" ? -1 : 1)
      return true
    }
    if (keyOf[cmd] !== undefined) { mv.key({ key: keyOf[cmd] }); return true }
    if (cmd === "tune" && mv.mode === "picker") {
      for (var k = 0; k < mv.pickRows.length; k++) if (guide.numbers[mv.pickRows[k]] === Number(number)) { mv.pick = k; break }
      return true
    }
    if (cmd === "tune") {
      var r = guide.numbers.indexOf(Number(number)), ch = guide.channels[r]
      if (!ch || mv.slots.indexOf(ch.url) >= 0) return true
      if (mv.askFirst(r)) return true
      var s = mv.slots.slice()
      s[mv.sel] = ch.url
      mv.slots = s
      return true
    }
    if (cmd === "guide") { mv.teardown(); guide.showGuide(); return true }
    if (cmd === "power") { guide.dismiss(); return true }   // the TV off: every tile stops
    // the full / mini button: the selected tile full screen (as Enter), or back to the tiles
    if (cmd === "window") { if (mv.mode === "tiles") mv.enter(); else if (mv.mode === "full") { mv.bannerUp = false; mv.mode = "tiles" } return true }
    // HOME stops the tiles (the guide does it); the transport buttons do nothing here
    if (cmd === "home") return false
    return ["mini", "full", "playpause", "rewind", "forward", "live", "seek"].indexOf(cmd) >= 0
  }

  // Media keys (MPRIS) while Multiview is up: play and pause every tile,
  // next and previous change the selected tile's channel, stop is TV off
  function media(cmd) {
    if (cmd === "stop") { guide.turnOff(); return }
    if (cmd === "next" || cmd === "previous") { mv.flip(cmd === "next" ? 1 : -1); return }
    if (cmd === "play") mv.paused = false
    else if (cmd === "pause") mv.paused = true
    else if (cmd === "playpause") mv.paused = !mv.paused
  }

  // Something else plays instead (an app's media): Multiview goes
  Connections {
    target: mv.guide
    ignoreUnknownSignals: true
    function onAppPlayingChanged() { if (mv.guide.appPlaying && mv.active) mv.teardown() }
  }

  onPickChanged: pickList.positionViewAtIndex(mv.pick, ListView.Contain)

  // ---- what you see ----

  // The background: the theme's colors (mvBackground), a color, or a
  // picture (the theme's, the wallpaper, yours) darkened as set
  Box {
    anchors.fill: parent
    s: mv.guide.look.mvBackground
    unit: mv.u
  }
  Rectangle {
    id: backColor
    anchors.fill: parent
    visible: mv.lookStep === "color" || mv.guide.multiviewBackground.mode === "color" && !!mv.guide.multiviewBackground.color
    color: mv.lookStep === "color" ? mv.pickedColor : mv.guide.multiviewBackground.color || "black"
  }
  Image {
    id: backPicture
    anchors.fill: parent
    visible: !backColor.visible && source.toString() !== "" && status === Image.Ready
    source: mv.active ? mv.guide.multiviewBackdrop : ""
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    sourceSize.width: 1920
  }
  Rectangle {
    anchors.fill: parent
    visible: backPicture.visible
    color: mv.guide.colors.bgBottom
    opacity: mv.guide.multiviewBackground.dim
  }

  // Clicks and the wheel on the background stop here: the screen under
  // Multiview (the guide, Home, the rail) never gets them
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    onWheel: function(wheel) { wheel.accepted = true }
  }

  // The header: MULTIVIEW, how many and the layout, the options bar, the clock
  Item {
    id: header
    visible: mv.mode !== "full"
    x: mv.u * 1.5
    y: 0
    width: mv.width - mv.u * 3
    height: mv.headH
    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: mv.u * 1.2
      Label { id: headTitle; anchors.verticalCenter: parent.verticalCenter; text: "MULTIVIEW"; s: mv.guide.look.title; unit: mv.u }
      // how many and the layout, in the room the options bar leaves
      Label {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, header.width - headTitle.width - barRow.width - mv.u * 3.6)
        elide: Text.ElideRight
        text: mv.count + (mv.count === 1 ? " channel" : " channels") + "  ·  " + mv.layoutName(mv.layout)
        s: mv.guide.look.showing
        unit: mv.u
      }
    }
    Row {
      id: barRow
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: mv.u * 0.8
      Repeater {
        model: mv.mode === "picker" || mv.mode === "look" ? [] : [mv.count >= 4 ? "4 of 4" : "+ Add channel", "Layout: " + mv.layoutName(mv.layout), "Exit Multiview"]
        Box {
          required property string modelData
          required property int index
          readonly property bool on: mv.mode === "bar" && mv.bar === index
          anchors.verticalCenter: parent.verticalCenter
          width: barLabel.implicitWidth + mv.u * 2.4
          height: mv.u * 2.8
          s: on ? mv.guide.look["menuRow:focused"] : mv.guide.look.menuRow
          unit: mv.u * 0.8
          Label { id: barLabel; anchors.centerIn: parent; text: modelData; s: parent.s; unit: mv.u * 0.8 }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { mv.bar = index; mv.barDo(index) } }
        }
      }
      // the background: a gear, not a button
      Box {
        id: gear
        readonly property bool on: mv.mode === "bar" && mv.bar === 3 || mv.mode === "look"
        visible: mv.mode !== "picker" && mv.mode !== "look"
        anchors.verticalCenter: parent.verticalCenter
        width: mv.u * 2.8
        height: mv.u * 2.8
        s: on ? mv.guide.look["menuRow:focused"] : mv.guide.look.menuRow
        unit: mv.u * 0.8
        Icon {
          anchors.centerIn: parent
          name: "gear"
          size: mv.u * 1.5
          stroke: 1.7
          color: gear.s.text && gear.s.text.color ? gear.s.text.color : mv.guide.ink
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mv.barDo(3) }
      }
      Label { anchors.verticalCenter: parent.verticalCenter; text: mv.guide.clock(mv.guide.now); s: mv.guide.look.clock; unit: mv.u }
    }
  }

  // The tiles: four made, the ones on screen placed
  Repeater {
    id: tiles
    model: 4
    Item {
      id: cell
      required property int index
      readonly property var rect: mv.rectOf(index)
      readonly property alias tile: player
      readonly property bool sound: index === mv.sel && mv.count > 1
      readonly property real tu: Math.max(8, Math.min(mv.u * 1.15, width / 32))   // text scale for this tile's size
      visible: mv.active && rect.shown
      x: rect.x
      y: rect.y
      width: rect.w
      height: rect.h
      z: mv.mode === "full" && index === mv.sel ? 5 : 1
      Behavior on x { enabled: mv.mode !== "full"; NumberAnimation { duration: 160 } }
      Behavior on y { enabled: mv.mode !== "full"; NumberAnimation { duration: 160 } }
      Behavior on width { enabled: mv.mode !== "full"; NumberAnimation { duration: 160 } }
      Behavior on height { enabled: mv.mode !== "full"; NumberAnimation { duration: 160 } }

      Box {
        id: frame
        anchors.fill: parent
        visible: mv.mode !== "full"
        s: index === mv.sel ? mv.guide.look["mvTile:current"] : mv.guide.look.mvTile
        unit: cell.tu
      }

      MultiviewTile {
        id: player
        anchors.fill: parent
        anchors.margins: mv.mode === "full" ? 0 : frame.borderWidth
        guide: mv.guide
        url: mv.active ? mv.slots[cell.index] : ""
        quality: mv.qualityOf(cell.index)
        sound: cell.index === mv.sel
        paused: mv.paused
        onUrlChanged: { if (url) tune(); else stop() }
      }

      // what's on it, along the bottom
      Box {
        visible: mv.mode !== "full"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: frame.borderWidth
        height: cell.tu * 3.4
        s: mv.guide.look.mvStrip
        unit: cell.tu
        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: cell.tu * 0.8
          anchors.rightMargin: cell.tu * 0.8
          spacing: cell.tu * 0.15
          Label { width: parent.width; text: mv.nameOf(cell.index); s: mv.guide.look.mvName; unit: cell.tu; elide: Text.ElideRight }
          Label { width: parent.width; text: player.onAir ? mv.guide.showTitle(player.onAir.title) : ""; s: mv.guide.look.mvShow; unit: cell.tu; elide: Text.ElideRight }
        }
      }

      // live, and the sound
      Row {
        visible: mv.mode !== "full"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: cell.tu * 0.7
        spacing: cell.tu * 0.5
        Box {
          visible: !!(player.onAir && player.onAir.live) && player.reception === "on"
          width: liveText.implicitWidth + cell.tu
          height: liveText.implicitHeight + cell.tu * 0.4
          s: mv.guide.look.liveBadge
          unit: cell.tu
          Label { id: liveText; anchors.centerIn: parent; text: "● Live"; s: mv.guide.look.liveBadge; unit: cell.tu }
        }
        Box {
          visible: cell.sound
          width: soundText.implicitWidth + cell.tu
          height: soundText.implicitHeight + cell.tu * 0.4
          s: mv.guide.look.mvSound
          unit: cell.tu
          Label { id: soundText; anchors.centerIn: parent; text: "Sound"; s: mv.guide.look.mvSound; unit: cell.tu }
        }
      }

      // tuning, locked, no signal
      Column {
        anchors.centerIn: parent
        spacing: cell.tu * 0.4
        visible: player.reception === "tuning" || player.reception === "locked" || player.reception === "lost"
        Icon {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: player.reception === "locked"
          name: "lock"
          size: cell.tu * 2.6
          stroke: 1.6
          color: mv.guide.ink
        }
        Label {
          anchors.horizontalCenter: parent.horizontalCenter
          text: player.reception === "tuning" ? "Tuning…" : player.reception === "locked" ? (index === mv.sel ? "Locked · Enter for the passcode" : "Locked")
                : (index === mv.sel ? "No signal · Enter tries again" : "No signal")
          s: mv.guide.look.posterSub
          unit: cell.tu
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { if (mv.mode === "tiles" || mv.mode === "bar") { mv.mode = "tiles"; mv.select(cell.index) } }
        onDoubleClicked: { if (mv.mode === "tiles") { mv.select(cell.index); mv.enter() } else if (mv.mode === "full") mv.mode = "tiles" }
      }
    }
  }

  // Full screen: the tile's banner, with what you can do from here
  LowerThird {
    z: 6
    anchors.fill: parent
    visible: mv.mode === "full" && mv.bannerUp
    readonly property int row: mv.rowOf(mv.sel)
    readonly property var air: mv.tileIn(mv.sel).onAir
    look: mv.guide.look
    image: mv.guide.areaImages ? mv.guide.areaImages.lt : null
    unit: mv.u
    logo: mv.guide.logoFor ? mv.guide.logoFor(mv.guide.channels[row]) : ""
    number: mv.guide.numbers[row] ? String(mv.guide.numbers[row]) : ""
    channel: mv.guide.channels[row] ? mv.guide.channels[row].name : ""
    title: air ? mv.guide.showTitle(air.title) : ""
    progress: air && (!air.live || air.epg) ? Math.max(0, (mv.guide.now - air.start) / Math.max(1, air.end - air.start)) : -1
    clock: mv.guide.clock(mv.guide.now)
    times: !air ? "" : air.live && !air.epg ? "● LIVE" : mv.guide.clock(air.start) + " – " + mv.guide.clock(air.end)
    options: mv.fullActions
    optionFocus: mv.bannerAct
    onOptionPicked: function(i) { mv.bannerAct = i; mv.fullAct(i) }
  }

  // Full screen: which tile it is, and the way back
  Box {
    visible: mv.mode === "full"
    z: 6
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: mv.u * 1.5
    width: mapRow.implicitWidth + mv.u * 2
    height: mv.u * 3
    s: mv.guide.look.box
    unit: mv.u * 0.8
    Row {
      id: mapRow
      anchors.centerIn: parent
      spacing: mv.u * 0.8
      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: mv.u * 0.25
        Repeater {
          model: mv.order
          Rectangle {
            required property int modelData
            width: mv.u * 1.4
            height: mv.u * 0.9
            radius: mv.u * 0.15
            color: modelData === mv.sel ? mv.guide.colors.accent : "transparent"
            border.width: 1
            border.color: modelData === mv.sel ? mv.guide.colors.accent : mv.guide.colors.cellBorder
          }
        }
      }
      Label { anchors.verticalCenter: parent.verticalCenter; text: "MULTIVIEW · " + mv.count; s: mv.guide.look.boxTitle; unit: mv.u * 0.8 }
    }
  }

  // The Add a channel list, down the right
  Box {
    id: drawer
    visible: mv.mode === "picker"
    z: 7
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.margins: mv.u
    anchors.bottomMargin: mv.footH
    width: mv.drawerW
    s: mv.guide.look.box
    unit: mv.u
    Column {
      anchors.fill: parent
      anchors.margins: drawer.padding + mv.u * 0.4
      spacing: mv.u * 0.6
      Label { width: parent.width; text: mv.pickMode === "add" ? "Add a channel" : "Change this tile"; s: mv.guide.look.boxTitle; unit: mv.u; sizeFactor: 1.2 }
      Label {
        width: parent.width
        wrapMode: Text.Wrap
        text: mv.typed ? "Channel " + mv.typed + "…"
              : mv.pickMode === "add" ? mv.count + " of 4 on screen. Each pick adds a tile; type a number to jump to it."
              : "Channels already on another tile are left out."
        s: mv.guide.look.boxText
        unit: mv.u
      }
      ListView {
        id: pickList
        width: parent.width
        height: parent.height - y
        clip: true
        spacing: Math.round(mv.u * 0.3)
        model: mv.mode === "picker" ? mv.pickRows : []
        currentIndex: mv.pick
        boundsBehavior: Flickable.StopAtBounds
        delegate: MenuRow {
          required property int modelData
          required property int index
          guide: mv.guide
          width: pickList.width
          height: implicitHeight
          size: 0.85
          oneClick: true
          focused: index === mv.pick
          label: (mv.guide.numbers[modelData] ? mv.guide.numbers[modelData] + "  " : "") + (mv.guide.channels[modelData] ? mv.guide.channels[modelData].name : "")
          value: mv.guide.channelLock.blocks(mv.guide.channels[modelData]) ? "Locked" : !mv.guide.airs(mv.guide.channels[modelData]) ? "Loading"
                 : mv.guide.secondStreamOf(mv.guide.channels[modelData]) ? "2nd stream" : ""
          onActivated: { mv.pick = index; mv.choose(index) }
        }
      }
    }
  }

  // The gear's panel, down the right: the background's four, the
  // wallpaper's two, or the color picker
  Box {
    id: lookPanel
    readonly property real inner: width - (padding + mv.u * 0.4) * 2
    visible: mv.mode === "look"
    z: 7
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: mv.u
    width: mv.drawerW
    height: lookColumn.implicitHeight + (lookPanel.padding + mv.u * 0.4) * 2
    s: mv.guide.look.box
    unit: mv.u
    Column {
      id: lookColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: lookPanel.padding + mv.u * 0.4
      spacing: mv.u * 0.6
      Label {
        width: parent.width
        text: mv.lookStep === "color" ? "A color" : mv.lookStep === "wallpaper" ? "A custom wallpaper" : "Background"
        s: mv.guide.look.boxTitle
        unit: mv.u
        sizeFactor: 1.2
      }
      Repeater {
        model: mv.lookStep === "color" ? [] : mv.lookRows
        MenuRow {
          required property var modelData
          required property int index
          guide: mv.guide
          width: lookPanel.inner
          height: implicitHeight
          size: 0.85
          oneClick: true
          focused: index === mv.lookCursor
          kind: modelData.kind
          label: modelData.label
          value: modelData.on ? "✓" : ""
          onActivated: { mv.lookCursor = index; mv.lookAct() }
        }
      }
      ColorPicker {
        id: colorPicker
        visible: mv.lookStep === "color"
        width: lookPanel.inner
        unit: Math.min(mv.u * 1.6, lookPanel.inner / 18.6)
        fontFamily: mv.guide.fontFamily
        ink: mv.guide.ink
        dim: mv.guide.dimInk
        accent: mv.guide.marquee
        edge: mv.guide.cellEdge
        swatches: mv.guide.pickerSwatches
        onChanged: function(value) { mv.pickedColor = value }
        onDone: function(keep) { mv.endColor(keep) }
      }
    }
  }

  // What just happened, above the keys
  Label {
    z: 8
    visible: mv.message !== "" && mv.mode !== "full"
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: mv.u * 1.5
    anchors.bottomMargin: mv.guide.showKeyHints ? mv.u * 3.4 : mv.u * 0.8
    text: mv.message
    s: mv.guide.look.showing
    unit: mv.u
  }

  KeyHints {
    z: 8
    visible: mv.guide.showKeyHints
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.leftMargin: mv.u * 1.5
    anchors.bottomMargin: mv.u * 0.8
    size: mv.u * 1.55
    capStyle: mv.guide.look.keycap
    labelStyle: mv.guide.look.keyLabel
    model: mv.mode === "look" && mv.lookStep === "color" ? [{ keys: ["←", "→", "↑", "↓"], label: "Color" }, { keys: ["PGUP", "PGDN"], label: "Hue" }, { keys: ["ENTER"], label: "Keep" }, { keys: ["ESC"], label: "Cancel" }]
         : mv.mode === "look" ? [{ keys: ["↑", "↓"], label: "Choose" }, { keys: ["ENTER"], label: "Pick" }, { keys: ["ESC"], label: mv.lookStep === "wallpaper" ? "Back" : "Done" }]
         : mv.mode === "picker" ? [{ keys: ["↑", "↓"], label: "Choose" }, { keys: ["0–9"], label: "Number" }, { keys: ["ENTER"], label: mv.pickMode === "add" ? "Add" : "Use it" }, { keys: ["ESC"], label: mv.pickMode === "add" ? "Done" : "Cancel" }]
         : mv.mode === "bar" ? [{ keys: ["←", "→"], label: "Choose" }, { keys: ["ENTER"], label: "Pick" }, { keys: ["↓"], label: "Back to the tiles" }]
         : mv.mode === "full" && mv.bannerUp ? [{ keys: ["←", "→"], label: "Choose" }, { keys: ["ENTER"], label: "Pick" }, { keys: ["ESC"], label: "Hide" }]
         : mv.mode === "full" ? [{ keys: ["↑", "↓"], label: "Channel" }, { keys: ["I"], label: "Options" }, { keys: ["ESC"], label: "Back to Multiview" }]
         : [{ keys: ["←", "→", "↑", "↓"], label: "Move the sound" }, { keys: ["ENTER"], label: "Full screen" }, { keys: ["PGUP", "PGDN"], label: "Channel" },
            { keys: ["DEL"], label: "Take off" }, { keys: ["L"], label: "Layout" }, { keys: ["ESC"], label: "Exit Multiview" }]
  }

  Timer { id: messageTimer; interval: 6000; onTriggered: mv.message = "" }
  Timer { id: bannerTimer; interval: 10000; onTriggered: mv.bannerUp = false }
  Timer { id: typedTimer; interval: 1500; onTriggered: mv.typed = "" }
}
