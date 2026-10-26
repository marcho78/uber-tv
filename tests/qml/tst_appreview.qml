import QtQuick
import QtTest
import "../../ui"
import "../../Look.js" as Look
import "../../AppAsks.js" as Asks

// The review laid out for the couch and an installed app's details,
// ui/DialogBox.qml drawn for real against a
// pretend guide whose store is AppAsks.js: who and where from for each kind
// of app, the summary, the rows in order with changing things first, a long
// list folded until OK opens it, an update's new lines, the buttons' cursor
// past the folded rows, and Activity in the details; Get apps' rows each
// about the app installed from their own origin, and a waiting update that
// asks for nothing new saying so.
// Run: /usr/lib/qt6/bin/qmltestrunner -input tests/qml
Item {
  id: root
  width: 1280
  height: 1600

  readonly property var retro: ({ text: "#f2f4ff", textDim: "#9fb0f0", accent: "#ffd23f", timeline: "#ff4d4d", cell: "#1b3591", cellBorder: "#3b5bd1", channelCell: "#0f2470", selected: "#ffd23f", selectedText: "#141414", header: "#ffd23f", headerText: "#141414", band: "#030a2b", bandText: "#ffd23f", infoPanel: "#40000000", preview: "#000000", alert: "#ff4d4d", bgTop: "#071447", bgBottom: "#030a2b", ltBg: "#eb081447", ltBorder: "#3b5bd1", ltNumber: "#ffd23f", ltChannel: "#9fb0f0", ltTitle: "#f2f4ff", ltProgress: "#ffd23f", ltTrack: "#1b3591", ltClock: "#f2f4ff", ltTime: "#ffd23f", cardBackdrop: "#d1000000", cardName: "#ffd23f", cardStatus: "#9fb0f0", cardFrame: "#3b5bd1", boxBg: "#071447", boxBorder: "#ffd23f", scrim: "#bf030a2b", keyFace: "#e4e9ff", keyText: "#0b1550", keyEdge: "#46559a", miniBar: "#eb030a2b" })

  QtObject {
    id: store
    property var review: null
    property var installed: []
    property string status: ""
    property bool installing: false
    property bool inspecting: false
    property var bundled: []
    property var catalog: null
    function record(id) { return store.installed.filter(function(a) { return a.id === id })[0] || null }
    // (as Apps.rowRecord, tests/qml/appstate.shell.qml step 9o)
    function rowRecord(r) {
      var origin = !r || r.type !== "app" ? "" : r.entry && r.entry.bundled ? "bundled" : "catalog:uber"
      var a = origin ? store.record(r.id) : null
      return a && a.source === origin ? a : null
    }
    function asks(p, s) { return Asks.asks(p, s) }
    function groupsOf(i, p, h) { return Asks.groupsOf(i, p, h) }
    function summary(p, k) { return Asks.summary(p, k) }
    function reviewFolds(r) { return Asks.reviewFolds(r) }
    function hadBefore(r) { return Asks.hadBefore(r) }
    function originLine(f, c, k) { return Asks.originLine(f, c, k) }
    function times(n) { return Asks.times(n) }
    function sizeWords(n) { return Asks.sizeWords(n) }
    readonly property var activityShown: Asks.activityShown
    function newer(a, b) { return String(a) > String(b) }   // (as Apps.newer, for the versions here: one digit each)
  }

  QtObject {
    id: guide
    property string lastInput: "keyboard"
    function noteInput(kind) { lastInput = kind }   // tablet mode: what was used last
    function keyFirst(event) { noteInput("keyboard"); return false }   // (Guide.qml: and the ⋯ panel)
    property var byUser: ({})
    property string dialog: ""
    readonly property var apps: store
    property real u: 16
    readonly property var colors: root.retro
    readonly property var fonts: ({ body: "Sans", display: "Sans", mono: "Monospace" })
    readonly property var look: Look.resolve({}, {}, guide.colors, guide.fonts, {})
    readonly property color ink: colors.text
    readonly property color dimInk: colors.textDim
    readonly property color marquee: colors.accent
    readonly property string fontFamily: "Sans"
    property bool watching: false
    property var channelLock: null
    property var areaImages: ({})
    property int appsCursor: 0
    property string appsArmed: ""
    property string appInfoId: ""
    property bool pickSignedApps: false
    property var reviewOpen: ({})
    property var appActivity: null
    readonly property var appsBoxRows: dialog === "appReview" ? Asks.reviewFolds(store.review).concat([{ type: "install", label: store.review && store.review.updateConsent ? "Agree" : "Install" }, { type: "cancel", label: "Cancel" }])
                                     : dialog === "appInfo" ? Asks.activityFolds(appActivity).concat([{ type: "toggle", label: "On" }, { type: "open", label: "Open it" }]).concat((store.record(appInfoId) || {}).update ? [{ type: "update", label: "Update" }] : []).concat([{ type: "remove", label: "Remove" }])
                                     : dialog === "appCatalog" ? catalogRows : []
    property var catalogRows: []
    property int acted: 0
    function appsAct(by) { guide.acted++ }
    function appsBusy() { return false }
    function closeDialog() {}
    function catalogName(n) { return String(n || "the catalog") }
    function shownPath(p) { return String(p) }
    function agoLabel(t) { return "2 h ago" }
    function inkOn(c) { return "#ffffff" }
  }

  DialogBox { id: box; guide: guide; anchors.fill: parent }

  TestCase {
    name: "AppReview"
    when: windowShown

    function app(api, p, extra) {
      var perms = { net: [], netWrite: {}, server: null, play: false, signIn: "", storage: false }
      for (var k in p) perms[k] = p[k]
      var m = { id: "tv.example.w", name: "Writer", author: "Alex", version: "2.0.0", kind: "app", api: api, permissions: perms, settings: [], home: [], icon: "" }
      for (var e in extra || {}) m[e] = extra[e]
      return m
    }
    function open(from, m, have) {
      var r = { from: from, file: "/home/x/writer.tar.gz", manifest: m, have: have || null, replaces: "", staging: "/nonexistent", asks: Asks.asks(m.permissions, m.settings) }
      r.newAsks = have ? Asks.newAsks(have, m) : []
      store.review = r
      guide.reviewOpen = {}
      guide.dialog = "appReview"
      guide.appsCursor = Asks.reviewFolds(r).length + (Asks.cancelFirst(r) ? 1 : 0)   // as Guide.qml openReview
      wait(0)
    }
    // every visible item drawing text, under item
    function texts(item, out) {
      out = out || []
      if (!item || !item.visible) return out
      if (item.text !== undefined && typeof item.text === "string" && item.text !== "" && item.width > 0 && item.height > 0) out.push(item)
      for (var i = 0; i < item.children.length; i++) texts(item.children[i], out)
      if (item.contentItem) texts(item.contentItem, out)
      return out
    }
    function find(s) { return texts(box).filter(function(t) { return t.text.indexOf(s) >= 0 })[0] || null }
    function findRow(label) {
      var hit = null
      var walk = function(it) {
        if (!it || hit) return
        if (it.label === label && it.visible && it.height > 0) { hit = it; return }
        for (var i = 0; i < it.children.length; i++) walk(it.children[i])
        if (it.contentItem) walk(it.contentItem)
      }
      walk(box)
      return hit
    }
    function posY(it) { return it.mapToItem(root, 0, 0).y }

    function cleanup() { guide.dialog = ""; store.review = null; guide.appActivity = null }

    function test_who_for_each_kind() {
      open("file", app(4, { net: ["a.example.com"] }))
      verify(find("From a file on this computer. Uber TV didn't make this app."), "a file's: plainly not Uber TV's")
      verify(find("It runs in its sandbox with only what's listed below."), "anyone else's code: the sandbox said")
      verify(find("Writer  ·  Alex  ·  version 2.0.0"))
      open("appFile", app(4, { net: ["a.example.com"] }))
      store.review = Object.assign({}, store.review, { fingerprint: "SHA256:" + "k".repeat(43) })
      wait(0)
      verify(find("From a signed app file you installed (developer key " + store.review.fingerprint + ")"))
      open("bundled", app(4, { net: ["a.example.com"] }))
      verify(find("From Uber TV: it comes with the guide"))
      verify(!find("It runs in its sandbox with only what's listed below."), "Uber TV's own: no need")
      open("catalog", { id: "tv.example.flix", name: "Flix", author: "Uber TV", version: "1.0.0", kind: "launcher", api: 1, permissions: { web: ["flix.example.com"] }, settings: [], home: [], icon: "" })
      verify(find("It opens flix.example.com in your browser."), "a launcher's summary")
      verify(find("flix.example.com, full screen"))
      verify(!findRow("Can't reach your files, channels, other apps or sites it didn't list"), "a launcher runs no code: no Can't row")
    }

    function test_summary_and_rows_in_order() {
      open("file", app(4, { net: ["api.trakt.tv", "img.example.com"], netWrite: { "api.trakt.tv": ["POST"] }, server: { label: "S" }, storage: true }))
      verify(find("It connects to 2 sites and can change things on 1, can read, change and delete things on your server.") === null)
      var s = find("It connects to 2 sites")
      verify(s, "the summary line")
      compare(s.text, "It connects to 2 sites and can change things on 1 and can read, change and delete things on your server.")
      var w = find("CAN CHANGE THINGS ON"), c = find("CONNECTS TO"), v = find("YOUR SERVER"), k = find("KEEPS ON THIS COMPUTER")
      verify(w && c && v && k, "a row a group")
      verify(posY(w) < posY(c) && posY(c) < posY(v) && posY(v) < posY(k), "changing things first, then the rest in order")
      verify(find("api.trakt.tv (POST)"))
      compare(find("img.example.com").text, "img.example.com", "a write site isn't listed again under Connects to")
      verify(findRow("Can't reach your files, channels, other apps or sites it didn't list"), "Can't, one line")
      verify(!find("It can't see your files"), "folded until opened")
    }

    function test_long_list_folds_and_opens() {
      open("file", app(4, { net: ["a.example.com", "b.example.com", "c.example.com", "d.example.com", "e.example.com"] }))
      verify(find("a.example.com, b.example.com, c.example.com"), "three shown")
      verify(!find("e.example.com"), "the rest folded")
      var more = findRow("And 2 more")
      verify(more, "a row the cursor stops on")
      verify(!more.focused, "the cursor starts on Cancel, not here")
      guide.appsCursor = 0
      wait(0)
      verify(more.focused, "it does stop on it")
      guide.reviewOpen = { net: true }
      wait(0)
      verify(find("a.example.com, b.example.com, c.example.com, d.example.com, e.example.com"), "OK opens it")
      verify(findRow("Fewer"))
      guide.reviewOpen = { cant: true }
      wait(0)
      verify(find("It can't see your files"), "and Can't opens too")
    }

    function test_buttons_past_the_folded_rows() {
      open("file", app(4, { net: ["a.example.com"] }))   // folds: Can't
      compare(guide.appsCursor, 2, "Cancel first for a file's: past one folded row")
      var cancel = findRow("Cancel"), install = findRow("Install")
      verify(cancel && install)
      verify(cancel.focused && !install.focused)
      open("bundled", app(4, { net: ["a.example.com"] }))
      compare(guide.appsCursor, 1, "Install first for Uber TV's own")
      verify(findRow("Install").focused)
    }

    function test_an_update_shows_whats_new() {
      var have = app(4, { net: ["a.example.com"], netWrite: { "a.example.com": ["POST"] } })
      open("bundled", app(4, { net: ["a.example.com"], netWrite: { "a.example.com": ["POST", "DELETE"] } }), have)
      verify(find("NEW IN VERSION 2.0.0"))
      verify(find("a.example.com (DELETE)"), "only the new method")
      verify(!find("a.example.com (POST, DELETE)"))
      var before = findRow("And what it had before")
      verify(before)
      verify(findRow("Cancel").focused, "a new way to change things: Cancel first, even for Uber TV's own")
      guide.reviewOpen = { before: true }
      wait(0)
      verify(find("Can change things on: a.example.com (POST)"), "what it had, when opened")
    }

    function test_signed_update_says_exactly_what_agree_fetches() {
      var have = app(4, { net: ["a.example.com"], netWrite: { "a.example.com": ["POST"] } })
      have.version = "1.0.0"
      have.from = "appFile"
      have.source = "app:0123456789abcdef"
      open("appFile", app(4, { net: ["a.example.com"], netWrite: { "a.example.com": ["POST", "DELETE"] } }), have)
      store.review = Object.assign({}, store.review, { updateConsent: true,
        fetchAddress: "https://updates.example.com/clock/clock-2.0.0.tar.gz", fetchSize: 1536,
        fingerprint: "SHA256:" + "k".repeat(43) })
      wait(0)
      verify(find("WHAT AGREE WILL FETCH"))
      verify(find("Address: https://updates.example.com/clock/clock-2.0.0.tar.gz"))
      verify(find("Version: 2.0.0  ·  Size: 2 KB"))
      verify(find("Developer key: " + store.review.fingerprint))
      verify(find("a.example.com (DELETE)"), "the new ask is shown")
      verify(findRow("Agree"), "the package consent is Agree")
    }

    function test_another_key_is_plainly_a_new_app_without_old_data() {
      var have = app(4, { net: ["a.example.com"] })
      have.from = "appFile"
      have.source = "app:1111111111111111"
      open("appFile", app(4, { net: ["a.example.com"] }), have)
      store.review = Object.assign({}, store.review, { source: "app:2222222222222222", replaces: "appFile",
                                                       fingerprint: "SHA256:" + "n".repeat(43) })
      wait(0)
      verify(find("same app id but a different developer key"))
      verify(find("none of the old app's saved data, settings, sign-in, server, pictures or Activity is kept"))
      verify(findRow("Install"), "another key installs a new app, not an update")
    }

    // A signed app file names the key pinned to what's installed.
    function test_details_name_the_key_that_signed_it() {
      var old = "SHA256:" + "o".repeat(43)
      store.installed = [{ id: "tv.alex.clock", name: "Clock", kind: "app", enabled: true, from: "appFile", source: "app:0123456789abcdef", catalogName: "",
                           keyFingerprint: old, home: [], settings: [],
                           permissions: { net: ["time.example.com"], netWrite: {}, server: null, play: false, signIn: "", storage: false } }]
      guide.appInfoId = "tv.alex.clock"
      guide.dialog = "appInfo"
      guide.appActivity = { sites: [], refused: [], refusedMore: 0 }
      wait(0)
      verify(find("From a signed app file you installed (developer key " + old + "). A signature shows who published it, not that anyone checked it."), "the key that signed it")
      guide.dialog = ""
    }

    function test_details_activity() {
      store.installed = [{ id: "tv.example.w", name: "Writer", kind: "app", enabled: true, from: "file", file: "/x", catalogName: "", home: [], settings: [],
                           permissions: { net: ["api.example.com"], netWrite: { "api.example.com": ["POST"] }, server: null, play: false, signIn: "", storage: false } }]
      guide.appInfoId = "tv.example.w"
      guide.dialog = "appInfo"
      wait(0)
      verify(find("Reading…"), "while it's read")
      guide.appActivity = { sites: [{ site: "api.example.com", server: false, reads: 12, writes: 1, sent: 100, received: 2048, failed: 0, kinds: ["fetch"], last: 1 },
                                    { site: "home.example:8096", server: true, reads: 3, writes: 0, sent: 0, received: 10, failed: 0, kinds: ["media"], last: 1 }],
                            refused: [{ site: "tracker.example", count: 3, last: 1, change: false }, { site: "api.example.com", count: 1, last: 1, change: true }],
                            refusedMore: 2 }
      wait(0)
      verify(find("api.example.com: got things 12 times, changed things once"))
      verify(find("Your server (home.example:8096): got things 3 times"))
      verify(find("Tried to reach tracker.example: refused, 3 times"))
      verify(find("Tried to change things on api.example.com: refused, once"))
      verify(find("And 2 more refused attempts"))
      verify(find("From a file on this computer. Uber TV didn't make this app."))
      verify(find("Can change things on: api.example.com (POST)"))
      guide.appActivity = { sites: [], refused: [], refusedMore: 0 }
      wait(0)
      verify(find("It hasn't contacted any site yet."))
      // past the first few, a row that Enter opens: every site still reachable
      var many = [], names = []
      for (var i = 1; i <= 7; i++) many.push({ site: "s" + i + ".example.com", server: false, reads: i, writes: 0, sent: 0, received: 0, failed: 0, kinds: ["fetch"], last: 1 })
      for (var j = 1; j <= 5; j++) names.push({ site: "t" + j + ".example", count: 1, last: 1, change: false })
      guide.appActivity = { sites: many, refused: names, refusedMore: 3 }
      wait(0)
      verify(find("s6.example.com") && !find("s7.example.com"), "six shown")
      verify(find("t4.example") && !find("t5.example"), "four refused shown")
      var moreSites = findRow("And 1 more site"), moreRefused = findRow("And 1 more refused site")
      verify(moreSites && moreRefused, "rows for the rest")
      var keysOf = guide.appsBoxRows.map(function(r) { return r.type === "fold" ? r.key : r.type })
      compare(keysOf.slice(0, 3).join(","), "sites,refused,toggle", "the cursor stops on each before the box's own rows")
      guide.appsCursor = 0
      wait(0)
      verify(moreSites.focused && !moreRefused.focused)
      guide.appsCursor = 1
      wait(0)
      verify(moreRefused.focused)
      verify(findRow("On") && !findRow("On").focused)
      verify(find("And 3 more refused attempts whose sites weren't kept"), "the unnamed ones, apart")
      guide.reviewOpen = { sites: true, refused: true }
      wait(0)
      verify(find("s7.example.com") && find("t5.example"), "opened, every one")
      verify(findRow("Fewer"))
      guide.reviewOpen = {}
      guide.appActivity = { failed: true, sites: [], refused: [], refusedMore: 0 }
      wait(0)
      verify(find("Its Activity couldn't be read just now."), "a failed read says so, never Reading… for ever")
    }

    // Get apps: a row for the guide's own Scores, or the catalog's, says
    // nothing of a Scores installed from a signed app file (choosing it
    // is a replace); one installed from the row's own origin is its own
    function test_get_apps_rows_are_their_own_origins() {
      var row = function(id, name, entry) { return { type: "app", id: id, label: name, entry: entry } }
      var value = function(label) { var r = findRow(label); return r ? r.value : null }
      var theirs = { id: "tv.uber.scores", name: "Scores", version: "2.0.0", source: "app:0123456789abcdef", from: "appFile" }
      var cat = { id: "tv.example.cat", name: "Cat", version: "1.0.0", source: "app:0123456789abcdef", from: "appFile" }
      store.installed = [theirs, cat]
      guide.catalogRows = [row("tv.uber.scores", "Scores", { bundled: true, version: "1.2.0", author: "Uber TV" }), row("tv.example.cat", "Cat", { version: "1.1.0", author: "Alex" })]
      var drawn = function() { tryVerify(function() { return findRow("Scores") !== null && findRow("Cat") !== null }, 2000, "both rows drawn") }
      guide.appsCursor = 0
      guide.dialog = "appCatalog"
      drawn()
      compare(value("Scores"), "By Uber TV", "not Installed: that's a signed-file Scores")
      compare(value("Cat"), "By Alex", "not Update to 1.1.0: that's a replace")
      guide.catalogRows = [row("tv.uber.scores", "Scores", { bundled: true, version: "3.0.0", author: "Uber TV" }), row("tv.example.cat", "Cat", { version: "1.0.0", author: "Alex" })]
      drawn()
      compare(value("Scores"), "By Uber TV", "nor Update to 3.0.0")
      compare(value("Cat"), "By Alex", "nor Installed")
      store.installed = [Object.assign({}, theirs, { version: "1.2.0", source: "bundled", from: "bundled" }), Object.assign({}, cat, { source: "catalog:uber", from: "catalog" })]
      wait(0)
      compare(value("Scores"), "Update to 3.0.0", "the guide's own, its own row")
      compare(value("Cat"), "Installed", "the catalog's, its own row")
      guide.dialog = ""
      guide.catalogRows = []
      store.installed = []
    }

    // a signed app-file update waits even when it asks for nothing new: said
    // so, never "it also asks to ."
    function test_a_waiting_update_that_asks_for_nothing_new() {
      store.installed = [{ id: "tv.alex.clock", name: "Clock", kind: "launcher", enabled: true, from: "appFile", source: "app:0123456789abcdef", catalogName: "",
                           keyFingerprint: "", home: [], settings: [], version: "1.0.0", update: { version: "1.1.0", asks: [] }, permissions: { web: ["clock.example.com"] } }]
      guide.appInfoId = "tv.alex.clock"
      guide.dialog = "appInfo"
      wait(0)
      verify(find("Update available: version 1.1.0. It asks for nothing new."), "said so")
      verify(!find("it also asks to"), "no empty list")
      store.installed = [Object.assign({}, store.installed[0], { update: { version: "2.0.0", asks: ["Now run code in a sandbox on this computer"] } })]
      wait(0)
      verify(find("Update available: version 2.0.0. it also asks to now run code in a sandbox on this computer."), "what it asks for, when it asks")
      guide.dialog = ""
      store.installed = []
    }
  }
}
