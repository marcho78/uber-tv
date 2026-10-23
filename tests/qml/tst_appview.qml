import QtQuick
import QtTest
import "../.."
import "../../AppBudget.js" as Budget

// AppView.qml against a pretend guide, store and runtime: an answer for a
// view epoch that's over, or from a runtime that isn't the app's now, never
// reaches the screen. Run: /usr/lib/qt6/bin/qmltestrunner -input tests/qml
Item {
  id: root

  // a runtime that answers only when the test says so
  component FakeRuntime: QtObject {
    id: frt
    property string phase: "ready"
    property var calls: []          // [{ id, method, args, done }]
    property var leases: ({})
    property int nextId: 1
    property var cancelled: []
    property string stoppedWith: ""
    signal readyNow()
    signal stopped(string why, string text)
    function call(method, args, done) {
      var c = { id: frt.nextId++, method: method, args: args, done: done }
      frt.calls = frt.calls.concat([c])
      return c.id
    }
    function cancel(id) {
      frt.cancelled = frt.cancelled.concat([id])
      for (var i = 0; i < frt.calls.length; i++) if (frt.calls[i].id === id) frt.calls[i].done("error", { code: "cancelled", text: "cancelled" })
    }
    function lease(name, on) { var l = {}; for (var k in frt.leases) l[k] = true; if (on) l[name] = true; else delete l[name]; frt.leases = l }
    property var asked: []          // [{ token, done, epoch, prio }]
    property int demand: 0
    property var released: []       // result ids the view let go of
    function image(token, done, epoch, prio, consumer, broken) { frt.asked = frt.asked.concat([{ token: token, done: done, epoch: epoch, prio: prio, consumer: consumer, broken: broken }]) }
    property var demands: []        // the demand epochs told to the helper
    function newDemand() { frt.demand += 1; frt.demands = frt.demands.concat([frt.demand]); return frt.demand }
    function release(results) { frt.released = frt.released.concat(results) }
    function stop(forget) { frt.stoppedWith = forget || "normal"; guide.order = guide.order.concat(["stop:" + (forget || "")]); frt.phase = "stopped"; frt.stopped("normal", "") }
    function signIn(flow, how, done) { return frt.call("signIn", { flow: flow, how: how }, done) }
    property var typed: []
    function sendPassword(flow, u, p) { frt.typed = frt.typed.concat([{ flow: flow, username: u, password: p }]); return true }
    function cancelSignIn(flow) { frt.cancelled = frt.cancelled.concat(["flow:" + flow]) }
    property int markedSignedIn: 0
    function markSignedIn() { frt.markedSignedIn++ }
    property var chose: []
    property var lived: []          // viewOn and viewOff, in order: "on:<id>", "off:<id>"
    function viewOn(v) { frt.lived = frt.lived.concat(["on:" + v]); return true }
    function viewOff(v) { frt.lived = frt.lived.concat(["off:" + v]); return true }
    function chooseServer(flow, handle, url) { frt.chose = frt.chose.concat([{ flow: flow, handle: handle, url: url }]); return true }
    function typedServer(flow, handle, address) { frt.chose = frt.chose.concat([{ flow: flow, handle: handle, typed: address }]); return true }
    signal signInCode(string flow, string code, string url, real expires)
    signal signInDone(string flow, bool ok, string message)
    function last() { return frt.calls[frt.calls.length - 1] }
  }

  Component { id: rtKind; FakeRuntime {} }

  QtObject {
    id: store
    property var runtimes: ({})
    property var made: []
    property string status: ""
    property var ready: [{ id: "tv.example.app" }]
    property var values: ({})
    property var perms: null          // a test's own permissions (null: the plain ones)
    property string server: ""
    function record(id) {
      return { id: id, name: "App", kind: "app", from: "bundled", icon: "", values: store.values, server: store.server,
               settings: [{ key: "league", type: "choice", label: "League", choices: ["A", "B"] }],
               permissions: store.perms || { net: [], server: null, play: false, signIn: "", storage: false } }
    }
    // wrong passwords, as Apps.qml counts them (its own logic: tests/qml/appstate.shell.qml)
    property int fails: 0
    property int worked: 0
    property int waitSeconds: 0
    function passwordWait(id) { return store.waitSeconds }
    function passwordFailed(id) { store.fails++ }
    function passwordWorked(id) { store.worked++ }
    function cannotOpen(id) { return "" }
    function clearFault(id) {}
    function used(id) {}
    property var changing: ({})
    function setChanging(id, on) { var o = {}; for (var k in store.changing) if (k !== id) o[k] = true; if (on) o[id] = true; store.changing = o }
    property string install: "v1"
    function pending(a, key) { return a && a.values && Array.isArray(a.values[key]) ? a.values[key] : [] }
    function pend(id, key, items) { var cur = store.pending(store.record(id), key); store.setValue(id, key, cur.concat(items.filter(function(x) { return cur.indexOf(x) < 0 }))) }
    function unpend(id, key, items) {
      if (store.values[key] === undefined) return
      var left = store.pending(store.record(id), key).filter(function(x) { return items.indexOf(x) < 0 })
      if (left.length) store.setValue(id, key, left); else store.dropValue(id, key)
    }
    function installOf(a) { return a ? a.id + "|" + store.install : "" }
    property bool saveFails: false    // apps.json can't be written
    property string saveError: ""
    function commit(id, change) {
      if (store.saveFails) { store.saveError = "Permission denied"; return false }
      var a = store.record(id)
      change(a)
      store.values = a.values
      return true
    }
    // budgetOn: the runtime budget as Apps.qml keeps it (three; AppBudget.js
    // picks what makes room), with the other apps' runtimes as plain records
    property bool budgetOn: false
    property var stoppedIds: []
    function live() {
      var n = 0
      for (var k in store.runtimes) if (["starting", "ready", "stopping"].indexOf(store.runtimes[k].phase) >= 0) n++
      return n
    }
    function ensure(id, lease) {
      if (store.changing[id]) return { rt: null, why: "it's being changed; try again in a moment" }
      var rt = store.runtimes[id]
      if (!rt || rt.phase === "stopped") {
        var wait = false
        if (store.budgetOn && store.live() >= 3) {
          var now = {}
          for (var x in store.runtimes) {
            var o = store.runtimes[x]
            now[x] = { phase: o.phase, leases: o.leases, busy: !!o.busy, lastUsed: o.lastUsed || 0 }
          }
          var room = Budget.makeRoom(now, store.changing, lease)
          if (room.refuse) return { rt: null, why: "three apps are busy" }
          if (room.stop) store.stoppedIds = store.stoppedIds.concat([room.stop])
          wait = true
        }
        rt = rtKind.createObject(root, { phase: wait ? "queued" : "ready" })
        var m = {}
        for (var k in store.runtimes) if (store.budgetOn) m[k] = store.runtimes[k]
        m[id] = rt
        store.runtimes = m
        store.made = store.made.concat([rt])
      }
      if (lease) rt.lease(lease, true)
      return { rt: rt, why: "" }
    }
    function withKey(map, key, value) { var o = {}; for (var k in map) o[k] = map[k]; o[key] = value; return o }
    property int authCount: 0
    function authChanged(id) { store.authCount++ }
    function setValue(id, key, value) { store.values = store.withKey(store.values, key, value) }
    function dropValue(id, key) { var o = {}; for (var k in store.values) if (k !== key) o[k] = store.values[k]; store.values = o }
    function runtime(id) { return store.runtimes[id] || null }
    property var forgot: []
    property var forgetLater: null    // set: forget waits, and this is its done
    property bool holdForget: false
    property string forgetFails: ""
    function forget(id, what, done) {
      store.forgot = store.forgot.concat([id + ":" + what]); guide.order = guide.order.concat(["forget:" + what])
      var fin = function(ok, why) { if (ok) store.unpend(id, "@forget", [what]); done(ok, why) }
      if (store.holdForget) store.forgetLater = fin
      else if (store.forgetFails) fin(false, store.forgetFails)
      else fin(true, "")
    }
    // choosing the server while signing in (Apps.qml's own: tests/qml/appstate.shell.qml)
    property var servers: []          // what setServer was asked
    function setServer(id, text, done) { store.servers = store.servers.concat([text]); store.server = text; done(true, "") }
    signal liveUpdated(string id, var rt, int view, var rows, var items)
    property var keptWith: []         // what signedInWith was asked
    property string keepFails: ""
    function signedInWith(id, server, install) {
      store.keptWith = store.keptWith.concat([{ server: server, install: install }])
      if (store.keepFails) return { ok: false, why: store.keepFails }
      store.server = server
      store.values = store.withKey(store.values, "@signedIn", true)
      return { ok: true, why: "" }
    }
    property bool canonicalLater: false   // set: the check waits, and this is its done
    property var canonicalDone: null
    function canonicalServer(text, done) {
      var fin = function() { done(!/^ftp:/.test(text), /^ftp:/.test(text) ? "" : text.replace(/\/?$/, "/"), "not http or https") }
      if (store.canonicalLater) store.canonicalDone = fin
      else fin()
    }
    function stopRuntime(id, forget, reason) { var rt = store.runtimes[id]; if (rt) guide.finishAppPlayback(id, reason, function() { rt.stop(forget) }) }
    function stopThen(id, reason, then) {
      var rt = store.runtimes[id]
      guide.finishAppPlayback(id, reason, function() { if (rt && rt.phase !== "stopped") rt.stop(""); then() })
    }
  }

  QtObject {
    id: guide
    property var byUser: ({})
    property bool opened: true
    property string screen: "apps"
    property bool watching: false
    property string codeApp: ""
    property string dialog: ""
    readonly property var apps: store
    property int playCalls: 0
    property var order: []
    function openApps(back) { guide.screen = "apps" }
    function focusKeys() {}
    function fileUrl(p) { return "file://" + p }
    function playApp(id, rt, value) { guide.playCalls++ }
    property var valuesAtFinish: null
    function finishAppPlayback(id, reason, then) { guide.valuesAtFinish = store.values; guide.order = guide.order.concat(["finish:" + reason]); then() }
    function appSignIn(id, by) {}
    property var qrAsked: []          // [{ url, done }]
    function makeQr(url, done) { guide.qrAsked = guide.qrAsked.concat([{ url: url, done: done }]) }
    // the app's Home rows: how many pictures they hold in its helper
    property int homeHeld: 0
    readonly property var appHome: QtObject { function heldBy(rt) { return guide.homeHeld } }
  }

  AppView { id: view; guide: guide }

  function screenOf(title, items) {
    return { title: title, empty: "", refresh: null, rows: [{ id: "r", title: "R", layout: "row",
             items: items.map(function(i) { return { id: i, title: i, subtitle: "", badge: "", kind: "open", image: null, progress: null } }) }] }
  }

  TestCase {
    name: "AppView"

    function init() {
      store.runtimes = ({})
      store.made = []
      store.values = ({})
      view.appId = ""
      view.stack = []
      view.pending = null
      view.refreshing = null
      view.failed = ""
      view.rt = null
      guide.screen = "apps"
      store.changing = ({})
      store.saveFails = false
      store.holdForget = false
      store.forgetLater = null
      store.install = "v1"
      store.forgetFails = ""
      store.forgot = []
      guide.qrAsked = []
      view.signIn = null
      store.budgetOn = false
      store.stoppedIds = []
      guide.homeHeld = 0
      view.wanted = ({})
      view.imagePaths = ({})
      view.imageInfo = ({})
      view.retried = ({})
      view.brokenRetried = ({})
    }

    function openAndLoad() {
      compare(view.open("tv.example.app", guide.byUser), "ok")
      var rt = store.made[store.made.length - 1]
      compare(rt.last().method, "home")
      rt.last().done("screen", screenOf("Home", ["a", "b"]))
      compare(view.stack.length, 1)
      return rt
    }

    function test_a_live_screen_is_on_while_its_shown() {
      compare(view.open("tv.example.app", guide.byUser), "ok")
      var rt = store.made[store.made.length - 1]
      guide.screen = "app"
      var live = screenOf("Live", ["a", "b"])
      live.live = true
      live.rows.push({ id: "r2", title: "R2", layout: "row", items: [{ id: "x", title: "x", subtitle: "", badge: "", kind: "open", image: null, progress: null }] })
      var first = rt.last()
      first.done("screen", live)
      var rid = view.topView.result
      compare(rt.lived, ["on:" + rid], "on as it's shown")
      // pushed under another view: off; back on top: on again
      view.ask("browse", { item: "a" }, "push")
      rt.last().done("screen", screenOf("Other", ["c"]))
      compare(rt.lived[rt.lived.length - 1], "off:" + rid)
      view.back()
      compare(rt.lived[rt.lived.length - 1], "on:" + rid)
      // an update replaces rows by id, and the selection stays on its item
      view.move("down")
      compare(view.topView.sel.row, "r2")
      store.liveUpdated("tv.example.app", rt, rid, [{ id: "r", title: "R", layout: "row",
        items: [{ id: "a", title: "A new", subtitle: "", badge: "", kind: "open", image: null, progress: null }] }], null)
      compare(view.topView.value.rows[0].items[0].title, "A new")
      compare(view.topView.value.rows.length, 2, "never a new row")
      compare(view.topView.sel.row, "r2", "the selection where it was")
      store.liveUpdated("tv.example.app", rt, 99999, [{ id: "r", title: "R", layout: "row", items: [] }], null)
      compare(view.topView.value.rows[0].items[0].title, "A new", "another view's update changes nothing")
      // the guide leaves the app: off
      guide.screen = "apps"
      compare(rt.lived[rt.lived.length - 1], "off:" + rid)
      guide.screen = "app"
      compare(rt.lived[rt.lived.length - 1], "on:" + rid)
      guide.screen = "apps"
    }

    function test_a_screen_that_isnt_live_is_never_on() {
      guide.screen = "app"
      var rt = openAndLoad()
      compare(rt.lived, [])
      guide.screen = "apps"
    }

    function test_only_the_user_opens() {
      compare(view.open("tv.example.app", {}), "only the user, at the screen")
      compare(guide.screen, "apps")
    }

    function test_open_loads_the_first_screen() {
      var rt = openAndLoad()
      compare(guide.screen, "app")
      compare(view.topView.value.title, "Home")
      verify(rt.leases.foreground === true, "the screen holds its lease")
    }

    function test_back_drops_the_answer() {
      var rt = openAndLoad()
      view.enter(guide.byUser)                         // browse "a"
      var browse = rt.last()
      compare(browse.method, "browse")
      compare(browse.args.item, "a")
      view.back()                                      // Esc: called off
      verify(rt.cancelled.indexOf(browse.id) >= 0)
      browse.done("screen", screenOf("Late", ["x"]))   // it answers anyway
      compare(view.stack.length, 1, "a called-off answer never lands")
      compare(view.topView.value.title, "Home")
    }

    function test_refresh_dropped_after_navigation() {
      var rt = openAndLoad()
      view.reload(guide.byUser)                         // a refresh out
      var refresh = rt.last()
      view.enter(guide.byUser)                          // then you open something
      var browse = rt.last()
      browse.done("screen", screenOf("Inside", ["y"]))
      compare(view.stack.length, 2)
      refresh.done("screen", screenOf("Home again", ["a"]))
      compare(view.topView.value.title, "Inside", "the old screen's refresh doesn't replace the new one")
      compare(view.stack[0].value.title, "Home")
    }

    function test_refresh_keeps_the_place() {
      var rt = openAndLoad()
      view.move("right")
      compare(view.topView.sel.col, 1)
      view.reload(guide.byUser)
      rt.last().done("screen", screenOf("Home", ["new", "a", "b"]))
      compare(view.topView.sel.col, 2, "still on b, which moved")
    }

    function test_setting_change_while_a_call_is_out() {
      var rt = openAndLoad()
      view.enter(guide.byUser)
      var browse = rt.last()
      view.openSettings(guide.byUser)
      view.settingsAct(1, guide.byUser)                 // League: A -> B, the app starts again
      compare(store.values.league, "B")
      compare(rt.stoppedWith, "normal")
      var fresh = store.made[store.made.length - 1]
      verify(fresh !== rt, "a new runtime")
      browse.done("screen", screenOf("Old settings", ["z"]))
      compare(view.stack.length, 0, "the old generation's answer doesn't show")
      compare(fresh.last().method, "home", "the new one loads from its first screen")
      fresh.last().done("screen", screenOf("New settings", ["q"]))
      compare(view.topView.value.title, "New settings")
    }

    function test_another_runtimes_answer_is_dropped() {
      var rt = openAndLoad()
      view.enter(guide.byUser)
      var browse = rt.last()
      view.rt = rtKind.createObject(root)               // the app was started again meanwhile
      browse.done("screen", screenOf("Stray", ["s"]))
      compare(view.stack.length, 1)
    }

    function test_errors_and_messages() {
      var rt = openAndLoad()
      view.enter(guide.byUser)
      rt.last().done("error", { code: "app", text: "the server is down" })
      compare(view.message, "The server is down.")
      compare(view.stack.length, 1)
      view.details(guide.byUser)
      rt.last().done("message", { text: "Saved" })
      compare(view.message, "Saved")
    }

    function test_root_failure_and_retry() {
      compare(view.open("tv.example.app", guide.byUser), "ok")
      var rt = store.made[store.made.length - 1]
      rt.last().done("error", { code: "fetch", text: "offline" })
      compare(view.failed, "Offline.")
      view.enter(guide.byUser)                          // Enter tries again
      compare(rt.last().method, "home")
      rt.last().done("screen", screenOf("Home", ["a"]))
      compare(view.failed, "")
    }

    function test_sign_out_in_order() {
      var rt = openAndLoad()
      guide.order = []
      store.values = store.withKey(store.values, "@signedIn", true)
      view.signOut(guide.byUser)
      compare(guide.order, ["finish:signOut"], "playback is finalized first")
      var c = rt.last()
      compare(c.method, "signOut", "then the app's signOut")
      c.done("ok", true)
      compare(guide.order, ["finish:signOut", "finish:user", "stop:", "forget:signIn"], "then the guide stops it, then forgets the sign-in itself")
      compare(store.values["@signedIn"], undefined)
    }

    function test_sign_out_even_if_the_app_fails() {
      var rt = openAndLoad()
      guide.order = []
      view.signOut(guide.byUser)
      rt.last().done("error", { code: "timeout", text: "it took too long" })
      compare(guide.order[guide.order.length - 1], "forget:signIn", "whatever the app answered")
    }

    function test_sign_in_flow_and_cancel() {
      var rt = openAndLoad()
      store.values = store.withKey(store.values, "x", 1)
      // no server: it says so
      view.startSignIn(guide.byUser)
      compare(view.signIn, null)
    }

    function test_password_sign_in() {
      store.perms = { net: [], server: { label: "S", defaultPort: 0 }, play: false, signIn: "code+password", storage: false }
      store.server = "http://s.example"
      var rt = openAndLoad()
      compare(view.settingsRows.filter(function(r) { return r.type === "signIn" }).map(function(r) { return r.label }),
              ["Sign in with a code", "Sign in with your username and password"], "a row for each way it offers")
      view.startSignIn(guide.byUser, "password")
      compare(view.signIn.how, "password")
      compare(view.signIn.stage, "typing")
      compare(rt.last().method, "signIn")
      compare(rt.last().args.how, "password")
      verify(!view.sendPassword("alex", "pw-1", {}), "only the user's own keys")
      verify(!view.sendPassword("", "pw-1", guide.byUser), "both are needed")
      compare(rt.typed.length, 0)
      verify(view.sendPassword("alex", "pw-1", guide.byUser))
      compare(rt.typed.length, 1)
      compare(rt.typed[0].username, "alex")
      compare(rt.typed[0].flow, view.signIn.flow)
      compare(view.signIn.stage, "checking", "the box says it's signing in")
      verify(view.signIn.password === undefined && view.signIn.username === undefined, "nothing typed is kept in the view")
      verify(!view.sendPassword("alex", "pw-2", guide.byUser), "sent once")
      // a code for this password sign-in (a buggy app) changes nothing
      var before = JSON.stringify(view.signIn)
      view.gotCode(view.signIn.flow, "123456", "", 60)
      compare(JSON.stringify(view.signIn), before, "the password box stays, and its stage")
      view.signInOver(view.signIn.flow, false, "Wrong password.")
      compare(store.fails, 1, "a password that was sent and didn't work counts")
      // one over before anything was sent (called off, or the app gave up) doesn't count
      view.startSignIn(guide.byUser, "password")
      view.signInOver(view.signIn.flow, false, "")
      compare(store.fails, 1)
      view.startSignIn(guide.byUser, "password")
      view.cancelSignIn()
      compare(store.fails, 1)
      // too many: it waits
      store.waitSeconds = 12
      view.settingsNote = ""
      view.startSignIn(guide.byUser, "password")
      compare(view.signIn, null)
      compare(view.settingsNote, "Too many wrong passwords: try again in 12 seconds.")
      store.waitSeconds = 0
      view.startSignIn(guide.byUser, "code")
      compare(view.signIn.how, "code", "a code isn't held up by wrong passwords")
      view.cancelSignIn()
      // signed in: Sign out, whatever the ways
      store.values = store.withKey(store.values, "@signedIn", true)
      compare(view.settingsRows.filter(function(r) { return r.type === "signIn" }).map(function(r) { return r.label }), ["Sign out"])
      store.perms = null
      store.server = ""
    }

    function test_choosing_its_server_while_signing_in() {
      store.perms = { net: [], server: { label: "S", defaultPort: 0, fromSignIn: true }, play: false, signIn: "code", storage: false }
      store.server = ""
      store.servers = []
      store.keptWith = []
      store.keepFails = ""
      var rt = openAndLoad()
      view.startSignIn(guide.byUser, "code")
      verify(view.signIn !== null, "it starts without a server: the account will list them")
      var flow = view.signIn.flow
      view.gotServers("other-flow", [{ handle: "x", label: "X", urls: ["http://x/"] }])
      compare(view.signInRows.length, 0, "another flow's servers aren't these")
      view.gotServers(flow, [{ handle: "res-a", label: "Living room", urls: ["https://a.plex.direct:32400/"] },
                             { handle: "res-b", label: "Office", urls: ["http://192.168.1.20:32400/", "https://b.example/"] }])
      compare(view.signIn.stage, "servers")
      compare(view.signInRows.map(function(r) { return r.label }), ["Living room", "Office"], "first the server")
      view.signInMove(1)
      view.signInAct({})
      compare(view.signIn.stage, "servers", "only the user chooses")
      view.signInAct(guide.byUser)
      compare(view.signIn.stage, "addresses")
      compare(view.signInRows.map(function(r) { return r.label }), ["http://192.168.1.20:32400/", "https://b.example/", "Type an address for this server"], "then how to reach it")
      view.signInBack()
      compare(view.signIn.stage, "servers", "Esc: a step back")
      view.signInMove(1)
      view.signInAct(guide.byUser)
      view.signInMove(2)
      view.signInAct(guide.byUser)
      compare(view.signIn.stage, "address", "typing one for this server")
      view.typedAddress("ftp://nope", guide.byUser)
      compare(rt.chose.length, 0)
      verify(/Not a server address/.test(view.signIn.note))
      view.typedAddress("https://media.example.com", guide.byUser)
      compare(rt.chose.length, 1)
      compare(rt.chose[0].handle, "res-b", "that server's own handle")
      compare(rt.chose[0].typed, "https://media.example.com/", "made canonical first")
      compare(view.signIn.stage, "checking")
      // the helper said no: back to its addresses, saying why
      view.refusedServer(flow, "it isn't one")
      compare(view.signIn.stage, "addresses")
      verify(/didn't work/.test(view.signIn.note))
      view.signInAct(guide.byUser)
      compare(rt.chose[1].url, "http://192.168.1.20:32400/")
      // done: the server kept with the sign-in, in one write
      view.signInOver(flow, true, "Signed in.", "http://192.168.1.20:32400/")
      compare(store.keptWith.length, 1)
      compare(store.keptWith[0].server, "http://192.168.1.20:32400/")
      compare(store.keptWith[0].install, store.installOf(store.record("tv.example.app")), "for the install it began on")
      compare(rt.markedSignedIn, 1)
      compare(view.signIn, null)
      store.perms = null
      store.server = ""
    }

    function test_a_code_then_its_servers_keeps_the_sign_in() {
      store.perms = { net: [], server: { label: "S", defaultPort: 0, fromSignIn: true }, play: false, signIn: "code", storage: false }
      store.server = ""
      store.keptWith = []
      store.keepFails = ""
      var rt = openAndLoad()
      view.startSignIn(guide.byUser, "code")
      var flow = view.signIn.flow
      var install = view.signIn.install
      view.gotCode(flow, "123456", "https://account.example/link", 600)
      compare(view.signIn.code, "123456")
      compare(view.signIn.install, install, "the code is added to the sign-in, which keeps its install")
      view.gotServers(flow, [{ handle: "res-a", label: "Living room", urls: ["https://a.example/"] }])
      view.gotCode(flow, "999999", "", 600)
      compare(view.signIn.code, "123456", "a code once it's choosing its server changes nothing")
      view.signInAct(guide.byUser)
      view.signInAct(guide.byUser)
      view.signInOver(flow, true, "Signed in.", "https://a.example/")
      compare(store.keptWith.length, 1)
      compare(store.keptWith[0].install, store.installOf(store.record("tv.example.app")), "for the install it began on")
      compare(rt.markedSignedIn, 1, "signed in")
      store.perms = null
      store.server = ""
    }

    function test_a_late_address_check_for_another_server_does_nothing() {
      store.perms = { net: [], server: { label: "S", defaultPort: 0, fromSignIn: true }, play: false, signIn: "code", storage: false }
      store.server = ""
      store.canonicalLater = true
      var rt = openAndLoad()
      view.startSignIn(guide.byUser, "code")
      var flow = view.signIn.flow
      view.gotServers(flow, [{ handle: "res-a", label: "Living room", urls: ["https://a.example/"] },
                             { handle: "res-b", label: "Office", urls: ["http://192.168.1.20:32400/"] }])
      view.signInMove(1)
      view.signInAct(guide.byUser)       // Office
      view.signInMove(1)
      view.signInAct(guide.byUser)       // Type an address for this server
      view.typedAddress("https://office.example", guide.byUser)
      var late = store.canonicalDone
      verify(late !== null, "being checked")
      view.signInBack()
      view.signInBack()
      compare(view.signIn.stage, "servers")
      view.signInAct(guide.byUser)       // Living room
      var before = JSON.stringify(view.signIn)
      late()
      compare(rt.chose.length, 0, "the late answer sends nothing")
      compare(JSON.stringify(view.signIn), before, "and changes nothing")
      // and a second try supersedes the first, for the same server too
      view.signInMove(1)
      view.signInAct(guide.byUser)       // Type an address
      view.typedAddress("https://one.example", guide.byUser)
      var first = store.canonicalDone
      view.typedAddress("https://two.example", guide.byUser)
      var second = store.canonicalDone
      first()
      compare(rt.chose.length, 0, "an older try doesn't count")
      second()
      compare(rt.chose.length, 1)
      compare(rt.chose[0].handle, "res-a")
      compare(rt.chose[0].typed, "https://two.example/")
      view.cancelSignIn()
      store.canonicalLater = false
      store.perms = null
    }

    function test_a_sign_in_whose_save_and_clean_up_both_fail_is_still_dropped() {
      store.perms = { net: [], server: { label: "S", defaultPort: 0, fromSignIn: true }, play: false, signIn: "code", storage: false }
      store.server = ""
      store.keepFails = "your list of apps couldn't be saved (No space left on device)"
      var rt = openAndLoad()
      view.startSignIn(guide.byUser, "code")
      var flow = view.signIn.flow
      store.saveFails = true             // nothing can be written now
      var valuesBefore = JSON.stringify(store.values)
      view.signInOver(flow, true, "Signed in.", "http://h/")
      compare(rt.markedSignedIn, 0, "not signed in")
      compare(rt.stoppedWith, "signIn", "the helper stopped, forgetting what the flow kept as it did: no write needed")
      compare(store.forgot, ["tv.example.app:signIn"], "the guide's clean-up tried after")
      compare(JSON.stringify(store.values), valuesBefore, "the record as it was")
      store.saveFails = false
      store.keepFails = ""
      store.perms = null
    }

    function test_a_sign_in_that_cant_be_kept_is_forgotten() {
      store.perms = { net: [], server: { label: "S", defaultPort: 0, fromSignIn: true }, play: false, signIn: "code", storage: false }
      store.server = ""
      store.keptWith = []
      store.keepFails = "your list of apps couldn't be saved (Permission denied)"
      var rt = openAndLoad()
      view.startSignIn(guide.byUser, "code")
      var flow = view.signIn.flow
      view.signInOver(flow, true, "Signed in.", "http://h/")
      compare(rt.markedSignedIn, 0, "not signed in")
      compare(store.forgot, ["tv.example.app:signIn"], "what it kept is forgotten: owed on disk, and done by the restart")
      verify(store.values["@signedIn"] !== true)
      store.keepFails = ""
      store.perms = null
    }

    function test_another_server_asks_first() {
      store.perms = { net: [], server: { label: "S", defaultPort: 0, fromSignIn: true }, play: false, signIn: "code", storage: false }
      store.server = "http://old.example/"
      store.servers = []
      var rt = openAndLoad()
      view.startSignIn(guide.byUser, "code")
      var flow = view.signIn.flow
      view.gotServers(flow, [{ handle: "res-n", label: "New", urls: ["http://new.example/"] }])
      view.signInAct(guide.byUser)
      view.signInAct(guide.byUser)
      compare(view.signIn.stage, "switch", "a different server: switch first?")
      compare(rt.chose.length, 0, "nothing chosen yet")
      compare(view.signInRows.map(function(r) { return r.type }), ["switch", "stay"])
      view.signInMove(1)
      view.signInAct(guide.byUser)
      compare(view.signIn, null, "No: called off")
      compare(store.servers, [], "and the server stays")
      view.startSignIn(guide.byUser, "code")
      flow = view.signIn.flow
      view.gotServers(flow, [{ handle: "res-n", label: "New", urls: ["http://new.example/"] }])
      view.signInAct(guide.byUser)
      view.signInAct(guide.byUser)
      view.signInAct(guide.byUser)
      compare(store.servers, ["http://new.example/"], "Yes: the server switched, through setServer (it forgets what the old one gave)")
      compare(view.pendingSignIn.how, "code", "and a new sign-in waits for it to start again")
      // the same server: no question
      view.pendingSignIn = null
      store.server = "http://new.example/"
      view.startSignIn(guide.byUser, "code")
      flow = view.signIn.flow
      view.gotServers(flow, [{ handle: "res-n", label: "New", urls: ["http://new.example/"] }])
      view.signInAct(guide.byUser)
      view.signInAct(guide.byUser)
      compare(view.signIn.stage, "checking")
      view.cancelSignIn()
      store.perms = null
      store.server = ""
    }

    function test_sign_out_without_a_runtime() {
      openAndLoad()
      store.runtimes = ({})                            // it stopped (idle, say)
      guide.order = []
      store.forgot = []
      view.signOut(guide.byUser)
      compare(store.forgot, ["tv.example.app:signIn"], "the guide forgets the sign-in with no app running")
    }

    function test_operations_stay_with_their_app() {
      var rt = openAndLoad()
      store.forgot = []
      view.signOut(guide.byUser)                        // for app A
      var c = rt.last()
      compare(c.method, "signOut")
      view.appId = "tv.example.other"                  // the view moved on meanwhile
      c.done("ok", true)
      compare(store.forgot, ["tv.example.app:signIn"], "A's sign-in is forgotten, not the other app's")
      compare(view.appId, "tv.example.other", "and the view isn't dragged back")
    }

    function test_navigation_cancels_a_refresh() {
      var rt = openAndLoad()
      view.reload(guide.byUser)
      var refresh = rt.last()
      view.enter(guide.byUser)                          // a new screen asked for
      verify(rt.cancelled.indexOf(refresh.id) >= 0, "the old screen's refresh is called off")
    }

    function test_sign_out_invalidates_home_at_once() {
      var rt = openAndLoad()
      var before = store.authCount
      view.signOut(guide.byUser)                        // the app hasn't answered yet
      verify(store.authCount > before, "Home's cached rows are no longer good from the start")
    }

    function test_sign_out_holds_the_app_until_it_is_forgotten() {
      var rt = openAndLoad()
      store.holdForget = true
      var before = store.authCount
      view.signOut(guide.byUser)
      verify(store.changing["tv.example.app"], "held from the start: Home asks a signed-in app for nothing more")
      compare(store.ensure("tv.example.app", "home:x").rt, null, "and nothing starts it or uses it meanwhile")
      rt.last().done("ok", true)
      verify(store.changing["tv.example.app"], "still held while its sign-in is forgotten")
      var mid = store.authCount
      store.forgetLater(true, "")
      verify(!store.changing["tv.example.app"], "let go once it's forgotten")
      verify(store.authCount > mid && mid > before, "a generation at the start and one more after the clean-up")
      compare(store.made[store.made.length - 1].last().method, "home", "then it starts again, signed out")
    }

    function test_a_failed_sign_out_clean_up_stays_owed() {
      var rt = openAndLoad()
      store.values = store.withKey(store.values, "@signedIn", true)
      store.holdForget = true
      view.signOut(guide.byUser)
      rt.last().done("ok", true)
      compare(store.values["@forget"], ["signIn"], "recorded before it's done: a guide cut off here still owes it")
      compare(store.values["@signedIn"], undefined, "and not signed in any more, so the next runtime isn't given the old sign-in")
      store.forgetLater(false, "the disk is full")
      compare(store.values["@forget"], ["signIn"], "a failed clean-up stays owed: the next start does it first")
      verify(view.settingsNote.indexOf("cleared before the app starts again") >= 0, view.settingsNote)
    }

    function test_sign_out_is_on_disk_before_anything_waits() {
      var rt = openAndLoad()
      store.values = store.withKey(store.values, "@signedIn", true)
      view.signOut(guide.byUser)
      compare(guide.valuesAtFinish["@forget"], ["signIn"], "owed before playback is finalized: a guide cut off from here still owes it")
      compare(guide.valuesAtFinish["@signedIn"], undefined, "and isn't signed in when it starts again")
      compare(rt.last().method, "signOut", "the app hasn't answered yet")
      compare(store.forgot, [], "nothing forgotten yet: the running app still has its token for its signOut")
      rt.last().done("ok", true)
      compare(store.forgot, ["tv.example.app:signIn"])
      compare(store.values["@forget"], undefined, "no longer owed once it's done")
    }

    function test_no_sign_out_unless_its_on_disk() {
      var rt = openAndLoad()
      store.values = store.withKey(store.values, "@signedIn", true)
      store.saveFails = true
      guide.order = []
      store.forgot = []
      view.signOut(guide.byUser)
      compare(guide.order, [], "nothing finalized, asked or stopped")
      compare(store.forgot, [])
      compare(store.values["@signedIn"], true, "still signed in, as it is on disk")
      compare(store.values["@forget"], undefined)
      verify(!store.changing["tv.example.app"], "not held")
      verify(view.settingsNote.indexOf("Couldn't sign out") === 0, view.settingsNote)
    }

    function test_no_clearing_unless_its_on_disk() {
      openAndLoad()
      store.saveFails = true
      guide.order = []
      store.forgot = []
      view.restartApp("tv.example.app", "data", "Its data is cleared.")
      compare(guide.order, [], "not stopped")
      compare(store.forgot, [], "nothing cleared that isn't owed on disk first")
      verify(!store.changing["tv.example.app"], "let go")
      verify(view.settingsNote.indexOf("Couldn't do it") === 0, view.settingsNote)
    }

    function test_a_done_clean_up_is_no_longer_owed() {
      openAndLoad()
      view.restartApp("tv.example.app", "data", "")
      compare(store.values["@forget"], undefined)
    }

    function test_signing_in_tells_the_runtime() {
      var rt = openAndLoad()
      store.values = store.withKey(store.values, "@clear", ["signIn"])
      view.signIn = { flow: "f", how: "code", stage: "", code: "", url: "", expires: 0, qr: "" }
      view.signInOver("f", true, "Signed in.")
      compare(rt.markedSignedIn, 1, "what it kept is the app's now")
      compare(store.values["@signedIn"], true)
      compare(store.values["@clear"], undefined, "an old clean-up of the sign-in would wipe this one")
    }

    function test_no_restart_or_sign_out_while_its_being_changed() {
      openAndLoad()
      guide.order = []
      store.setChanging("tv.example.app", true)         // an update, say
      view.restartApp("tv.example.app", "data", "")
      view.signOut(guide.byUser)
      compare(guide.order, [], "neither stops it nor forgets anything")
      compare(store.forgot, [])
      compare(view.settingsNote, "It's being changed. Try again in a moment.")
    }

    function test_no_setting_changes_while_its_being_changed() {
      openAndLoad()
      view.openSettings(guide.byUser)
      store.setChanging("tv.example.app", true)
      view.settingsAct(1, guide.byUser)                 // League A → B
      compare(store.values.league, undefined, "not written")
      compare(view.settingsNote, "It's being changed. Try again in a moment.")
      view.editing = { type: "text", key: "name", label: "Name", text: "" }
      view.editDone("x", guide.byUser)
      compare(store.values.name, undefined)
    }

    function test_restart_doesnt_reopen_a_replaced_install() {
      var rt = openAndLoad()
      store.holdForget = true
      view.restartApp("tv.example.app", "data", "")
      var n = store.made.length
      store.install = "v2"                              // what it restarted for is gone by then
      store.forgetLater(true, "")
      compare(store.made.length, n, "no new runtime for the replaced one")
    }

    function test_each_code_asks_for_its_qr_and_only_the_latest_shows() {
      openAndLoad()
      view.signIn = { flow: "f", how: "code", stage: "", code: "", url: "", expires: 0, qr: "" }
      view.gotCode("f", "AAAA", "https://example.com/a", 60)
      view.gotCode("f", "BBBB", "", 60)                 // a code with no link: still asks, which calls A's off
      compare(guide.qrAsked.length, 2)
      compare(guide.qrAsked[1].url, "")
      guide.qrAsked[0].done("/tmp/qr-a.png")            // A's, late
      compare(view.signIn.code, "BBBB")
      compare(view.signIn.qr, "", "the older code's QR never shows beside the newer code")
      view.gotCode("f", "CCCC", "https://example.com/c", 60)
      guide.qrAsked[2].done("/tmp/qr-c.png")
      compare(view.signIn.qr, "/tmp/qr-c.png")
    }

    // the shared runtime budget, through the user's own open: a sign-out
    // still out is never stopped to make room (AppBudget.js)
    function test_a_sign_out_still_out_isnt_stopped_to_make_room() {
      store.budgetOn = true
      store.runtimes = { "tv.example.a": { phase: "ready", leases: ({}), busy: true, lastUsed: 1 },
                         "tv.example.b": { phase: "starting", leases: ({}), busy: false, lastUsed: 2 },
                         "tv.example.c": { phase: "starting", leases: ({}), busy: false, lastUsed: 3 } }
      store.changing = { "tv.example.a": true }       // A is signing out
      compare(view.open("tv.example.app", guide.byUser), "ok")
      compare(guide.screen, "app", "the screen first, as the user's open does")
      compare(view.failed, "Three apps are busy.")
      compare(store.stoppedIds, [], "the signing-out app isn't stopped")
      compare(store.made.length, 0, "and nothing is queued")
      // its sign-out finishes and it's stopping: Enter tries again and waits for the slot
      store.runtimes = { "tv.example.a": { phase: "stopping", leases: ({}), busy: false, lastUsed: 1 },
                         "tv.example.b": store.runtimes["tv.example.b"], "tv.example.c": store.runtimes["tv.example.c"] }
      store.changing = ({})
      view.enter(guide.byUser)
      compare(store.made.length, 1)
      compare(store.made[0].phase, "queued", "it waits for the slot")
      compare(store.stoppedIds, [], "nothing else stopped")
    }

    function test_leaving_releases_the_lease() {
      var rt = openAndLoad()
      guide.screen = "home"
      verify(rt.leases.foreground !== true, "off the screen, no screen lease")
    }

    // ---- milestone 1: reloads, what views hold, the picture demand --------
    // a screen whose n items each name `per` pictures of their own (an image,
    // then images for each shape), every token unique to it
    function picScreen(title, n, per, prefix) {
      var items = []
      for (var i = 0; i < n; i++) {
        var it = { id: "i" + i, title: "I" + i, subtitle: "", badge: "", kind: "open", progress: null, image: { token: prefix + "-" + i + "-0" } }
        if (per > 1) {
          it.images = {}
          ;["poster", "wide", "square", "backdrop", "logo"].slice(0, per - 1).forEach(function(k, j) { it.images[k] = { token: prefix + "-" + i + "-" + (j + 1) } })
        }
        items.push(it)
      }
      return { title: title, empty: "", refresh: null, rows: [{ id: "r", title: "R", layout: "row", items: items }] }
    }
    function held() { return view.stack.reduce(function(n, v) { return n + (v.stale ? 0 : v.tokens) }, 0) }
    function actions(rt) { return rt.calls.filter(function(c) { return c.method === "action" }).length }
    function push(rt, method, args, value) {
      view.ask(method, args, "push")
      rt.last().done(value.title !== undefined && value.rows ? "screen" : "detail", value)
    }

    function test_each_view_knows_how_it_loads_again() {
      var rt = openAndLoad()
      compare(view.topView.reload.method, "home")
      compare(view.topView.result, rt.calls[0].id, "its result id: what its pictures are held by")
      view.enter(guide.byUser)
      rt.last().done("screen", screenOf("Inside", ["x"]))
      compare(JSON.stringify(view.topView.reload), JSON.stringify({ method: "browse", args: { item: "a" } }))
      push(rt, "search", { query: "q" }, screenOf("Found", ["y"]))
      compare(view.topView.reload.method, "search")
      push(rt, "action", { item: "y", action: "go" }, screenOf("After a button", ["z"]))
      compare(view.topView.reload, null, "a button's screen has none")
    }

    function test_r_never_asks_a_button_again() {
      var rt = openAndLoad()
      var s = screenOf("After a button", ["y"])
      s.refresh = 15
      push(rt, "action", { item: "a", action: "go" }, s)
      var n = rt.calls.length
      view.reload(guide.byUser)
      compare(rt.calls.length, n, "R doesn't send the button again")
      verify(/button/.test(view.message), view.message)
      var timer = findChild(view, "refreshTimer")
      verify(timer !== null)
      verify(!timer.running, "and a button's screen doesn't come again by itself")
      var s2 = screenOf("Browsed", ["w"])
      s2.refresh = 15
      push(rt, "browse", { item: "y" }, s2)
      verify(timer.running, "a screen that only reads does")
    }

    function test_views_let_go_of_what_they_held() {
      var rt = openAndLoad()
      var home = view.topView.result
      view.enter(guide.byUser)
      rt.last().done("screen", screenOf("Inside", ["x"]))
      var inside = view.topView.result
      view.back()
      verify(rt.released.indexOf(inside) >= 0, "popped: let go")
      view.reload(guide.byUser)
      rt.last().done("screen", screenOf("Home", ["a"]))
      verify(rt.released.indexOf(home) >= 0, "replaced by its refresh: let go")
      view.enter(guide.byUser)
      var late = rt.last()
      view.back()                                       // called off
      late.done("screen", screenOf("Late", ["z"]))      // it answers anyway
      verify(rt.released.indexOf(late.id) >= 0, "an answer dropped: let go")
      var top = view.topView.result
      view.reset()
      verify(rt.released.indexOf(top) >= 0, "a reset lets go of them all")
    }

    function test_at_most_20_views() {
      var rt = openAndLoad()
      var first = view.topView.result
      for (var i = 0; i < 25; i++) push(rt, "browse", { item: "b" + i }, screenOf("S" + i, ["x"]))
      compare(view.stack.length, 20)
      compare(view.stack[0].result, first, "the first stays")
      compare(view.stack[1].value.title, "S6", "the six oldest after it went (26 made, 20 kept)")
      compare(view.topView.value.title, "S24")
      compare(rt.released.length, 6, "and let go")
    }

    function test_more_than_4000_pictures() {
      var rt = openAndLoad()
      view.screenWidth = 1280
      var mostHeld = 0
      var step = function(method, args, title, prefix) {
        push(rt, method, args, picScreen(title, 200, 6, prefix))
        mostHeld = Math.max(mostHeld, held())
      }
      step("browse", { item: "a" }, "A", "a")             // 1,200 pictures each
      step("action", { item: "a", action: "go" }, "B", "b")
      step("browse", { item: "c" }, "C", "c")
      compare(view.stack[1].stale, false, "3,600 held: under 4,000")
      step("browse", { item: "d" }, "D", "d")
      compare(view.stack[1].stale, true, "past 4,000: the oldest that can load again let go first")
      step("action", { item: "d", action: "go" }, "E", "e")
      step("action", { item: "e", action: "go" }, "F", "f")
      step("action", { item: "f", action: "go" }, "G", "g")
      verify(mostHeld <= 4000, "never more than 4,000 held: " + mostHeld)
      compare(view.stack.map(function(v) { return v.stale ? "*" : v.value.title }).join(" "), "Home * * * E F G",
              "A, C and D let go (they load again); B, a button's, left the history once only those were left")
      compare(actions(rt), 4, "the four button presses")
      // a look change (the screen made again at another width) and a refresh
      view.move("right")
      view.screenWidth = 900
      compare(view.topView.sel.col, 1, "the place kept")
      var n = rt.calls.length
      view.reload(guide.byUser)
      compare(rt.calls.length, n, "R on a button's screen asks nothing")
      // the helper lets one of F's pictures go anyway: a button's screen shows the title there
      rt.asked = []
      var img = view.topView.value.rows[0].items[0].image
      view.want(img, "visible")
      rt.asked[rt.asked.length - 1].done("", { code: "unknown" })
      compare(view.imagePaths[img.token], "-gone", "a button's screen can't load again: the title in its place")
      view.unwant(img, "visible")
      // Back through the history: what let go loads again through its reload
      var loads = []
      while (view.stack.length > 1) {
        view.back()
        wait(0)                                         // a view that let go starts loading again
        if (view.pending) {
          var c = rt.last()
          loads.push(c.method + ":" + (c.args.item || ""))
          c.done("screen", picScreen("again", 200, 6, "r" + loads.length))
        }
      }
      compare(loads.join(" "), "browse:d browse:c browse:a", "each from its reload, B gone from the history")
      compare(actions(rt), 4, "not one button pressed again")
    }

    function test_home_rows_count_toward_the_4000() {
      var rt = openAndLoad()
      guide.homeHeld = 1500                               // the app's Home rows hold 1,500
      push(rt, "browse", { item: "a" }, picScreen("A", 200, 6, "a"))
      push(rt, "browse", { item: "b" }, picScreen("B", 200, 6, "b"))
      compare(view.stack[1].stale, false, "2,400 and Home's 1,500: under 4,000")
      push(rt, "browse", { item: "c" }, picScreen("C", 200, 6, "c"))
      compare(view.stack[1].stale, true, "3,600 and Home's 1,500: past it, so A lets go")
      verify(held() + guide.homeHeld <= 4000)
    }

    function test_a_live_update_keeps_within_the_4000() {
      var rt = openAndLoad()
      push(rt, "browse", { item: "a" }, picScreen("A", 200, 6, "a"))
      push(rt, "browse", { item: "b" }, picScreen("B", 200, 6, "b"))
      push(rt, "browse", { item: "c" }, picScreen("C", 200, 6, "c"))
      var live = picScreen("L", 1, 1, "l")
      live.live = true
      push(rt, "browse", { item: "l" }, live)
      compare(view.stack[1].stale, false, "3,601 held: under 4,000")
      var n = rt.released.length
      store.liveUpdated("tv.example.app", rt, view.topView.result, picScreen("L", 200, 6, "m").rows, null)
      compare(view.topView.tokens, 1200, "the live screen holds 1,200 now")
      compare(view.stack[1].stale, true, "4,800 past it: the oldest that loads again let go")
      verify(held() <= 4000, "never more than 4,000 held: " + held())
      verify(rt.released.length > n, "and let go in the helper")
      guide.homeHeld = 0
    }

    function test_a_picture_let_go_loads_the_view_again_once() {
      var rt = openAndLoad()
      push(rt, "browse", { item: "a" }, picScreen("A", 2, 1, "a"))
      rt.asked = []
      var img = view.topView.value.rows[0].items[0].image
      view.want(img, "visible")
      var n = rt.calls.length
      rt.asked[0].done("", { code: "unknown" })
      compare(rt.calls.length, n + 1, "loaded again")
      compare(rt.last().method + ":" + rt.last().args.item, "browse:a")
      view.unwant(img, "visible")
      rt.last().done("screen", picScreen("A", 2, 1, "a2"))
      var img2 = view.topView.value.rows[0].items[0].image
      rt.asked = []
      view.want(img2, "visible")
      rt.asked[0].done("", { code: "unknown" })
      compare(rt.calls.length, n + 1, "only once")
      compare(view.imagePaths[img2.token], "-gone", "then the card shows its title")
      view.unwant(img2, "visible")
    }

    function test_pictures_are_asked_for_the_demand_now() {
      var rt = openAndLoad()
      rt.asked = []
      var a = { token: "t-a" }, b = { token: "t-b" }
      view.want(a, "visible")
      view.want(b, "focus")
      compare(rt.asked.length, 2)
      compare([rt.asked[0].epoch, rt.asked[0].prio, rt.asked[1].prio], [rt.demand, "visible", "focus"])
      var before = rt.demand
      view.move("right")                                // the focus moved: a new demand
      verify(rt.demand > before)
      wait(0)                                           // its asks go out after the move
      var again = rt.asked.slice(2)
      compare(again.map(function(x) { return x.token }).sort().join(","), "t-a,t-b", "what's still wanted, asked again")
      verify(again.every(function(x) { return x.epoch === rt.demand }), "under the new demand")
      rt.asked[0].done("", { code: "stale" })
      verify(view.imagePaths["t-a"] !== "-", "stale isn't failed")
      again[1].done("/p/b.png", { w: 200, h: 300 })
      compare(view.imagePaths["t-b"], "/p/b.png")
      compare(view.imageRatio(b), 200 / 300, "its size, before it's drawn")
      // the helper's queue was full: asked again in a moment
      var c = { token: "t-c" }
      view.want(c, "rest")
      var n = rt.asked.length
      rt.asked[n - 1].done("", { code: "busy" })
      verify(findChild(view, "busyRetry").running)
      tryVerify(function() { return rt.asked.length > n }, 3000, "asked again")
      compare(rt.asked[rt.asked.length - 1].token, "t-c")
      // a failure is tried once more the next time it's shown
      rt.asked[rt.asked.length - 1].done("", { code: "failed" })
      compare(view.imagePaths["t-c"], "-failed")
      view.unwant(c, "rest")
      n = rt.asked.length
      view.want(c, "visible")
      compare(rt.asked.length, n + 1, "tried once more")
      rt.asked[n].done("", { code: "failed" })
      view.unwant(c, "visible")
      view.want(c, "visible")
      compare(rt.asked.length, n + 1, "but only once")
      view.unwant(c, "visible")
      view.unwant(a, "visible")
      view.unwant(b, "focus")
      compare(Object.keys(view.wanted).length, 0, "nothing wanted once the cards let go")
    }


    // ---- milestone 1, ycodex round 1 ---------------------------------------
    function test_a_refused_picture_isnt_asked_again() {
      var rt = openAndLoad()
      rt.asked = []
      var img = { token: "t-refused" }
      view.want(img, "visible")
      rt.asked[0].done("", { code: "refused" })
      compare(view.imagePaths["t-refused"], "-refused")
      view.unwant(img, "visible")
      view.want(img, "visible")
      compare(rt.asked.length, 1, "the rules won't fetch it: not asked again")
      view.unwant(img, "visible")
    }

    function test_a_file_that_cant_be_drawn_is_fetched_again_once() {
      var rt = openAndLoad()
      rt.asked = []
      var img = { token: "t-broken" }
      view.want(img, "visible")
      rt.asked[0].done("/p/broken.png", { w: 10, h: 10 })
      view.brokenPicture(img, "visible")
      compare(rt.asked.length, 2, "asked again")
      compare(rt.asked[1].broken, true, "telling the helper the file was bad")
      compare(view.imagePaths["t-broken"], "", "loading again")
      rt.asked[1].done("/p/broken.png", { w: 10, h: 10 })
      view.brokenPicture(img, "visible")
      compare(view.imagePaths["t-broken"], "-broken", "a second time: its title")
      compare(rt.asked.length, 2, "and not asked a third time")
      view.unwant(img, "visible")
    }

    function test_a_recovery_that_fails_settles_its_pictures() {
      var rt = openAndLoad()
      push(rt, "browse", { item: "a" }, picScreen("A", 1, 1, "rf"))
      rt.asked = []
      var img = view.topView.value.rows[0].items[0].image
      view.want(img, "visible")
      rt.asked[0].done("", { code: "unknown" })
      compare(rt.last().method, "browse", "loaded again to put it back")
      compare(view.imagePaths[img.token], "", "waiting for that")
      rt.last().done("error", { code: "fetch", text: "offline" })
      compare(view.imagePaths[img.token], "-gone", "it failed: the picture stops waiting, its title shows")
      view.unwant(img, "visible")
    }

    function test_leaving_the_screen_tells_the_helper() {
      var rt = openAndLoad()
      var n = rt.demands.length
      guide.screen = "home"
      verify(rt.demands.length > n, "a new demand, with nothing to ask for")
    }

    function test_a_row_starts_its_clock_when_its_shown() {
      openAndLoad()
      view.learned = ({})
      view.sampling = ({})
      // a card made ahead, off the screen, settles first
      view.settleNow("r", 0, 0.66, 5)
      var k = view.shapeKey + "\n" + "r"
      compare(view.sampling[k].start, 0, "kept, its clock not started")
      wait(2300)
      verify(view.sampling[k] !== undefined && !view.learned[view.shapeKey], "two seconds off the screen don't decide it")
      view.rowShown("r", 5)
      verify(view.sampling[k].start > 0, "shown: its clock starts")
      compare(view.sampling[k].settled[0], 0.66, "with what settled before")
      view.sampling = ({})
    }

    // Rows made ahead and never shown don't pile up, and keep no clock
    // running: the 200 ms clock runs only while a shown row decides, and a
    // new view drops what was deciding for the one before
    function sampleTimer() {
      for (var i = 0; i < view.data.length; i++) {
        var t = view.data[i]
        if (t && t.interval === 200 && t.repeat === true && t.triggered !== undefined) return t
      }
      return null
    }
    function test_rows_made_ahead_dont_pile_up_or_keep_the_clock_running() {
      openAndLoad()
      view.learned = ({})
      view.sampling = ({})
      var timer = sampleTimer()
      verify(timer !== null, "the sampling clock")
      verify(!timer.running, "nothing deciding: no clock")
      view.settleNow("ahead", 0, 0.66, 5)                 // made ahead, off the screen
      var k = view.shapeKey + "\n" + "ahead"
      compare(view.sampling[k].start, 0)
      verify(!timer.running, "a row made ahead keeps no clock running")
      view.rowShown("shown", 5)
      verify(timer.running, "a shown row deciding: the clock runs")
      view.epoch += 1                                    // another screen
      compare(Object.keys(view.sampling).length, 0, "what was deciding for the old view goes")
      verify(!timer.running, "and the clock stops")
      view.settleNow("ahead", 0, 0.66, 5)
      view.epoch += 1
      compare(Object.keys(view.sampling).length, 0, "a row made ahead goes with its view too")
      view.sampling = ({})
    }

    // ---- milestone 1, ycodex round 2 ---------------------------------------
    // Three pictures that settle before their row is shown decide it then,
    // and the same three decide the same on the screen, in any order: the
    // answer depends only on them, never on when they came (only the 2 s
    // timeout depends on time, and it starts when the row is shown).
    function test_three_settled_off_the_screen_decide_as_they_would_on_it() {
      openAndLoad()
      view.learned = ({})
      view.sampling = ({})
      view.settleNow("off", 0, 0.66, 5)
      view.settleNow("off", 1, 0.7, 5)
      var k = view.shapeKey + "\n" + "off"
      compare(view.sampling[k].start, 0, "two of three: it waits, no clock running")
      verify(!view.learned[view.shapeKey], "nothing decided")
      view.settleNow("off", 2, 1.78, 5)
      compare(view.learned[view.shapeKey]["r:off"], "poster", "all three in: decided by them alone")
      view.rowShown("on", 5)
      view.settleNow("on", 2, 1.78, 5)
      view.settleNow("on", 0, 0.66, 5)
      verify(!view.learned[view.shapeKey]["r:on"], "on the screen too, it waits for the first three")
      view.settleNow("on", 1, 0.7, 5)
      compare(view.learned[view.shapeKey]["r:on"], "poster", "the same three, the same answer")
      view.sampling = ({})
    }

    function test_a_picture_drawn_fine_may_be_repaired_again() {
      var rt = openAndLoad()
      rt.asked = []
      var img = { token: "t-again" }
      view.want(img, "visible")
      rt.asked[0].done("/p/a.png", { w: 10, h: 10 })
      view.brokenPicture(img, "visible")                // its file went
      rt.asked[1].done("/p/a.png", { w: 10, h: 10 })
      view.pictureDrawn(img)                            // fetched again, and drawn fine
      view.brokenPicture(img, "visible")                // later the helper's folder let it go again
      compare(rt.asked.length, 3, "repaired again")
      compare(rt.asked[2].broken, true)
      compare(view.imagePaths["t-again"], "", "loading again")
      view.unwant(img, "visible")
    }

    function test_a_picture_shown_again_is_checked_again() {
      var rt = openAndLoad()
      rt.asked = []
      var img = { token: "t-reuse" }
      view.want(img, "visible")
      rt.asked[0].done("/p/r.png", { w: 10, h: 10 })
      view.unwant(img, "visible")
      view.want(img, "visible")
      compare(rt.asked.length, 1, "within a minute: drawn from what the view has")
      view.unwant(img, "visible")
      view.imageInfo["t-reuse"].at = Date.now() - view.recheckMs - 1000
      view.want(img, "visible")
      compare(rt.asked.length, 2, "after a minute: the helper checks its file again (and keeps it fresh)")
      compare(view.imagePaths["t-reuse"], "/p/r.png", "the card keeps it meanwhile")
      view.want(img, "rest")
      compare(rt.asked.length, 2, "asked once")
      rt.asked[1].done("/p/r.png", { w: 10, h: 10 })
      verify(Date.now() - view.imageInfo["t-reuse"].at < 5000, "checked now")
      view.unwant(img, "visible")
      view.unwant(img, "rest")
    }

    function test_what_the_view_knows_of_pictures_is_bounded() {
      var rt = openAndLoad()
      rt.asked = []
      // a failure retried, let go while it was asked for again: nothing of it stays
      var f = { token: "t-f0" }
      view.want(f, "visible")
      rt.asked[0].done("", { code: "failed" })
      view.unwant(f, "visible")
      view.want(f, "visible")
      verify(view.retried["t-f0"], "its one retry")
      rt.asked[1].done("", { code: "stale" })
      view.unwant(f, "visible")
      compare([view.imagePaths["t-f0"], view.retried["t-f0"], view.imageInfo["t-f0"]], [undefined, undefined, undefined])
      // one fetched again for its file, the oldest when 2,000 more come: it goes, retries and all
      var b = { token: "t-b0" }
      view.want(b, "visible")
      rt.asked[2].done("/p/b.png", { w: 10, h: 10 })
      view.brokenPicture(b, "visible")
      rt.asked[3].done("/p/b.png", { w: 10, h: 10 })
      view.unwant(b, "visible")
      verify(view.brokenRetried["t-b0"])
      for (var i = 0; i < 2000; i++) view.setPath("t-fill" + i, "/p/fill.png")
      compare([view.imagePaths["t-b0"], view.brokenRetried["t-b0"], view.imageInfo["t-b0"]], [undefined, undefined, undefined])
      verify(Object.keys(view.imagePaths).length <= 2000)
    }

  }
}
