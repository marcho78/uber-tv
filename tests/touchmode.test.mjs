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
  "; return { SETTINGS, INPUTS, FINGER_MM, MIN_PX, MAX_PX, setting, on, fingerPx, fit }")()
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
assert.match(guideSrc, /TouchWatch \{\n\s+anchors\.fill: parent\n\s+z: 1000000\n\s+onTouched: root\.touchReleased\(\)\n\s+onPointed: root\.noteInput\("pointer"\)\n\s+\}/)
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
assert.ok(pressed.indexOf('guide.noteInput("keyboard")') >= 0 && pressed.indexOf('guide.noteInput("keyboard")') < pressed.indexOf("return"), "a key, before anything returns")
const remote = block(guideSrc, "function remoteCommand(cmd, number, by, digits, extra) {")
assert.match(remote, /if \(by === root\.byUser\) \{\n\s+root\.noteInput\("remote"\)/, "a press on the phone (not an agent)")
// touch, then the mini player's keys: its own router notes the keyboard first
{
  const body = block(miniSrc, "Keys.onPressed: function(event) {")
  const noted = []
  const guide = { noteInput: (k) => noted.push(k), streamAsk: false, pipSurf() {}, closePip() {}, expandPip() {}, guidePip() {}, showPipBanner() {}, muted: false }
  new Function("guide", "Qt", "event", body)(guide, { Key_Up: 1, Key_PageUp: 2, Key_Down: 3, Key_PageDown: 4, Key_Return: 5, Key_Enter: 6, Key_Y: 7, Key_Escape: 8, Key_Backspace: 9, Key_N: 10, Key_M: 11, Key_G: 12, Key_F: 13, Key_I: 14, Key_Space: 15 }, { key: 1, accepted: false })
  assert.deepEqual(noted, ["keyboard"], "the mini player's ↑ notes the keyboard")
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
      assert.ok(/guide\.noteInput\("keyboard"\)|picker\.keyed\(\)/.test(body), f + ": Keys.on" + m[1] + "Pressed doesn't note the keyboard")
    }
    for (const m of src.matchAll(/\n[ \t]*(TextInput|TextEdit) \{\n/g)) {
      fields++
      const field = braced(src, m.index + m[0].length - 2)
      assert.match(field, /\n[ \t]*Keys\.onPressed: function\(event\) \{/, f + ": a " + m[1] + " with no Keys.onPressed")
      assert.ok(field.length < 4000, f + ": a " + m[1] + " that runs on: " + field.length)
    }
  }
  assert.ok(handlers >= 30 && fields >= 11, "found them: " + handlers + " handlers, " + fields + " fields")
}
assert.match(read("ui/ColorPicker.qml"), /signal keyed\(\)/)
assert.match(read("ui/StylePanel.qml"), /onKeyed: guide\.noteInput\("keyboard"\)/)
assert.match(read("ui/Multiview.qml"), /onKeyed: guide\.noteInput\("keyboard"\)/)

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

console.log("touchmode: ok")
