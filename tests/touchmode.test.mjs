// node tests/touchmode.test.mjs
// Tablet mode's foundations (Touch.js, Guide.qml, GuideKeys.qml,
// Commands.qml), run from their own code with the guide stood in: the
// setting (auto, on, off; anything else is auto), on only when set on or once
// a finger let go in Auto, the latch let go when Uber TV closes; a finger's
// size from the screen's density and scale, inside 44 to 72 px; how much room
// a screen gives (compact, medium, expanded) for real screen shapes; the
// setting kept in settings.json; what was used last (the keys, the phone);
// touchControls and state for agents.
import assert from "node:assert/strict"
import { readFileSync, readdirSync } from "node:fs"

const read = (f) => readFileSync(new URL("../" + f, import.meta.url), "utf8")
const guideSrc = read("Guide.qml")
const keysSrc = read("GuideKeys.qml")
const cmdSrc = read("Commands.qml")
const T = new Function(read("Touch.js").replace(/^\.pragma library\s*/, "") +
  "; return { SETTINGS, INPUTS, FINGER_MM, MIN_PX, MAX_PX, KEY, SHIFT, ACROSS, setting, on, fingerPx, fit, unit, railShows, hoursAcross, rowPx, byFinger, pressable, split, fitCount }")()
const block = (text, opener) => {
  const i = text.indexOf(opener)
  assert.ok(i >= 0, "missing: " + opener)
  const lineStart = text.lastIndexOf("\n", i) + 1
  const indent = text.slice(lineStart, i).match(/^ */)[0]
  const open = text.indexOf("{", i + opener.length - 1)
  const end = text.indexOf("\n" + indent + "}\n", open)
  assert.ok(end > open, "no end: " + opener)
  return text.slice(open + 1, end)
}

// ---- the setting ----
assert.deepEqual(T.SETTINGS, ["auto", "on", "off"])
for (const v of T.SETTINGS) assert.equal(T.setting(v), v)
for (const v of [undefined, null, "", "ON", "Auto", 1, true, "tablet", {}]) assert.equal(T.setting(v), "auto", "anything else is auto: " + JSON.stringify(v))
assert.equal(T.on("auto", false), false, "Auto: off until a finger")
assert.equal(T.on("auto", true), true, "Auto: on once a finger let go")
assert.equal(T.on("on", false), true)
assert.equal(T.on("off", true), false, "Off stays off, a finger or not")
assert.equal(T.on("auto", "true"), false, "only a real latch")

// ---- a finger's size ----
assert.equal(T.fingerPx(7.3, 1, 20), 66, "a 12-inch 1920x1200 tablet at scale 1: 9 mm")
assert.equal(T.fingerPx(7.3, 1.25, 16), 53, "the same at scale 1.25")
assert.equal(T.fingerPx(11.1, 2, 36), 50, "a 15.6-inch 4K laptop at scale 2")
assert.equal(T.fingerPx(3.15, 1, 36), 44, "a 55-inch TV: never under 44 px")
assert.equal(T.fingerPx(50, 1, 20), 72, "a silly density: never over 72 px")
assert.equal(T.fingerPx(0, 1, 20), 64, "no density: 3.2 units")
assert.equal(T.fingerPx(undefined, undefined, 10), 44, "no density, a small unit: still 44 px")
assert.equal(T.fingerPx(NaN, 0, 18), 58, "a broken density and scale: units")
assert.equal(T.fingerPx(Infinity, 1, 18), 58, "an infinite density: units")

// ---- the unit, and how much room ----
// a 60th of the height; on a narrow screen small enough for 50 across
assert.equal(T.ACROSS, 50)
assert.equal(T.unit(1920, 1080), 18, "16:9: a 60th of the height, as always")
assert.equal(T.unit(1920, 1200), 20, "16:10")
assert.equal(T.unit(1600, 941), 16, "this laptop's guide")
assert.equal(T.unit(1024, 768), 13, "4:3")
assert.equal(T.unit(1500, 1000), 17, "3:2")
assert.equal(T.unit(800, 1280), 16, "a 16:10 tablet in portrait: 50 across, not 21 px")
assert.equal(T.unit(1200, 1920), 24, "a big tablet in portrait")
assert.equal(T.unit(900, 1000), 17, "a narrow window: its height still decides")
assert.equal(T.unit(1600, 560), 10, "a short window: never under 10 px")
assert.equal(T.unit(0, 0), 10, "no size yet")
assert.equal(T.unit(NaN, 1080), 18, "no width: the height's")
assert.equal(T.unit(800, undefined), 10, "no height")
// every screen at least as wide as 5:6 gets what it always got
for (const [w, h] of [[1920, 1080], [2560, 1600], [1280, 800], [1024, 768], [1366, 768], [3840, 2160], [1000, 1200], [2736, 1824], [900, 560]])
  assert.equal(T.unit(w, h), Math.max(10, Math.round(h / 60)), "unchanged: " + w + "x" + h)
const fitOf = (w, h) => T.fit(w, T.unit(w, h))
assert.equal(fitOf(1920, 1080), "expanded", "16:9")
assert.equal(fitOf(1920, 1200), "expanded", "16:10")
assert.equal(fitOf(1600, 941), "expanded", "this laptop's guide")
assert.equal(fitOf(1500, 1000), "expanded", "3:2 (a Surface)")
assert.equal(fitOf(1024, 768), "medium", "4:3")
assert.equal(fitOf(800, 1280), "compact", "a 16:10 tablet in portrait")
assert.equal(fitOf(800, 1200), "compact", "a 3:2 tablet in portrait")
assert.equal(fitOf(1200, 1920), "compact", "a big tablet in portrait")
assert.equal(fitOf(900, 1400), "compact", "a narrow window, tiled")
assert.equal(fitOf(1600, 560), "expanded", "a short, wide window")
assert.equal(T.fit(800, 0), "compact", "no unit yet")
for (const [w, h] of [[800, 1280], [800, 1200], [1200, 1920], [900, 1400], [1080, 1920]])
  assert.ok(w / T.unit(w, h) >= 49, "a compact screen has about 50 units across: " + w + "x" + h)
// a compact screen steps the theme's layout down; the others keep it
assert.equal(T.railShows("always", "compact"), "focus", "the rail tucks away")
assert.equal(T.railShows("always", "medium"), "always")
assert.equal(T.railShows("always", "expanded"), "always")
assert.equal(T.railShows("focus", "compact"), "focus")
assert.equal(T.railShows("none", "compact"), "none", "none stays none")
for (const h of [1, 1.5, 2, 2.5, 3]) assert.equal(T.hoursAcross(h, "compact"), 1, "an hour across: " + h)
assert.equal(T.hoursAcross(1.5, "medium"), 1.5)
assert.equal(T.hoursAcross(3, "expanded"), 3)
assert.equal(T.rowPx(30, true, 44), 44, "tablet mode: a finger tall")
assert.equal(T.rowPx(61, true, 44), 61, "a taller row stays")
assert.equal(T.rowPx(30, false, 44), 30, "keys and mouse: the layout's")
// what made a click: a finger (Qt's touch to mouse: 2; the system's: 1), or
// a mouse or touchpad (0); tablet mode on or off has nothing to do with it
const FINGER = { source: 2 }, MOUSE = { source: 0 }
assert.equal(T.byFinger(FINGER), true)
assert.equal(T.byFinger({ source: 1 }), true, "the system's touch to mouse")
assert.equal(T.byFinger(MOUSE), false, "a mouse's own click")
assert.equal(T.byFinger({ source: 3 }), false, "one an app made")
assert.equal(T.byFinger({}), false)
assert.equal(T.byFinger(undefined), false)
// the guide's: a finger's click with tablet mode on (off, a tap is a click)
{
  const body = guideSrc.match(/function isFinger\(mouse\) \{ (.*) \}\n/)[1]
  const isFinger = (touchMode, mouse) => new Function("root", "Touch", "mouse", body)({ touchMode }, T, mouse)
  assert.equal(isFinger(true, FINGER), true)
  assert.equal(isFinger(true, MOUSE), false, "tablet mode on, the mouse: a click")
  assert.equal(isFinger(false, FINGER), false, "tablet mode off: a tap is a click, as before")
}
assert.ok(guideSrc.includes('import "Touch.js" as Touch'))
assert.match(guideSrc, /readonly property real fingerPx: Touch\.fingerPx\(shownScreen \? shownScreen\.physicalPixelDensity : 0, shownScreen \? shownScreen\.devicePixelRatio : 1, u\)/)
assert.match(guideSrc, /readonly property real shownWidth: windowed && guideWindow\.width > 100 \? guideWindow\.width : panel\.width\n/)
assert.match(guideSrc, /readonly property real shownHeight: windowed && guideWindow\.height > 100 \? guideWindow\.height : panel\.height\n/)
assert.match(guideSrc, /readonly property real u: Touch\.unit\(shownWidth, shownHeight\)\n/)
assert.match(guideSrc, /readonly property string screenFit: Touch\.fit\(shownWidth, u\)\n/)
assert.match(guideSrc, /readonly property var shownScreen: windowed \? guideWindow\.screen : panel\.screen/)

// ---- the guide's side: the setting, the latch ----
assert.match(guideSrc, /property string touchSetting: "auto"/)
assert.match(guideSrc, /property bool touchLatched: false/)
assert.match(guideSrc, /readonly property bool touchMode: Touch\.on\(touchSetting, touchLatched\)/)
const noteBody = guideSrc.match(/function noteInput\(kind\) \{ (.*) \}\n/)[1]
const stand = (over) => {
  const r = Object.assign({ touchSetting: "auto", touchLatched: false, lastInput: "keyboard", opened: true, pip: false, saved: 0, saveSettings() { this.saved++ } }, over || {})
  r.noteInput = (kind) => new Function("root", "kind", noteBody)(r, kind)
  r.touchSessionCheck = () => new Function("root", guideSrc.match(/function touchSessionCheck\(\) \{ (.*) \}\n/)[1])(r)
  return r
}
const setTouch = (root, mode) => new Function("root", "Touch", "mode", block(guideSrc, "function setTouch(mode) {"))(root, T, mode)
const touchReleased = (root) => new Function("root", block(guideSrc, "function touchReleased() {"))(root)
{
  const r = stand()
  assert.equal(setTouch(r, "on"), "on"); assert.equal(r.touchSetting, "on"); assert.equal(r.saved, 1, "saved")
  assert.equal(setTouch(r, "bogus"), "auto", "anything else is auto")
  touchReleased(r)
  assert.equal(r.touchLatched, true, "Auto: a finger let go turns them on"); assert.equal(r.lastInput, "touch")
  const o = stand({ touchSetting: "off" })
  touchReleased(o)
  assert.equal(o.touchLatched, false, "Off: a finger changes nothing"); assert.equal(o.lastInput, "touch")
  const n = stand({ touchSetting: "on" })
  touchReleased(n)
  assert.equal(n.touchLatched, false, "On needs no latch")
}
// The latch lasts until Uber TV closes: the guide gone and no mini player,
// checked once a change settles (the guide and the mini player swap places
// through neither). Both handlers only queue the check.
{
  const openedBody = block(guideSrc, "onOpenedChanged: {")
  const pipBody = guideSrc.match(/onPipChanged: \{ (.*) \}\n/)[1]
  assert.match(pipBody, /Qt\.callLater\(root\.touchSessionCheck\)/)
  assert.ok(!/touchLatched/.test(openedBody), "closing the guide alone doesn't let go of the latch")
  const run = (r, changes) => {
    const queue = new Set()
    const Qt = { callLater: (fn) => queue.add(fn) }
    for (const [k, v] of changes) {
      r[k] = v
      if (k === "opened") new Function("root", "remoteStateTimer", "Qt", openedBody)(r, { restart() {} }, Qt)
      if (k === "pip") new Function("root", "remoteStateTimer", "Qt", pipBody)(Object.assign(r, { cancelScrub() {} }), { restart() {} }, Qt)
    }
    for (const fn of queue) fn()
  }
  const r = stand({ touchLatched: true })
  run(r, [["pip", true], ["opened", false]])          // goPip: the mini player, then the guide hides
  assert.equal(r.touchLatched, true, "the guide to the mini player keeps the touch controls")
  run(r, [["pip", false], ["opened", true]])          // open(): back from the mini player
  assert.equal(r.touchLatched, true, "the mini player back to the guide keeps them")
  run(r, [["opened", false]])                         // closeNow() with no mini player
  assert.equal(r.touchLatched, false, "Uber TV closed: Auto starts over")
  const m = stand({ touchLatched: true, opened: false, pip: true })
  run(m, [["pip", false]])                            // closePip(): the mini player closed, the guide already gone
  assert.equal(m.touchLatched, false, "the mini player closed: Auto starts over")
}
// the watcher over everything, its finger to the latch
assert.match(guideSrc, /TouchWatch \{\n\s+anchors\.fill: parent\n\s+z: 1000000\n\s+onTouched: function\(at\) \{ root\.touchReleased\(\); touchKeyboard\.tappedAt\(at\) \}\n\s+onPointed: root\.noteInput\("pointer"\)\n\s+\}/, "a finger: the latch, and the keyboard back on its field")
assert.ok(guideSrc.indexOf("TouchWatch {") > guideSrc.indexOf("id: appSplash"), "on top of everything in the screen")
assert.match(read("ui/TouchWatch.qml"), /acceptedDevices: PointerDevice\.TouchScreen\n(\s+\/\/.*\n)+\s+acceptedButtons: Qt\.NoButton\n/, "no buttons: Qt's mouse from a finger can't end it early")
// the mini player is its own window: its own watcher, a finger there latches too
const miniSrc = read("ui/MiniPlayer.qml")
assert.match(miniSrc, /TouchWatch \{\n\s+anchors\.fill: parent\n\s+z: 10000\n\s+onTouched: guide\.touchReleased\(\)\n\s+onPointed: guide\.noteInput\("pointer"\)\n\s+\}/)
{
  const r = stand({ opened: false, pip: true, lastInput: "touch" })
  touchReleased(r)
  assert.equal(r.touchLatched, true, "a first touch in the mini player turns them on")
}

// ---- settings.json ----
assert.match(block(guideSrc, "function saveSettings() {"), /keyHints: root\.showKeyHints, touch: root\.touchSetting,/)
assert.match(block(guideSrc, "function applySettings(settingsText) {"), /root\.touchSetting = Touch\.setting\(saved\.touch\)/)

// ---- what was used last ----
{
  const r = stand({ lastInput: "touch" })
  r.noteInput("keyboard"); assert.equal(r.lastInput, "keyboard")
  r.noteInput("keyboard"); assert.equal(r.lastInput, "keyboard", "the same again changes nothing")
}
const pressed = block(keysSrc, "Keys.onPressed: function(event) {")
assert.match(pressed, /^\n\s+if \(guide\.keyFirst\(event\)\) return\s+\/\/.*\n\s+keys\.press\(event\)\s*$/, "a real key: keyFirst (the keyboard, the ⋯ panel), then the router")
assert.ok(!/noteInput/.test(block(keysSrc, "function press(event) {")), "the router itself never notes (a touch button runs it too)")
const remote = block(guideSrc, "function remoteCommand(cmd, number, by, digits, extra) {")
assert.match(remote, /if \(by === root\.byUser\) \{\n\s+root\.noteInput\("remote"\)/, "a press on the phone (not an agent)")
// touch, then the mini player's keys: its own router notes the keyboard first
{
  const body = block(miniSrc, "Keys.onPressed: function(event) {")
  const noted = []
  const guide = { keyFirst: (e) => { noted.push("keyboard"); return false }, streamAsk: false, pipSurf() {}, closePip() {}, expandPip() {}, guidePip() {}, showPipBanner() {}, muted: false }
  new Function("guide", "Qt", "event", body)(guide, { Key_Up: 1, Key_PageUp: 2, Key_Down: 3, Key_PageDown: 4, Key_Return: 5, Key_Enter: 6, Key_Y: 7, Key_Escape: 8, Key_Backspace: 9, Key_N: 10, Key_M: 11, Key_G: 12, Key_F: 13, Key_I: 14, Key_Space: 15 }, { key: 1, accepted: false })
  assert.deepEqual(noted, ["keyboard"], "the mini player's ↑ goes through keyFirst")
}
// Every key handler in the guide notes the keyboard, and every text field has
// one that does (typing goes through it): nothing typed is missed
{
  const files = ["Guide.qml", "GuideKeys.qml", "ScreenSaver.qml", "ChannelLock.qml", "AppView.qml", "AppPanel.qml"]
    .concat(readdirSync(new URL("../ui/", import.meta.url)).filter((f) => f.endsWith(".qml")).map((f) => "ui/" + f))
  // from an opening brace to the one that closes it
  const braced = (text, open) => {
    let depth = 0
    for (let i = open; i < text.length; i++) {
      if (text[i] === "{") depth++
      else if (text[i] === "}" && --depth === 0) return text.slice(open, i + 1)
    }
    assert.fail("unclosed brace")
  }
  let handlers = 0, fields = 0
  for (const f of files) {
    const src = read(f)
    for (const m of src.matchAll(/Keys\.on(\w*)Pressed: (function\(event\) \{|\{)?/g)) {
      handlers++
      const body = m[2] ? braced(src, m.index + m[0].length - 1) : src.slice(m.index, src.indexOf("\n", m.index))
      assert.ok(/guide\.keyFirst\(event\)|picker\.keyed\(event\)/.test(body), f + ": Keys.on" + m[1] + "Pressed doesn't go through keyFirst")
    }
    for (const m of src.matchAll(/\n[ \t]*(TextInput|TextEdit) \{\n/g)) {
      fields++
      const field = braced(src, m.index + m[0].length - 2)
      assert.match(field, /\n[ \t]*Keys\.onPressed: function\(event\) \{[^\n]*\n?[^\n]*guide\.keyFirst\(event\)|\n[ \t]*Keys\.onPressed: function\(event\) \{\n[ \t]*picker\.keyed\(event\)/, f + ": a " + m[1] + " whose typed keys miss keyFirst")
      assert.ok(field.length < 4000, f + ": a " + m[1] + " that runs on: " + field.length)
    }
  }
  assert.ok(handlers >= 30 && fields >= 11, "found them: " + handlers + " handlers, " + fields + " fields")
}
assert.match(read("ui/ColorPicker.qml"), /signal keyed\(var event\)/)
assert.equal((read("ui/ColorPicker.qml").match(/picker\.keyed\(event\)\n\s+if \(event\.accepted\) return/g) || []).length, 2, "an Esc used up stops the picker's own")
assert.match(read("ui/StylePanel.qml"), /onKeyed: function\(event\) \{ guide\.keyFirst\(event\) \}/)
assert.match(read("ui/Multiview.qml"), /onKeyed: function\(event\) \{ guide\.keyFirst\(event\) \}/)
// keyFirst: the keyboard; the ⋯ panel goes; an Esc that closed it is used up
{
  const body = block(guideSrc, "function keyFirst(event) {")
  const run = (open, key) => {
    const r = stand({ lastInput: "touch", touchMore: open ? [{}] : null }), ev = { key, accepted: false }
    const used = new Function("root", "Qt", "event", body)(r, { Key_Escape: 0x01000000 }, ev)
    return { used, accepted: ev.accepted, more: r.touchMore, input: r.lastInput }
  }
  assert.deepEqual(run(true, 0x01000000), { used: true, accepted: true, more: null, input: "keyboard" }, "Esc with ⋯ open: only closes it")
  assert.deepEqual(run(true, 0x41), { used: false, accepted: false, more: null, input: "keyboard" }, "a letter with ⋯ open: closes it and goes on to the field")
  assert.deepEqual(run(false, 0x01000000), { used: false, accepted: false, more: null, input: "keyboard" }, "nothing open: Esc goes on")
}

// ---- agents: touchControls and state ----
assert.ok(cmdSrc.includes('import "Touch.js" as Touch'))
assert.match(cmdSrc, /\["touchControls <auto\|on\|off\|\\"\\">", "tablet mode's touch controls: auto \(on once a finger touches the screen, until Uber TV closes\), on or off; \\"\\" just says which, and whether they're on now\. Only when the user asks"\]/)
assert.match(cmdSrc, /keyHints: guide\.showKeyHints, touch: commands\.touchInfo\(\),/)
{
  const guide = { touchSetting: "auto", touchMode: false, lastInput: "keyboard", screenFit: "expanded", setTouch(m) { this.touchSetting = m; this.touchMode = m === "on" } }
  const commands = {
    okReply: (x) => JSON.stringify(Object.assign({ ok: true }, x)), failReply: (m) => JSON.stringify({ ok: false, error: m }),
    touchInfo: () => new Function("guide", block(cmdSrc, "function touchInfo() {"))(guide)
  }
  const run = (mode) => JSON.parse(new Function("commands", "guide", "Touch", "mode", block(cmdSrc, "function touchControls(mode: string): string {"))(commands, guide, T, mode))
  assert.deepEqual(run(""), { ok: true, touch: { setting: "auto", on: false, lastInput: "keyboard", fit: "expanded" } }, "\"\" just says")
  assert.deepEqual(run(" ON "), { ok: true, touch: { setting: "on", on: true, lastInput: "keyboard", fit: "expanded" } })
  assert.deepEqual(run("tablet"), { ok: false, error: "auto, on, off or \"\"" })
  assert.equal(guide.touchSetting, "on", "a refused value changes nothing")
}

// ---- touch buttons: which keys, which hints, how many fit ----
{
  const K = T.KEY, ENTER = 0x01000004, ESC = 0x01000000, SPACE = 0x20, V = 0x56, CTRL = 0x04000000
  assert.equal(T.pressable({ key: ENTER }, false), true)
  assert.equal(T.pressable({ key: SPACE, mods: T.SHIFT }, false), true, "Shift+Space (managing)")
  assert.equal(T.pressable({ key: V, mods: CTRL }, false), false, "no Ctrl, Alt or Meta")
  for (const k of [K.left, K.right, K.up, K.down, K.pageUp, K.pageDown]) {
    assert.equal(T.pressable({ key: k }, false), false, "never the arrows or Page Up/Down: " + k)
  }
  assert.equal(T.pressable({ key: K.l }, false), true, "L outside watching (My List, logos)")
  assert.equal(T.pressable({ key: K.l }, true), false, "never L while watching (it holds to scrub)")
  assert.equal(T.pressable({ key: K.j }, true), false, "nor J")
  for (const bad of [null, undefined, {}, { key: "ENTER" }, { key: 0 }, { key: -1 }, { keys: ["ENTER"] }]) {
    assert.equal(T.pressable(bad, false), false, "only a hint's own numeric key: " + JSON.stringify(bad))
  }
  const run = () => {}
  const s = T.split([
    { keys: ["↑", "↓"], label: "Channel" },
    { keys: ["ENTER"], label: "Watch", touch: { key: ENTER } },
    { keys: ["ESC"], label: "Home", touch: { key: ESC, back: true } },
    { keys: ["ESC"], label: "Second back", touch: { key: ESC, back: true } },
    { keys: ["ENTER"], label: "Save", touch: { run } },
    { keys: [], label: "Checking it…" },
    { keys: ["?"], label: "All keys" },
    { keys: ["X"], label: "Bad", touch: { label: "no key" } },
    null, { keys: ["Y"] }
  ])
  assert.equal(s.back.label, "Home", "the first back")
  assert.deepEqual(s.buttons.map((h) => h.label), ["Watch", "Second back", "Save"], "own keys or a field's action; a second back is a button")
  assert.deepEqual(s.notes.map((h) => h.label), ["Checking it…"], "words with no key")
  assert.deepEqual(T.split(undefined), { back: null, buttons: [], notes: [] })
  assert.equal(T.fitCount([100, 100, 100], 10, 0, 50), 3, "no limit")
  assert.equal(T.fitCount([100, 100, 100], 10, 320, 50), 3, "all fit exactly")
  assert.equal(T.fitCount([100, 100, 100], 10, 319, 50), 2, "not all: room left for ⋯ (50 + 10 + 100 + 10 + 100 = 270)")
  assert.equal(T.fitCount([100, 100, 100], 10, 200, 50), 1)
  assert.equal(T.fitCount([300], 10, 100, 50), 0, "none fit: only ⋯")
}
// the guide's side: touchPress runs the router with the hint's own key, a
// field's action as it is, nothing else; it closes the ⋯ panel first
{
  const body = block(guideSrc, "function touchPress(t) {")
  const ran = []
  const keys = { press: (ev) => { ran.push(ev); ev.accepted = true } }
  const make = (watching) => ({ watching, touchMore: [{}] })
  const press = (root, t) => new Function("root", "Touch", "keys", "t", body)(root, T, keys, t)
  let r = make(false)
  assert.equal(press(r, { key: 0x01000004 }), true)
  assert.deepEqual(ran.pop(), { key: 0x01000004, modifiers: 0, text: "", isAutoRepeat: false, accepted: true }, "a plain record: its key, no text, no repeat")
  assert.equal(r.touchMore, null, "the ⋯ panel goes first")
  press(r, { key: 0x20, mods: T.SHIFT })
  assert.equal(ran.pop().modifiers, T.SHIFT)
  assert.equal(press(make(false), { key: T.KEY.left }), false); assert.equal(ran.length, 0, "an arrow: nothing runs")
  assert.equal(press(make(true), { key: T.KEY.l }), false); assert.equal(ran.length, 0, "L while watching: nothing runs")
  let did = 0
  assert.equal(press(make(false), { run: () => did++ }), true); assert.equal(did, 1, "a field's own action runs as it is")
  assert.equal(ran.length, 0, "without the router")
}
// Every file whose hints are made touch (any hint with a touch:): every hint
// with Esc is a Back button (Back is always there), every touch key is one a
// finger may press, and every button has its own key or action
{
  const files = {}
  for (const f of readdirSync(new URL("../", import.meta.url)).filter((f) => f.endsWith(".qml"))
                  .concat(readdirSync(new URL("../ui/", import.meta.url)).filter((f) => f.endsWith(".qml")).map((f) => "ui/" + f))) {
    const src = read(f)
    if (/touch: \{/.test(src)) files[f] = src
  }
  for (const f of ["Guide.qml", "Backups.qml", "ui/HomeScreen.qml", "ui/SettingsScreen.qml", "ui/NavRail.qml", "ui/LibraryScreen.qml",
                   "ui/SearchScreen.qml", "ui/AppsScreen.qml", "ui/DetailBox.qml", "ui/AppScreen.qml", "ui/AppCustomize.qml"])
    assert.ok(f in files, f + ": its hints are touch")
  const braced = (text, open) => {
    let depth = 0
    for (let i = open; i < text.length; i++) {
      if (text[i] === "{") depth++
      else if (text[i] === "}" && --depth === 0) return text.slice(open, i + 1)
    }
    assert.fail("unclosed")
  }
  let escs = 0, keyed = 0
  for (const [f, src] of Object.entries(files)) {
    for (const m of src.matchAll(/\{ keys: \[([^\]]*)\]/g)) {
      const hint = braced(src, m.index)
      if (/"ESC"/.test(m[1])) {
        escs++
        assert.match(hint, /back: true/, f + ": an Esc hint that isn't Back: " + hint.slice(0, 90))
      }
      for (const k of hint.matchAll(/touch: \{ key: Qt\.Key_(\w+)/g)) {
        keyed++
        assert.ok(!["Left", "Right", "Up", "Down", "PageUp", "PageDown"].includes(k[1]), f + ": a touch button with an arrow or Page key: " + k[1])
      }
      if (/touch: \{ (?!run|key)/.test(hint) && !/touch: \{\}/.test(hint)) assert.fail(f + ": a touch with neither key nor run: " + hint.slice(0, 90))
    }
  }
  assert.ok(escs >= 30 && keyed >= 40, "found them: " + escs + " Esc hints, " + keyed + " touch keys")
  // the style panel's hints come in rows, the same rules
  const styleHints = block(guideSrc, "readonly property var styleHintRows: {")
  for (const m of styleHints.matchAll(/\{ keys: \[([^\]]*)\]/g)) {
    if (/"ESC"/.test(m[1])) assert.match(braced(styleHints, m.index), /back: true/, "the style panel: Esc is Back")
  }
}
// Every MenuRow: ‹ › and the switch are their own targets only where its user
// handles them (touchParts); a choice row's user always does, and a row that
// opens and switches handles the switch. Elsewhere a tap is the whole row.
{
  const files = ["ChannelLock.qml"].concat(readdirSync(new URL("../ui/", import.meta.url)).filter((f) => f.endsWith(".qml")).map((f) => "ui/" + f))
  const braced = (text, open) => {
    let depth = 0
    for (let i = open; i < text.length; i++) {
      if (text[i] === "{") depth++
      else if (text[i] === "}" && --depth === 0) return text.slice(open, i + 1)
    }
    assert.fail("unclosed")
  }
  let rows = 0, parted = 0
  for (const f of files) {
    const src = read(f)
    for (const m of src.matchAll(/MenuRow \{/g)) {
      rows++
      const row = braced(src, m.index + m[0].length - 1)
      const where = f + " line " + (src.slice(0, m.index).split("\n").length)
      const parts = /\n\s+touchParts: true\n/.test(row)
      if (/"choice"/.test(row)) assert.ok(parts && /\n\s+onStepped: /.test(row), where + ": a choice row whose ‹ › aren't handled")
      if (parts) {
        parted++
        assert.ok(/\n\s+onStepped: /.test(row), where + ": touchParts without onStepped")
        if (/\n\s+more: /.test(row)) assert.ok(/\n\s+onToggled: /.test(row), where + ": a switch that opens, its switch not handled")
      }
    }
  }
  assert.ok(rows >= 25 && parted >= 6, "found them: " + rows + " rows, " + parted + " with parts")
  assert.match(read("ui/MenuRow.qml"), /readonly property bool parted: touching && touchParts/)
}
// The table and the board, tablet mode on: a tap chooses a channel and a
// tap on the one chosen watches it; a mouse's click only chooses (a double
// click watches); in the channel manager a tap marks, never watches
const fingerGuide = (over) => Object.assign({ touchMode: true, isFinger(m) { return this.touchMode && T.byFinger(m) } }, over)
for (const f of ["ui/ChannelTable.qml", "ui/FlapBoard.qml"]) {
  const src = read(f)
  const at = src.indexOf("// a finger: a tap on the channel already chosen watches it")
  assert.ok(at > 0, f + ": the row's tap")
  const run = new Function("guide", "rowItem", "mouse", block(src.slice(at), "onClicked: function(mouse) {"))
  const make = (managing, row) => fingerGuide({ managing, row, watched: [], marked: [],
                                                watch(r) { this.watched.push(r) }, toggleMark(r) { this.marked.push(r) } })
  let g = make(false, 3); run(g, { r: 5 }, FINGER)
  assert.deepEqual([g.row, g.watched], [5, []], f + ": a first tap chooses")
  g = make(false, 5); run(g, { r: 5 }, FINGER)
  assert.deepEqual(g.watched, [5], f + ": a tap on the one chosen watches")
  g = make(false, 5); run(g, { r: 5 }, MOUSE)
  assert.deepEqual(g.watched, [], f + ": a mouse's click only chooses, tablet mode on")
  g = make(true, 5); run(g, { r: 5 }, FINGER)
  assert.deepEqual([g.watched, g.marked], [[], [5]], f + ": in the manager a tap marks")
  g = make(false, 5); g.touchMode = false; run(g, { r: 5 }, FINGER)
  assert.deepEqual(g.watched, [], f + ": tablet mode off, a tap is a click")
  assert.match(src.slice(at, at + 600), /onDoubleClicked: if \(!guide\.managing\) guide\.watch\(rowItem\.r\)/, f + ": a double click watches")
}
// The grid in tablet mode: a tap chooses a show, a tap on the one chosen
// watches it (a double click too, as before), a finger held on one opens its
// choices; with the mouse a hold does nothing. A finger dragged sideways
// moves the window a half hour per half hour's width, never before now nor
// past the end, the cursor kept in it; Now goes back. A channel's cell
// watches at once, as it always has (the manager: marks).
{
  const grid = read("ui/ProgramGrid.qml")
  const at = grid.indexOf("// a finger: a tap on the show already chosen watches it")
  assert.ok(at > 0)
  const area = grid.slice(at, at + 1200)
  const tap = new Function("guide", "rowItem", "cell", "chosen", "mouse", block(area, "onClicked: function(mouse) {"))
  const hold = new Function("guide", "rowItem", "cell", "mouse", block(area, "onPressAndHold: function(mouse) {"))
  const make = () => fingerGuide({ row: 2, cursorTime: 0, windowStart: 1000, watched: [], choices: 0,
                                   watch(r) { this.watched.push(r) }, openShowChoices() { this.choices++ } })
  let g = make(); tap(g, { r: 5 }, { modelData: { start: 1600 } }, false, FINGER)
  assert.deepEqual([g.row, g.cursorTime, g.watched], [5, 1600, []], "a first tap chooses the show")
  g = make(); tap(g, { r: 5 }, { modelData: { start: 400 } }, false, FINGER)
  assert.equal(g.cursorTime, 1000, "a show begun before the window: the cursor at the window's start")
  g = make(); tap(g, { r: 5 }, { modelData: { start: 1600 } }, true, FINGER)
  assert.deepEqual(g.watched, [5], "a tap on the one chosen watches it")
  g = make(); tap(g, { r: 5 }, { modelData: { start: 1600 } }, true, MOUSE)
  assert.deepEqual(g.watched, [], "a mouse's click only chooses, tablet mode on")
  assert.match(area, /onDoubleClicked: guide\.watch\(rowItem\.r\)/)
  assert.match(area, /readonly property bool chosen: guide\.row === rowItem\.r && !!guide\.selected && guide\.selected\.start === cell\.modelData\.start/)
  g = make(); hold(g, { r: 7 }, { modelData: { start: 1600 } }, FINGER)
  assert.deepEqual([g.row, g.cursorTime, g.choices], [7, 1600, 1], "a held finger: its choices")
  g = make(); hold(g, { r: 7 }, { modelData: { start: 1600 } }, MOUSE)
  assert.deepEqual([g.row, g.choices], [2, 0], "a held mouse button: nothing, tablet mode on")
  // the drag: a finger's only
  assert.match(grid, /DragHandler \{\n\s+id: timeDrag\n\s+enabled: guide\.touchMode\n\s+acceptedDevices: PointerDevice\.TouchScreen\n\s+target: null\n\s+xAxis\.enabled: true\n\s+yAxis\.enabled: false\n/)
  assert.match(grid, /onActiveTranslationChanged: if \(active\) guide\.dragTime\(from - Math\.round\(activeTranslation\.x \/ Math\.max\(1, gridArea\.slotW\)\)\)/, "a half hour per half hour's width, to the left is later")
  const drag = new Function("root", block(guideSrc, "function dragTime(offset) {").replace(/\boffset\b/g, "root.offset"))
  const r = { maxSlotOffset: 24, slotOffset: 0, cursorAt: 123, cursorTime: 0 }
  for (const [o, want] of [[3, 3], [-2, 0], [99, 24], [2.6, 3], [0, 0]]) {
    r.offset = o; drag(r)
    assert.equal(r.slotOffset, want, "dragged to " + o)
  }
  assert.equal(r.cursorTime, 123, "the cursor kept in the window")
  const now = new Function("root", block(guideSrc, "function timeToNow() {"))
  const n = { slotOffset: 9, cursorTime: 0 }; now(n)
  assert.equal(n.slotOffset, 0)
  assert.ok(Math.abs(n.cursorTime - Date.now() / 1000) < 5, "Now: the cursor now")
  // a channel's cell
  const chan = grid.slice(grid.indexOf("MouseArea {", grid.indexOf("color: guide.nowLine")), grid.indexOf("id: lane"))
  const chanTap = new Function("guide", "rowItem", block(chan, "onClicked: {"))
  g = { row: 0, managing: false, watched: [], marked: [], watch(x) { this.watched.push(x) }, toggleMark(x) { this.marked.push(x) } }
  chanTap(g, { r: 4 })
  assert.deepEqual([g.row, g.watched], [4, [4]], "a channel's cell watches")
  g.managing = true; g.watched = []; chanTap(g, { r: 6 })
  assert.deepEqual([g.watched, g.marked], [[], [6]], "the manager: it marks")
}
// Cards (Home, the Library, Search): a click picks and a double click
// opens; a finger opens at once. An app's screen: a click puts the cursor
// there and a second opens; a finger opens at once.
{
  const cards = read("ui/CardRows.qml")
  const line = (name) => {
    const m = cards.match(new RegExp("\\n\\s+" + name + ": function\\(mouse\\) \\{ (.*) \\}\\n"))
    assert.ok(m, name)
    return m[1]
  }
  const click = new Function("rowsView", "rowItem", "card", "mouse", line("onClicked"))
  const dbl = new Function("rowsView", "rowItem", "card", "mouse", line("onDoubleClicked"))
  const rv = () => ({ guide: fingerGuide({}), did: [], select(r, c) { this.did.push("select " + r + "," + c) }, open(r, c) { this.did.push("open " + r + "," + c) } })
  let v = rv(); click(v, { index: 1 }, { index: 2 }, FINGER); dbl(v, { index: 1 }, { index: 2 }, FINGER)
  assert.deepEqual(v.did, ["select 1,2", "open 1,2"], "a finger opens once, at the first tap")
  v = rv(); click(v, { index: 1 }, { index: 2 }, MOUSE)
  assert.deepEqual(v.did, ["select 1,2"], "a mouse's click picks, tablet mode on")
  dbl(v, { index: 1 }, { index: 2 }, MOUSE)
  assert.deepEqual(v.did, ["select 1,2", "open 1,2"], "a double click opens")
  v = rv(); v.guide.touchMode = false; click(v, { index: 1 }, { index: 2 }, FINGER)
  assert.deepEqual(v.did, ["select 1,2"], "tablet mode off: a tap picks, as a click")
  const app = read("ui/AppScreen.qml")
  const tapBody = block(app, "function tap(line, col, finger) {")
  const tap = new Function("page", "view", "guide", "line", "col", "finger", tapBody)
  const make = (sel) => ({ page: { sel }, view: { entered: 0, pick() { return true }, enter() { this.entered++ } }, guide: fingerGuide({ byUser: {} }) })
  let t = make({ line: 0, col: 0 }); tap(t.page, t.view, t.guide, 1, 3, false)
  assert.equal(t.view.entered, 0, "a mouse's click, tablet mode on: the cursor there")
  t = make({ line: 1, col: 3 }); tap(t.page, t.view, t.guide, 1, 3, false)
  assert.equal(t.view.entered, 1, "a second click opens")
  t = make({ line: 0, col: 0 }); tap(t.page, t.view, t.guide, 1, 3, true)
  assert.equal(t.view.entered, 1, "a finger opens at once")
  t = make(null); t.view.pick = () => false; tap(t.page, t.view, t.guide, 1, 3, true)
  assert.equal(t.view.entered, 0, "nothing there: nothing opens")
  // every item's click says whether it was a finger's (the hero's too); its
  // dots choose; tests/qml/tst_appscreen.qml taps and clicks them for real
  for (const name of ["button", "listRow", "tableRow", "rowCard", "gridCard"])
    assert.ok(app.includes("onClicked: function(mouse) { page.tap(lineItem.index, " + name + ".index, guide.isFinger(mouse)) }"), name)
  assert.match(app, /onTapped: function\(c, finger\) \{ page\.tap\(lineItem\.index, c, finger\) \}\n\s+onChose: function\(c\) \{ page\.view\.pick\(lineItem\.index, c\) \}/)
  const hero = read("ui/AppHero.qml")
  assert.match(hero, /onClicked: function\(mouse\) \{ hero\.tapped\(hero\.col, hero\.guide\.isFinger\(mouse\)\) \}/)
  assert.match(hero, /spacing: hero\.guide\.touchMode \? Math\.max\(hero\.u \* 0\.5, hero\.guide\.fingerPx - dot\) : hero\.u \* 0\.5/, "the dots a finger apart")
  const page = read("ui/AppPage.qml")
  assert.match(page, /interactive: guide\.touchMode\n\s+onMovementEnded: view\.pageY = contentY\n/, "an article scrolls under a finger, the keys going on from there")
}
// Tablet mode being on never decides what a click does: no click handler
// (a click, a double click, a hold, a row's activation, an app's tap) reads
// touchMode; a finger's click says so itself (isFinger, MenuRow's byFinger)
{
  const handlers = /\b(onClicked|onDoubleClicked|onPressAndHold|onActivated|onTapped|onPressed|onReleased): /g
  const braced = (text, open) => {
    let depth = 0
    for (let i = open; i < text.length; i++) {
      if (text[i] === "{") depth++
      else if (text[i] === "}" && --depth === 0) return text.slice(open, i + 1)
    }
    return text.slice(open)
  }
  const files = readdirSync(new URL("../", import.meta.url)).filter((f) => f.endsWith(".qml"))
    .concat(readdirSync(new URL("../ui/", import.meta.url)).filter((f) => f.endsWith(".qml")).map((f) => "ui/" + f))
  let seen = 0
  for (const f of files) {
    const src = read(f)
    for (const m of src.matchAll(handlers)) {
      const rest = src.slice(m.index + m[0].length)
      const brace = rest.search(/\{/), nl = rest.indexOf("\n")
      const body = brace >= 0 && (nl < 0 || brace < nl) ? braced(rest, brace) : rest.slice(0, nl)
      seen++
      assert.ok(!/touchMode/.test(body), f + " line " + src.slice(0, m.index).split("\n").length + ": a click deciding by tablet mode: " + body.slice(0, 120))
    }
    for (const m of src.matchAll(/function tap\([^)]*\) \{/g)) assert.ok(!/touchMode/.test(braced(src, m.index + m[0].length - 1)), f + ": tap() by tablet mode")
  }
  assert.ok(seen >= 100, "found the handlers: " + seen)
  const menu = read("ui/MenuRow.qml")
  assert.match(menu, /onClicked: function\(mouse\) \{ row\.byFinger = row\.guide\.isFinger\(mouse\); row\.tapAt\(mouse\.x\) \}/)
  assert.match(menu, /onDoubleClicked: function\(mouse\) \{ row\.byFinger = row\.guide\.isFinger\(mouse\); if \(!row\.oneClick\) row\.tapAt\(mouse\.x\) \}/)
  // the rows that pick with a click and act with a tap go by it
  const dlg = read("ui/DialogBox.qml")
  assert.equal((dlg.match(/!byFinger/g) || []).length, 5, "the review's folds (3), apps, phones")
  assert.match(dlg, /guide\.showCursor === index \|\| byFinger/)
  assert.match(dlg, /if \(guide\.isFinger\(mouse\)\) guide\.choosePick\(guide\.byUser\)/)
  assert.match(read("ui/LockBox.qml"), /if \(!byFinger\) return \} lockBox\.lock\.act/)
  const app = read("ui/AppScreen.qml")
  assert.match(app, /if \(view\.settingsCursor !== index\) \{ view\.settingsCursor = index; if \(!byFinger\) return \}/)
  const home = read("ui/HomeScreen.qml")
  assert.match(home, /if \(card\.modelData\.kind === "app" \|\| guide\.isFinger\(mouse\)\) guide\.homeOpen\(\)/)
  assert.match(home, /onDoubleClicked: function\(mouse\) \{ if \(card\.modelData\.kind !== "app" && !guide\.isFinger\(mouse\)\) guide\.homeOpen\(\) \}/)
  // in tablet mode the rail's items and an app's buttons are a finger tall
  assert.match(read("ui/NavRail.qml"), /readonly property real itemH: Math\.round\(Math\.max\(u \* 3, guide\.touchMode \? guide\.fingerPx : 0\)\)/)
  assert.equal((read("ui/NavRail.qml").match(/height: rail\.itemH\n/g) || []).length, 2, "both groups")
  // (an app's buttons from the model's geometry: AppLooks.geometry with tablet
  // mode's finger, tests/applooks.test.mjs; their line makes room for them)
  assert.match(app, /y: page\.geo\.actionY\n/)
  assert.match(app, /height: page\.geo\.actionH   /)
  assert.match(read("AppView.qml"), /touch: guide\.touchMode \? guide\.fingerPx : 0,/)
}
// A compact screen's layout (the mockup's portrait): the rail tucked away
// with ☰ on the masthead, the preview no wider than half beside the words,
// an hour across, the table across (the TV in the info area), Settings'
// parts or rows across, the Library's tabs sliding before the clock, Home's
// title across, three apps a row. In tablet mode a channel's row is a
// finger tall in the grid, the table and the board.
{
  assert.match(guideSrc, /readonly property int slotsShown: Math\.round\(Touch\.hoursAcross\(layout\.hours, screenFit\) \* 2\)/)
  assert.match(guideSrc, /readonly property real rowH: Touch\.rowPx\(u \* layout\.rowHeight, touchMode, fingerPx\)\n/)
  assert.match(guideSrc, /function fingerRow\(px\) \{ return Touch\.rowPx\(px, root\.touchMode, root\.fingerPx\) \}/)
  assert.match(guideSrc, /readonly property string railShows: Touch\.railShows\(layout\.rail, screenFit\)\n/)
  assert.match(guideSrc, /readonly property real railSpace: railShows === "always" \? Math\.round\(u \* layout\.railWidth\) : 0\n/)
  assert.match(guideSrc, /readonly property bool railButtonUp: railShows === "focus" && layout\.masthead === "title" && \(screenFit === "compact" \|\| touchMode\)\n/)
  assert.match(guideSrc, /\.concat\(railShows === "focus" && !railButtonUp \? \[\{ keys: \["←"\], label: "Nav rail", touchOnly: true/, "the guide's bar: Nav rail only without ☰")
  assert.match(guideSrc, /listLoader\.item\.videoSlot && listLoader\.item\.panes \? listLoader\.item\.videoSlot : infoPanel\.videoSlot/, "the TV: the table's preview only while it shows")
  assert.match(guideSrc, /readonly property int appsCols: screenFit === "compact" \? 3 : 5/)
  const mast = read("ui/Masthead.qml")
  assert.match(mast, /height: Math\.max\(guide\.u \* 3, guide\.railButtonUp \? guide\.fingerPx : 0\)/)
  assert.match(mast, /TouchButton \{\n\s+visible: guide\.railButtonUp\n[^}]*icon: "menu"\n\s+accessibleName: "Nav rail"\n\s+onTapped: masthead\.guide\.openRail\(\)/)
  assert.match(read("ui/NavRail.qml"), /visible: guide\.railEditing \|\| \(guide\.railShows !== "none" && \(guide\.railShows === "always" \|\| guide\.railOpen\) && !guide\.watching\)/)
  // what draws the rail goes by railShows; only the setting itself (its
  // row, its panel, agents) reads layout.rail
  for (const f of readdirSync(new URL("../ui/", import.meta.url)).filter((f) => f.endsWith(".qml")).map((f) => "ui/" + f).concat(["Guide.qml"])) {
    for (const m of read(f).matchAll(/layout\.rail === "(focus|always)"/g)) {
      const line = read(f).slice(0, m.index).split("\n").length
      const text = read(f).split("\n")[line - 1]
      assert.ok(/settingValue|key === "rail"|railModeLabel/.test(text), f + " line " + line + ": the rail drawn by layout.rail, not railShows")
    }
  }
  // every screen whose rail can tuck away offers it to a finger
  for (const f of ["ui/HomeScreen.qml", "ui/SearchScreen.qml", "ui/AppsScreen.qml", "ui/SettingsScreen.qml", "ui/LibraryScreen.qml", "ui/AppScreen.qml"])
    assert.match(read(f), /guide\.railShows === "focus" \? (\[\{ keys: \["←"\], label: "Nav rail", touchOnly: true, touch: )?\{ run: function\(\) \{ (page|home|lib)\.guide\.openRail\(\) \}, icon: "menu" \}/, f + ": Nav rail for a finger")
  const info = read("ui/InfoPanel.qml")
  assert.match(info, /height: guide\.screenFit === "compact" && layout\.preview !== "none"\n\s+\? Math\.max\(0, Math\.min\(guide\.u \* layout\.infoHeight, Math\.round\(\(width - area\.padding \* 2 - guide\.u\) \/ 2 \* 9 \/ 16 \+ area\.padding \* 2\)\)\)\n\s+: guide\.u \* layout\.infoHeight/)
  const table = read("ui/ChannelTable.qml")
  assert.match(table, /readonly property real lineH: Math\.round\(guide\.fingerRow\(rowH\)\)/)
  assert.match(table, /readonly property bool panes: guide\.screenFit !== "compact"/)
  assert.match(table, /width: table\.panes \? Math\.round\(table\.width \* table\.layout\.tableWidth\) : table\.width/)
  assert.equal((table.match(/visible: table\.panes\n/g) || []).length, 2, "the preview and lineup panes")
  assert.equal((table.match(/height: table\.lineH\n/g) || []).length, 2, "a channel's row and a show's in the lineup")
  assert.match(table, /height: headH \+ table\.lineH\n/)
  assert.match(table, /model: lineup\.shows\.slice\(0, Math\.max\(1, lineup\.room\)\)/)
  assert.match(table, /id: lineupNotes\n\s+visible: lineup\.room >= 1\n/, "the notes give way to the one show that fits")
  const board = read("ui/FlapBoard.qml")
  assert.match(board, /readonly property real tileH: Math\.round\(rowH \* 0\.78\)\n/, "the flaps from the layout's row")
  assert.match(board, /readonly property real lineH: Math\.round\(guide\.fingerRow\(rowH\)\)/)
  assert.match(board, /height: headH \+ board\.lineH\n/)
  assert.match(board, /height: board\.lineH\n/)
  const settings = read("ui/SettingsScreen.qml")
  assert.match(settings, /readonly property bool stacked: guide\.screenFit === "compact"/)
  assert.match(settings, /visible: !page\.stacked \|\| !guide\.settingsInRows\n\s+width: page\.stacked \? page\.width - page\.u \* 6 : /)
  assert.match(settings, /x: page\.stacked \? page\.u \* 3 : parts\.x \+ parts\.width \+ page\.u \* 2\.4\n\s+anchors\.top: parts\.top\n\s+visible: !page\.stacked \|\| guide\.settingsInRows/)
  assert.match(settings, /guide\.settingsInRows = page\.stacked; guide\.settingsArmed = ""/, "a tap on a part goes in when stacked")
  const lib = read("ui/LibraryScreen.qml")
  assert.match(lib, /width: Math\.max\(0, Math\.min\(tabRow\.width, clockLabel\.x - x - lib\.u \* 2\)\)/, "the tabs end before the clock")
  assert.match(lib, /interactive: contentWidth > width/)
  assert.match(lib, /anchors\.topMargin: -tabStrip\.reach\n\s+anchors\.bottomMargin: -tabStrip\.reach/, "a finger tall")
  const home = read("ui/HomeScreen.qml")
  assert.match(home, /width: home\.compact \? parent\.width - home\.u \* 6 : Math\.min\(parent\.width \* 0\.58, home\.u \* 56\)/)
  assert.match(home, /home\.heroY \+ home\.u \* \(home\.compact \? 16 : 13\.3\)/)
  assert.match(read("ui/AppsScreen.qml"), /interactive: guide\.touchMode/)
}
assert.match(guideSrc, /property var touchMore: null/)
// the keyboard: Search's box brings it back after Hide (Search has no field)
assert.match(guideSrc, /function showTouchKeyboard\(\) \{ touchKeyboard\.hidden = false \}/)
assert.match(read("ui/SearchScreen.qml"), /onClicked: \{ guide\.searchInResults = false; guide\.showTouchKeyboard\(\) \}/)
// and keeps the field above it, lifting its surface (tests/qml/tst_touchlift.qml)
assert.match(read("ui/TouchKeyboard.qml"), /onFieldChanged: \{ hidden = false; numbers = false; shift = false; Qt\.callLater\(kb\.relift\) \}/)
assert.match(guideSrc, /TouchMore \{\n\s+anchors\.fill: parent\n\s+z: 900000\n\s+guide: root\n\s+\}/, "the ⋯ panel over everything but the watcher")


console.log("touchmode: ok")
