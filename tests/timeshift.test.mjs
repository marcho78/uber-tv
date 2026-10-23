// Pause and rewind, the guide's side (Timeshift.js, Timeshift.qml, Guide.qml,
// GuideKeys.qml, Commands.qml, ui/Multiview.qml), run from their own code over
// stand-ins: what the buffer takes (a live channel watched, not one it gave up
// on); a session started through the helper (the address on stdin, the TV's
// direct picture let go first, the 20 s watchdog off while it fills); the
// player opened once two segments are in, at Live, each move a new address
// and generation, only that open seeking (an earlier one's status ignored);
// pause, resume clamped to the buffer, back, forward to Live, an agent's
// seconds; one reopen on a failure, then the channel directly only once the
// writer's stop has answered; a stall held and back to Live when segments
// come; a turned address followed; an end that waits for a start still on its
// way. The approved words, as they are. J K L, the media keys, Multiview
// waiting for the writer, the setting's row, the agents refused in order.
//   node tests/timeshift.test.mjs
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const read = f => readFileSync(new URL("../" + f, import.meta.url), "utf8")
// a clock of its own: the counts don't depend on how fast this runs
let clockNow = 1800000000000
Date.now = () => clockNow
const tsSrc = read("Timeshift.qml")
const guideSrc = read("Guide.qml")
const T = new Function(read("Timeshift.js").replace(/^\.pragma library\s*/, "") +
  "; return { MINUTES, STEP, NEAR, minutesOf, minutesLabel, supported, upstream, openUrl, clamp, backTarget, reachesLive, forwardTarget, behind, liveNow, span, chip, stallAfter, stalled, flowing, cantPause, genOf }")()
const D = new Function(read("Dvr.js").replace(/^\.pragma library\s*/, "") + "; return { hashOf, providerOf, checked, defaults, GB, next }")()
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

// a function's body, from its opening brace to the one that closes it
const braces = (text, open) => {
  let depth = 0
  for (let i = open; i < text.length; i++) {
    if (text[i] === "{") depth++
    else if (text[i] === "}" && --depth === 0) return text.slice(open + 1, i)
  }
  assert.fail("unclosed")
}

// ---- the rules ----
assert.deepEqual([T.minutesOf(5), T.minutesOf(30), T.minutesOf(7), T.minutesOf(undefined)], [5, 30, 0, 0])
assert.deepEqual(T.MINUTES.map(T.minutesLabel), ["Off", "5 min", "30 min"], "the row's values, as approved")
assert.equal(T.supported({ live: true, iptv: true }), true)
assert.equal(T.supported({ live: true, id: "abc" }), true, "a YouTube channel's live stream")
assert.equal(T.supported({ id: "abc", start: 0, end: 10 }), false, "a scheduled channel's video isn't live")
assert.equal(T.supported({ live: true, vod: true }), false)
assert.equal(T.upstream({ live: true, iptv: true, stream: "http://p/1.ts" }, ""), "http://p/1.ts")
assert.equal(T.upstream({ live: true, id: "abcdefghijk" }, "http://127.0.0.1:9/s"), "http://127.0.0.1:9/s/play/abcdefghijk.m3u8", "YouTube through the streamer: pulled once")
assert.equal(T.upstream({ live: true, id: "abcdefghijk" }, ""), "", "no streamer yet: nothing")
assert.equal(T.openUrl("http://b/S", 3, 17), "http://b/S/live.m3u8?open=3&from=17")
assert.deepEqual([T.genOf("http://b/S/live.m3u8?open=12&from=4", "http://b/S"), T.genOf("http://p/1.ts", "http://b/S"), T.genOf("http://b/S/live.m3u8?open=2", "")], [12, 0, 0])
const w = { oldest: 10000, live: 100000, edge: 112000, longest: 6000, completedAgo: 500, ready: true }
assert.equal(T.backTarget(25000, w), 10000, "never before the oldest part")
assert.equal(T.backTarget(70000, w), 40000)
assert.equal(T.forwardTarget(40000, w), 70000)
assert.equal(T.forwardTarget(75000, w), 100000, "past live is Live")
assert.equal(T.reachesLive(69500, w), true, "within a second of it")
assert.deepEqual([T.span(135000), T.span(3723000), T.span(0)], ["2:15", "1:02:03", "0:00"])
assert.equal(T.liveNow(w, 1000), 113500, "how far the writer's got: its newest segment's end plus what's come in since")
assert.equal(T.liveNow(w, 60000), 118000, "as long as a segment takes, then it holds (a stall)")
assert.equal(T.chip(true, 0), "Live")
assert.equal(T.chip(false, 135000), "2:15 behind live", "the chip, as approved")
assert.equal(T.stallAfter(w), 14000, "longer than this channel's segments")
assert.equal(T.stallAfter({ longest: 0 }), 8000)
assert.equal(T.stalled(Object.assign({}, w, { completedAgo: 15000 }), 3000), true)
assert.equal(T.stalled(Object.assign({}, w, { completedAgo: 13000 }), 9000), false, "a long segment still being written isn't a stall")
assert.equal(T.stalled(Object.assign({}, w, { completedAgo: 15000 }), 500), false, "the picture still moving isn't one")
assert.deepEqual(["drive", "readonly", "space", "", "service"].map(T.cantPause),
  ["Can't pause: the drive isn't plugged in", "Can't pause: can't save to the drive", "Can't pause: not enough space", "Can't pause right now", "Can't pause right now"], "as approved")
assert.equal(D.checked({ timeshift: 30 }).timeshift, 30)
assert.equal(D.checked({ timeshift: 7 }).timeshift, 0, "a length it doesn't offer: off")
assert.equal(D.defaults().timeshift, 0, "off to start with")

// ---- Timeshift.qml, from its own code ----
const MP = { LoadedMedia: 2, BufferingMedia: 4, BufferedMedia: 5, EndOfMedia: 6, InvalidMedia: 7, StoppedState: 0, PlayingState: 1, PausedState: 2 }
function make() {
  const calls = [], helper = [], xhrs = []
  const player = { source: "", position: -1, playbackState: MP.StoppedState,
                   stop() { calls.push("player.stop"); this.playbackState = MP.StoppedState },
                   play() { calls.push("play"); this.playbackState = MP.PlayingState },
                   pause() { calls.push("pause"); this.playbackState = MP.PausedState } }
  const place = { volume: "uuid:x", mount: "/m", rel: "Uber TV Recordings" }
  const dvr = { settings: { on: true, timeshift: 5, place }, keepFreeGB: 5, ready(then) { then(place) },
                call(args, input, done) { helper.push({ args, input, done }) }, channelByHash: () => null }
  const chan = { name: "One", url: "http://p/1.ts", kind: "iptv" }
  const guide = { watching: true, bufferNext: false, streamBase: "", onAir: { live: true, iptv: true, stream: chan.url }, channels: [chan], tunedRow: 0,
                  reception: "tuning", started: false, tuneWatch(on) { calls.push("watchdog " + on) }, play() { calls.push("guide.play") } }
  const fillDeadline = { restart() { calls.push("fill") }, stop() { calls.push("fill stop") } }
  class XHR { open(m, u) { this.url = u } send() { xhrs.push(this) } }
  XHR.DONE = 4
  const ts = { session: "", base: "", upstreamUrl: "", chan: null, provider: "", phase: "off", reason: "", failedFor: "",
               win: { ready: false, count: 0, headSeq: 0, oldest: 0, live: 0, edge: 0, longest: 0, completedAgo: -1 }, gen: 0, pending: null,
               owning: false, paused: false, atLive: true, point: 0, winAt: 0, liveOffset: 0, tick: 0, lastFrame: 0, lastTick: 0, stalled: false, recovering: false, request: 0,
               misses: 0, startsOut: 0, stopsOut: 0, waiting: [], unstopped: [], following: false }
  for (const m of tsSrc.matchAll(/\n  property \w+ (\w+)(?=:)/g)) assert.ok(m[1] in ts, "the stand-in has " + m[1])
  for (const m of tsSrc.matchAll(/\n  readonly property \w+ (\w+): (.*)(?=\n)/g)) {
    const f = new Function("ts", "Ts", "dvr", "with (ts) { return (" + m[2] + ") }")
    Object.defineProperty(ts, m[1], { get: () => f(ts, T, dvr) })
  }
  for (const m of tsSrc.matchAll(/\n  function (\w+)\(([^)]*)\) \{/g)) {
    ts[m[1]] = new Function("ts", "player", "guide", "dvr", "Ts", "Dvr", "MediaPlayer", "fillDeadline", "XMLHttpRequest",
                            "return function(" + m[2] + ") {" + braces(tsSrc, m.index + m[0].length - 1) + "}")(ts, player, guide, dvr, T, D, MP, fillDeadline, XHR)
  }
  // the helper's answers, the status's
  const answer = (res) => { const h = helper.shift(); h.done(res); return h }
  const status = (st) => { const x = xhrs.shift(); x.readyState = 4; x.status = 200; x.responseText = JSON.stringify(st); x.onreadystatechange(); return x }
  return { ts, player, guide, dvr, helper, calls, xhrs, answer, status, chan }
}
const ready = (o) => Object.assign({ state: "ready", reason: "", ready: true, count: 5, headSeq: 7, oldest: 20000, live: 50000, edge: 62000, longest: 6000, completedAgo: 300 }, o || {})

{
  const t = make()
  t.dvr.settings.timeshift = 0
  assert.equal(t.ts.takes(t.guide.onAir), false, "off: the channel directly")
  t.dvr.settings.timeshift = 5
  t.guide.watching = false
  assert.equal(t.ts.takes(t.guide.onAir), false, "the guide's preview: directly")
  t.guide.bufferNext = true
  assert.equal(t.ts.takes(t.guide.onAir), true, "about to be watched: through the buffer")
  t.guide.watching = true
  t.guide.bufferNext = false
  t.dvr.settings.on = false
  assert.equal(t.ts.takes(t.guide.onAir), false, "Recordings off: off")
  t.dvr.settings.on = true
  assert.equal(t.ts.takes({ live: true, id: "abcdefghijk" }), false, "YouTube before the streamer's up: directly for now")
  t.ts.failedFor = t.chan.url
  assert.equal(t.ts.takes(t.guide.onAir), false, "a channel it gave up on: directly until another one")
}

{
  const t = make()
  t.ts.tuned()
  assert.ok(t.calls.indexOf("watchdog false") >= 0, "the 20 s watchdog off while it fills")
  assert.ok(t.calls.indexOf("player.stop") >= 0 && t.calls.indexOf("player.stop") < t.calls.length, "the direct picture let go before the writer starts")
  const start = t.helper[0]
  assert.deepEqual(start.args, ["buffer", "start"])
  const job = JSON.parse(start.input)
  assert.deepEqual([job.url, job.minutes, job.keepFree, job.height, job.place.volume], [t.chan.url, 5, 5 * D.GB, 1080, "uuid:x"], "the address on stdin, never the command line")
  assert.equal(t.ts.phase, "starting")
  assert.equal(t.ts.cantPauseText, "Can't pause right now", "starting: Pause says so")
  t.answer({ ok: true, session: "0123456789abcdef", base: "http://127.0.0.1:5/S" })
  assert.deepEqual([t.ts.phase, t.ts.session, t.xhrs[0].url], ["filling", "0123456789abcdef", "http://127.0.0.1:5/S/status"], "filling, its status asked (the lease)")
  t.status({ state: "filling", ready: false, count: 1, headSeq: 0, oldest: 0, live: 0, edge: 4000, longest: 4000, completedAgo: 100 })
  assert.equal(t.player.source, "", "one segment: the player waits")
  t.ts.ask()
  t.status(ready())
  assert.equal(t.ts.phase, "ready")
  assert.equal(t.player.source, "http://127.0.0.1:5/S/live.m3u8?open=1&from=7", "opened from the window's head, a generation of its own")
  assert.deepEqual([t.ts.pending.at, t.ts.point, t.ts.atLive], [30000, 50000, true], "at Live: where Qt seeks is from the oldest part")
  assert.ok(t.calls.lastIndexOf("watchdog true") > t.calls.indexOf("watchdog false"), "the watchdog once a playlist's handed over")
  assert.equal(t.ts.mediaStatus(MP.LoadedMedia), true)
  assert.deepEqual([t.player.position, t.player.playbackState, t.guide.started], [30000, MP.PlayingState, true], "only this open seeks, then plays")
  t.ts.mediaStatus(MP.BufferedMedia)
  assert.equal(t.guide.reception, "on")
  assert.equal(t.ts.active, true)
  assert.equal(t.ts.chipText, "Live")

  // moves: each a new address; an earlier one's status does nothing
  const before = t.player.source
  assert.equal(t.ts.back(), "ok")
  assert.equal(t.player.source, "http://127.0.0.1:5/S/live.m3u8?open=2&from=7")
  assert.deepEqual([t.ts.point, t.ts.atLive, t.ts.pending.at], [20000, false, 0], "30 s back, never before the oldest part")
  t.player.source = before
  t.player.position = -5
  t.ts.mediaStatus(MP.LoadedMedia)
  assert.equal(t.player.position, -5, "an earlier open's load doesn't seek")
  const gen2 = t.ts.gen
  t.ts.mediaStatus(MP.EndOfMedia)
  t.ts.mediaStatus(MP.InvalidMedia)
  t.ts.error()
  assert.deepEqual([t.ts.gen, t.ts.recovering, t.ts.phase], [gen2, false, "ready"], "nor does its end or error reopen anything")
  t.player.source = "http://127.0.0.1:5/S/live.m3u8?open=2&from=7"
  t.ts.mediaStatus(MP.LoadedMedia)
  assert.equal(t.player.position, 0)
  assert.equal(t.ts.chipText, "0:30 behind live")
  t.ts.forward()
  assert.deepEqual([t.ts.point, t.ts.gen], [50000, 3], "forward from 20 s to 50 s: Live")
  assert.equal(t.ts.atLive, true)
  t.ts.mediaStatus(MP.LoadedMedia)
  // pause, then resume clamped to the buffer as it is now
  assert.equal(t.ts.togglePause(), "ok")
  assert.deepEqual([t.ts.paused, t.ts.atLive, t.player.playbackState], [true, false, MP.PausedState])
  t.ts.ask()
  t.status(ready({ oldest: 80000, live: 300000, edge: 312000, headSeq: 40 }))
  assert.equal(t.ts.chipText, "4:10 behind live", "paused, it falls behind")
  t.ts.tick = t.ts.winAt + 4000
  assert.equal(t.ts.chipText, "4:14 behind live", "second by second, between statuses")
  t.ts.tick = t.ts.winAt + 60000
  assert.equal(t.ts.chipText, "4:15 behind live", "not past what the writer could have taken in (a stall doesn't count)")
  t.ts.tick = 0
  t.ts.togglePause()
  assert.deepEqual([t.ts.paused, t.ts.point, t.player.source], [false, 80000, "http://127.0.0.1:5/S/live.m3u8?open=4&from=40"], "paused longer than it holds: the oldest part kept, a new open")
  t.ts.mediaStatus(MP.LoadedMedia)
  assert.equal(t.player.playbackState, MP.PlayingState)
  assert.equal(t.ts.seekBy(-90), "ok")
  assert.equal(t.ts.point, 80000, "an agent's seconds, as far as the buffer goes")
  t.ts.seekBy(10000)
  assert.equal(t.ts.atLive, true, "past live is Live")

  // a failure: one reopen, then the channel directly once the writer's gone
  t.ts.mediaStatus(MP.LoadedMedia)
  t.ts.mediaStatus(MP.EndOfMedia)
  assert.equal(t.ts.recovering, true)
  const reopened = t.player.source
  assert.ok(/open=7&/.test(reopened), "reopened where it was")
  t.ts.error()
  assert.equal(t.ts.phase, "failed", "failing again gives up")
  assert.deepEqual(t.helper[0].args, ["buffer", "stop", "0123456789abcdef"], "the writer stopped")
  assert.equal(t.calls.indexOf("guide.play"), -1, "not the channel directly before the writer's gone")
  t.answer({ ok: true })
  assert.ok(t.calls.indexOf("guide.play") >= 0 && t.guide.reception === "tuning", "then directly")
  assert.equal(t.ts.takes(t.guide.onAir), false, "and directly while it's on")
  assert.equal(t.ts.cantPauseText, "Can't pause right now")
}

{
  const t = make()
  t.ts.tuned()
  t.answer({ ok: false, error: "drive" })
  assert.equal(t.ts.cantPauseText, "Can't pause: the drive isn't plugged in", "the drive missing: why Pause can't")
  assert.ok(t.calls.indexOf("guide.play") >= 0, "the channel plays directly")
}

{
  const t = make()
  t.ts.tuned()
  t.answer({ ok: true, session: "aaaaaaaaaaaaaaaa", base: "http://127.0.0.1:5/S" })
  t.status(ready())
  t.ts.mediaStatus(MP.LoadedMedia)
  t.ts.mediaStatus(MP.BufferedMedia)
  t.ts.ask()
  t.status(ready({ state: "failed", reason: "space" }))
  assert.equal(t.ts.cantPauseText, "Can't pause: not enough space", "too little space while it writes: said, and directly")
  t.answer({ ok: true })
  assert.ok(t.calls.indexOf("guide.play") >= 0)
}

{
  // a stall: held, not Live; segments again: back to Live
  const t = make()
  t.ts.tuned()
  t.answer({ ok: true, session: "bbbbbbbbbbbbbbbb", base: "http://127.0.0.1:5/S" })
  t.status(ready())
  t.ts.mediaStatus(MP.LoadedMedia)
  t.ts.lastFrame = Date.now() - 5000
  t.ts.ask()
  t.status(ready({ completedAgo: 20000 }))
  assert.equal(t.ts.stalled, true)
  const gen = t.ts.gen
  t.ts.ask()
  t.status(ready({ completedAgo: 500, live: 70000 }))
  assert.deepEqual([t.ts.stalled, t.ts.gen, t.ts.point, t.ts.atLive], [false, gen + 1, 70000, true], "segments again: Live, its margin back")
  // three statuses unanswered: it gives up
  for (let i = 0; i < 3; i++) {
    t.ts.ask()
    const x = t.xhrs.shift()
    x.readyState = 4; x.status = 0; x.onreadystatechange()
  }
  assert.equal(t.ts.phase, "failed")
}

{
  // a turned address: followed
  const t = make()
  t.ts.tuned()
  t.answer({ ok: true, session: "cccccccccccccccc", base: "http://127.0.0.1:5/S" })
  t.status(ready())
  t.ts.mediaStatus(MP.LoadedMedia)
  t.dvr.channelByHash = (c, provider) => (c.hash === D.hashOf(t.chan.url) ? { name: "One", url: "http://p/2.ts", kind: "iptv" } : null)
  t.ts.ask()
  t.status(ready())
  assert.deepEqual([t.helper[0].args, JSON.parse(t.helper[0].input).url], [["buffer", "follow", "cccccccccccccccc"], "http://p/2.ts"])
  t.answer({ ok: true, gen: 1 })
  assert.equal(t.ts.upstreamUrl, "http://p/2.ts")
}

{
  // ended while a start is on its way: what waits for it waits for that start, and its session goes
  const t = make()
  t.ts.tuned()
  let done = false
  t.ts.end(() => { done = true })
  assert.equal(done, false, "not while a start's on its way")
  t.answer({ ok: true, session: "dddddddddddddddd", base: "http://127.0.0.1:5/S" })
  assert.deepEqual(t.helper[0].args, ["buffer", "stop", "dddddddddddddddd"], "the late one stopped")
  assert.equal(done, false, "nor while it stops")
  t.answer({ ok: true })
  assert.equal(done, true)
  assert.equal(t.ts.session, "")
}

{
  // the same channel again: no new session, Live
  const t = make()
  t.ts.tuned()
  t.answer({ ok: true, session: "eeeeeeeeeeeeeeee", base: "http://127.0.0.1:5/S" })
  t.status(ready())
  const g = t.ts.gen
  t.ts.tuned()
  assert.deepEqual([t.helper.length, t.ts.gen], [0, g + 1], "retuned: the same session, Live")
}

{
  // A's start on its way, then B, then C: only C starts, once A's gone
  const t = make()
  t.ts.tuned()                                            // A
  t.guide.onAir = { live: true, iptv: true, stream: "http://p/B.ts" }
  t.ts.tuned()                                            // B
  assert.equal(t.ts.phase, "starting", "the card says it's starting while the old one goes")
  t.guide.onAir = { live: true, iptv: true, stream: "http://p/C.ts" }
  t.ts.tuned()                                            // C
  t.answer({ ok: true, session: "aaaaaaaaaaaaaaa1", base: "http://127.0.0.1:5/A" })
  assert.deepEqual(t.helper.map(h => h.args.join(" ")), ["buffer stop aaaaaaaaaaaaaaa1"], "A goes, nothing starts beside it")
  t.answer({ ok: true })
  assert.deepEqual(t.helper.map(h => h.args[1] + " " + (h.input ? JSON.parse(h.input).url : "")), ["start http://p/C.ts"], "then only C starts: B was overtaken")
}

{
  // a stop that doesn't confirm the writer's gone: what waits doesn't go ahead, it's asked again
  const t = make()
  t.ts.tuned()
  t.answer({ ok: true, session: "fffffffffffffff1", base: "http://127.0.0.1:5/S" })
  let done = false, dropped = false
  t.ts.end(() => { done = true })
  t.answer({ ok: false, error: "running" })
  assert.deepEqual([done, t.ts.stopsOut, t.ts.unstopped], [false, 1, ["fffffffffffffff1"]], "not gone: nothing goes ahead")
  t.ts.tryStop(t.ts.unstopped.shift())                   // the retry timer
  t.answer({ ok: true })
  assert.equal(done, true, "gone: then")
  // something newer while one waits: that one doesn't happen, and says so
  t.ts.tuned()
  t.answer({ ok: true, session: "fffffffffffffff2", base: "http://127.0.0.1:5/S" })
  done = false
  t.ts.end()
  t.ts.whenGone(() => { done = true }, () => { dropped = true })
  t.ts.end()                                             // the TV off meanwhile
  t.answer({ ok: true })
  assert.deepEqual([done, dropped], [false, true], "overtaken: not done, told so (Multiview, an app's video)")
}

{
  // a recovery counts as working only once a frame of the reopened source comes
  const t = make()
  t.ts.tuned()
  t.answer({ ok: true, session: "eeeeeeeeeeeeeee1", base: "http://127.0.0.1:5/S" })
  t.status(ready())
  t.ts.mediaStatus(MP.LoadedMedia)
  t.ts.mediaStatus(MP.EndOfMedia)
  assert.equal(t.ts.recovering, true)
  t.ts.mediaStatus(MP.LoadedMedia)
  t.ts.mediaStatus(MP.BufferedMedia)
  assert.equal(t.ts.recovering, true, "Buffered isn't proof")
  t.ts.frame()
  assert.equal(t.ts.recovering, false, "a frame is")
  t.ts.mediaStatus(MP.EndOfMedia)
  t.ts.mediaStatus(MP.LoadedMedia)
  t.ts.mediaStatus(MP.BufferedMedia)
  t.ts.lastFrame = Date.now() - 9000
  t.ts.ask()
  t.status(ready())
  assert.equal(t.ts.phase, "failed", "no frame after the reopen: the channel directly, not another reopen")
}

// ---- an app's video waits for the TV's buffer to be gone (AppPlayback.qml) ----
{
  const apSrc = read("AppPlayback.qml")
  const startBody = braces(apSrc, apSrc.indexOf("function start(appId, rt, value) {") + "function start(appId, rt, value) ".length)
  const waiters = []
  const guide = { turnOffs: 0, turnOff() { this.turnOffs++ }, pauser: { busy: true, whenGone(done, dropped) { waiters.push({ done, dropped }) } }, appPlaying: false }
  const closed = []
  const rt = { phase: "ready", lease() {}, closeRelay(s) { closed.push(s) } }
  const pb = { session: null, waitingTv: null, epochs: 0, attempted: [], dropPending() {}, attempt(u) { this.attempted.push(u) } }
  const start = new Function("pb", "guide", "progressTimer", "seekGap", "return function(appId, rt, value) {" + startBody + "}")(pb, guide, { last: 0 }, { stop() {} })
  pb.start = start
  pb.dropWaiting = new Function("pb", "return function(appId) {" + braces(apSrc, apSrc.indexOf("function dropWaiting(appId) {") + "function dropWaiting(appId) ".length) + "}")(pb)
  const url = "http://127.0.0.1:9/" + "a".repeat(32) + "/v"
  start("jellyfin", rt, { url, session: "s1" })
  assert.deepEqual([pb.attempted, guide.turnOffs, waiters.length], [[], 1, 1], "the TV off, its buffer told to go; no player yet")
  guide.pauser.busy = false
  waiters.shift().done()
  assert.deepEqual(pb.attempted, [url], "the writer gone: then the app's player")
  guide.pauser.busy = true
  pb.session = null
  start("jellyfin", rt, { url, session: "s2" })
  waiters.shift().dropped()
  assert.deepEqual([pb.attempted.length, closed, pb.waitingTv], [1, ["s2"], null], "overtaken meanwhile: never starts, its relay closed")
  // a second play while one waits: the first's relay closed at once
  start("jellyfin", rt, { url, session: "s3" })
  start("jellyfin", rt, { url, session: "s4" })
  assert.deepEqual(closed, ["s2", "s3"], "the first waiting play let go at once")
  // the app stopping or signing out while it waits: never starts
  pb.dropWaiting("jellyfin")
  assert.deepEqual([closed, pb.waitingTv], [["s2", "s3", "s4"], null])
  guide.pauser.busy = false
  waiters.splice(0).forEach(x => x.done())
  assert.equal(pb.attempted.length, 1, "the writer gone later: nothing starts")
  // the app's runtime gone while it waited: not started, its relay its runtime's
  guide.pauser.busy = true
  const dead = { phase: "stopped", lease() {}, closeRelay(s) { closed.push("dead " + s) } }
  start("other", dead, { url, session: "s5" })
  guide.pauser.busy = false
  waiters.shift().done()
  assert.deepEqual([pb.attempted.length, closed.length, pb.waitingTv], [1, 3, null], "a runtime that's gone: no player, no relay call")
  assert.match(apSrc.slice(apSrc.indexOf("function runtimeGone(appId) {")), /^function runtimeGone\(appId\) \{\n\s*pb\.dropWaiting\(appId\)/, "its runtime gone: its waiting play too")
  assert.match(apSrc, /if \(reason !== "replaced"\) \{ pb\.dropPending\(\); pb\.dropWaiting\(""\) \}/, "closing: the waiting play too")
  assert.match(block(guideSrc, "function finishAppPlayback(id, reason, then) {"), /appPlaybackItem\.dropWaiting\(id \|\| ""\)/, "sign out, removal, Apps off: the waiting play too")
}

{
  // uneven segments: A 15 s, B 6 s, then C 6 s; paused at Live, six seconds read six seconds
  const t = make()
  t.ts.tuned()
  t.answer({ ok: true, session: "abababababababab", base: "http://127.0.0.1:5/S" })
  t.status(ready({ oldest: 0, live: 0, edge: 21000, longest: 15000, completedAgo: 0, headSeq: 0 }))
  t.ts.mediaStatus(MP.LoadedMedia)
  t.ts.togglePause()
  assert.equal(t.ts.chipText, "0:00 behind live")
  clockNow += 6000
  t.ts.ask()
  t.status(ready({ oldest: 0, live: 15000, edge: 27000, longest: 15000, completedAgo: 0, headSeq: 0 }))
  t.ts.tick = Date.now()
  assert.equal(t.ts.chipText, "0:06 behind live", "the edge moved by the 6 s segment just finished, not by the 15 s before it")
  // the other way round, playing behind live: a long segment after short ones doesn't make it look Live
  t.ts.togglePause()
  t.ts.mediaStatus(MP.LoadedMedia)
  const before = t.ts.behind
  clockNow += 15000
  t.ts.point += 15000                                      // played 15 s
  t.ts.ask()
  t.status(ready({ oldest: 0, live: 21000, edge: 42000, longest: 15000, completedAgo: 0, headSeq: 0 }))
  t.ts.tick = Date.now()
  assert.ok(Math.abs(t.ts.behind - before) < 1000 && !t.ts.atLive, "still as far behind, not Live: " + before + " → " + t.ts.behind)
}

// ---- the guide ----
assert.match(guideSrc, /onMinutesChanged: root\.timeshiftChanged\(\)/, "off, on, or 5 ↔ 30: a new buffer")
assert.match(block(guideSrc, "function play() {"), /if \(timeshift\.takes\(root\.onAir\)\) \{ timeshift\.tuned\(\); return \}\n\s*if \(timeshift\.busy\) \{ timeshift\.end\(/, "the buffer's first; directly only once its writer's gone")
assert.match(guideSrc, /if \(watching && timeshift\.turnedOn && !timeshift\.busy && !vod && \(reception === "on" \|\| reception === "tuning"\) && tunedRow >= 0 && timeshift\.takes\(onAir\)\) root\.tune\(tunedRow\)/,
             "a channel the preview has on, or is still tuning, goes through the buffer once it's full screen")
assert.match(block(guideSrc, "function turnOff() {"), /timeshift\.end\(\)/)
assert.match(block(guideSrc, "function playVod(entry, from) {"), /timeshift\.end\(\)/, "a video: the buffer goes")
const statusHandler = guideSrc.slice(guideSrc.indexOf("onMediaStatusChanged: {", guideSrc.indexOf("id: player")))
assert.match(statusHandler.slice(0, 200), /^onMediaStatusChanged: \{\n\s*if \(timeshift\.mediaStatus\(mediaStatus\)\) return/, "its own handling before the live TV's")
assert.match(guideSrc, /if \(timeshift\.error\(\)\) return\s+\/\/ the buffer reopens/)
const keys = read("GuideKeys.qml")
assert.equal((keys.match(/k === Qt\.Key_J\) guide\.tsKey\("back"\)/g) || []).length, 2, "J: back, with or without the choices up")
assert.equal((keys.match(/k === Qt\.Key_K\) guide\.tsKey\("pause"\)/g) || []).length, 2)
assert.equal((keys.match(/k === Qt\.Key_L\) guide\.tsKey\("forward"\)/g) || []).length, 2)
assert.match(block(guideSrc, "function mprisCommand(cmd, message) {"), /timeshift\.active && \(cmd === "playpause" \|\| cmd === "play" \|\| cmd === "pause"\)/, "media keys: its own pause")
const mv = read("ui/Multiview.qml")
assert.equal((mv.match(/if \(guide\.pauser\.busy\) \{ guide\.turnOff\(\); guide\.pauser\.whenGone\(/g) || []).length, 2, "Multiview waits for the writer to be gone")
const acts = new Function("watching", "vod", "timeshift", "Ts", "onAir", "return (" + guideSrc.match(/readonly property var tsActions: ([\s\S]*?)\n  readonly property var bannerActions/)[1] + ")")
const on = { turnedOn: true, active: true, paused: false, atLive: true }
assert.deepEqual(acts(true, null, on, T, { live: true, iptv: true }).map(a => a.label), ["Pause", "Back 30 s", "Forward 30 s", "Live"], "the choices, Pause first, as approved")
assert.equal(acts(true, null, on, T, { live: true, iptv: true })[3].unavailable, true, "Live dimmed at live")
assert.equal(acts(true, null, Object.assign({}, on, { paused: true }), T, { live: true, iptv: true })[0].label, "Resume")
const off = acts(true, null, { turnedOn: true, active: false, cantPauseText: "Can't pause: not enough space" }, T, { live: true, iptv: true })
assert.deepEqual([off.length, off[0].unavailable, off[0].note], [1, true, "Can't pause: not enough space"], "can't run: Pause dimmed, saying why")
assert.deepEqual(acts(true, null, Object.assign({}, on, { turnedOn: false }), T, { live: true, iptv: true }), [], "off: none")
assert.deepEqual(acts(false, null, on, T, { live: true, iptv: true }), [], "not full screen: none")
assert.match(guideSrc, /if \(tsOffMenu\) return \[\{ key: "tsOn", label: "Turn on", icon: "", note: "Pause and rewind is off" \}\]/, "off, J K L: as approved")
assert.match(guideSrc, /if \(key === "recPause"\) return "Pause, go back and catch up while you watch live TV\. Keeps the last 5 or 30 minutes on the recordings drive, writing the whole time you watch\."/)
assert.match(guideSrc, /\{ key: "recPause", label: "Pause and rewind", kind: "choice" \}/)
const ident = read("ui/ChannelIdent.qml")
assert.match(ident, /ident\.status === "filling" \? "Starting pause and rewind…" : ident\.status === "stalled" \? "Waiting for the channel…"/, "as approved")

// ---- the agents ----
const commandsSrc = read("Commands.qml")
const problem = new Function("guide", "Ts", block(commandsSrc, "function pauseProblem() {"))
const g = { pauser: { turnedOn: false }, reception: "on", vod: null, multiview: { active: false }, onAir: { live: true, iptv: true } }
assert.match(problem(g, T), /^pause and rewind is off/, "off: said, never turned on")
g.pauser = { turnedOn: true, active: false, filling: false, cantPauseText: "Can't pause: the drive isn't plugged in" }
g.vod = { id: "x" }
assert.equal(problem(g, T), "no live channel is on the TV", "a video on: refused")
g.vod = null
g.multiview.active = true
assert.equal(problem(g, T), "no live channel is on the TV", "Multiview: refused")
g.multiview.active = false
assert.equal(problem(g, T), "Can't pause: the drive isn't plugged in", "not running: why")
g.pauser.filling = true
assert.match(problem(g, T), /still starting/)
g.pauser = { turnedOn: true, active: true }
assert.equal(problem(g, T), "")
assert.match(block(commandsSrc, "function setRecordingSettings(json: string): string {"), /Ts\.MINUTES\.indexOf\(given\.pauseAndRewind\) >= 0\) changes\.timeshift = given\.pauseAndRewind/)

console.log("timeshift: all good")
