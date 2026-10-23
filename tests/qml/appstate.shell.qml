import QtQuick
import Quickshell
import Quickshell.Io

// Apps.qml in a Quickshell of its own, with a pretend guide, against the
// real bin/om-pg-apps in a scratch home. Run by tests/appstate.test.py,
// which makes that home first.
ShellRoot {
  id: root
  property string tmp: Quickshell.env("T")
  property string sd: "9866a2d1833b76c1"
  property string src: "file:0123456789abcdef"
  QtObject {
    id: fake
    property string configDir: Quickshell.env("XDG_CONFIG_HOME") + "/om-pg"   // where the helper looks too
    property string cacheDir: Quickshell.env("XDG_CACHE_HOME") + "/om-pg"
    property string pluginDir: Quickshell.env("OM_PG_ROOT")
    property var appPlayback: null
    property var sources: null   // (Sources.qml in the guide: step 9b stands in its find, 9l is Sources.qml itself)
    // what Sources.qml asks of the guide (step 9l)
    property var apps: null
    property string dialog: ""
    property var byUser: ({ who: "you" })
    readonly property bool authBusy: false
    function boxShown() { return true }
    function authorize(kind, payload, done, still) { done(false, "not asked here") }
    function authSaid(why) { return why }
    function finishAppPlayback(id, reason, then) { then() }
    function askApps() {}
    function askDeveloper() {}
  }
  QtObject { id: fakeRt; property string phase: "starting"; signal stopped(string why, string text); function stop(f) { fakeRt.phase = "stopped" } }
  property var apps: null
  property var fails: 0
  function check(c, s) { if (!c) root.fails++; console.log((c ? "H PASS " : "H FAIL ") + s) }
  function rd(p) { var r = readFile.createObject(root, { path: p }); var t = r.text(); r.destroy(); return t }
  Component { id: readFile; FileView { blockLoading: true; printErrors: false } }
  function secrets(id) { try { return JSON.parse(rd(fake.configDir + "/app-secrets/" + root.sd + "/" + id + ".json")) } catch (e) { return null } }
  // then() once cond() holds, looked at every 20 ms; ticks (1500, half a
  // minute, unless said) the most it waits (what it waits for is mostly the
  // helper, a process of its own that a busy computer starts slowly)
  function waitFor(cond, then, label, ticks) {
    var n = 0
    var t = poll.createObject(root)
    t.triggered.connect(function() { if (cond()) { t.destroy(); then() } else if (++n > (ticks || 1500)) { t.destroy(); root.check(false, "timed out: " + label); Qt.quit() } })
    t.start()
  }
  Component { id: poll; Timer { interval: 20; repeat: true } }
  property var atLoad: null
  property int verified: 0     // verify's answers taken in, and other changes to checkedIds (step 9l counts them)
  Connections {
    target: root.apps
    function onLoadedChanged() { var a = root.apps.record("tv.example.launch"); root.atLoad = a ? JSON.stringify(a.values) : "none" }
    function onCheckedIdsChanged() { root.verified++ }
  }
  Component.onCompleted: {
    var c = Qt.createComponent("file://" + fake.pluginDir + "/Apps.qml")
    if (c.status !== Component.Ready) { console.log("H ERR " + c.errorString()); Qt.quit(); return }
    root.apps = c.createObject(root, { guide: fake, sweep: false })   // (the guide's own apps left running)
    waitFor(function() { return root.apps.loaded }, step1, "load")
  }
  // 1: a launcher's record keeps only what it owes, and the guide's start does it
  function step1() {
    check(root.atLoad === JSON.stringify({ "@forget": ["data"], "@clear": ["apiKey", "signIn"] }), "a launcher keeps only the clean-ups it owes: " + root.atLoad)
    check(root.apps.changing["tv.example.launch"] === true, "held while it's settled")
    waitFor(function() { return !root.apps.changing["tv.example.launch"] }, function() {
      var s = secrets("tv.example.launch")
      check(s && s.user.apiKey === undefined && s.user.other === "o" && Object.keys(s.signIn.values).length === 0, "its owed secrets cleared, the rest kept: " + JSON.stringify(s))
      check(rd(root.tmp + "/data/om-pg/app-store/" + root.sd + "/tv.example.launch.json") === "", "its data forgotten")
      check(JSON.stringify(root.apps.record("tv.example.launch").values) === "{}", "nothing owed any more")
      check(JSON.parse(rd(fake.configDir + "/apps.json")).installed.filter(function(a) { return a.id === "tv.example.launch" })[0].values !== undefined, "saved")
      step2()
    }, "settle")
  }
  // 2: a secret isn't written while a start may still clear its name
  function step2() {
    var rec = { id: "tv.example.code", name: "Code", version: "1.0.0", kind: "app", api: 2, source: root.src, sourceDir: root.sd, sha256: "a", updated: 1,
                permissions: { net: [], server: { label: "S", defaultPort: 0 }, play: false, signIn: "code", storage: true },
                settings: [{ key: "apiKey", type: "secret", label: "Key" }], values: { "@clear": ["apiKey"], "@forget": ["server"] }, server: "https://s.example" }
    root.apps.installed = root.apps.installed.concat([rec])
    root.apps.runtimes = { "tv.example.code": fakeRt }
    var said = null
    root.apps.setSecret("tv.example.code", "apiKey", "new", function(ok, why) { said = [ok, why] })
    check(said && said[0] === false && /starting/.test(said[1]), "refused while it's starting: " + JSON.stringify(said))
    fakeRt.phase = "stopping"
    said = null
    root.apps.setSecret("tv.example.code", "apiKey", "new", function(ok, why) { said = [ok, why] })
    check(said && said[0] === false, "and while it's stopping")
    fakeRt.phase = "ready"
    said = null
    root.apps.setSecret("tv.example.code", "apiKey", "new", function(ok, why) { said = [ok, why] })
    waitFor(function() { return said !== null }, function() {
      check(said[0] === true, "written once it's ready (its clean-ups are done): " + JSON.stringify(said))
      var v = root.apps.record("tv.example.code").values
      check(v["@clear"] === undefined && v["@secret:apiKey"] === true, "no longer owed, and set: " + JSON.stringify(v))
      check(secrets("tv.example.code").user.apiKey === "new", "the value kept")
      step3()
    }, "setSecret")
  }
  // 3: save() says whether it was written
  function step3() {
    check(root.apps.save() === true && root.apps.saveError === "", "a save that's written says so")
    chmod.command = ["/bin/sh", "-c", "chmod 400 \"$0/apps.json\" && chmod 500 \"$0\"", fake.configDir]
    chmod.running = true
    waitFor(function() { return !chmod.running }, function() {
      root.apps.catalogSeen += 1; var r = root.apps.save(); check(r === false && root.apps.saveError !== "", "one that isn't says so: " + r + " " + root.apps.saveError)
      check(root.apps.save() === false, "and the same again still isn't")
      chmod.command = ["/bin/sh", "-c", "chmod 700 \"$0\" && chmod 600 \"$0/apps.json\"", fake.configDir]
      chmod.running = true
      waitFor(function() { return !chmod.running }, function() {
        // the same text as the failed write: written now, not taken as written already
        check(root.apps.save() === true && JSON.parse(rd(fake.configDir + "/apps.json")).catalogSeen === root.apps.catalogSeen, "once it can be, the same save is written")
        // a write that says it worked but left the file as it was (Quickshell 0.3.1 on a failed replace)
        var orig = root.apps.writerKind
        root.apps.writerKind = liar
        root.apps.catalogSeen += 1
        var r2 = root.apps.save()
        check(r2 === false && /isn't what was written/.test(root.apps.saveError), "a write that didn't land is caught: " + root.apps.saveError)
        root.apps.writerKind = orig
        check(root.apps.save() === true, "and written again with the real writer")
        step3b()
      }, "chmod back")
    }, "chmod")
  }
  Process { id: chmod }
  Component { id: liar; QtObject { property string path; signal saveFailed(int error); function setText(t) {} } }

  // 3b: an update's package doesn't go in until what it takes away is
  // withdrawn on disk; then, after a restart, a later version that asks
  // for the secret again doesn't get the old bytes
  property var v2: ({ id: "tv.example.code", name: "Code", version: "2.0.0", kind: "app", settings: [],
                      permissions: { net: [], server: { label: "S", defaultPort: 0 }, play: false, signIn: "code", storage: true } })
  function step3b() {
    check(root.apps.record("tv.example.code").values["@secret:apiKey"] === true, "apiKey is set before")
    chmod.command = ["/bin/sh", "-c", "chmod 400 \"$0/apps.json\" && chmod 500 \"$0\"", fake.configDir]
    chmod.running = true
    waitFor(function() { return !chmod.running }, function() {
      check(root.apps.withdraw("tv.example.code", root.v2) === false, "not withdrawn when it can't be saved: nothing is installed")
      var v = root.apps.record("tv.example.code").values
      check(v["@secret:apiKey"] === true && v["@clear"] === undefined, "and the record is as it is on disk: " + JSON.stringify(v))
      chmod.command = ["/bin/sh", "-c", "chmod 700 \"$0\" && chmod 600 \"$0/apps.json\"", fake.configDir]
      chmod.running = true
      waitFor(function() { return !chmod.running }, function() {
        check(root.apps.withdraw("tv.example.code", root.v2) === true, "withdrawn once it can be")
        var d = JSON.parse(rd(fake.configDir + "/apps.json")).installed.filter(function(a) { return a.id === "tv.example.code" })[0].values
        check(d["@secret:apiKey"] === undefined && JSON.stringify(d["@clear"]) === JSON.stringify(["apiKey"]), "on disk: not set, and owed: " + JSON.stringify(d))
        // the guide stops here (the package is replaced, the save and the clear after it fail): it starts again
        root.apps.destroy()
        var c = Qt.createComponent("file://" + fake.pluginDir + "/Apps.qml")
        root.apps = c.createObject(root, { guide: fake, sweep: false })   // (the guide's own apps left running)
        waitFor(function() { return root.apps.loaded }, step3c, "reload")
      }, "chmod back")
    }, "chmod")
  }
  function step3c() {
    var v3 = { manifest: { id: "tv.example.code", name: "Code", version: "3.0.0", kind: "app", author: "", description: "", main: "main.py",
                           settings: [{ key: "apiKey", type: "secret", label: "Key" }],
                           permissions: { net: [], server: { label: "S", defaultPort: 0 }, play: false, signIn: "code", storage: true } },
               path: root.tmp + "/x", sourceDir: root.sd, files: {} }
    root.apps.setChanging("tv.example.code", true)
    var warning = null
    root.apps.keep(v3, root.src, "/x.zip", "c", function(w) { warning = w })
    var v = root.apps.record("tv.example.code").values
    check(v["@secret:apiKey"] === undefined, "a later version asking for apiKey again isn't given the old one: " + JSON.stringify(v))
    check((v["@clear"] || []).indexOf("apiKey") >= 0, "and still owes clearing it")
    root.apps.setChanging("tv.example.code", false)
    step4()
  }
  // 4: an app with code updated to a launcher: what it owes is done at once
  function step4() {
    root.apps.runtimes = ({})
    var res = { manifest: { id: "tv.example.code", name: "Code", version: "4.0.0", kind: "launcher", author: "", description: "",
                            permissions: { web: ["example.com"] }, launch: { web: "https://example.com/" } },
                path: root.tmp + "/x", sourceDir: root.sd, files: {} }
    var warning = null
    root.apps.setChanging("tv.example.code", true)
    root.apps.keep(res, root.src, "/x.zip", "b", function(w) { warning = w })
    var v0 = root.apps.record("tv.example.code").values
    check(JSON.stringify(v0["@clear"]) === JSON.stringify(["apiKey", "signIn"]) && JSON.stringify(v0["@forget"]) === JSON.stringify(["server"]), "a launcher now, owing its secrets, its sign-in and its old server's: " + JSON.stringify(v0))
    var disk = JSON.parse(rd(fake.configDir + "/apps.json")).installed.filter(function(a) { return a.id === "tv.example.code" })[0]
    check(disk.kind === "launcher" && JSON.stringify(disk.values["@clear"]) === JSON.stringify(["apiKey", "signIn"]), "on disk before anything's cleared")
    waitFor(function() { return warning !== null }, function() {
      check(warning === "", "no warning: " + warning)
      check(JSON.stringify(root.apps.record("tv.example.code").values) === "{}", "nothing owed")
      var s = secrets("tv.example.code")
      check(s.user.apiKey === undefined && Object.keys(s.signIn.values).length === 0, "its secrets cleared: " + JSON.stringify(s))
      step4b()
    }, "keep")
  }

  // 4b: API 3. Scores installed as it was
  // (1.0.2, api 2, from a copy of the plugin before it); then Scores 1.1.0
  // (api 3, asking for nothing new, from a copy of the plugin at API 3)
  // installs quietly through the real update path, its source the
  // record's; the update matrix; and a restart keeps its api 3 and its
  // layout. (The plugin's own Scores, api 4, waits for you: see 4d.)
  function bundledVersion(id) { var b = root.apps.bundled.filter(function(x) { return x.id === id })[0]; return b && b.manifest ? b.manifest.version : "" }
  function step4b() {
    var id = "tv.uber.scores"
    root.apps.on = true
    root.apps.checked = Date.now() / 1000   // (no catalog fetch)
    fake.pluginDir = Quickshell.env("OLD_PLUGIN")
    root.apps.listBundled()
    waitFor(function() { return bundledVersion(id) === "1.0.2" }, function() {
      root.apps.get(id)
      waitFor(function() { return root.apps.review !== null }, function() {
        var installed = null
        root.apps.confirm(function(ok) { installed = ok })
        waitFor(function() { return installed !== null }, function() {
          var a = root.apps.record(id)
          check(installed === true && a.api === 2 && a.version === "1.0.2" && a.layout === null, "Scores 1.0.2 installed, api 2: " + JSON.stringify(a ? [a.api, a.version, a.layout] : root.apps.status))
          fake.pluginDir = Quickshell.env("MID_PLUGIN")
          root.apps.listBundled()
          waitFor(function() { return bundledVersion(id) === "1.1.0" }, function() {
            root.apps.queueUpdates([root.apps.queued(root.apps.record(id))])
            waitFor(function() { var r = root.apps.record(id); return !root.apps.updating && r && (r.version === "1.1.0" || r.update) }, function() {
              var b = root.apps.record(id)
              check(b.version === "1.1.0" && b.api === 3 && !b.update, "the bundled update from api 2 to 3, asking nothing new, installed quietly: " + JSON.stringify([b.version, b.api, b.update]))
              check(root.apps.review === null, "and no review for it")
              check(b.layout && b.layout.rows.length === 3 && b.layout.rows[0].id === "in" && b.layout.rows[0].shape === "logo", "its layout kept: " + JSON.stringify(b.layout))
              // the update matrix: what newAsks (the update path and review alike) makes of each
              var perms = function(net) { return { net: net, server: null, play: false, signIn: "", storage: false } }
              var app = function(api, net, settings) { return { kind: "app", api: api, permissions: perms(net), settings: settings || [] } }
              var keys = function(l) { return l.map(function(x) { return x.key }).join(",") }
              check(keys(root.apps.newAsks(app(2, ["a.example.com"]), app(3, ["a.example.com"]))) === "", "2 to 3, nothing new: quiet")
              check(keys(root.apps.newAsks(app(2, ["a.example.com"]), app(3, ["a.example.com", "b.example.com"]))) === "net:b.example.com", "2 to 3 and a host: review")
              check(keys(root.apps.newAsks(app(2, []), app(3, [], [{ key: "k", type: "secret", label: "Key" }]))) === "secret:k", "2 to 3 and a secret: review")
              check(/^api/.test(keys(root.apps.newAsks(app(3, []), app(4, [])))), "3 to 4: review")
              check(/^api/.test(keys(root.apps.newAsks(app(3, []), app(2, [])))), "3 to 2: review")
              check(/^kind/.test(keys(root.apps.newAsks({ kind: "launcher", api: 1, permissions: { web: ["a.example.com"] } }, app(3, [])))), "a launcher becoming an app: review")
              // api 4 records as they're loaded: netWrite only for its own net hosts and write methods
              var rec4 = root.apps.checkedRecord({ id: "tv.example.w", name: "W", version: "1.0.0", kind: "app", api: 4, source: root.src, sourceDir: root.sd,
                                                   permissions: { net: ["a.example.com"], netWrite: { "a.example.com": ["DELETE", "GET", "POST"], "b.example.com": ["POST"], "c": "POST" } } })
              check(rec4 && rec4.api === 4 && JSON.stringify(rec4.permissions.netWrite) === JSON.stringify({ "a.example.com": ["POST", "DELETE"] }),
                    "a loaded record keeps api 4 and only netWrite it could have: " + JSON.stringify(rec4 && [rec4.api, rec4.permissions.netWrite]))
              var rec5 = root.apps.checkedRecord({ id: "tv.example.w", name: "W", version: "1.0.0", kind: "app", api: 5, source: root.src, sourceDir: root.sd, permissions: {} })
              check(rec5 && rec5.api === 2, "an api it doesn't know isn't taken as one: " + (rec5 && rec5.api))
              // wrong passwords: 5 in a row, then 30 seconds' wait; a right one starts the count again
              for (var f = 0; f < 4; f++) root.apps.passwordFailed("tv.example.pw")
              check(root.apps.passwordWait("tv.example.pw") === 0, "4 wrong: no wait yet")
              root.apps.passwordFailed("tv.example.pw")
              var w5 = root.apps.passwordWait("tv.example.pw")
              check(w5 >= 29 && w5 <= 30, "the 5th: 30 seconds: " + w5)
              check(root.apps.passwordWait("tv.example.other") === 0, "another app isn't held up")
              root.apps.passwordWorked("tv.example.pw")
              check(root.apps.passwordWait("tv.example.pw") === 0, "a right one ends the wait")
              root.apps.passwordFailed("tv.example.pw")
              check(root.apps.passwordWait("tv.example.pw") === 0 && root.apps.passwordFails["tv.example.pw"].n === 1, "and the count starts again")
              // the server chosen while signing in, kept with the sign-in in one write
              var fsi = { id: "tv.example.fsi", name: "F", version: "1.0.0", kind: "app", api: 4, source: root.src, sourceDir: root.sd, sha256: "f", updated: 7,
                          permissions: { net: [], server: { label: "S", fromSignIn: true }, play: false, signIn: "code", storage: true },
                          settings: [], values: { "@forget": ["server", "data"], "@clear": ["signIn"] }, server: "", pin: "abc" }
              root.apps.installed = root.apps.installed.concat([fsi])
              var inst = root.apps.installOf(root.apps.record("tv.example.fsi"))
              check(root.apps.signedInWith("tv.example.fsi", "http://h/", "another-install").ok === false, "not for another install")
              check(root.apps.signedInWith("tv.example.fsi", "", inst).ok === false, "not without a server")
              var kept = root.apps.signedInWith("tv.example.fsi", "http://h/", inst)
              var fr = root.apps.record("tv.example.fsi")
              check(kept.ok && fr.server === "http://h/" && fr.pin === "" && fr.values["@signedIn"] === true
                    && JSON.stringify(fr.values["@forget"]) === JSON.stringify(["data"]) && fr.values["@clear"] === undefined,
                    "server, a fresh pin and signed in, the sign-in's clean-ups no longer owed, the others kept: " + JSON.stringify([fr.server, fr.pin, fr.values]))
              var onDisk = JSON.parse(rd(fake.configDir + "/apps.json")).installed.filter(function(x) { return x.id === "tv.example.fsi" })[0]
              check(onDisk && onDisk.server === "http://h/" && onDisk.values["@signedIn"] === true, "on disk, in the same write")
              check(root.apps.signedInWith("tv.example.fsi", "http://other/", inst).why === "it has another server", "another server goes through setServer first")
              root.apps.withRecord("tv.example.fsi", function(x) { x.pin = "keep"; x.values = {} })
              check(root.apps.signedInWith("tv.example.fsi", "http://h/", inst).ok && root.apps.record("tv.example.fsi").pin === "keep", "the same server keeps its pin")
              root.apps.installed = root.apps.installed.filter(function(x) { return x.id !== "tv.example.fsi" })
              root.apps.save()
              var recPw = root.apps.checkedRecord({ id: "tv.example.pw", name: "P", version: "1.0.0", kind: "app", api: 4, source: root.src, sourceDir: root.sd,
                                                    permissions: { server: { label: "S" }, signIn: "code+password" } })
              check(recPw.permissions.signIn === "code+password", "a loaded record keeps both ways: " + recPw.permissions.signIn)
              check(root.apps.checkedRecord({ id: "tv.example.pw", name: "P", version: "1.0.0", kind: "app", api: 4, source: root.src, sourceDir: root.sd,
                                              permissions: { signIn: "fingerprint" } }).permissions.signIn === "", "and no way it doesn't know")
              // the guide starts again (the plugin as it is now): the record as it's loaded from disk
              fake.pluginDir = Quickshell.env("OM_PG_ROOT")
              root.apps.destroy()
              var c = Qt.createComponent("file://" + fake.pluginDir + "/Apps.qml")
              root.apps = c.createObject(root, { guide: fake, sweep: false })
              waitFor(function() { return root.apps.loaded }, function() {
                var r = root.apps.record(id)
                check(r.api === 3 && r.layout && r.layout.rows.length === 3 && r.layout.look === "", "a restart keeps api 3 and its layout: " + JSON.stringify([r.api, r.layout]))
                // 4d: the plugin's own Scores (1.2.1, api 4, live) waits for you: a change of api is reviewed
                root.apps.on = true
                root.apps.listBundled()
                waitFor(function() { return bundledVersion(id) === "1.2.1" }, function() {
                  root.apps.queueUpdates([root.apps.queued(root.apps.record(id))])
                  waitFor(function() { var x = root.apps.record(id); return !root.apps.updating && x && (x.update || x.version === "1.2.1") }, function() {
                    var u = root.apps.record(id)
                    check(u.version === "1.1.0" && u.update && u.update.version === "1.2.1" && /version 4/.test(u.update.asks.join(" ")),
                          "api 3 to 4 isn't quiet: it waits, saying why: " + JSON.stringify([u.version, u.update]))
                    step4c()
                  }, "the api 4 update", 1500)
                }, "the plugin's Scores 1.2.1")
              }, "reload")
            }, "quiet update", 1500)
          }, "the plugin's Scores")
        }, "install 1.0.2")
      }, "review 1.0.2")
    }, "the old plugin's Scores")
  }

  // 4c: AppRuntime's picture asks (it loads only in a shell): one callback
  // a consumer however often it asks, nothing of a picture kept once it's
  // answered, and a stale answer for an older ask ignored while a newer one
  // is out. Labels in a layout counted as bin/om-pg-apps counts them.
  function step4c() {
    var c = Qt.createComponent("file://" + fake.pluginDir + "/AppRuntime.qml")
    if (c.status !== Component.Ready) { check(false, "AppRuntime loads: " + c.errorString()); step5(); return }
    var rt = c.createObject(root, { store: root.apps, record: { id: "tv.example.pics", source: "bundled", sourceDir: "0123456789abcdef",
                                                                version: "1.0.0", values: {}, settings: [] } })
    var got = []
    for (var i = 1; i <= 50; i++) rt.image("t", function(p, info) { got.push("view " + info.w) }, i, "visible", "view")
    rt.image("t", function(p, info) { got.push("home " + info.h) }, 50, "visible", "home:a")
    check(Object.keys(rt.imageWaits["t"]).length === 2, "fifty asks from the view and one from Home: two callbacks waiting")
    rt.onFrame(JSON.stringify({ t: "image", token: "t", path: "/tmp/x.png", w: 10, h: 20 }))
    check(got.join(",") === "view 10,home 20", "each called once: " + got)
    check(rt.imageWaits["t"] === undefined && rt.sentEpoch["t"] === undefined, "nothing of it kept once it's answered")
    var said = []
    rt.image("u", function(p, info) { said.push(info.code) }, 7, "visible", "view")
    rt.onFrame(JSON.stringify({ t: "image", token: "u", code: "stale", epoch: 6 }))
    check(said.length === 0, "a stale answer for an older ask is ignored while a newer one is out")
    rt.onFrame(JSON.stringify({ t: "image", token: "u", code: "stale", epoch: 7 }))
    check(said.join() === "stale" && rt.sentEpoch["u"] === undefined, "the one for this ask counts, and clears it")
    var emoji = ""
    for (var j = 0; j < 40; j++) emoji += "\ud83d\ude00"
    var lay = root.apps.checkedLayout({ rows: [{ id: "a", label: emoji }, { id: "b", label: "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\ud83d\ude00\ud83d\ude00" }] })
    check(lay.rows[0].label === emoji, "forty emoji stay forty")
    check(lay.rows[1].label === "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\ud83d\ude00", "39 letters and an emoji: forty, never half of one")
    rt.destroy()
    step5()
  }

  // 6: the runtime budget through the real ensure (AppBudget.js), with
  // three other apps' runtimes standing in: a sign-out still out (ready, no
  // lease, its call out, the app being changed) isn't stopped to make room
  // and nothing is queued; once it's stopping, a new start waits for its
  // slot; an idle one is the one that goes
  Component {
    id: standIn
    QtObject {
      property string phase: "ready"
      property var leases: ({})
      readonly property bool leased: Object.keys(leases).length > 0
      property bool busy: false
      property real lastUsed: Date.now()
      property int stops: 0
      signal stopped(string why, string text)
      function stop(forget) { stops++ }
    }
  }
  function step6() {
    var id = "tv.uber.scores"
    var a = standIn.createObject(root, { busy: true, lastUsed: Date.now() - 3000 })
    var b = standIn.createObject(root, { phase: "starting" })
    var c = standIn.createObject(root, { phase: "starting" })
    root.apps.runtimes = { "x.signout": a, "x.b": b, "x.c": c }
    root.apps.setChanging("x.signout", true)
    var e = root.apps.ensure(id, "foreground")
    check(e.rt === null && e.why === "three apps are busy", "a sign-out still out isn't stopped to make room: " + e.why)
    check(a.stops === 0, "the signing-out app isn't stopped")
    check(!root.apps.runtimes[id], "and nothing is queued")
    root.apps.setChanging("x.signout", false)
    a.phase = "stopping"
    var e2 = root.apps.ensure(id, "foreground")
    check(e2.rt !== null && e2.rt.phase === "queued", "once it's stopping, a new start waits for its slot: " + (e2.rt ? e2.rt.phase : e2.why))
    check(a.stops + b.stops + c.stops === 0, "nothing else stopped")
    if (e2.rt) e2.rt.stop("")         // never started: let go
    var idle = standIn.createObject(root, { lastUsed: Date.now() - 5000 })
    root.apps.runtimes = { "x.idle": idle, "x.b": b, "x.c": c }
    var e3 = root.apps.ensure(id, "foreground")
    check(idle.stops === 1, "an idle one is the one that goes")
    check(e3.rt !== null && e3.rt.phase === "queued", "and the new start waits for its slot")
    if (e3.rt) e3.rt.stop("")
    root.apps.runtimes = ({})
    finish()
  }

  // 5: a bundled app with code (Scores) installed and started through
  // AppRuntime, in its own systemd scope, with the init its record gives it:
  // what it owes is done before it runs, and no longer owed once it's ready
  Component { id: writeFile; FileView { blockWrites: true; preload: false; printErrors: false } }
  function finish() { step7() }
  function done() { console.log("H DONE fails=" + root.fails); Qt.quit() }

  // 7: an incarnation is given only once it's on disk. A record from
  // before them, loaded where apps.json can't be written, has none (so
  // nothing is customized for it under one the next start wouldn't know);
  // it's tried again, and the one given once it can be saved is the one a
  // restart loads
  function incarnationOnDisk() {
    var d = JSON.parse(rd(fake.configDir + "/apps.json"))
    var a = d.installed.filter(function(x) { return x.id === "tv.example.old" })[0]
    return a ? (a.incarnation || "") : "none"
  }
  function step7() {
    root.apps.destroy()
    var w = writeFile.createObject(root, { path: fake.configDir + "/apps.json" })
    w.setText(JSON.stringify({ on: false, installed: [{ id: "tv.example.old", version: "1.0.0", kind: "launcher", name: "Old", source: root.src, sourceDir: root.sd,
                                                        permissions: { web: ["example.com"] }, launch: { web: "https://example.com/" }, values: {} }] }))
    w.destroy()
    chmod.command = ["/bin/sh", "-c", "chmod 400 \"$0/apps.json\" && chmod 500 \"$0\"", fake.configDir]
    chmod.running = true
    waitFor(function() { return !chmod.running }, function() {
      var c = Qt.createComponent("file://" + fake.pluginDir + "/Apps.qml")
      root.apps = c.createObject(root, { guide: fake, sweep: false, incarnationRetryMs: 100 })
      waitFor(function() { return root.apps.loaded }, function() {
        var a = root.apps.record("tv.example.old")
        check(a && a.incarnation === "", "not saved: no incarnation in memory either: " + (a ? JSON.stringify(a.incarnation) : "no record"))
        check(root.apps.incarnationProblem !== "", "and why: " + root.apps.incarnationProblem)
        check(incarnationOnDisk() === "", "none on disk")
        var tries = 0
        waitFor(function() { return ++tries > 15 }, function() {   // a few tries go by, all failing
          check(root.apps.record("tv.example.old").incarnation === "", "still none while it can't be saved")
          chmod.command = ["/bin/sh", "-c", "chmod 700 \"$0\" && chmod 600 \"$0/apps.json\"", fake.configDir]
          chmod.running = true
          waitFor(function() { return !chmod.running && root.apps.record("tv.example.old").incarnation !== "" }, function() {
            var given = root.apps.record("tv.example.old").incarnation
            check(/^[0-9a-f]{16}$/.test(given) && incarnationOnDisk() === given, "once it can be saved, it's given, and it's the one on disk: " + given)
            check(root.apps.incarnationProblem === "", "and nothing's wrong any more")
            root.apps.destroy()
            var c2 = Qt.createComponent("file://" + fake.pluginDir + "/Apps.qml")
            root.apps = c2.createObject(root, { guide: fake, sweep: false })
            waitFor(function() { return root.apps.loaded }, function() {
              check(root.apps.record("tv.example.old").incarnation === given, "a restart loads the same one")
              stepB()
            }, "reload")
          }, "the retry")
        }, "tries")
      }, "load")
    }, "chmod")
  }
  // B: signed app files in Apps.qml, with the helper stood in. Picking one
  // calls only app-inspect; a different key is installed beside the old app
  // and recorded before the old identity is removed, with none of its data.
  // Update checks fetch only the signed note; the package command starts only
  // after consent. Unknown sources off kills an outstanding note or package
  // run, stops these apps and starts no new contact.
  function helperAnswer(cmd, obj) {
    var w = writeFile.createObject(root, { path: root.tmp + "/answers/" + cmd + ".json" })
    w.setText(obj === null ? "\n" : JSON.stringify(obj))
    w.destroy()
  }
  function helperCalls() {
    var out = []
    rd(root.tmp + "/answers/calls").split("\n").forEach(function(l) { try { out.push(JSON.parse(l)) } catch (e) {} })
    return out
  }
  function signedManifest(version, extra) {
    return Object.assign({ id: "tv.alex.clock", name: "Clock", version: version, kind: "app", api: 4, author: "Alex", description: "A clock", color: "#112233",
                           permissions: { net: ["time.example.com"], netWrite: {}, server: null, play: false, signIn: "", storage: true },
                           settings: [{ key: "style", type: "choice", label: "Style", choices: ["plain", "bold"], default: "plain" }], home: [], main: "main.py" }, extra || {})
  }
  function signedRecord(source, version, over) {
    var m = signedManifest(version)
    return Object.assign({ id: m.id, name: m.name, version: version, kind: m.kind, api: m.api, author: m.author, description: m.description, color: m.color,
                           source: source, sourceDir: source === "app:1111111111111111" ? "1111111111111111" : "2222222222222222", from: "appFile",
                           sha256: "a".repeat(64), files: {}, installed: 5, updated: 5, used: 0, permissions: m.permissions, main: m.main,
                           settings: m.settings, home: [], values: { style: "bold", "@secret:old": true, "@signedIn": true }, server: "https://old.example", pin: "",
                           enabled: true, broken: "", revoked: "", update: null, catalogName: "", keyFingerprint: "SHA256:" + "o".repeat(43),
                           updateAddress: "https://updates.example.com/clock/", updateChecked: 0, releaseUpdated: 1000,
                           incarnation: "0123456789abcdef" }, over || {})
  }
  function updateEntry(version) {
    var m = signedManifest(version)
    return { id: m.id, name: m.name, version: version, kind: m.kind, api: m.api, author: m.author, description: m.description, color: m.color,
             permissions: m.permissions, package: "https://updates.example.com/clock/clock-" + version + ".tar.gz",
             packageName: "clock-" + version + ".tar.gz", sha256: "b".repeat(64), size: 2048 }
  }
  function updateReviewFor(a, entry) {
    return { format: 1, source: a.source, id: a.id, installed: a.version, state: "c".repeat(64), updated: 2000,
             version: entry.version, size: entry.size, url: entry.package, fingerprint: a.keyFingerprint, entry: entry }
  }
  function stepB() {
    fake.pluginDir = Quickshell.env("STUB_PLUGIN")
    root.apps.on = true
    root.apps.unknownSources = true
    root.apps.checked = Date.now() / 1000
    var old = signedRecord("app:1111111111111111", "1.0.0")
    root.apps.installed = [old]
    root.apps.save()
    var m = signedManifest("1.0.0")
    var n = helperCalls().length
    helperAnswer("app-inspect", { ok: true, staging: fake.cacheDir + "/app-staging/app-signed", tree: "tree", manifest: m, files: {}, sha256: "d".repeat(64),
                                  source: "appFile", sourceName: "Signed app file", sourceId: "app:2222222222222222",
                                  keyFingerprint: "SHA256:" + "n".repeat(43), updated: 1100, updates: "https://updates.example.com/clock/" })
    var inspected = null
    check(root.apps.getAppFile(Quickshell.env("HOME") + "/Downloads/clock.tvapp", function(ok) { inspected = ok }), "a signed app file can be checked while Unknown sources is on")
    waitFor(function() { return inspected !== null }, function() {
      var r = root.apps.review
      var made = helperCalls().slice(n).map(function(c) { return c[0] })
      check(inspected === true && JSON.stringify(made) === JSON.stringify(["app-inspect"]), "picking it contacts nothing: " + JSON.stringify(made))
      check(r && r.from === "appFile" && r.source === "app:2222222222222222" && r.replaces === "appFile" && r.fingerprint === "SHA256:" + "n".repeat(43),
            "its pinned key identity and different-key replacement are in review")
      helperAnswer("app-current", { ok: true })
      helperAnswer("install", { ok: true, manifest: m, files: {}, path: root.tmp + "/new-clock", proof: "appFile", source: r.source,
                                sourceDir: "2222222222222222", keyFingerprint: r.fingerprint })
      helperAnswer("remove", { ok: true })
      var installed = null
      root.apps.confirm(function(ok) { installed = ok })
      waitFor(function() { return installed !== null }, function() {
        var a = root.apps.record(m.id)
        var order = helperCalls().slice(n).map(function(c) { return c[0] }).filter(function(c) { return ["app-current", "install", "remove"].indexOf(c) >= 0 })
        check(installed === true && JSON.stringify(order) === JSON.stringify(["app-current", "install", "remove"]), "still current, new identity installed, then old removed: " + JSON.stringify(order))
        check(a && a.source === "app:2222222222222222" && JSON.stringify(a.values) === "{}" && a.server === "" && a.incarnation !== old.incarnation,
              "another key is a new app with none of the old data: " + JSON.stringify(a ? [a.source, a.values, a.server, a.incarnation] : null))
        check(a.updateAddress === "https://updates.example.com/clock/" && a.keyFingerprint === r.fingerprint, "its update address and pinned key are kept")
        check(root.apps.commit(m.id, function(x) { x.values = { style: "bold" } }), "new app data is saved under the new identity")
        stepBUpdate(root.apps.record(m.id))
      }, "signed install")
    }, "signed inspection")
  }
  function stepBUpdate(a) {
    var entry = updateEntry("2.0.0")
    var review = updateReviewFor(a, entry)
    var n = helperCalls().length
    helperAnswer("app-update-check", { ok: true, checked: 3000, review: review, update: entry, revoked: null })
    var checked = null
    root.apps.checkAppFiles(true, function(ok) { checked = ok }, a.id)
    waitFor(function() { return checked !== null }, function() {
      var now = root.apps.record(a.id)
      var made = helperCalls().slice(n).map(function(c) { return c[0] })
      check(checked === true && JSON.stringify(made) === JSON.stringify(["app-update-check"]), "an update look fetches only its signed note: " + JSON.stringify(made))
      check(now.update && now.update.version === "2.0.0" && now.update.review.url === entry.package, "Update available keeps the exact consent review")
      var opened = null
      root.apps.reviewAppUpdate(a.id, function(ok) { opened = ok })
      check(opened === true && root.apps.review && root.apps.review.updateConsent && root.apps.review.fetchAddress === entry.package
            && root.apps.review.fetchSize === entry.size && root.apps.review.fingerprint === a.keyFingerprint,
            "the consent has the exact address, version, size and key")
      check(helperCalls().slice(n).every(function(c) { return c[0] !== "app-update-prepare" }), "no package before Agree")
      stepBAgree(entry)
    }, "signed note check")
  }
  function stepBAgree(entry) {
    var a = root.apps.record("tv.alex.clock")
    var m2 = signedManifest("2.0.0")
    var n = helperCalls().length
    helperAnswer("app-update-prepare", { ok: true, staging: fake.cacheDir + "/app-staging/app-update", tree: "tree2", manifest: m2, files: {}, sha256: entry.sha256,
                                         source: "appFile", sourceName: "Signed app file", sourceId: a.source, keyFingerprint: a.keyFingerprint,
                                         updated: 2000, updates: a.updateAddress })
    helperAnswer("app-current", { ok: true })
    helperAnswer("install", { ok: true, manifest: m2, files: {}, path: root.tmp + "/updated-clock", proof: "appFile", source: a.source,
                              sourceDir: a.sourceDir, keyFingerprint: a.keyFingerprint })
    var agreed = null
    root.apps.confirm(function(ok) { agreed = ok })
    waitFor(function() { return agreed !== null }, function() {
      var made = helperCalls().slice(n).map(function(c) { return c[0] }).filter(function(c) { return ["app-update-prepare", "app-current", "install"].indexOf(c) >= 0 })
      var after = root.apps.record(a.id)
      check(agreed === true && JSON.stringify(made) === JSON.stringify(["app-update-prepare", "app-current", "install"]), "Agree fetches, rechecks, then installs: " + JSON.stringify(made))
      check(after.version === "2.0.0" && after.values.style === "bold" && after.source === a.source, "same key update keeps its data and identity")
      stepBWithdraw(after)
    }, "consented signed update")
  }
  function stepBWithdraw(a) {
    var n = helperCalls().length
    helperAnswer("app-update-check", { ok: true, checked: 4000, review: updateReviewFor(a, updateEntry("2.0.0")), update: null,
                                       revoked: { version: "2.0.0", reason: "A security problem." } })
    var checked = null
    root.apps.checkAppFiles(true, function(ok) { checked = ok }, a.id)
    waitFor(function() { return checked !== null }, function() {
      var pulled = root.apps.record(a.id)
      check(pulled.revoked === "A security problem." && pulled.enabled === false && root.apps.cannotOpen(a.id) === "its developer withdrew it",
            "a developer withdrawal turns it off and says why")
      check(helperCalls().slice(n).map(function(c) { return c[0] }).indexOf("app-update-prepare") < 0, "a withdrawal fetches no package")
      stepBOff(pulled)
    }, "withdrawal")
  }
  function stepBOff(a) {
    root.apps.withRecord(a.id, function(x) { x.revoked = ""; x.enabled = true; x.updateChecked = 0 })
    root.apps.save()
    helperAnswer("app-update-check", { ok: true, checked: 5000, review: updateReviewFor(root.apps.record(a.id), updateEntry("3.0.0")), update: updateEntry("3.0.0"), revoked: null, _hold: "app-check.hold" })
    var h = writeFile.createObject(root, { path: root.tmp + "/answers/app-check.hold" }); h.setText("1"); h.destroy()
    var n = helperCalls().length
    root.apps.checkAppFiles(true)
    waitFor(function() { return root.apps.appCheckRun !== null }, function() {
      root.apps.setUnknownSources(false)
      check(!root.apps.checkingAppFiles && root.apps.appCheckRun === null && root.apps.appCheckQueue.length === 0, "Unknown sources off kills an update-note check")
      check(root.apps.cannotOpen(a.id) === "it's a third-party app, and third-party apps are off", "and its apps stop")
      var count = helperCalls().slice(n).filter(function(c) { return c[0] === "app-update-check" }).length
      root.apps.freshen()
      var t = poll.createObject(root, { interval: 120 })
      t.triggered.connect(function() {
        t.destroy()
        var after = helperCalls().slice(n).filter(function(c) { return c[0] === "app-update-check" }).length
        check(after === count, "while off, no update address is contacted again")
        stepBDone()
      })
      t.start()
    }, "held app-file check")
  }
  function stepBDone() {
    fake.pluginDir = Quickshell.env("OM_PG_ROOT")
    var before = root.apps.record("tv.alex.clock")
    var noUpdates = signedManifest(before.version)
    root.apps.review = { from: "appFile", manifest: noUpdates, updateAddress: "", releaseUpdated: 6000 }
    var kept = null
    root.apps.keep({ manifest: noUpdates, path: root.tmp + "/same-clock", sourceDir: before.sourceDir,
                     files: {}, keyFingerprint: before.keyFingerprint }, before.source, "Signed app file", before.sha256,
                   function(warning, saved) { kept = saved })
    check(kept === true && root.apps.record(before.id).updateAddress === "",
          "a signed file that removes its update address does not keep scheduling checks")
    root.apps.review = null
    root.apps.showDeveloper()
    root.apps.setDeveloper(true)
    check(root.apps.developer && root.apps.developerShown, "Developer mode remains separate: on, its row shows")
    root.apps.setDeveloper(false)
    check(!root.apps.developer && !root.apps.developerShown, "Developer mode off: its row hides again")
    done()
  }
  // 8: an app from one of your sources. Its review comes straight from the
  // list (nothing downloaded), bound to a snapshot; Install gets it ready
  // first (bin/om-pg-apps prepare), and a prepare that fails (its package's
  // address never resolves) installs nothing, stages nothing and says why;
  // Cancel while it's getting ready leaves nothing staged either. What a
  // source's list says of the apps you have from it: a newer version waits
  // for you, a pulled one turns off, and while its key changed nothing waits.
  function step8() {
    var s = sourceFrom(rd(Quickshell.env("T") + "/sfolder").trim())
    var entry = s.list.apps[0]
    var before = JSON.stringify(root.apps.installed.map(function(a) { return a.id }))
    check(root.apps.reviewSource(entry, s), "its review opens from the list")
    var r = root.apps.review
    check(r && r.from === "source" && r.staging === "" && r.snapshot.source === s.id && r.snapshot.life === s.life && r.snapshot.listSha256 === s.list.listSha256
          && JSON.stringify(r.snapshot.entry) === JSON.stringify({ id: entry.id, version: entry.version, kind: entry.kind, package: entry["package"], sha256: entry.sha256, size: entry.size, permissions: entry.permissions }),
          "bound to a snapshot, nothing downloaded: " + JSON.stringify(r ? r.snapshot : null))
    var said = null
    root.apps.confirm(function(ok) { said = ok })
    check(root.apps.preparing && !root.apps.installing, "getting it ready (Cancel still works)")
    waitFor(function() { return said !== null }, function() {
      check(said === false && !root.apps.preparing, "a failed prepare installs nothing")
      check(/^Not installed: Couldn't get the app/.test(root.apps.status), "and says why: " + root.apps.status)
      check(JSON.stringify(root.apps.installed.map(function(a) { return a.id })) === before, "what you have is as it was")
      // Cancel while it's getting ready
      root.apps.reviewSource(entry, s)
      var said2 = null
      root.apps.confirm(function(ok) { said2 = ok })
      check(root.apps.cancel(), "Cancel works while it gets ready")
      waitFor(function() { return !root.apps.preparing }, function() {
        check(said2 === null && root.apps.review === null, "cancelled: nothing more happens")
        // what a source's list says of the apps you have from it
        root.apps.installed = root.apps.installed.concat([{ id: "tv.alex.films", name: "Films", version: "0.9.0", kind: "launcher", source: s.id, from: "source",
                                                             sourceDir: "", permissions: { web: ["films.example.com"] }, launch: { web: "https://films.example.com/" },
                                                             enabled: true, broken: "", revoked: "", update: null, values: {}, files: {}, catalogName: s.name }])
        root.apps.applySource(s)
        var a = root.apps.record("tv.alex.films")
        check(a.update && a.update.version === "1.0.0", "a newer version waits for you: " + JSON.stringify(a.update))
        check(!root.apps.updateQueue.some(function(q) { return q.id === "tv.alex.films" }), "never quietly")
        root.apps.withRecord("tv.alex.films", function(x) { x.version = "1.0.0" })
        root.apps.applySource(s)
        check(root.apps.record("tv.alex.films").update === null, "the same version: nothing waits")
        root.apps.withRecord("tv.alex.films", function(x) { x.version = "0.9.0" })
        root.apps.applySource(Object.assign({}, s, { keyChanged: "SHA256:" + "B".repeat(43) }))
        check(root.apps.record("tv.alex.films").update === null, "while its key changed, nothing waits")
        // the delta as its review has it (a change of kind or API named), not
        // its permissions alone
        var listing = function(e) { return Object.assign({}, s, { list: Object.assign({}, s.list, { apps: [Object.assign({}, entry, { id: "tv.alex.films", version: "2.0.0" }, e)] }) }) }
        var codeAsks = { net: [], netWrite: {}, server: null, play: false, signIn: "", storage: false }
        root.apps.applySource(listing({ kind: "app", api: 4, permissions: codeAsks }))
        var u = root.apps.record("tv.alex.films").update
        check(u && JSON.stringify(u.asks) === JSON.stringify(["Now run code in a sandbox on this computer"]), "a website turning into code says so: " + JSON.stringify(u))
        root.apps.withRecord("tv.alex.films", function(x) { x.kind = "app"; x.api = 3; x.permissions = codeAsks })
        root.apps.applySource(listing({ kind: "app", api: 4, permissions: codeAsks }))
        u = root.apps.record("tv.alex.films").update
        check(u && JSON.stringify(u.asks) === JSON.stringify(["Now use version 4 of the guide's app protocol, where it used version 3"]), "a change of API is named: " + JSON.stringify(u))
        root.apps.withRecord("tv.alex.films", function(x) { x.kind = "launcher"; delete x.api; x.permissions = { web: ["films.example.com"] } })
        var pulled = Object.assign({}, s, { list: Object.assign({}, s.list, { revoked: [{ id: "tv.alex.films", version: "*", reason: "It was broken." }] }) })
        root.apps.applySource(pulled)
        a = root.apps.record("tv.alex.films")
        check(a.revoked === "It was broken." && a.enabled === false, "a pulled one turns off: " + a.revoked)
        check(JSON.parse(rd(fake.configDir + "/apps.json")).installed.filter(function(x) { return x.id === "tv.alex.films" })[0].revoked === "It was broken.", "saved")
        // got ready, then the source changed before Install went on: asked first, nothing touched
        var have = root.apps.record("tv.alex.films")
        var m = { id: "tv.alex.films", name: "Films", version: "1.1.0", author: "Alex", description: "", kind: "launcher", api: 1, permissions: { web: ["films.example.com"] }, settings: [], home: [], launch: { web: "https://films.example.com/" } }
        root.apps.review = { staging: fake.cacheDir + "/app-staging/app-stale", tree: "x", manifest: m, sha256: "", from: "source", file: s.name, fingerprint: s.fingerprint,
                             source: s.id, have: have, replaces: "source", asks: root.apps.asks(m.permissions, []), newAsks: [], snapshot: {} }   // (a replace: the old one would go first)
        var said3 = null
        root.apps.confirm(function(ok) { said3 = ok })
        waitFor(function() { return said3 !== null }, function() {
          check(said3 === false, "refused")
          check(/^Not installed: Its source has a newer list/.test(root.apps.status), "saying why: " + root.apps.status)
          var after = root.apps.record("tv.alex.films")
          check(after && after.version === "0.9.0" && after.revoked === "It was broken.", "what you have untouched")
          check(!root.apps.changing["tv.alex.films"] && !root.apps.installing && root.apps.review === null, "and let go")
          // taking the place of an app from a file: installed first, the old one's
          // files and data only after; an install that's refused leaves it all
          var old = root.apps.record("tv.example.old")
          var before = JSON.stringify(old)
          var m2 = { id: "tv.example.old", name: "Old", version: "2.0.0", author: "Alex", description: "", kind: "launcher", api: 1, permissions: { web: ["example.com"] }, settings: [], home: [], launch: { web: "https://example.com/" } }
          var r2 = { staging: fake.cacheDir + "/app-staging/app-stale2", tree: "x", manifest: m2, sha256: "", from: "source", file: s.name, fingerprint: s.fingerprint,
                     source: s.id, have: old, replaces: "file", asks: root.apps.asks(m2.permissions, []), newAsks: [], snapshot: {} }
          root.apps.review = r2
          root.apps.installing = true
          root.apps.setChanging("tv.example.old", true)
          var said4 = null
          root.apps.replaceFromSource(r2, function(ok) { said4 = ok })
          waitFor(function() { return said4 !== null }, function() {
            check(said4 === false && /The one you have is as it was/.test(root.apps.status), "a refused install: " + root.apps.status)
            check(JSON.stringify(root.apps.record("tv.example.old")) === before, "its record exactly as it was")
            check(rd(root.tmp + "/data/om-pg/app-store/" + root.sd + "/tv.example.old.json").indexOf("kept") >= 0, "and its data")
            check(!root.apps.changing["tv.example.old"] && !root.apps.installing, "let go")
            step9()
          }, "the replace", 1500)
        }, "the stale install", 1500)
      }, "the cancelled prepare", 1500)
    }, "prepare", 1500)
  }
  // 9: the stand-in plugin (tests/appstate.test.py): the helper's answers
  // that matter here are the test's (answer), the rest the real helper's;
  // calls() is every call made to it
  function answer(cmd, obj) {
    var w = writeFile.createObject(root, { path: root.tmp + "/answers/" + cmd + ".json" })
    w.setText(obj === null ? "\n" : JSON.stringify(obj))   // (blank: none, the real helper answers; a new FileView doesn't write "", its text already)
    w.destroy()
  }
  function calls() {
    var out = []
    rd(root.tmp + "/answers/calls").split("\n").forEach(function(l) { try { out.push(JSON.parse(l)) } catch (e) {} })   // (one still being written: next look)
    return out
  }
  function onDisk(id) { return JSON.parse(rd(fake.configDir + "/apps.json")).installed.filter(function(a) { return a.id === id })[0] || null }
  function diskText() { return rd(fake.configDir + "/apps.json") }
  property var s9: null
  function step9() {
    fake.pluginDir = Quickshell.env("STUB_PLUGIN")
    root.s9 = sourceFrom(rd(Quickshell.env("T") + "/sfolder").trim())
    root.apps.on = true
    root.apps.unknownSources = true
    root.apps.checked = Date.now() / 1000   // (no catalog fetch)
    step9a()
  }
  function sourceApp(id, over) {
    var s = root.s9
    return Object.assign({ id: id, name: "Clock", version: "1.0.0", kind: "launcher", api: 1, author: "Alex", description: "", source: s.id, from: "source", sourceDir: root.sd,
                           sha256: "a".repeat(64), files: {}, installed: 5, updated: 5, used: 0, permissions: { web: ["clock.example.com"] }, launch: { web: "https://clock.example.com/" },
                           settings: [], home: [], values: {}, server: "", pin: "", enabled: true, broken: "", revoked: "", update: null, catalogName: s.name, keyFingerprint: "",
                           incarnation: "0123456789abcdef" }, over || {})
  }

  // 9a: a source you removed (its apps stay, off): its apps can't be turned
  // on or opened again for the rest of the session, as at the next start,
  // and no update waits for them (none can come)
  function step9a() {
    var s = root.s9
    var w = sourceApp("tv.alex.clock", { update: { version: "1.1.0", asks: [] } })
    root.apps.installed = [w]
    root.apps.setChecked(w.id, true)
    check(root.apps.cannotOpen(w.id) === "" && root.apps.updates.length === 1, "it opens before, an update waiting: " + root.apps.cannotOpen(w.id))
    root.apps.sourceGone(s.id)
    var said = root.apps.setEnabled(w.id, true)
    check(said === "Its source was removed: remove it and install it again", "it can't be turned on again: " + said)
    check(root.apps.cannotOpen(w.id) === "Its source was removed", "nor opened: " + root.apps.cannotOpen(w.id))
    check(root.apps.record(w.id).enabled === false && !root.apps.ready.some(function(a) { return a.id === w.id }), "it's off")
    check(root.apps.record(w.id).update === null && root.apps.updates.length === 0, "no update waits for it: " + JSON.stringify(root.apps.record(w.id).update))
    var d = onDisk(w.id)
    check(d && d.broken === "Its source was removed" && d.update === null && d.enabled === false, "saved so: " + JSON.stringify(d ? [d.broken, d.update, d.enabled] : null))
    step9b()
  }

  // 9b: an app from a source, kept with what that source's list says now
  // (a fetch that came in while it installed): one it pulls is off, and
  // that's said; while its key changed, its list doesn't count
  function step9b() {
    var s = root.s9
    var pulling = Object.assign({}, s.list, { revoked: [{ id: "tv.alex.clock", version: "1.0.0", reason: "A bad build: don't run it." }] })
    var res = { manifest: { id: "tv.alex.clock", name: "Clock", version: "1.0.0", kind: "launcher", api: 1, author: "Alex", description: "",
                            permissions: { web: ["clock.example.com"] }, launch: { web: "https://clock.example.com/" } },
                path: root.tmp + "/x", sourceDir: root.sd, files: {}, keyFingerprint: "" }
    var kept = function(withSource) {
      fake.sources = { find: function(id) { return id === s.id ? withSource : null } }
      root.apps.installed = []
      var warning = null
      root.apps.setChanging(res.manifest.id, true)
      root.apps.keep(res, s.id, s.name, "b".repeat(64), function(w) { warning = w })
      root.apps.setChanging(res.manifest.id, false)
      fake.sources = null
      return warning
    }
    var said = kept(Object.assign({}, s, { list: pulling }))
    var a = root.apps.record("tv.alex.clock")
    check(a.revoked === "A bad build: don't run it." && a.enabled === false && root.apps.cannotOpen(a.id) !== "",
          "pulled by the list its source has now: off: " + JSON.stringify([a.revoked, a.enabled, root.apps.cannotOpen(a.id)]))
    check(said === "Clock was turned off: its source pulled it.", "and said: " + said)
    check(onDisk("tv.alex.clock").revoked === "A bad build: don't run it.", "saved so")
    kept(Object.assign({}, s, { list: pulling, keyChanged: "SHA256:" + "B".repeat(43) }))
    check(root.apps.record("tv.alex.clock").revoked === "" && root.apps.record("tv.alex.clock").enabled === true, "not while its key changed")
    kept(s)
    check(root.apps.record("tv.alex.clock").revoked === "", "nor when its list doesn't pull it")
    var ahead = Object.assign({}, s.list, { apps: [Object.assign({}, s.list.apps[0], { id: "tv.alex.clock", version: "1.1.0", permissions: { web: ["clock.example.com"] } })] })
    kept(Object.assign({}, s, { list: ahead }))
    check(JSON.stringify(root.apps.record("tv.alex.clock").update) === JSON.stringify({ version: "1.1.0", asks: [] }), "a newer one its source lists waits: " + JSON.stringify(root.apps.record("tv.alex.clock").update))
    var aheadCode = Object.assign({}, s.list, { apps: [Object.assign({}, s.list.apps[0], { id: "tv.alex.clock", version: "1.1.0", kind: "app", api: 4,
                                                                                           permissions: { net: [], netWrite: {}, server: null, play: false, signIn: "", storage: false } })] })
    kept(Object.assign({}, s, { list: aheadCode }))
    check(JSON.stringify(root.apps.record("tv.alex.clock").update) === JSON.stringify({ version: "1.1.0", asks: ["Now run code in a sandbox on this computer"] }),
          "one that turns into code says so: " + JSON.stringify(root.apps.record("tv.alex.clock").update))
    kept(Object.assign({}, s, { list: Object.assign({}, ahead, { revoked: pulling.revoked }) }))
    check(root.apps.record("tv.alex.clock").update === null, "but not for one it pulls")
    step9c()
  }

  // 9c: an update that drops a secret setting and the sign-in withdraws
  // them before its package goes in. Install refuses, saying nothing on
  // disk changed (unchanged): they're given back before anything can run
  // it, and apps.json is byte for byte as it was
  property var m2: ({ id: "tv.alex.code", name: "Code", version: "2.0.0", kind: "app", api: 2, author: "Alex", description: "", main: "main.py",
                      settings: [{ key: "theme", type: "text", label: "Theme" }],
                      permissions: { net: [], netWrite: {}, server: { label: "S", defaultPort: 0 }, play: false, signIn: "", storage: true } })
  function codeV1() {
    return sourceApp("tv.alex.code", { name: "Code", kind: "app", api: 2, main: "main.py", launch: null,
                                       permissions: { net: [], netWrite: {}, server: { label: "S", defaultPort: 0 }, play: false, signIn: "code", storage: true },
                                       settings: [{ key: "apiKey", type: "secret", label: "API Key" }, { key: "theme", type: "text", label: "Theme" }],
                                       values: { "@secret:apiKey": true, "@signedIn": true, theme: "dark", "@clear": ["oldKey"] }, server: "https://s.example" })
  }
  function updateReview() {
    var s = root.s9
    return { staging: fake.cacheDir + "/app-staging/app-code", tree: "x", manifest: root.m2, sha256: "", from: "source", file: s.name, fingerprint: s.fingerprint,
             source: s.id, have: root.apps.record("tv.alex.code"), replaces: "", asks: root.apps.asks(root.m2.permissions, root.m2.settings), newAsks: [], snapshot: {},
             checkedNow: true }   // (its source checked just now)
  }
  function updateThat(installSays, then, wrongWriter) {
    root.apps.installed = [codeV1()]
    root.apps.save()
    var before = diskText()
    answer("install", installSays)
    root.apps.review = updateReview()
    var said = null
    root.apps.confirm(function(ok) { said = ok })
    var w = root.apps.record("tv.alex.code").values
    check(w["@secret:apiKey"] === undefined && w["@signedIn"] === undefined && JSON.stringify(w["@clear"]) === JSON.stringify(["oldKey", "apiKey", "signIn"]),
          "withdrawn before its package goes in: " + JSON.stringify(w))
    var orig = root.apps.writerKind
    if (wrongWriter) root.apps.writerKind = liar   // (withdrawn on disk already: no save lands from here)
    waitFor(function() { return said !== null }, function() {
      root.apps.writerKind = orig
      check(said === false && !root.apps.changing["tv.alex.code"] && !root.apps.installing && root.apps.review === null, "not installed, and let go")
      then(before)
    }, "the update")
  }
  function step9c() {
    updateThat({ ok: false, error: "its source has a newer list since you were shown it: look again", unchanged: true }, function(before) {
      check(root.apps.status === "Not installed: its source has a newer list since you were shown it: look again", "said why: " + root.apps.status)
      check(JSON.stringify(root.apps.record("tv.alex.code").values) === JSON.stringify(codeV1().values), "what was withdrawn is given back: " + JSON.stringify(root.apps.record("tv.alex.code").values))
      check(diskText() === before, "apps.json byte for byte as it was: " + JSON.stringify(onDisk("tv.alex.code").values))
      step9c2()
    })
  }
  // 9c2: only what withdraw took goes back: a setting changed while it
  // installed (its settings page isn't held) stays as it was changed
  function step9c2() {
    root.apps.installed = [codeV1()]
    root.apps.save()
    answer("install", { ok: false, error: "its source has a newer list since you were shown it: look again", unchanged: true })
    root.apps.review = updateReview()
    var said = null
    root.apps.confirm(function(ok) { said = ok })
    root.apps.setValue("tv.alex.code", "theme", "light")
    waitFor(function() { return said !== null }, function() {
      var v = root.apps.record("tv.alex.code").values
      check(JSON.stringify(v) === JSON.stringify({ "@secret:apiKey": true, "@signedIn": true, theme: "light", "@clear": ["oldKey"] }), "given back, the setting changed meanwhile kept: " + JSON.stringify(v))
      check(JSON.stringify(onDisk("tv.alex.code").values) === JSON.stringify(v), "on disk too")
      step9c3()
    }, "the refused update")
  }
  // 9c3: a secret already owed a clear (not set) stays owed when the rest
  // is given back (only the names withdraw added go)
  function step9c3() {
    root.apps.installed = [Object.assign(codeV1(), { values: { "@signedIn": true, theme: "dark", "@clear": ["apiKey"] } })]
    root.apps.save()
    var before = diskText()
    answer("install", { ok: false, error: "its source has a newer list since you were shown it: look again", unchanged: true })
    root.apps.review = updateReview()
    var said = null
    root.apps.confirm(function(ok) { said = ok })
    waitFor(function() { return said !== null }, function() {
      check(JSON.stringify(root.apps.record("tv.alex.code").values) === JSON.stringify({ "@signedIn": true, theme: "dark", "@clear": ["apiKey"] }) && diskText() === before,
            "what was owed before stays owed: " + JSON.stringify(root.apps.record("tv.alex.code").values))
      step9d()
    }, "the refused update")
  }
  // 9d: given back only when install says nothing changed: any other
  // failure keeps them withdrawn (the safe way round), and so does a give
  // back that can't be saved; either way that's said, and nothing says
  // nothing changed
  function step9d() {
    var withdrawn = JSON.stringify({ theme: "dark", "@clear": ["oldKey", "apiKey", "signIn"] })
    updateThat({ ok: false, error: "it couldn't be put in place (Input/output error), and putting back what was there didn't finish: the new 2.0.0 in /x is still there (remove it);" }, function() {
      check(JSON.stringify(root.apps.record("tv.alex.code").values) === withdrawn && JSON.stringify(onDisk("tv.alex.code").values) === withdrawn,
            "an uncertain failure keeps them withdrawn: " + JSON.stringify(root.apps.record("tv.alex.code").values))
      check(/remove it\)\. Its API Key and sign-in are cleared before it next starts: set them again then\.$/.test(root.apps.status), "and says so: " + root.apps.status)
      updateThat({ ok: false, error: "it couldn't be made ready to put in place (No space left on device), so nothing changed", unchanged: true }, function() {
        check(JSON.stringify(root.apps.record("tv.alex.code").values) === withdrawn && JSON.stringify(onDisk("tv.alex.code").values) === withdrawn,
              "a give back that can't be saved keeps them withdrawn: " + JSON.stringify(root.apps.record("tv.alex.code").values))
        check(root.apps.status === "Not installed: it couldn't be made ready to put in place (No space left on device). Its API Key and sign-in are cleared before it next starts: set them again then.",
              "and says so, never that nothing changed: " + root.apps.status)
        step9e()
      }, true)
    })
  }

  // 9e: the same for a quiet update (the catalog's, asking for nothing new,
  // dropping a secret setting), and for a give back that can't be saved
  function step9e() {
    var q = sourceApp("tv.example.quiet", { name: "Quiet", kind: "app", api: 2, main: "main.py", launch: null, source: "catalog:uber", from: "catalog", catalogName: "Uber TV",
                                            permissions: { net: [], netWrite: {}, server: null, play: false, signIn: "", storage: false },
                                            settings: [{ key: "apiKey", type: "secret", label: "API Key" }], values: { "@secret:apiKey": true } })
    root.apps.installed = [q]
    root.apps.save()
    var before = diskText()
    var mq = { id: q.id, name: "Quiet", version: "2.0.0", kind: "app", api: 2, author: "Alex", description: "", main: "main.py", settings: [], permissions: q.permissions }
    answer("inspect", { ok: true, staging: fake.cacheDir + "/app-staging/app-quiet", tree: "t", manifest: mq, source: "catalog", sourceName: "Uber TV", sha256: "d".repeat(64) })
    answer("install", { ok: false, error: "it couldn't be made ready to put in place (No space left on device), so nothing changed", unchanged: true })
    root.apps.catalog = { name: "Uber TV", updated: 1, fetched: 1, apps: [{ id: q.id, name: "Quiet", version: "2.0.0", kind: "app", permissions: q.permissions }], revoked: [] }
    root.apps.applyCatalog()
    check(root.apps.updating, "a quiet update")
    waitFor(function() { return !root.apps.updating && !root.apps.updateQueue.length }, function() {
      check(root.apps.status === "Couldn't update Quiet: it couldn't be made ready to put in place (No space left on device), so nothing changed", "not updated, and said why: " + root.apps.status)
      check(diskText() === before, "what was withdrawn is given back: apps.json byte for byte as it was: " + JSON.stringify(onDisk(q.id).values))
      check(!root.apps.changing[q.id], "let go")
      // a give back that can't be saved: withdrawn it stays, and that's said, never that nothing changed
      answer("inspect", { ok: true, staging: fake.cacheDir + "/app-staging/app-quiet", tree: "t", manifest: mq, source: "catalog", sourceName: "Uber TV", sha256: "d".repeat(64) })
      answer("install", { ok: false, error: "it couldn't be made ready to put in place (No space left on device), so nothing changed", unchanged: true })
      hold("install.hold", true)   // its install answers when let go
      var k = calls().length
      root.apps.applyCatalog()
      waitFor(function() { return calls().slice(k).some(function(c) { return c[0] === "install" }) }, function() {
        var orig = root.apps.writerKind
        root.apps.writerKind = liar   // (withdrawn on disk already: no save lands from here)
        hold("install.hold", false)
        waitFor(function() { return !root.apps.updating && !root.apps.updateQueue.length }, function() {
          root.apps.writerKind = orig
          check(root.apps.status === "Couldn't update Quiet: it couldn't be made ready to put in place (No space left on device). Its API Key is cleared before it next starts: set it again then.",
                "a give back that can't be saved: said so, never that nothing changed: " + root.apps.status)
          check(JSON.stringify(onDisk(q.id).values) === JSON.stringify({ "@clear": ["apiKey"] }), "and it stays withdrawn: " + JSON.stringify(onDisk(q.id).values))
          root.apps.catalog = null
          step9e2()
        }, "the quiet update")
      }, "its install")
    }, "the quiet update")
  }

  // 9e2: a new copy that couldn't be made or didn't check out (retry) only
  // says to try again, for an update you confirmed and for a quiet one (the
  // helper's words go to the log)
  function step9e2() {
    var why = "it couldn't be made ready to put in place (its files changed while it waited), so nothing changed"
    updateThat({ ok: false, error: why, unchanged: true, retry: true }, function(before) {
      check(root.apps.status === "Couldn't update Code. Try again.", "said to try again: " + root.apps.status)
      check(diskText() === before, "apps.json byte for byte as it was")
      var q = sourceApp("tv.example.quiet", { name: "Quiet", kind: "app", api: 2, main: "main.py", launch: null, source: "catalog:uber", from: "catalog", catalogName: "Uber TV",
                                              permissions: { net: [], netWrite: {}, server: null, play: false, signIn: "", storage: false },
                                              settings: [{ key: "apiKey", type: "secret", label: "API Key" }], values: { "@secret:apiKey": true } })
      root.apps.installed = [q]
      root.apps.save()
      var mq = { id: q.id, name: "Quiet", version: "2.0.0", kind: "app", api: 2, author: "Alex", description: "", main: "main.py", settings: [], permissions: q.permissions }
      answer("inspect", { ok: true, staging: fake.cacheDir + "/app-staging/app-quiet", tree: "t", manifest: mq, source: "catalog", sourceName: "Uber TV", sha256: "d".repeat(64) })
      answer("install", { ok: false, error: why, unchanged: true, retry: true })
      root.apps.catalog = { name: "Uber TV", updated: 1, fetched: 1, apps: [{ id: q.id, name: "Quiet", version: "2.0.0", kind: "app", permissions: q.permissions }], revoked: [] }
      root.apps.applyCatalog()
      waitFor(function() { return !root.apps.updating && !root.apps.updateQueue.length }, function() {
        check(root.apps.status === "Couldn't update Quiet. Try again.", "a quiet update says to try again: " + root.apps.status)
        root.apps.catalog = null
        step9f()
      }, "the quiet update")
    })
  }

  // 9f: a quiet update queued for the catalog's app while a review of the
  // same id from one of your sources was open never acts on the source's
  // app that took its place: nothing looked at, nothing waiting, nothing
  // broken (and nothing owed from before proof was kept)
  function step9f() {
    var s = root.s9
    var x = sourceApp("tv.example.x", { name: "Ex", source: "catalog:uber", from: "catalog", catalogName: "Uber TV", permissions: { web: ["x.example.com"] }, launch: { web: "https://x.example.com/" } })
    root.apps.installed = [x]
    root.apps.save()
    var mx = { id: x.id, name: "Ex", version: "1.0.0", kind: "launcher", api: 1, author: "Alex", description: "", permissions: x.permissions, launch: x.launch, settings: [], home: [] }
    root.apps.review = { staging: fake.cacheDir + "/app-staging/app-x", tree: "x", manifest: mx, sha256: "", from: "source", file: s.name, fingerprint: s.fingerprint,
                         source: s.id, have: root.apps.record(x.id), replaces: "catalog", asks: root.apps.asks(mx.permissions, []), newAsks: [], snapshot: {}, checkedNow: true }
    // the catalog meanwhile: a newer Ex asking for nothing new (it waits: a review is open)
    root.apps.catalog = { name: "Uber TV", updated: 2, fetched: 2, apps: [{ id: x.id, name: "Ex", version: "1.1.0", kind: "launcher", permissions: x.permissions }], revoked: [] }
    root.apps.applyCatalog()
    root.apps.unproven = root.apps.withKey(root.apps.unproven, x.id, root.apps.installOf(x))
    check(root.apps.updateQueue.length === 1 && !root.apps.updating, "queued, waiting for the review")
    var n = calls().length
    answer("install", { ok: true, manifest: mx, files: {}, path: root.tmp + "/x", proof: "source", source: s.id, sourceDir: root.sd, keyFingerprint: "" })
    answer("remove", { ok: true })
    answer("inspect", { ok: true, staging: fake.cacheDir + "/app-staging/app-x2", tree: "t", manifest: Object.assign({}, mx, { version: "1.1.0" }), source: "catalog", sourceName: "Uber TV", sha256: "f".repeat(64) })
    var said = null, queued = null
    root.apps.confirm(function(ok) { said = ok; queued = [root.apps.updateQueue.length, root.apps.unproven[x.id] === undefined] })
    waitFor(function() { return said !== null && !root.apps.updating && !root.apps.updateQueue.length }, function() {
      var after = calls().slice(n).map(function(c) { return c[0] })
      var a = root.apps.record(x.id)
      check(said === true && a.source === s.id && root.apps.status === "Ex is installed.", "the source's Ex took its place: " + root.apps.status)
      check(JSON.stringify(queued) === JSON.stringify([0, true]), "its record replaced, nothing waits for the catalog's: " + JSON.stringify(queued))
      check(after.indexOf("inspect") < 0, "the catalog's update isn't looked at for it: " + JSON.stringify(after))
      check(a.update === null && a.broken === "" && root.apps.unproven[x.id] === undefined, "nothing waiting, nothing broken: " + JSON.stringify([a.update, a.broken]))
      // the same from a file (the old one removed first, then the new installed)
      root.apps.installed = [x]
      root.apps.save()
      var mf = Object.assign({}, mx)
      root.apps.review = { staging: fake.cacheDir + "/app-staging/app-xf", tree: "x", manifest: mf, sha256: "", from: "file", file: "/x.zip", source: root.src,
                           have: root.apps.record(x.id), replaces: "catalog", asks: root.apps.asks(mf.permissions, []), newAsks: [] }
      root.apps.applyCatalog()
      answer("remove", { ok: true })
      answer("install", { ok: true, manifest: mf, files: {}, path: root.tmp + "/x", proof: "none", source: root.src, sourceDir: root.sd })
      var said2 = null, queued2 = null
      root.apps.confirm(function(ok) { said2 = ok; queued2 = root.apps.updateQueue.length })
      waitFor(function() { return said2 !== null && !root.apps.updating && !root.apps.updateQueue.length }, function() {
        check(said2 === true && root.apps.record(x.id).source === root.src && queued2 === 0, "from a file too: nothing waits for the catalog's: " + JSON.stringify([said2, queued2, root.apps.status]))
        check(root.apps.record(x.id).update === null, "nor is written on the file's")
        answer("inspect", null)
        root.apps.catalog = null
        step9g()
      }, "the replace from a file")
    }, "the replace")
  }

  // 9g: what verify queued for the catalog's app (installed before proof
  // was kept) once the catalog comes never acts on another in its place
  // meanwhile: a catalog that can't be read marks only what's still the
  // catalog's, and a quiet update for it is let go, nothing looked at
  function step9g() {
    var s = root.s9
    var y = sourceApp("tv.example.y", { name: "Why", source: "catalog:uber", from: "catalog", catalogName: "Uber TV", permissions: { web: ["y.example.com"] }, launch: { web: "https://y.example.com/" } })
    var ys = Object.assign({}, y, { source: s.id, from: "source", sha256: "b".repeat(64), updated: 6, catalogName: s.name })
    var m = { id: y.id, name: "Why", version: "1.0.0", kind: "launcher", api: 1, author: "Alex", description: "", permissions: y.permissions, launch: y.launch }
    var verified = function(then) {
      root.apps.installed = [y]
      root.apps.save()
      answer("verify", { ok: true, apps: [{ sourceDir: y.sourceDir, id: y.id, version: y.version, problem: "", proof: "none", manifest: m, files: {} }] })
      root.apps.fetching = true   // (a catalog fetch already out: what verify wants waits for it)
      root.apps.verify()
      waitFor(function() { return !!root.apps.unproven[y.id] }, function() {
        root.apps.installed = [ys]   // the source's in its place meanwhile
        var waiting = root.apps.afterFetch
        root.apps.afterFetch = []
        root.apps.fetching = false
        then(waiting)
      }, "verify")
    }
    verified(function(waiting) {
      waiting.forEach(function(f) { f({ ok: false, error: "the network is down" }) })
      check(root.apps.record(y.id).broken === "", "a catalog that can't be read doesn't mark the source's: " + root.apps.record(y.id).broken)
      verified(function(waiting2) {
        var n = calls().length
        answer("inspect", { ok: true, staging: fake.cacheDir + "/app-staging/app-y", tree: "t", manifest: m, source: "catalog", sourceName: "Uber TV", sha256: "f".repeat(64) })
        waiting2.forEach(function(f) { f({ ok: true }) })
        waitFor(function() { return !root.apps.updating && !root.apps.updateQueue.length }, function() {
          var a = root.apps.record(y.id)
          check(calls().slice(n).map(function(c) { return c[0] }).indexOf("inspect") < 0, "nor is its quiet update looked at for it")
          check(a.update === null && a.broken === "" && root.apps.unproven[y.id] === undefined, "nothing waiting, nothing broken: " + JSON.stringify([a.update, a.broken]))
          answer("inspect", null)
          step9h()
        }, "the quiet update for what's there now")
      })
    })
  }

  // 9h: a removal asked for one install refuses another in its place
  // (nothing removed, nothing held); for the one there, it goes
  function step9h() {
    var z = sourceApp("tv.alex.zed", { name: "Zed" })
    root.apps.installed = [z]
    root.apps.save()
    var n = calls().length
    var gone = null
    check(root.apps.remove(z.id, function(ok) { gone = ok }, "catalog:uber|0.9.0|x|1") === false, "refused for another install")
    check(root.apps.record(z.id) !== null && !root.apps.changing[z.id], "nothing touched, nothing held")
    root.apps.installing = true
    check(root.apps.remove(z.id, function(ok) { gone = ok }, root.apps.installOf(z)) === false && root.apps.status === "It's being installed. Try again in a moment.", "nor while something installs")
    root.apps.installing = false
    root.apps.setChanging(z.id, true)
    check(root.apps.remove(z.id, function(ok) { gone = ok }, root.apps.installOf(z)) === false && root.apps.status === "It's being changed. Try again in a moment.", "nor while it's being changed")
    root.apps.setChanging(z.id, false)
    answer("remove", { ok: true })
    root.apps.review = { manifest: { id: "tv.example.other" } }   // (a review: nothing queued runs)
    root.apps.queueUpdates([root.apps.queued(z)])
    var queuedThen = null
    check(root.apps.remove(z.id, function(ok) { gone = ok; queuedThen = root.apps.updateQueue.length }, root.apps.installOf(z)) === true, "asked for the one there")
    waitFor(function() { return gone !== null }, function() {
      root.apps.review = null
      check(gone === true && root.apps.record(z.id) === null, "it's removed")
      check(queuedThen === 0, "and nothing waits for it: " + queuedThen)
      check(calls().slice(n).filter(function(c) { return c[0] === "remove" }).length === 1, "the helper asked once, for it")
      step9i()
    }, "the removal")
  }

  // 9i: a quiet update only for what came from where it came from: an
  // inspect answered from elsewhere (the guide's own for the catalog's) is
  // let go, nothing said of it, and a source's app queued is never looked at
  function step9i() {
    var w = sourceApp("tv.example.w", { name: "Wee", source: "catalog:uber", from: "catalog", catalogName: "Uber TV", permissions: { web: ["w.example.com"] }, launch: { web: "https://w.example.com/" } })
    var mw = { id: w.id, name: "Wee", version: "1.1.0", kind: "launcher", api: 1, author: "Alex", description: "", permissions: w.permissions, launch: w.launch }
    root.apps.installed = [w]
    root.apps.save()
    var n = calls().length
    answer("inspect", { ok: true, staging: fake.cacheDir + "/app-staging/app-w", tree: "t", manifest: mw, source: "bundled", sourceName: "", sha256: "f".repeat(64) })
    root.apps.catalog = { name: "Uber TV", updated: 3, fetched: 3, apps: [{ id: w.id, name: "Wee", version: "1.1.0", kind: "launcher", permissions: w.permissions }], revoked: [] }
    root.apps.applyCatalog()
    waitFor(function() { return !root.apps.updating && !root.apps.updateQueue.length }, function() {
      var after = calls().slice(n).map(function(c) { return c[0] })
      check(after.indexOf("inspect") >= 0 && after.indexOf("install") < 0, "an inspect from elsewhere goes no further: " + JSON.stringify(after))
      check(root.apps.record(w.id).update === null && root.apps.record(w.id).broken === "", "nothing waits for it from there")
      root.apps.catalog = null
      // (what's looked at is counted by inspect calls: a discard let go just
      // before, noted when its process starts, isn't one)
      var inspects = function() { return calls().filter(function(c) { return c[0] === "inspect" }).length }
      var m = inspects()
      var d = sourceApp("tv.alex.direct", { name: "Direct" })
      root.apps.installed = [d]
      root.apps.queueUpdates([root.apps.queued(d)])
      check(!root.apps.updating && !root.apps.updateQueue.length, "a source's app queued is let go, nothing started for it")
      // queued for one install of the catalog's: not done to another of it
      // put in place since (the next look queues that, if it needs it)
      var c1 = sourceApp("tv.example.c", { name: "Cee", source: "catalog:uber", from: "catalog", catalogName: "Uber TV", permissions: { web: ["c.example.com"] }, launch: { web: "https://c.example.com/" } })
      root.apps.installed = [c1]
      root.apps.review = { manifest: { id: "tv.example.other" } }   // (a review: nothing queued runs)
      root.apps.queueUpdates([root.apps.queued(c1)])
      root.apps.installed = [Object.assign({}, c1, { version: "1.1.0", updated: 11 })]
      root.apps.review = null
      root.apps.nextUpdate()
      check(!root.apps.updating && !root.apps.updateQueue.length, "nor another install of the catalog's than the one it was queued for")
      // a mark from before proof was kept, for an install that's gone, doesn't
      // count for the one there now
      var e1 = sourceApp("tv.example.e", { name: "Eee", source: "catalog:uber", from: "catalog", catalogName: "Uber TV", permissions: { web: ["e.example.com"] }, launch: { web: "https://e.example.com/" } })
      root.apps.installed = [e1]
      root.apps.unproven = root.apps.withKey(root.apps.unproven, e1.id, "catalog:uber|0.9.0|x|1")
      answer("inspect", { ok: true, staging: fake.cacheDir + "/app-staging/app-e", tree: "t", source: "catalog", sourceName: "Uber TV", sha256: "f".repeat(64),
                          manifest: { id: e1.id, name: "Eee", version: "1.1.0", kind: "launcher", api: 1, author: "Alex", description: "", permissions: { web: ["e.example.com", "more.example.com"] }, launch: e1.launch } })
      root.apps.queueUpdates([root.apps.queued(e1)])
      waitFor(function() { return !root.apps.updating && !root.apps.updateQueue.length }, function() {
        var e = root.apps.record(e1.id)
        check(e.update && e.update.version === "1.1.0" && e.broken === "", "an update asking more waits, and isn't taken for one owed a check: " + JSON.stringify([e.update, e.broken]))
        check(inspects() === m + 1, "of the source's app, the other install and this one, only this one was looked at: " + (inspects() - m))
        step9j()
      }, "the update asking more")
    }, "the inspect from elsewhere")
  }

  // 9j: an answer for an app that became another install while it was held
  // (only a test can do that: nothing else changes a held app) touches
  // nothing of the other: a quiet update's inspect, an update's install (and
  // what it withdrew), a quiet update that fails, a removal
  function step9j() {
    var x = sourceApp("tv.example.x", { name: "Ex", source: "catalog:uber", from: "catalog", catalogName: "Uber TV", permissions: { web: ["x.example.com"] }, launch: { web: "https://x.example.com/" } })
    var x2 = Object.assign({}, x, { version: "1.0.1", sha256: "9".repeat(64), updated: 7 })
    var mx = { id: x.id, name: "Ex", version: "1.1.0", kind: "launcher", api: 1, author: "Alex", description: "", permissions: x.permissions, launch: x.launch }
    root.apps.installed = [x]
    root.apps.save()
    var n = calls().length
    answer("inspect", { ok: true, staging: fake.cacheDir + "/app-staging/app-x3", tree: "t", manifest: mx, source: "catalog", sourceName: "Uber TV", sha256: "f".repeat(64) })
    answer("install", { ok: false, error: "it couldn't be made ready to put in place (No space left on device), so nothing changed", unchanged: true })
    root.apps.catalog = { name: "Uber TV", updated: 4, fetched: 4, apps: [{ id: x.id, name: "Ex", version: "1.1.0", kind: "launcher", permissions: x.permissions }], revoked: [] }
    root.apps.applyCatalog()   // its inspect out, Ex held
    root.apps.installed = [x2]
    waitFor(function() { return !root.apps.updating && !root.apps.updateQueue.length }, function() {
      check(calls().slice(n).map(function(c) { return c[0] }).indexOf("install") < 0 && JSON.stringify(root.apps.record(x.id)) === JSON.stringify(x2), "a quiet update's inspect goes no further for the other")
      answer("install", null)
      root.apps.catalog = null
      root.apps.installed = [codeV1()]
      root.apps.save()
      answer("install", { ok: false, error: "its source has a newer list since you were shown it: look again", unchanged: true })
      root.apps.review = updateReview()
      var said = null
      root.apps.confirm(function(ok) { said = ok })
      var other = Object.assign({}, codeV1(), { version: "1.0.1", updated: 8, values: { "@secret:apiKey": true, theme: "blue" } })
      root.apps.installed = [other]
      waitFor(function() { return said !== null }, function() {
        check(JSON.stringify(root.apps.record("tv.alex.code").values) === JSON.stringify(other.values), "what an update withdrew isn't given to the other: " + JSON.stringify(root.apps.record("tv.alex.code").values))
        check(root.apps.status === "Not installed: its source has a newer list since you were shown it: look again", "nor said of it: " + root.apps.status)
        // a quiet update from before proof was kept, failing once the other's in its place
        var y = sourceApp("tv.example.y", { name: "Why", source: "catalog:uber", from: "catalog", catalogName: "Uber TV", permissions: { web: ["y.example.com"] }, launch: { web: "https://y.example.com/" } })
        var y2 = Object.assign({}, y, { version: "1.0.1", updated: 9 })
        root.apps.installed = [y]
        root.apps.unproven = root.apps.withKey(root.apps.unproven, y.id, root.apps.installOf(y))
        var k = calls().length
        answer("inspect", { ok: true, staging: fake.cacheDir + "/app-staging/app-y2", tree: "t", manifest: Object.assign({}, mx, { id: y.id, name: "Why", version: "1.0.0", permissions: y.permissions, launch: y.launch }), source: "catalog", sourceName: "Uber TV", sha256: "f".repeat(64) })
        var hold = writeFile.createObject(root, { path: root.tmp + "/answers/install.hold" })
        hold.setText("1")   // its install answers when let go
        answer("install", { ok: false, error: "the disk is full" })
        root.apps.queueUpdates([root.apps.queued(y)])
        waitFor(function() { return calls().slice(k).some(function(c) { return c[0] === "install" }) }, function() {
          root.apps.installed = [y2]
          hold.setText("")
          hold.destroy()
          waitFor(function() { return !root.apps.updating && !root.apps.updateQueue.length }, function() {
            check(root.apps.record(y.id).broken === "" && root.apps.unproven[y.id] === undefined, "a failed quiet update marks nothing of the other: " + root.apps.record(y.id).broken)
            var z = sourceApp("tv.alex.zed", { name: "Zed" })
            var z2 = Object.assign({}, z, { version: "1.0.1", updated: 10 })
            root.apps.installed = [z]
            root.apps.save()
            answer("remove", { ok: true })
            var gone = null
            root.apps.remove(z.id, function(ok) { gone = ok })
            root.apps.installed = [z2]
            waitFor(function() { return gone !== null }, function() {
              check(root.apps.record(z.id) !== null && root.apps.record(z.id).version === "1.0.1", "a removal's answer leaves the other's record")
              step9k()
            }, "the removal")
          }, "the failed quiet update")
        }, "its install")
      }, "the update")
    }, "the quiet update's inspect")
  }

  // 9k: a check of your apps answered after one's source was removed
  // doesn't undo that (its answer is older): it stays off
  function step9k() {
    var s = root.s9
    var v = sourceApp("tv.alex.vee", { name: "Vee", permissions: { web: ["vee.example.com"] }, launch: { web: "https://vee.example.com/" } })
    var u = sourceApp("tv.example.you", { name: "You", source: root.src, from: "file", catalogName: "", permissions: { web: ["you.example.com"] }, launch: { web: "https://you.example.com/" } })
    var shown = function(a) { return { id: a.id, name: a.name, version: a.version, kind: "launcher", api: 1, author: a.author, description: "", color: "", permissions: a.permissions, launch: a.launch } }
    root.apps.installed = [v, u]
    root.apps.save()
    root.apps.setChecked(u.id, false)
    var hold = writeFile.createObject(root, { path: root.tmp + "/answers/verify.hold" })
    hold.setText("1")   // its answer comes when let go
    answer("verify", { ok: true, apps: [{ sourceDir: v.sourceDir, id: v.id, version: v.version, problem: "", proof: "source", keyFingerprint: "", manifest: shown(v), files: {} },
                                        { sourceDir: u.sourceDir, id: u.id, version: u.version, problem: "", proof: "none", manifest: shown(u), files: {} }] })
    var k = calls().length
    root.apps.verify()
    waitFor(function() { return calls().slice(k).some(function(c) { return c[0] === "verify" }) }, function() {
      root.apps.sourceGone(s.id)   // removed while it checks
      hold.setText("")
      hold.destroy()
      waitFor(function() { return !!root.apps.checkedIds[u.id] }, function() {
        var a = root.apps.record(v.id)
        check(a.broken === "Its source was removed" && a.enabled === false && root.apps.setEnabled(v.id, true) !== "ok", "still off: " + JSON.stringify([a.broken, a.enabled]))
        step9l()
      }, "the check")
    }, "the check under way")
  }

  // 9l: a source removed (its apps stay, off), then added again with the
  // same key (so the same id), through Sources.qml itself (its helper stood
  // in by runner): the apps kept from it are checked again, as the guide's
  // next start checks them, and only they are. Nothing says its source was
  // removed any more, none opens till that check says it traces back to it,
  // and then it's off, yours to turn on. One its list now pulls stays
  // refused; a removal while that check runs keeps them off; a check begun
  // before it came back doesn't mark them again (nor does one begun after
  // its removal, when nothing was marked); a check that can't run says so;
  // and one whose add didn't answer is checked again once a read lists it,
  // marked or not (marked from before this start too, when nothing else
  // says it was removed). A read of a source whose apps are fine checks
  // nothing again.
  property var srcCalls: []
  property var src9: null
  property var clock9: null
  property var you9: null
  function srcAnswer(cmd, res) {
    var c = root.srcCalls.filter(function(x) { return x.args[0] === cmd && !x.answered })[0]
    if (!c) return false
    c.answered = true
    c.done(res)
    return true
  }
  // a read of your sources answered: every one out (made here, it reads
  // twice as it starts, and one answered after a change it didn't see reads
  // again)
  function readAs(sources) {
    var n = 0
    while (n < 10 && srcAnswer("source-list", { ok: true, sources: sources })) n++
    return n > 0
  }
  function hold(name, on) {
    var w = writeFile.createObject(root, { path: root.tmp + "/answers/" + name })
    w.setText(on ? "1" : "\n")   // (blank lets it go: a new FileView doesn't write "")
    w.destroy()
  }
  function verifyCalls() { return calls().filter(function(x) { return x[0] === "verify" }).length }
  function shown9(a) { return { id: a.id, name: a.name, version: a.version, kind: "launcher", api: 1, author: a.author, description: "", color: "", permissions: a.permissions, launch: a.launch } }
  // verify's answer: Clock with problem and proof (You's files gone), held on its own if held names a file
  function says9(problem, proof, held) {
    var c = root.clock9, y = root.you9
    var r = { ok: true, apps: [{ sourceDir: c.sourceDir, id: c.id, version: c.version, problem: problem, proof: proof, keyFingerprint: "", manifest: root.shown9(c), files: {} },
                               { sourceDir: y.sourceDir, id: y.id, version: y.version, problem: "its files are gone", proof: "none", manifest: root.shown9(y), files: {} }] }
    if (held) r._hold = held
    return r
  }
  function listed9(life) { return Object.assign({}, root.s9, { life: life, list: Object.assign({}, root.s9.list, { fetched: Math.floor(Date.now() / 1000) }) }) }
  function removeIt() { root.src9.current = root.s9.id; root.src9.remove(false); return srcAnswer("source-remove", { ok: true }) }
  function addAgain(life, list, res) {
    var s = root.s9
    root.src9.preview = { url: "https://src.invalid/tv/", name: s.name, fingerprint: s.fingerprint, apps: [], skipped: 0, staged: "e".repeat(64) }
    root.src9.pin()
    return srcAnswer("source-add", res || { ok: true, source: { id: s.id, url: "https://src.invalid/tv/", name: s.name, fingerprint: s.fingerprint, keyGen: 0, added: 2, seen: 1000,
                                                              keyChanged: "", life: life },
                                            list: list || root.listed9(life).list })
  }
  function step9l() {
    root.clock9 = sourceApp("tv.alex.clock", { name: "Clock" })
    root.you9 = sourceApp("tv.example.you", { name: "You", source: root.src, from: "file", catalogName: "", permissions: { web: ["you.example.com"] }, launch: { web: "https://you.example.com/" } })
    var clock = root.clock9, you = root.you9
    root.apps.installed = [clock, you]
    root.apps.save()
    root.apps.setChecked(clock.id, true)
    root.apps.setChecked(you.id, false)
    root.apps.sourcesGone = ({})   // (9a and 9k removed it behind Sources' back: here it's as at a start)
    fake.apps = root.apps
    var c = Qt.createComponent("file://" + Quickshell.env("OM_PG_ROOT") + "/Sources.qml")
    if (c.status !== Component.Ready) { check(false, "Sources loads: " + c.errorString()); step9lDone(); return }
    root.src9 = c.createObject(root, { guide: fake, runner: function(args, done) { root.srcCalls = root.srcCalls.concat([{ args: args, done: done }]) } })
    fake.sources = root.src9
    check(readAs([root.listed9(root.s9.life)]), "your sources read as it starts")
    removeIt()
    check(root.apps.record(clock.id).broken === "Its source was removed", "removed: its app is off: " + root.apps.record(clock.id).broken)
    hold("back.hold", true)
    answer("verify", says9("", "source", "back.hold"))
    var v = verifyCalls()
    addAgain("d".repeat(32))
    var a = root.apps.record(clock.id)
    check(a.broken === "", "added again: nothing says its source was removed: " + a.broken)
    waitFor(function() { return verifyCalls() > v }, function() {
      check(root.apps.setEnabled(clock.id, true) === "ok" && root.apps.cannotOpen(clock.id) === "it's still being checked",
            "and it doesn't open till it's checked again: " + root.apps.cannotOpen(clock.id))
      root.apps.setEnabled(clock.id, false)
      hold("back.hold", false)
      waitFor(function() { return !!root.apps.checkedIds[clock.id] }, function() {
        var b = root.apps.record(clock.id)
        check(b.broken === "" && b.enabled === false && root.apps.cannotOpen(clock.id) === "it's off", "checked: it traces back to its source, off till you turn it on: " + JSON.stringify([b.broken, b.enabled]))
        check(root.apps.setEnabled(clock.id, true) === "ok" && root.apps.cannotOpen(clock.id) === "", "then it can be turned on, and opens: " + root.apps.cannotOpen(clock.id))
        check(root.apps.record(you.id).broken === "" && !root.apps.checkedIds[you.id], "only its source's apps are checked again: " + root.apps.record(you.id).broken)
        check(verifyCalls() === v + 1, "checked once: " + (verifyCalls() - v))
        check(onDisk(clock.id).broken === "", "saved so")
        root.src9.read()
        check(readAs([Object.assign(root.listed9("d".repeat(32)), { seen: 1234 })]) && root.src9.find(root.s9.id).seen === 1234, "read")
        check(!!root.apps.checkedIds[clock.id] && root.apps.cannotOpen(clock.id) === "", "a read of it now checks nothing again")
        step9l2()
      }, "the check")
    }, "a check of its apps")
  }
  function step9l2() {
    var clock = root.clock9
    removeIt()
    answer("verify", says9("", "source"))
    var pulling = Object.assign({}, root.listed9("e".repeat(32)).list, { revoked: [{ id: clock.id, version: "1.0.0", reason: "A bad build: don't run it." }] })
    addAgain("e".repeat(32), pulling)
    waitFor(function() { return !!root.apps.checkedIds[clock.id] }, function() {
      var a = root.apps.record(clock.id)
      check(a.broken === "" && a.revoked === "A bad build: don't run it." && root.apps.setEnabled(clock.id, true) !== "ok" && root.apps.cannotOpen(clock.id) !== "",
            "added again with a list that pulls it: still refused: " + JSON.stringify([a.broken, a.revoked]))
      step9l3()
    }, "the check")
  }
  function step9l3() {
    var clock = root.clock9
    removeIt()
    hold("again.hold", true)
    answer("verify", says9("", "source", "again.hold"))
    var v = verifyCalls()
    addAgain("f".repeat(32))
    waitFor(function() { return verifyCalls() > v }, function() {
      removeIt()   // removed again while it's checked
      var n = root.verified
      hold("again.hold", false)
      waitFor(function() { return root.verified > n }, function() {
        var a = root.apps.record(clock.id)
        check(a.broken === "Its source was removed" && a.enabled === false && root.apps.setEnabled(clock.id, true) !== "ok", "removed again while it was checked: still off: " + JSON.stringify([a.broken, a.enabled]))
        step9l4()
      }, "the check")
    }, "a check of its apps")
  }
  function step9l4() {
    var clock = root.clock9
    hold("before.hold", true)
    answer("verify", says9("its source was removed", "", "before.hold"))
    var v = verifyCalls()
    root.apps.verify()   // all your apps (as when apps are turned on), begun while it's removed
    waitFor(function() { return verifyCalls() > v }, function() {
      answer("verify", says9("", "source"))
      addAgain("1".repeat(32))
      waitFor(function() { return !!root.apps.checkedIds[clock.id] }, function() {
        var n = root.verified
        hold("before.hold", false)
        waitFor(function() { return root.verified > n }, function() {
          var a = root.apps.record(clock.id)
          check(a.broken === "" && root.apps.setEnabled(clock.id, true) === "ok" && root.apps.cannotOpen(clock.id) === "",
                "a check begun before it came back doesn't mark it again: " + JSON.stringify([a.broken, root.apps.cannotOpen(clock.id)]))
          step9l5()
        }, "the older check")
      }, "the check")
    }, "the check of all your apps")
  }
  // (nothing marked: it was off for another reason when its source went)
  function step9l5() {
    var clock = root.clock9
    root.apps.withRecord(clock.id, function(x) { x.broken = "Its files are gone" })
    removeIt()
    check(root.apps.record(clock.id).broken === "Its files are gone", "removed while off for another reason: that's kept")
    hold("after.hold", true)
    answer("verify", says9("its source was removed", "", "after.hold"))
    var v = verifyCalls()
    root.apps.verify()   // begun after its removal
    waitFor(function() { return verifyCalls() > v }, function() {
      answer("verify", says9("", "source"))
      addAgain("2".repeat(32))
      waitFor(function() { return !!root.apps.checkedIds[clock.id] }, function() {
        var n = root.verified
        hold("after.hold", false)
        waitFor(function() { return root.verified > n }, function() {
          var a = root.apps.record(clock.id)
          check(a.broken === "", "a check begun after its removal doesn't mark it once it's back: " + a.broken)
          step9l6()
        }, "the older check")
      }, "the check")
    }, "the check of all your apps")
  }
  function step9l6() {
    var clock = root.clock9
    removeIt()
    root.apps.status = ""
    answer("verify", { ok: false, error: "the disk can't be read" })
    addAgain("3".repeat(32))
    waitFor(function() { return root.apps.status !== "" }, function() {
      check(root.apps.status === "Couldn't check the apps from Alex's TV apps (the disk can't be read), so they won't open until they can be.", "a check that can't run says so: " + root.apps.status)
      var a = root.apps.record(clock.id)
      check(a.broken === "" && root.apps.setEnabled(clock.id, true) === "ok" && root.apps.cannotOpen(clock.id) === "it's still being checked",
            "with nothing said to be removed, and it doesn't open: " + JSON.stringify([a.broken, root.apps.cannotOpen(clock.id)]))
      step9l7()
    }, "the check that can't run")
  }
  function step9l7() {
    var clock = root.clock9
    removeIt()
    answer("verify", says9("", "source"))
    var v = verifyCalls()
    addAgain("4".repeat(32), null, { ok: false, error: "the app helper failed" })   // (added, but its answer was lost)
    check(root.apps.record(clock.id).broken === "Its source was removed" && verifyCalls() === v, "an add that didn't answer changes nothing")
    root.src9.read()
    check(readAs([root.listed9("4".repeat(32))]) && !!root.src9.find(root.s9.id), "read")
    waitFor(function() { return !!root.apps.checkedIds[clock.id] }, function() {
      check(root.apps.record(clock.id).broken === "" && verifyCalls() === v + 1, "once a read lists it again, its apps are checked again: " + root.apps.record(clock.id).broken)
      step9l8()
    }, "the check")
  }
  // (back by a read, nothing marked: off for another reason when its source went)
  function step9l8() {
    var clock = root.clock9
    root.apps.withRecord(clock.id, function(x) { x.broken = "Its files are gone" })
    removeIt()
    hold("lost.hold", true)
    answer("verify", says9("its source was removed", "", "lost.hold"))
    var v = verifyCalls()
    root.apps.verify()   // begun after its removal
    waitFor(function() { return verifyCalls() > v }, function() {
      answer("verify", says9("", "source"))
      addAgain("5".repeat(32), null, { ok: false, error: "the app helper failed" })   // (added, but its answer was lost)
      root.src9.read()
      check(readAs([root.listed9("5".repeat(32))]) && !root.apps.checkedIds[clock.id], "a read lists it again: its apps are checked again, though none said its source was removed")
      waitFor(function() { return !!root.apps.checkedIds[clock.id] }, function() {
        var n = root.verified
        hold("lost.hold", false)
        waitFor(function() { return root.verified > n }, function() {
          check(root.apps.record(clock.id).broken === "", "and a check begun after its removal doesn't mark it: " + root.apps.record(clock.id).broken)
          step9l9()
        }, "the older check")
      }, "the check")
    }, "the check of all your apps")
  }
  // (back by a read, marked from before this start: removed in another
  // session, so only its apps say so, then added again, its answer lost)
  function step9l9() {
    var clock = root.clock9
    removeIt()
    root.apps.sourcesGone = ({})   // (as at a start)
    answer("verify", says9("", "source"))
    var v = verifyCalls()
    addAgain("6".repeat(32), null, { ok: false, error: "the app helper failed" })   // (added, but its answer was lost)
    root.src9.read()
    check(readAs([root.listed9("6".repeat(32))]) && !root.apps.checkedIds[clock.id], "a read lists it again: its apps are checked again, though only they say its source was removed")
    waitFor(function() { return !!root.apps.checkedIds[clock.id] }, function() {
      check(root.apps.record(clock.id).broken === "" && verifyCalls() === v + 1, "and it traces back: " + root.apps.record(clock.id).broken)
      step9lDone()
    }, "the check")
  }
  function step9lDone() {
    if (root.src9) root.src9.destroy()
    root.src9 = null
    fake.sources = null
    fake.apps = null
    step9m()
  }

  // 9m: a change of source that isn't to one of yours (a file over the
  // catalog's, say): the one it takes the place of is removed first, and
  // gone from apps.json at once. An install that fails then, though what
  // it says is that it changed nothing, says the old one was removed:
  // never that nothing changed. If apps.json couldn't be saved then, it's
  // saved at the install's end, and if it can't be then either, that's said
  function step9m() {
    var p = sourceApp("tv.example.pa", { name: "Pa", source: "catalog:uber", from: "catalog", catalogName: "Uber TV", permissions: { web: ["pa.example.com"] }, launch: { web: "https://pa.example.com/" } })
    var mp = { id: p.id, name: "Pa", version: "1.0.0", kind: "launcher", api: 1, author: "Alex", description: "", permissions: p.permissions, launch: p.launch, settings: [], home: [] }
    var removedFirst = "Not installed: it couldn't be made ready to put in place (No space left on device). The Pa it was to take the place of was removed first."
    // failFirst: apps.json can't be saved as the old one goes; failLast: nor at the install's end
    var replaced = function(then, failFirst, failLast) {
      root.apps.installed = [p]
      root.apps.save()
      root.apps.review = { staging: fake.cacheDir + "/app-staging/app-pa", tree: "x", manifest: mp, sha256: "", from: "file", file: "/pa.zip", source: root.src,
                           have: root.apps.record(p.id), replaces: "catalog", asks: root.apps.asks(mp.permissions, []), newAsks: [] }
      answer("remove", { ok: true })
      answer("install", { ok: false, error: "it couldn't be made ready to put in place (No space left on device), so nothing changed", unchanged: true })
      hold("install.hold", true)   // its install answers when let go
      var n = calls().length
      var orig = root.apps.writerKind
      if (failFirst) root.apps.writerKind = liar
      var said = null
      root.apps.confirm(function(ok) { said = ok })
      waitFor(function() { return calls().slice(n).some(function(c) { return c[0] === "install" }) }, function() {
        var listed = onDisk(p.id)
        root.apps.writerKind = failLast ? liar : orig
        hold("install.hold", false)
        waitFor(function() { return said !== null }, function() {
          root.apps.writerKind = orig
          var after = calls().slice(n).map(function(c) { return c[0] }).filter(function(c) { return c === "remove" || c === "install" })
          check(JSON.stringify(after) === JSON.stringify(["remove", "install"]), "the old one removed first, then the install: " + JSON.stringify(after))
          check(said === false && root.apps.record(p.id) === null && !root.apps.changing[p.id] && !root.apps.installing && root.apps.review === null, "not installed, the old one gone, and let go")
          then(listed)
        }, "the change of source")
      }, "its install")
    }
    replaced(function(listed) {
      check(listed === null, "gone from apps.json before the install: " + JSON.stringify(listed))
      check(root.apps.status === removedFirst, "said: the old one was removed first, not that nothing changed: " + root.apps.status)
      check(onDisk(p.id) === null, "and so it stays: " + JSON.stringify(onDisk(p.id)))
      replaced(function(listed2) {
        check(listed2 !== null && onDisk(p.id) === null, "apps.json not saved as it went: saved at the install's end: " + JSON.stringify(onDisk(p.id)))
        check(root.apps.status === removedFirst, "said as before: " + root.apps.status)
        replaced(function(listed3) {
          check(listed3 !== null && onDisk(p.id) !== null, "nor then: still listed there")
          check(root.apps.status === removedFirst + " Your list of apps couldn't be saved (what's on disk isn't what was written).", "and that's said: " + root.apps.status)
          root.apps.save()
          step9n()
        }, true, true)
      }, true, false)
    })
  }
  // 9n: 9c through the real helper, only source-current stood in (a newer
  // list lands just after it): install's own check, under your sources'
  // lock, refuses the update, saying nothing changed, so the kept version's
  // secret settings and sign-in are exactly as they were: its record,
  // apps.json and its secrets file byte for byte
  function step9n() {
    var secretsFile = fake.configDir + "/app-secrets/" + root.sd + "/tv.alex.code.json"
    root.apps.installed = [codeV1()]
    root.apps.save()
    var before = diskText()
    var kept = rd(secretsFile)
    check(kept.indexOf("k3") >= 0 && kept.indexOf("t3") >= 0, "its API Key and sign-in are there: " + kept)
    answer("source-current", { ok: true })
    answer("install", null)   // (none: the real helper answers)
    var n = calls().length
    root.apps.review = Object.assign(updateReview(), { staging: fake.cacheDir + "/app-staging/app-stale3", checkedNow: false })
    var said = null
    root.apps.confirm(function(ok) { said = ok })
    waitFor(function() { return said !== null }, function() {
      var made = calls().slice(n).map(function(c) { return c[0] }).filter(function(c) { return c === "source-current" || c === "install" })
      check(JSON.stringify(made) === JSON.stringify(["source-current", "install"]), "checked, then install refused it: " + JSON.stringify(made))
      check(said === false && root.apps.status === "Not installed: its source has a newer list since you were shown it: look again", "by its own check: " + root.apps.status)
      check(JSON.stringify(root.apps.record("tv.alex.code").values) === JSON.stringify(codeV1().values), "what was withdrawn is given back: " + JSON.stringify(root.apps.record("tv.alex.code").values))
      check(diskText() === before, "apps.json byte for byte as it was: " + JSON.stringify(onDisk("tv.alex.code").values))
      check(rd(secretsFile) === kept, "its secrets file byte for byte as it was: " + rd(secretsFile))
      check(!root.apps.changing["tv.alex.code"] && !root.apps.installing && root.apps.review === null, "and let go")
      step9o()
    }, "the refused update", 1500)
  }
  // 9o: Get apps' rows are each about the app installed from their own
  // origin (rowRecord); and a source's app taking the place of the
  // catalog's (replaceFromSource) whose record can't be saved: the old
  // one's record never leaves the list, nothing of it is removed, and
  // that's said (a save that works later keeps it); saved, the old one
  // goes after
  function step9o() {
    var s = root.s9
    var theirs = sourceApp("tv.uber.scores", { name: "Scores", version: "2.0.0" })
    root.apps.installed = [theirs]
    check(root.apps.rowRecord({ type: "app", id: theirs.id, entry: { bundled: true, version: "1.2.0" } }) === null, "the guide's own Scores row isn't about a source's Scores")
    check(root.apps.rowRecord({ type: "app", id: theirs.id, entry: { version: "1.2.0" } }) === null, "nor the catalog's")
    check(root.apps.rowRecord({ type: "sourceApp", id: theirs.id, source: s.id, entry: {} }) === root.apps.record(theirs.id), "its own source's row is")
    check(root.apps.rowRecord({ type: "sourceApp", id: theirs.id, source: "source:ffffffffffffffff", entry: {} }) === null, "another source's isn't")
    root.apps.installed = [Object.assign({}, theirs, { source: "bundled", from: "bundled" })]
    check(root.apps.rowRecord({ type: "app", id: theirs.id, entry: { bundled: true } }) === root.apps.record(theirs.id), "the guide's own row is about the guide's own")
    check(root.apps.rowRecord({ type: "app", id: theirs.id, entry: {} }) === null, "the catalog's isn't")
    root.apps.installed = [Object.assign({}, theirs, { source: "catalog:uber", from: "catalog" })]
    check(root.apps.rowRecord({ type: "app", id: theirs.id, entry: {} }) === root.apps.record(theirs.id), "the catalog's row is about the catalog's")
    check(root.apps.rowRecord(undefined) === null && root.apps.rowRecord({ type: "retry" }) === null, "no row, or one that isn't an app's: none")
    var p = sourceApp("tv.example.pb", { name: "Pb", source: "catalog:uber", from: "catalog", catalogName: "Uber TV", permissions: { web: ["pb.example.com"] }, launch: { web: "https://pb.example.com/" } })
    var mp = { id: p.id, name: "Pb", version: "2.0.0", kind: "launcher", api: 1, author: "Alex", description: "", permissions: p.permissions, launch: p.launch, settings: [], home: [] }
    var replaced = function(failing, then) {
      root.apps.installed = [p]
      root.apps.setChecked(p.id, false)   // (keep marks the new one checked)
      root.apps.save()
      var before = JSON.stringify(root.apps.installed)
      answer("install", { ok: true, manifest: mp, path: root.tmp + "/pb", sourceDir: "00112233445566aa", files: {}, keyFingerprint: s.fingerprint })
      var r = { staging: fake.cacheDir + "/app-staging/app-pb", tree: "x", manifest: mp, sha256: "c".repeat(64), from: "source", file: s.name, fingerprint: s.fingerprint,
                source: s.id, have: root.apps.record(p.id), replaces: "catalog", asks: root.apps.asks(mp.permissions, []), newAsks: [], snapshot: {} }
      root.apps.review = r
      root.apps.installing = true
      root.apps.setChanging(p.id, true)
      var n = calls().length
      var orig = root.apps.writerKind
      if (failing) root.apps.writerKind = liar
      var seen = []   // its record each time the list changed
      var look = function() { var a = root.apps.record(p.id); seen.push(a ? a.source : "none") }
      root.apps.installedChanged.connect(look)
      var said = null
      root.apps.replaceFromSource(r, function(ok) { said = ok })
      waitFor(function() { return said !== null }, function() {
        root.apps.writerKind = orig
        root.apps.installedChanged.disconnect(look)
        check(!root.apps.changing[p.id] && !root.apps.installing && root.apps.review === null, "let go")
        then(said, before, calls().slice(n), seen)
      }, "the replace", 1500)
    }
    replaced(true, function(said, before, made, seen) {
      check(said === false, "not installed")
      check(seen.every(function(x) { return x === "catalog:uber" }), "the old one's record never left the list meanwhile: " + JSON.stringify(seen))
      check(root.apps.status === "Not installed: your list of apps couldn't be saved (what's on disk isn't what was written). The one you have is as it was.", "and said so: " + root.apps.status)
      check(JSON.stringify(root.apps.installed) === before, "the old one's record back in the list: " + JSON.stringify(root.apps.installed.map(function(a) { return [a.id, a.source] })))
      check(!root.apps.checkedIds[p.id], "nor was the new one marked checked")
      check(!made.some(function(c) { return c[0] === "remove" }), "nothing of it removed: " + JSON.stringify(made.map(function(c) { return c[0] })))
      root.apps.save()   // a save that works, later
      check(onDisk(p.id) && onDisk(p.id).source === "catalog:uber", "keeps it: " + JSON.stringify(onDisk(p.id)))
      replaced(false, function(said2, before2, made2, seen2) {
        check(JSON.stringify(seen2) === JSON.stringify(["none", s.id]), "saved: the old one gone from the list, as any removal, then the new one in: " + JSON.stringify(seen2))
        check(said2 === true && root.apps.status === "Pb is installed.", "saved: installed: " + root.apps.status)
        check(onDisk(p.id) && onDisk(p.id).source === s.id && root.apps.record(p.id).source === s.id, "the new one's record on disk: " + JSON.stringify(onDisk(p.id)))
        check(made2.some(function(c) { return c[0] === "remove" && c[1] === p.id && c[2] === "catalog:uber" }), "then the old one's files and data removed: " + JSON.stringify(made2.map(function(c) { return c.slice(0, 3) })))
        step9p()
      })
    })
  }
  // 9p: Cancel while a source's app gets ready: its prepare stops at once
  // (its process killed, nothing more fetched for it), and an update
  // queued meanwhile goes on; turning Unknown sources or apps off does the
  // same, and its review goes too
  Process { id: pgrep; property int code: -1; onExited: function(c) { pgrep.code = c } }
  function preparesGone(then, label) {
    var tries = 0
    var look = function() {
      pgrep.code = -1
      pgrep.command = ["/usr/bin/pgrep", "-f", "--", Quickshell.env("STUB_PLUGIN") + "/bin/om-pg-apps prepare"]
      pgrep.running = true
      waitFor(function() { return pgrep.code >= 0 }, function() {
        if (pgrep.code === 1) { check(true, label); then() }
        else if (++tries > 250) { check(false, label + ": its prepare is still running"); then() }
        else look()
      }, "pgrep", 500)
    }
    look()
  }
  function step9p() {
    var s = root.s9
    var pc = sourceApp("tv.example.pc", { name: "Pc", source: "catalog:uber", from: "catalog", catalogName: "Uber TV", permissions: { web: ["pc.example.com"] }, launch: { web: "https://pc.example.com/" } })
    root.apps.installed = [pc]
    root.apps.save()
    hold("prepare.hold", true)   // each prepare waits (until it's killed)
    var preparing = function(then) {
      answer("prepare", { ok: false, error: "it's never answered" })
      var n = calls().length
      check(root.apps.reviewSource(s.list.apps[0], s), "a source's app in review")
      root.apps.confirm(function() {})
      check(root.apps.preparing, "getting it ready")
      waitFor(function() { return calls().slice(n).some(function(c) { return c[0] === "prepare" }) }, then, "its prepare", 1500)
    }
    preparing(function() {
      root.apps.updateQueue = [{ id: pc.id, install: root.apps.installOf(pc) }]
      root.apps.nextUpdate()
      check(!root.apps.updating, "a quiet update waits for the review")
      answer("inspect", { ok: false, error: "the catalog can't be reached" })
      var n = calls().length
      check(root.apps.cancel(), "Cancel")
      check(!root.apps.preparing && root.apps.prepareRun === null && root.apps.review === null, "stops it at once")
      waitFor(function() { return calls().slice(n).some(function(c) { return c[0] === "inspect" }) && !root.apps.updating && !root.apps.updateQueue.length }, function() {
        check(root.apps.status === "Couldn't update Pc: the catalog can't be reached", "the update queued meanwhile went on: " + root.apps.status)
        preparesGone(function() {
          preparing(function() {
            root.apps.setUnknownSources(false)
            check(!root.apps.preparing && root.apps.prepareRun === null && root.apps.review === null, "Unknown sources off: stopped, its review gone")
            preparesGone(function() {
              root.apps.unknownSources = true
              preparing(function() {
                root.apps.setOn(false)
                check(!root.apps.preparing && root.apps.prepareRun === null && root.apps.review === null, "apps off: stopped, its review gone")
                preparesGone(function() {
                  root.apps.on = true   // (as it was, without setOn's look at your apps)
                  root.apps.unknownSources = true
                  // a prepare that answers once its review has gone some other
                  // way: what it got is let go, and the update queued goes on
                  preparing(function() {
                    root.apps.review = null
                    root.apps.updateQueue = [{ id: pc.id, install: root.apps.installOf(pc) }]
                    answer("inspect", { ok: false, error: "the catalog still can't be reached" })
                    var m = calls().length
                    hold("prepare.hold", false)
                    waitFor(function() { return !root.apps.preparing && calls().slice(m).some(function(c) { return c[0] === "inspect" }) && !root.apps.updating && !root.apps.updateQueue.length }, function() {
                      check(root.apps.status === "Couldn't update Pc: the catalog still can't be reached", "its answer let go, the queued update went on: " + root.apps.status)
                      answer("prepare", null)
                      step9Done()
                    }, "the late answer", 1500)
                  })
                }, "apps off: its prepare killed")
              })
            }, "Unknown sources off: its prepare killed")
          })
        }, "cancelled: its prepare killed")
      }, "the queued update", 1500)
    })
  }
  function step9Done() {
    fake.pluginDir = Quickshell.env("OM_PG_ROOT")
    // Developer mode's row: shown by the 7 presses and while it's on, gone
    // again once it's switched off, or apps are (the presses bring it back)
    root.apps.showDeveloper()
    root.apps.setDeveloper(true)
    check(root.apps.developer && root.apps.developerShown, "Developer mode on: its row shows")
    root.apps.setDeveloper(false)
    check(!root.apps.developer && !root.apps.developerShown, "switched off: its row goes again")
    root.apps.showDeveloper()
    check(root.apps.developerShown, "the presses bring it back")
    root.apps.setOn(false)
    check(!root.apps.developerShown, "apps off: it goes too")
    check(rd(fake.configDir + "/apps.json").indexOf("developerShown") < 0, "and it's never kept for the next start")
    done()
  }

  function sourceFrom(folder) {
    var shown = JSON.parse(rd(Quickshell.env("XDG_STATE_HOME") + "/om-pg/sources/" + folder + "/list.json"))
    return { id: Quickshell.env("SOURCE_ID"), life: "c".repeat(32), name: "Alex's TV apps", fingerprint: Quickshell.env("SOURCE_FP"), keyGen: 0, keyChanged: "", list: shown }
  }

  // 5b: a stop asked for the moment it starts, before its process is up,
  // reaches the helper right behind the init: an orderly stop, well inside
  // the 5 s after which the unit would be killed, and the app never ready
  function step5b() {
    var id = "tv.uber.scores"
    var e = root.apps.ensure(id, "foreground")
    check(e.rt !== null && e.rt.phase === "starting", "started again: " + (e.rt ? e.rt.phase : e.why))
    if (!e.rt) { step6(); return }
    var rt = e.rt
    var why = null, was = "", t0 = Date.now(), t1 = 0
    rt.stopped.connect(function(w, text) { if (why === null) { why = w; t1 = Date.now() } })
    rt.readyNow.connect(function() { was = "ready" })
    rt.stop()
    waitFor(function() { return why !== null }, function() {
      check(why === "normal", "an orderly stop, from the helper (" + why + ")")
      check(t1 - t0 < 4000, "without waiting for the kill: " + (t1 - t0) + " ms")
      check(was === "", "the app never got as far as ready")
      waitFor(function() { return !root.apps.runtimes[id] }, function() { check(true, "let go"); step6() }, "gone", 750)
    }, "stopped at once", 400)
  }
  function step5() {
    var id = "tv.uber.scores"
    root.apps.on = true
    root.apps.checked = Date.now() / 1000   // (no catalog fetch)
    root.apps.listBundled()
    waitFor(function() { return root.apps.isBundled(id) }, function() {
      if (!root.apps.canRun) { console.log("H SKIP apps with code can't run here"); console.log("H SKIP the runtime budget (no app with code installed)"); finish(); return }
      root.apps.get(id)
      waitFor(function() { return root.apps.review !== null }, function() {
        var installed = null
        root.apps.confirm(function(ok) { installed = ok })
        waitFor(function() { return installed !== null }, function() {
          check(installed === true, "Scores installed: " + root.apps.status)
          var a = root.apps.record(id)
          check(root.apps.commit(id, function(x) { var v = {}; for (var k in x.values) v[k] = x.values[k]; v["@clear"] = ["oldKey"]; x.values = v }), "a clean-up owed, on disk")
          var path = fake.configDir + "/app-secrets/" + a.sourceDir + "/" + id + ".json"
          var w = writeFile.createObject(root, { path: path })
          w.setText(JSON.stringify({ user: { oldKey: "left over" }, signIn: { server: "", values: {} } }))
          w.destroy()
          var e = root.apps.ensure(id, "foreground")
          check(e.rt !== null, "it starts: " + e.why)
          if (!e.rt) { finish(); return }
          // what the app's screen does at once with a new runtime (a new
          // demand) can't go to the helper ahead of the init
          e.rt.newDemand()
          e.rt.release([7])
          waitFor(function() { return e.rt.phase === "ready" || e.rt.phase === "stopped" }, function() {
            check(e.rt.phase === "ready", "ready: the helper took the init its record gave it (" + e.rt.why + " " + e.rt.whyText + ")")
            check(JSON.stringify(e.rt.cleanup.clear) === JSON.stringify(["oldKey"]), "asked to clear what it owed first")
            var left = null
            try { left = JSON.parse(rd(path)) } catch (err) {}
            check(left && left.user && left.user.oldKey === undefined, "cleared before the app ran: " + JSON.stringify(left))
            check(root.apps.record(id).values["@clear"] === undefined, "no longer owed once it's ready")
            root.apps.stopAll()   // (a stopped runtime is let go of and destroyed)
            waitFor(function() { return !root.apps.runtimes[id] }, function() { check(true, "stopped"); step5b() }, "stop", 750)
          }, "ready")
        }, "install")
      }, "review")
    }, "bundled")
  }
}
