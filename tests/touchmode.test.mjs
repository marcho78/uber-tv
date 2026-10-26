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
  "; return { SETTINGS, INPUTS, FINGER_MM, MIN_PX, MAX_PX, KEY, SHIFT, setting, on, fingerPx, fit, pressable, split, fitCount }")()
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

// ---- how much room ----
const u = (h) => Math.max(10, Math.round(h / 60))   // Guide.qml's u
const fitOf = (w, h) => T.fit(w, u(h))
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
assert.ok(guideSrc.includes('import "Touch.js" as Touch'))
assert.match(guideSrc, /readonly property real fingerPx: Touch\.fingerPx\(shownScreen \? shownScreen\.physicalPixelDensity : 0, shownScreen \? shownScreen\.devicePixelRatio : 1, u\)/)
assert.match(guideSrc, /readonly property string screenFit: Touch\.fit\(windowed && guideWindow\.width > 100 \? guideWindow\.width : panel\.width, u\)/)
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
// The hint lists made touch so far (the guide's, the boxes', Home's, Settings',
// the nav rail's, the style panel's, the backups'): every hint with Esc is a
// Back button (Back is always there), every touch key is one a finger may
// press, and every button has its own key or action
{
  const files = { "Guide.qml": guideSrc, "Backups.qml": read("Backups.qml"), "ui/HomeScreen.qml": read("ui/HomeScreen.qml"),
                  "ui/SettingsScreen.qml": read("ui/SettingsScreen.qml"), "ui/NavRail.qml": read("ui/NavRail.qml") }
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
assert.match(guideSrc, /property var touchMore: null/)
assert.match(guideSrc, /TouchMore \{\n\s+anchors\.fill: parent\n\s+z: 900000\n\s+guide: root\n\s+\}/, "the ⋯ panel over everything but the watcher")


console.log("touchmode: ok")
