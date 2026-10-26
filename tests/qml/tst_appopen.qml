import QtQuick
import QtTest
import "../.."
import "../../AppBudget.js" as Budget

// An agent opening an app's screen and taking its picture
// (openApp, appScreen's view, appSnapshot), with the real AppView, AppAgent,
// AppScreens and Snapshots against a pretend guide, store and runtimes:
// the refusals in their order; nothing done after three faults while the
// user's own open still works; every check again right before each call
// goes, including one sent later from the start-up queue; never play, a
// button, sign-in or settings; the same runtime budget as the user's open;
// you doing anything yourself ending it; and view identity from openApp to
// the poll to the picture. Run: /usr/lib/qt6/bin/qmltestrunner -input tests/qml
Item {
  id: root
  width: 640
  height: 360

  component FakeRuntime: QtObject {
    id: frt
    property string phase: "ready"
    property int gen: 1
    property var calls: []
    property var leases: ({})
    property int nextId: 1
    property var cancelled: []
    property bool busy: false
    property real lastUsed: 0
    signal readyNow()
    signal stopped(string why, string text)
    function call(method, args, done) { var c = { id: frt.nextId++, method: method, args: args, done: done }; frt.calls = frt.calls.concat([c]); return c.id }
    function cancel(id) { frt.cancelled = frt.cancelled.concat([id]) }
    function lease(name, on) { var l = {}; for (var k in frt.leases) l[k] = true; if (on) l[name] = true; else delete l[name]; frt.leases = l }
    function image(token, done, epoch, prio, consumer, broken) {}
    function newDemand() { return 1 }
    function release(results) {}
    function stop(forget) { frt.phase = "stopped"; frt.stopped("normal", "") }
    function signIn(flow, how, done) { return frt.call("signIn", { flow: flow, how: how }, done) }
    property var typed: []
    function sendPassword(flow, u, p) { frt.typed = frt.typed.concat([{ flow: flow, username: u, password: p }]); return true }
    function cancelSignIn(flow) {}
    function markSignedIn() {}
    signal signInCode(string flow, string code, string url, real expires)
    signal signInDone(string flow, bool ok, string message)
    function last() { return frt.calls[frt.calls.length - 1] }
  }
  Component { id: rtKind; FakeRuntime {} }

  property int hexes: 0
  QtObject {
    id: store
    property var runtimes: ({})
    property var made: []
    property string status: ""
    property var ready: [{ id: "tv.example.app" }]
    property var faulted: ({})
    property var unavailable: ({})
    property var changing: ({})
    property var cleared: []
    property var usedIds: []
    property string blocked: ""          // cannotOpen's reason
    property var installed: ({
      "tv.example.app": { id: "tv.example.app", name: "Example", kind: "app", source: "bundled", from: "bundled", incarnation: "0123456789abcdef", values: {}, settings: [],
                          permissions: { net: [], server: null, play: false, signIn: "", storage: false } },
      "tv.example.web": { id: "tv.example.web", name: "Web", kind: "launcher", source: "bundled", from: "bundled", incarnation: "1111111111111111", values: {}, settings: [] },
      "tv.example.file": { id: "tv.example.file", name: "File", kind: "app", source: "file:0123456789abcdef", from: "file", incarnation: "2222222222222222", values: {}, settings: [] }
    })
    function record(id) { return store.installed[id] || null }
    function setRecord(id, change) { var all = {}; for (var k in store.installed) all[k] = store.installed[k]; var a = JSON.parse(JSON.stringify(all[id])); change(a); all[id] = a; store.installed = all }
    function cannotOpen(id) { return store.blocked }
    function clearFault(id) { store.cleared = store.cleared.concat([id]); var o = {}; for (var k in store.faulted) if (k !== id) o[k] = store.faulted[k]; store.faulted = o }
    function used(id) { store.usedIds = store.usedIds.concat([id]) }
    function randomHex(n) {
      root.hexes++
      var s = ""
      var x = root.hexes * 2654435761 % 4294967296
      while (s.length < n) { x = (x * 1103515245 + 12345) % 2147483648; s += ("0000000" + x.toString(16)).slice(-8) }
      return s.slice(0, n)
    }
    function installOf(a) { return a ? a.id + "|" + a.incarnation : "" }
    // the runtime budget as Apps.qml keeps it: three, AppBudget.js picks what makes room
    property bool budgetOn: false
    property var stoppedIds: []
    property var leasesAsked: []
    function live() {
      var n = 0
      for (var k in store.runtimes) if (["starting", "ready", "stopping"].indexOf(store.runtimes[k].phase) >= 0) n++
      return n
    }
    property string startPhase: "ready"   // what a new runtime starts as
    property var screenAtEnsure: []
    function ensure(id, lease) {
      store.leasesAsked = store.leasesAsked.concat([id + ":" + lease])
      store.screenAtEnsure = store.screenAtEnsure.concat([guide.screen])
      if (store.changing[id]) return { rt: null, why: "it's being changed; try again in a moment" }
      var rt = store.runtimes[id]
      if (!rt || rt.phase === "stopped") {
        var wait = false
        if (store.budgetOn && store.live() >= 3) {
          var now = {}
          for (var x in store.runtimes) { var o = store.runtimes[x]; now[x] = { phase: o.phase, leases: o.leases, busy: o.busy, lastUsed: o.lastUsed } }
          var room = Budget.makeRoom(now, store.changing, lease)
          if (room.refuse) return { rt: null, why: "three apps are busy" }
          if (room.stop) store.stoppedIds = store.stoppedIds.concat([room.stop])
          wait = true
        }
        rt = rtKind.createObject(root, { phase: wait ? "queued" : store.startPhase })
        var m = {}
        for (var k in store.runtimes) m[k] = store.runtimes[k]
        m[id] = rt
        store.runtimes = m
        store.made = store.made.concat([rt])
      }
      if (lease) rt.lease(lease, true)
      return { rt: rt, why: "" }
    }
    function runtime(id) { return store.runtimes[id] || null }
    function withKey(map, key, value) { var o = {}; for (var k in map) o[k] = map[k]; o[key] = value; return o }
    function pending(a, key) { return [] }
    function stopThen(id, reason, then) { then() }
  }

  QtObject { id: panelStub; property bool open: false; property bool renaming: false; function seenRows(a) { return [] } function openFor(id, by) { panelStub.open = true; return "ok" } }
  QtObject {
    id: guide
    property string lastInput: "keyboard"
    function noteInput(kind) { lastInput = kind }   // tablet mode: what was used last
    function keyFirst(event) { noteInput("keyboard"); return false }   // (Guide.qml: and the ⋯ panel)
    property var byUser: ({})
    property bool opened: true
    property string screen: "apps"
    property bool watching: false
    property var vod: null
    property bool appPlaying: false
    property bool pip: false
    property string codeApp: ""
    property string dialog: ""
    property bool railOpen: false
    property bool railEditing: false
    property string appOpening: ""
    property bool showKeyHints: true
    property bool muted: false
    property var opened_: []
    function openRail() { guide.opened_ = guide.opened_.concat(["rail"]); return true }
    function openStyle() { guide.opened_ = guide.opened_.concat(["style"]) }
    function setKeyHints(on) { guide.showKeyHints = on }
    function openHelp() { guide.dialog = "help" }
    property var currentTheme: ({ id: "retro", apps: {} })
    readonly property string configDir: "/tmp/om-pg-test-config"
    readonly property var apps: store
    readonly property var appView: view
    readonly property var appScreens: screens
    readonly property var appPanel: panelStub
    readonly property var snapshots: snaps
    property int playCalls: 0
    function openApps(back) { guide.screen = "apps" }
    function focusKeys() {}
    function fileUrl(p) { return "file://" + p }
    function playApp(id, rt, value) { guide.playCalls++ }
    function finishAppPlayback(id, reason, then) { then() }
    function appSignIn(id, by) {}
    function makeQr(url, done) {}
    readonly property var appHome: QtObject { function heldBy(rt) { return 0 } }
  }

  AppView { id: view; guide: guide }
  GuideKeys { id: keysItem; guide: guide }
  AppScreens {
    id: screens
    guide: guide
    reader: function(done) { done({ ok: true, text: "" }) }
    writer: function(text, done) { done({ ok: true, outcome: "saved" }) }
  }
  AppAgent { id: agent; guide: guide }
  Rectangle { id: shot; width: 320; height: 180 }
  property var grabs: []
  property var moves: []
  Snapshots {
    id: snaps
    guide: guide
    target: shot
    folder: "/tmp/om-pg-snaps"
    run: "0a1b2c3d4e5f60718293a4b5c6d7e8f9"
    grab: function(item, done, size) { root.grabs = root.grabs.concat([done]); return true }
    mover: function(argv, done) { root.moves = root.moves.concat([{ argv: argv, done: done }]) }
  }
  function grabNow() { root.grabs[root.grabs.length - 1]({ saveToFile: function(p) { return true } }) }

  function item(id, kind) { return { id: id, title: id, subtitle: "", badge: "", kind: kind || "open", image: null, progress: null } }
  function screenOf(title) {
    return { title: title, empty: "", refresh: null, rows: [{ id: "libs", title: "Libraries", layout: "row", items: [item("lib-a"), item("lib-b")] },
                                                           { id: "seasons", title: "Seasons", layout: "row", items: [item("s1", "info"), item("s2", "info")] }] }
  }
  function rtNow() { return store.made[store.made.length - 1] }

  TestCase {
    name: "AppOpen"
    when: windowShown

    function init() {
      store.runtimes = ({})
      store.made = []
      store.faulted = ({})
      store.unavailable = ({})
      store.changing = ({})
      store.cleared = []
      store.usedIds = []
      store.blocked = ""
      store.budgetOn = false
      store.stoppedIds = []
      store.leasesAsked = []
      store.screenAtEnsure = []
      store.startPhase = "ready"
      store.setRecord("tv.example.app", function(a) { a.source = "bundled"; a.kind = "app"; a.incarnation = "0123456789abcdef" })
      guide.screen = "apps"
      guide.opened = true
      guide.dialog = ""
      guide.watching = false
      guide.vod = null
      guide.appPlaying = false
      guide.pip = false
      guide.railOpen = false
      guide.appOpening = ""
      guide.playCalls = 0
      panelStub.open = false
      view.appId = ""
      view.stack = []
      view.pending = null
      view.refreshing = null
      view.failed = ""
      view.rt = null
      view.queued = null
      view.agentOpen = null
      view.waitingStart = false
      view.waitingFor = null
      view.settingsOpen = false
      view.signIn = null
      view.editing = null
      view.certOffer = null
      if (snaps.live) snaps.finish(snaps.live, "refused", "test")
      root.grabs = []
      root.moves = []
    }

    // openApp, its first screen answered: the view it said
    function openFirst() {
      var a = agent.openApp("tv.example.app", "")
      verify(a.ok, a.error)
      var rt = rtNow()
      compare(rt.last().method, "home")
      rt.last().done("screen", screenOf("Home"))
      compare(agent.appScreen("tv.example.app").view, a.view, "the view it said is the one on the screen")
      return { rt: rt, view: a.view }
    }

    // ---- the refusals, in order --------------------------------------------------
    function test_the_refusals_in_their_order() {
      // everything wrong at once; taking each away shows the next
      guide.dialog = "help"
      view.settingsOpen = true
      guide.watching = true
      store.blocked = "apps are off"
      var steps = [
        ["a box is open", function() { guide.dialog = "" }],
        ["an app's own box", function() { view.settingsOpen = false }],
        ["something is playing", function() { guide.watching = false }],
        ["apps are off", function() { store.blocked = "" }]
      ]
      steps.forEach(function(s) {
        var r = agent.openApp("tv.example.app", "")
        verify(!r.ok && r.error.indexOf(s[0]) >= 0, s[0] + ": " + r.error)
        s[1]()
      })
      compare(store.made.length, 0, "nothing started")
      compare(guide.screen, "apps", "and the screen didn't change")
      // the record's own: a launcher, a file app, faulted, unavailable, changing, stopping
      verify(agent.openApp("tv.example.web", "").error.indexOf("isn't an app with code") >= 0)
      verify(agent.openApp("tv.example.file", "").error.indexOf("comes with the guide") >= 0)
      store.faulted = { "tv.example.app": "crashed" }
      store.unavailable = { "tv.example.app": "no" }
      store.changing = { "tv.example.app": true }
      var stopping = rtKind.createObject(root, { phase: "stopping" })
      store.runtimes = { "tv.example.app": stopping }
      var last = [
        ["stopped working", function() { store.faulted = ({}) }],
        ["can't run on this system", function() { store.unavailable = ({}) }],
        ["being changed", function() { store.changing = ({}) }],
        ["stopping", function() { store.runtimes = ({}) }]
      ]
      last.forEach(function(s) {
        var r = agent.openApp("tv.example.app", "")
        verify(!r.ok && r.error.indexOf(s[0]) >= 0, s[0] + ": " + r.error)
        s[1]()
      })
      compare(store.made.length, 0)
      verify(agent.openApp("tv.example.app", "").ok, "and with nothing wrong, it opens")
    }

    function test_overlays_and_playing_each_refuse_data() {
      return [
        { tag: "its settings", set: function() { view.settingsOpen = true } },
        { tag: "its sign-in", set: function() { view.signIn = { code: "1" } } },
        { tag: "a text field", set: function() { view.editing = { type: "text" } } },
        { tag: "a certificate to pin", set: function() { view.certOffer = { sha256: "a" } } },
        { tag: "on demand", set: function() { guide.vod = { title: "x" } } },
        { tag: "an app's media", set: function() { guide.appPlaying = true } },
        { tag: "the mini player", set: function() { guide.pip = true } }
      ]
    }
    function test_overlays_and_playing_each_refuse(d) {
      d.set()
      verify(!agent.openApp("tv.example.app", "").ok)
      compare(store.made.length, 0)
    }

    function test_after_three_faults_nothing_but_the_users_own_open_tries_it() {
      store.faulted = { "tv.example.app": "it crashed three times" }
      var r = agent.openApp("tv.example.app", "")
      verify(!r.ok && r.error.indexOf("only the user's own open tries it again") >= 0, r.error)
      compare(store.cleared.length, 0, "the fault stays")
      compare(store.made.length, 0, "nothing started")
      compare(store.leasesAsked.length, 0, "not even asked")
      compare(guide.screen, "apps")
      compare(view.open("tv.example.app", guide.byUser), "ok", "the user's own open")
      compare(JSON.stringify(store.cleared), JSON.stringify(["tv.example.app"]), "clears it")
      compare(rtNow().last().method, "home")
    }

    // ---- the same steps as the user's open ----------------------------------------
    function test_the_same_start_as_the_users_open() {
      var o = openFirst()
      compare(JSON.stringify(store.leasesAsked), JSON.stringify(["tv.example.app:foreground"]), "the same ensure, with the screen's lease")
      compare(JSON.stringify(store.usedIds), JSON.stringify(["tv.example.app"]), "marked used, as the user's open does")
      compare(guide.screen, "app")
      compare(guide.codeApp, "tv.example.app")
      compare(store.cleared.length, 0, "never clears a fault")
    }

    function test_never_closes_a_box() {
      guide.dialog = "help"
      verify(!agent.openApp("tv.example.app", "").ok)
      compare(guide.dialog, "help")
    }

    function test_at_the_runtime_limit_the_same_budget_as_the_users() {
      store.budgetOn = true
      // three busy apps (on screens, starting, playing): refused, nothing stopped, nothing queued
      var m = {}
      ;["a", "b", "c"].forEach(function(k) { m["tv.example." + k] = rtKind.createObject(root, { phase: "starting" }) })
      store.runtimes = m
      var r = agent.openApp("tv.example.app", "")
      verify(!r.ok && r.error.indexOf("hree apps are busy") >= 0, r.error)
      compare(store.stoppedIds.length, 0, "nothing stopped")
      compare(store.runtimes["tv.example.app"], undefined, "nothing queued")
      // an idle one at the limit is stopped, and the open waits for its slot
      init()
      store.budgetOn = true
      m = {}
      ;["a", "b"].forEach(function(k) { var x = rtKind.createObject(root, { phase: "ready" }); x.lease("foreground", true); m["tv.example." + k] = x })
      m["tv.example.c"] = rtKind.createObject(root, { phase: "ready", lastUsed: 1 })
      store.runtimes = m
      r = agent.openApp("tv.example.app", "")
      verify(r.ok, r.error)
      compare(JSON.stringify(store.stoppedIds), JSON.stringify(["tv.example.c"]), "the idle one makes room")
      var rt = rtNow()
      compare(rt.phase, "queued", "the open waits for the slot")
      compare(rt.calls.length, 0, "nothing sent yet")
      rt.phase = "ready"
      rt.readyNow()
      compare(rt.last().method, "home", "then its first screen")
    }

    function test_the_runtime_limit_the_rest_of_its_cases() {
      store.budgetOn = true
      // the app's screen comes first, so Home rows' loads (and their leases)
      // are given back before ensure runs (AppHome lets go when the screen changes)
      guide.screen = "home"
      verify(agent.openApp("tv.example.app", "").ok)
      compare(JSON.stringify(store.screenAtEnsure), JSON.stringify(["app"]), "on the app's screen before ensure")
      // one runtime stopping: the open waits for it, nothing else stopped
      init()
      store.budgetOn = true
      store.runtimes = { "tv.example.a": rtKind.createObject(root, { phase: "starting" }), "tv.example.b": rtKind.createObject(root, { phase: "starting" }),
                         "tv.example.c": rtKind.createObject(root, { phase: "stopping" }) }
      verify(agent.openApp("tv.example.app", "").ok)
      compare(store.stoppedIds.length, 0)
      compare(rtNow().phase, "queued", "it waits for the slot")
      // a sign-out still out in a ready app with no lease, two others starting:
      // refused, the signing-out app isn't stopped, nothing queued; once it's
      // done and stopped, a retry goes through
      init()
      store.budgetOn = true
      var out = rtKind.createObject(root, { phase: "ready" })
      store.runtimes = { "tv.example.x": out, "tv.example.a": rtKind.createObject(root, { phase: "starting" }), "tv.example.b": rtKind.createObject(root, { phase: "starting" }) }
      store.changing = { "tv.example.x": true }
      var r = agent.openApp("tv.example.app", "")
      verify(!r.ok && r.error.indexOf("hree apps are busy") >= 0, r.error)
      compare(store.stoppedIds.length, 0, "the signing-out app isn't stopped")
      compare(store.runtimes["tv.example.app"], undefined, "nothing queued")
      out.phase = "stopped"
      store.changing = ({})
      verify(agent.openApp("tv.example.app", "").ok, "its sign-out done and stopped: a retry goes through")
      // a ready runtime with no lease and a call still out, not changing: never stopped
      init()
      store.budgetOn = true
      store.runtimes = { "tv.example.x": rtKind.createObject(root, { phase: "ready", busy: true }), "tv.example.a": rtKind.createObject(root, { phase: "starting" }),
                         "tv.example.b": rtKind.createObject(root, { phase: "starting" }) }
      r = agent.openApp("tv.example.app", "")
      verify(!r.ok, "refused")
      compare(store.stoppedIds.length, 0, "a call still out keeps it")
    }

    // ---- checked again right before every call ----------------------------------
    function test_checked_again_before_a_call_the_start_up_queue_sends_data() {
      return [
        { tag: "playback starting", why: "playing", set: function() { guide.appPlaying = true } },
        { tag: "a fault", why: "stopped working", set: function() { store.faulted = { "tv.example.app": "crashed" } } },
        { tag: "unavailable", why: "can't run", set: function() { store.unavailable = { "tv.example.app": "no" } } },
        { tag: "changing", why: "being changed", set: function() { store.changing = { "tv.example.app": true } } },
        { tag: "a box", why: "a box is open", set: function() { guide.dialog = "help" } },
        { tag: "another source", why: "comes with the guide", set: function() { store.setRecord("tv.example.app", function(a) { a.source = "file:0123456789abcdef" }) } },
        { tag: "another kind", why: "isn't an app with code", set: function() { store.setRecord("tv.example.app", function(a) { a.kind = "launcher" }) } },
        { tag: "a reinstall", why: "installed again", set: function() { store.setRecord("tv.example.app", function(a) { a.incarnation = "fedcba9876543210" }) } },
        { tag: "a runtime started again", why: "started again", set: function() { view.rt = rtKind.createObject(root, { phase: "starting", gen: 2 }) } }
      ]
    }
    function test_checked_again_before_a_call_the_start_up_queue_sends(d) {
      store.startPhase = "starting"
      var a = agent.openApp("tv.example.app", "")
      verify(a.ok, a.error)
      var rt = view.rt
      compare(rt.calls.length, 0, "waiting for the app to start")
      d.set()
      view.rt.phase = "ready"
      view.rt.readyNow()
      compare(rt.calls.length, 0, "nothing sent to the app it opened")
      compare(view.rt.calls.length, 0, "nor to any other")
      verify(view.failed.indexOf("Stopped opening it for an agent") === 0 && view.failed.indexOf(d.why) > 0, view.failed)
      compare(view.agentOpen, null)
    }

    function test_checked_again_before_the_items_call_data() {
      return [
        { tag: "playback starting", set: function() { guide.appPlaying = true } },
        { tag: "a fault", set: function() { store.faulted = { "tv.example.app": "crashed" } } },
        { tag: "a reinstall", set: function() { store.setRecord("tv.example.app", function(a) { a.incarnation = "fedcba9876543210" }) } },
        { tag: "the rail's Customize box", set: function() { guide.dialog = "style" } }
      ]
    }
    function test_checked_again_before_the_items_call(d) {
      var o = openFirst()
      var h = agent.appScreen("tv.example.app").items.filter(function(x) { return x.kind === "open" })[1].handle
      var a = agent.openApp("tv.example.app", h)
      verify(a.ok, a.error)
      var rt = o.rt
      compare(rt.last().method, "home", "its first screen again first: a handle is never sent before home returns")
      var n = rt.calls.length
      rt.last().done("screen", screenOf("Home"))
      d.set()
      wait(0)   // the item's call goes a moment after
      compare(rt.calls.length, n, "the item's call isn't sent")
      verify(view.failed.indexOf("Stopped opening it for an agent") === 0, view.failed)
    }

    function test_an_items_handle_opens_that_item() {
      var o = openFirst()
      var items = agent.appScreen("tv.example.app").items
      var lib = items.filter(function(x) { return x.kind === "open" && x.position === 1 })[0]
      var season = items.filter(function(x) { return x.kind === "info" && x.position === 1 })[0]
      var a = agent.openApp("tv.example.app", lib.handle)
      verify(a.ok, a.error)
      o.rt.last().done("screen", screenOf("Home"))
      tryVerify(function() { return o.rt.last().method === "browse" }, 1000)
      compare(o.rt.last().args.item, "lib-b", "the second library, by its handle")
      o.rt.last().done("screen", screenOf("Library B"))
      compare(agent.appScreen("tv.example.app").view, a.view, "the view it said")
      // an info item opens its details (the handle is for the screen it came from)
      var home = agent.openApp("tv.example.app", "")
      o.rt.last().done("screen", screenOf("Home"))
      season = agent.appScreen("tv.example.app").items.filter(function(x) { return x.kind === "info" && x.position === 1 })[0]
      a = agent.openApp("tv.example.app", season.handle)
      o.rt.last().done("screen", screenOf("Home"))
      tryVerify(function() { return o.rt.last().method === "details" }, 1000)
      compare(o.rt.last().args.item, "s2")
    }

    function test_a_stale_handle_fails() {
      var o = openFirst()
      var h = agent.appScreen("tv.example.app").items[0].handle
      var again = agent.openApp("tv.example.app", "")
      o.rt.last().done("screen", screenOf("Home"))
      var r = agent.openApp("tv.example.app", h)
      verify(!r.ok && r.error.indexOf("stale") >= 0, "a handle from a view that's gone: " + r.error)
      verify(!agent.openApp("tv.example.app", "i-0000000000000000").ok)
      verify(!agent.openApp("tv.example.app", "lib-a").ok, "an app's own id is just unknown")
    }

    function test_never_play_a_button_sign_in_or_settings() {
      var o = openFirst()
      ;["play", "action", "signIn", "settings", "search"].forEach(function(m) {
        view.agentOpen = { guard: function() { return "" } }
        var n = o.rt.calls.length
        view.ask(m, {}, "push")
        compare(o.rt.calls.length, n, m + " isn't sent for an agent")
        verify(view.failed.indexOf("only screens and details") > 0, view.failed)
        view.failed = ""
      })
    }

    // ---- you, doing anything yourself, end it ---------------------------------------
    function test_you_doing_anything_ends_it_data() {
      return [
        { tag: "a move", act: function() { view.move("right") } },
        { tag: "Back", act: function() { view.back() } },
        { tag: "R", act: function() { view.reload(guide.byUser) } },
        { tag: "settings", act: function() { view.openSettings(guide.byUser) } },
        { tag: "search", act: function() { view.startSearch(guide.byUser) } },
        { tag: "your own open", act: function() { view.open("tv.example.app", guide.byUser) } }
      ]
    }
    function test_you_doing_anything_ends_it(d) {
      var o = openFirst()
      var h = agent.appScreen("tv.example.app").items[0].handle
      verify(agent.openApp("tv.example.app", h).ok)
      var homeCall = o.rt.last()
      d.act()
      compare(view.agentOpen, null, "its open is over")
      var n = o.rt.calls.length
      homeCall.done("screen", screenOf("Home"))
      wait(0)
      verify(o.rt.calls.slice(n).every(function(c) { return c.method !== "browse" }), "and the item it had waiting is never sent unchecked")
    }

    // the moment after its first screen is in, before its item goes: you
    // acting then, or a newer open, ends it, and its item is never sent
    function test_the_item_waiting_a_moment_ends_with_it_data() {
      return [
        { tag: "a move", act: function() { view.move("right") } },
        { tag: "a newer open", act: function() { verify(agent.openApp("tv.example.app", "").ok) } },
        { tag: "your own open", act: function() { view.open("tv.example.app", guide.byUser) } }
      ]
    }
    function test_the_item_waiting_a_moment_ends_with_it(d) {
      var o = openFirst()
      var h = agent.appScreen("tv.example.app").items[0].handle
      verify(agent.openApp("tv.example.app", h).ok)
      o.rt.last().done("screen", screenOf("Home"))      // its first screen: the item would go a moment later
      var n = o.rt.calls.length
      d.act()
      wait(0)
      wait(0)
      verify(o.rt.calls.slice(n).every(function(c) { return c.method !== "browse" }), "the first open's item never goes: " + JSON.stringify(o.rt.calls.slice(n).map(function(c) { return c.method })))
    }

    // a step for an open that isn't the live one fails closed, whatever sent it
    function test_a_step_for_another_open_is_never_sent() {
      var o = openFirst()
      var stale = { guard: function() { return "" } }
      var n = o.rt.calls.length
      view.ask("browse", { item: "lib-a" }, "push", stale)
      compare(o.rt.calls.length, n, "no open live: nothing sent")
      verify(agent.openApp("tv.example.app", "").ok)
      n = o.rt.calls.length
      view.ask("browse", { item: "lib-a" }, "push", stale)
      compare(o.rt.calls.length, n, "another open live: nothing sent either")
    }

    // the keys you press (through the guide's own key handler) end it
    function test_any_key_ends_it_data() {
      return [{ tag: "C (Customize)", key: Qt.Key_C }, { tag: "K (key hints)", key: Qt.Key_K }, { tag: "M (mute)", key: Qt.Key_M },
              { tag: "S (style)", key: Qt.Key_S }, { tag: "← at the edge (the rail)", key: Qt.Key_Left }, { tag: "?", key: Qt.Key_Question }]
    }
    function test_any_key_ends_it(d) {
      guide.screen = "app"
      var o = openFirst()
      var h = agent.appScreen("tv.example.app").items[0].handle
      verify(agent.openApp("tv.example.app", h).ok)
      var homeCall = o.rt.last()
      keysItem.forceActiveFocus()
      keyClick(d.key)
      compare(view.agentOpen, null, "its open is over")
      var n = o.rt.calls.length
      homeCall.done("screen", screenOf("Home"))
      wait(0)
      verify(o.rt.calls.slice(n).every(function(c) { return c.method !== "browse" }), "its item never goes")
      panelStub.open = false
      guide.showKeyHints = true
      guide.muted = false
    }

    // its first screen, sent once the app has started, is a step of the open
    // too: with nothing in between it goes, checked; a key you press while
    // the app starts ends the open, and nothing goes until you ask (Enter)
    function test_its_first_screen_once_started_goes_checked() {
      store.startPhase = "starting"
      verify(agent.openApp("tv.example.app", "").ok)
      var rt = view.rt
      compare(rt.calls.length, 0, "waiting for the app to start")
      rt.phase = "ready"
      rt.readyNow()
      compare(rt.calls.length, 1)
      compare(rt.last().method, "home", "its first screen, once it's ready")
    }
    function test_its_first_screen_ends_with_the_open_data() {
      return [{ tag: "K (key hints)", key: Qt.Key_K }, { tag: "C (Customize)", key: Qt.Key_C }, { tag: "M (mute)", key: Qt.Key_M }]
    }
    function test_its_first_screen_ends_with_the_open(d) {
      guide.screen = "app"
      store.startPhase = "starting"
      verify(agent.openApp("tv.example.app", "").ok)
      var rt = view.rt
      keysItem.forceActiveFocus()
      keyClick(d.key)
      compare(view.agentOpen, null, "its open is over")
      rt.phase = "ready"
      rt.readyNow()
      compare(rt.calls.length, 0, "its first screen isn't sent once you've taken over")
      verify(view.failed.indexOf("you took over") > 0, view.failed)
      panelStub.open = false
      view.enter(guide.byUser)
      compare(rt.calls.length, 1, "Enter: your own")
      compare(rt.last().method, "home")
      guide.showKeyHints = true
      guide.muted = false
    }
    function test_a_newer_open_while_it_starts_takes_its_place() {
      store.startPhase = "starting"
      verify(agent.openApp("tv.example.app", "").ok)
      var first = view.agentOpen
      verify(agent.openApp("tv.example.app", "").ok)
      verify(view.agentOpen !== first, "a newer open")
      view.rt.phase = "ready"
      view.rt.readyNow()
      compare(view.rt.calls.length, 1, "one first screen, the newer open's")
    }

    function test_customize_and_the_rail_count_as_boxes() {
      panelStub.open = true
      verify(agent.openApp("tv.example.app", "").error.indexOf("a box is open") >= 0)
      panelStub.open = false
      guide.railOpen = true
      verify(agent.openApp("tv.example.app", "").error.indexOf("a box is open") >= 0)
      guide.railOpen = false
      compare(store.made.length, 0)
    }

    // ---- view identity, from openApp to the poll to the picture -------------------
    function test_the_workflow_ends_in_a_picture_of_that_view() {
      var o = openFirst()
      var s = agent.appScreen("tv.example.app")
      compare([s.view, s.state, s.covered, s.picturesPending], [o.view, "ready", false, 0])
      var shotA = agent.appSnapshot(o.view)
      verify(shotA.ok, shotA.error)
      root.grabNow()
      root.moves[0].done(true)
      compare(snaps.report.outcome, "written")
      compare(snaps.report.name, shotA.name)
    }

    function test_moving_back_or_a_restart_between_the_steps_fails_explicitly_data() {
      return [
        { tag: "navigation", go: function(o) { view.enter(guide.byUser); o.rt.last().done("screen", screenOf("Inside")) } },
        { tag: "Back", go: function(o) { view.enter(guide.byUser); o.rt.last().done("screen", screenOf("Inside")); view.back() } },
        { tag: "a restart", go: function(o) { o.rt.stop(""); view.loadRoot(); rtNow().last().done("screen", screenOf("Home")) } }
      ]
    }
    function test_moving_back_or_a_restart_between_the_steps_fails_explicitly(d) {
      // between openApp and the poll
      var o = openFirst()
      d.go(o)
      var s = agent.appScreen("tv.example.app")
      verify(s.view !== o.view, "the poll sees another view: " + s.view)
      var r = agent.appSnapshot(o.view)
      verify(!r.ok && r.error.indexOf("that view isn't the one on the screen") >= 0, r.error)
      // between the poll and the capture's grab
      init()
      o = openFirst()
      verify(agent.appSnapshot(o.view).ok)
      d.go(o)
      root.grabNow()
      compare(snaps.report.outcome, "refused")
      verify(snaps.report.why.indexOf("that view isn't the one on the screen") >= 0 || snaps.report.why.indexOf("while the picture was taken") >= 0, snaps.report.why)
      compare(root.moves.length, 0, "no file")
    }

    function test_the_rail_customize_help_and_the_style_panel_between_the_steps_data() {
      return [
        { tag: "the rail", set: function() { guide.railOpen = true } },
        { tag: "Customize", set: function() { panelStub.open = true } },
        { tag: "help", set: function() { guide.dialog = "help" } },
        { tag: "the style panel", set: function() { guide.dialog = "style" } }
      ]
    }
    function test_the_rail_customize_help_and_the_style_panel_between_the_steps(d) {
      var o = openFirst()
      // between the poll and the capture: an error answer
      d.set()
      compare(agent.appScreen("tv.example.app").covered, true)
      verify(!agent.appSnapshot(o.view).ok)
      compare(root.grabs.length, 0)
      // between the request and the grab: refused, no file
      guide.railOpen = false
      panelStub.open = false
      guide.dialog = ""
      verify(agent.appSnapshot(o.view).ok)
      d.set()
      root.grabNow()
      compare(snaps.report.outcome, "refused")
      compare(root.moves.length, 0)
    }
  }
}
