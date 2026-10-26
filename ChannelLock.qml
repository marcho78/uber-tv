import QtQuick
import "ChannelLock.js" as LockRules

// The channel lock (ChannelLock.js): a passcode you set
// once, and channels it protects. Its state comes from the helper
// (bin/om-pg-apps lock-read), which keeps the passcode only as a hash in
// ~/.config/om-pg/lock.json and checks each one typed (lock-check); the
// guide never keeps a passcode after its check. Tuning a blocked channel is
// refused (Guide.qml tune), and your actions ask here first. Until the lock
// has been read, every channel is blocked (a lock that can't be read never
// counts as off). The box (ui/LockBox.qml, guide.dialog lockCode,
// lockSettings, lockChannels) is only yours: the keys, the mouse, your paired
// phone; closing it, cancelling, or Uber TV closing abandons it, and an
// answer that comes back for an abandoned one is dropped (gen).
Item {
  id: lock

  required property var guide
  property string helper: ""          // bin/om-pg-apps
  property string file: ""            // lock.json
  // for the tests: runner(cmd, req, done(res)) instead of the helper (cmd
  // "auth" is the computer's password)
  property var runner: null

  // what the helper says (never the hash)
  property bool loaded: false         // read at least once
  property string failed: ""          // why it couldn't be read ("" if it could)
  property bool set: false
  property bool on: false
  property var entries: []            // [{ url, name }]
  property var unlockFor: "tv"
  property bool titles: false
  property int wait: 0                // seconds before another try counts

  readonly property var idx: LockRules.index(lock.entries, lock.guide.channels)
  property var unlocked: ({})         // address → until (0: until the TV is off)

  // something that decides what may play changed: the guide checks the
  // channel that's on (Guide.qml enforceLock)
  signal recheck()

  // A channel on the list, with the lock on (agents see this); before the
  // lock's been read, every one
  function isLocked(ch) { return !!ch && (!lock.loaded || (lock.on && LockRules.isLocked(lock.idx, ch))) }
  // Locked and not unlocked: it doesn't play
  function blocks(ch) { return !!ch && (!lock.loaded || LockRules.blocks(lock.on, lock.idx, lock.unlocked, ch, Date.now() / 1000)) }
  // The TV turned off: every unlock that lasts until then ends
  function relock() {
    var keep = {}
    for (var u in lock.unlocked) if (lock.unlocked[u] !== 0) keep[u] = lock.unlocked[u]
    lock.unlocked = keep
  }
  onUnlockedChanged: { lock.recheck(); lock.schedule() }

  // A timed unlock running out: the timer is set for the soonest one (four
  // hours at most, well within a timer), and set again every time it fires
  // or the unlocks change, so it never stops while one is still running;
  // the ones run out are pruned, and the channel on is checked again
  property alias expiryTimer: expiry
  function schedule() {
    var next = LockRules.nextExpiry(lock.unlocked, 0)
    if (next <= 0) { expiry.stop(); return }
    expiry.interval = Math.max(500, Math.round((next - Date.now() / 1000) * 1000 + 250))
    expiry.restart()
  }
  Timer {
    id: expiry
    repeat: false
    onTriggered: { lock.unlocked = LockRules.pruned(lock.unlocked, Date.now() / 1000); lock.schedule() }
  }

  // ---- the helper ----
  function run(cmd, req, done) {
    var finish = function(res) {
      if (res && res.ok && res.set !== undefined) lock.take(res)
      done(res || {})
    }
    if (lock.runner) { lock.runner(cmd, req, finish); return }
    var r = lock.newRun({ timeoutMs: 30000, maxBytes: 2 * 1024 * 1024, okCodes: [0, 1], splitMarker: "\n" })
    if (!r) { finish({ ok: false, error: "the helper couldn't be started" }); return }
    r.finished.connect(function(ok, output) {
      var res
      try { res = JSON.parse(String(output).trim().split("\n").pop()) } catch (e) { res = { ok: false, error: "the helper's answer couldn't be read" } }
      finish(res)
      Qt.callLater(function() { r.destroy() })
    })
    r.start(["/usr/bin/python3", lock.helper, cmd], JSON.stringify(Object.assign({ file: lock.file }, req)))
  }
  // made when needed, so this file loads without the shell (the tests)
  function newRun(props) {
    var c = Qt.createComponent("ui/Run.qml")
    return c.status === Component.Ready ? c.createObject(lock, props) : null
  }
  // The computer's password, through the system's usual prompt (pkexec, as
  // the firewall change asks): done(true) only if it was given; otherwise
  // done(false, why): "unavailable" when no prompt could be shown (no
  // prompt program, no password agent), "refused" when it wasn't given. The guide
  // asks through Authorize.qml (one prompt at a time), which runs this.
  function auth(done) {
    if (lock.runner) { lock.runner("auth", {}, function(res) { done(!!res && res.ok === true, res && res.why || "refused") }); return }
    var r = lock.newRun({ timeoutMs: 180000, maxBytes: 64 * 1024, okCodes: [0] })
    if (!r) { done(false, "unavailable"); return }
    r.finished.connect(function(ok, output) {
      done(ok, ok ? "" : /No authentication agent|failed to execute|No such file|not found/i.test(String(output)) ? "unavailable" : "refused")
      Qt.callLater(function() { r.destroy() })
    })
    r.start(["/usr/bin/pkexec", "/usr/bin/true"])
  }

  // the helper's words, as a sentence
  function said(res, otherwise) {
    var t = res && typeof res.error === "string" && res.error ? res.error : otherwise
    return t.charAt(0).toUpperCase() + t.slice(1) + (/[.!?]$/.test(t) ? "" : ".")
  }

  function take(res) {
    lock.set = res.set === true
    lock.on = res.on === true
    lock.entries = Array.isArray(res.channels) ? res.channels : []
    lock.unlockFor = res.unlockFor === 60 || res.unlockFor === 240 ? res.unlockFor : "tv"
    lock.titles = res.titles === true
    lock.wait = Math.max(0, Number(res.wait) || 0)
    lock.failed = ""
    lock.loaded = true
    lock.recheck()
  }

  // Read again; until a read works, it's tried every few seconds (and every
  // channel stays blocked meanwhile)
  function read() {
    lock.run("lock-read", {}, function(res) {
      if (!res.ok) lock.failed = lock.said(res, "it couldn't be read")
    })
  }
  Timer {
    interval: 5000
    repeat: true
    running: !lock.loaded
    onTriggered: lock.read()
  }
  Component.onCompleted: Qt.callLater(lock.read)

  function save(changes, done) {
    lock.run("lock-save", changes, function(res) {
      if (!res.ok) lock.note = lock.said(res, "it couldn't be saved")
      if (done) done(res)
    })
  }

  // ---- the box ----
  readonly property bool boxUp: ["lockCode", "lockSettings", "lockChannels"].indexOf(lock.guide.dialog) >= 0
  // the code box's step: unlock (to watch), enter (to change the lock), new
  // and again (setting one), current, change and changeAgain (changing it),
  // reset (forgotten, or can't be read), unavailable (not read yet)
  property string step: ""
  property string code: ""            // what's typed: never kept after a step
  property string first: ""           // a new passcode, until it's typed again
  property string old: ""             // the passcode now, for a change
  property string problem: ""
  property bool busy: false
  property bool authBusy: false       // the computer's password prompt is up
  property var then: null             // what to do once it's right
  property var target: null           // the channel being unlocked
  property string note: ""            // the settings' last word ("Passcode changed")
  property int cursor: 0
  property int listCursor: 0
  property string query: ""
  property string back: ""            // the box Esc goes back to ("" closes)
  property int gen: 0                 // which session: an answer for an older one is dropped

  function forget() { lock.code = ""; lock.first = ""; lock.old = "" }

  // The whole session ends: nothing typed, nothing pending, the box closed
  function abandon() {
    lock.gen += 1
    lock.forget()
    lock.then = null
    lock.target = null
    lock.step = ""
    lock.back = ""
    lock.problem = ""
    lock.busy = false
    lock.note = ""
    lock.query = ""
    if (lock.boxUp) lock.guide.dialog = ""
  }

  // Asks in the code box; then() once it's right (back: the box Esc goes
  // back to, "" to close it)
  function ask(step, then, target, back) {
    lock.gen += 1
    lock.forget()
    lock.step = step
    lock.then = then || null
    lock.target = target || null
    lock.problem = ""
    lock.busy = false
    lock.back = back || ""
    lock.guide.dialog = "lockCode"
    if (lock.loaded) lock.read()
  }

  // A blocked channel you asked for: the passcode, then it plays (then); or,
  // before the lock's been read, why nothing plays. True if it asked
  function askUnlock(ch, then) {
    if (!lock.loaded) { lock.ask(lock.failed ? "reset" : "unavailable", null, null, ""); return true }
    if (!lock.set) return false
    lock.ask("unlock", then, ch, "")
    return true
  }

  // Settings → Live TV → Channel lock: a passcode set first, or asked for
  function openSettings() {
    if (!lock.loaded) { lock.ask(lock.failed ? "reset" : "unavailable", null, null, ""); return }
    if (!lock.set) lock.ask("new", lock.showSettings, null, "")
    else lock.ask("enter", lock.showSettings, null, "")
  }
  function showSettings() {
    lock.note = ""
    lock.guide.dialog = "lockSettings"
    lock.cursor = Math.min(lock.cursor, lock.rows.length - 1)
  }

  // L in the guide: these channels locked (or unlocked, if all are), after
  // the passcode (one set first if there's none); locking turns the lock on
  function toggleChannels(chans) {
    chans = chans.filter(function(c) { return !!c })
    if (!chans.length) return
    if (!lock.loaded) { lock.ask(lock.failed ? "reset" : "unavailable", null, null, ""); return }
    var doIt = function() {
      var lockThem = chans.some(function(c) { return !LockRules.isLocked(lock.idx, c) })
      var changes = { channels: LockRules.setLocked(lock.entries, chans, lockThem, lock.guide.channels) }
      if (lockThem) changes.on = true
      lock.save(changes)
      lock.abandon()
    }
    if (!lock.set) lock.ask("new", doIt, null, "")
    else lock.ask("enter", doIt, null, "")
  }

  function close() { lock.abandon() }

  // Esc in the code box: back where it came from (the settings), or closed
  function cancel() {
    if (lock.guide.dialog !== "lockCode" || !lock.back) { lock.abandon(); return }
    lock.gen += 1
    lock.forget()
    lock.problem = ""
    lock.busy = false
    lock.guide.dialog = lock.back
  }

  // Right: the box goes, and on with what you were doing
  function done() {
    var then = lock.then
    lock.forget()
    lock.then = null
    lock.target = null
    if (lock.guide.dialog === "lockCode") lock.guide.dialog = ""
    if (then) then()
  }

  function submit() {
    if (lock.busy || lock.authBusy) return
    if (lock.step === "unavailable") { lock.abandon(); return }
    if (lock.step === "reset") { lock.reset(); return }
    if (!LockRules.complete(lock.code)) return
    var code = lock.code
    var g = lock.gen
    lock.code = ""
    lock.problem = ""
    if (lock.step === "new" || lock.step === "change") {
      lock.first = code
      lock.step = lock.step === "new" ? "again" : "changeAgain"
      return
    }
    if (lock.step === "again" || lock.step === "changeAgain") {
      if (code !== lock.first) {
        lock.problem = "They weren't the same. Type the new passcode again, twice."
        lock.first = ""
        lock.step = lock.step === "again" ? "new" : "change"
        return
      }
      var req = { code: code }
      if (lock.step === "changeAgain") req.old = lock.old
      var first = lock.step === "again"
      lock.busy = true
      lock.run("lock-passcode", req, function(res) {
        if (g !== lock.gen) return
        lock.busy = false
        if (!res.ok) { lock.problem = lock.said(res, "it couldn't be set"); lock.forget(); lock.step = first ? "new" : "current"; return }
        if (first) { lock.save({ on: true }); lock.done() }
        else { lock.forget(); lock.showSettings(); lock.note = "Passcode changed." }
      })
      return
    }
    // unlock, enter, current: checked by the helper
    lock.busy = true
    lock.run("lock-check", { code: code }, function(res) {
      if (g !== lock.gen) return
      lock.busy = false
      if (res.ok !== true) {
        lock.problem = lock.said(res, "that's not the passcode")
        if (res.wait) lock.wait = res.wait
        return
      }
      lock.wait = 0
      if (lock.step === "current") { lock.old = code; lock.step = "change"; return }
      if (lock.step === "unlock" && lock.target) {
        var u = Object.assign({}, lock.unlocked)
        u[lock.target.url] = LockRules.unlockUntil(lock.unlockFor, Date.now() / 1000)
        lock.unlocked = u
      }
      lock.done()
    })
  }

  // Forgotten (or a lock that can't be read): the computer's password, then
  // no passcode, nothing locked, the lock off
  function reset() {
    var g = lock.gen
    lock.problem = ""
    lock.authBusy = true
    var answered = function(given, why) {
      lock.authBusy = false
      if (g !== lock.gen) return
      if (!given) { lock.problem = why === "unavailable" ? "Nothing was reset: the computer's password prompt can't be shown here." : why === "busy" ? "Nothing was reset: the computer's password is being asked for already." : "Nothing was reset: the computer's password wasn't given."; return }
      lock.busy = true
      lock.run("lock-reset", {}, function(res) {
        if (g !== lock.gen) return
        lock.busy = false
        if (!res.ok) { lock.problem = lock.said(res, "it couldn't be reset"); return }
        lock.unlocked = ({})
        lock.abandon()
      })
    }
    // one prompt at a time: through the guide's (Authorize.qml) when there is one
    if (lock.guide.authorize) lock.guide.authorize("lockReset", null, answered, function() { return g === lock.gen })
    else lock.auth(answered)
  }

  // a wait counts down on screen
  Timer {
    interval: 1000
    repeat: true
    running: lock.wait > 0 && lock.guide.dialog === "lockCode"
    onTriggered: { lock.wait = Math.max(0, lock.wait - 1); if (lock.wait === 0 && /wait/i.test(lock.problem)) lock.problem = "" }
  }

  readonly property string title: lock.step === "unlock" ? "Locked channel"
                                : lock.step === "enter" ? "Enter the passcode"
                                : lock.step === "new" ? "Set a passcode"
                                : lock.step === "again" ? "Type it again"
                                : lock.step === "current" ? "The passcode now"
                                : lock.step === "change" ? "A new passcode"
                                : lock.step === "changeAgain" ? "Type the new one again"
                                : lock.step === "reset" ? (lock.failed ? "The channel lock can't be read" : "Forgot the passcode?")
                                : lock.step === "unavailable" ? "Channel lock" : ""
  readonly property string prompt: lock.step === "unlock" ? (lock.target ? lock.target.name : "This channel") + " is locked. Enter the passcode to watch it."
                                 : lock.step === "enter" ? "The channel lock's passcode."
                                 : lock.step === "new" ? "4 to 8 digits. It's asked for to watch a locked channel and to change the lock. Only a scrambled form of it is kept, in a file only you can read."
                                 : lock.step === "again" ? "The same digits again, to be sure."
                                 : lock.step === "current" ? "The passcode you have now."
                                 : lock.step === "change" ? "4 to 8 digits."
                                 : lock.step === "changeAgain" ? "The same digits again."
                                 : lock.step === "reset" ? (lock.failed ? lock.failed + " Until it can be read, no channel plays. " : "")
                                                           + "Resetting forgets the passcode and the locked channels, and turns the lock off. It asks for this computer's password first, so a child can't do it."
                                 : lock.step === "unavailable" ? "Checking the channel lock. Try again in a moment." : ""
  readonly property bool typing: ["unlock", "enter", "new", "again", "current", "change", "changeAgain"].indexOf(lock.step) >= 0

  // ---- the settings ----
  readonly property var rows: [
    { key: "on", label: "Channel lock", kind: "switch" },
    { key: "change", label: "Change the passcode", kind: "opens" },
    { key: "channels", label: "Locked channels", kind: "opens" },
    { key: "unlock", label: "Unlocks last", kind: "choice" },
    { key: "titles", label: "Show titles of locked channels", kind: "switch" }
  ]
  readonly property int gone: LockRules.missing(lock.entries, lock.guide.channels).length
  function rowValue(key) {
    if (key === "channels") return (lock.entries.length - lock.gone) + (lock.entries.length - lock.gone === 1 ? " channel" : " channels")
                                   + (lock.gone ? " · " + lock.gone + " not in your channels" : "")
    if (key === "unlock") return LockRules.unlockLabel(lock.unlockFor)
    return ""
  }
  function rowOn(key) { return key === "on" ? lock.on : key === "titles" ? lock.titles : false }
  readonly property string rowNote: {
    var key = (lock.rows[lock.cursor] || {}).key
    if (lock.note) return lock.note
    if (key === "on") return "Off, nothing is locked; the passcode and the list stay."
    if (key === "change") return "The passcode now, then the new one twice."
    if (key === "channels") return "Your channels, with a search: Enter locks or unlocks one. L does the same in the guide, where you manage channels (E)."
    if (key === "unlock") return "Once you've typed the passcode for a channel, how long it stays open."
    if (key === "titles") return "Off, a locked channel's shows say Locked in the guide."
    return ""
  }
  function act(key) {
    lock.note = ""
    if (key === "on") lock.save({ on: !lock.on })
    else if (key === "change") lock.ask("current", null, null, "lockSettings")
    else if (key === "channels") { lock.query = ""; lock.listCursor = 0; lock.guide.dialog = "lockChannels" }
    else if (key === "unlock") lock.save({ unlockFor: LockRules.nextUnlock(lock.unlockFor) })
    else if (key === "titles") lock.save({ titles: !lock.titles })
  }

  // ---- the list of channels ----
  readonly property var listed: lock.guide.dialog === "lockChannels" ? LockRules.listed(lock.guide.channels, lock.guide.numbers, lock.idx, lock.query) : []
  function toggleListed() {
    var it = lock.listed[lock.listCursor]
    if (!it) return
    var ch = lock.guide.channels[it.row]
    var changes = { channels: LockRules.setLocked(lock.entries, [ch], !it.locked, lock.guide.channels) }
    if (!it.locked) changes.on = true
    lock.save(changes)
  }

  // ---- keys and the phone ----
  function key(event) {
    var k = event.key
    var d = lock.guide.dialog
    if (d === "lockCode") {
      // while a passcode is being checked, Esc still backs out (its answer is dropped)
      if (lock.busy || lock.authBusy) { if (k === Qt.Key_Escape && !lock.authBusy) lock.cancel(); return }
      if (k === Qt.Key_Escape) lock.cancel()
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) lock.submit()
      else if (!lock.typing) return
      else if (k === Qt.Key_Backspace) lock.code = LockRules.typed(lock.code, "back")
      else if (k === Qt.Key_F && (lock.step === "unlock" || lock.step === "enter" || lock.step === "current")) { lock.forget(); lock.problem = ""; lock.step = "reset"; lock.back = "" }
      else if (/^[0-9]$/.test(event.text)) { lock.code = LockRules.typed(lock.code, event.text); if (lock.wait === 0) lock.problem = "" }
      return
    }
    if (d === "lockSettings") {
      if (k === Qt.Key_Up) { lock.cursor = Math.max(0, lock.cursor - 1); lock.note = "" }
      else if (k === Qt.Key_Down) { lock.cursor = Math.min(lock.rows.length - 1, lock.cursor + 1); lock.note = "" }
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Right || k === Qt.Key_Space) lock.act(lock.rows[lock.cursor].key)
      else if (k === Qt.Key_Escape || k === Qt.Key_Left || k === Qt.Key_Backspace) lock.close()
      return
    }
    if (d === "lockChannels") {
      var n = lock.listed.length
      if (k === Qt.Key_Up) lock.listCursor = Math.max(0, lock.listCursor - 1)
      else if (k === Qt.Key_Down) lock.listCursor = Math.min(Math.max(0, n - 1), lock.listCursor + 1)
      else if (k === Qt.Key_PageUp) lock.listCursor = Math.max(0, lock.listCursor - 8)
      else if (k === Qt.Key_PageDown) lock.listCursor = Math.min(Math.max(0, n - 1), lock.listCursor + 8)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) lock.toggleListed()
      else if (k === Qt.Key_Escape) { if (lock.query) { lock.query = ""; lock.listCursor = 0 } else lock.showSettings() }
      else if (k === Qt.Key_Backspace) { lock.query = lock.query.slice(0, -1); lock.listCursor = 0 }
      else if (event.text && event.text.length === 1 && event.text >= " " && lock.query.length < 40) { lock.query += event.text; lock.listCursor = 0 }
    }
  }

  // The paired phone's buttons, as the keys; its number pad's passcode
  // (digits, as text), typed in at once
  function remote(cmd, digits) {
    if (cmd === "code") {
      var d = String(digits === undefined || digits === null ? "" : digits)
      if (lock.guide.dialog === "lockCode" && lock.typing && !lock.busy && LockRules.complete(d)) { lock.code = d; lock.submit() }
      return
    }
    var keyOf = { up: Qt.Key_Up, down: Qt.Key_Down, left: Qt.Key_Left, right: Qt.Key_Right, ok: Qt.Key_Return, back: Qt.Key_Escape }
    if (keyOf[cmd] !== undefined) lock.key({ key: keyOf[cmd], text: "" })
  }

  // (tablet mode: buttons in the lock's box, ui/LockBox.qml, with its pad
  // for the digits; rows are tapped)
  readonly property var hints: lock.guide.dialog === "lockCode"
    ? (lock.typing ? [{ keys: ["0", "–", "9"], label: "Type" }, { keys: ["⌫"], label: "Erase" }, { keys: ["ENTER"], label: "OK" }]
                     .concat(lock.step === "unlock" || lock.step === "enter" || lock.step === "current" ? [{ keys: ["F"], label: "Forgot it", touch: { key: Qt.Key_F } }] : [])
                     .concat([{ keys: ["ESC"], label: "Cancel", touch: { key: Qt.Key_Escape, back: true } }])
       : lock.step === "reset" ? [{ keys: ["ENTER"], label: "Reset (asks for the computer's password)", touch: { key: Qt.Key_Return, primary: true } }, { keys: ["ESC"], label: "Cancel", touch: { key: Qt.Key_Escape, back: true } }]
       : [{ keys: ["ENTER", "/", "ESC"], label: "Close", touch: { key: Qt.Key_Escape, back: true } }])
    : lock.guide.dialog === "lockChannels"
    ? [{ keys: ["↑", "↓"], label: "Pick" }, { keys: ["ENTER"], label: "Lock or unlock" }, { keys: ["TYPE"], label: "Search" }, { keys: ["ESC"], label: "Back", touch: { key: Qt.Key_Escape, back: true } }]
    : [{ keys: ["↑", "↓"], label: "Pick" }, { keys: ["ENTER"], label: "Change" }, { keys: ["ESC"], label: "Close", touch: { key: Qt.Key_Escape, back: true } }]
}
