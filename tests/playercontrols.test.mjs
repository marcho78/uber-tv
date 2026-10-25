// node tests/playercontrols.test.mjs
// The TV's player controls and scrubbing (Guide.qml, GuideKeys.qml,
// Timeshift.qml), run from their own code with the guide stood in:
// ▲ once is the banner's choices without the pause ones; ▲ again the player
// controls while pause and rewind runs, or the banner saying it's off (Turn
// on) or why it can't run; ▼ back a layer; a held ← → (or J, L) scrubs on
// its own clock (10 s steps for the first second, 30 s the next, then a
// minute), stays inside what's kept (past the newest end is Live) and jumps
// once when let go, only if it's still what was playing; a tap steps 30 s on
// the player controls, J or L does with nothing open, a movie's tap is 10 s;
// with pause and rewind not running a hold answers as J does; a missed
// letting go never sticks. The phone: ▲ from the choices, the controls'
// arrows and OK, and seek along the card's bar (refused for something else).
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const read = (f) => readFileSync(new URL("../" + f, import.meta.url), "utf8")
const guideSrc = read("Guide.qml")
const keysSrc = read("GuideKeys.qml")
const tsSrc = read("Timeshift.qml")
const Ts = new Function(read("Timeshift.js").replace(/^\.pragma library\s*/, "") + "; return { chip, span, NEAR }")()
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
const argsOf = (opener) => opener.match(/\(([^)]*)\)/)[1].split(",").map((s) => s.trim()).filter(Boolean)

const FUNCS = ["function openPlayerControls(fromChoices) {", "function controlsAct(what) {", "function scrubStart(dir, byKey, at) {", "function scrubStep() {",
               "function scrubTo(frac) {", "function scrubEnd() {", "function cancelScrub() {", "function scrubKeyDown(dir, jl) {", "function holdBegan() {",
               "function scrubKeyUp() {", "function bannerBack() {", "function hideBanner() {", "function openBannerOptions() {", "function remoteSeek(at, play) {"]

function stand(over) {
  const did = []
  const clock = { now: 1000 }
  const timer = (name) => ({ running: false, start() { this.running = true; did.push([name + ".start"]) }, restart() { this.running = true; did.push([name + ".restart"]) }, stop() { this.running = false; did.push([name + ".stop"]) } })
  const ts = Object.assign({ turnedOn: true, active: true, paused: false, point: 600000, liveEnd: 900000, win: { oldest: 300000, live: 899000 }, behind: 300000,
                             cantPauseText: "", togglePause: () => did.push(["ts.togglePause"]), back: () => did.push(["ts.back"]), forward: () => did.push(["ts.forward"]),
                             live: () => did.push(["ts.live"]), seekTo: (t) => did.push(["ts.seekTo", t]) }, (over || {}).ts || {})
  const root = Object.assign({ watching: true, vod: null, pip: false, appPlaying: false, reception: "on", started: true, playSig: "A", playToken: 5,
                               bannerOptions: false, bannerShown: false, playerControls: false, tsOffMenu: false, tsCantMenu: false, tsMenuFromChoices: false,
                               recStopMenu: false, streamAsk: null, bannerAct: 3, scrub: null, keyHold: null, vodBarShown: false,
                               seekVod: (s) => did.push(["seekVod", s]), seekVodTo: (s) => did.push(["seekVodTo", s]), tsKey: (w) => did.push(["tsKey", w]),
                               showBanner: () => did.push(["showBanner"]), answerStream: () => did.push(["answerStream"]) }, over || {})
  delete root.ts
  const dvr = { said: "", checkPlace() {} }
  const player = { position: 120000, duration: 3600000 }
  const appPlaybackItem = { duration: 1800, seekTo: (s) => did.push(["app.seekTo", s]) }
  const env = { root, timeshift: ts, player, dvr, appPlaybackItem, Ts, bannerTimer: timer("bannerTimer"), scrubClock: timer("scrubClock"), holdTimer: timer("holdTimer"),
                vodBarTimer: timer("vodBarTimer"), Date: { now: () => clock.now } }
  for (const opener of FUNCS) {
    const name = opener.match(/function (\w+)/)[1]
    const body = block(guideSrc, opener)
    const fn = new Function(...Object.keys(env), ...argsOf(opener), body)
    root[name] = (...a) => fn(...Object.values(env), ...a)
  }
  return { root, ts, did, clock, env }
}

// ---- ▲ once: no pause choices; ▲ again: the player controls, or why not ----
{
  const actions = guideSrc.slice(guideSrc.indexOf("readonly property var bannerActions: {"), guideSrc.indexOf("  // The REC badge on the banner"))
  assert.ok(!/tsActions\.concat/.test(actions), "the banner's choices no longer start with Pause, Back 30 s, Forward 30 s and Live")
  assert.match(actions, /if \(tsCantMenu\) return \[\{ key: "tsPause", label: "Pause", icon: "", unavailable: true, note: timeshift\.cantPauseText/, "▲ again, can't run: Pause dimmed, saying why")

  let s = stand()
  s.root.openPlayerControls(true)
  assert.ok(s.root.playerControls && !s.root.bannerOptions && s.root.bannerShown, "running: the player controls, the banner under them")
  assert.ok(s.did.some((d) => d[0] === "bannerTimer.restart"), "their ten seconds start")
  s = stand({ ts: { turnedOn: false, active: false } })
  s.root.openPlayerControls(true)
  assert.ok(s.root.tsOffMenu && s.root.bannerOptions && !s.root.playerControls && s.root.tsMenuFromChoices, "off: the banner says so, with Turn on")
  s.root.bannerBack()
  assert.ok(s.root.bannerOptions && !s.root.tsOffMenu && !s.root.tsMenuFromChoices && s.root.bannerAct === 0, "▼ back to the choices")
  s = stand({ ts: { turnedOn: true, active: false, cantPauseText: "Can't pause: not enough space" } })
  s.root.openPlayerControls(true)
  assert.ok(s.root.tsCantMenu && s.root.bannerOptions, "on but not running: Pause saying why")
  s = stand()
  s.root.openPlayerControls(true)
  s.root.bannerBack()
  assert.ok(!s.root.playerControls && s.root.bannerOptions, "▼ from the player controls: back to the choices")
  s.root.bannerBack()
  assert.ok(!s.root.bannerOptions && !s.root.bannerShown, "▼ again: away")
  s = stand({ ts: { turnedOn: false, active: false } })
  s.root.tsOffMenu = true; s.root.bannerOptions = true; s.root.tsMenuFromChoices = false   // J with it off
  s.root.bannerBack()
  assert.ok(!s.root.bannerOptions, "from J (not the choices): ▼ closes, as before")
  s = stand({ vod: {} })
  s.root.openPlayerControls(true)
  assert.ok(!s.root.playerControls && !s.root.bannerOptions, "a movie keeps its own player bar")
  s = stand()
  s.root.openPlayerControls(false)
  s.root.hideBanner()
  assert.ok(!s.root.playerControls && !s.root.bannerShown, "BACK hides them")
}

// ---- a held key scrubs on its own clock ----
{
  const s = stand()
  s.root.playerControls = true
  s.root.scrubKeyDown(-1, false)
  assert.equal(s.root.keyHold.began, false)
  s.root.holdBegan()                                  // 300 ms on: a hold
  assert.equal(s.root.scrub.at, 600000, "the mark starts where the picture is")
  assert.ok(s.did.some((d) => d[0] === "scrubClock.start") && s.did.some((d) => d[0] === "bannerTimer.stop"), "its own clock; the controls stay up")
  const steps = []
  for (const t of [1250, 1500, 1750, 1999, 2250, 2500, 2999, 3250, 3500]) { s.clock.now = t; const was = s.root.scrub.at; s.root.scrubStep(); steps.push((was - s.root.scrub.at) / 1000) }
  assert.deepEqual(steps, [10, 10, 10, 10, 30, 30, 30, 60, 60], "10 s steps the first second, 30 s the next, then a minute")
  for (let i = 0; i < 20; i++) s.root.scrubStep()
  assert.equal(s.root.scrub.at, 300000, "never before the oldest kept")
  s.root.scrubKeyUp()
  assert.deepEqual(s.did.filter((d) => d[0] === "ts.seekTo"), [["ts.seekTo", 300000]], "let go: one jump, there")
  assert.equal(s.root.scrub, null)
  assert.ok(s.did.some((d) => d[0] === "bannerTimer.restart"), "their ten seconds start when it ends")
}
{
  const s = stand()
  s.root.scrubKeyDown(1, false)
  s.root.holdBegan()
  assert.ok(s.root.playerControls, "a hold with nothing open opens the player controls")
  s.clock.now = 5000
  for (let i = 0; i < 10; i++) s.root.scrubStep()
  assert.equal(s.root.scrub.at, 900000, "never past where Live is now")
  s.root.scrubKeyUp()
  assert.deepEqual(s.did.filter((d) => d[0] === "ts.seekTo"), [["ts.seekTo", 900000]], "at the end: Live (seekTo turns it into Live)")
  // Timeshift.seekTo: Live at the end, never before the oldest, paused stays where it is
  const seekTo = block(tsSrc, "function seekTo(t) {")
  assert.match(seekTo, /if \(t >= ts\.win\.live - Ts\.NEAR\) return ts\.live\(\)/)
  assert.match(seekTo, /ts\.openAt\(Math\.max\(ts\.win\.oldest, t\), false\)/, "one reopen")
}
{
  const s = stand()
  s.root.scrubKeyDown(-1, true)
  s.root.holdBegan()
  s.clock.now = 1500; s.root.scrubStep()
  s.root.playSig = "B"                               // the channel changed during it
  s.root.cancelScrub()                               // (onPlaySigChanged)
  s.root.scrubKeyUp()
  assert.deepEqual(s.did.filter((d) => d[0] === "ts.seekTo"), [], "something else playing: letting go does nothing")
  // and a scrub whose playing changed without the cancel still never seeks
  const t = stand()
  t.root.scrubKeyDown(-1, true); t.root.holdBegan()
  t.root.playSig = "C"
  t.root.scrubKeyUp()
  assert.deepEqual(t.did.filter((d) => d[0] === "ts.seekTo"), [], "checked again when let go")
  assert.match(guideSrc, /onPlaySigChanged: \{ playToken \+= 1; cancelScrub\(\) \}/, "a change of what's playing cancels a scrub at once")
  for (const h of ["onWatchingChanged: {\n    remoteStateTimer.restart()\n    root.cancelScrub()", "onPipChanged: { remoteStateTimer.restart(); root.cancelScrub() }"]) assert.ok(guideSrc.includes(h), "and so does the mode: " + h.slice(0, 18))
}

// ---- taps ----
{
  let s = stand()
  s.root.playerControls = true
  s.root.scrubKeyDown(1, false); s.root.scrubKeyUp()
  assert.deepEqual(s.did.filter((d) => d[0].startsWith("ts.")), [["ts.forward"]], "on the player controls: a tap steps 30 s")
  s = stand()
  s.root.scrubKeyDown(-1, true); s.root.scrubKeyUp()
  assert.deepEqual(s.did.filter((d) => d[0] === "tsKey"), [["tsKey", "back"]], "J with nothing open: as before (30 s, the banner)")
  s = stand()
  s.root.scrubKeyDown(-1, false); s.root.scrubKeyUp()
  assert.deepEqual(s.did.filter((d) => d[0].startsWith("ts") || d[0] === "seekVod"), [], "← with nothing open: a tap does nothing, as before")
  s = stand({ vod: { id: "m" } })
  s.root.scrubKeyDown(1, false); s.root.scrubKeyUp()
  assert.deepEqual(s.did.filter((d) => d[0] === "seekVod"), [["seekVod", 10]], "a movie: a tap is 10 s")
}

// ---- not running: a hold answers as J does ----
{
  const s = stand({ ts: { turnedOn: false, active: false } })
  s.root.scrubKeyDown(1, false)
  s.root.holdBegan()
  assert.equal(s.root.scrub, null, "no scrub")
  assert.deepEqual(s.did.filter((d) => d[0] === "tsKey"), [["tsKey", "forward"]], "J's answer: Turn on, or why it can't")
  s.root.scrubKeyUp()
  assert.deepEqual(s.did.filter((d) => d[0] === "tsKey"), [["tsKey", "forward"]], "and nothing more when let go")
}

// ---- a movie's held key scrubs its bar ----
{
  const s = stand({ vod: { id: "m" } })
  s.root.scrubKeyDown(1, false)
  s.root.holdBegan()
  assert.equal(s.root.scrub.movie, true)
  assert.equal(s.root.scrub.at, 120, "from where it is (seconds)")
  assert.ok(s.root.vodBarShown, "its bar shows")
  s.clock.now = 1300; s.root.scrubStep()
  s.root.scrubKeyUp()
  assert.deepEqual(s.did.filter((d) => d[0] === "seekVodTo"), [["seekVodTo", 130]], "one seek, when let go")
}

// ---- the mouse along the bar ----
{
  const s = stand()
  s.root.playerControls = true
  assert.ok(s.root.scrubStart(0, false))
  s.root.scrubTo(0.5)
  assert.equal(s.root.scrub.at, 600000, "half way along what's kept")
  s.root.scrubTo(2)
  assert.equal(s.root.scrub.at, 900000)
  assert.ok(!s.did.some((d) => d[0] === "scrubClock.start"), "a drag has no clock")
  s.root.scrubTo(0.25)
  s.root.scrubEnd()
  assert.deepEqual(s.did.filter((d) => d[0] === "ts.seekTo"), [["ts.seekTo", 450000]], "the picture jumps on letting go")
}

// ---- a missed letting go never sticks ----
{
  const s = stand()
  s.root.scrubKeyDown(-1, false); s.root.holdBegan()
  s.root.scrubKeyDown(1, false)                      // a press while one was held: the release went elsewhere
  assert.equal(s.root.scrub, null, "the old one's over, with no jump")
  assert.equal(s.root.keyHold.dir, 1, "the new press counts")
  s.root.scrubKeyUp()
  assert.deepEqual(s.did.filter((d) => d[0] === "ts.seekTo"), [])
  const t = stand()
  t.root.scrubKeyDown(-1, false); t.root.holdBegan()
  t.clock.now = 70000; t.root.scrubStep()
  assert.equal(t.root.scrub, null, "held for a minute: given up")
}

// ---- the keys ----
{
  assert.match(keysSrc, /Keys\.onReleased: function\(event\) \{\n    var k = event\.key\n    if \(event\.isAutoRepeat \|\| !guide\.keyHold\) return/, "letting go counts once (auto-repeat's releases don't)")
  const controls = keysSrc.slice(keysSrc.indexOf("} else if (guide.watching && guide.playerControls) {"), keysSrc.indexOf("} else if (guide.watching && guide.bannerOptions) {"))
  assert.match(controls, /if \(dirKey\) \{ if \(!event\.isAutoRepeat\) guide\.scrubKeyDown/, "the player controls: ← → J L press once (auto-repeat ignored)")
  assert.match(controls, /k === Qt\.Key_Down\) guide\.bannerBack\(\)/)
  assert.match(controls, /else if \(k === Qt\.Key_Up\) \{\}/, "↑ there does nothing")
  const choices = keysSrc.slice(keysSrc.indexOf("} else if (guide.watching && guide.bannerOptions) {"), keysSrc.indexOf("} else if (guide.watching) {"))
  assert.match(choices, /k === Qt\.Key_Up\) \{ if \(!guide\.recStopMenu && !guide\.streamAsk && !guide\.tsOffMenu && !guide\.tsCantMenu\) guide\.openPlayerControls\(true\) \}/, "↑ on the choices: the player controls (as the phone's ▲)")
  assert.match(choices, /k === Qt\.Key_Left\) guide\.moveBannerAct\(-1\)/, "← → stay on the choices' row (held or not: never a scrub)")
  const open = keysSrc.slice(keysSrc.indexOf("} else if (guide.watching) {"), keysSrc.indexOf("    } else {\n      if (k === Qt.Key_Escape) guide.homeEnabled"))
  assert.match(open, /k === Qt\.Key_Up \|\| k === Qt\.Key_PageUp\) guide\.surf\(1\)/, "↑ with nothing open is still channel up")
  assert.match(open, /if \(!event\.isAutoRepeat\) guide\.scrubKeyDown\(k === Qt\.Key_J \|\| k === Qt\.Key_Left \? -1 : 1, k === Qt\.Key_J \|\| k === Qt\.Key_L\)/)
}

// ---- the phone ----
{
  const cmd = block(guideSrc, "function remoteCommand(cmd, number, by, digits, extra) {")
  const pc = cmd.indexOf("} else if (root.watching && root.playerControls) {")
  const ch = cmd.indexOf("} else if (root.watching && root.bannerOptions) {")
  assert.ok(pc > 0 && pc < ch, "the player controls' layer is routed before the choices'")
  const layer = cmd.slice(pc, ch)
  for (const [c, act] of [["left", 'root.controlsAct("back")'], ["right", 'root.controlsAct("forward")'], ["ok", 'root.controlsAct("pause")'], ["down", "root.bannerBack()"], ["back", "root.hideBanner()"]])
    assert.ok(layer.includes('cmd === "' + c + '") ' + act), "the phone's " + c + " on the player controls")
  assert.ok(cmd.slice(ch, ch + 400).includes('if (cmd === "up") { if (!root.recStopMenu && !root.streamAsk && !root.tsOffMenu && !root.tsCantMenu) root.openPlayerControls(true) }'), "▲ on the choices")

  let s = stand()
  assert.equal(s.root.remoteSeek(1.5, 5), "not a point along the bar")
  assert.equal(s.root.remoteSeek("0.5", 5), "not a point along the bar")
  assert.equal(s.root.remoteSeek(0.5, 4), "something else is playing now", "a stale play token: nothing")
  assert.deepEqual(s.did, [])
  s.root.remoteSeek(0.5, 5)
  assert.deepEqual(s.did.filter((d) => d[0] === "ts.seekTo"), [["ts.seekTo", 600000]], "that point of what's kept")
  s = stand()
  s.root.remoteSeek(1, 5)
  assert.deepEqual(s.did.filter((d) => d[0] === "ts.seekTo"), [["ts.seekTo", 900000]], "1: Live")
  s = stand({ ts: { active: false, turnedOn: false } })
  s.root.remoteSeek(0.5, 5)
  assert.deepEqual(s.did, [["tsKey", "back"]], "off or can't run: rewind's answer")
  s = stand({ vod: { id: "m" } })
  s.root.remoteSeek(0.25, 5)
  assert.deepEqual(s.did, [["seekVodTo", 900]], "a movie: that point")
  s = stand({ appPlaying: true })
  s.root.remoteSeek(0.5, 5)
  assert.deepEqual(s.did, [["app.seekTo", 900]], "an app's video: that point (a new absolute seek)")
  s = stand({ watching: false, pip: true })
  s.root.remoteSeek(0.5, 5)
  assert.deepEqual(s.did, [], "the mini player's live channel: nothing")
  assert.match(read("AppPlayback.qml"), /function seekTo\(seconds\) \{\n    if \(!pb\.player \|\| pb\.closing \|\| !pb\.player\.seekable \|\| !\(pb\.player\.duration > 0\) \|\| !isFinite\(seconds\)\) return/)
  assert.ok(block(guideSrc, "function remoteState() {").includes("play: root.playToken"), "the phones are told what's playing as a number, never what it is")
}

console.log("player controls: all good")
