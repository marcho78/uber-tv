// Recordings, the guide's side (Dvr.js, DVR.qml, Guide.qml, Commands.qml):
// the SHA-256 that names a recording's channel matches node's; settings
// checked, the place's defaults (8 GB and 720p on a small system disk);
// what a Record press records (to the show's end with listings plus the
// late padding, an hour without, a scheduled video saved whole); the stop
// times on offer, never past 12 hours from the start; a card's state and the
// Recordings rows (what needs you, then recording, then upcoming, then recorded); which
// provider a stream comes from. The banner's choices: Record (not when it
// can't start), Stop, the stop times and back out of them; a recording's
// choices in its details, Delete only on a second OK; a locked channel's
// recording asks for the passcode before it plays, and says nothing about
// itself on its card or to an agent. The agent commands, run from their own
// code: refused while off and on a locked channel, lengths and stop times
// read, turning off while one records only with stopAndCancel, a drive
// that isn't opened refused, the library's tabs in order. The helper gets a
// job on stdin, never on its command line. Recordings start off, and the
// strip asks about them once, after updates.
//   node tests/dvr.test.mjs
import assert from "node:assert/strict"
import { createHash } from "node:crypto"
import { readFileSync } from "node:fs"

const read = f => readFileSync(new URL("../" + f, import.meta.url), "utf8")
const guideSrc = read("Guide.qml")
const commandsSrc = read("Commands.qml")
const dvrQml = read("DVR.qml")
const D = new Function(read("Dvr.js").replace(/^\.pragma library\s*/, "") +
  "; return { seriesPass, rulesOf, identities, streamKey, sha256, hashOf, defaults, checked, keepFreeOf, qualityOf, next, paddingLabel, jobFor, recordLabel, stopChoices, reasonText, reasonOf, stateOf, active, playable, needsYou, rows, sourceId, providerOf, fold, identity, slotFor, seriesShows, waiting, spanOf, clashes, forShow, PADDINGS, KEEP_FREE, QUALITIES, MAX_HOURS, AT_ONCE, GB }")()
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

// ---- the rules ----
for (const s of ["", "abc", "http://user:pass@host/live/1/2/3.ts", "é漢字🎬", "x".repeat(1000)])
  assert.equal(D.sha256(s), createHash("sha256").update(s).digest("hex"), "sha256 of " + s.slice(0, 20))

assert.deepEqual(D.checked(null), D.defaults())
assert.equal(D.defaults().on, false, "Recordings: off until turned on")
assert.equal(D.checked({}).on, false, "none saved for it: off")
assert.equal(D.checked({ on: "yes" }).on, false)
assert.equal(D.checked({ on: true }).on, true)
assert.deepEqual(D.checked({ on: false, keepFree: 7, quality: 999, padding: 9, atOnce: 9 }), { on: false, place: null, keepFree: 0, quality: 0, padding: 1, atOnce: 2, timeshift: 0 }, "bad values: auto")
assert.equal(D.checked({ place: { volume: "uuid:x", mount: "relative", rel: "a" } }).place, null, "a place's mount is a full path")
const place = D.checked({ place: { volume: "uuid:x", mount: "/run/media/me/USB", rel: "Uber TV Recordings", removable: true, label: "USB" } }).place
assert.equal(place.removable, true)
const smallDisk = { system: true, size: 32 * D.GB }
assert.equal(D.keepFreeOf(D.defaults(), smallDisk), 8, "a small system disk keeps 8 GB")
assert.equal(D.qualityOf(D.defaults(), smallDisk), 720, "and records YouTube at 720p")
assert.equal(D.keepFreeOf(D.defaults(), { removable: true, system: false, size: 32 * D.GB }), 5, "a USB drive: 5 GB")
assert.equal(D.qualityOf({ quality: 480 }, smallDisk), 480, "yours wins")
assert.equal(D.paddingLabel(1), "1 min early, 2 late")
assert.equal(D.paddingLabel(0), "None")

const now = 1_800_000_000
const iptv = { kind: "iptv", name: "News 24", url: "http://p.example/live/u/p/1.ts", number: 101, category: "News" }
let job = D.jobFor(iptv, { epg: true, title: "Evening News", start: now - 600, end: now + 1800, desc: "Today" }, now, 1)
assert.equal(job.kind, "iptv")
assert.equal(job.end, now + 1800 + 120, "to the show's end, 2 minutes late")
assert.equal(job.title, "Evening News")
assert.equal(job.channel.hash, D.sha256(iptv.url), "its channel by the address hashed")
assert.equal(job.listed, true)
job = D.jobFor(iptv, { epg: true, title: "Marathon", start: now, end: now + 20 * 3600 }, now, 1)
assert.equal(job.end, now + 12 * 3600, "never past 12 hours")
job = D.jobFor(iptv, { title: "News 24", start: now, end: now + 6 * 3600, live: true, iptv: true }, now, 1)
assert.equal(job.end, now + 3600, "no listings: an hour")
assert.equal(job.listed, false)
job = D.jobFor({ kind: "youtube", name: "Space", url: "https://y/@s", live: { id: "AbCdEfGhIjK", title: "Launch" } }, { live: true }, now, 1)
assert.deepEqual([job.kind, job.video, job.end], ["youtube-live", "AbCdEfGhIjK", now + 3600], "YouTube live: an hour")
job = D.jobFor({ kind: "youtube", name: "Kurz", url: "https://y/@k" }, { id: "ZyXwVuTsRqP", title: "Black holes", start: now - 60, end: now + 600 }, now, 1)
assert.deepEqual([job.kind, job.video, job.end], ["youtube-video", "ZyXwVuTsRqP", 0], "a scheduled channel's show: its video")
assert.equal(D.recordLabel(job), "Save video")
assert.equal(D.jobFor({ kind: "youtube", url: "u" }, { id: "../etc" }, now, 1), null, "not a video id: nothing")

const clock = t => "T" + (t - now)
let rec = { created: now, end: now + 1800 }
let ch = D.stopChoices(rec, now + 3000, now, clock)
assert.deepEqual(ch.map(c => c.key), ["show", "more", "1h", "2h", "max"])
assert.equal(ch[0].end, now + 3000)
assert.equal(ch[1].end, now + 3600, "+30 minutes on the stop")
assert.equal(ch.at(-1).end, now + 12 * 3600, "12 hours from the start at most")
assert.equal(ch.at(-1).label, "Until I stop — 12 h maximum")
rec = { created: now - 11 * 3600, end: now + 600 }
ch = D.stopChoices(rec, now + 100, now, clock)
assert.deepEqual(ch.map(c => c.key), ["show", "more", "1h", "max"], "near the limit: only what still fits in its 12 hours")
assert.deepEqual(D.stopChoices(rec, now + 30, now, clock).map(c => c.key), ["more", "1h", "max"], "a show ending in under a minute isn't offered")

assert.equal(D.stateOf({ state: "recording", kind: "iptv" }), "Recording")
assert.equal(D.stateOf({ state: "recording", kind: "youtube-video" }), "Saving")
assert.equal(D.stateOf({ state: "done", present: false }), "Drive missing")
assert.equal(D.stateOf({ state: "incomplete", present: true }), "Incomplete")
assert.equal(D.playable({ state: "done", present: true, path: "/x.ts" }), true)
assert.equal(D.playable({ state: "done", present: false, path: "" }), false)
const rows = D.rows([{ id: "a", state: "done", present: true, created: 3 }, { id: "b", state: "recording", created: 5 }, { id: "c", state: "failed", created: 1 },
                     { id: "d", state: "done", present: false, created: 4 }, { id: "e", state: "done", present: true, created: 6 },
                     { id: "f", state: "scheduled", start: 900, created: 7 }, { id: "g", state: "scheduled", start: 500, created: 8 },
                     { id: "h", state: "missed", created: 2 }, { id: "i", state: "conflict", start: 700, created: 9 }])
assert.deepEqual(rows.map(r => [r.key, r.list.map(x => x.id)]),
                 [["rec-attention", ["c", "h", "i", "d"]], ["rec-now", ["b"]], ["rec-upcoming", ["g", "f"]], ["rec-done", ["e", "a"]]],
                 "what needs you (Failed, Missed, Incomplete, Conflict, Drive missing), then recording, then what's coming (soonest first), then recorded (newest first)")

assert.equal(D.providerOf({ kind: "iptv", src: "abc123", url: "http://x/1" }), "src:abc123", "its playlist's id")
assert.equal(D.providerOf({ kind: "iptv", url: "http://user:pw@Cdn.Example:8080/live/1" }), "host:cdn.example", "else its host, the login left out")
assert.equal(D.providerOf({ kind: "youtube", url: "https://y" }), "", "YouTube has no stream limit")
assert.equal(D.sourceId("https://p.example/list.m3u").length, 12)

// ---- the helper's job on stdin, never its command line ----
assert.ok(block(dvrQml, "function record(row, done, end, show, rule) {").includes('dvr.call(["start"], JSON.stringify(job)'), "the job (with a stream's address) on stdin")
assert.ok(!/call\(\["start", /.test(dvrQml), "never as an argument")
assert.match(dvrQml, /r\.start\(\["\/usr\/bin\/python3", "-I", dvr\.helper\]\.concat\(args\)/, "the helper by its path, isolated")

// ---- the banner's choices (Guide.qml) ----
{
  const pick = new Function("root", "dvr", "bannerTimer", "i", block(guideSrc, "function pickBannerAct(i) {"))
  const back = new Function("root", "bannerTimer", block(guideSrc, "function bannerBack() {"))
  const seen = []
  const timer = { restart() {}, stop() {} }
  const dvr = { busy: false, record: r => seen.push("record " + r), stop: id => seen.push("stop " + id), setEnd: (id, e) => seen.push("end " + id + " " + e) }
  const root = { tunedRow: 4, bannerAct: 2, recStopMenu: false, muted: false, recOnTuned: { id: "r1" },
                 bannerActions: [], hideBanner() { seen.push("hide") }, openMultiview() { seen.push("mv") }, goPip() {}, showGuide() {},
                 bannerBack() { back(root, timer) } }
  root.bannerActions = [{ key: "multiview" }, { key: "record", unavailable: true }]
  pick(root, dvr, timer, 1)
  assert.deepEqual(seen.splice(0), [], "Record that can't start: nothing")
  root.bannerActions = [{ key: "multiview" }, { key: "record" }]
  pick(root, dvr, timer, 1)
  assert.deepEqual(seen.splice(0), ["record 4"], "Record: the channel on")
  dvr.busy = true
  pick(root, dvr, timer, 1)
  assert.deepEqual(seen.splice(0), [], "not twice while one starts")
  root.bannerActions = [{ key: "multiview" }, { key: "recStop" }, { key: "recUntil" }]
  pick(root, dvr, timer, 1)
  assert.deepEqual(seen.splice(0), ["stop r1"])
  pick(root, dvr, timer, 2)
  assert.equal(root.recStopMenu, true, "Until …: the stop times")
  root.bannerActions = [{ key: "recEnd", end: 123 }]
  pick(root, dvr, timer, 0)
  assert.deepEqual(seen.splice(0), ["end r1 123"], "a stop time picked")
  assert.equal(root.recStopMenu, false, "and back to the choices")
  root.recStopMenu = true
  root.bannerActions = [{ key: "multiview" }, { key: "recStop" }, { key: "recUntil" }]
  back(root, timer)
  assert.deepEqual([root.recStopMenu, seen.splice(0)], [false, []], "Esc in the stop times: back out, not away")
  back(root, timer)
  assert.deepEqual(seen.splice(0), ["hide"], "then away")
  assert.ok(block(guideSrc, "function remoteCommand(cmd, number, by, digits, extra) {").includes('else if (cmd === "down" || cmd === "back") root.bannerBack()'), "the phone's ▼ and BACK too")
  assert.match(read("GuideKeys.qml"), /Key_Escape \|\| k === Qt\.Key_Backspace \|\| k === Qt\.Key_Down\) guide\.bannerBack\(\)/)
}

// ---- a recording's card, choices and playing (Guide.qml) ----
{
  const card = new Function("root", "dvr", "DvrRules", "library", "Qt", "rec", block(guideSrc, "function recordingCard(rec) {"))
  const entry = new Function("root", "library", "rec", "title", "hide", "locked", block(guideSrc, "function recordingEntry(rec, title, hide, locked) {"))
  const locks = { hidden: new Set(), locked: new Set() }
  const dvr = { hidden: r => locks.hidden.has(r.id), locked: r => locks.locked.has(r.id), byId: {}, channelOf: r => r.ch || null }
  const library = { idFor: u => "f:" + u }
  const Qt = { formatDateTime: () => "Oct 19" }
  const root = { now, clock: t => "9:00", dayTime: t => "Oct 19, 9:00", lengthLabel: s => s ? Math.round(s / 60) + " min" : "", fileUrl: p => "file://" + p }
  root.recordingEntry = (...a) => entry(root, library, ...a)
  root.recordingCard = r => card(root, dvr, D, library, Qt, r)
  const done = { id: "r1", kind: "iptv", state: "done", present: true, path: "/rec/News.ts", title: "News", titles: ["News"], desc: "Today",
                 channel: { name: "News 24", hash: "h" }, created: now - 3600, duration: 1800, thumb: "/thumbs/rec-r1.jpg" }
  let c = root.recordingCard(done)
  assert.deepEqual([c.kind, c.title, c.poster, c.entry.url, c.entry.recId, c.id], ["recording", "News", "/thumbs/rec-r1.jpg", "file:///rec/News.ts", "r1", "f:file:///rec/News.ts"],
                   "a recording: its card, played from its file (resume as My Videos)")
  locks.locked.add("r1")
  c = root.recordingCard(done)
  assert.deepEqual([c.title, c.poster, c.entry.description], ["News", "", ""], "a locked channel's: no picture, no description")
  locks.hidden.add("r1")
  c = root.recordingCard(done)
  assert.deepEqual([c.title, c.sub], ["Locked recording", ""], "while the lock hides titles: nothing about it")
  const going = { id: "r2", kind: "iptv", state: "recording", created: now - 600, started: now - 600, end: now + 600, channel: { name: "C" }, titles: ["A", "B"] }
  c = root.recordingCard(going)
  assert.deepEqual([c.entry, c.id, c.title, c.recState], [null, "rec:r2", "A · B", "Recording"], "recording: not playable yet; both back-to-back shows named")
  assert.ok(Math.abs(c.recProgress - 0.5) < 0.01, "how far to its stop")

  const actsSrc = guideSrc.match(/readonly property var recActions: \{([\s\S]*?)\n  \}\n/)[1]
  const acts = (rec, armed, resume, stopping, rule) => new Function("libDetailRec", "recArmed", "DvrRules", "root", "dvr", actsSrc)(rec, armed, D, { libResumeAt: () => resume || 0, recordingCard: r => ({ id: "x" }) },
                                                                                                                                       { stopping: stopping || {}, ruleOf: () => rule || null })
  assert.deepEqual(acts(done, "", 0).map(a => a.key), ["play", "delete"])
  assert.deepEqual(acts(done, "", 30).map(a => a.label), ["Resume", "Start over", "Delete recording…"])
  assert.equal(acts(done, "r1", 0)[1].label, "OK again to delete it", "Delete asks for a second OK")
  assert.deepEqual(acts(going, "").map(a => a.key), ["watch", "stop"], "recording: watch it live, or stop")
  assert.deepEqual(acts(going, "", 0, { r2: true }).map(a => a.label), ["Stopping…"], "Stop pressed: Stopping…, nothing to press twice")
  assert.deepEqual(acts({ ...done, present: false }, "").map(a => a.label), ["Take it off the list…"], "a missing drive's: off the list (the file stays)")

  const act = new Function("root", "dvr", "i", block(guideSrc, "function recAct(i) {"))
  const seen = []
  const r2 = { recActions: acts(done, ""), libDetailRec: done, libEpisode: 1, recArmed: "", libDetail: { rec: done },
               playRecording: (c, s) => seen.push("play " + s) }
  const d2 = { remove: id => seen.push("remove " + id), stop: id => seen.push("stop " + id) }
  act(r2, d2)
  assert.deepEqual([seen.splice(0), r2.recArmed], [[], "r1"], "Delete: armed, nothing deleted")
  act(r2, d2)
  assert.deepEqual(seen.splice(0), ["remove r1"], "the second OK deletes it")
  r2.libEpisode = 0
  act(r2, d2)
  assert.deepEqual(seen.splice(0), ["play false"])

  const play = new Function("root", "dvr", "DvrRules", "channelLockItem", "card", "fromStart", block(guideSrc, "function playRecording(card, fromStart) {"))
  const lockedCh = { url: "x" }
  const ask = []
  const r3 = { opened: true, libDetail: {}, channels: [lockedCh], recordingCard: root.recordingCard, playVod: e => seen.push("vod " + e.url), summonGuide() {}, watch: r => seen.push("watch " + r) }
  locks.hidden.clear(); locks.locked.clear()
  const cl = { blocks: c => c === lockedCh, askUnlock: (c, then) => ask.push(then) }
  assert.equal(play(r3, { ...dvr, channelOf: () => lockedCh, lockChannelOf: () => lockedCh }, D, cl, { rec: done }, false), "asked for the passcode")
  assert.deepEqual(seen.splice(0), [], "a locked channel's recording: not before the passcode")
  assert.equal(play(r3, { ...dvr, channelOf: () => null, lockChannelOf: () => null }, D, cl, { rec: done }, true), "ok")
  assert.deepEqual(seen.splice(0), ["vod file:///rec/News.ts"])
  assert.equal(play(r3, { ...dvr, channelOf: () => lockedCh, lockChannelOf: () => lockedCh }, D, cl, { rec: going }, false), "ok")
  assert.deepEqual(seen.splice(0), ["watch 0"], "one still recording: its channel live")
  assert.match(block(guideSrc, "function enforceLock() {"), /root\.vod\.recId && dvr\.locked\(/, "a recording playing stops when its channel locks")

  const order = new Function("libraryTabKinds", "given", block(guideSrc, "function checkedLibraryOrder(given) {"))
  const kinds = ["movies", "ondemand", "videos", "recordings", "mylist"].map(key => ({ key }))
  assert.deepEqual(order(kinds, ["recordings", "nope", "movies", "recordings"]), ["recordings", "movies", "ondemand", "videos", "mylist"], "yours first, the rest in theirs")
}

// ---- recording elsewhere (DVR.qml): said at the top of the guide (never on another channel's banner), and two streams from one provider ----
{
  const elsewhere = new Function("dvr", block(dvrQml, "function elsewhere() {"))
  const shares = new Function("dvr", "Dvr", "ch", block(dvrQml, "function sharesProvider(ch) {"))
  const a = { url: "http://p/1.ts", kind: "iptv", src: "aaaaaaaaaaaa" }, b = { url: "http://p/2.ts", kind: "iptv", src: "aaaaaaaaaaaa" }, c = { url: "http://q/3.ts", kind: "iptv" }
  const r1 = { id: "1", channel: { name: "CBS News" } }, r2 = { id: "2", channel: { name: "Two" }, private: true }
  const dvr = { active: [r1], hidden: () => false, channelOf: r => r === r1 ? a : b }
  assert.equal(elsewhere(dvr), "● Recording CBS News")
  dvr.active = [r2]
  assert.equal(elsewhere(dvr), "● Recording a locked channel", "a locked channel's not named")
  dvr.active = [r1, r2]
  assert.equal(elsewhere(dvr), "● 2 recording")
  dvr.active = []
  assert.equal(elsewhere(dvr), "")
  // a video being saved isn't a channel recording: not named, not counted
  dvr.active = [{ kind: "youtube-video", channel: { name: "Lofi" }, title: "Mix" }]
  assert.equal(elsewhere(dvr), "", "a save alone: nothing at the top")
  dvr.active = [{ kind: "youtube-video", channel: { name: "Lofi" } }, { kind: "iptv", channel: { name: "CBS News" } }]
  assert.equal(elsewhere(dvr), "● Recording CBS News", "a save and a recording: only the recording")
  dvr.active = [r1]
  assert.equal(shares(dvr, D, b), true, "watching another of its provider's channels: two streams")
  assert.equal(shares(dvr, D, a), false, "the one recording itself: that's its own banner")
  assert.equal(shares(dvr, D, c), false, "another provider: no")
  assert.match(guideSrc, /onRecOnTunedIdChanged: if \(recOnTunedId && bannerOptions && !recStopMenu && \(bannerActions\[bannerAct\] \|\| \{\}\)\.key === "recStop"\)/,
               "Record turned into Stop under the cursor: the cursor moves to Until, once")
  assert.match(block(guideSrc, "readonly property var bannerActions: {"), /dvr\.stopping\[recOnTuned\.id\] \? \[\{ key: "recStopping", label: "Stopping…"/, "Stop pressed: Stopping… at once")
}

// ---- review round 1: the lock follows a removed channel; a 2nd stream is asked once ----
{
  const lockOf = new Function("dvr", "guide", "Dvr", "rec", block(dvrQml, "function lockChannelOf(rec) {"))
  const gone = "http://p/old.ts"
  const guide = { channels: [{ url: "http://p/new.ts", name: "Renamed" }], channelLock: { entries: [{ url: gone, name: "Old Name" }] } }
  const dvr = { channelOf: () => null }
  const rec = { channel: { hash: D.sha256(gone), name: "Old Name" } }
  assert.deepEqual(lockOf(dvr, guide, D, rec), { url: gone, name: "Old Name", kind: "iptv" }, "its channel gone: still found by its lock entry, unlockable by that address")
  const byName = { channel: { hash: "0".repeat(64), name: "Renamed" } }
  assert.equal(lockOf(dvr, guide, D, byName), guide.channels[0], "else by name, as the lock goes")
  assert.equal(lockOf(dvr, guide, D, { channel: { hash: "1".repeat(64), name: "Nobody" } }), null)
  assert.match(dvrQml, /function locked\(rec\) \{ var ch = dvr\.lockChannelOf\(rec\)/, "locked and hidden go by it")
  assert.ok(block(guideSrc, "function playRecording(card, fromStart) {").includes("dvr.lockChannelOf(rec)"), "and so does playing")

  const needs = new Function("dvr", "Dvr", "ch", block(dvrQml, "function needsAsk(ch) {"))
  const a = { url: "http://p/1.ts", kind: "iptv", src: "aaaaaaaaaaaa" }, b = { url: "http://p/2.ts", kind: "iptv", src: "aaaaaaaaaaaa" }
  const d2 = { allowed: {}, recordingFrom: p => p === "src:aaaaaaaaaaaa" }
  assert.equal(needs(d2, D, b), true, "another of the provider's channels while one records: asked")
  assert.equal(needs(d2, D, a), true, "the one recording too: watching it is a 2nd stream")
  d2.allowed = { "src:aaaaaaaaaaaa": true }
  assert.equal(needs(d2, D, b), false, "once Watch anyway is said: not again")

  const ok = new Function("root", "dvr", "bannerTimer", "keys", "r", "then", block(guideSrc, "function streamOk(r, then) {"))
  const ans = new Function("root", "dvr", "keys", "yes", block(guideSrc, "function answerStream(yes) {"))
  const seen = []
  const timer = { restart() {}, stop() {} }
  const keys = { forceActiveFocus() {} }
  const root = { channels: [a, b], tunedRow: 0, reception: "on", watching: true, pip: false, opened: true, dialog: "", streamAsk: null, bannerOptions: false,
                 hideBanner() { root.bannerOptions = false }, summonGuide() { seen.push("summon") } }
  const d3 = { needsAsk: () => true, allow: ch => seen.push("allow " + ch.url) }
  assert.equal(ok(root, d3, timer, keys, 0, () => seen.push("then")), true, "already playing it: no question")
  assert.equal(ok(root, d3, timer, keys, 1, () => seen.push("then")), false, "watching full screen: asked")
  assert.deepEqual([root.bannerOptions, root.streamAsk.row, root.dialog], [true, 1, ""], "on the banner, not a box")
  ans(root, d3, keys, false)
  assert.deepEqual([seen.splice(0), root.streamAsk], [[], null], "Stay: nothing opened")
  root.watching = false
  ok(root, d3, timer, keys, 1, () => seen.push("then"))
  assert.equal(root.dialog, "recStream", "in the guide: a box")
  ans(root, d3, keys, true)
  assert.deepEqual([seen.splice(0), root.dialog], [["allow http://p/2.ts", "then"], ""], "Watch anyway: remembered for that provider, then watched")
  assert.match(block(guideSrc, "function surf(delta) {"), /if \(!root\.streamOk\(to,/, "surfing asks before it tunes")
  assert.match(block(guideSrc, "function watch(r) {"), /!root\.streamOk\(r,/, "and watching")
  assert.match(block(guideSrc, "function previewRow() {"), /dvr\.needsAsk\(ch\)/, "the preview waits on those channels")
  assert.match(block(guideSrc, "function remoteCommand(cmd, number, by, digits, extra) {"), /if \(!root\.streamOk\(i, function\(\) \{ root\.remoteCommand\("tune", number, by\) \}\)\) return/, "a phone's number too")
  assert.match(block(guideSrc, "function remoteCommand(cmd, number, by, digits, extra) {"), /if \(root\.dialog === "recStream"\) \{[^}]*cmd === "ok"\) root\.answerStream\(true\)/, "the phone answers the box")
  assert.match(block(guideSrc, "function remoteCommand(cmd, number, by, digits, extra) {"), /if \(cmd === "up"\) root\.libEpisodeMove\(-1\)\n\s*else if \(cmd === "down"\) root\.libEpisodeMove\(1\)\n\s*else if \(cmd === "ok"\) root\.libDetailOk\(\)/,
               "the phone's OK in a recording's details picks the choice under the cursor")

  // the small-disk defaults: only the system disk
  assert.equal(D.keepFreeOf(D.defaults(), { system: true, size: 32 * D.GB }), 8)
  assert.equal(D.keepFreeOf(D.defaults(), { system: false, size: 32 * D.GB }), 5, "a 32 GB USB drive or second disk: 5 GB")
  assert.equal(D.qualityOf(D.defaults(), { system: false, removable: false, size: 32 * D.GB }), 1080)
  // off while one starts: nothing survives
  assert.ok(block(dvrQml, "function record(row, done, end, show, rule) {").includes("if (!dvr.settings.on) { dvr.busy = false"), "turned off before the start: it doesn't start")
  assert.ok(block(dvrQml, "function record(row, done, end, show, rule) {").includes("if (res.ok && !dvr.settings.on) dvr.stop(res.id)"), "turned off as it started: stopped at once, new or joined")
}

// ---- review round 2: the show's choices in the guide; the provider kept; Multiview asks ----
{
  const offerSrc = block(dvrQml, "function offer(row, show) {")
  const offer = (ch, show, extra) => new Function("dvr", "guide", "Dvr", "row", "show", offerSrc)(
    Object.assign({ settings: { on: true, padding: 1, place: null }, active: [], placeInfo: null, keepFreeGB: 5, said: "",
                    chanFor: () => Object.assign({ number: 1 }, ch), secondStream: () => false, hidden: () => false, placeLabel: "Videos folder" }, extra || {}),
    { channels: [ch], airing: () => ({ epg: false, title: ch.name, start: 0, end: 0 }) }, D, 0, show)
  const t = Date.now() / 1000
  const iptv = { kind: "iptv", name: "News", url: "http://p/1.ts" }
  assert.equal(offer(iptv, { epg: true, title: "Later", start: t + 3600, end: t + 7200 }), null, "an IPTV show that hasn't started: not recorded now (scheduling, later)")
  const now = offer(iptv, { epg: true, title: "Evening News", start: t - 60, end: t + 1800 })
  assert.deepEqual([now.label, now.job.title, now.job.end], ["Record", "Evening News", Math.round(t + 1800 + 120)], "the show on now: to its end")
  const yt = { kind: "youtube", name: "Kurz", url: "https://y/@k" }
  const picked = offer(yt, { id: "PiCkEdViDeO", title: "Picked one", start: t + 7200, end: t + 7800 })
  assert.deepEqual([picked.label, picked.job.video], ["Save video", "PiCkEdViDeO"], "a scheduled channel's show: the one picked is saved, not whatever's airing")
  assert.equal(offer(iptv, { epg: true, title: "x", start: t - 60, end: t + 60 }, { settings: { on: false, padding: 1 } }), null, "Recordings off: no Record")
  const twoOn = [{ title: "A", channel: { name: "A" } }, { title: "B", channel: { name: "B" } }]
  const full = offer(iptv, { epg: true, title: "x", start: t - 60, end: t + 600 }, { active: twoOn, settings: { on: true, padding: 1, place: null, atOnce: 2 } })
  assert.deepEqual([full.unavailable, full.note], [true, "Too many recordings right now"], "as many recording as allowed: Record can't start, saying so (no titles: it fits)")
  assert.equal(offer(iptv, { epg: true, title: "x", start: t - 60, end: t + 600 }, { active: twoOn, settings: { on: true, padding: 1, place: null, atOnce: 3 } }).unavailable, false,
               "three allowed: a third can")

  const openSrc = block(guideSrc, "function openShowChoices() {")
  const shown = { has: () => true, at: (url, at) => ({ epg: true, title: "Listed at " + at, start: at, end: at + 1800 }) }
  const open = (root, dvr, keys, listings) => new Function("root", "dvr", "keys", "listings", "DvrRules", openSrc)(root, dvr, keys, listings || shown, D)
  const act = (root, dvr, i, listings) => new Function("root", "dvr", "i", "listings", block(guideSrc, "function showChoiceAct(i) {"))(root, dvr, i, listings || shown)
  const choicesSrc = guideSrc.match(/readonly property var showChoices: \{([\s\S]*?)\n  \}\n/)[1]
  const choices = (c, dvr) => new Function("showChoice", "DvrRules", "dvr", choicesSrc)(c, D, dvr || { stopping: {} })
  const seen = []
  const root = { row: 0, channels: [iptv], screen: "guide", selected: { epg: true, title: "Evening News", start: t - 60, end: t + 1800 }, airs: () => true, dialog: "",
                 watch: r => seen.push("watch " + r), closeShowChoices() { root.showChoice = null; root.dialog = "" }, askToWatch: () => false }
  const base = { settings: { on: true }, rules: [], forShow: () => null, laterOffer: () => null, ruleOf: () => null, ruleFor: () => null }
  const d = Object.assign({}, base, { offer: (r, sh) => sh && sh.title === "Evening News" ? { label: "Record", note: "", unavailable: false } : null, record: (r, done, end, sh) => seen.push("record " + sh.title) })
  open(root, d, { forceActiveFocus() {} })
  assert.equal(root.dialog, "showChoices", "I or Space on a show: its choices")
  root.showChoices = choices(root.showChoice)
  assert.deepEqual(root.showChoices.map(c => c.key), ["watch", "record", "series"], "Watch, Record, and Record every episode")
  root.showCursor = 1
  act(root, d)
  assert.deepEqual(seen.splice(0), ["record Evening News"], "Record: that show")
  assert.match(read("GuideKeys.qml"), /else if \(k === Qt\.Key_Return \|\| k === Qt\.Key_Enter\) guide\.watch\(guide\.row\)\n\s*else if \(k === Qt\.Key_I \|\| k === Qt\.Key_Space\) guide\.openShowChoices\(\)/, "Enter still watches; I or Space opens the choices")
  assert.match(block(guideSrc, "function remoteCommand(cmd, number, by, digits, extra) {"), /else if \(root\.screen === "guide"\) root\.openShowChoices\(\)/, "phone ⋯ in the guide too")

  // a locked channel's cell (its show hidden): on now, Record (after the
  // passcode, what's on); later, Record and Record every episode, the
  // passcode first, then the show listed at that time, never what's on now
  const lockedCell = { locked: true, live: false, id: "", title: "Locked", start: t - 3600, end: t + 7200 }
  const offers = []
  const d4 = Object.assign({}, base, { offer: (r, sh) => { offers.push(sh); return { label: "Record", note: "", unavailable: false } }, record: (r, done, end, sh) => seen.push("record " + (sh ? sh.title : "on now")),
                                       schedule: (r, sh) => seen.push("schedule " + sh.title), recordSeries: (r, sh) => seen.push("series " + sh.title) })
  Object.assign(root, { selected: lockedCell, cursorAt: t, dialog: "" })
  open(root, d4, { forceActiveFocus() {} })
  assert.deepEqual([offers.pop(), choices(root.showChoice).map(c => c.key)], [null, ["watch", "record", "series"]], "on now: Record, worked out from what's on (the hidden show isn't kept)")
  root.showChoices = choices(root.showChoice)
  root.showCursor = 1
  act(root, d4)
  assert.deepEqual(seen.splice(0), ["record on now"])
  Object.assign(root, { selected: lockedCell, cursorAt: t + 5400, dialog: "" })
  open(root, d4, { forceActiveFocus() {} })
  root.showChoices = choices(root.showChoice)
  assert.deepEqual([root.showChoice.offer, root.showChoices.map(c => c.key)], [null, ["watch", "schedule", "series"]], "later on a locked channel: Record (scheduled) and Record every episode")
  let asked = null
  root.askToWatch = (r, then) => { asked = then; return true }
  root.showCursor = 1
  act(root, d4)
  assert.deepEqual([seen.splice(0), typeof asked], [[], "function"], "the passcode first: nothing scheduled yet")
  asked()
  assert.deepEqual(seen.splice(0), ["schedule Listed at " + (t + 5400)], "then the show listed at that time (never the one on now)")
  root.askToWatch = () => false

  // the real path: a playlist channel's provider reaches the job through chanFor
  const chanFor = new Function("guide", "row", block(dvrQml, "function chanFor(row) {"))
  const one = { kind: "iptv", name: "One", url: "http://cdn-a.example/1.ts", src: "abcdefabcdef" }, two = { kind: "iptv", name: "Two", url: "http://cdn-b.example/2.ts", src: "abcdefabcdef" }
  const job = D.jobFor(chanFor({ channels: [one, two], numbers: [101, 102] }, 0), { epg: false }, t, 1)
  assert.equal(job.provider, "src:abcdefabcdef", "its playlist's id, not its host")
  const from2 = new Function("dvr", "Dvr", "p", block(dvrQml, "function recordingFrom(p) {"))
  const needs2 = new Function("dvr", "Dvr", "ch", block(dvrQml, "function needsAsk(ch) {"))
  const d5 = { active: [{ provider: job.provider, channel: job.channel }], channelOf: () => null, allowed: {} }
  d5.recordingFrom = p => from2(d5, D, p)
  assert.equal(needs2(d5, D, two), true, "another channel of that playlist on another host, its own channel gone since: still asked")

  // the provider kept with a recording: still known when its channel's gone
  const from = new Function("dvr", "Dvr", "p", block(dvrQml, "function recordingFrom(p) {"))
  assert.equal(from({ active: [{ provider: "src:aaaaaaaaaaaa", channel: { hash: "x" } }], channelOf: () => null }, D, "src:aaaaaaaaaaaa"), true, "its channel gone: its provider still counts")
  assert.equal(D.jobFor({ kind: "iptv", name: "N", url: "http://h/1", src: "bbbbbbbbbbbb" }, { epg: false }, t, 1).provider, "src:bbbbbbbbbbbb", "the job carries it")

  // Multiview: a tile's channel change to a 2nd stream opens the marked list instead
  const mvSrc = read("ui/Multiview.qml")
  assert.match(block(mvSrc, "function flip(d) {"), /if \(mv\.askFirst\(r\)\) return/, "CH+/CH- and media keys on a tile ask first")
  assert.match(mvSrc, /if \(!ch \|\| mv\.slots\.indexOf\(ch\.url\) >= 0\) return true\n\s*if \(mv\.askFirst\(r\)\) return true/, "and a phone's number")
}

// ---- the agent commands (Commands.qml) ----
{
  const fn = (opener, params) => new Function("guide", "commands", "DvrRules", ...params, block(commandsSrc, opener))
  const channels = [{ url: "http://p/1.ts", name: "One", kind: "iptv" }, { url: "http://p/2.ts", name: "Two", kind: "iptv" }]
  const locked = { "http://p/2.ts": true }
  const seen = []
  const t0 = Math.floor(Date.now() / 1000)
  const rec = { id: "aaaaaaaaaaaaaaaa", kind: "iptv", state: "recording", created: t0 - 60, end: t0 + 3000, title: "Show", channel: { name: "One", number: 101 } }
  const lockedRec = { id: "bbbbbbbbbbbbbbbb", kind: "iptv", state: "done", present: true, path: "/r/Secret.ts", title: "Secret", channel: { name: "Two", number: 102 } }
  const dvr = { settings: { on: true, place: null, keepFree: 0, quality: 0, padding: 1 }, busy: false, active: [rec], recordings: [rec, lockedRec],
                byId: { [rec.id]: rec, [lockedRec.id]: lockedRec }, drives: [{ device: "/dev/sdb1", label: "USB", mount: "" }, { device: "/dev/sdc1", label: "Big", mount: "/run/media/me/Big", free: 9 }],
                placeLabel: "Videos folder", placeInfo: { problem: "", path: "/home/me/Videos/Uber TV Recordings", free: 100 }, keepFreeGB: 5, quality: 1080,
                hidden: r => r === lockedRec, locked: r => r === lockedRec,
                offer: r => r === 0 ? { label: "Record", note: "", job: { kind: "iptv", end: now + 3600 } } : null,
                record: (r, done, end) => { seen.push(["record", r, end]); return "ok" }, setEnd: (id, e) => seen.push(["end", id]), stop: id => seen.push(["stop", id]),
                remove: id => seen.push(["remove", id]), turnOff: () => seen.push(["off"]), set: c => seen.push(["set", c]), useDefault: () => seen.push(["default"]),
                useFolder: p => seen.push(["folder", p]), listDrives() {}, checkPlace() {}, refresh() {} }
  const guide = { recorder: dvr, numbers: [101, 102], channels, airs: () => true, clock: () => "9:00", opened: true, libraryOrder: [], saveSettings() {},
                  channelLock: { loaded: true, blocks: c => !!locked[c.url] } }
  guide.recOffWhat = () => new Function("dvr", "DvrRules", block(guideSrc, "function recOffWhat() {"))(dvr, D)
  const commands = { okReply: o => ({ ok: true, ...o }), failReply: e => ({ ok: false, error: e }), recordingsOff: "off",
                     channelInfo: r => ({ number: guide.numbers[r] }) }
  for (const [name, params] of Object.entries({ rowsFor: ["numbers"], recordingInfo: ["rec"], recordingSettingsInfo: [], recordingById: ["id"] })) {
    const f = fn("function " + name + "(", params)
    commands[name] = (...a) => f(guide, commands, D, ...a)
  }
  const ipc = (name, params) => { const f = fn("function " + name + "(" + params.map(p => p + ": string").join(", ") + "): string {", params); return (...a) => f(guide, commands, D, ...a) }
  const record = ipc("record", ["number", "length"])
  const until = ipc("recordUntil", ["id", "when"])
  const setRec = ipc("setRecordingSettings", ["json"])
  const setRecPre = setRec

  assert.match(record("102", "").error, /locked: only the user/, "not a locked channel")
  dvr.busy = true
  dvr.active = []
  assert.match(setRecPre('{"on": false}').error, /would stop 1 recording: one starting/, "off while one is starting: told, not done")
  dvr.busy = false
  dvr.active = [rec]
  assert.match(record("999", "").error, /no channel 999/)
  assert.match(record("101", "soon").error, /minutes/, "a length it can read")
  assert.match(record("101", "13h").error, /12 hours/)
  let res = record("101", "90")
  assert.equal(res.ok, true)
  assert.ok(Math.abs(seen.at(-1)[2] - (Date.now() / 1000 + 5400)) < 5, "90 minutes from now")
  record("101", "")
  assert.equal(seen.at(-1)[2], 0, "\"\": the show's end (or an hour)")
  dvr.settings.on = false
  assert.equal(record("101", "").error, "off", "not while Recordings are off")
  dvr.settings.on = true

  assert.equal(until(rec.id, "30").ok, true)
  assert.match(until(rec.id, "1000").error, /12 hours/, "not past 12 hours from its start")
  assert.match(until(lockedRec.id, "30").error, /isn't recording/)
  assert.match(until("nope", "30").error, /no recording/)

  const info = commands.recordingInfo(lockedRec)
  assert.deepEqual([info.title, info.channel, info.file, info.locked], ["Locked recording", undefined, undefined, true], "a locked channel's says nothing about itself")
  assert.equal(commands.recordingInfo(rec).channel.name, "One")

  seen.length = 0
  assert.match(setRec('{"on": false}').error, /would stop 1 recording: Show/, "off while one records: told, not done")
  assert.deepEqual(seen, [], "nothing stopped")
  setRec('{"on": false, "stopAndCancel": true}')
  assert.deepEqual(seen.splice(0), [["off"]], "with stopAndCancel: off, stopping it")
  res = setRec('{"keepFree": 8, "quality": "auto", "padding": 2, "colour": 1}')
  assert.deepEqual(seen.splice(0), [["set", { keepFree: 8, quality: 0, padding: 2 }]])
  assert.deepEqual(res.ignored, ["colour"])
  assert.deepEqual(setRec('{"keepFree": 7}').ignored.length, 1, "only the choices offered")
  setRec('{"atOnce": 3}')
  assert.deepEqual(seen.splice(0), [["set", { atOnce: 3 }]], "how many at once, when the user asks")
  assert.match(setRec('{"atOnce": 7}').ignored[0], /atOnce \(1, 2, 3, 4\)/, "1 to 4 only")
  assert.match(setRec('{"place": "drive:/dev/sdb1"}').ignored[0], /isn't opened/, "a drive that isn't opened: the user opens it")
  setRec('{"place": "drive:/dev/sdc1"}')
  assert.deepEqual(seen.splice(0), [["folder", "/run/media/me/Big"]], "an opened drive: used, checked by the helper")
  setRec('{"place": "/home/me/Recordings"}')
  assert.deepEqual(seen.splice(0), [["folder", "/home/me/Recordings"]], "a folder: the helper checks it as for the user")
  assert.match(setRec('{"place": "Recordings"}').ignored[0], /full path/)
  // playRecording: once the guide is up, checked again
  assert.match(block(commandsSrc, "function playRecording(id: string): string {"), /commands\.pendingRecording = \{ id: rec\.id, tries: 0 \}/, "deferred until the guide is up")
  const fired = new Function("guide", "commands", "DvrRules", "recordingSoon", commandsSrc.match(/id: recordingSoon[\s\S]*?onTriggered: \{([\s\S]*?)\n    \}\n/)[1])
  const played = []
  const g2 = { opened: true, recorder: { byId: {}, locked: () => false }, recordingCard: r => r, playRecording: c => played.push(c.id) }
  const c2 = { pendingRecording: { id: "x", tries: 0 } }
  fired(g2, c2, D, { restart() {} })
  assert.deepEqual(played, [], "removed meanwhile: not played")
  g2.recorder.byId.y = { id: "y", state: "done", present: true, path: "/r/y.ts" }
  g2.recorder.locked = () => true
  c2.pendingRecording = { id: "y", tries: 0 }
  fired(g2, c2, D, { restart() {} })
  assert.deepEqual(played, [], "locked meanwhile: not played")
  g2.recorder.locked = () => false
  c2.pendingRecording = { id: "y", tries: 0 }
  fired(g2, c2, D, { restart() {} })
  assert.deepEqual(played, ["y"], "still fine: played")
  assert.match(block(commandsSrc, "function watch(number: string): string {"), /guide\.recorder\.needsAsk\(guide\.channels\[r\]\)\)\n\s*return commands\.failReply\("a recording is using that channel's provider/, "an agent never opens a 2nd stream")
}

// ---- later shows: scheduled, a series' episodes, conflicts, the checker ----
{
  for (const u of ["http://user:pass@host/live/1.ts", "", "__proto__", "é漢字"]) assert.equal(D.hashOf(u), D.sha256(u), "a channel's address hashed once a session: the same SHA-256")
  assert.equal(D.hashOf(undefined), D.sha256(""))
  const t = Math.floor(Date.now() / 1000)
  const ch = { kind: "iptv", name: "Food", url: "http://p/food.ts", src: "abcdefabcdef", number: 107 }
  const later = { epg: true, title: "Bake Off", sub: "Bread Week", ep: "S2E5", desc: "Loaves", start: t + 3600, end: t + 5400 }
  const slot = D.slotFor(ch, later, 1, "1111222233334444")
  assert.equal(D.streamKey({ kind: "iptv", provider: slot.provider, channel: slot.channel }), "ch:src:abcdefabcdef|food", "an IPTV stream by its provider and name")
  assert.deepEqual([slot.kind, slot.channel.hash, slot.provider, slot.showStart, slot.showEnd, slot.early, slot.late, slot.rule, slot.ep, slot.sub],
                   ["iptv", D.sha256(ch.url), "src:abcdefabcdef", t + 3600, t + 5400, 60, 120, "1111222233334444", "S2E5", "Bread Week"],
                   "a later show's slot: its channel by its address hashed, its times, its padding, its series")
  assert.equal("url" in slot || JSON.stringify(slot).includes(ch.url), false, "never the stream's address")
  assert.equal(D.slotFor({ kind: "youtube", url: "u" }, later, 1, ""), null, "IPTV only")
  assert.equal(D.slotFor(ch, { title: "x", start: t, end: t + 60 }, 1, ""), null, "only a listed show")
  assert.deepEqual([D.identity({ title: "Bake Off", ep: " S2E5 " }), D.identity({ title: "Bake  off", sub: "Bread  Week" }), D.identity({ show: { start: 5 } })],
                   ["ep:bake off|s2e5", "sub:bake off|bread week", "at:5"], "a show's identity: its title with its episode number, else its episode's title, else when it starts")
  assert.notEqual(D.identity({ title: "Bake Off", ep: "S1E2" }), D.identity({ title: "Quiz", ep: "S1E2" }), "two shows' S1E2 aren't one")
  const h = D.sha256(ch.url)
  const rule = { id: "1111222233334444", channel: { hash: h }, title: "Bake Off" }
  const shows = [{ epg: true, title: "bake  off", ep: "S2E6", start: t + 100, end: t + 200 }, { epg: true, title: "Bake Off", ep: "S2E5", start: t + 300, end: t + 400 },
                 { epg: true, title: "Bake Off", ep: "S2E7", start: t - 100, end: t + 50 }, { epg: true, title: "Bake Off Extra", start: t + 500, end: t + 600 },
                 { epg: true, title: "Bake Off", ep: "S2E4", start: t + 700, end: t + 800 }]
  const recs = [{ channel: { hash: h }, title: "Bake Off", ep: "S2E5", state: "done" }, { channel: { hash: h }, title: "Bake Off", ep: "S2E4", state: "failed" }]
  assert.deepEqual(D.seriesShows(rule, shows, recs, t).map(x => x.ep), ["S2E6", "S2E4"],
                   "a series' episodes: its title (spacing and case aside), not started, not recorded already (a failed one tried again)")
  const busy = [{ id: "1", state: "scheduled", kind: "iptv", channel: { hash: "1" }, start: t + 900, end: t + 2000, title: "Quiz" },
                { id: "2", state: "recording", kind: "iptv", channel: { hash: "2" }, end: t + 1500, title: "Film" }]
  assert.deepEqual(D.clashes(busy, "3", t + 1100, t + 1400, t).map(r => r.title), ["Film", "Quiz"], "two others then: one too many, naming them")
  assert.deepEqual(D.clashes(busy, "1", t + 1100, t + 1400, t), [], "back to back on a channel that's one of them: one stream, it fits")
  assert.deepEqual(D.clashes(busy, "3", t + 1600, t + 1700, t), [], "after one of them ends: it fits")
  assert.equal(D.forShow([busy[0]], "1", { start: t + 900 }, t), null, "a schedule goes by its show's start")
  assert.equal(D.forShow([{ ...busy[0], show: { start: t + 960 } }], "1", { start: t + 960, end: t + 1900 }, t).id, "1")
  assert.equal(D.forShow([busy[1]], "2", { start: t - 60, end: t + 600 }, t).id, "2", "the show on now while it records")
  assert.equal(D.reasonOf({ state: "conflict", others: ["id1", "id2"] }, ["Quiz", "Film"]), "Already scheduled: Quiz, Film", "a conflict names the others (as given)")
  assert.equal(D.reasonOf({ state: "conflict", others: ["id1"] }), "Conflict: too many recordings at this time", "never a name it wasn't given")
  // a video save is a stream of its own, even from one channel
  const saves = [{ id: "v1", state: "recording", kind: "youtube-video", channel: { hash: "9" }, end: 0 }, { id: "v2", state: "recording", kind: "youtube-video", channel: { hash: "9" }, end: 0 }]
  assert.deepEqual(D.clashes(saves, "3", t + 100, t + 200, t, 2).map(r => r.id), ["v1", "v2"], "two videos saving from one channel: two streams")
  assert.deepEqual(D.clashes(saves, "3", t + 100, t + 200, t, 3), [], "three at once: it fits")
  // every episode a recording holds, under its channel or its series
  const held = [{ channel: { hash: "old" }, rule: "9999000099990000", rules: ["9999000099990000", "1111222233334444"], ids: ["ep:bake off|s2e6", "ep:bake off|s2e9"], state: "done" }]
  assert.deepEqual(D.seriesShows(rule, [{ epg: true, title: "Bake Off", ep: "S2E9", start: t + 900, end: t + 1000 }], held, t), [],
                   "an episode joined into another series' recording, under an address since turned: known by its series")
  const rot = [{ id: "o", state: "recording", kind: "iptv", provider: "src:abcdefabcdef", channel: { hash: "old", name: "Food" }, end: t + 3000 }]
  assert.deepEqual(D.clashes(rot, D.streamKey({ kind: "iptv", provider: "src:abcdefabcdef", channel: { hash: "new", name: "food" } }), t + 100, t + 200, t, 1), [],
                   "one at once: the same channel under a new address is the same stream")
  assert.equal(D.clashes(rot, D.streamKey({ kind: "iptv", provider: "src:000000000000", channel: { hash: "x", name: "Food" } }), t + 100, t + 200, t, 1).length, 1,
               "another provider's channel of that name is another")
  assert.deepEqual(D.clashes(busy, "3", t + 1100, t + 1400, t, 3), [], "three at once allowed: it fits")
  assert.equal(D.clashes(busy, "3", t + 1600, t + 1700, t, 1).length, 1, "one at once: one other is too many")
  assert.deepEqual([D.checked({}).atOnce, D.checked({ atOnce: 4 }).atOnce, D.checked({ atOnce: 5 }).atOnce, D.checked({ atOnce: "3" }).atOnce], [2, 4, 2, 2],
                   "how many at once: 1 to 4, 2 to start with")
  assert.equal(D.stateOf({ state: "missed" }), "Missed")
  assert.match(D.reasonOf({ state: "missed", reason: "notRunning" }), /wasn't running/)

  const listedJob = D.jobFor({ kind: "iptv", name: "Food", url: "http://p/food.ts" }, { epg: true, title: "Bake Off", ep: "S2E8", sub: "Pies", start: t - 60, end: t + 1800 }, t, 1)
  assert.deepEqual([listedJob.ep, listedJob.sub, listedJob.show], ["S2E8", "Pies", { start: t - 60, end: t + 1800 }], "a listed show recorded now keeps its episode and times")

  // DVR.qml, from its own code
  const fn = (name, params) => new Function(...params, block(dvrQml, "function " + name + "(" ))
  const laterOffer = new Function("dvr", "guide", "Dvr", "row", "show", block(dvrQml, "function laterOffer(row, show) {"))
  const dq = { settings: { on: true, padding: 1, place: null, atOnce: 2 }, placeInfo: null, recordings: busy, chanFor: () => ch, hidden: () => false }
  dq.namesOf = r => new Function("dvr", "recs", block(dvrQml, "function namesOf(recs) {"))(dq, r)
  const g = { channels: [ch] }
  const clash = laterOffer(dq, g, D, 0, { ...later, start: t + 1100, end: t + 1420 })
  assert.deepEqual([clash.label, clash.note, clash.why, clash.unavailable], ["Record", "Conflict: too many recordings at this time", "Already scheduled: Film, Quiz", false],
                   "said before it's pressed: one too many then, the same short words on its row (no titles: it fits), the others named for the box")
  dq.settings.atOnce = 1
  dq.recordings = busy.slice(0, 1)
  assert.deepEqual([laterOffer(dq, g, D, 0, { ...later, start: t + 1100, end: t + 1420 }).note, laterOffer(dq, g, D, 0, { ...later, start: t + 1100, end: t + 1420 }).why],
                   ["Conflict: too many recordings at this time", "Already scheduled: Quiz"], "one at once, one in the way: the same row, that one named")
  dq.recordings = busy
  dq.settings.atOnce = 3
  assert.equal(laterOffer(dq, g, D, 0, { ...later, start: t + 1100, end: t + 1420 }).note, "", "three allowed at once: nothing to say")
  dq.settings.atOnce = 2
  assert.equal(laterOffer(dq, g, D, 0, { ...later, start: t + 30, end: t + 900 }), null, "on now: Record records it now instead")
  assert.equal(laterOffer({ ...dq, settings: { on: false, padding: 1 } }, g, D, 0, later), null, "Recordings off: nothing")
  dq.recordings = []
  dq.settings.place = { label: "Stick" }
  dq.placeInfo = { problem: "drive" }
  assert.equal(laterOffer(dq, g, D, 0, later).note, "Stick isn't plugged in now", "the drive missing now: said (it may be back by then)")

  // a conflict's others named as the lock is now (kept by their ids)
  const nm = { byId: { q: { id: "q", title: "Quiz", channel: { name: "Two" } }, f: { id: "f", title: "Film", channel: { name: "Three" } } }, hidden: r => r.id === "f" }
  nm.namesOf = r => new Function("dvr", "recs", block(dvrQml, "function namesOf(recs) {"))(nm, r)
  nm.othersOf = ids => new Function("dvr", "ids", block(dvrQml, "function othersOf(ids) {"))(nm, ids)
  const reasonOfQ = rec => new Function("dvr", "Dvr", "rec", dvrQml.match(/function reasonOf\(rec\) \{ (.*) \}\n/)[1])(nm, D, rec)
  assert.equal(reasonOfQ({ state: "conflict", others: ["q", "f", "gone"] }), "Already scheduled: Quiz, a locked channel, a recording",
               "a channel locked since isn't named; one gone is a recording")
  // the series a show is on, its channel's address turned since
  const rf2 = { rules: [{ id: "r1", title: "Bake Off", provider: "src:abcdefabcdef", channel: { hash: "old", name: "Food" } }] }
  const ruleFor = (c, title) => new Function("dvr", "Dvr", "ch", "title", block(dvrQml, "function ruleFor(ch, title) {"))(rf2, D, c, title)
  assert.equal(ruleFor(ch, "bake off").id, "r1", "by its name from the same provider")
  assert.equal(ruleFor({ ...ch, src: "000000000000" }, "Bake Off"), null, "not another provider's channel of that name")

  // the checker: due ones claimed, once
  const calls = []
  const ck = { recordings: [{ id: "a1", state: "scheduled", start: t - 10, end: t + 900, channel: { hash: h, name: "Food" }, provider: "src:abcdefabcdef" },
                            { id: "a2", state: "scheduled", start: t + 600, end: t + 900, channel: { hash: h } },
                            { id: "a3", state: "scheduled", start: t - 900, end: t - 10, channel: { hash: h } },
                            { id: "a4", state: "conflict", start: t - 10, end: t + 900, channel: { hash: h } }],
               claiming: {}, keepFreeGB: 5, quality: 720, hashMap: { [h]: ch },
               call: (args, input, done) => { calls.push([args, JSON.parse(input || "null")]); if (done) ck.pending = done },
               ready: then => then({ volume: "uuid:x", mount: "/m", rel: "R" }), refresh() {}, followLinks() {} }
  ck.channelByHash = (c, p) => fn("channelByHash", ["dvr", "guide", "Dvr", "c", "provider"])(ck, { channels: [ch] }, D, c, p)
  ck.claim = r => fn("claim", ["dvr", "Dvr", "rec"])(ck, D, r)
  const startDue = () => fn("startDue", ["dvr"])(ck)
  startDue()
  assert.deepEqual(calls.map(c => [c[0][0], c[1].slot]), [["start", "a1"]], "only a scheduled one that's due (not later, not over, not a conflict)")
  assert.deepEqual(calls[0][1], { slot: "a1", url: ch.url, place: { volume: "uuid:x", mount: "/m", rel: "R" }, keepFree: 5 * D.GB, quality: 720 },
                   "its channel's address looked up now, and the place, on stdin")
  startDue()
  assert.equal(calls.length, 1, "while it's being started: not asked twice")
  ck.pending({ ok: true })
  assert.deepEqual(ck.claiming, {}, "then free to be asked again (the helper says it's started)")
  calls.length = 0
  ck.hashMap = {}
  assert.equal(ck.channelByHash({ hash: h, name: "Food" }, "src:abcdefabcdef"), ch, "its address changed (a playlist that turns its links): by its name, same provider")
  assert.equal(ck.channelByHash({ hash: h, name: "Food" }, "src:000000000000"), null, "not another provider's channel of that name")
  const stopped = []
  ck.settings = { on: false }
  ck.stop = id => stopped.push(id)
  ck.claim(ck.recordings[0])
  ck.pending({ ok: true, id: "a1" })
  assert.deepEqual(stopped, ["a1"], "turned off while it was starting: stopped at once")
  ck.settings = { on: true }
  calls.length = 0
  ck.claim({ id: "a5", channel: { hash: "9".repeat(64), name: "Gone" } })
  assert.deepEqual(calls.pop()[1], { slot: "a5", gone: true }, "its channel gone: the helper's told (it fails, saying why)")

  // a series' episodes scheduled as the listings come
  const sent = []
  const us = { loaded: true, settings: { on: true, padding: 1 }, rules: [{ id: "1111222233334444", channel: { hash: h, name: "Food" }, title: "Bake Off", private: true }],
               recordings: [], listings: { shows: { [ch.url]: [[later.start, later.end, later.title, later.desc, "", later.sub, later.ep]] } }, chanFor: () => ch,
               channelByHash: () => ch, call: (args, input) => sent.push([args, JSON.parse(input)]) }
  us.sendSeries = (sl, from, more) => fn("sendSeries", ["dvr", "slots", "from", "more", "Dvr", "seriesRetry"])(us, sl, from, more, D, { restart() {} })
  us.seriesPassed = {}
  fn("updateSeries", ["dvr", "guide", "Dvr"])(us, { channels: [ch] }, D)
  assert.deepEqual([sent[0][0], sent[0][1].slots.map(x => [x.rule, x.private, x.title])], [["schedule"], [["1111222233334444", true, "Bake Off"]]],
                   "each new episode scheduled, with its series and its lock")
  sent.length = 0
  us.seriesBusy = false
  us.recordings = [{ channel: { hash: h }, title: "Bake Off", ep: "S2E5", sub: "Bread Week", state: "scheduled" }]
  fn("updateSeries", ["dvr", "guide", "Dvr"])(us, { channels: [ch] }, D)
  assert.deepEqual(sent, [], "one scheduled already: nothing sent")

  // the pass makes only what it sends, however big the listings
  let reads = 0
  const hugeList = new Proxy(Array.from({ length: 100000 }, (_, i) => [t + 600 + i * 60, t + 960 + i * 60, "News", "", "", "", "E" + i]),
                             { get: (o, k) => { if (typeof k === "string" && /^\d+$/.test(k)) reads++; return o[k] } })
  const pass = D.seriesPass([{ rule: { id: "r", title: "News", channel: { hash: "h" } }, list: hugeList }, { rule: { id: "q", title: "Film", channel: { hash: "q" } }, list: [[t + 700, t + 9000, "Film", "", "", "", ""]] }],
                            [], t, 40 * 3600 * 100, {}, 2000)
  assert.deepEqual([pass.picks.length, pass.more, pass.picks[1].rule.id], [2000, true, "q"], "2,000 picked, more left, the quiet series' in turn")
  assert.ok(reads <= 2002, "only as far through the listings as was picked (" + reads + " read of 100,000)")
  assert.deepEqual(D.seriesPass([{ rule: { id: "r", title: "News", channel: { hash: "h" } }, list: [[t + 600, t + 960, "News", "", "", "", "E1"], [t + 960, t + 1320, "News", "", "", "", "E1"]] }],
                                [], t, 3600, { "r|ep:news|e1": true }, 10).picks, [], "an episode passed by this session isn't picked again")

  // the 12 hours from when it began (a scheduled one started at its time), not when it was scheduled
  const late = D.stopChoices({ created: t - 48 * 3600, start: t - 600, end: t + 600 }, 0, t, () => "x")
  assert.equal(late[late.length - 1].end, t - 600 + 12 * 3600, "up to 12 hours from when it began")

  // a playlist turned a recording's channel link: told once, while it's on its way
  const fl = []
  const fq = { active: [{ id: "run", kind: "iptv", provider: "src:abcdefabcdef", channel: { hash: "old-hash", name: "Food" } }], following: {},
               channelByHash: () => ch, call: (args, input, done) => { fl.push([args[0], JSON.parse(input)]); fq.flDone = done }, refresh() {} }
  fn("followLinks", ["dvr", "Dvr"])(fq, D)
  fn("followLinks", ["dvr", "Dvr"])(fq, D)
  assert.deepEqual(fl, [["follow", { id: "run", url: ch.url }]], "its channel at another address now: the recording told, once")
  fq.flDone({ ok: true })
  assert.deepEqual(fq.following, {}, "then free again")
  fq.active[0].channel.hash = D.hashOf(ch.url)
  fn("followLinks", ["dvr", "Dvr"])(fq, D)
  assert.equal(fl.length, 1, "at the address it already has: nothing")

  // and the product runs it for a plain Record now: the refresh timer (on whenever one records) follows each refresh with it
  const pollSrc = dvrQml.match(/Timer \{\n    interval: dvr\.anyActive \|\| dvr\.busy[\s\S]*?\n  \}/)[0]
  assert.match(pollSrc, /running: dvr\.loaded && \(dvr\.anyActive \|\|/, "on whenever one records, nothing scheduled or no series needed")
  const fl2 = []
  const fp = { active: [{ id: "plain", kind: "iptv", provider: "src:abcdefabcdef", channel: { hash: "old-hash", name: "Food" } }], anyActive: true, hasWaiting: false, rules: [],
               following: {}, channelByHash: () => ch, call: (args, input) => fl2.push([args[0], JSON.parse(input).url]), checkPlace() {} }
  fp.followLinks = () => fn("followLinks", ["dvr", "Dvr"])(fp, D)
  fp.refresh = then => { if (then) then() }
  new Function("dvr", pollSrc.match(/onTriggered: \{([\s\S]*?)\}\n/)[1])(fp)
  assert.deepEqual(fl2, [["follow", ch.url]], "a plain Record now, its channel's link turned: followed")
  assert.ok(!block(dvrQml, "function startDue() {").includes("followLinks"), "one path, so no doubled calls")

  // a running recording found under the channel's new address (its provider and name)
  const oc = { anyActive: true, active: [{ id: "run", kind: "iptv", provider: "src:abcdefabcdef", channel: { hash: "old-hash", name: "Food" } }] }
  assert.equal(fn("onChannel", ["dvr", "Dvr", "ch"])(oc, D, ch).id, "run", "its address turned: still the one recording that channel")
  assert.equal(fn("onChannel", ["dvr", "Dvr", "ch"])(oc, D, { ...ch, src: "000000000000" }), null, "not another provider's channel of that name")

  // the cells' marks
  const mk = { recordings: [{ kind: "iptv", state: "scheduled", show: { start: t + 3600, end: t + 5400 }, start: t + 3540, end: t + 5520, channel: { hash: h } },
                            { kind: "iptv", state: "recording", started: t - 600, end: t + 600, channel: { hash: h } }], channelOf: () => ch }
  mk.marks = new Function("dvr", "recordings", "Dvr", block(dvrQml, "readonly property var marks: {").replace(/\breturn m\b/, "return m"))(mk, mk.recordings, D)
  const markFor = (c, sh) => fn("markFor", ["dvr", "ch", "show"])(mk, c, sh)
  assert.deepEqual([markFor(ch, { start: t + 3600, end: t + 5400 }), markFor(ch, { start: t - 1800, end: t + 60 }), markFor(ch, { start: t + 7200, end: t + 9000 })],
                   ["scheduled", "recording", ""], "a cell says Scheduled, Recording, or nothing")
  assert.deepEqual([markFor(ch, { start: t - 3000, end: t - 540 }), markFor(ch, { start: t + 480, end: t + 3600 })], ["", ""],
                   "the shows either side, only in its padding (a minute before, two after): not Recording")
  // a YouTube live stream recording: its cell says Recording too; a video being saved, or a YouTube one that's
  // over, doesn't
  const yt = { recordings: [{ kind: "youtube-live", state: "recording", started: t - 600, end: t + 3000, channel: { hash: h } },
                            { kind: "youtube-video", state: "recording", started: t - 600, end: 0, channel: { hash: "v" } },
                            { kind: "youtube-live", state: "done", started: t - 9000, end: t - 6000, channel: { hash: "d" } }], channelOf: r => r.channel.hash === h ? ch : { url: "other-" + r.channel.hash } }
  yt.marks = new Function("dvr", "recordings", "Dvr", block(dvrQml, "readonly property var marks: {").replace(/\breturn m\b/, "return m"))(yt, yt.recordings, D)
  assert.deepEqual(Object.keys(yt.marks), [ch.url], "only the live stream recording now")
  assert.equal(fn("markFor", ["dvr", "ch", "show"])(yt, ch, { live: true, start: t - 7200, end: t + 7200 }), "recording", "the LIVE block says Recording")
  const short = { recordings: [{ kind: "youtube-live", state: "recording", started: t - 30, end: t + 150, channel: { hash: h } }], channelOf: () => ch }
  short.marks = new Function("dvr", "recordings", "Dvr", block(dvrQml, "readonly property var marks: {").replace(/\breturn m\b/, "return m"))(short, short.recordings, D)
  assert.equal(fn("markFor", ["dvr", "ch", "show"])(short, ch, { live: true, start: t - 7200, end: t + 7200 }), "recording", "a short one too (three minutes): the LIVE block says Recording")
  assert.equal(fn("markFor", ["dvr", "ch", "show"])(short, ch, { start: t - 1800, end: t + 1800 }), "", "a listed show keeps the five-minute rule")
  // and I or Space on what's on now finds it (Stop recording), not on a later one; IPTV as before
  const fs = (chan, show, onCh) => new Function("dvr", "guide", "Dvr", "row", "show", block(dvrQml, "function forShow(row, show) {"))(
    { recordings: [], onChannel: () => onCh }, { channels: [chan] }, D, 0, show)
  const running = { id: "y1", kind: "youtube-live", state: "recording" }
  assert.equal(fs({ kind: "youtube", url: "yt" }, { live: true, start: t - 7200, end: t + 7200 }, running), running, "a YouTube channel recording: the show on now")
  assert.equal(fs({ kind: "youtube", url: "yt" }, { start: t + 600, end: t + 1800 }, running), null, "not a later show of it")
  assert.equal(fs({ kind: "youtube", url: "yt" }, { live: true, start: t - 7200, end: t + 7200 }, null), null, "nothing recording: nothing")
  assert.equal(fs({ kind: "iptv", url: "x" }, { start: t - 60, end: t + 600 }, running), null, "IPTV goes by its own recordings, as before")

  // turning Recordings off: the running ones stop, the scheduled ones go (not cancelled: a series' come back)
  const off = []
  const to = { active: [{ id: "r1" }], recordings: [{ id: "r1", state: "recording" }, { id: "s1", state: "scheduled" }, { id: "s2", state: "conflict" }, { id: "d1", state: "done" }],
               stop: id => off.push(["stop", id]), call: (args) => off.push(args), set: c => off.push(["set", c.on]), refresh() {} }
  to.hasWaiting = true
  fn("turnOff", ["dvr", "Dvr"])(to, D)
  assert.deepEqual(off, [["stop", "r1"], ["clear"], ["set", false]], "the scheduled ones off the list in one go (not a helper each)")

  // Record every episode on the show about to start: that show, as the series'
  const rec2 = []
  const rs = { settings: { on: true }, chanFor: () => ch, onChannel: () => null, record: (...a) => rec2.push(a), refresh() {},
               call: (args, input, done) => done({ ok: true, id: "5555666677778888" }) }
  const soon = { epg: true, title: "Bake Off", ep: "S2E8", start: t + 40, end: t + 1840 }
  fn("recordSeries", ["dvr", "guide", "Dvr", "row", "show", "done"])(rs, { channels: [ch], askToWatch: () => false, lockProtects: () => false }, D, 0, soon, null)
  assert.deepEqual(rec2.map(a => [a[0], a[3], a[4]]), [[0, soon, "5555666677778888"]], "the show picked (not the one before it), with its series")
  const tags = [], order = []
  let tagDone = null
  rs.settings.padding = 1
  Object.assign(rs, { onChannel: () => ({ id: "g1" }), refresh: () => order.push("refresh"),
                      call: (args, input, done) => { if (args[0] === "tag") { tags.push(JSON.parse(input)); tagDone = done } else done({ ok: true, id: "5555666677778888" }) } })
  rec2.length = 0
  const seriesDone = []
  fn("recordSeries", ["dvr", "guide", "Dvr", "row", "show", "done"])(rs, { channels: [ch], askToWatch: () => false, lockProtects: () => false }, D, 0, soon, r => seriesDone.push(r))
  assert.deepEqual([rec2.length, tags.map(x => [x.id, x.rule, x.ep, x.late, x.url]), order, seriesDone.length], [0, [["g1", "5555666677778888", "S2E8", 120, ch.url]], [], 0],
                   "already recording that channel: joined to that recording (not a second one), nothing said before it's in")
  tagDone({ ok: true, id: "g1", end: t + 1960 })
  assert.deepEqual([order, seriesDone.length, rec2.length], [["refresh"], 1, 0], "then the series is looked at, and it's said")
  order.length = 0
  fn("recordSeries", ["dvr", "guide", "Dvr", "row", "show", "done"])(rs, { channels: [ch], askToWatch: () => false, lockProtects: () => false }, D, 0, soon, null)
  tagDone({ ok: false, error: "ended" })
  assert.deepEqual(rec2.map(a => [a[3], a[4]]), [[soon, "5555666677778888"]], "that recording ended meanwhile: the show recorded itself")
  rec2.length = 0
  order.length = 0
  fn("recordSeries", ["dvr", "guide", "Dvr", "row", "show", "done"])(rs, { channels: [ch], askToWatch: () => false, lockProtects: () => false }, D, 0, soon, null)
  tagDone({ ok: true, id: "g1", end: t + 600, continued: "cccccccccccccccc" })
  assert.deepEqual([rec2.length, order], [0, ["refresh"]], "past its 12 hours: a continuation holds it (nothing recorded twice)")

  // the limit, one write at a time, the newest last
  const lim = []
  const lm = { settings: { atOnce: 2 }, limitBusy: false, refresh() {}, call: (args, input, done) => lim.push({ n: args[1], done }) }
  lm.sayLimit = () => new Function("dvr", "limitRetry", block(dvrQml, "function sayLimit() {"))(lm, { restart() {} })
  for (const n of [3, 4, 1]) { lm.settings.atOnce = n; lm.sayLimit() }
  assert.deepEqual(lim.map(x => x.n), ["3"], "one write at a time")
  lim[0].done({ ok: true, atOnce: 3 })
  assert.deepEqual(lim.map(x => x.n), ["3", "1"], "then the newest, not each in between")
  lim[1].done({ ok: true, atOnce: 1 })
  assert.equal(lm.limitBusy, false)
  const retried = []
  const lf = { settings: { atOnce: 1 }, limitBusy: false, refresh() {}, call: (args, input, done) => done({ ok: false, error: "helper" }) }
  new Function("dvr", "limitRetry", block(dvrQml, "function sayLimit() {"))(lf, { restart: () => retried.push(true) })
  assert.deepEqual([lf.limitBusy, retried.length], [true, 1], "not in: still on its way (the scheduled ones wait), tried again")
  new Function("dvr", "limitRetry", block(dvrQml, "function sayLimit() {"))({ settings: { atOnce: 3 }, limitBusy: false, refresh() {}, call: (a, i, done) => done({ ok: true, atOnce: 2 }) },
                                                                        { restart: () => retried.push(true) })
  assert.equal(retried.length, 2, "an answer for another number doesn't count")
  const gated = { followLinks() {}, limitBusy: true, recordings: [{ id: "z", state: "scheduled", start: t - 5, end: t + 600 }], claiming: {}, claim: () => assert.fail("not while the limit's on its way") }
  fn("startDue", ["dvr"])(gated)

  // more than 100 episodes: the next batch once the first is in
  const batches = []
  const many = { loaded: true, settings: { on: true, padding: 1 }, recordings: [],
                 listings: { shows: new Proxy({}, { get: (o, url) => typeof url === "string" ? [[t + 600, t + 1200, "Show " + url, "", "", "", ""]] : undefined }) },
                 chanFor: r => ({ kind: "iptv", name: "C" + r, url: "http://p/" + r, number: r }), channelByHash: c => ({ kind: "iptv", url: c.hash }),
                 rules: Array.from({ length: 101 }, (_, i) => ({ id: "r" + i, title: "Show " + i, channel: { hash: String(i) } })),
                 refresh(then) { if (then) then() } }
  const gch = { channels: Array.from({ length: 101 }, (_, i) => ({ kind: "iptv", url: String(i) })) }
  gch.channels.indexOf = function(c) { return Number(c.url) }
  many.call = (args, input, done) => { const sl = JSON.parse(input).slots; batches.push(sl.length); many.recordings = many.recordings.concat(sl.map(x => ({ channel: x.channel, rule: x.rule, ids: ["at:" + x.showStart], state: "scheduled" })))
                                       done({ ok: true, slots: sl.map((x, i) => ({ ok: true, id: "n" + batches.length + "_" + i })) }) }
  many.updateSeries = () => fn("updateSeries", ["dvr", "guide", "Dvr"])(many, gch, D)
  many.seriesPassed = {}
  many.sendSeries = (sl, from, more) => fn("sendSeries", ["dvr", "slots", "from", "more", "Dvr", "seriesRetry"])(many, sl, from, more, D, many.retry || { restart() {} })
  many.updateSeries()
  assert.deepEqual(batches, [100, 1], "101 episodes: two batches, the second once the first is in")
  batches.length = 0
  many.recordings = []
  many.call = (args, input, done) => { const sl = JSON.parse(input).slots; batches.push(sl.length)
                                       done({ ok: true, slots: sl.map(() => batches.length === 1 ? { ok: true, skipped: true } : { ok: true, id: "x" }) }) }
  many.updateSeries()
  assert.deepEqual(batches, [100, 1], "the first 100 all cancelled before (skipped): the 101st is still sent")
  // the list full: not passed by for good, tried again (once recordings are deleted it fits)
  batches.length = 0
  many.recordings = []
  many.seriesPassed = {}
  let fullOnce = true
  const fullRetry = []
  many.call = (args, input, done) => { const sl = JSON.parse(input).slots; batches.push(sl.length)
                                       done({ ok: true, slots: sl.map((x, i) => fullOnce && batches.length === 1 && i === 0 ? { ok: false, error: "full" } : { ok: true, skipped: true }) }) }
  const sendWithFull = (sl, from, more) => fn("sendSeries", ["dvr", "slots", "from", "more", "Dvr", "seriesRetry", "seriesFullRetry"])(many, sl, from, more, D, { restart() {} }, { restart: () => fullRetry.push(true) })
  many.sendSeries = sendWithFull
  many.updateSeries()
  assert.equal(fullRetry.length, 1, "the list full: tried again in a while")
  fullOnce = false
  batches.length = 0
  many.updateSeries()
  assert.deepEqual(batches, [1], "the one refused for the list being full is sent again; the ones passed by aren't")

  // past 2,000: the rest sent too, without another nudge; a busy series doesn't keep the others waiting
  const big = { loaded: true, settings: { on: true, padding: 1 }, recordings: [], seriesPassed: {}, refresh(then) { if (then) then() },
                rules: [{ id: "chatty", title: "News", channel: { hash: "0" } }, { id: "quiet", title: "Film", channel: { hash: "1" } }],
                chanFor: r => ({ kind: "iptv", name: "C" + r, url: String(r), number: r }), channelByHash: c => ({ kind: "iptv", url: c.hash }),
                listings: { shows: { "0": Array.from({ length: 2100 }, (_, i) => [t + 600 + i * 60, t + 960 + i * 60, "News", "", "", "", "E" + i]),
                                     "1": [[t + 600, t + 6000, "Film", "", "", "", ""]] } } }
  const g2 = { channels: [{ kind: "iptv", url: "0" }, { kind: "iptv", url: "1" }] }
  g2.channels.indexOf = c => Number(c.url)
  const sentBig = []
  let failOnce = 2
  big.retry = { restart() { big.retrying = true } }
  big.call = (args, input, done) => { const sl = JSON.parse(input).slots; sentBig.push(sl)
    if (--failOnce === 0) { done({ ok: false, error: "helper" }); return }
    big.recordings = big.recordings.concat(sl.map(x => ({ channel: x.channel, title: x.title, ep: x.ep, rule: x.rule, state: "scheduled" })))
    done({ ok: true, slots: sl.map((x, i) => ({ ok: true, id: "i" + sentBig.length + "_" + i })) }) }
  big.updateSeries = () => fn("updateSeries", ["dvr", "guide", "Dvr"])(big, g2, D)
  big.sendSeries = (sl, from, more) => fn("sendSeries", ["dvr", "slots", "from", "more", "Dvr", "seriesRetry"])(big, sl, from, more, D, big.retry)
  big.updateSeries()
  assert.ok(sentBig[0].some(x => x.rule === "quiet"), "the quiet series' episode in the first batch, not after 2,000 of the busy one's")
  assert.deepEqual([sentBig.length, big.retrying, !!big.seriesPending], [2, true, true], "the second batch failed: kept, and tried again in a while")
  const failed = sentBig[1]
  const p = big.seriesPending; big.seriesPending = null; big.sendSeries(p.slots, p.from, p.more)
  assert.deepEqual(sentBig[2], failed, "that same batch again, before any later one")
  const sentAll = new Set(sentBig.slice(2).concat([sentBig[0]]).flat().map(x => x.rule + x.ep + x.title))
  assert.equal(sentAll.size, 2101, "every one of the 2,101 sent, past the first 2,000, without another nudge")

  // the list given only when it changed
  const lists = [{ ok: true, recordings: [{ id: "x", state: "done" }], rules: [] }]
  const rf = { listing: false, again: false, thens: [], listText: "", rulesText: "[]", stopping: {}, allowed: {}, recordings: [], rules: [],
               call: (args, input, done) => done(lists[0]), recordingFrom: () => false }
  const refresh = then => fn("refresh", ["dvr", "Dvr", "then", "call"])(rf, D, then, rf.call)
  refresh()
  const first = rf.recordings
  let after = 0
  refresh(() => after++)
  assert.equal(rf.recordings, first, "the same list again: not given again (nothing built from it is made again)")
  assert.equal(after, 1, "what waited for it runs")
  lists[0] = { ok: true, recordings: [{ id: "x", state: "done" }, { id: "y", state: "scheduled" }], rules: [{ id: "r" }] }
  refresh()
  assert.deepEqual([rf.recordings.length, rf.rules.length], [2, 1], "a changed one is")

  // Guide.qml: a show's choices
  const openSrc = block(guideSrc, "function openShowChoices() {")
  const choicesSrc = guideSrc.match(/readonly property var showChoices: \{([\s\S]*?)\n  \}\n/)[1]
  const did = []
  const ruleOn = { id: "9999888877776666", channel: { hash: h }, title: "Bake Off" }
  const gd = { settings: { on: true }, rules: [], stopping: {}, ruleOf: r => r && r.rule === ruleOn.id ? ruleOn : null, offer: () => null,
               laterOffer: (r, sh) => ({ label: "Record", note: "" }), forShow: () => null,
               schedule: (r, sh) => did.push("schedule " + sh.title), recordSeries: (r, sh) => did.push("series " + sh.title),
               cancel: id => did.push("cancel " + id), stopSeries: id => did.push("stopSeries " + id), stop: id => did.push("stop " + id),
               ruleFor: (c, title) => gd.rules.find(x => D.fold(x.title) === D.fold(title)) || null }
  const groot = { row: 0, channels: [ch], screen: "guide", airs: () => true, dialog: "", cursorAt: t + 3600, selected: later,
                  watch: () => {}, closeShowChoices() { groot.showChoice = null }, askToWatch: () => false }
  const lst = { has: () => true, at: () => later }
  const openC = () => { new Function("root", "dvr", "keys", "listings", "DvrRules", openSrc)(groot, gd, { forceActiveFocus() {} }, lst, D)
                        groot.showChoices = new Function("showChoice", "DvrRules", "dvr", choicesSrc)(groot.showChoice, D, gd) }
  const actC = key => { groot.showCursor = groot.showChoices.findIndex(c => c.key === key)
                        new Function("root", "dvr", "i", "listings", block(guideSrc, "function showChoiceAct(i) {"))(groot, gd, undefined, lst) }
  openC()
  assert.deepEqual(groot.showChoices.map(c => c.key), ["watch", "schedule", "series"], "a later show: Watch, Record, Record every episode")
  actC("schedule")
  openC(); actC("series")
  assert.deepEqual(did.splice(0), ["schedule Bake Off", "series Bake Off"], "Record schedules it; Record every episode makes its series")
  gd.forShow = () => ({ id: "s1", state: "scheduled", rule: ruleOn.id })
  openC()
  assert.deepEqual(groot.showChoices.map(c => c.key), ["watch", "cancel", "stopSeries"], "scheduled, of a series: Cancel recording, Stop recording this series")
  actC("cancel"); openC(); actC("stopSeries")
  assert.deepEqual(did.splice(0), ["cancel s1", "stopSeries " + ruleOn.id])
  gd.forShow = () => ({ id: "r9", state: "recording" })
  openC()
  assert.deepEqual(groot.showChoices.map(c => c.key), ["watch", "stopRec"], "recording it now: Stop recording")
  gd.forShow = () => null
  gd.rules = [ruleOn]
  openC()
  assert.deepEqual(groot.showChoices.map(c => c.key), ["watch", "schedule", "stopSeries"], "an episode of a series not scheduled (yet): its series can be stopped")
  // one that won't record: its row says so briefly, the box's text names the others
  gd.laterOffer = () => ({ label: "Record", note: "Conflict: too many recordings at this time", why: "Already scheduled: Film, Quiz" })
  Object.assign(groot, { numbers: ["107"], clock: () => "9:00" })
  openC()
  assert.equal(groot.showChoices.find(c => c.key === "schedule").note, "Conflict: too many recordings at this time", "the row: short")
  const choiceText = () => new Function("root", "dvr", "DvrRules", block(guideSrc, "function showChoiceText() {"))(groot, gd, D)
  assert.match(choiceText(), /\n\nAlready scheduled: Film, Quiz$/, "the box: the others named")
  gd.laterOffer = () => ({ label: "Record", note: "" })
  openC()
  assert.doesNotMatch(choiceText(), /Already scheduled/, "nothing in the way: nothing said")

  // its card's choices in Recordings
  const actsSrc = guideSrc.match(/readonly property var recActions: \{([\s\S]*?)\n  \}\n/)[1]
  const acts = (rec, rule) => new Function("libDetailRec", "recArmed", "DvrRules", "root", "dvr", actsSrc)(rec, "", D, { libResumeAt: () => 0, recordingCard: () => ({ id: "x" }) },
                                                                                                          { stopping: {}, ruleOf: () => rule || null })
  assert.deepEqual(acts({ id: "s", state: "scheduled", channel: { name: "Food" } }).map(a => a.label), ["Cancel recording", "Watch Food now"], "Upcoming: cancel it, or watch its channel")
  assert.deepEqual(acts({ id: "s", state: "conflict", channel: { name: "Food" } }, ruleOn).map(a => a.key), ["cancel", "stopSeries", "channel"], "a conflict, of a series")
  assert.deepEqual(acts({ id: "m", state: "missed" }).map(a => a.label), ["Take it off the list…"], "Missed: off the list")
  assert.deepEqual(acts({ id: "d", state: "done", present: true, path: "/r/d.ts" }, ruleOn).map(a => a.key), ["play", "stopSeries", "delete"], "a series' recording: its series can be stopped")
  // Stop recording this series there: one still to come goes with it, so its box closes (as Cancel's); a recorded one stays
  const recAct = new Function("root", "dvr", "DvrRules", "i", block(guideSrc, "function recAct(i) {"))
  for (const [rec, closes] of [[{ id: "s", state: "scheduled" }, true], [{ id: "k", state: "conflict" }, true], [{ id: "d", state: "done", present: true, path: "/r/d.ts" }, false]]) {
    const stopped = []
    const rr = { recActions: [{ key: "stopSeries" }], libDetailRec: rec, libEpisode: 0, recArmed: "", libDetail: { rec } }
    recAct(rr, { ruleOf: () => ruleOn, stopSeries: id => stopped.push(id) }, D)
    assert.deepEqual([stopped, rr.libDetail === null], [[ruleOn.id], closes], rec.state + ": the series stopped, " + (closes ? "its box closed" : "its box kept"))
  }

  // the agents' commands
  const cfn = (opener, params) => new Function("guide", "commands", "DvrRules", ...params, block(commandsSrc, opener))
  const lockedCh = { kind: "iptv", name: "Secret", url: "http://p/s.ts" }
  const plain = { kind: "youtube", name: "Kurz", url: "https://y/@k" }
  const asked = []
  const ad = { settings: { on: true }, rules: [{ id: "9999888877776666", title: "Bake Off", channel: { name: "Food", number: 107 } }],
               recordings: [], byId: { s1: { id: "s1", state: "scheduled", rule: "" }, r1: { id: "r1", state: "recording" }, d1: { id: "d1", state: "done" } },
               laterOffer: () => ({ label: "Record", note: "" }), schedule: (r, sh) => { asked.push(["schedule", r, sh.title]); return "ok" },
               recordSeries: (r, sh) => { asked.push(["series", r, sh.title]); return "ok" }, cancel: id => asked.push(["cancel", id]), stopSeries: id => asked.push(["stopSeries", id]), ruleOf: () => null }
  const ag = { recorder: ad, numbers: [107, 108, 109], channels: [ch, lockedCh, plain], channelLock: { blocks: c => c === lockedCh },
               listingsHave: c => c.kind === "iptv", showListed: (c, at, after) => at ? (at < t + 60 ? { epg: true, title: "On now", start: t - 60, end: t + 600 } : { epg: true, title: "At " + at, start: at, end: at + 1800 })
                                                                               : { epg: true, title: "Next", start: t + 600, end: t + 2400 } }
  const ac = { okReply: o => ({ ok: true, ...o }), failReply: e => ({ ok: false, error: e }), recordingsOff: "off", channelInfo: r => ({ number: ag.numbers[r] }) }
  for (const [name, params] of Object.entries({ rowsFor: ["numbers"], laterShow: ["number", "when", "nowToo"], recordingById: ["id"] })) {
    const f = cfn("function " + name + "(", params)
    ac[name] = (...a) => f(ag, ac, D, ...a)
  }
  const ipc = (name, params) => { const f = cfn("function " + name + "(" + params.map(p => p + ": string").join(", ") + "): string {", params); return (...a) => f(ag, ac, D, ...a) }
  const recordShow = ipc("recordShow", ["number", "when"]), recordSeries = ipc("recordSeries", ["number", "when"]), cancelRec = ipc("cancelRecording", ["id"])
  assert.match(recordShow("108", "next").error, /locked: only the user/, "not a locked channel")
  assert.match(recordShow("109", "next").error, /no listings/, "only a channel with listings")
  assert.match(recordShow("107", "soon").error, /clock time/, "a time it can read")
  assert.equal(recordShow("107", "next").title, "Next")
  const hhmm = new Date((t + 7200) * 1000)
  const at = String(hhmm.getHours()).padStart(2, "0") + ":" + String(hhmm.getMinutes()).padStart(2, "0")
  assert.match(recordShow("107", at).title, /^At /, "a clock time: the show on then")
  assert.match(recordShow("107", "now").error, /clock time \(21:30\), a day and time \(2026-10-21 21:30\), a show's start from shows, or next/, "now isn't for recordShow (record does that)")
  assert.equal(recordSeries("107", "now").title, "On now", "recordSeries now: the show on now")
  assert.deepEqual(asked.splice(0).map(a => a[0]), ["schedule", "schedule", "series"])
  ad.settings.on = false
  assert.equal(recordShow("107", "next").error, "off", "Recordings off: refused")
  ad.settings.on = true
  assert.equal(cancelRec("9999888877776666").series, "9999888877776666", "a series by its id: stopped")
  assert.equal(cancelRec("s1").id, "s1")
  assert.match(cancelRec("r1").error, /stopRecording stops it/, "a running one: stopRecording")
  assert.match(cancelRec("d1").error, /isn't scheduled/)
  assert.deepEqual(asked.splice(0), [["stopSeries", "9999888877776666"], ["cancel", "s1"]])
  const sinfo = cfn("function seriesInfo(", ["rule"])
  assert.deepEqual(sinfo(ag, ac, D, { id: "x", title: "Secret show", private: true, channel: { name: "Secret" } }), { id: "x", title: "Locked series", locked: true, channel: undefined },
                   "a locked channel's series names nothing")
}

// ---- the strip's question about Recordings: once, after updates ----
{
  const asksSrc = guideSrc.match(/readonly property string stripAsks: ([\s\S]*?: "")\n/)[1]
  const answerSrc = block(guideSrc, "function stripAnswer(yes) {")
  const loadSrc = guideSrc.match(/root\.recAsked = (.*saved\.firstStart.*)\n/)[1]
  const setSrc = block(dvrQml, "function set(changes) {")
  const world = (rec, upd) => {
    const updatesItem = Object.assign({ asked: true, strip: "", turnOn() { this.asked = true; this.strip = "Update notifications are on." }, dismiss() { this.asked = true } }, upd)
    const root = { recAsked: false, saves: 0, stripAnsweredAt: 0, saveSettings() { this.saves++ } }
    const dvr = { settings: D.defaults(), placeInfo: null, checkPlace() {}, sayLimit() {} }
    dvr.set = changes => new Function("dvr", "Dvr", "guide", "changes", setSrc)(dvr, D, root, changes)
    Object.assign(dvr.settings, rec)
    Object.defineProperty(root, "stripAsks", { get: () => new Function("root", "updatesItem", "dvr", "return " + asksSrc)(root, updatesItem, dvr) })
    const answer = yes => new Function("root", "updatesItem", "dvr", "yes", answerSrc)(root, updatesItem, dvr, yes)
    return { root, updatesItem, dvr, answer }
  }
  const realNow = Date.now
  let clock = 1e12
  Date.now = () => clock
  // a first start: updates first, then Recordings once the look's result has gone
  const w = world({}, { asked: false })
  assert.equal(w.root.stripAsks, "updates")
  w.answer(true)
  assert.equal(w.root.recAsked, false, "Y on updates leaves Recordings to ask")
  assert.equal(w.root.stripAsks, "", "not while the updates look's result shows")
  w.updatesItem.strip = ""
  assert.equal(w.root.stripAsks, "recordings")
  clock += 5000
  w.answer(true)
  assert.equal(w.dvr.settings.on, true, "Y turns Recordings on")
  assert.equal(w.root.recAsked, true)
  assert.ok(w.root.saves >= 1, "and it's saved")
  assert.equal(w.root.stripAsks, "")
  // N: away for good, Recordings still off
  const n = world({})
  assert.equal(n.root.stripAsks, "recordings")
  n.answer(false)
  assert.equal(n.dvr.settings.on, false, "N leaves Recordings off")
  assert.equal(n.root.recAsked, true)
  assert.equal(n.root.saves, 1)
  assert.equal(n.root.stripAsks, "")
  // on already (Settings, an agent): nothing to ask, and asked from then on
  assert.equal(world({ on: true }).root.stripAsks, "")
  const s = world({})
  s.dvr.set({ on: true })
  assert.equal(s.root.recAsked, true, "turned on anywhere: the strip has nothing to ask")
  s.dvr.set({ on: false })
  assert.equal(s.root.stripAsks, "", "and turned off later, it doesn't come back")
  // loading: an update from before Recordings asks; answered or on doesn't
  const loaded = (saved, on) => new Function("saved", "dvr", "return " + loadSrc)(saved, { settings: { on } })
  assert.equal(loaded({}, false), false, "an update from before Recordings: asked")
  assert.equal(loaded({ firstStart: { demo: true, apps: true } }, false), false)
  assert.equal(loaded({ firstStart: { recordings: true } }, false), true, "answered: not again")
  assert.equal(loaded({}, true), true, "on already: not asked")
  assert.ok(/root\.demoAsked = false\s+root\.appsAsked = false\s+root\.recAsked = false/.test(guideSrc), "a first start asks")
  // N on updates, then its repeat or a second click: Recordings stays asked
  const r = world({}, { asked: false })
  r.answer(false)
  assert.equal(r.root.stripAsks, "recordings", "updates dismissed")
  r.answer(false)
  clock += 400
  r.answer(false)
  assert.equal(r.root.recAsked, false, "the same press or a double click doesn't answer Recordings")
  assert.equal(r.root.stripAsks, "recordings")
  clock += 1000
  r.answer(false)
  assert.equal(r.root.recAsked, true, "a press of its own does")
  Date.now = realNow
  // the keys: Y and N answer the strip's question, a held one once
  const keysSrc = read("GuideKeys.qml")
  const stripKeys = keysSrc.match(/\n    (if \(!guide\.watching && guide\.stripAsks !== ""[\s\S]*?\n    \})\n/)[1]
  const press = (key, repeat) => {
    const said = [], event = { isAutoRepeat: repeat, accepted: false }
    const guide = { watching: false, stripAsks: "recordings", screen: "home", managing: false, homeEditing: false, stripAnswer: yes => said.push(yes) }
    new Function("guide", "k", "event", "Qt", stripKeys)(guide, key, event, { Key_Y: 89, Key_N: 78 })
    return { said, accepted: event.accepted }
  }
  assert.deepEqual(press(78, false), { said: [false], accepted: true }, "N: Dismiss")
  assert.deepEqual(press(89, false), { said: [true], accepted: true }, "Y: Turn on")
  assert.deepEqual(press(78, true), { said: [], accepted: true }, "a held key's repeats: taken, not answered")
  assert.ok(guideSrc.includes('"New: Recordings. Record shows to watch later. Turn on here, or anytime in Settings → Recordings."'))
  assert.match(read("ui/AskStrip.qml"), /message: guide\.stripQuestion \|\| updates\.strip\n\n  visible: message !== "" && guide\.stripPlace\n/, "the strip says the question the phone does, where it shows")
  assert.match(guideSrc, /readonly property bool stripPlace: opened && !watching && dialog === "" && \(screen === "home" \|\| screen === "guide"\)\n\s+&& !managing && !homeEditing && !railEditing && !appPlaying && !\(multiview && multiview\.active\) && !splashItem\.running\n/,
               "nothing over it: not under Multiview, an app's video or the splash (so the phone can't answer it then)")
}

// ---- M4: the phone (the strip's question, ⋯ while watching, the mini
// player's question, what's recording and paused), the mini player's keys,
// L on a recording; the agents' shows and startOver ----
{
  const remoteCommand = new Function("root", "appViewItem", "nativeSaverItem", "screenSaverItem", "Hyprland", "channelLockItem", "appPanelItem", "appsStore", "cmd", "number", "by",
                                     block(guideSrc, "function remoteCommand(cmd, number, by, digits, extra) {"))
  const you = {}
  const idle = { up: false, settling: false, showing: false, activity() {}, wake() {} }
  const make = extra => {
    const seen = []
    const root = Object.assign({ byUser: you, splash: null, reception: "playing", authBusy: false, dialog: "", appOpening: false, appUp: false,
                                 multiview: { active: false }, pip: false, vod: null, opened: true, watching: false, screen: "home", railOpen: false,
                                 bannerOptions: false, streamAsk: null, stripAsks: "", stripPlace: false, homeEditing: false,
                                 boxShown: () => true, closeDialog: () => seen.push("closeDialog"),
                                 stripAnswer: yes => seen.push("strip " + yes), answerStream: yes => seen.push("stream " + yes),
                                 showPipBanner: () => seen.push("pipBar"), showVodBar: () => seen.push("vodBar"),
                                 openBannerOptions: () => seen.push("banner"), hideBanner: () => seen.push("hide"), openHomePanel: () => seen.push("homePanel"),
                                 openShowChoices: () => seen.push("choices"), pipSurf: d => seen.push("pipSurf " + d), expandPip: () => seen.push("full"),
                                 guidePip: () => seen.push("guide"), seekVod: d => seen.push("seek " + d), togglePause: () => seen.push("pause"), stopVod: () => seen.push("stop") }, extra)
    return { root, seen, press: cmd => remoteCommand(root, { agentOpen: null, settingsOpen: false, signIn: false, editing: false }, idle, idle, { usingLua: false }, { boxUp: false },
                                                     { open: false }, { installing: false, inspecting: false }, cmd, 0, you) }
  }
  // the strip's question: TURN ON and DISMISS, only while it's on the screen
  let m = make({ stripAsks: "recordings", stripPlace: true })
  m.press("yes"); m.press("no")
  assert.deepEqual(m.seen, ["strip true", "strip false"], "the phone answers the strip")
  m = make({ stripAsks: "recordings", stripPlace: false })
  m.press("yes")
  assert.deepEqual(m.seen, [], "not while it isn't showing")
  m = make({ stripAsks: "", stripPlace: true })
  m.press("no")
  assert.deepEqual(m.seen, [], "nor with nothing to ask")
  // ⋯ does what I does
  m = make({ watching: true }); m.press("options")
  assert.deepEqual(m.seen, ["banner"], "full screen: the banner's choices")
  m = make({ watching: true, bannerOptions: true }); m.press("options")
  assert.deepEqual(m.seen, ["hide"], "and again: away")
  m = make({ watching: true, vod: { title: "Film" } }); m.press("options")
  assert.deepEqual(m.seen, ["vodBar"], "a movie: its player bar")
  m = make({ pip: true, opened: false }); m.press("options")
  assert.deepEqual(m.seen, ["pipBar"], "the mini player: its bar")
  m = make({ screen: "home" }); m.press("options")
  assert.deepEqual(m.seen, ["homePanel"], "Home: customize, as before")
  m = make({ screen: "guide" }); m.press("options")
  assert.deepEqual(m.seen, ["choices"], "the guide: a show's choices, as before")
  m = make({ opened: false }); m.press("options")
  assert.deepEqual(m.seen, [], "the guide away: nothing")
  // the mini player's question: OK watches anyway, BACK stays, nothing else answers
  m = make({ pip: true, opened: false, streamAsk: { row: 1 } })
  m.press("ok"); m.press("back"); m.press("up"); m.press("options")
  assert.deepEqual(m.seen, ["stream true", "stream false"], "OK and BACK answer it; ▲ and ⋯ don't")
  m = make({ pip: true, opened: false, streamAsk: { row: 1 }, vod: { title: "Film" } })
  m.press("ok")
  assert.deepEqual(m.seen, ["stream true"], "before a movie's OK")
  m = make({ pip: true, opened: false })
  m.press("ok"); m.press("back")
  assert.deepEqual(m.seen, ["full", "guide"], "not asking: as before")

  // what the phones see: the strip's question while it shows, recording and pause and rewind as the banner says them
  const stateOf = new Function("root", "listings", "channelLockItem", "timeshift", "Schedule", block(guideSrc, "function remoteState() {"))
  const tv = (extra, ts) => stateOf(Object.assign({ reception: "on", onAir: { title: "News", start: 1, end: 2 }, channels: [{ name: "One", category: "" }], tunedRow: 0,
                                                    visibleRows: [], numbers: [101], muted: false, opened: true, screen: "home", pip: false, watching: true, vod: null,
                                                    stripAsks: "", stripPlace: false, stripQuestion: "", recBadge: "", showTitle: t => t }, extra),
                                      {}, { boxUp: false, blocks: () => false }, Object.assign({ active: false, paused: false, atLive: true, chipText: "" }, ts), {})
  assert.equal(tv({}).ask, null)
  assert.deepEqual(tv({ stripAsks: "recordings", stripPlace: true, stripQuestion: "New: Recordings." }).ask, { text: "New: Recordings." })
  assert.equal(tv({ stripAsks: "recordings", stripPlace: false, stripQuestion: "New: Recordings." }).ask, null, "not while the strip isn't showing")
  assert.equal(tv({ recBadge: "● REC until 9:30" }).rec, "● REC until 9:30")
  assert.equal(tv({ recBadge: "● REC until 9:30", reception: "off" }).rec, "", "the TV off: nothing")
  assert.equal(tv({}, { active: true, paused: true, chipText: "0:40 behind live", atLive: false }).pause, "Paused")
  assert.equal(tv({}, { active: true, chipText: "2:30 behind live", atLive: false }).pause, "2:30 behind live")
  assert.equal(tv({}, { active: true, chipText: "Live", atLive: true }).pause, "", "live: nothing more")
  assert.equal(tv({ vod: { title: "Film" } }, { active: true, paused: true }).pause, "", "a movie: its own Paused")
  assert.match(guideSrc, /readonly property string remotePause: timeshift\.active && !vod \? \(timeshift\.paused \? "paused" : timeshift\.atLive \? "live" : "behind " \+ Math\.round\(timeshift\.behind \/ 15000\)\) : ""\n  onRemotePauseChanged: remoteStateTimer\.restart\(\)/,
               "told when it pauses, goes live or moves 15 s; not each second")
  for (const p of ["onRecBadgeChanged", "onStripAsksChanged", "onStripPlaceChanged"]) assert.match(guideSrc, new RegExp("\\n  " + p + ": remoteStateTimer\\.restart\\(\\)\\n"), p)
  assert.match(read("bin/om-pg-remote"), /"code",\n\s+"yes", "no"[,}]/, "the helper lets yes and no through")

  // the mini player's keys while it asks
  const miniSrc = read("ui/MiniPlayer.qml")
  const miniKeys = new Function("guide", "event", "Qt", block(miniSrc, "Keys.onPressed: function(event) {"))
  const K = { Key_Escape: 1, Key_Up: 2, Key_PageUp: 3, Key_Down: 4, Key_PageDown: 5, Key_M: 6, Key_G: 7, Key_Return: 8, Key_Enter: 9, Key_F: 10, Key_I: 11, Key_Space: 12, Key_Y: 13, Key_N: 14, Key_Backspace: 15 }
  const mini = (asking, key) => {
    const seen = []
    const guide = { streamAsk: asking ? { row: 1 } : null, answerStream: y => seen.push("stream " + y), closePip: () => seen.push("close"), expandPip: () => seen.push("full"),
                    pipSurf: d => seen.push("surf " + d), guidePip() {}, showPipBanner() {}, muted: false }
    const event = { key, accepted: false }
    miniKeys(guide, event, K)
    return seen
  }
  assert.deepEqual(mini(true, K.Key_Return), ["stream true"], "Enter: watch anyway")
  assert.deepEqual(mini(true, K.Key_Escape), ["stream false"], "Esc: stay (not closed)")
  assert.deepEqual(mini(false, K.Key_Escape), ["close"], "not asking: Esc closes, as before")
  assert.deepEqual(mini(false, K.Key_Return), ["full"])
  assert.match(miniSrc, /model: guide\.streamAsk \? \[\{ label: "WATCH ANYWAY", act: "streamYes" \}, \{ label: "STAY", act: "streamNo" \}\]/, "its buttons say it")
  assert.match(miniSrc, /text: guide\.streamAsk \? guide\.streamAskLabel : guide\.showTitle\(guide\.nowLabel\(\)\)/)
  assert.match(miniSrc, /text: guide\.streamAsk \? guide\.streamAskNote :/)
  assert.match(guideSrc, /if \(streamAsk\) return \[\{ key: "streamYes", label: streamAskLabel, icon: "", rec: true, note: streamAskNote \}, \{ key: "streamNo", label: "Stay", icon: "" \}\]/, "the banner says the same")

  // L on a recording: nothing (the Recordings tab has no L)
  const toggled = []
  const toggle = new Function("root", "library", block(guideSrc, "function libToggleList() {"))
  toggle({ libDetail: null, libCard: { kind: "recording", entry: { id: "r" } } }, { toggleList: e => toggled.push(e.id) })
  toggle({ libDetail: null, libCard: { kind: "movie", entry: { id: "m" } } }, { toggleList: e => toggled.push(e.id) })
  assert.deepEqual(toggled, ["m"], "a recording isn't put on My List; a movie is")
  // the library's footer: Watch live on one still being made
  const footer = read("ui/LibraryScreen.qml").match(/label: (\["Starting", "Recording", "Saving"\].*? : "Play") \}/)[1]
  const label = card => new Function("guide", "return " + footer)({ libCard: card })
  assert.deepEqual([label({ recState: "Recording" }), label({ recState: "Saving" }), label({ recState: "Done" }), label(null)], ["Watch live", "Watch live", "Play", "Play"])
  assert.equal(D.reasonText("cap"), "", "no reason that's never stored")

  // the agents: shows, a day and time for recordShow, startOver
  const fn = (opener, params) => new Function("guide", "commands", "DvrRules", "Qt", "recordingSoon", "playSoon", ...params, block(commandsSrc, opener))
  const now = Math.floor(Date.now() / 1000)
  const L = {
    "http://p/1.ts": [{ title: "Bake Off", sub: "Bread", ep: "S1E2", start: now + 3600, end: now + 7200 }, { title: "News", start: now - 600, end: now + 1200 }],
    "http://p/2.ts": [{ title: "Bake Off", sub: "Cake", start: now + 1800, end: now + 3600 }],
    "http://p/3.ts": [{ title: "Bake Off", start: now + 600, end: now + 900 }],
  }
  const chans = [{ url: "http://p/1.ts", name: "One", kind: "iptv" }, { url: "http://p/2.ts", name: "Two", kind: "iptv" }, { url: "http://p/3.ts", name: "Secret", kind: "iptv" },
                 { url: "yt", name: "Tube", kind: "youtube" }]
  // kept as Listings keeps them: [start, end, title, desc, category, sub, ep]
  const raw = s => [s.start, s.end, s.title, "", "", s.sub || "", s.ep || ""]
  const g = { channels: chans, numbers: [101, 102, 103, 104], listingsHave: c => !!L[c.url], titlesHidden: c => c.name === "Secret",
              eachListed: (c, from, to, visit) => L[c.url].filter(s => s.end > from && s.start < to).map(raw).forEach(visit),
              listedShow: x => ({ start: x[0], end: x[1], title: x[2], sub: x[5], ep: x[6] }), recMark: (c, s) => s.sub === "Cake" ? "scheduled" : "" }
  const cmds = { okReply: o => ({ ok: true, ...o }), failReply: e => ({ ok: false, error: e }) }
  cmds.rowsFor = n => new Function("guide", "numbers", block(commandsSrc, "function rowsFor(numbers) {"))(g, n)
  const Qt = { formatDateTime: d => d.toISOString().slice(0, 16).replace("T", " ") }
  const shows = (n, w) => fn("function shows(number: string, words: string): string {", ["number", "words"])(g, cmds, D, Qt, null, null, n, w)
  let got = shows("", "bake off")
  assert.deepEqual(got.shows.map(x => [x.number, x.episode || ""]), [[102, "Cake"], [101, "Bread"]], "every channel's, soonest first; a locked channel's left out")
  assert.equal(got.shows[0].recording, "scheduled")
  assert.equal(got.shows[1].episodeNumber, "S1E2")
  assert.equal(got.shows[1].when, Qt.formatDateTime(new Date((now + 3600) * 1000)), "the when recordShow takes")
  got = shows("101", "")
  assert.deepEqual(got.shows.map(x => [x.title, x.onNow]), [["News", true], ["Bake Off", false]], "one channel's, what's on now first")
  assert.equal(shows("", "bread").total, 1, "an episode's title finds it")
  assert.match(shows("103", "").error, /locked/)
  assert.match(shows("104", "").error, /no listings/)
  assert.match(shows("999", "").error, /no channel 999/)
  // a lot of them: every one counted, the soonest 100 kept, in order
  const many = Array.from({ length: 300 }, (_, i) => ({ title: "Bake Off", start: now + (299 - i) * 60, end: now + (300 - i) * 60 }))
  L["http://p/2.ts"] = many
  got = shows("", "bake off")
  assert.equal(got.total, 301)
  assert.equal(got.more, true)
  assert.equal(got.shows.length, 100)
  assert.deepEqual(got.shows.slice(0, 3).map(x => x.start), [now, now + 60, now + 120], "the soonest, in order, though they came last")
  assert.ok(got.shows.every((x, i) => !i || got.shows[i - 1].start <= x.start))
  assert.match(commandsSrc, /if \(kept\.length > 100\) kept\.pop\(\)/, "never more than 100 kept")
  // recordShow and recordSeries: a day and time as shows gives it
  const later = new Function("guide", "commands", "number", "when", "nowToo", block(commandsSrc, "function laterShow(number, when, nowToo) {"))
  const lg = Object.assign({}, g, { channelLock: { blocks: () => false }, showListed: (c, at, after) => at ? L[c.url].find(s => at >= s.start && at < s.end) || null : null })
  const lc = { rowsFor: n => new Function("guide", "numbers", block(commandsSrc, "function rowsFor(numbers) {"))(lg, n) }
  const at = new Date((now + 3700) * 1000)
  const pad = x => String(x).padStart(2, "0")
  const stamp = at.getFullYear() + "-" + pad(at.getMonth() + 1) + "-" + pad(at.getDate()) + " " + pad(at.getHours()) + ":" + pad(at.getMinutes())
  assert.equal(later(lg, lc, "101", stamp, false).show.sub, "Bread", "a day and time")
  assert.equal(later(lg, lc, "101", stamp.replace(" ", "T"), false).show.sub, "Bread", "or with a T")
  assert.match(later(lg, lc, "101", "tomorrow", false).error, /a day and time \(2026-10-21 21:30\)/)
  assert.match(later(lg, lc, "101", "2026-02-31 21:00", false).error, /no such day and time/, "a day that isn't: refused, not moved")
  assert.match(later(lg, lc, "101", "2026-10-21 25:00", false).error, /no such day and time/)
  assert.equal(later(lg, lc, "101", String(now + 3700), false).show.sub, "Bread", "a show's start in seconds")
  // when the clocks change (Los Angeles): tomorrow by the calendar, a skipped time refused, the repeated hour by its start
  {
    const { execFileSync } = await import("node:child_process")
    const probe = `
      const later = new Function("guide", "commands", "number", "when", "nowToo", "Date", ${JSON.stringify(block(commandsSrc, "function laterShow(number, when, nowToo) {"))})
      const RealDate = Date
      const at = new RealDate(2026, 2, 7, 23, 0).getTime()
      class Fake extends RealDate { constructor(...a) { a.length ? super(...a) : super(at) } }
      RealDate.now = () => at
      let asked = 0
      const guide = { channels: [{ kind: "iptv" }], numbers: [101], listingsHave: () => true, channelLock: { blocks: () => false },
                      showListed: (c, t) => (asked = t, { title: "X", start: t, end: t + 3600 }) }
      const commands = { rowsFor: () => [0] }
      const out = {}
      later(guide, commands, "101", "22:00", false, Fake)
      const d = new RealDate(asked * 1000)
      out.tomorrow = [d.getDate(), d.getHours(), d.getMinutes()]
      out.skipped = later(guide, commands, "101", "2026-03-08 02:30", false, Fake).error || ""
      const second = new RealDate(2026, 10, 1, 1, 30).getTime() / 1000 + 3600
      later(guide, commands, "101", String(second), false, Fake)
      out.repeated = asked === second
      console.log(JSON.stringify(out))`
    const out = JSON.parse(execFileSync(process.execPath, ["-e", probe], { env: { ...process.env, TZ: "America/Los_Angeles" } }).toString())
    assert.deepEqual(out.tomorrow, [8, 22, 0], "22:00 tomorrow, by the calendar, though that day is 23 hours")
    assert.match(out.skipped, /no such day and time/, "a time the clocks skip: refused")
    assert.equal(out.repeated, true, "the hour that repeats: by its start")
  }
  const gone = Object.assign({}, lg, { showListed: () => ({ title: "Old", start: now - 7200, end: now - 3600 }) })
  assert.match(later(gone, lc, "101", "2020-01-01 10:00", false).error, /over/, "a show that's over")
  // startOver: a recording or a movie, from the start
  const rec = { id: "aaaaaaaaaaaaaaaa", state: "done", present: true, path: "/r/a.ts" }
  const so = { okReply: cmds.okReply, failReply: cmds.failReply, recordingById: id => id === rec.id ? rec : null, pendingRecording: null, pendingPlay: null, pendingFrom: undefined }
  const sg = { opened: true, recorder: { locked: () => false }, entryFor: id => id === "m1" ? { id: "m1", title: "Film" } : null, videoLockedBy: () => null }
  const restarted = []
  const startOver = id => fn("function startOver(id: string): string {", ["id"])(sg, so, D, Qt, { restart: () => restarted.push("rec") }, { restart: () => restarted.push("play") }, id)
  assert.equal(startOver(rec.id).ok, true)
  assert.deepEqual(so.pendingRecording, { id: rec.id, tries: 0, fromStart: true })
  assert.equal(startOver("m1").from, 0)
  assert.deepEqual([so.pendingPlay.id, so.pendingFrom], ["m1", 0])
  assert.deepEqual(restarted, ["rec", "play"])
  assert.match(startOver("nope").error, /nothing with id/)
  sg.recorder.locked = () => true
  assert.match(startOver(rec.id).error, /locked/)
  // and they're played that way, once the guide is up
  const fired = new Function("guide", "commands", "DvrRules", "recordingSoon", commandsSrc.match(/id: recordingSoon[\s\S]*?onTriggered: \{([\s\S]*?)\n    \}\n/)[1])
  const played = []
  fired({ opened: true, recorder: { byId: { [rec.id]: rec }, locked: () => false }, recordingCard: r => r, playRecording: (c, fromStart) => played.push(fromStart) },
        { pendingRecording: { id: rec.id, tries: 0, fromStart: true } }, D, { restart() {} })
  fired({ opened: true, recorder: { byId: { [rec.id]: rec }, locked: () => false }, recordingCard: r => r, playRecording: (c, fromStart) => played.push(fromStart) },
        { pendingRecording: { id: rec.id, tries: 0 } }, D, { restart() {} })
  assert.deepEqual(played, [true, false], "from the start; playRecording resumes")
  assert.match(commandsSrc, /onTriggered: if \(commands\.pendingPlay\) \{ guide\.playVod\(commands\.pendingPlay, commands\.pendingFrom\); commands\.pendingPlay = null; commands\.pendingFrom = undefined \}/)
  assert.match(block(commandsSrc, "function play(id: string): string {"), /commands\.pendingFrom = undefined/, "play resumes")
  // and the help lists them
  for (const c of ["shows <number> <words>", "startOver <id>"]) assert.ok(commandsSrc.includes('["' + c + '"'), c)
}

// ---- the guide shows what's recording: ● REC in the channel column, the
// cell's ● Recording in red, the line at the top; YouTube's 🔴 out of titles ----
{
  const sched = new Function(read("Schedule.js").replace(/^\.pragma library\s*/, "") + "; return { cleanTitle }")()
  assert.equal(sched.cleanTitle("Zenko by Lofi Geek 🔴 Japanese Lofi Hip Hop Mix 2023 🔴 No Copyright"), "Zenko by Lofi Geek · Japanese Lofi Hip Hop Mix 2023 · No Copyright", "between words: a ·")
  assert.equal(sched.cleanTitle("🔴 LIVE: News"), "LIVE: News", "at the start: gone")
  assert.equal(sched.cleanTitle("News 🔴"), "News", "at the end: gone")
  assert.equal(sched.cleanTitle("A 🔴🔴 B"), "A · B", "two together: one ·")
  assert.equal(sched.cleanTitle("🔴LIVE"), "LIVE")
  assert.equal(sched.cleanTitle("Plain · title"), "Plain · title", "nothing else changes")
  assert.equal(sched.cleanTitle(undefined), "")
  assert.match(guideSrc, /function showTitle\(t\) \{ return Schedule\.cleanTitle\(t\) \}/)
  // every place a show's or video's title is shown goes through it
  const shown = { "ui/ProgramGrid.qml": 2, "ui/InfoPanel.qml": 3, "ui/TvScreen.qml": 1, "ui/MiniPlayer.qml": 2, "ui/ChannelTable.qml": 3, "ui/FlapBoard.qml": 2,
                  "ui/Multiview.qml": 2, "ui/CardRows.qml": 2, "ui/HomeScreen.qml": 4, "ui/DetailBox.qml": 1, "ui/VodBar.qml": 1 }
  for (const [f, n] of Object.entries(shown)) assert.equal((read(f).match(/showTitle\(/g) || []).length, n, f)
  assert.equal((guideSrc.match(/root\.showTitle\(/g) || []).length, 6, "the phones' titles (an app's video's too) and the media widget's")
  // ● REC in the channel column while it records; the cell's mark in its recording state
  const grid = read("ui/ProgramGrid.qml")
  assert.match(grid, /readonly property bool recording: guide\.recordingOn\(rowItem\.channel\)/)
  assert.match(grid, /id: chanRec\n\s+visible: rowItem\.recording\n[\s\S]*?text: "● REC"\n\s+s: guide\.look\.channelRec/)
  assert.match(grid, /\) - \(chanRec\.visible \? chanRec\.implicitWidth \+ guide\.u \* 0\.6 : 0\)\n\s+text: rowItem\.channel\.name/, "the name makes room for it")
  assert.match(grid, /s: cell\.rec === "recording" \? guide\.look\["recordDot:recording"\] : guide\.look\.recordDot/)
  assert.match(guideSrc, /function recordingOn\(ch\) \{ return !!dvr\.onChannel\(ch\) \}/)
  // the line at the top: what's recording, in the banner's words
  assert.match(guideSrc, /readonly property string recordingNow: dvr\.anyActive \? dvr\.elsewhere\(\) : ""/)
  // the banner says REC only on the channel that's recording: another channel's says nothing of it
  const badge = guideSrc.match(/readonly property string recBadge: ([\s\S]*?)\n  \/\/ and a word/)[1]
  assert.ok(!badge.includes("elsewhere"), "no other channel's recording on the banner")
  const badgeOf = (onTuned, stopping) => new Function("recOnTuned", "dvr", "root", "vod", "return " + badge)(onTuned, { stopping: stopping || {}, anyActive: true, elsewhere: () => "● 2 recording" }, { clock: () => "9:30" }, null)
  assert.equal(badgeOf(null), "", "watching another channel while two record: nothing")
  assert.equal(badgeOf({ id: "a", state: "recording", end: 1 }), "● REC until 9:30", "the channel that's recording: its REC")
  // the Split-Flap board: its status column says ● REC, red, before Live or On air
  const flap = read("ui/FlapBoard.qml")
  const status = new Function("guide", "ch", "show", "recording", flap.match(/function status\(ch, show, recording\) \{([\s\S]*?)\n  \}\n/)[1])
  assert.equal(status({ now: 100 }, { state: "ready" }, { live: true }, true), "● REC", "a recording row")
  assert.equal(status({ now: 100 }, { state: "ready" }, { live: true }, false), "Live", "a row that isn't")
  assert.match(flap, /readonly property bool recording: guide\.recordingOn\(rowItem\.channel\)/)
  assert.match(flap, /if \(c === "status"\) return board\.status\(ch, show, item\.recording\)/)
  assert.match(flap, /text === "● REC" \? guide\.look\.channelRec\.text\.color/, "in the REC color")
  // the Terminal layout (a status bar, a channel table) shows them too
  assert.match(read("ui/TopBar.qml"), /visible: guide\.recordingNow !== ""\n\s+text: guide\.recordingNow\n\s+s: guide\.look\.mastheadRec/)
  const table = read("ui/ChannelTable.qml")
  assert.match(table, /readonly property bool recording: guide\.recordingOn\(rowItem\.channel\)/)
  assert.match(table, /id: tableRec\n\s+visible: rowItem\.recording\n[\s\S]*?text: "● REC"\n\s+s: guide\.look\.channelRec/)
  assert.match(table, /- \(tableRec\.visible \? tableRec\.implicitWidth \+ parent\.spacing : 0\)\n\s+anchors\.verticalCenter: parent\.verticalCenter\n\s+text: rowItem\.channel\.name/, "the name makes room")
  assert.match(read("ui/Masthead.qml"), /id: mastRec\n\s+visible: guide\.layout\.masthead === "title" && guide\.recordingNow !== ""[\s\S]*?text: guide\.recordingNow\n\s+s: guide\.look\.mastheadRec/)
  // red by default, a theme can change each
  const look = new Function(read("Look.js").replace(/^\.pragma library\s*/, "") + "; return { effective }")()
  const eff = look.effective({}, {})
  assert.equal(eff["recordDot:recording"].text.color, "alert", "● Recording is red")
  assert.equal(eff.recordDot.text.color, "inherit", "Scheduled and Conflict keep the cell's color")
  assert.equal(eff.channelRec.text.color, "alert")
  assert.equal(eff.mastheadRec.text.color, "alert")
  assert.equal(look.effective({ "recordDot:recording": { text: { color: "accent" } } }, {})["recordDot:recording"].text.color, "accent", "a theme's own")
}

// ---- the movie bar: click or drag along it to go there ----
{
  const vb = read("ui/VodBar.qml")
  const atX = new Function("x", "track", "duration", vb.match(/function atX\(x\) \{ (return [^}]*) \}/)[1])
  assert.equal(atX(250, { width: 1000 }, 3600), 900, "a quarter of the way: a quarter of it")
  assert.equal(atX(-50, { width: 1000 }, 3600), 0, "left of it: the start")
  assert.equal(atX(1200, { width: 1000 }, 3600), 3600, "right of it: the end")
  assert.match(vb, /onPressed: function\(mouse\) \{ bar\.dragFor = bar\.guide\.vod; bar\.dragAt = bar\.atX\(mouse\.x\); bar\.guide\.showVodBar\(\) \}/, "pressing shows where")
  assert.match(vb, /onPositionChanged: function\(mouse\) \{ if \(pressed\) \{ bar\.dragAt = bar\.atX\(mouse\.x\)/, "the time follows the drag")
  const release = new Function("bar", "mouse", vb.match(/onReleased: function\(mouse\) \{ ([^\n]*) \}\n/)[1])
  const film = { id: "a" }, seeks = []
  const b1 = { dragFor: film, dragAt: 5, atX: x => x, guide: { vod: film, seekVodTo: t => seeks.push(t) } }
  release(b1, { x: 42 })
  assert.deepEqual([seeks, b1.dragAt, b1.dragFor], [[42], -1, null], "the picture jumps on letting go")
  const b2 = { dragFor: film, dragAt: 5, atX: x => x, guide: { vod: { id: "b" }, seekVodTo: t => seeks.push(t) } }
  release(b2, { x: 7 })
  assert.deepEqual(seeks, [42], "another video came on during the drag: it isn't moved")
  assert.match(vb, /onPressed: function\(mouse\) \{ bar\.dragFor = bar\.guide\.vod;/, "the drag remembers its video")
  assert.match(vb, /readonly property real shownAt: dragAt >= 0 \? dragAt : keyScrub \? guide\.scrub\.at : position/, "a drag, a held key's scrub, or where it is")
  assert.equal((vb.match(/bar\.shownAt/g) || []).length, 4, "the bar, the mark and both times show the drag")
  assert.match(read("ui/TvScreen.qml"), /guide\.reception !== "on" \|\| vodBar\.held\)/, "it stays while the pointer's on it")
}

console.log("dvr (guide): all good")
