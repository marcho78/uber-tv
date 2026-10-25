import QtQuick
import "Remote.js" as RemoteRules

// The phone remote's templates (Remote.js): the twelve built in (the
// plugin's remotes/) and yours and agents' (~/.config/om-pg/remotes/, a
// folder of their own, apart from the TV's themes). The default is in
// settings.json (remote.template); each phone's own choice is on its entry
// in remotes.json, which only the phone remote's helper writes, so changing
// one goes through the helper and waits for its answer (setPrefs).
//
// Your templates are read and written only through bin/om-pg-apps
// (remote-list, remote-save, remote-remove: plain files, never through a
// link, under a lock). Once read, every change (a template saved or removed,
// the default, the TV's theme or colors) sends the helper the templates
// resolved with the TV's colors on now, and its revision: open phones fetch
// theirs again and redraw.
Item {
  id: rt

  required property var guide
  readonly property string dir: guide.configDir + "/remotes"
  property var order: ["classic", "minimal", "player", "surfer", "big-buttons", "premium", "techie", "pebble", "swipe", "dock", "glance", "tiles"]

  property var builtIn: ({})          // id → checked template
  property var yours: ({})            // id → checked template
  property var dropped: ({})          // id → what its file had that was dropped
  property var problems: []           // files that aren't templates: [{ id, why }]
  property bool loaded: false
  property bool listOk: false         // the built-in ones and yours were all read the last time (only then is a phone moved off a template that's gone)
  property int loadSeq: 0
  property int rev: 0
  property bool busy: false           // a save or removal is out
  property int req: 0
  property var waiting: ({})          // req → done(answer)
  property var last: null             // the last change to a phone: { req, phone, change, ok, error }
  property var lastSave: null         // the last save or removal: { id, action, ok, outcome, error }
  // stand-ins (tests): helper(command, request, done(res)); reader(done(ok, text))
  property var helper: null
  property var reader: null
  readonly property string busyWhy: "a template is still being saved: try again in a moment"

  readonly property string defaultId: has(guide.remoteTemplate) ? guide.remoteTemplate : "classic"

  // every template, built in first (in their order), then yours by name
  readonly property var list: {
    var out = []
    for (var i = 0; i < order.length; i++) if (builtIn[order[i]]) out.push({ id: order[i], name: builtIn[order[i]].name, description: builtIn[order[i]].description, builtIn: true })
    var mine = Object.keys(yours).map(function(id) { return { id: id, name: yours[id].name, description: yours[id].description, builtIn: false } })
    mine.sort(function(a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0 })
    return out.concat(mine)
  }

  function has(id) { return typeof id === "string" && (!!rt.builtIn[id] || !!rt.yours[id]) }
  function template(id) { return rt.yours[id] || rt.builtIn[id] || null }
  function nameOf(id) { var t = rt.template(id); return t ? t.name : "" }

  // ---- reading -----------------------------------------------------------
  // The built-in ones count only all together: unless every one in order
  // was read and checked, the ones read before stay (nothing is sent until a
  // first good read), no phone is moved off one, and it's tried again soon.
  function load() {
    var mine = ++rt.loadSeq
    retryTimer.stop()
    rt.readBuiltIn(function(readOk1, text) {
      if (mine !== rt.loadSeq) return
      var b = {}, d = {}, probs = []
      var parts = readOk1 ? String(text || "").split("\x1e") : []
      for (var i = 0; i < parts.length; i++) {
        var nl = parts[i].indexOf("\n")
        if (nl < 0) continue
        var m = parts[i].slice(0, nl).match(/\/([a-z0-9][a-z0-9-]{0,31})\.json$/)
        if (!m) continue
        var res = rt.parse(m[1], parts[i].slice(nl + 1))
        if (res.error) { probs.push({ id: m[1], why: res.error }); continue }
        b[m[1]] = res.template
        if (res.dropped.length) d[m[1]] = res.dropped
      }
      if (!readOk1 || !rt.order.every(function(id) { return !!b[id] })) {
        // everything stays as it was: nothing sent, no phone moved
        rt.problems = probs.concat([{ id: "", why: "the built-in templates couldn't all be read: trying again in a moment" }])
        rt.listOk = false
        retryTimer.restart()
        return
      }
      rt.call("remote-list", { dir: rt.dir }, function(listed) {
        if (mine !== rt.loadSeq) return
        // yours couldn't be read this time: the ones read before stay, and no
        // phone on one of them is moved off it
        var readOk = !!listed && listed.ok === true && Array.isArray(listed.templates)
        var y = readOk ? {} : rt.yours
        var files = readOk ? listed.templates : []
        for (var j = 0; j < files.length; j++) {
          var id = files[j] && typeof files[j].id === "string" ? files[j].id : ""
          if (!RemoteRules.ID.test(id)) continue
          if (b[id] || rt.order.indexOf(id) >= 0) { probs.push({ id: id, why: "has a built-in template's id" }); continue }
          var r = rt.parse(id, files[j].text)
          if (r.error) { probs.push({ id: id, why: r.error }); continue }
          y[id] = r.template
          if (r.dropped.length) d[id] = r.dropped
        }
        if (!readOk) { probs.push({ id: "", why: "your templates couldn't be read: " + rt.said(listed, "try again") }); for (var k in rt.dropped) if (y[k]) d[k] = rt.dropped[k] }
        rt.builtIn = b
        rt.yours = y
        rt.dropped = d
        rt.problems = probs
        rt.listOk = readOk
        if (!readOk) retryTimer.restart()
        rt.loaded = true
        rt.send()
        rt.tidyPhones()
      })
    })
  }
  Timer { id: retryTimer; interval: 30000; onTriggered: rt.load() }
  // one file's text: checked, its id the file's name
  function parse(id, text) {
    var given
    try { given = JSON.parse(String(text || "")) } catch (e) { return { error: "isn't JSON" } }
    if (given && typeof given === "object" && !Array.isArray(given)) given.id = id
    return RemoteRules.check(given)
  }

  // ---- sending them to the phones ------------------------------------------
  // Resolved with the TV's colors on now (and again whenever they change)
  function send() {
    if (!rt.loaded) return
    var colors = rt.guide.colors
    var out = {}
    var all = rt.list
    for (var i = 0; i < all.length; i++) out[all[i].id] = RemoteRules.resolve(rt.template(all[i].id), colors)
    rt.rev += 1
    rt.guide.remoteSend({ templates: out, list: all.map(function(t) { return { id: t.id, name: t.name, description: t.description } }), default: rt.defaultId, rev: rt.rev })
  }
  Timer { id: sendTimer; interval: 300; onTriggered: rt.send() }
  function sendSoon() { if (rt.loaded) sendTimer.restart() }

  // ---- the default, and each phone's choices ----------------------------------
  function setDefault(id) {
    if (!rt.has(id)) return { ok: false, error: "no template " + id + " (remoteTemplates lists them)" }
    rt.guide.remoteTemplate = id
    rt.guide.saveSettings()
    rt.send()
    return { ok: true, default: id }
  }

  // A phone's template, number pad or size, saved by the helper (with the
  // phone remote off, there's no helper: refused). done({ ok, error, prefs })
  function setPrefs(phone, change, done) {
    if (!rt.guide.remoteReady) { done({ ok: false, error: "turn on the phone remote first" }); return 0 }
    var n = ++rt.req
    var w = {}
    for (var k in rt.waiting) w[k] = rt.waiting[k]
    w[n] = done
    rt.waiting = w
    var msg = { id: phone }
    for (var c in change) msg[c] = change[c]
    rt.guide.remoteSend({ prefs: msg, req: n })
    deadline.createObject(rt, { req: n })
    return n
  }
  Component {
    id: deadline
    Timer {
      property int req: 0
      interval: 10000
      running: true
      onTriggered: { rt.answered({ done: req, ok: false, error: "the phone remote didn't answer" }); destroy() }
    }
  }
  // The helper's answer to a change: { done: n, ok, error, prefs }
  function answered(m) {
    var f = rt.waiting[m.done]
    if (!f) return
    var w = {}
    for (var k in rt.waiting) if (String(k) !== String(m.done)) w[k] = rt.waiting[k]
    rt.waiting = w
    f({ ok: m.ok === true, error: typeof m.error === "string" ? m.error.slice(0, 160) : "", prefs: m.prefs })
  }
  // Phones on a template that's gone follow the default again
  function tidyPhones() {
    if (!rt.loaded || !rt.listOk || !rt.guide.remoteReady) return
    var ds = rt.guide.remoteDevices || []
    for (var i = 0; i < ds.length; i++) {
      var p = ds[i].prefs || {}
      if (typeof p.template === "string" && !rt.has(p.template)) rt.setPrefs(ds[i].id, { template: null }, function() {})
    }
  }

  // ---- saving and removing (yours only) ------------------------------------------
  // A checked template: replaces yours of that id, or (copy) a new one under
  // a fresh id from it. done({ ok, id, outcome, error })
  function save(t, mode, done) {
    if (rt.busy) { done({ ok: false, error: rt.busyWhy }); return }
    if (rt.builtIn[t.id] && mode !== "copy") { done({ ok: false, error: t.id + " is built in: give yours another id" }); return }
    rt.busy = true
    rt.call("remote-save", { dir: rt.dir, id: t.id, template: t, mode: mode === "copy" ? "copy" : "replace" }, function(res) {
      rt.busy = false
      var ok = !!res && res.ok === true && (res.outcome === "saved" || res.outcome === "unconfirmed")
      done({ ok: ok, id: ok ? res.id : "", outcome: ok ? res.outcome : "failed", error: ok ? "" : rt.said(res, "it couldn't be saved") })
      if (ok) rt.load()
    })
  }
  // One of yours taken away: the default goes back to Classic if it was the
  // default, and the phones on it follow the default. done({ ok, error })
  function remove(id, done) {
    if (rt.busy) { done({ ok: false, error: rt.busyWhy }); return }
    if (rt.builtIn[id]) { done({ ok: false, error: id + " is built in: it can't be removed" }); return }
    if (!rt.yours[id]) { done({ ok: false, error: "no template " + id + " of yours (remoteTemplates lists them)" }); return }
    rt.busy = true
    rt.call("remote-remove", { dir: rt.dir, id: id }, function(res) {
      rt.busy = false
      var ok = !!res && res.ok === true && (res.outcome === "saved" || res.outcome === "unconfirmed")
      if (ok) {
        if (rt.guide.remoteTemplate === id) { rt.guide.remoteTemplate = "classic"; rt.guide.saveSettings() }
        var y = {}
        for (var k in rt.yours) if (k !== id) y[k] = rt.yours[k]
        rt.yours = y
        rt.send()
        rt.tidyPhones()
        rt.load()
      }
      done({ ok: ok, error: ok ? "" : rt.said(res, "it couldn't be removed") })
    })
  }
  function said(res, otherwise) {
    var w = res && typeof res.why === "string" ? res.why : res && typeof res.error === "string" ? res.error : ""
    return w && w.indexOf("/") < 0 ? w.slice(0, 120) : otherwise
  }

  // ---- the helper and the files -------------------------------------------------
  property var runKind: null
  function newRun(opts) {
    if (!rt.runKind) rt.runKind = Qt.createComponent(Qt.resolvedUrl("ui/Run.qml"))
    return rt.runKind.createObject(rt, opts)
  }
  function call(command, request, done) {
    if (rt.helper) { rt.helper(command, request, done); return }
    var r = rt.newRun({ timeoutMs: 30000, maxBytes: 8 * 1024 * 1024, okCodes: [0, 1], splitMarker: "\n" })
    r.finished.connect(function(ok, output) {
      var res
      try { res = JSON.parse(String(output).trim().split("\n").pop()) } catch (e) { res = { ok: false, outcome: "failed", why: "" } }
      done(res)
      Qt.callLater(function() { r.destroy() })
    })
    r.start(["/usr/bin/python3", rt.guide.apps.helper, command], JSON.stringify(request))
  }
  // the built-in templates, in one go: "\x1e<path>\n<its JSON>"
  function readBuiltIn(done) {
    if (rt.reader) { rt.reader(done); return }
    var r = rt.newRun({ timeoutMs: 15000, maxBytes: 4 * 1024 * 1024, splitMarker: "\n" })
    r.finished.connect(function(ok, output) {
      done(ok, ok ? output : "")
      Qt.callLater(function() { r.destroy() })
    })
    r.start(["/usr/bin/sh", "-c", "PATH=/usr/bin; for f in \"$1\"/*.json; do [ -f \"$f\" ] || continue; printf '\\036%s\\n' \"$f\"; head -c 65536 -- \"$f\"; done",
             "sh", rt.guide.pluginDir + "/remotes"])
  }
}
