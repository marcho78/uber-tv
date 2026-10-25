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
import { readFileSync } from "node:fs"

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
const stand = (over) => Object.assign({ touchSetting: "auto", touchLatched: false, lastInput: "keyboard", saved: 0, saveSettings() { this.saved++ } }, over || {})
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
{
  const body = block(guideSrc, "onOpenedChanged: {")
  const r = stand({ touchLatched: true, opened: false })
  new Function("root", "remoteStateTimer", body)(r, { restart() {} })
  assert.equal(r.touchLatched, false, "closing Uber TV lets go of Auto's latch")
  const k = stand({ touchLatched: true, opened: true })
  new Function("root", "remoteStateTimer", body)(k, { restart() {} })
  assert.equal(k.touchLatched, true, "opening keeps it")
}
// the watcher over everything, its finger to the latch
assert.match(guideSrc, /TouchWatch \{\n\s+anchors\.fill: parent\n\s+z: 1000000\n\s+onTouched: root\.touchReleased\(\)\n\s+onPointed: if \(root\.lastInput !== "pointer"\) root\.lastInput = "pointer"\n\s+\}/)
assert.ok(guideSrc.indexOf("TouchWatch {") > guideSrc.indexOf("id: appSplash"), "on top of everything in the screen")

// ---- settings.json ----
assert.match(block(guideSrc, "function saveSettings() {"), /keyHints: root\.showKeyHints, touch: root\.touchSetting,/)
assert.match(block(guideSrc, "function applySettings(settingsText) {"), /root\.touchSetting = Touch\.setting\(saved\.touch\)/)

// ---- what was used last ----
const pressed = block(keysSrc, "Keys.onPressed: function(event) {")
assert.ok(pressed.indexOf('guide.lastInput = "keyboard"') >= 0 && pressed.indexOf('guide.lastInput = "keyboard"') < pressed.indexOf("return"), "a key, before anything returns")
const remote = block(guideSrc, "function remoteCommand(cmd, number, by, digits, extra) {")
assert.match(remote, /if \(by === root\.byUser\) \{\n\s+root\.lastInput = "remote"/, "a press on the phone (not an agent)")

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
