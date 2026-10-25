import QtQuick
import QtMultimedia
import "Timeshift.js" as Ts
import "Dvr.js" as Dvr

// Pause and rewind (Settings → Recordings: Off, 5 or 30 minutes; off to
// start with). While it's on, a live channel watched on the TV plays through
// a rolling buffer on the recordings drive (bin/om-pg-dvr buffer, one
// session at a time): the provider sees one stream, the buffer's writer.
// The player opens once two segments are in (its own deadline: the 20 s
// tune watchdog starts only once a playlist is handed over), at Live (the
// start of the second-newest). Every move (Resume, Back 30 s, Forward 30 s,
// Live, a recovery) opens the buffer again at a new address, a generation
// of its own: only that open seeks. The clock here is the buffer's: the
// edge moves when a segment is finished, the picture while frames come.
// A stall holds the picture and goes back to Live when segments come again.
// Anything it can't recover from stops the writer, waits until it's gone,
// then plays the channel directly; never two connections. Asking for the
// status is the session's lease: a guide that's gone stops it. The buffer
// stays while that channel is on the TV (full screen, the guide's preview,
// the mini player) and goes on another channel, TV off, Multiview, a video,
// an app, relocking, or a change of the setting or the place. Rules in
// Timeshift.js.
Item {
  id: ts

  required property var guide
  required property var dvr
  required property var player        // the TV's

  readonly property int minutes: dvr.settings.on ? Ts.minutesOf(dvr.settings.timeshift) : 0
  readonly property bool turnedOn: minutes > 0

  property string session: ""
  property string base: ""            // the session's address, its secret included
  property string upstreamUrl: ""     // what it copies
  property var chan: null             // the channel it copies, { name, hash }, and its provider: a turned address is followed
  property string provider: ""
  property string phase: "off"        // off, starting, filling, ready, failed
  property string reason: ""          // why it gave up
  property string failedFor: ""       // the channel it gave up on: played directly until another one
  property var win: ({ ready: false, count: 0, headSeq: 0, oldest: 0, live: 0, edge: 0, longest: 0, completedAgo: -1 })
  property int gen: 0                 // the newest open of the buffer
  property var pending: null          // that open, until it's loaded: { gen, at (where Qt seeks), live }
  property bool owning: false         // the player is on the buffer
  property bool paused: false
  property bool atLive: true
  property real point: 0              // the picture, in the buffer's time
  property real winAt: 0              // when win came
  property real liveOffset: 0         // how far the picture was from live (liveNow) when it last went to Live
  property real tick: 0               // the clock's now, for the chip
  property real lastFrame: 0
  property real lastTick: 0
  property bool stalled: false
  property bool recovering: false     // one reopen tried: another failure gives up
  property int request: 0             // each start and end: a late answer of an earlier one is ignored
  property int misses: 0              // the status not answered, in a row
  property int startsOut: 0           // starts on their way
  property int stopsOut: 0            // stops on their way (their writers not gone yet)
  property var waiting: []            // what waits until every writer is gone: [{ request, done }]
  property var unstopped: []          // sessions whose stop didn't confirm they're gone: asked again
  property bool following: false

  readonly property bool active: phase === "ready" && owning
  readonly property bool filling: phase === "starting" || phase === "filling"
  readonly property bool busy: session !== "" || startsOut > 0 || stopsOut > 0
  // how far behind live, counted from the last time it was Live (so a pause
  // of a minute reads a minute, whatever the segments)
  readonly property real behind: active ? Math.max(0, Ts.liveNow(win, tick - winAt) - point - liveOffset) : 0
  readonly property string chipText: active ? Ts.chip(atLive, behind) : ""
  // what Pause says when it can't run now ("" when it can)
  readonly property string cantPauseText: !turnedOn || active ? "" : phase === "failed" ? Ts.cantPause(reason) : "Can't pause right now"

  // ---- starting and ending ----

  // Whether the TV's stream goes through the buffer: a live channel watched
  // (or about to be: guide.bufferNext), and not one it gave up on
  function takes(onAir) {
    if (!ts.turnedOn || !(guide.watching || guide.bufferNext)) return false
    var url = Ts.upstream(onAir, guide.streamBase)
    return url !== "" && url !== ts.failedFor
  }

  // The TV tuned a channel it takes (Guide.qml play())
  function tuned() {
    var url = Ts.upstream(guide.onAir, guide.streamBase)
    ts.failedFor = ""
    guide.tuneWatch(false)
    if (ts.session && ts.upstreamUrl === url) {
      // the same channel again: Live, once it's ready
      ts.paused = false
      if (ts.phase === "ready") ts.openAt(ts.win.live, true)
      return
    }
    ts.end(function() { ts.begin(url) })
    if (ts.phase === "off") ts.phase = "starting"   // the old writer stops first: the card says it's starting already
  }

  function begin(url) {
    var my = ++ts.request
    var ch = guide.channels[guide.tunedRow]
    ts.phase = "starting"
    ts.reason = ""
    ts.upstreamUrl = url
    ts.chan = ch ? { name: ch.name || "", hash: Dvr.hashOf(ch.url) } : null
    ts.provider = ch ? Dvr.providerOf(ch) : ""
    ts.win = { ready: false, count: 0, headSeq: 0, oldest: 0, live: 0, edge: 0, longest: 0, completedAgo: -1 }
    player.stop()                     // a picture on the channel directly lets go first
    fillDeadline.restart()
    ts.startsOut += 1
    dvr.ready(function(place) {
      if (my !== ts.request || !place) {
        ts.startDone()
        if (my === ts.request) ts.fallback("drive")
        return
      }
      dvr.call(["buffer", "start"], JSON.stringify({ url: url, minutes: ts.minutes, place: place, keepFree: dvr.keepFreeGB * Dvr.GB, height: 1080 }), function(res) {
        if (my !== ts.request) {
          // overtaken: that one goes too, and what waits for it waits for that
          if (res.ok) ts.stopOne(res.session)
          ts.startDone()
          return
        }
        if (!res.ok) { ts.startDone(); ts.fallback(res.error); return }
        ts.session = res.session
        ts.base = res.base
        ts.phase = "filling"
        ts.misses = 0
        ts.startDone()
        ts.ask()
      }, 30000)
    })
  }

  // Everything off: the session stops (done() once its writer is gone)
  function end(done) {
    if (ts.owning) player.stop()      // the old buffer's address says nothing more once its server's gone
    ts.request += 1
    ts.phase = "off"
    ts.reason = ""
    ts.owning = false
    ts.pending = null
    ts.paused = false
    ts.atLive = true
    ts.stalled = false
    ts.recovering = false
    fillDeadline.stop()
    if (ts.session) { ts.stopOne(ts.session); ts.session = ""; ts.base = "" }
    ts.whenGone(done)
  }

  // done() once no writer is left (none starting, none stopping), unless
  // something newer was asked for meanwhile (a later start or end): then it
  // doesn't happen (dropped(), if given, says so)
  function whenGone(done, dropped) {
    if (!done) return
    if (ts.startsOut === 0 && ts.stopsOut === 0) done()
    else ts.waiting = ts.waiting.concat([{ request: ts.request, done: done, dropped: dropped }])
  }
  function startDone() { ts.startsOut -= 1; ts.flush() }
  function stopOne(session) {
    ts.stopsOut += 1
    ts.tryStop(session)
  }
  // a stop counts only once the helper says the writer's gone; otherwise it's
  // asked again in a moment (its lease ends it soon anyway: nothing asks it now)
  function tryStop(session) {
    dvr.call(["buffer", "stop", session], undefined, function(res) {
      if (res.ok) { ts.stopsOut -= 1; ts.flush(); return }
      ts.unstopped = ts.unstopped.concat([session])
    }, 60000)
  }
  Timer {
    interval: 3000
    repeat: true
    running: ts.unstopped.length > 0
    onTriggered: { var left = ts.unstopped; ts.unstopped = []; for (var i = 0; i < left.length; i++) ts.tryStop(left[i]) }
  }
  function flush() {
    if (ts.startsOut || ts.stopsOut || !ts.waiting.length) return
    var w = ts.waiting
    ts.waiting = []
    for (var i = 0; i < w.length; i++) {
      if (w[i].request === ts.request) w[i].done()
      else if (w[i].dropped) w[i].dropped()
    }
  }

  // Gives up on this channel: the writer stops, and once it's gone (its
  // connection closed) the channel plays directly
  function fallback(why) {
    var url = ts.upstreamUrl
    ts.request += 1
    ts.reason = why || ""
    ts.phase = "failed"
    ts.failedFor = url
    ts.owning = false
    ts.pending = null
    ts.paused = false
    ts.stalled = false
    ts.recovering = false
    fillDeadline.stop()
    player.stop()
    if (ts.session) { ts.stopOne(ts.session); ts.session = ""; ts.base = "" }
    ts.whenGone(function() {
      if (guide.reception === "off" || Ts.upstream(guide.onAir, guide.streamBase) !== url) return
      guide.reception = "tuning"
      guide.started = false
      guide.tuneWatch(true)
      guide.play()
    })
  }

  Timer {
    id: fillDeadline
    interval: 45000                   // two finished segments, even on a channel with long ones
    onTriggered: if (ts.filling) ts.fallback("")
  }

  // ---- the status: what's in the buffer, and the lease ----

  Timer {
    interval: ts.phase === "filling" ? 1000 : 2000
    repeat: true
    running: ts.session !== ""
    onTriggered: ts.ask()
  }

  function ask() {
    var base = ts.base, my = ts.request
    if (!base) return
    var x = new XMLHttpRequest()
    x.onreadystatechange = function() {
      if (x.readyState !== XMLHttpRequest.DONE || my !== ts.request || base !== ts.base) return
      var w = null
      try { w = x.status === 200 ? JSON.parse(x.responseText) : null } catch (e) { w = null }
      if (!w || typeof w !== "object") { if (++ts.misses >= 3) ts.fallback(""); return }
      ts.misses = 0
      ts.win = w
      ts.winAt = Date.now()
      ts.checkWindow()
    }
    x.open("GET", base + "/status")
    x.send()
  }

  function checkWindow() {
    var w = ts.win
    if (w.state === "failed") { ts.fallback(w.reason); return }
    if (ts.phase === "filling" && w.ready) {
      ts.phase = "ready"
      fillDeadline.stop()
      ts.openAt(w.live, true)
      return
    }
    if (ts.phase !== "ready" || !ts.owning) return
    var quiet = Date.now() - ts.lastFrame
    if (!ts.stalled && !ts.paused && !ts.pending && Ts.stalled(w, quiet)) ts.stalled = true
    else if (ts.stalled && Ts.flowing(w)) { ts.stalled = false; ts.openAt(w.live, true) }   // segments again: Live, its margin back
    else if (!ts.stalled && !ts.paused && !ts.pending && quiet > 6000 && Ts.flowing(w)) ts.recover()   // the player stuck, the buffer fine
    ts.follow()
  }

  // A playlist that turned its links: the writer moves to the new address
  function follow() {
    if (!ts.chan || ts.following || !ts.session || !guide.onAir || !guide.onAir.iptv) return
    var ch = dvr.channelByHash(ts.chan, ts.provider)
    if (!ch || ch.url === ts.upstreamUrl) return
    var my = ts.request
    ts.following = true
    dvr.call(["buffer", "follow", ts.session], JSON.stringify({ url: ch.url }), function(res) {
      ts.following = false
      if (my !== ts.request || !res.ok) return
      ts.upstreamUrl = ch.url
      ts.chan = { name: ch.name || "", hash: Dvr.hashOf(ch.url) }
    })
  }

  // ---- the player ----

  // Opens the buffer at t (its time; Live: where Live is now), a new generation
  function openAt(t, live) {
    var w = ts.win
    var target = live ? w.live : Ts.clamp(t, w)
    ts.gen += 1
    ts.pending = { gen: ts.gen, at: Math.max(0, target - w.oldest), live: live }
    ts.point = target
    ts.atLive = live
    ts.tick = Date.now()
    if (live) ts.liveOffset = Math.max(0, Ts.liveNow(w, ts.tick - ts.winAt) - target)
    ts.owning = true
    ts.lastFrame = Date.now()
    guide.tuneWatch(true)
    player.source = Ts.openUrl(ts.base, ts.gen, w.headSeq)
  }

  // The player's status about a buffer source, before the live TV's own
  // handling: true when it was the buffer's (an earlier open's is ignored)
  function mediaStatus(s) {
    var g = Ts.genOf(player.source, ts.base)
    if (!g) return false
    if (g !== ts.gen) return true
    if (s === MediaPlayer.LoadedMedia && ts.pending && ts.pending.gen === g) {
      player.position = ts.pending.at
      ts.pending = null
      if (ts.paused) player.pause()
      else player.play()
      guide.started = true
    } else if ((s === MediaPlayer.BufferedMedia || s === MediaPlayer.BufferingMedia) && !ts.pending) {
      if (guide.reception === "tuning" && guide.started) guide.reception = "on"
    } else if (s === MediaPlayer.EndOfMedia || s === MediaPlayer.InvalidMedia) {
      ts.recover()
    }
    return true
  }
  function error() {
    var g = Ts.genOf(player.source, ts.base)
    if (!g) return false
    if (g === ts.gen) ts.recover()
    return true
  }
  // One reopen where it was; failing again gives up
  function recover() {
    if (ts.phase !== "ready") return
    if (ts.recovering) { ts.fallback(""); return }
    ts.recovering = true
    ts.openAt(ts.point, ts.atLive)
  }

  // A frame: the clock's. Once the reopened source shows one, a recovery
  // worked (Qt saying Buffered isn't proof: the picture can stay frozen)
  function frame() {
    ts.lastFrame = Date.now()
    if (ts.recovering && !ts.pending) ts.recovering = false
  }

  // The picture's place: it moves only while it plays and frames come
  Timer {
    interval: 250
    repeat: true
    running: ts.owning
    onRunningChanged: ts.lastTick = 0
    onTriggered: {
      var now = Date.now()
      var dt = ts.lastTick ? now - ts.lastTick : 0
      ts.lastTick = now
      ts.tick = now
      if (ts.pending || ts.paused || player.playbackState !== MediaPlayer.PlayingState || now - ts.lastFrame > 600) return
      ts.point += dt
      if (!ts.atLive && ts.behind < Ts.NEAR) ts.atLive = true
      // at Live and playing: the count stays anchored to what's on (the
      // provider's recent past still coming in after it opened moves the
      // buffer's live ahead, not you), so a pause counts from when it's pressed
      if (ts.atLive) ts.liveOffset = Math.max(0, Ts.liveNow(ts.win, now - ts.winAt) - ts.point)
    }
  }

  // ---- what you do (each says why it couldn't, or "ok") ----

  function togglePause() {
    if (!ts.active) return ts.cantPauseText
    if (ts.paused) return ts.resume()
    player.pause()
    ts.paused = true
    ts.atLive = false
    return "ok"
  }
  function pause() { return ts.active && ts.paused ? "ok" : ts.togglePause() }
  // Resume opens again where it was, clamped to the buffer now (paused
  // longer than it holds: its oldest part)
  function resume() {
    if (!ts.active) return ts.cantPauseText
    ts.paused = false
    ts.openAt(ts.point, false)
    return "ok"
  }
  function back() {
    if (!ts.active) return ts.cantPauseText
    ts.openAt(Ts.backTarget(ts.point, ts.win), false)
    return "ok"
  }
  function forward() {
    if (!ts.active) return ts.cantPauseText
    if (Ts.reachesLive(ts.point, ts.win)) return ts.live()
    ts.openAt(Ts.forwardTarget(ts.point, ts.win), false)
    return "ok"
  }
  function live() {
    if (!ts.active) return ts.cantPauseText
    ts.paused = false
    ts.openAt(ts.win.live, true)
    return "ok"
  }
  // To a point in the buffer's time (a scrub let go, the phone's bar):
  // never before its oldest part; at Live or past it, Live. One reopen;
  // paused stays paused, there
  function seekTo(t) {
    if (!ts.active) return ts.cantPauseText
    if (!isFinite(t)) return "no such point"
    if (t >= ts.win.live - Ts.NEAR) return ts.live()
    ts.openAt(Math.max(ts.win.oldest, t), false)
    return "ok"
  }
  // Where Live is now, as the chip counts it (the end of the bar)
  readonly property real liveEnd: active ? point + behind : 0

  // An agent's move by seconds (back when negative), as far as the buffer goes
  function seekBy(seconds) {
    if (!ts.active) return ts.cantPauseText
    var t = ts.point + seconds * 1000
    if (t >= ts.win.live - Ts.NEAR) return ts.live()
    ts.openAt(t, false)
    return "ok"
  }
}
