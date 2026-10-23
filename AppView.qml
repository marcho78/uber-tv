import QtQuick
import "AppNav.js" as Nav
import "AppLooks.js" as Looks

// An app with code on the screen (ui/AppScreen.qml draws it): its screens
// on a stack, the first from its home, each new one pushed (Esc pops; at
// the first, back to Apps). Every navigation is a new view epoch: an answer
// for an epoch that's over (you went back, or somewhere else, or the app
// started again) is dropped, and so is one from a runtime that isn't this
// app's now. While a call is out, the screen you're on stays, under
// "Loading" (Esc calls it off). A screen that asks for it comes again every
// so often, your place kept. Its settings page: the app's own settings, its
// server, signing in, clearing its data; a change starts the app again,
// from its first screen. Only you, at the screen, do any of it (by).
//
// Every view records how it may be loaded again: one from home, browse,
// details or search has a read-only reload (the same call); one from a
// button (action), play or sign-in has none and is never asked again (R
// says so, a refresh doesn't run). The pictures a view names are held in
// the helper by its result id until the view goes (popped, replaced, or
// let go to make room), when the guide drops it. At most 20 views, and with
// the app's Home rows at most 4,000 pictures held in its helper: past that,
// the oldest views with a reload let go first and load again when shown,
// then the oldest without one leave the history (Back goes to the one
// before it).
Item {
  id: view

  required property var guide
  readonly property var apps: guide.apps

  property string appId: ""
  readonly property var record: appId ? apps.record(appId) : null
  property var rt: null
  property var stack: []              // [{ kind, value, item, method, args, sel, result, reload, tokens, stale, recovered }]
  property int epoch: 0
  property var pending: null          // the call the screen waits for: { id, epoch, method, args, mode, rt }
  property var refreshing: null       // a refresh out (nothing waits for it)
  property bool waitingStart: false   // the runtime is starting: the first screen comes once it's ready
  property var waitingFor: null       // the agent's open that first screen is for (null: yours)
  property bool restarting: false
  property string failed: ""          // the first screen couldn't come: why (Enter tries again)
  property string message: ""         // the app's, or what went wrong, over the screen for a moment
  property bool messageBad: false
  // image token -> its local path, "" while it comes, or why it can't be shown:
  // "-failed" (it couldn't be fetched: tried once more the next time it's
  // shown), "-refused" (the rules won't fetch it), "-gone" (let go, and the
  // view can't load again), "-broken" (fetched again, and still not drawn).
  // At most 2,000.
  property var imagePaths: ({})
  property var imageInfo: ({})        // image token -> { w, h } from its header (0 when not known), at (when the helper last gave it)
  property var pathOrder: []          // the tokens in imagePaths, oldest first
  // the pictures the cards on the screen want: token -> { focus, visible, rest } (how many cards want it at each)
  property var wanted: ({})
  property var retried: ({})          // failed pictures tried once more (the next time they're shown)
  property var brokenRetried: ({})    // pictures fetched again once because their file couldn't be drawn
  property var recoveredAt: []        // when reloads for pictures the helper had let go ran (at most 6 a minute)
  property real screenWidth: 0        // the width the screen draws its lines in (AppScreen says)
  // The presentation model (AppLooks.js): every line's layout, picture
  // shape, card size and columns, read by the drawing and the arrows alike
  readonly property var model: Looks.model(view.topView, view.envNow())
  // typing: { type: "search"|"text"|"secret"|"server", key, label, text }
  property var editing: null
  property bool settingsOpen: false
  property int settingsCursor: 0
  property string armed: ""           // Clear its data, waiting for its second Enter
  property string settingsNote: ""
  // signing in: { flow, code, url, expires (when, ms), qr (a picture's path) }
  property var signIn: null
  property var certOffer: null        // a certificate to pin: { sha256, verified }
  property string cameFrom: "apps"    // where Esc at its first screen goes: apps, or home
  property var queued: null           // what to ask once its first screen is in: { method, args }
  readonly property var topView: stack.length ? stack[stack.length - 1] : null
  // the top view's selection: moving changes only this (and the view's own
  // copy), so the model and what's drawn aren't remade on every arrow
  property var sel: null
  onTopViewChanged: {
    view.pageY = 0   // an article page starts at its top
    view.sel = view.topView ? view.topView.sel : null
    view.bumpDemand()
    if (view.topView && view.topView.stale && !view.pending) Qt.callLater(view.restoreTop)
  }
  onSelChanged: view.bumpDemand()
  onRtChanged: view.bumpDemand()
  readonly property bool loading: pending !== null || (waitingStart && !failed)
  readonly property bool shown: guide.opened && guide.screen === "app" && !guide.watching

  // An agent's open (AppAgent.openApp), while it's live: { guard }, where
  // guard() says, right before every call the view sends for it, why that
  // call mustn't go ("" if it may). One is live at a time. Each step it takes
  // later (its first screen once the app has started, its item once that's
  // in) carries the open it's for, and goes only while that very open is
  // still the live one: you doing anything yourself, a newer open, leaving
  // the app, or a mismatch ends it, and nothing of it is ever sent unchecked.
  property var agentOpen: null
  function userActs() {
    view.agentOpen = null
    if (view.queued && view.queued.agent) view.queued = null
  }

  // ---- opening and leaving ------------------------------------------------
  function open(id, by) {
    if (by !== guide.byUser) return "only the user, at the screen"
    view.userActs()
    var why = apps.cannotOpen(id)
    if (why) { apps.status = "Couldn't open it: " + why + "."; return why }
    apps.clearFault(id)   // you opening it is what tries a stopped app again
    if (view.appId && view.appId !== id) view.leave(true)
    view.cameFrom = "apps"
    view.queued = null
    var again = view.appId === id && view.stack.length > 0 && view.rt && view.rt.phase === "ready"
    view.appId = id
    guide.codeApp = id
    guide.dialog = ""
    guide.screen = "app"
    view.settingsOpen = false
    view.editing = null
    view.message = ""
    apps.used(id)
    if (again) { view.rt.lease("foreground", true); view.scheduleRefresh(); return "ok" }
    view.reset()
    view.loadRoot()
    return "ok"
  }

  function reset() {
    view.epoch += 1
    view.release(view.stack)
    view.stack = []
    if (view.pending && view.pending.rt) view.pending.rt.cancel(view.pending.id)
    view.pending = null
    view.cancelRefresh()
    view.failed = ""
    view.imagePaths = ({})
    view.imageInfo = ({})
    view.pathOrder = []
    view.retried = ({})
    view.brokenRetried = ({})
    view.certOffer = null
    view.waitingStart = false
    view.waitingFor = null
    refreshTimer.stop()
  }

  // ---- what views hold in the helper ----------------------------------------
  // How a view may be loaded again: the same call, for one that only reads
  // (home, browse, details, search); none for a button, play or sign-in
  function reloadOf(method, args) {
    return ["home", "browse", "details", "search"].indexOf(method) >= 0 ? { method: method, args: args || {} } : null
  }

  // The picture tokens a screen, details or row names, each once
  function tokensIn(v) {
    var seen = Object.create(null)
    var out = []
    var add = function(img) { if (img && typeof img.token === "string" && !seen[img.token]) { seen[img.token] = true; out.push(img.token) } }
    var items = function(list) {
      ;(Array.isArray(list) ? list : []).forEach(function(it) {
        if (!it) return
        add(it.image)
        var pics = it.images && typeof it.images === "object" ? it.images : {}
        for (var k in pics) add(pics[k])
      })
    }
    if (!v) return out
    if (Array.isArray(v)) { items(v); return out }
    add(v.image)
    add(v.backdrop)
    add(v.logo)
    ;(v.rows || []).forEach(function(r) { items(r && r.items) })
    return out
  }

  // Views gone: the helper may let go of what only they held
  function release(views) {
    var ids = (views || []).filter(function(v) { return v && v.result > 0 }).map(function(v) { return v.result })
    if (ids.length && view.rt) view.rt.release(ids)
  }

  // A view that let go of its pictures to make room: what's needed to load
  // it again (its reload) and to put you back where you were
  function staleOf(v) {
    return { kind: v.kind, value: null, item: v.item, method: v.method, args: v.args, sel: v.sel, result: 0,
             reload: v.reload, tokens: 0, stale: true, recovered: false }
  }

  // At most 20 views (the first stays), and at most 4,000 pictures held in
  // the helper with what the app's Home rows hold: past that, the oldest
  // views with a reload let go first, then the oldest without one leave the
  // history. The view on the screen keeps what it has.
  function trim() {
    var s = view.stack.slice()
    var gone = []
    while (s.length > 20) gone.push(s.splice(1, 1)[0])
    var budget = 4000 - (guide.appHome && view.rt ? guide.appHome.heldBy(view.rt) : 0)
    var held = function() { return s.reduce(function(n, v) { return n + (v.stale ? 0 : v.tokens || 0) }, 0) }
    while (held() > budget) {
      var i = -1
      for (var k = 0; k < s.length - 1 && i < 0; k++) if (s[k].reload && !s[k].stale && s[k].tokens > 0) i = k
      if (i >= 0) { gone.push(s[i]); s[i] = view.staleOf(s[i]); continue }
      for (k = 0; k < s.length - 1 && i < 0; k++) if (!s[k].reload && s[k].tokens > 0) i = k
      if (i < 0) break
      gone.push(s.splice(i, 1)[0])
    }
    if (gone.length) { view.release(gone); view.stack = s }
  }

  // The view on the screen let go of its pictures earlier: loaded again from
  // its reload, your place kept
  function restoreTop() {
    var top = view.topView
    if (!top || !top.stale || view.pending || !top.reload) return
    view.ask(top.reload.method, top.reload.args, "restore")
  }

  // A refresh no one waits for any more: called off, not just ignored
  function cancelRefresh() {
    var p = view.refreshing
    view.refreshing = null
    if (p && p.rt) p.rt.cancel(p.id)
  }

  // Esc at the first screen: back to Apps (forget: the app is left behind)
  function leave(forget) {
    view.userActs()
    view.cancelSignIn()
    if (view.rt) view.rt.lease("foreground", false)
    if (view.pending && view.pending.rt) view.pending.rt.cancel(view.pending.id)
    view.pending = null
    view.cancelRefresh()
    if (forget) {
      view.reset()
      view.rt = null
      view.appId = ""
      guide.codeApp = ""
    }
  }

  function close() {
    var to = view.cameFrom
    view.leave(true)
    if (to === "home") guide.openHome()
    else guide.openApps(true)
  }

  // An agent's open: the user's steps in the same order (leave another app,
  // switch to the app's screen, start it), but it never clears a fault and
  // never closes a box, and guard() runs again right before every call it
  // sends: home, then browse or details for the item (read-only, never play,
  // a button, sign-in or settings), including one sent later, once the app
  // has started. A mismatch fails it, and nothing is sent again into a new
  // generation. Answers "" or why it couldn't start.
  function openForAgent(id, item, guard) {
    if (view.appId && view.appId !== id) view.leave(true)
    view.cameFrom = "apps"
    view.appId = id
    guide.codeApp = id
    guide.screen = "app"
    view.settingsOpen = false
    view.editing = null
    view.message = ""
    apps.used(id)
    view.reset()
    var mine = { guard: guard }
    view.agentOpen = mine
    view.queued = item ? { method: item.kind === "info" ? "details" : "browse", args: { item: item.item }, agent: mine } : null
    view.loadRoot()
    if (view.failed) { if (view.agentOpen === mine) view.agentOpen = null; view.queued = null; return view.failed }
    return ""
  }
  function agentStopped(why) {
    view.agentOpen = null
    view.queued = null
    view.failed = "Stopped opening it for an agent: " + why + "."
  }

  // An app opened at one of its items (a Home row's card): its first screen
  // loads, then what the card asks for (details, a screen, playing it)
  function openAt(id, method, args, by, from) {
    var r = view.open(id, by)
    if (r !== "ok") return r
    view.cameFrom = from || "apps"
    if (view.topView && !view.pending && view.rt && view.rt.phase === "ready") view.ask(method, args, method === "play" ? "play" : "push")
    else view.queued = { method: method, args: args }
    return "ok"
  }

  function attach() {
    var got = apps.ensure(view.appId, "foreground")
    if (!got.rt) { view.failed = got.why.charAt(0).toUpperCase() + got.why.slice(1) + "."; return false }
    view.rt = got.rt
    return true
  }

  function loadRoot() {
    view.failed = ""
    if (!view.rt || view.rt.phase === "stopped" || view.rt.phase === "stopping") { if (!view.attach()) return }
    if (view.rt.phase === "starting" || view.rt.phase === "queued") { view.waitingStart = true; view.waitingFor = view.agentOpen; return }
    view.waitingStart = false
    view.ask("home", {}, "root")
  }

  // ---- calls ------------------------------------------------------------
  // mode: root (the first screen), push (a new one), refresh (the one
  // that's there, again), play
  // forAgent: the agent's open a later step of it was for (it goes only
  // while that open is still the live one)
  function ask(method, args, mode, forAgent) {
    if (forAgent && forAgent !== view.agentOpen) return
    if (!view.rt || view.rt.phase !== "ready") {
      if (mode === "refresh") return
      if (view.rt && (view.rt.phase === "starting" || view.rt.phase === "queued")) { if (mode === "root") { view.waitingStart = true; view.waitingFor = view.agentOpen } return }
      if (mode === "root") view.failed = "The app isn't running. Enter starts it again."
      else view.say("The app isn't running. R starts it again.", true)
      return
    }
    if (mode === "refresh") {
      if (view.pending || view.refreshing) return
    } else {
      if (view.pending) view.cancelPending()
      view.cancelRefresh()   // a new screen: the old one's refresh is called off
      view.epoch += 1
    }
    // an agent's open: checked again right before it goes, every time
    if (view.agentOpen && mode !== "refresh") {
      var why = ["home", "browse", "details"].indexOf(method) < 0 ? "only screens and details are opened for an agent" : view.agentOpen.guard(method)
      if (why) { view.agentStopped(why); return }
      if (method !== "home" || !view.queued) view.agentOpen = null      // its last call
    }
    var p = { epoch: view.epoch, method: method, args: args || {}, mode: mode, rt: view.rt, id: 0 }
    if (mode === "refresh") view.refreshing = p
    else view.pending = p
    p.id = view.rt.call(method, p.args, function(kind, value) { view.answered(p, kind, value) })
  }

  function cancelPending() {
    var p = view.pending
    view.pending = null
    view.epoch += 1
    if (p && p.rt) p.rt.cancel(p.id)
  }

  function answered(p, kind, value) {
    if (view.pending === p) view.pending = null
    if (view.refreshing === p) view.refreshing = null
    // a reload that was to put back pictures the helper had let go: however
    // it ends, those pictures stop waiting (an answer that lands names new ones)
    ;(p.recover || []).forEach(function(t) { var v = view.imagePaths[t]; if (v === "" || v === undefined) view.setPath(t, "-gone") })
    var drop = function() { if ((kind === "screen" || kind === "detail") && p.rt) p.rt.release([p.id]) }
    // an epoch that's over, or a runtime that isn't this app's now: dropped
    if (p.rt !== view.rt || p.epoch !== view.epoch || !view.appId) { drop(); return }
    if (kind === "error") {
      if (value.code === "cancelled") return
      if (p.mode === "root") { view.failed = view.sentence(value.text || "it didn't answer"); return }
      if (p.mode !== "refresh") view.say(view.sentence(value.text || "it didn't answer"), true)
      return
    }
    var place = Nav.placement(p.method, kind)
    if (place === "message") { view.say(value.text, false); return }
    if (place === "play") { guide.playApp(view.appId, view.rt, value); return }
    if (place !== "push") { drop(); return }
    var nv = { kind: kind, value: value, item: p.args.item || "", method: p.method, args: p.args, sel: null,
               result: p.id, reload: view.reloadOf(p.method, p.args), tokens: view.tokensIn(value).length, stale: false, recovered: false }
    if (p.mode === "refresh" && view.topView) {
      // the same row and item, by their ids, else as near as there is; a
      // reload that put back pictures the helper had let go keeps it from
      // happening twice in a row
      var was = view.topView
      nv.sel = Nav.normalize(Looks.model(nv, view.envNow()), was.sel, view.model)
      nv.recovered = was.recovered
      view.stack = view.stack.slice(0, -1).concat([nv])
      view.release([was])
      view.trim()
    } else if (p.mode === "restore") {
      var top = view.topView
      if (!top || !top.stale) { drop(); return }   // gone meanwhile
      nv.sel = Nav.normalize(Looks.model(nv, view.envNow()), top.sel, null)
      view.stack = view.stack.slice(0, -1).concat([nv])
      view.trim()
    } else if (p.mode === "root") {
      view.release(view.stack)
      view.stack = [nv]
      if (view.queued) {
        var q = view.queued
        view.queued = null
        // an agent's item goes only while its open is still the live one, then and a moment later
        if (!q.agent || q.agent === view.agentOpen)
          Qt.callLater(function() { if (!q.agent || q.agent === view.agentOpen) view.ask(q.method, q.args, q.method === "play" ? "play" : "push", q.agent || null) })
      }
    } else {
      view.stack = view.stack.concat([nv])
      view.trim()
    }
    view.scheduleRefresh()
  }

  function sentence(t) {
    var s = String(t || "").trim()
    if (!s) return ""
    s = s.charAt(0).toUpperCase() + s.slice(1)
    return /[.!?…]$/.test(s) ? s : s + "."
  }

  function say(text, bad) {
    view.message = String(text || "")
    view.messageBad = bad === true
    messageTimer.restart()
  }

  // only a screen that may be loaded again comes again (never a button's)
  function scheduleRefresh() {
    refreshTimer.stop()
    if (view.topView && view.topView.kind === "screen" && view.topView.reload && view.topView.value && view.topView.value.refresh) {
      refreshTimer.interval = Math.round(view.topView.value.refresh * 1000)
      refreshTimer.start()
    }
  }

  // ---- the keys -----------------------------------------------------------
  // ---- live views (api 4) -------------------------
  // The top view, when it's a screen that said live and it's on the screen:
  // its helper and app hear when it comes and goes (viewOn, viewOff), and
  // its rows may be replaced meanwhile (liveUpdate), the selection kept.
  readonly property var liveTarget: view.shown && view.rt && view.topView && view.topView.kind === "screen" && view.topView.value
                                    && view.topView.value.live === true ? { rt: view.rt, id: view.topView.result } : null
  property var liveSent: null
  onLiveTargetChanged: view.syncLive()
  function syncLive() {
    var t = view.liveTarget, s = view.liveSent
    if (s && (!t || t.rt !== s.rt || t.id !== s.id)) {
      if (s.rt && s.rt.phase === "ready") s.rt.viewOff(s.id)
      view.liveSent = null
    }
    if (t && !view.liveSent && t.rt.phase === "ready" && t.rt.viewOn(t.id)) view.liveSent = t
  }
  function liveUpdate(id, vid, rows) {
    if (id !== view.appId || !rows) return
    rows = JSON.parse(JSON.stringify(rows))   // a plain copy: since Qt 6.12 a list through a signal isn't an array
    var i = -1
    for (var k = 0; k < view.stack.length; k++) if (view.stack[k].result === vid && view.stack[k].kind === "screen") i = k
    if (i < 0) return
    var old = view.stack[i]
    var by = {}
    rows.forEach(function(r) { by[r.id] = r })
    var value = view.merged(old.value, { rows: old.value.rows.map(function(r) { return by[r.id] || r }) })
    var nv = view.merged(old, { value: value, tokens: view.tokensIn(value).length })
    if (i === view.stack.length - 1) nv.sel = Nav.normalize(Looks.model(nv, view.envNow()), old.sel, view.model)
    view.stack = view.stack.slice(0, i).concat([nv]).concat(view.stack.slice(i + 1))
    view.trim()   // within the 4,000 pictures again: older views let go first
  }

  // an article page (api 4): up and down scroll it, a step at a time (the
  // screen keeps it within its length: pageMax)
  property real pageY: 0
  property real pageMax: 0

  function move(key) {
    view.userActs()
    if (!view.topView) return false
    if (view.topView.kind === "page") {
      if (key !== "up" && key !== "down") return false
      var step = guide.u * 8
      view.pageY = Math.max(0, Math.min(view.pageMax, view.pageY + (key === "down" ? step : -step)))
      return true
    }
    var s = Nav.move(view.model, view.topView.sel, key)
    if (!s) return false
    view.topView.sel = s
    view.sel = s
    return true
  }

  function enter(by) {
    view.userActs()
    if (by !== guide.byUser) return
    if (view.failed) { view.loadRoot(); return }
    if (!view.topView || view.pending) return
    var go = Nav.enter(view.topView, view.model)
    if (go) view.ask(go.method, go.args, go.method === "play" ? "play" : "push")
  }

  function details(by) {
    view.userActs()
    if (by !== guide.byUser || !view.topView || view.pending) return
    var go = Nav.details(view.topView, view.model)
    if (go) view.ask(go.method, go.args, "push")
  }

  // R: the view again, through its read-only reload; never a button's call
  function reload(by) {
    if (by !== guide.byUser) return
    view.userActs()
    if (view.failed || !view.topView) { view.loadRoot(); return }
    var top = view.topView
    if (top.stale) { view.restoreTop(); return }
    if (top.reload) view.ask(top.reload.method, top.reload.args, "refresh")
    else view.say("This came from a button, so R doesn't ask for it again.", false)
  }

  function back() {
    view.userActs()
    if (view.signIn) { view.cancelSignIn(); return }
    if (view.editing) { view.editing = null; guide.focusKeys(); return }
    if (view.settingsOpen) { view.settingsOpen = false; view.armed = ""; return }
    if (view.pending) { view.cancelPending(); return }
    if (view.stack.length > 1) {
      view.epoch += 1
      view.cancelRefresh()
      var gone = view.stack[view.stack.length - 1]
      view.stack = view.stack.slice(0, -1)
      view.release([gone])
      view.scheduleRefresh()
      return
    }
    view.close()
  }

  function startSearch(by) {
    if (by !== guide.byUser || view.failed || !view.rt) return
    view.userActs()
    view.editing = { type: "search", key: "", label: "Search " + (view.record ? view.record.name : ""), text: "" }
  }

  // Enter in the text field
  function editDone(text, by) {
    if (by !== guide.byUser || !view.editing) return
    view.userActs()
    var e = view.editing
    view.editing = null
    guide.focusKeys()
    if (e.type === "search") {
      if (String(text).trim()) view.ask("search", { query: String(text).trim().slice(0, 200) }, "push")
      return
    }
    var id = view.appId
    if (apps.changing[id]) { view.noteFor(id, "It's being changed. Try again in a moment."); return }
    if (e.type === "text") { apps.setValue(id, e.key, String(text).slice(0, 200)); view.restartApp(id, "", ""); return }
    if (e.type === "secret") {
      apps.setSecret(id, e.key, String(text), function(ok, why) {
        view.noteFor(id, ok ? (text === "" ? "Cleared." : "Kept.") : "Couldn't keep it: " + why)
        if (ok) view.restartApp(id, "", "")
      })
      return
    }
    if (e.type === "server") {
      apps.setServer(id, String(text), function(ok, why, notAddress) {
        if (!ok) { view.noteFor(id, (notAddress ? "Not a server address: " : "Couldn't change it: ") + why); return }
        view.restartApp(id, "server", "The app started again with this server.")
      })
    }
  }

  // ---- the presentation model's inputs --------------------------------------
  // (choices: yours for this app and all apps come with Customize; the
  // theme's apps object is the look it gives every app)
  function envNow() {
    var theme = guide.currentTheme && guide.currentTheme.apps ? guide.currentTheme.apps : ({})
    var store = guide.appScreens
    var mine = store && view.record ? store.entryOf(view.record) : null
    return { width: view.screenWidth, u: guide.u, layout: guide.layout, learned: view.learned[view.shapeKey] || ({}), defaults: view.rowDefaults,
             choices: { mine: mine || ({}), all: store ? store.all : ({}), theme: theme },
             suggested: view.record && view.record.layout ? view.record.layout.look || "" : "" }
  }
  // a new look is a new demand: what the screen wants now is asked for under it
  readonly property string lookNow: view.model && view.model.screen ? view.model.screen.look : ""
  onLookNowChanged: view.bumpDemand()

  // The app's app.json defaults for its rows (API 3), by row id
  readonly property var rowDefaults: {
    var out = Object.create(null)
    var lay = view.record && view.record.layout
    ;((lay && lay.rows) || []).forEach(function(r) { out["d:" + r.id] = r })
    return out
  }

  // The shape each row learned from its first pictures (AppLooks.autoShape),
  // once per app (its source and id, like every store of an app's), row id
  // and session; never saved. "<source>\n<app id>" -> { "r:<row id>": shape },
  // at most 256 rows an app (the oldest learned goes first).
  readonly property string shapeKey: view.appId ? ((view.record && view.record.source) || "") + "\n" + view.appId : ""
  property var learned: ({})
  property var learnedOrder: ({})     // shape key -> [row keys, oldest first]
  // rows still deciding: "<shape key>\n<row id>" -> { app, row, epoch, start, count, settled: { position: ratio } },
  // each for the view (epoch) that showed it
  property var sampling: ({})

  function shapeKnown(rowId) {
    var mine = view.learned[view.shapeKey]
    return !!mine && Object.prototype.hasOwnProperty.call(mine, "r:" + rowId)
  }

  // A line of a row is on the screen: its 2 s start, once for this view (a
  // row still deciding when another screen shows the same row id starts
  // again there). Pictures that settled before it was shown count; the
  // clock starts only now.
  function rowShown(rowId, count) {
    if (!view.shapeKey || view.shapeKnown(rowId)) return
    var k = view.shapeKey + "\n" + rowId
    var cur = view.sampling[k]
    if (cur && cur.epoch === view.epoch && cur.start > 0) return
    var s = Object.create(null)
    for (var x in view.sampling) s[x] = view.sampling[x]
    s[k] = cur && cur.epoch === view.epoch
           ? { app: cur.app, row: cur.row, epoch: cur.epoch, start: Date.now(), count: Math.max(cur.count, count), settled: cur.settled }
           : { app: view.shapeKey, row: rowId, epoch: view.epoch, start: Date.now(), count: count, settled: ({}) }
    view.sampling = s
  }

  // A card's picture settled at position: ratio is its width over height,
  // 0 when it failed or there's none. Taken in once what's being drawn now
  // is done (cards report while the model's lines are being made), so the
  // model is never made again in the middle of being made.
  // count: how many items its row has; owner and epoch: the app (shape key)
  // and view the card was made for. A report for another app or view is
  // dropped.
  property var settledLater: []
  function pictureSettled(rowId, position, ratio, count, owner, epoch) {
    view.settledLater.push([owner, epoch, rowId, position, ratio, count])
    Qt.callLater(view.takeSettled)
  }
  function takeSettled() {
    var all = view.settledLater
    view.settledLater = []
    for (var i = 0; i < all.length; i++)
      if (all[i][0] === view.shapeKey && all[i][1] === view.epoch) view.settleNow(all[i][2], all[i][3], all[i][4], all[i][5])
  }
  function settleNow(rowId, position, ratio, count) {
    if (!view.shapeKey || view.shapeKnown(rowId)) return
    var k = view.shapeKey + "\n" + rowId
    var cur = view.sampling[k]
    if (!cur || cur.epoch !== view.epoch) {
      // a card made ahead, off the screen, settled first: kept, its row's
      // clock not started until the row is shown. Once the first three have
      // all settled the row is decided, shown or not: that answer is theirs
      // alone, whenever they came (only the 2 s timeout waits for the screen)
      var s0 = Object.create(null)
      for (var y in view.sampling) s0[y] = view.sampling[y]
      s0[k] = { app: view.shapeKey, row: rowId, epoch: view.epoch, start: 0, count: Math.max(count || 0, position + 1), settled: ({}) }
      view.sampling = s0
      cur = view.sampling[k]
    }
    if (cur.settled[position] !== undefined) return
    var settled = {}
    for (var p in cur.settled) settled[p] = cur.settled[p]
    settled[position] = ratio > 0 && isFinite(ratio) ? ratio : 0
    var next = Object.create(null)
    for (var x in view.sampling) next[x] = view.sampling[x]
    next[k] = { app: cur.app, row: cur.row, epoch: cur.epoch, start: cur.start, count: cur.count, settled: settled }
    view.sampling = next
    view.decideShape(k, false)
  }

  function decideShape(k, force) {
    var cur = view.sampling[k]
    if (!cur) return
    var shape = Looks.autoShape(cur.settled, cur.count, force)
    if (!shape) return
    var left = Object.create(null)
    for (var x in view.sampling) if (x !== k) left[x] = view.sampling[x]
    view.sampling = left
    var mine = {}
    var had = view.learned[cur.app] || {}
    for (var r in had) mine[r] = had[r]
    var order = (view.learnedOrder[cur.app] || []).filter(function(o) { return o !== "r:" + cur.row })
    order.push("r:" + cur.row)
    mine["r:" + cur.row] = shape
    while (order.length > 256) delete mine[order.shift()]
    view.learnedOrder = apps.withKey(view.learnedOrder, cur.app, order)
    view.learned = apps.withKey(view.learned, cur.app, mine)
  }

  // A new view, or another app: what was deciding for the one before goes
  // (its pictures' reports are dropped anyway, and its rows start again if
  // they're shown again), so rows made ahead and never shown don't pile up
  onEpochChanged: view.dropOldSampling()
  onShapeKeyChanged: view.dropOldSampling()
  function dropOldSampling() {
    var keep = Object.create(null), dropped = false
    for (var k in view.sampling) {
      var s = view.sampling[k]
      if (s.epoch === view.epoch && s.app === view.shapeKey) keep[k] = s
      else dropped = true
    }
    if (dropped) view.sampling = keep
  }
  // The 2 s timeout's clock runs only while a row on the screen is deciding
  // (a row made ahead waits for its pictures, not the clock)
  readonly property bool sampleClock: {
    for (var k in view.sampling) if (view.sampling[k].start > 0) return true
    return false
  }
  Timer {
    interval: 200
    repeat: true
    running: view.sampleClock
    onTriggered: {
      var now = Date.now()
      for (var k in view.sampling) { var s = view.sampling[k]; if (s.start > 0 && now - s.start >= 2000) view.decideShape(k, true) }
    }
  }

  // ---- images -------------------------------------------------------------
  // imagePaths: token -> its local path; "" while it comes, "-" when the
  // helper couldn't get it (refused, or it failed, or it was let go and
  // can't be loaded again: the card shows its title)
  function imageUrl(img) {
    if (!img) return ""
    if (img.path) return guide.fileUrl(img.path)
    var p = img.token ? view.imagePaths[img.token] : ""
    return p && p.charAt(0) !== "-" ? guide.fileUrl(p) : ""
  }

  function imageFailed(img) {
    var p = img && !img.path && img.token ? view.imagePaths[img.token] : undefined
    return typeof p === "string" && p.charAt(0) === "-"
  }

  // A picture's width over height, from its header (a packaged picture's
  // came with it; a fetched one's with its file), or 0 until it's known
  function imageRatio(img) {
    if (!img) return 0
    var i = img.path ? img : view.imageInfo[img.token]
    return i && i.w > 0 && i.h > 0 ? i.w / i.h : 0
  }

  function setPath(tok, v) {
    if (view.imagePaths[tok] === undefined) view.pathOrder.push(tok)
    var next = {}
    for (var k in view.imagePaths) next[k] = view.imagePaths[k]
    next[tok] = v
    // at most 2,000 kept: the oldest no card wants go first, with all that's
    // known of them
    for (var i = 0; view.pathOrder.length > 2000 && i < view.pathOrder.length; ) {
      var old = view.pathOrder[i]
      if (view.wanted[old]) { i++; continue }
      view.pathOrder.splice(i, 1)
      delete next[old]
      view.forgetPicture(old)
    }
    view.imagePaths = next
  }
  function unsetPath(tok) {
    if (view.imagePaths[tok] === undefined) return
    var next = {}
    for (var k in view.imagePaths) if (k !== tok) next[k] = view.imagePaths[k]
    view.pathOrder = view.pathOrder.filter(function(t) { return t !== tok })
    view.imagePaths = next
    if (!view.wanted[tok]) view.forgetPicture(tok)   // no card waits for it: nothing of it is kept
  }
  // what's known of a picture besides its path: its size, and its retries
  function forgetPicture(tok) {
    delete view.imageInfo[tok]
    delete view.retried[tok]
    delete view.brokenRetried[tok]
  }

  function bestPrio(w) { return w.focus > 0 ? "focus" : w.visible > 0 ? "visible" : "rest" }

  // A card (or a details screen's picture) wants a picture, at a priority:
  // focus (the selected card, a details screen's), visible (on the screen),
  // rest (made ahead, off it). Each card says when it stops wanting it.
  function want(img, prio) {
    if (!img || !img.token) return
    var tok = img.token
    var pr = prio === "focus" || prio === "rest" ? prio : "visible"
    var w = view.wanted[tok] || { focus: 0, visible: 0, rest: 0 }
    var next = { focus: w.focus, visible: w.visible, rest: w.rest }
    next[pr] += 1
    view.wanted[tok] = next
    var p = view.imagePaths[tok]
    // one that couldn't be fetched is tried once more (never one the rules
    // refused, or one let go)
    if (p === "-failed" && !view.retried[tok]) { view.retried[tok] = true; p = undefined }
    if (p === undefined || (p === "" && pr === "focus")) view.request(tok, view.bestPrio(next))
    else if (p && p.charAt(0) !== "-") {
      // one already here, shown again: the helper checks its file again
      // (and keeps it from being the next to go), at most once a minute
      var info = view.imageInfo[tok]
      var now = Date.now()
      if (!info || !(now - (info.at || 0) < view.recheckMs)) {
        if (info) info.at = now
        view.request(tok, view.bestPrio(next))
      }
    }
  }
  property int recheckMs: 60000
  function unwant(img, prio) {
    if (!img || !img.token || !view.wanted[img.token]) return
    var w = view.wanted[img.token]
    var pr = prio === "focus" || prio === "rest" ? prio : "visible"
    var next = { focus: w.focus, visible: w.visible, rest: w.rest }
    next[pr] = Math.max(0, next[pr] - 1)
    if (next.focus + next.visible + next.rest > 0) view.wanted[img.token] = next
    else {
      delete view.wanted[img.token]
      if (view.imagePaths[img.token] === undefined) view.forgetPicture(img.token)   // nothing of it kept, nothing waits for it
    }
  }

  function request(tok, prio, broken) {
    if (!view.rt) return
    var rt = view.rt
    var p = view.imagePaths[tok]
    if (p === undefined || p.charAt(0) === "-") view.setPath(tok, "")
    rt.image(tok, function(path, info) { view.gotImage(rt, tok, path, info) }, rt.demand, prio, "view", broken === true)
  }

  // A picture drawn fine: a later failure to draw it (its file gone from the
  // helper's folder since, say) may be repaired again. Only a drawing proves
  // the file good: the helper's answer alone doesn't (a spoiled file with a
  // good header would be fetched again for ever).
  function pictureDrawn(img) {
    if (img && !img.path && img.token) delete view.brokenRetried[img.token]
  }

  // A picture's file came, but couldn't be drawn (spoiled, or gone since):
  // fetched again once, then it's shown as its title
  function brokenPicture(img, prio) {
    if (!img || img.path || !img.token) return
    var tok = img.token
    var p = view.imagePaths[tok]
    if (!p || p.charAt(0) === "-") return
    if (view.brokenRetried[tok]) { view.setPath(tok, "-broken"); return }
    view.brokenRetried[tok] = true
    view.unsetPath(tok)
    view.request(tok, prio, true)
  }

  function gotImage(rt, tok, path, info) {
    if (rt !== view.rt) return
    if (path) {
      view.imageInfo = apps.withKey(view.imageInfo, tok, { w: info && info.w || 0, h: info && info.h || 0, at: Date.now() })
      delete view.retried[tok]              // a failure from now on is a new one
      if (view.imagePaths[tok] !== path) view.setPath(tok, path)
      return
    }
    var code = info && info.code
    if (code === "stale") { if (view.imagePaths[tok] === "") view.unsetPath(tok); return }   // a newer demand asks again if it still wants it
    if (code === "busy") { busyRetry.restart(); return }                                     // still "", asked again in a moment
    if (code === "unknown") { if (!view.recover(tok)) view.setPath(tok, "-gone"); return }
    view.setPath(tok, code === "refused" ? "-refused" : "-failed")
  }

  // The demand moved on (another view, focus or runtime): what the screen
  // still wants and hasn't got is asked for again under the new epoch (the
  // runtime's, shared with the app's Home rows)
  function bumpDemand() {
    if (view.rt) view.rt.newDemand()
    Qt.callLater(view.resendDemand)
  }
  function resendDemand() {
    if (!view.rt) return
    for (var t in view.wanted) {
      var p = view.imagePaths[t]
      if (p === undefined || p === "") view.request(t, view.bestPrio(view.wanted[t]))
    }
  }

  // The helper no longer knows a picture the view on the screen names (it
  // was let go): the view loads again once through its read-only reload, at
  // most 6 such reloads a minute. A view without one shows the title there.
  function recover(tok) {
    var top = view.topView
    if (!top || top.stale || !top.reload || top.recovered || view.pending || view.refreshing) return false
    if (view.tokensIn(top.value).indexOf(tok) < 0) return false
    var now = Date.now()
    view.recoveredAt = view.recoveredAt.filter(function(t) { return now - t < 60000 })
    if (view.recoveredAt.length >= 6) return false
    view.recoveredAt = view.recoveredAt.concat([now])
    top.recovered = true
    view.ask(top.reload.method, top.reload.args, "refresh")
    if (view.refreshing) view.refreshing.recover = [tok]
    return true
  }

  // ---- settings -----------------------------------------------------------
  readonly property var settingsRows: {
    var a = view.record
    if (!a || a.kind !== "app") return []
    var rows = []
    var vals = a.values || {}
    ;(a.settings || []).forEach(function(st) {
      var v = vals[st.key]
      rows.push({ key: st.key, type: st.type, label: st.label, choices: st.choices || [],
                  value: st.type === "switch" ? v === true
                       : st.type === "choice" ? ((st.choices || []).indexOf(v) >= 0 ? v : (st.choices || [""])[0])
                       : st.type === "secret" ? (vals["@secret:" + st.key] ? "Set" : "Not set")
                       : String(v || "") })
    })
    if (a.permissions.server) rows.push({ key: "@server", type: "server", label: a.permissions.server.label || "Server", value: a.server || "Not set" })
    if (a.permissions.server && /^https:/.test(a.server || ""))
      rows.push({ key: "@pin", type: "pin", label: "Its certificate", value: a.pin ? "Pinned (" + a.pin.slice(0, 8) + "…)" : view.certOffer ? "Enter again to pin it" : "Checked by this computer" })
    // signing in: a row for each way it offers (a code, your username and password), or Sign out
    var ways = String(a.permissions.signIn || "").split("+").filter(function(w) { return w === "code" || w === "password" })
    if (ways.length && vals["@signedIn"]) rows.push({ key: "@signIn", type: "signIn", how: "", label: "Sign out", value: "" })
    else ways.forEach(function(w) {
      rows.push({ key: w === "code" ? "@signIn" : "@signInPassword", type: "signIn", how: w, value: "",
                  label: ways.length === 1 ? "Sign in" : w === "code" ? "Sign in with a code" : "Sign in with your username and password" })
    })
    if (a.permissions.storage) rows.push({ key: "@clear", type: "clear", label: "Clear its data", value: "" })
    return rows
  }

  function openSettings(by) {
    if (by !== guide.byUser || !view.record) return
    view.userActs()
    view.settingsOpen = true
    view.settingsCursor = 0
    view.armed = ""
    view.settingsNote = ""
  }

  function moveSettings(d) {
    view.settingsCursor = Math.max(0, Math.min(view.settingsRows.length - 1, view.settingsCursor + d))
    view.armed = ""
  }

  // Enter (d 0), or ← → (d -1, 1) on a setting
  function settingsAct(d, by) {
    if (by !== guide.byUser) return
    view.userActs()
    var r = view.settingsRows[view.settingsCursor]
    if (!r) return
    view.settingsNote = ""
    // nothing of it changes while something else is changing it (an update,
    // a sign-out, a restart): what's written now would miss that restart
    if (apps.changing[view.appId]) { view.settingsNote = "It's being changed. Try again in a moment."; return }
    if (r.type === "switch") { apps.setValue(view.appId, r.key, !r.value); view.restart(""); return }
    if (r.type === "choice") {
      var i = r.choices.indexOf(r.value)
      var next = r.choices[(i + (d < 0 ? -1 : 1) + r.choices.length) % r.choices.length]
      apps.setValue(view.appId, r.key, next)
      view.restart("")
      return
    }
    if (d !== 0) return
    if (r.type === "text") view.editing = { type: "text", key: r.key, label: r.label, text: r.value }
    else if (r.type === "secret") view.editing = { type: "secret", key: r.key, label: r.label, text: "" }
    else if (r.type === "server") view.editing = { type: "server", key: r.key, label: r.label, text: view.record.server || ("http://") }
    else if (r.type === "signIn") { if ((view.record.values || {})["@signedIn"]) view.signOut(by); else view.startSignIn(by, r.how) }
    else if (r.type === "pin") view.pinAct(by)
    else if (r.type === "clear") {
      if (view.armed !== r.key) { view.armed = r.key; return }
      view.armed = ""
      view.settingsNote = "Clearing its data…"
      view.restartApp(view.appId, "data", "Its data is cleared.")
    }
  }

  // ---- signing in, with a code or a password -------------------------------
  // You choose Sign in (how: "code" or "password", from what the app offers).
  // With a code: the app asks its server for one, the guide shows it big
  // (and as a QR code); you enter it on your phone or computer. With a
  // password: the guide's own box takes your username and password, typed
  // on the keyboard only (the phone remote can't), and hands them to the app
  // once, through the helper (AppRuntime.sendPassword); nothing keeps them.
  // Either way the app keeps what the service gives back (only while
  // signing in) and says it's done. Esc, leaving, the app stopping or the
  // code expiring call it off. After 5 wrong passwords in a row, the box
  // waits 30 seconds.
  function startSignIn(by, how) {
    if (by !== guide.byUser || !view.record) return
    view.userActs()
    how = how === "password" ? "password" : "code"
    // an account that lists your servers chooses it while signing in
    var fromSignIn = !!(view.record.permissions.server && view.record.permissions.server.fromSignIn)
    if (!view.record.server && !fromSignIn) { view.settingsNote = "Set its server first."; return }
    var wait = how === "password" ? apps.passwordWait(view.appId) : 0
    if (wait > 0) { view.settingsNote = "Too many wrong passwords: try again in " + wait + " seconds."; return }
    if (!view.rt || view.rt.phase !== "ready") {
      if (!view.rt && !view.attach()) return
      view.settingsNote = "The app is starting. Try again in a moment."
      return
    }
    var hex = ""
    for (var i = 0; i < 32; i++) hex += "0123456789abcdef".charAt(Math.floor(Math.random() * 16))
    view.settingsOpen = false
    view.signIn = { flow: hex, how: how, stage: how === "password" ? "typing" : "", code: "", url: "", expires: 0, qr: "",
                    sent: false, install: apps.installOf(view.record), servers: [], server: null, pick: 0, target: "", note: "" }
    view.rt.signIn(hex, how, function(kind, value) {
      if (!view.signIn || view.signIn.flow !== hex) return
      if (kind === "error") { view.signIn = null; view.say(view.sentence(value.text || "Signing in didn't start"), true) }
    })
  }

  // Enter in the password box: what you typed goes to the app, and the box
  // says it's signing in (false: not now, the fields stay as they are)
  function sendPassword(username, password, by) {
    if (by !== guide.byUser || !view.signIn || view.signIn.how !== "password" || view.signIn.stage !== "typing" || !view.rt) return false
    if (!String(username) || !String(password)) return false
    view.userActs()
    if (!view.rt.sendPassword(view.signIn.flow, String(username), String(password))) return false
    view.signIn = view.merged(view.signIn, { stage: "checking", sent: true })
    return true
  }

  function merged(a, b) { var o = {}; for (var k in a) o[k] = a[k]; for (var j in b) o[j] = b[j]; return o }

  // ---- choosing your server while signing in -----
  // An account that lists your servers (app.json's server.fromSignIn): once
  // the app is signed in to the account it offers them; you choose the
  // server, then one of its addresses or one you type for it. The app gets
  // only that server's credential (it knows which by the handle). A server
  // other than the one it has asks first: switching clears what it kept for
  // the old one (setServer and its restart), then you sign in again.
  property var pendingSignIn: null   // { id, how }: a sign-in to start once it's started again with the server you switched to
  property int addressAsk: 0         // a typed address being checked: only the newest, for the server it was typed for, counts

  function gotServers(flow, servers) {
    if (!view.signIn || view.signIn.flow !== flow) return
    view.addressAsk++
    view.signIn = view.merged(view.signIn, { stage: servers.length ? "servers" : "checking", servers: servers, server: null, pick: 0,
                                             note: servers.length ? "" : "The account lists no server this guide can reach." })
  }

  function refusedServer(flow, why) {
    if (!view.signIn || view.signIn.flow !== flow) return
    view.signIn = view.merged(view.signIn, { stage: "addresses", pick: 0, note: "That address didn't work: " + why })
  }

  // the rows of the step it's at: its servers, a server's addresses (and
  // typing one), or "switch to it?"
  readonly property var signInRows: {
    var si = view.signIn
    if (!si) return []
    if (si.stage === "servers") return si.servers.map(function(sv) { return { type: "server", label: sv.label, value: sv.urls[0], server: sv } })
    if (si.stage === "addresses" && si.server)
      return si.server.urls.map(function(u) { return { type: "url", label: u, value: "", url: u } })
                           .concat([{ type: "type", label: "Type an address for this server", value: "" }])
    if (si.stage === "switch") return [{ type: "switch", label: "Switch to it", value: "" }, { type: "stay", label: "Keep " + (view.record ? view.record.server : "the one it has"), value: "" }]
    return []
  }

  function signInMove(d) {
    if (!view.signIn || !view.signInRows.length) return
    view.userActs()
    view.signIn = apps.withKey(view.signIn, "pick", Math.max(0, Math.min(view.signInRows.length - 1, view.signIn.pick + d)))
  }

  function signInAct(by) {
    if (by !== guide.byUser || !view.signIn) return
    view.userActs()
    var r = view.signInRows[view.signIn.pick]
    if (!r) return
    if (r.type === "server") view.signIn = view.merged(view.signIn, { stage: "addresses", server: r.server, pick: 0, note: "" })
    else if (r.type === "url") view.pickAddress(r.url, false, by)
    else if (r.type === "type") view.signIn = view.merged(view.signIn, { stage: "address", note: "" })
    else if (r.type === "switch") view.switchTo(view.signIn.target, by)
    else if (r.type === "stay") view.cancelSignIn()
  }

  // Esc: a step back, or (at the first step) calls it off
  function signInBack() {
    var si = view.signIn
    if (!si) return
    view.userActs()
    view.addressAsk++   // an address still being checked no longer counts
    if (si.stage === "addresses") view.signIn = view.merged(si, { stage: "servers", server: null, pick: 0, note: "" })
    else if (si.stage === "address" || si.stage === "switch") view.signIn = view.merged(si, { stage: "addresses", pick: 0, note: "" })
    else view.cancelSignIn()
  }

  // Enter in "Type an address for this server": made canonical first (as a
  // server's address is), then as if it were one of its own
  function typedAddress(text, by) {
    if (by !== guide.byUser || !view.signIn || view.signIn.stage !== "address" || !String(text).trim()) return
    view.userActs()
    if (!view.signIn.server) return
    var flow = view.signIn.flow, handle = view.signIn.server.handle, ask = ++view.addressAsk
    apps.canonicalServer(String(text).trim(), function(ok, server, why) {
      // still this sign-in, still typing for that server, and still this try
      var si = view.signIn
      if (!si || si.flow !== flow || si.stage !== "address" || !si.server || si.server.handle !== handle || ask !== view.addressAsk) return
      if (!ok) { view.signIn = view.merged(si, { note: "Not a server address: " + why }); return }
      view.pickAddress(server, true, by, handle)
    })
  }

  // handle: the server it's for (a typed address names the one it was typed for)
  function pickAddress(url, typed, by, handle) {
    var si = view.signIn
    if (by !== guide.byUser || !si || !si.server || !view.rt) return
    if (handle !== undefined && handle !== si.server.handle) return
    if (view.record && view.record.server && view.record.server !== url) {
      view.signIn = view.merged(si, { stage: "switch", target: url, pick: 0, note: "" })
      return
    }
    if (typed) view.rt.typedServer(si.flow, si.server.handle, url)
    else view.rt.chooseServer(si.flow, si.server.handle, url)
    view.signIn = view.merged(si, { stage: "checking", note: "" })
  }

  // Yes to "switch to it": this sign-in called off, the new server set
  // (what the old one gave is forgotten at the restart), then a new sign-in
  function switchTo(url, by) {
    if (by !== guide.byUser || !view.signIn) return
    var how = view.signIn.how, id = view.appId
    view.cancelSignIn()
    apps.setServer(id, url, function(ok, why) {
      if (!ok) { view.noteFor(id, "Couldn't switch: " + why); return }
      view.pendingSignIn = { id: id, how: how }
      view.restartApp(id, "server", "")
    })
  }

  function cancelSignIn() {
    view.addressAsk++
    if (!view.signIn) return
    if (view.rt) view.rt.cancelSignIn(view.signIn.flow)
    view.signIn = null
  }

  function gotCode(flow, code, url, expires) {
    // only a code sign-in shows a code (the helper drops one in a password sign-in too)
    if (!view.signIn || view.signIn.flow !== flow || view.signIn.how !== "code" || view.signIn.stage !== "") return
    // added to the sign-in as it is (which install it began on, and the rest)
    var mine = view.merged(view.signIn, { code: code, url: url, expires: Date.now() + expires * 1000, qr: "" })
    view.signIn = mine
    // every code asks (one without a link too: the QR being made for the
    // code before is called off), and only this code takes the answer
    guide.makeQr(url, function(path) { if (view.signIn === mine && path) view.signIn = apps.withKey(mine, "qr", path) })
  }

  function signInOver(flow, ok, message, server) {
    if (!view.signIn || view.signIn.flow !== flow) return
    var si = view.signIn
    // a password that was sent and didn't work counts toward the wait
    if (si.how === "password" && si.sent) {
      if (ok) apps.passwordWorked(view.appId)
      else apps.passwordFailed(view.appId)
    }
    view.signIn = null
    var fromSignIn = !!(view.record && view.record.permissions.server && view.record.permissions.server.fromSignIn)
    if (ok && fromSignIn) {
      // the server you chose, kept with the sign-in in one write; if that
      // can't be done, it isn't signed in, and what it kept is forgotten
      var saved = apps.signedInWith(view.appId, server, si.install)
      if (!saved.ok) {
        view.say("Couldn't keep the sign-in: " + saved.why + ".", true)
        view.dropSignIn(view.appId)
        return
      }
      if (view.rt) view.rt.markSignedIn()
      apps.authChanged(view.appId)
      view.say(message || "Signed in.", false)
      view.reset()
      view.loadRoot()
      return
    }
    if (ok) {
      // what it kept now is the sign-in (a runtime gets to ready only after
      // its earlier clean-ups are done, so none of these is still owed)
      apps.unpend(view.appId, "@clear", ["signIn"])
      apps.unpend(view.appId, "@forget", ["signIn", "server"])
      apps.setValue(view.appId, "@signedIn", true)
      if (view.rt) view.rt.markSignedIn()
      apps.authChanged(view.appId)
      view.say(message || "Signed in.", false)
      view.reset()
      view.loadRoot()
    } else if (message) view.say(message, true)
  }

  // A sign-in the app finished whose record couldn't be written: there's no
  // sign-in to keep, so whatever can or can't be written now, the helper
  // stops and, as it does, forgets what the flow kept and goes back to the
  // server it had (its own forget: signIn, no write of the guide's needed);
  // then the guide's clean-up is tried, and it starts again
  function dropSignIn(id) {
    if (!id) return
    apps.setChanging(id, true)
    if (view.appId === id) { view.reset(); view.restarting = true }
    var after = function() {
      apps.forget(id, "signIn", function() {
        apps.setChanging(id, false)
        apps.authChanged(id)
        if (view.appId !== id) return
        view.restarting = false
        view.rt = null
        view.loadRoot()
      })
    }
    var rt = apps.runtime(id)
    if (!rt || rt.phase === "stopped" || rt.phase === "queued") { if (rt) rt.stop(""); after(); return }
    var done = false
    rt.stopped.connect(function() { if (done) return; done = true; after() })
    apps.stopRuntime(id, "signIn", "user")
  }

  // Signing out, in order, whatever the app answers: playback ends first
  // (its last report goes out while the token still works), then the app's
  // signOut (5 s), then the guide stops it and forgets its sign-in (the
  // secrets it kept, its storage marked server, its pictures stay)
  function signOut(by) {
    if (by !== guide.byUser || !view.record) return
    view.userActs()
    var id = view.appId
    if (apps.changing[id]) { view.settingsNote = "It's being changed. Try again in a moment."; return }
    var rt = apps.runtime(id)
    view.settingsNote = "Signing out…"
    // held from now until it's forgotten: Home asks it for nothing more (what
    // it had is dropped now), and it doesn't start again in between
    // on disk first, in one write, before the waits below: a guide cut off
    // meanwhile owes the forget and isn't signed in when it starts again
    // (the app running keeps what it was started with, so its last report
    // and its signOut still have the token). Not on disk: not signed out.
    var saved = apps.commit(id, function(a) {
      var v = {}
      for (var k in a.values || {}) if (k !== "@signedIn") v[k] = a.values[k]
      var f = apps.pending(a, "@forget")
      if (f.indexOf("signIn") < 0) v["@forget"] = f.concat(["signIn"])
      a.values = v
    })
    if (!saved) { view.settingsNote = "Couldn't sign out: your list of apps couldn't be saved (" + apps.saveError + ")."; return }
    apps.setChanging(id, true)
    apps.authChanged(id)
    // the guide's part, whatever the app did (or if it isn't running at all)
    var local = function() { view.restartHeld(id, "signIn", "Signed out.") }
    if (!rt || rt.phase !== "ready") { local(); return }
    guide.finishAppPlayback(id, "signOut", function() {
      if (rt.phase !== "ready") { local(); return }
      rt.call("signOut", {}, function() { local() })
    })
  }

  // A note on the settings page of that app, if it's still the one shown
  function noteFor(id, text) { if (view.appId === id) view.settingsNote = text }

  // The server's certificate: pinned on your say-so (one this computer
  // doesn't trust, say a home server's own), or unpinned
  function pinAct(by) {
    if (by !== guide.byUser || !view.record) return
    view.userActs()
    if (view.record.pin) {
      apps.setPin(view.appId, "")
      view.certOffer = null
      view.restartApp(view.appId, "", "Unpinned: its certificate is checked by this computer again.")
      return
    }
    if (view.certOffer) {
      apps.setPin(view.appId, view.certOffer.sha256)
      view.certOffer = null
      view.restartApp(view.appId, "", "Pinned. Only a server with this certificate is reached.")
      return
    }
    view.settingsNote = "Getting its certificate…"
    var id = view.appId
    var server = view.record.server
    apps.certOf(id, function(ok, info) {
      if (view.appId !== id || !view.record || view.record.server !== server) return   // another app, or another server, by now
      if (!ok) { view.settingsNote = "Couldn't get it: " + info; return }
      view.certOffer = info
      view.settingsNote = (info.verified ? "This computer already trusts it, so there's no need to pin it. " : "This computer doesn't trust it. ")
        + "Its SHA-256 is " + info.sha256.match(/.{1,2}/g).join(":").toUpperCase() + ". Pin it only if that's your server's. Enter again pins it."
    })
  }

  // A change: the app stops (in order) and starts again with it, from its
  // first screen. forget: what goes with the stop (server, data, signIn).
  // While it's playing, playback ends first.
  function restart(forget) { view.restartApp(view.appId, forget || "", "") }

  // App id stops in order (its playback finalized, the helper exited), then
  // what goes with the change is forgotten by the guide itself (sign-in,
  // server, data: bin/om-pg-apps forget), then, if it's still on the
  // screen, it starts again from its first screen. Whatever the view does
  // meanwhile, this acts on id alone.
  function restartApp(id, forget, note) {
    if (!id) return
    if (apps.changing[id]) { view.noteFor(id, "It's being changed. Try again in a moment."); return }
    apps.setChanging(id, true)
    view.restartHeld(id, forget, note)
  }

  // The same, for a caller already holding id (apps.changing): held until
  // it's stopped and what goes is forgotten, so nothing starts it or changes
  // it in between; then let go, and Home's rows of it start afresh
  function restartHeld(id, forget, note) {
    // what's forgotten is owed on disk first (a sign-out and a new server
    // owe it already): if it's cut off or fails, the next start does it.
    // Not on disk: nothing is done.
    if (forget && apps.pending(apps.record(id), "@forget").indexOf(forget) < 0 &&
        !apps.commit(id, function(a) { var v = {}; for (var k in a.values || {}) v[k] = a.values[k]; v["@forget"] = apps.pending(a, "@forget").concat([forget]); a.values = v })) {
      apps.setChanging(id, false)
      view.noteFor(id, "Couldn't do it: your list of apps couldn't be saved (" + apps.saveError + ").")
      return
    }
    if (forget) apps.authChanged(id)   // what's forgotten is no longer good for Home, from now
    var mine = apps.installOf(apps.record(id))
    if (view.appId === id) {
      view.reset()
      view.restarting = true
    }
    apps.stopThen(id, "user", function() {
      var go = function(ok, why) {
        apps.setChanging(id, false)
        if (forget) apps.authChanged(id)   // one more, after it's forgotten: rows load again for what's left
        if (forget && ok === false) view.noteFor(id, "Couldn't clear it yet (" + why + "). It's cleared before the app starts again.")
        else if (note) view.noteFor(id, note)
        if (view.appId !== id || apps.installOf(apps.record(id)) !== mine) return   // another app, or replaced, by now
        view.restarting = false
        view.rt = null
        view.loadRoot()
      }
      if (forget) apps.forget(id, forget, go)
      else go(true, "")
    })
  }

  Connections {
    target: view.rt
    ignoreUnknownSignals: true
    // its first screen, once the app has started: for an agent's open, only
    // while that very open is still the live one (checked again as it goes);
    // if you took over meanwhile, it waits for you
    function onReadyNow() {
      // you switched servers in a sign-in: the new sign-in, now it runs with that server
      var p = view.pendingSignIn
      if (p && p.id === view.appId) { view.pendingSignIn = null; Qt.callLater(function() { if (view.appId === p.id) view.startSignIn(guide.byUser, p.how) }) }
      else if (p) view.pendingSignIn = null
      if (!view.waitingStart) return
      var w = view.waitingFor
      view.waitingStart = false
      view.waitingFor = null
      if (w && w !== view.agentOpen) { view.failed = "It was opened for an agent, and you took over: Enter loads it."; return }
      view.ask("home", {}, "root", w)
    }
    function onSignInCode(flow, code, url, expires) { view.gotCode(flow, code, url, expires) }
    function onSignInDone(flow, ok, message, server) { view.signInOver(flow, ok, message, server) }
    function onSignInServers(flow, servers) { view.gotServers(flow, servers) }
    function onSignInServerRefused(flow, why) { view.refusedServer(flow, why) }
    // a request it wasn't allowed: said once a session (its Activity has them all)
    function onRefused(site) {
      if (view.record && apps.sayRefused(view.appId))
        view.say(view.record.name + " tried to reach " + (site || "a site it didn't list") + ". It isn't allowed, so it wasn't reached (see its Activity).", false)
    }
    function onStopped(why, text) {
      view.rt = null
      view.waitingStart = false
      view.waitingFor = null
      view.signIn = null
      view.pending = null
      view.refreshing = null
      if (!view.appId || view.restarting) return   // a restart picks up from here itself
      if (why === "normal" || why === "guide") { view.stack = []; return }
      view.reset()
      view.failed = why === "unavailable" ? view.sentence(text || "It can't run on this system")
                  : "The app stopped (" + (why === "violation" ? "it broke the rules apps follow" : why === "timeout" ? "it stopped answering" : why === "start" ? "it didn't start" : "it crashed")
                    + (text ? ": " + text : "") + "). Enter starts it again."
    }
  }

  // leaving the screen (the rail, Home, the guide put away): the app keeps
  // its place, without its screen lease
  Connections {
    target: guide
    // off the app's screen, its pictures aren't wanted: a new demand tells
    // the helper (the screen's cards are gone, so nothing is asked again)
    function onScreenChanged() { if (guide.screen !== "app" && view.rt) { view.rt.lease("foreground", false); view.bumpDemand() } }
    function onOpenedChanged() {
      if (!guide.opened) { if (view.rt) view.rt.lease("foreground", false); return }
      if (guide.screen !== "app" || !view.appId) return
      // back to it: its runtime may have stopped while the guide was away
      if (view.rt && view.rt.phase === "ready") { view.rt.lease("foreground", true); view.scheduleRefresh() }
      else if (!view.rt && !view.failed) { view.reset(); view.loadRoot() }
    }
  }

  // an app that can't open any more (off, removed, apps off) leaves the screen
  Connections {
    target: apps
    function onLiveUpdated(id, rt, vid, rows, items) { if (rt === view.rt) view.liveUpdate(id, vid, rows) }
    function onReadyChanged() {
      if (!view.appId || apps.ready.some(function(a) { return a.id === view.appId })) return
      var on = guide.screen === "app"
      view.leave(true)
      if (on) guide.openApps(true)
    }
  }

  Timer {
    id: refreshTimer
    objectName: "refreshTimer"
    repeat: true
    onTriggered: {
      var top = view.topView
      if (!view.shown || view.settingsOpen || view.pending || !top || top.kind !== "screen" || !top.reload) return
      view.ask(top.reload.method, top.reload.args, "refresh")
    }
  }

  // the helper's picture queue was full: what the screen still wants is
  // asked for again in a moment
  Timer {
    id: busyRetry
    objectName: "busyRetry"
    interval: 1000
    onTriggered: view.resendDemand()
  }

  Timer {
    id: messageTimer
    interval: 5000
    onTriggered: view.message = ""
  }
}
