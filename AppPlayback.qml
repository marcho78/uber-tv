import QtQuick
import QtMultimedia

// An app's media playing (ui/AppPlayer.qml shows it). Every play, the first
// or the one fallback an app may give after a failure, is an attempt with
// its own MediaPlayer, made for it and destroyed after it: before the next
// one is made, the old one is marked dead (its signals are ignored), let go
// of the video, stopped and destroyed, and its destruction waited for (2 s
// at most; if it doesn't come, the attempt fails and nothing new is made).
// A player is never reset with source = "" (this FFmpeg backend aborts the
// next open). The player only ever gets the helper's relay address.
//
// The app hears what happens through playback calls, one at a time, in
// order (progress coalesced, at most 8 waiting). Closing a session (you
// stopped it, it ended, another one replaced it, sign-out, removal, apps
// off, the runtime stopping) is ordered: a new playback epoch (late answers
// to earlier play or playbackFailed calls are dropped), the pending calls
// called off, the player paused, one last "stopped" call (5 s), then the
// player destroyed, the relay closed, the lease given back, and only then
// whatever was waiting for it (a replacement, a restart, a sign-out).
Item {
  id: pb

  required property var guide

  property var session: null        // { app, rt, handle, epoch, seq, title, subtitle, startAt, live, attempt, failed, state, started, lastPos }
  property var player: null
  property var videoOutput: null    // the screen's (ui/AppPlayer.qml)
  property int epochs: 0
  property int attempts: 0
  property var queue: []            // events waiting: [{ state, reason }]
  property var sending: null        // the playback call out: { id, terminal }
  property var after: []            // what waits for the close to finish
  property bool paused: false
  property bool buffering: false
  property string error: ""
  property real position: 0         // seconds
  property real duration: 0
  // the session's phase, as a property (a field of session changing isn't
  // seen by bindings): playing, closing, finalizing, or "" with none
  property string phase: ""
  readonly property bool active: session !== null
  readonly property bool closing: active && phase !== "playing"
  property var pendingPlay: null    // a play waiting for the old session to close
  property var waitingTv: null      // a play waiting for the TV's pause and rewind buffer to be gone

  // ---- starting ---------------------------------------------------------
  // value: the helper's play result ({ url (the relay), title, subtitle,
  // startAt, live, session })
  function start(appId, rt, value) {
    if (pb.session) {
      pb.dropPending()   // a newer play: the one waiting before it won't happen
      pb.pendingPlay = { app: appId, rt: rt, value: value }
      pb.close("replaced", null)
      return
    }
    if (!/^http:\/\/127\.0\.0\.1:[0-9]+\/[0-9a-f]{32}\//.test(String(value.url || ""))) return
    if (guide.pauser && guide.pauser.busy) {
      // the TV's pause and rewind buffer ends first, its writer gone; something
      // newer asked for meanwhile (a channel, the TV off, another play, the
      // app stopping or signing out) wins
      pb.dropWaiting("")                  // a play waiting before it: never
      var w = { app: appId, rt: rt, value: value }
      pb.waitingTv = w
      guide.turnOff()
      guide.pauser.whenGone(function() {
        if (pb.waitingTv === w && rt.phase === "ready") { pb.waitingTv = null; pb.start(appId, rt, value) }
        else if (pb.waitingTv === w) pb.dropWaiting("")
      }, function() { if (pb.waitingTv === w) pb.dropWaiting("") })
      return
    }
    pb.waitingTv = null
    guide.turnOff()   // the TV or a video ends first
    pb.epochs += 1
    pb.session = { app: appId, rt: rt, handle: value.session, epoch: pb.epochs, seq: 0, title: value.title || "", subtitle: value.subtitle || "",
                   startAt: Number(value.startAt) || 0, live: value.live === true, failed: 0, state: "playing", started: false, startApplied: false }
    pb.phase = "playing"
    pb.queue = []
    pb.sending = null
    pb.error = ""
    progressTimer.last = -1
    pb.paused = false
    pb.buffering = true
    pb.position = 0
    pb.duration = 0
    pb.seekTarget = -1
    seekGap.stop()
    rt.lease("playback", true)
    guide.appPlaying = true
    pb.attempt(value.url)
  }

  // A new attempt, once the old player is gone
  function attempt(url) {
    var s = pb.session
    pb.retire(function(ok) {
      if (pb.session !== s || s.state !== "playing") return
      if (!ok) { pb.fail("the player before didn't let go"); return }
      pb.attempts += 1
      pb.buffering = true
      pb.player = playerKind.createObject(pb, { owner: s.app, sessionEpoch: s.epoch, attemptId: pb.attempts, source: url })
      pb.player.videoOutput = pb.videoOutput
      pb.player.play()
    })
  }

  // The player that's there, gone: marked dead, let go of, stopped,
  // destroyed, its destruction waited for (done(ok))
  function retire(done) {
    var p = pb.player
    if (!p) { done(true); return }
    pb.player = null
    p.dead = true
    p.videoOutput = null
    p.stop()
    var finished = false
    var timer = Qt.createQmlObject("import QtQuick; Timer { interval: 2000 }", pb)
    p.gone.connect(function() { if (finished) return; finished = true; timer.destroy(); done(true) })
    timer.triggered.connect(function() { if (finished) return; finished = true; timer.destroy(); done(false) })
    timer.start()
    p.destroy()
  }

  onVideoOutputChanged: if (pb.player) pb.player.videoOutput = pb.videoOutput

  // ---- what the player says (only the live attempt is heard) --------------
  function heard(p) { return pb.session && pb.player === p && !p.dead && p.sessionEpoch === pb.session.epoch && pb.session.state === "playing" }

  function onStatus(p) {
    if (!heard(p)) return
    var st = p.mediaStatus
    pb.buffering = st === MediaPlayer.LoadingMedia || st === MediaPlayer.BufferingMedia || st === MediaPlayer.StalledMedia
    if (st === MediaPlayer.EndOfMedia && pb.session.started) { pb.close("ended", null); return }
    if (st === MediaPlayer.InvalidMedia) { pb.failed(p, "it couldn't be played"); return }
    if ((st === MediaPlayer.LoadedMedia || st === MediaPlayer.BufferedMedia) && p.seekable && !pb.session.startApplied && pb.session.startAt > 0) {
      pb.session.startApplied = true
      p.position = pb.session.startAt * 1000
    }
  }

  function onState(p) {
    if (!heard(p)) return
    var st = p.playbackState
    if (st === MediaPlayer.PlayingState) {
      if (!pb.session.started) { pb.session.started = true; pb.event("started") }
      else if (pb.paused) pb.event("resumed")
      pb.paused = false
      progressTimer.restart()
    } else if (st === MediaPlayer.PausedState) {
      if (!pb.paused && pb.session.started) pb.event("paused")
      pb.paused = true
    }
  }

  function onError(p, text) {
    if (!heard(p)) return
    pb.failed(p, text || "it couldn't be played")
  }

  function onPosition(p) {
    if (!heard(p)) return
    pb.position = p.position / 1000
    pb.duration = p.duration / 1000
  }

  // The first failure: the app may give one more thing to try. Qt can say
  // one failure twice (an invalid file and an error): an attempt fails once.
  function failed(p, why) {
    if (p.failedOnce) return
    p.failedOnce = true
    var s = pb.session
    if (s.failed >= 1) { pb.fail(why); return }
    s.failed = 1
    pb.buffering = true
    var epoch = s.epoch
    s.failedCall = s.rt.call("playbackFailed", { session: s.handle, reason: String(why).slice(0, 200) }, function(kind, value) {
      if (!pb.session || pb.session.epoch !== epoch || pb.session.state !== "playing") return   // the session closed meanwhile: dropped
      pb.session.failedCall = 0
      if (kind === "play") {
        // a new attempt: everything about it is the fallback's
        var t = pb.session
        t.handle = value.session
        t.title = value.title || ""
        t.subtitle = value.subtitle || ""
        t.startAt = Number(value.startAt) || 0
        t.live = value.live === true
        t.startApplied = false
        pb.session = t
        pb.attempt(value.url)
        return
      }
      pb.fail(kind === "message" ? value.text : why)
    })
  }

  function fail(why) {
    pb.error = String(why || "It couldn't be played.")
    pb.close("error", null)
  }

  // ---- the app hears it -------------------------------------------------
  function event(state, reason) {
    var s = pb.session
    if (!s || s.state !== "playing") return
    var q = pb.queue.slice()
    if (state === "progress") {
      q = q.filter(function(e) { return e.state !== "progress" })   // the newest progress only
    } else if (q.filter(function(e) { return e.state !== "progress" }).length >= 8) {
      pb.fail("the app stopped keeping up")
      return
    }
    q.push({ state: state, reason: reason || "" })
    pb.queue = q
    pb.pump()
  }

  function pump() {
    var s = pb.session
    if (!s || pb.sending || !pb.queue.length || s.state !== "playing") return
    var e = pb.queue[0]
    pb.queue = pb.queue.slice(1)
    s.seq += 1
    var args = { session: s.handle, seq: s.seq, state: e.state, position: pb.position, duration: pb.duration }
    if (e.reason) args.reason = e.reason
    var sent = { id: 0, terminal: false }
    pb.sending = sent
    sent.id = s.rt.call("playback", args, function() {
      if (pb.sending === sent) pb.sending = null
      pb.pump()
    })
  }

  // ---- closing and finalizing ---------------------------------------------
  // reason: user, ended, replaced, error, signOut, appsOff, removed,
  // guideExit, runtime. then: what waits for it to be finalized.
  function close(reason, then) {
    if (then) pb.after = pb.after.concat([then])
    var s = pb.session
    if (reason !== "replaced") { pb.dropPending(); pb.dropWaiting("") }   // stopping, removing, signing out: nothing replaces it
    if (!s) { pb.runAfter(); return }
    if (s.state !== "playing") return   // closing already: then waits with the rest
    s.state = "closing"
    pb.phase = "closing"
    pb.epochs += 1                        // late play / playbackFailed answers: dropped
    progressTimer.stop()
    pb.queue = []
    if (pb.sending && !pb.sending.terminal) { s.rt.cancel(pb.sending.id); pb.sending = null }
    if (s.failedCall) { s.rt.cancel(s.failedCall); s.failedCall = 0 }   // its fallback, if one was being asked for
    if (pb.player) pb.player.pause()
    if (s.rt.phase !== "ready") { pb.finalize(); return }
    s.seq += 1
    var term = { id: 0, terminal: true }
    pb.sending = term
    var done = false
    var finish = function() { if (done) return; done = true; pb.sending = null; pb.finalize() }
    // its 5 s: then it's called off (its requests with it) and finalizing goes on
    terminalTimer.callback = function() { if (!done) s.rt.cancel(term.id); finish() }
    terminalTimer.restart()
    term.id = s.rt.call("playback", { session: s.handle, seq: s.seq, state: "stopped", position: pb.position, duration: pb.duration, reason: reason }, finish)
  }

  // Always, after the last call (or its 5 s): the player, the relay, the
  // lease, gone; then whatever waited
  function finalize() {
    terminalTimer.stop()
    var s = pb.session
    if (!s || s.state === "closed" || s.state === "finalizing") return
    s.state = "finalizing"
    pb.phase = "finalizing"
    pb.retire(function(ok) {
      s.rt.closeRelay(s.handle)
      s.rt.lease("playback", false)
      s.state = "closed"
      pb.phase = ""
      pb.session = null
      pb.buffering = false
      guide.appPlaying = false
      guide.appPlaybackEnded(s.app, pb.error)
      pb.runAfter()
      var next = pb.pendingPlay
      // a replacement only once the old player is really gone, and only for
      // a runtime still running
      if (next && !ok) { pb.dropPending(); guide.appPlaybackEnded(next.app, "The player before didn't let go, so it didn't play.") }
      else if (next && next.rt.phase === "ready") { pb.pendingPlay = null; pb.start(next.app, next.rt, next.value) }
      else if (next) { pb.dropPending(); guide.appPlaybackEnded(next.app, "The app stopped before it could play.") }
    })
  }

  // A play waiting for the TV's buffer, given up (its app's, or any): its relay closed
  function dropWaiting(appId) {
    var w = pb.waitingTv
    if (!w || (appId && w.app !== appId)) return
    pb.waitingTv = null
    if (w.rt.phase === "ready") w.rt.closeRelay(w.value.session)
  }

  // A play that waited and won't happen after all: the relay session its
  // app opened for it is closed (it never started, so no report is owed;
  // a runtime that's stopping or stopped takes it with it, and nothing is
  // sent to one that's gone)
  function dropPending() {
    var p = pb.pendingPlay
    pb.pendingPlay = null
    if (p) p.rt.closeRelay(p.value.session)
  }

  function runAfter() {
    var calls = pb.after
    pb.after = []
    for (var i = 0; i < calls.length; i++) calls[i]()
  }

  // ---- your keys ----------------------------------------------------------
  function togglePause() {
    if (!pb.player || pb.closing) return
    if (pb.player.playbackState === MediaPlayer.PlayingState) pb.player.pause()
    else pb.player.play()
  }

  // Skips add up, and the player is asked at most every 300 ms (as the
  // guide's own: a burst of seeks stalled the shell)
  property real seekTarget: -1
  function seek(seconds) {
    if (!pb.player || pb.closing || !pb.player.seekable) return
    var from = pb.seekTarget >= 0 ? pb.seekTarget : pb.player.position
    pb.seekTarget = Math.max(0, Math.min(pb.player.duration - 1000, from + seconds * 1000))
    if (!seekGap.running) pb.applySeek()
  }
  function applySeek() {
    if (pb.seekTarget < 0) return
    if (pb.player && !pb.closing) {
      pb.player.position = pb.seekTarget
      pb.event("seeked")
    }
    pb.seekTarget = -1
    seekGap.restart()
  }
  Timer {
    id: seekGap
    interval: 300
    onTriggered: pb.applySeek()
  }

  // the runtime stopping on its own: the media stops, and it's said
  function runtimeGone(appId) {
    pb.dropWaiting(appId)
    if (pb.session && pb.session.app === appId && pb.session.state === "playing") {
      pb.error = "The app stopped, so playback did."
      pb.close("runtime", null)
    }
  }

  Timer {
    id: progressTimer
    interval: 10000
    repeat: true
    property real last: -1
    onTriggered: {
      if (!pb.player || pb.paused || pb.closing) return
      if (pb.position !== last) { last = pb.position; pb.event("progress") }
    }
  }

  Timer {
    id: terminalTimer
    interval: 5000
    property var callback: null
    onTriggered: if (callback) callback()
  }

  // the system's sound output now, followed by the players (as the TV's)
  MediaDevices { id: audioDevices }

  Component {
    id: playerKind
    MediaPlayer {
      id: mp
      property string owner: ""
      property int sessionEpoch: 0
      property int attemptId: 0
      property bool dead: false
      property bool failedOnce: false
      signal gone()
      audioOutput: AudioOutput { device: audioDevices.defaultAudioOutput; muted: pb.guide.muted }
      onMediaStatusChanged: pb.onStatus(mp)
      onPlaybackStateChanged: pb.onState(mp)
      onErrorOccurred: function(error, errorString) { pb.onError(mp, errorString) }
      onPositionChanged: pb.onPosition(mp)
      onDurationChanged: pb.onPosition(mp)
      Component.onDestruction: mp.gone()
    }
  }
}
