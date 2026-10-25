// node tests/remotecommands.test.mjs
// The phone's new buttons on the TV's side (Guide.qml, ui/Multiview.qml), run
// from their own code with the guide stood in: pause / play, rewind,
// forward and Live per what's playing (a live channel full screen as J K L,
// a movie or video 10 s, an app's video, the mini player only for a movie,
// nothing with the TV off); the one full / mini button (full screen ↔ the
// mini player, elsewhere as FULL, TV off → on); HOME (nothing with Home off;
// an app's video closes first; the picture stops; Home opens); Multiview
// (the selected tile full screen and back, the transport buttons ignored).
// And what the phones are told: pause and rewind's fields, a movie's place,
// the recording channels, without any stream address.
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const read = (f) => readFileSync(new URL("../" + f, import.meta.url), "utf8")
const guideSrc = read("Guide.qml")
const mvSrc = read("ui/Multiview.qml")
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

function stand(over) {
  const did = []
  const rec = (name) => (...a) => { did.push([name, ...a]); return "ok" }
  const root = Object.assign({
    appPlaying: false, vod: null, watching: false, pip: false, reception: "on", opened: true, homeEnabled: true, row: 3,
    togglePause: rec("togglePause"), seekVod: rec("seekVod"), tsKey: rec("tsKey"), showBanner: rec("showBanner"), expandPip: rec("expandPip"),
    goPip: rec("goPip"), watch: rec("watch"), remoteSeek: rec("remoteSeek"), remotePowerOn: rec("remotePowerOn"), turnOff: rec("turnOff"), openHome: rec("openHome"), summonTo: rec("summonTo"),
  }, over || {})
  const timeshift = Object.assign({ active: true, live: rec("live") }, (over || {}).ts || {})
  const appPlaybackItem = { togglePause: rec("app.togglePause"), seek: rec("app.seek"), close: (why, then) => { did.push(["app.close", why]); root.appPlaying = false; if (then) then() } }
  return { root, timeshift, appPlaybackItem, did }
}

// ---- pause / play, rewind, forward, Live ----
const transportBody = block(guideSrc, "function remoteTransport(cmd, extra) {")
const transport = (s, cmd, extra) => new Function("root", "timeshift", "appPlaybackItem", "cmd", "extra", transportBody)(s.root, s.timeshift, s.appPlaybackItem, cmd, extra)
{
  let s = stand({ watching: true })
  for (const [cmd, what] of [["playpause", "pause"], ["rewind", "back"], ["forward", "forward"]]) {
    transport(s, cmd)
    assert.deepEqual(s.did.pop(), ["tsKey", what], "a live channel full screen: " + cmd + " is " + what + " (J K L, their answers when it's off)")
  }
  transport(s, "live")
  assert.deepEqual(s.did.splice(0), [["live"], ["showBanner"]], "LIVE goes to Live while the buffer runs")
  s = stand({ watching: true, ts: { active: false } })
  transport(s, "live")
  assert.deepEqual(s.did, [], "with nothing kept, LIVE does nothing (it's live already)")
  s = stand({ watching: true, vod: {} })
  transport(s, "playpause"); transport(s, "rewind"); transport(s, "forward"); transport(s, "live")
  assert.deepEqual(s.did, [["togglePause"], ["seekVod", -10], ["seekVod", 10]], "a movie: pause, 10 s back and forward; no Live")
  s = stand({ pip: true, vod: {} })
  transport(s, "forward")
  assert.deepEqual(s.did, [["seekVod", 10]], "the mini player's movie too")
  s = stand({ pip: true })
  transport(s, "playpause"); transport(s, "rewind")
  assert.deepEqual(s.did, [], "the mini player's live channel: nothing (the buffer runs only full screen)")
  s = stand({ appPlaying: true, watching: true })
  transport(s, "playpause"); transport(s, "rewind"); transport(s, "live")
  assert.deepEqual(s.did, [["app.togglePause"], ["app.seek", -10]], "an app's video")
  s = stand({ watching: true, reception: "off" })
  transport(s, "playpause")
  assert.deepEqual(s.did, [], "the TV off: nothing")
  s = stand({ watching: false })
  transport(s, "playpause")
  assert.deepEqual(s.did, [], "the guide or Home: nothing")
  s = stand({ watching: true })
  transport(s, "seek", { cmd: "seek", at: 0.5, play: 3 })
  assert.deepEqual(s.did, [["remoteSeek", 0.5, 3]], "seek: the card's bar, with its point and play (tests/playercontrols.test.mjs)")
}

// ---- the one full / mini button ----
const windowBody = block(guideSrc, 'if (cmd === "window") {')
const windowCmd = (s) => new Function("root", "on", windowBody)(s.root, s.root.reception !== "off")
{
  let s = stand({ watching: true })
  windowCmd(s); assert.deepEqual(s.did, [["goPip"]], "full screen → the mini player")
  s = stand({ pip: true }); windowCmd(s); assert.deepEqual(s.did, [["expandPip"]], "the mini player → full screen")
  s = stand({ opened: true }); windowCmd(s); assert.deepEqual(s.did, [["watch", 3]], "Home, the guide, the library → full screen on what's highlighted, as FULL")
  s = stand({ opened: false, reception: "off" }); windowCmd(s); assert.deepEqual(s.did, [["remotePowerOn", -1]], "TV off → on, full screen")
  s = stand({ appPlaying: true, opened: true }); windowCmd(s); assert.deepEqual(s.did, [], "an app's video: nothing (it has no mini player)")
}

// ---- HOME ----
const homeBody = block(guideSrc, "function remoteHome(closed) {")
{
  let s = stand({ homeEnabled: false })
  const home = (st) => { st.root.remoteHome = (closed) => new Function("root", "appPlaybackItem", "closed", homeBody)(st.root, st.appPlaybackItem, closed); return st.root.remoteHome() }
  assert.equal(home(s), "Home is off")
  assert.deepEqual(s.did, [], "with Home off, nothing")
  s = stand({ watching: true, vod: {} })
  home(s)
  assert.deepEqual(s.did, [["turnOff"], ["openHome"]], "the picture stops (turnOff keeps a movie's place, stops Multiview and the mini player), then Home")
  s = stand({ opened: false, pip: true })
  home(s)
  assert.deepEqual(s.did, [["turnOff"], ["summonTo", "home"]], "the guide closed: it opens on Home")
  s = stand({ appPlaying: true })
  home(s)
  assert.deepEqual(s.did, [["app.close", "user"], ["turnOff"], ["openHome"]], "an app's video closes as BACK closes it, then Home")
  s = stand({ appPlaying: true })
  s.appPlaybackItem.close = (why, then) => { s.did.push(["app.close", why]); then() }   // still playing when it calls back
  home(s)
  assert.deepEqual(s.did, [["app.close", "user"], ["turnOff"], ["openHome"]], "closed once, never again in a loop")
  // turnOff is what stops each picture
  const off = block(guideSrc, "function turnOff() {")
  for (const step of ["timeshift.end()", "multiviewItem.teardown()", "root.leaveVod()", "root.pip = false"]) assert.ok(off.includes(step), "turnOff: " + step)
}

// ---- Multiview takes the button ----
const mvBody = block(mvSrc, "function remote(cmd, number) {")
{
  const mvRemote = (mv, cmd) => new Function("mv", "guide", "Qt", "cmd", "number", mvBody)(mv, { numbers: [], showGuide() {}, dismiss() {} }, { Key_Up: 1, Key_Down: 2, Key_Left: 3, Key_Right: 4, Key_Return: 5, Key_Escape: 6, Key_PageUp: 7, Key_PageDown: 8, Key_I: 9 }, cmd)
  let entered = 0
  const mv = { mode: "tiles", bannerUp: false, enter() { entered += 1 }, key() { throw new Error("no key") } }
  assert.equal(mvRemote(mv, "window"), true)
  assert.equal(entered, 1, "the tiles: the selected tile full screen")
  mv.mode = "full"; mv.bannerUp = true
  assert.equal(mvRemote(mv, "window"), true)
  assert.equal(mv.mode, "tiles", "a full-screen tile: back to the tiles")
  assert.equal(mv.bannerUp, false)
  for (const c of ["playpause", "rewind", "forward", "live", "seek"]) assert.equal(mvRemote(mv, c), true, c + " does nothing in Multiview (taken)")
  assert.equal(mvRemote(mv, "home"), false, "HOME goes to the guide, which stops the tiles")
}

// ---- what the phones are told ----
{
  const state = block(guideSrc, "function remoteState() {")
  for (const field of ["signal: root.reception", "recHere:", "media: media", "ts: ts", "paused:", "position: Math.round(root.playPosition / 1000)", "length: Math.round(root.playDuration / 1000)", "rec: !!dvr.onChannel(c)"])
    assert.ok(state.includes(field), "the phone's state: " + field)
  assert.ok(!/\b(url|stream|base|source)\s*:/i.test(state), "no stream address in what the phones are told")
  for (const k of ["running: timeshift.active", "paused: timeshift.paused", "atLive: timeshift.atLive", "behind: Math.round(timeshift.behind / 1000)", "why: timeshift.cantPauseText"])
    assert.ok(state.includes(k), "pause and rewind: " + k)
  // routed: the new commands reach their handlers, after a box on the TV
  const cmd = block(guideSrc, "function remoteCommand(cmd, number, by, digits, extra) {")
  const box = cmd.indexOf('if (root.dialog && root.dialog !== "remote") {   // a box is open on the TV')
  const tr = cmd.indexOf('return root.remoteTransport(cmd, extra)')
  assert.ok(box > 0 && tr > box, "a box open on the TV takes the transport buttons first")
  assert.ok(cmd.indexOf('if (cmd === "home") return root.remoteHome()') > 0)
}

console.log("remote commands: all good")
