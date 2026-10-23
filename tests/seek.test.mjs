// Skipping through a movie: a burst of skips (a held key, a remote sending
// hundreds) adds up, and the player is asked at most once a gap, so it
// isn't flooded with seeks (343 in a row stalled the shell until Omarchy
// restarted it). And playAt plays from a moment, for a scene, with no skips.
// The guide's and Commands' own code, over stand-ins: node tests/seek.test.mjs
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const guideSrc = readFileSync(new URL("../Guide.qml", import.meta.url), "utf8")
const commandsSrc = readFileSync(new URL("../Commands.qml", import.meta.url), "utf8")
const appPlaybackSrc = readFileSync(new URL("../AppPlayback.qml", import.meta.url), "utf8")
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

function timer() {
  return { running: false, restart() { this.running = true }, stop() { this.running = false } }
}

{
  // the guide's own movie player
  const seeks = []
  const player = { duration: 7_200_000, _p: 444_000,
    get position() { return this._p }, set position(v) { seeks.push(v); this._p = v } }
  const seekGap = timer()
  const root = { vod: { id: "m" }, started: true, seekTarget: -1, showVodBar() {} }
  const fn = (name, params) => new Function("root", "player", "seekGap", ...params, block(guideSrc, "function " + name + "("))
  root.seekVodTo = s => fn("seekVodTo", ["seconds"])(root, player, seekGap, s)
  root.applySeek = () => fn("applySeek", [])(root, player, seekGap)
  root.seekVod = s => fn("seekVod", ["seconds"])(root, player, seekGap, s)

  for (let i = 0; i < 343; i++) root.seekVod(10)
  assert.equal(seeks.length, 1, "the first skip goes at once; the rest wait for the gap")
  assert.equal(root.seekTarget, 444_000 + 343 * 10_000, "they add up")
  root.applySeek()   // the gap ends
  assert.deepEqual(seeks, [454_000, 444_000 + 343 * 10_000], "two seeks for 343 skips")
  root.applySeek()   // and the next gap: nothing waiting
  assert.equal(seeks.length, 2)
  assert.equal(root.seekTarget, -1)
  root.seekVod(1_000_000)
  root.applySeek()
  assert.equal(player.position, 7_199_000, "never past the end")
  assert.match(guideSrc, /readonly property real playPosition: vod \? \(seekTarget >= 0 \? seekTarget : player\.position\) : 0/,
               "the bar shows where the skips are going")
}

{
  // an app's video (AppPlayback)
  const seeks = [], events = []
  const pb = { closing: false, seekTarget: -1, event(e) { events.push(e) },
    player: { seekable: true, duration: 3_600_000, _p: 0, get position() { return this._p }, set position(v) { seeks.push(v); this._p = v } } }
  const seekGap = timer()
  const fn = (name, params) => new Function("pb", "seekGap", ...params, block(appPlaybackSrc, "function " + name + "("))
  pb.applySeek = () => fn("applySeek", [])(pb, seekGap)
  pb.seek = s => fn("seek", ["seconds"])(pb, seekGap, s)
  for (let i = 0; i < 100; i++) pb.seek(10)
  pb.applySeek()
  assert.deepEqual(seeks, [10_000, 1_000_000], "an app's skips add up too")
  assert.equal(events.length, 2, "the app hears of each seek made, not each key")
}

{
  // playAt: a moment, then the movie from there
  const played = []
  const guide = { opened: true, entryFor: id => id === "m1" ? { id: "m1", title: "A.I." } : null, resumeAt: () => 80,
    videoLockedBy: () => null, guidePip() {}, playVod: (e, from) => played.push([e.title, from]) }
  const commands = {
    pendingPlay: null, pendingFrom: null,
    okReply: x => JSON.stringify(Object.assign({ ok: true }, x)), failReply: m => JSON.stringify({ ok: false, error: m }) }
  const playSoon = { restart() {} }
  // play and playAt are the IpcHandler's (id: ipc), not commands': playAt reaches play through it
  assert.match(commandsSrc, /IpcHandler \{\n    id: ipc\n/)
  const ipc = { play: id => new Function("guide", "commands", "playSoon", "id", block(commandsSrc, "function play(id: string): string {"))(guide, commands, playSoon, id) }
  const playAt = (id, at) => new Function("guide", "commands", "playSoon", "ipc", "id", "at", block(commandsSrc, "function playAt(id: string, at: string): string {"))(guide, commands, playSoon, ipc, id, at)
  const soonLine = commandsSrc.match(/onTriggered: (if \(commands\.pendingPlay\) \{.*\})\n/)
  assert.ok(soonLine, "playSoon's onTriggered")
  const soon = () => new Function("guide", "commands", soonLine[1])(guide, commands)
  for (const [at, secs] of [["3880", 3880], ["1:04:40", 3880], ["64:40", 3880], ["0", 0]]) {
    assert.deepEqual(JSON.parse(playAt("m1", at)), { ok: true, playing: "A.I.", from: secs }, at)
    soon()
    assert.deepEqual(played.pop(), ["A.I.", secs], "plays from " + at)
  }
  for (const bad of ["", "abc", "1:2:3:4", "-5", "1.5"]) assert.equal(JSON.parse(playAt("m1", bad)).ok, false, "refused: " + JSON.stringify(bad))
  assert.equal(JSON.parse(playAt("nope", "10")).ok, false, "an id that isn't there")
  JSON.parse(ipc.play("m1"))
  soon()
  assert.deepEqual(played.pop(), ["A.I.", undefined], "play, after playAt: from where you stopped again")
}
console.log("seek: all good")
