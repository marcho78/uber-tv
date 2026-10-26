import QtQuick
import QtTest
import "../.."
import "../../ui"
import "../../Look.js" as Look
import "../../AppLooks.js" as Looks
import "../../Touch.js" as Touch

// ui/AppScreen.qml drawn for real, offscreen at 1280×720, with the real
// AppView against a pretend guide, store and runtime, Retro's colors and
// the fixture pictures in tests/fixtures/pictures: a details screen asks for
// both its pictures and shapes its picture's space; cards learn their row's
// shape and fill it; a learned square shows its picture whole; corners are
// cut under a radius; the focus ring and the selected title survive hostile
// themes; the colors they're measured against are the colors drawn; a big
// grid makes only the cards on the screen.
// Run: /usr/lib/qt6/bin/qmltestrunner -input tests/qml
Item {
  id: root
  width: 1280
  height: 720

  readonly property string pics: Qt.resolvedUrl("../fixtures/pictures/").toString().replace(/^file:\/\//, "")

  component FakeRuntime: QtObject {
    id: frt
    property string phase: "ready"
    property var calls: []
    property var leases: ({})
    property int nextId: 1
    property var asked: []            // [{ token, done }]
    signal readyNow()
    signal stopped(string why, string text)
    signal signInCode(string flow, string code, string url, real expires)
    signal signInDone(string flow, bool ok, string message)
    function call(method, args, done) { var c = { id: frt.nextId++, method: method, args: args, done: done }; frt.calls = frt.calls.concat([c]); return c.id }
    function cancel(id) {}
    function lease(name, on) { var l = {}; for (var k in frt.leases) l[k] = true; if (on) l[name] = true; else delete l[name]; frt.leases = l }
    property var released: []
    property int demand: 0
    function image(token, done, epoch, prio, consumer, broken) { frt.asked = frt.asked.concat([{ token: token, done: done, epoch: epoch, prio: prio, broken: broken }]) }
    function newDemand() { frt.demand += 1; return frt.demand }
    function release(results) { frt.released = frt.released.concat(results) }
    // the helper's answer: a path (with its size, when given), or a failure's code
    function answer(token, path, w, h) {
      for (var i = 0; i < frt.asked.length; i++) if (frt.asked[i].token === token)
        frt.asked[i].done(path, path ? { w: w || 0, h: h || 0 } : { code: "failed" })
    }
    function last() { return frt.calls[frt.calls.length - 1] }
    property var typed: []
    function sendPassword(flow, u, p) { frt.typed = frt.typed.concat([{ flow: flow, username: u, password: p }]); return true }
    function cancelSignIn(flow) {}
    property var chose: []
    function chooseServer(flow, handle, url) { frt.chose = frt.chose.concat([{ handle: handle, url: url }]); return true }
    function typedServer(flow, handle, address) { frt.chose = frt.chose.concat([{ handle: handle, typed: address }]); return true }
  }
  Component { id: rtKind; FakeRuntime {} }

  QtObject {
    id: store
    property var runtimes: ({})
    property var made: []
    property string status: ""
    property var ready: [{ id: "tv.example.app" }]
    property var changing: ({})
    property string source: "bundled"
    property string from: "bundled"
    function record(id) {
      return { id: id, name: "Example", kind: "app", from: store.from, source: store.source, icon: "", values: {}, settings: [],
               permissions: { net: [], server: null, play: false, signIn: "", storage: false } }
    }
    function cannotOpen(id) { return "" }
    function clearFault(id) {}
    function used(id) {}
    function ensure(id, lease) {
      var rt = store.runtimes[id]
      if (!rt) { rt = rtKind.createObject(root); var m = {}; m[id] = rt; store.runtimes = m; store.made = store.made.concat([rt]) }
      if (lease) rt.lease(lease, true)
      return { rt: rt, why: "" }
    }
    function withKey(map, key, value) { var o = {}; for (var k in map) o[k] = map[k]; o[key] = value; return o }
    function runtime(id) { return store.runtimes[id] || null }
    function canonicalServer(text, done) { done(true, text.replace(/\/?$/, "/"), "") }
  }

  readonly property var retro: ({ text: "#f2f4ff", textDim: "#9fb0f0", accent: "#ffd23f", timeline: "#ff4d4d", cell: "#1b3591", cellBorder: "#3b5bd1", channelCell: "#0f2470", selected: "#ffd23f", selectedText: "#141414", header: "#ffd23f", headerText: "#141414", band: "#030a2b", bandText: "#ffd23f", infoPanel: "#40000000", preview: "#000000", alert: "#ff4d4d", bgTop: "#071447", bgBottom: "#030a2b", ltBg: "#eb081447", ltBorder: "#3b5bd1", ltNumber: "#ffd23f", ltChannel: "#9fb0f0", ltTitle: "#f2f4ff", ltProgress: "#ffd23f", ltTrack: "#1b3591", ltClock: "#f2f4ff", ltTime: "#ffd23f", cardBackdrop: "#d1000000", cardName: "#ffd23f", cardStatus: "#9fb0f0", cardFrame: "#3b5bd1", boxBg: "#071447", boxBorder: "#ffd23f", scrim: "#bf030a2b", keyFace: "#e4e9ff", keyText: "#0b1550", keyEdge: "#46559a", miniBar: "#eb030a2b" })

  QtObject {
    id: guide
    property bool touchMode: false
    property real fingerPx: 44
    function isFinger(mouse) { return Touch.byFinger(mouse) }   // (as Guide.qml's)
    property string lastInput: "keyboard"
    function noteInput(kind) { lastInput = kind }   // tablet mode: what was used last
    function keyFirst(event) { noteInput("keyboard"); return false }   // (Guide.qml: and the ⋯ panel)
    property var byUser: ({})
    property bool opened: true
    property string screen: "apps"
    property bool watching: false
    property string codeApp: ""
    property string dialog: ""
    readonly property var apps: store
    property real u: 16
    property var colorOverrides: ({})
    readonly property var colors: { var o = {}; for (var k in root.retro) o[k] = root.retro[k]; for (var c in guide.colorOverrides) o[c] = guide.colorOverrides[c]; return o }
    property var elementOverrides: ({})
    readonly property var fonts: ({ body: "Sans", display: "Sans", mono: "Monospace" })
    readonly property var look: Look.resolve({}, guide.elementOverrides, guide.colors, guide.fonts, {})
    readonly property var layout: Look.effectiveLayout({}, {})
    readonly property color ink: colors.text
    readonly property color dimInk: colors.textDim
    readonly property color marquee: colors.accent
    readonly property string fontFamily: "Sans"
    property bool showKeyHints: true
    property real now: 0
    readonly property var appView: view
    readonly property var appScreens: screensStub
    property var currentTheme: ({ id: "retro", apps: ({}) })
    property string wallpaperUrl: ""
    property string backgroundSource: ""
    property real bgDim: 0.6
    property bool bgFloored: false
    property real railSpace: 0
    property bool appPlaying: false
    property var screenSaver: ({ showing: false })
    function clock(t) { return "8:42 PM" }
    function fileUrl(p) { return "file://" + p }
    function inkOn(c) { return "#ffffff" }
    function openApps(back) { guide.screen = "apps" }
    function focusKeys() {}
    function playApp(id, rt, value) {}
    function finishAppPlayback(id, reason, then) { then() }
    function makeQr(url, done) {}
  }

  // your choices for the app's screen (AppScreens), as the tests set them
  QtObject {
    id: screensStub
    property var entry: null
    property var all: ({})
    function entryOf(a) { return screensStub.entry }
  }

  AppView { id: view; guide: guide }
  // something of the guide's own drawn before the app's screen, as Guide.qml
  // draws its key hints note (K) before it, at the bottom left
  Rectangle { id: guideNote; visible: false; color: "#ff0000"; x: 32; y: root.height - 80; width: 200; height: 48 }
  AppScreen { id: screen; guide: guide; anchors.fill: parent }

  // the real Box drawing a page's fill over the window's own color, shown
  // only while the colors behind are checked against it
  Rectangle {
    id: fillBase
    visible: false
    z: 10
    width: 48
    height: 320
    Box { id: fillBox; anchors.fill: parent }
  }

  function item(id, image) { return { id: id, title: id, subtitle: "", badge: "", kind: "open", image: image, progress: null } }
  function pic(name) { return { path: root.pics + name } }
  function screenOf(rows) { return { title: "Home", empty: "", refresh: null, rows: rows } }

  function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var f = find(kids[i], name); if (f) return f }
    if (item.contentItem && item.contentItem !== item) return find(item.contentItem, name)
    return null
  }
  function findAll(item, pred, out) {
    out = out || []
    if (!item) return out
    if (pred(item)) out.push(item)
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) findAll(kids[i], pred, out)
    if (item.contentItem && item.contentItem !== item) findAll(item.contentItem, pred, out)
    return out
  }
  // the window's pixel at (x, y) of item (items in a list don't grab alone);
  // the grab is in device pixels, so on a HiDPI screen it's bigger than root
  function pixelOf(img, item, x, y) {
    var p = item.mapToItem(null, x, y)
    var w = root.Window.window ? root.Window.window.width : root.width
    var h = root.Window.window ? root.Window.window.height : root.height
    return img.pixel(Math.round(p.x * img.width / Math.max(1, w)), Math.round(p.y * img.height / Math.max(1, h)))
  }
  function cards() {
    var seen = new Set()
    return findAll(screen, function(x) { return x.cardW !== undefined && x.modelData !== undefined && x.selectedTitle !== undefined })
           .filter(function(x) { if (seen.has(x)) return false; seen.add(x); return true })
  }

  TestCase {
    name: "AppScreen"
    when: windowShown

    function open(value, kind) {
      compare(view.open("tv.example.app", guide.byUser), "ok")
      var rt = store.made[store.made.length - 1]
      rt.last().done(kind || "screen", value)
      return rt
    }

    function init() {
      store.runtimes = ({})
      store.made = []
      view.appId = ""
      view.stack = []
      view.pending = null
      view.rt = null
      view.learned = ({})
      view.learnedOrder = ({})
      view.sampling = ({})
      view.imagePaths = ({})
      guide.screen = "apps"
      guide.touchMode = false
      guide.elementOverrides = ({})
      guide.colorOverrides = ({})
      guide.currentTheme = ({ id: "retro", apps: ({}) })
      store.source = "bundled"
      store.from = "bundled"
    }

    // ---- the password box -------------------------
    function test_the_password_box_takes_two_fields_and_keeps_nothing() {
      var rt = open({ title: "T", rows: [] })
      view.signIn = { flow: "f1", how: "password", stage: "typing", code: "", url: "", expires: 0, qr: "" }
      wait(50)
      var fields = findAll(screen, function(x) { return x.echoMode !== undefined && x.visible && x.width > 0 })
      compare(fields.length, 2, "a username and a password field")
      var user = fields.filter(function(f) { return f.echoMode === TextInput.Normal })[0]
      var pass = fields.filter(function(f) { return f.echoMode === TextInput.Password })[0]
      verify(user && pass, "the password as dots")
      verify(user.activeFocus, "the cursor starts in the username")
      verify(!findAll(screen, function(x) { return x.text !== undefined && x.visible && typeof x.text === "string" && /Asking .* for a code/.test(x.text) }).length, "no code here")
      keyClick(Qt.Key_A); keyClick(Qt.Key_L); keyClick(Qt.Key_E); keyClick(Qt.Key_X)
      compare(user.text, "alex", "typed on the keyboard")
      keyClick(Qt.Key_Return)
      verify(pass.activeFocus, "Enter with no password moves to it")
      compare(rt.typed.length, 0, "nothing sent without both")
      keyClick(Qt.Key_P); keyClick(Qt.Key_W); keyClick(Qt.Key_1)
      keyClick(Qt.Key_Return)
      compare(rt.typed.length, 1)
      compare(rt.typed[0].username, "alex")
      compare(rt.typed[0].password, "pw1")
      compare(user.text + pass.text, "", "the fields are cleared the moment it's sent")
      compare(view.signIn.stage, "checking")
      wait(20)
      verify(!user.visible && !pass.visible, "and gone while it signs in")
      verify(findAll(screen, function(x) { return x.text === "Signing in…" && x.visible }).length === 1, "it says so")
      view.cancelSignIn()
      // typed, then cancelled: cleared too
      view.signIn = { flow: "f2", how: "password", stage: "typing", code: "", url: "", expires: 0, qr: "" }
      wait(20)
      keyClick(Qt.Key_Z)
      compare(user.text, "z")
      keyClick(Qt.Key_Escape)
      compare(view.signIn, null, "Esc cancels")
      compare(user.text + pass.text, "", "and what was typed goes with the box")
    }

    function test_choosing_a_server_in_the_sign_in_box() {
      var rt = open({ title: "T", rows: [] })
      view.signIn = { flow: "f3", how: "code", stage: "servers", code: "123456", url: "", expires: 0, qr: "", sent: false, install: "",
                      servers: [{ handle: "res-a", label: "Living room", urls: ["https://a.example/"] }, { handle: "res-b", label: "Office", urls: ["http://192.168.1.20:32400/"] }],
                      server: null, pick: 0, target: "", note: "" }
      wait(30)
      var rows = function() { return findAll(screen, function(x) { return x.label !== undefined && x.focused !== undefined && x.visible && x.height > 0 && x.kind !== undefined }) }
      compare(rows().map(function(r) { return r.label }), ["Living room", "Office"], "the servers, as rows")
      verify(rows()[0].focused)
      verify(!findAll(screen, function(x) { return x.text === "1 2 3 4 5 6" && x.visible }).length, "the code is gone once it's choosing")
      // (the arrows and Enter reach these through GuideKeys.qml, not drawn here)
      view.signInMove(1)
      verify(rows()[1].focused, "the arrows move")
      view.signInAct(guide.byUser)
      compare(rows().map(function(r) { return r.label }), ["http://192.168.1.20:32400/", "Type an address for this server"])
      view.signInMove(1)
      view.signInAct(guide.byUser)
      wait(20)
      var field = findAll(screen, function(x) { return x.echoMode !== undefined && x.visible && x.width > 0 })[0]
      verify(field && field.activeFocus, "typing an address: its field, focused")
      keyClick(Qt.Key_H); keyClick(Qt.Key_Period); keyClick(Qt.Key_I); keyClick(Qt.Key_O)
      keyClick(Qt.Key_Return)
      compare(rt.chose.length, 1)
      compare(rt.chose[0].handle, "res-b")
      compare(rt.chose[0].typed, "h.io/")
      compare(view.signIn.stage, "checking")
      verify(findAll(screen, function(x) { return x.text === "Signing in…" && x.visible }).length === 1)
      view.cancelSignIn()
    }

    // ---- api 4's richer blocks, in every look ------
    function richScreen() {
      return { title: "Scores", empty: "", refresh: null, rows: [
        { id: "news", title: "News", layout: "ticker", items: [{ id: "n1", title: "Gulls win", subtitle: "", badge: "NEW", kind: "open", image: null, progress: null }] },
        { id: "st", title: "Standings", layout: "table", columns: [{ label: "#", align: "end" }, { label: "Team", align: "start" }, { label: "Pct", align: "end" }],
          items: [{ id: "t1", title: "Gulls", subtitle: "", badge: "", kind: "info", image: null, progress: null, cells: ["1", "Harbor Gulls", "0.750"], chart: { points: [4, 6, 9], low: "", high: "" } },
                  { id: "t2", title: "Owls", subtitle: "", badge: "", kind: "info", image: null, progress: null, cells: ["2", "North Owls", "0.625"] }] } ] }
    }
    function test_richBlocks_data() { return ["classic", "posters", "cinematic", "wall", "compact"].map(function(l) { return { tag: l, look: l } }) }
    function test_richBlocks(d) {
      setLook(d.look)
      open(richScreen())
      wait(50)
      var labels = function(pred) {
        var seen = new Set()   // (a list's items are reached twice: as children and through its content)
        return findAll(screen, function(x) { return x.text !== undefined && typeof x.text === "string" && x.visible && pred(x.text) })
               .filter(function(x) { if (seen.has(x)) return false; seen.add(x); return true })
      }
      verify(labels(function(t) { return t === "Harbor Gulls" }).length === 1, "a table's cell, drawn")
      verify(labels(function(t) { return t === "Pct" }).length === 1, "its column's name")
      var pct = labels(function(t) { return t === "0.750" })[0]
      compare(pct.horizontalAlignment, Text.AlignRight, "an end column keeps to the right")
      var seenRows = new Set()
      var rows = findAll(screen, function(x) { return x.objectName === "tableRow" && x.visible })
                 .filter(function(x) { if (seenRows.has(x)) return false; seenRows.add(x); return true })
      compare(rows.length, 2)
      verify(find(screen, "ticker").visible, "the ticker")
      var strip = find(screen, "tickerStrip")
      verify(strip, "its strip")
      // the ticker is the first line: selected, it holds still
      var x0 = strip.x
      wait(400)
      compare(strip.x, x0, "selected: it stops")
      view.move("down")      // into the table
      wait(400)
      verify(strip.x !== x0, "not selected: it moves across")
      verify(rows[0].current, "the table's first line selected")
      // a video full screen, or the screen saver: it stops again
      guide.appPlaying = true
      var x1 = strip.x
      wait(300)
      compare(strip.x, x1, "a video playing: it stops")
      guide.appPlaying = false
      guide.screenSaver = { showing: true }
      x1 = strip.x
      wait(300)
      compare(strip.x, x1, "the screen saver up: it stops")
      guide.screenSaver = { showing: false }
      setLook("")
    }

    function test_a_details_chart_and_an_article_page() {
      open({ title: "Team", subtitle: "", text: "", image: null, backdrop: null, facts: [], actions: [], rows: [], style: "classic",
             chart: { points: [1, 5, 3, 8], low: "0", high: "10" } }, "detail")
      wait(50)
      var c = find(screen, "detailChart")
      verify(c && c.visible && c.height > 0, "a details page's chart")
      // an article page: its title and sections; the arrows scroll it, within its length
      var rt = store.made[store.made.length - 1]
      var sections = []
      for (var i = 0; i < 20; i++) sections.push({ heading: "Part " + (i + 1), text: "A line of text that goes on for a while.\nAnd another." })
      view.ask("browse", { item: "a" }, "push")
      rt.last().done("page", { title: "An article", sections: sections })
      wait(50)
      var pg = find(screen, "appPage")
      verify(pg && pg.visible, "the page")
      verify(!find(screen, "appLines").visible, "instead of the lines")
      verify(find(screen, "pageTitle").text === "An article")
      verify(view.pageMax > 0, "longer than the screen")
      compare(view.pageY, 0)
      view.move("down")
      verify(view.pageY > 0, "down scrolls")
      for (var k = 0; k < 200; k++) view.move("down")
      compare(view.pageY, view.pageMax, "never past its end")
      verify(!view.move("left"), "left isn't scrolling (the rail opens)")
      view.back()
      compare(view.topView.kind, "detail", "Esc: back to where it came from")
    }

    // ---- tablet mode: a finger, or the mouse ---------------------------------
    // with tablet mode on, a finger's tap opens a card at once and a mouse's
    // click picks it (a second click opens); a featured row's item opens at
    // a tap, and its dots, a finger apart, show their items; a long article
    // scrolls under a finger, and the keys go on from where it stopped
    function tapAt(item, x, y) {
      var t = touchEvent(item)
      t.press(0, item, x, y).commit()
      t.release(0, item, x, y).commit()
    }
    function test_tablet_mode_a_finger_opens_and_the_mouse_picks() {
      var rt = open(lookScreen())
      guide.touchMode = true
      var hero = null
      tryVerify(function() { hero = find(screen, "appHero"); return !!hero }, 2000)
      var card = function(id) { return cards().filter(function(c) { return c.modelData && c.modelData.id === id })[0] }
      tryVerify(function() { return !!card("c2") && card("c2").visible }, 2000, "a row's card")
      view.move("down")   // its row in view (the cursor on its first card)
      var shown = function(id) { var c = card(id); var p = c.mapToItem(screen, 0, c.height); return p.y <= find(screen, "appLines").mapToItem(screen, 0, find(screen, "appLines").height).y }
      tryVerify(function() { return shown("c2") }, 2000, "on the screen whole")
      var calls = rt.calls.length
      mouseClick(card("c2"), card("c2").width / 2, card("c2").height / 2)
      verify(view.sel && view.sel.item === "c2", "a click picks")
      compare(rt.calls.length, calls, "and doesn't open")
      wait(500)   // (a second click, not a double click)
      mouseClick(card("c2"), card("c2").width / 2, card("c2").height / 2)
      verify(rt.calls.length > calls, "a second click opens")
      view.back()
      wait(50)
      calls = rt.calls.length
      tryVerify(function() { return !!card("c3") && card("c3").visible && shown("c3") }, 2000)
      tapAt(card("c3"), card("c3").width / 2, card("c3").height / 2)
      verify(view.sel && view.sel.item === "c3")
      verify(rt.calls.length > calls, "a finger opens at its first tap")
    }
    function test_tablet_mode_the_featured_row() {
      var rt = open(lookScreen())
      guide.touchMode = true
      var hero = null
      tryVerify(function() { hero = find(screen, "appHero"); return !!hero }, 2000)
      var dots = findAll(find(hero, "heroDots"), function(x) { return x.radius !== undefined && x.width === Math.round(guide.u * 0.7) })
      compare(dots.length, 3)
      var gap = function() { return dots[1].mapToItem(hero, 0, 0).x - dots[0].mapToItem(hero, 0, 0).x }
      tryVerify(function() { return gap() >= guide.fingerPx - 1 }, 1000, "a finger apart")
      var calls = rt.calls.length
      tapAt(dots[2], dots[2].width / 2, dots[2].height / 2)
      compare(view.sel.item, "hero2", "a dot shows its item")
      compare(rt.calls.length, calls, "and opens nothing")
      view.move("down")
      compare(view.sel.item === "hero2", false, "the cursor elsewhere")
      mouseClick(hero, hero.width * 0.3, hero.height * 0.4)
      compare(view.sel.item, "hero2", "a click on it picks the item it shows")
      compare(rt.calls.length, calls)
      tapAt(hero, hero.width * 0.3, hero.height * 0.4)
      verify(rt.calls.length > calls, "a tap opens it")
    }
    function test_tablet_mode_an_article_scrolls_under_a_finger() {
      open({ title: "Team", subtitle: "", text: "", image: null, backdrop: null, facts: [], actions: [], rows: [], style: "classic" }, "detail")
      var rt = store.made[store.made.length - 1]
      var sections = []
      for (var i = 0; i < 30; i++) sections.push({ heading: "Part " + (i + 1), text: "A line of text that goes on for a while.\nAnd another." })
      view.ask("browse", { item: "a" }, "push")
      rt.last().done("page", { title: "An article", sections: sections })
      guide.touchMode = true
      var pg = null
      tryVerify(function() { pg = find(screen, "appPage"); return !!pg && pg.visible && view.pageMax > 0 }, 2000)
      verify(pg.interactive, "a finger scrolls it")
      var t = touchEvent(pg)
      var x = pg.width / 2, y = pg.height * 0.8
      t.press(0, pg, x, y).commit()
      for (var k = 1; k <= 12; k++) { t.move(0, pg, x, y - k * 30).commit(); wait(16) }
      t.release(0, pg, x, y - 360).commit()
      tryVerify(function() { return !pg.moving && pg.contentY > 0 }, 4000, "later parts in view")
      tryCompare(view, "pageY", pg.contentY, 1000, "the keys go on from there")
      var was = view.pageY
      view.move("down")
      verify(view.pageY > was, "down: further on, not back to the top")
      tryVerify(function() { return Math.abs(pg.contentY - view.pageY) < 1 || pg.contentY === Math.min(view.pageY, view.pageMax) }, 1000)
    }

    // ---- details ----------------------------------------------------------
    function test_details_ask_for_their_picture_and_backdrop() {
      var rt = open({ title: "The Long Night", subtitle: "", text: "An overview.", facts: [], actions: [], rows: [],
                      image: { token: "a".repeat(32) }, backdrop: { token: "b".repeat(32) } }, "detail")
      tryVerify(function() { return rt.asked.length === 2 }, 2000)
      compare(rt.asked.map(function(a) { return a.token }).sort(), ["a".repeat(32), "b".repeat(32)], "both are asked for")
    }

    function test_the_pictures_space_is_kept_then_shaped_then_closed() {
      var rt = open({ title: "Ep. 1", subtitle: "", text: "", facts: [], actions: [], rows: [],
                      image: { token: "c".repeat(32) }, backdrop: null }, "detail")
      var box = find(screen, "detailPicture")
      var p = Math.round(guide.u * guide.layout.libraryPosterWidth * 1.15)
      tryVerify(function() { return rt.asked.length === 1 }, 2000)
      compare([box.width, box.height], [p, Math.round(1.5 * p)], "kept at a poster's shape while it comes")
      rt.answer("c".repeat(32), root.pics + "wide.png")
      tryVerify(function() { return box.height < box.width }, 3000)
      compare(box.width, 2 * p, "a still lies wide")
      verify(Math.abs(box.width / box.height - 16 / 9) < 0.03)
      // another details screen whose picture can't come: the space closes
      view.stack = []
      rt.last().done("detail", { title: "Gone", subtitle: "", text: "", facts: [], actions: [], rows: [], image: { token: "d".repeat(32) }, backdrop: null })
      view.enter(guide.byUser)
      var rt2 = store.made[store.made.length - 1]
      open({ title: "Gone", subtitle: "", text: "x", facts: [], actions: [], rows: [], image: { token: "d".repeat(32) }, backdrop: null }, "detail")
      rt2 = store.made[store.made.length - 1]
      tryVerify(function() { return rt2.asked.some(function(a) { return a.token === "d".repeat(32) }) }, 2000)
      rt2.answer("d".repeat(32), "")
      tryVerify(function() { return find(screen, "detailPicture").width === 0 }, 2000)
    }

    function test_a_poster_stands_tall() {
      open({ title: "Movie", subtitle: "", text: "", facts: [], actions: [], rows: [], image: pic("poster.png"), backdrop: null }, "detail")
      var box = find(screen, "detailPicture")
      var p = Math.round(guide.u * guide.layout.libraryPosterWidth * 1.15)
      tryVerify(function() { return box.width === p && box.height === Math.round(1.5 * p) }, 3000)
    }

    function test_the_details_picture_is_asked_first_and_shaped_by_its_size() {
      var rt = open({ title: "Ep. 2", subtitle: "", text: "", facts: [], actions: [], rows: [],
                      image: { token: "e".repeat(32) }, backdrop: { token: "f".repeat(32) } }, "detail")
      tryVerify(function() { return rt.asked.length === 2 }, 2000)
      verify(rt.asked.every(function(a) { return a.prio === "focus" }), "a details screen's pictures come first")
      var box = find(screen, "detailPicture")
      var p = Math.round(guide.u * guide.layout.libraryPosterWidth * 1.15)
      // its size comes with its file: the space takes its shape before it's drawn
      rt.answer("e".repeat(32), root.pics + "nothing-here.png", 1920, 1080)
      tryVerify(function() { return box.width === 2 * p }, 2000)
      verify(Math.abs(box.width / box.height - 16 / 9) < 0.03, "a still's space from its size: " + box.width + "x" + box.height)
    }

    // ---- cards: milestone 1 ------------------------------------------------
    function test_a_card_shows_its_picture_for_the_rows_shape() {
      var both = function(id) {
        var it = item(id, { token: (id + "img").padEnd(32, "0") })
        it.images = { poster: { token: (id + "pos").padEnd(32, "0") }, wide: { token: (id + "wid").padEnd(32, "0") } }
        return it
      }
      var rt = open(screenOf([{ id: "posters", title: "P", layout: "row", shape: "poster", size: null, items: [both("a")] },
                              { id: "unsure", title: "U", layout: "row", items: [both("b")] }]))
      tryVerify(function() { return rt.asked.length >= 2 }, 2000)
      var asked = rt.asked.map(function(a) { return a.token })
      verify(asked.indexOf("apos".padEnd(32, "0")) >= 0, "a poster row's card: the item's poster")
      verify(asked.indexOf("aimg".padEnd(32, "0")) < 0 && asked.indexOf("awid".padEnd(32, "0")) < 0, "and not its other pictures")
      verify(asked.indexOf("bimg".padEnd(32, "0")) >= 0, "a row still working out its shape: its own image")
      compare(view.model.lines[0].shape, "poster", "the row as the app said")
      compare(view.model.lines[1].from, "auto")
    }

    function test_a_row_made_ahead_waits_until_its_shown() {
      // six rows still working out their shapes, their pictures not come:
      // the ones on the screen time out to wide at 2 s, the ones made
      // ahead below it don't start their clocks until they're shown
      var rows = []
      for (var r = 0; r < 6; r++) {
        var its = []
        for (var c = 0; c < 4; c++) its.push(item("r" + r + "c" + c, { token: ("r" + r + "c" + c).padEnd(32, "0") }))
        rows.push({ id: "row" + r, title: "Row " + r, layout: "row", items: its })
      }
      open(screenOf(rows))
      tryVerify(function() { return cards().length > 4 }, 2000)
      wait(2400)
      var mine = view.learned[view.shapeKey] || {}
      compare(mine["r:row0"], "wide", "on the screen, nothing came in 2 s: wide")
      var made = cards().map(function(c) { return c.line.id })
      verify(made.indexOf("row3") >= 0 && made.indexOf("row4") >= 0, "rows 3 and 4 are made ahead, below the screen")
      verify(mine["r:row3"] === undefined && mine["r:row4"] === undefined, "and not decided while they're off it: " + JSON.stringify(mine))
      var k3 = view.shapeKey + "\n" + "row3"
      verify(!view.sampling[k3] || view.sampling[k3].start === 0, "their clocks not started")
      // scrolled to: its clock starts, and it decides
      view.move("down"); view.move("down"); view.move("down")
      tryVerify(function() { return (view.learned[view.shapeKey] || {})["r:row3"] === "wide" }, 4000, "shown: decided in its turn")
    }

    function test_the_selected_card_is_wanted_first() {
      var rt = open(screenOf([{ id: "r", title: "R", layout: "row", items: [item("x", { token: "1".repeat(32) }), item("y", { token: "2".repeat(32) })] }]))
      tryVerify(function() { return rt.asked.length >= 2 }, 2000)
      var prioOf = function(tok) { var a = rt.asked.filter(function(x) { return x.token === tok }); return a.length ? a[a.length - 1].prio : "" }
      compare(prioOf("1".repeat(32)), "focus", "the selected card")
      compare(prioOf("2".repeat(32)), "visible", "the one beside it, on the screen")
      view.move("right")
      tryVerify(function() { return prioOf("2".repeat(32)) === "focus" }, 2000, "the selection moved: its picture is wanted first now")
      verify(rt.asked[rt.asked.length - 1].epoch > rt.asked[0].epoch, "under a newer demand")
    }

    // ---- cards --------------------------------------------------------------
    function test_a_row_learns_posters_and_fills_them() {
      open(screenOf([{ id: "movies", title: "Movies", layout: "row", items: [item("m1", pic("poster.png")), item("m2", pic("poster.png")), item("m3", pic("poster.png")), item("m4", pic("poster.png"))] }]))
      tryVerify(function() { return view.model.lines.length === 1 && view.model.lines[0].shape === "poster" }, 3000)
      var line = view.model.lines[0]
      compare(line.cardH, Math.round(line.cardW * 1.5), "a 2:3 box")
      compare(line.fit, "fill")
      tryVerify(function() { var c = cards(); return c.length > 0 && c[0].cardH === line.cardH }, 2000)
    }

    function test_a_learned_square_shows_a_picture_whole() {
      // two squares and a wide picture: the row learns square, drawn whole
      open(screenOf([{ id: "logos", title: "Logos", layout: "row", items: [item("s1", pic("square.png")), item("s2", pic("square.png")), item("w1", pic("wide.png"))] }]))
      tryVerify(function() { return view.model.lines.length === 1 && view.model.lines[0].shape === "autoSquare" }, 3000)
      compare(view.model.lines[0].fit, "fit")
      var wide = null
      tryVerify(function() { wide = cards().filter(function(c) { return c.modelData.id === "w1" && c.cardH === view.model.lines[0].cardH })[0]; return !!wide }, 2000)
      wait(300)
      var img = grabImage(root.Window.window.contentItem)
      // whole: green across the middle, the card's own fill above and below it
      var mid = pixelOf(img, wide, Math.round(wide.width / 2), Math.round(wide.cardH / 2))
      var top = pixelOf(img, wide, Math.round(wide.width / 2), 4)
      verify(mid.g > 0.6 && mid.r < 0.3, "the picture across the middle: " + mid)
      verify(!(top.g > 0.6 && top.r < 0.3), "not cropped to fill: the top isn't the picture: " + top)
    }

    // under a radius, a circle, a slant or a path of the theme's, the
    // picture is cut to the box: drawn through the box's mask
    function shapes_data() {
      return [
        { tag: "radius", style: { radius: 2 }, learned: "poster" },
        { tag: "circle", style: {}, learned: "circle" },
        { tag: "slant", style: { shape: "slant", slant: 1 }, learned: "poster" },
        { tag: "path", style: { shape: "path", path: "M12 0 L100 0 L100 100 L0 100 L0 12 Z" }, learned: "poster" }
      ]
    }
    function showShape(data) {
      guide.elementOverrides = ({ posterCard: data.style, "posterCard:current": data.style })
      view.learned = ({ "bundled\ntv.example.app": { "r:movies": data.learned } })
      open(screenOf([{ id: "movies", title: "Movies", layout: "row", items: [item("m1", pic("poster.png")), item("m2", pic("poster.png")), item("m3", pic("poster.png"))] }]))
      var c = null
      tryVerify(function() { c = cards().filter(function(x) { return x.modelData.id === "m2" && x.cardH === view.model.lines[0].cardH })[0]; return !!c }, 2000)
      return c
    }
    function test_pictures_are_cut_to_the_box_data() { return shapes_data() }
    function test_pictures_are_cut_to_the_box(data) {
      var c = showShape(data)
      var area = findAll(c, function(x) { return x.sized !== undefined && x.spec !== undefined })[0]
      tryVerify(function() { return area.status === Image.Ready }, 3000)
      verify(area.layer.enabled, "the picture goes through the box's mask (" + data.tag + ")")
    }
    // the pixels themselves: shader effects don't run in Qt's software
    // renderer (QT_QPA_PLATFORM=offscreen), so this needs a GPU one
    // (QT_QPA_PLATFORM=wayland)
    function test_corners_are_hidden_on_screen_data() { return shapes_data() }
    function test_corners_are_hidden_on_screen(data) {
      if (GraphicsInfo.api === GraphicsInfo.Software) skip("needs a GPU renderer: run with QT_QPA_PLATFORM=wayland")
      var c = showShape(data)
      wait(300)
      var img = grabImage(root.Window.window.contentItem)
      var center = pixelOf(img, c, Math.round(c.width / 2), Math.round(c.cardH / 2))
      var corner = pixelOf(img, c, 1, 1)   // the top left: cut by each of them
      verify(center.r > 0.7 && center.g < 0.3, "the picture in the middle: " + center)
      verify(!(corner.r > 0.7 && corner.g < 0.3), "the corner is hidden (" + data.tag + "): " + corner)
    }

    // ---- the colors behind are the colors drawn -----------------------------
    // a gradient whose ends are see-through by different amounts, drawn by
    // the real Box over the window's color, is the model's colors all along it
    function test_the_colors_behind_are_what_is_drawn_data() {
      return [
        { tag: "half red to blue, over white", from: "#80ff0000", to: "#ff0000ff", base: "#ffffff" },
        { tag: "see-through gold fading out, over navy", from: "#c0ffd700", to: "transparent", base: "#030a2b" },
        { tag: "faint black to near white, over gray", from: "#20000000", to: "#e0ffffff", base: "#808080" }
      ]
    }
    function test_the_colors_behind_are_what_is_drawn(data) {
      fillBase.color = data.base
      fillBox.s = { fill: { from: data.from, to: data.to, direction: "down" } }
      fillBase.visible = true
      wait(300)
      var img = grabImage(root.Window.window.contentItem)
      fillBase.visible = false
      var model = Looks.behindColors({ fill: fillBox.s.fill, base: data.base })
      for (var i = 1; i < 16; i++) {
        var p = pixelOf(img, fillBox, Math.round(fillBox.width / 2), fillBox.height * i / 16)
        var m = Qt.color(model[i])
        verify(Math.abs(p.r - m.r) <= 2 / 255 && Math.abs(p.g - m.g) <= 2 / 255 && Math.abs(p.b - m.b) <= 2 / 255,
               data.tag + ", " + i + "/16 along: drawn " + p + ", the model " + model[i])
      }
    }

    // ---- the focus ring and the selected title -----------------------------
    function test_the_ring_and_title_survive_hostile_themes() {
      // the current card's own border gone, the title the page's own color,
      // the accent the background's
      guide.elementOverrides = ({ "posterCard:current": { border: { width: 0, color: "none" } }, posterTitle: { text: { color: "#071447" } } })
      guide.colorOverrides = ({ accent: "#071447" })
      open(screenOf([{ id: "r", title: "R", layout: "row", items: [item("a", pic("wide.png")), item("b", pic("wide.png"))] }]))
      var c = null
      tryVerify(function() { c = cards().filter(function(x) { return x.current })[0]; return !!c }, 2000)
      var ring = find(c, "focusRing")
      verify(ring.visible, "the ring is always on the selected card")
      verify(ring.border.width >= Math.ceil(guide.u * 0.15), "at least 0.15 units wide")
      compare(String(ring.border.color), "#f2f4ff", "an accent like the background gives way to the ink")
      var title = find(c, "cardTitle")
      compare(String(title.color), "#f2f4ff", "the title like the page gives way to the ink")
      compare(title.opacity, 1)
      // a see-through title color is drawn opaque, in a color that reads
      guide.elementOverrides = ({ posterTitle: { text: { color: "#33f2f4ff" } } })
      tryVerify(function() { return String(find(c, "cardTitle").color) === "#f2f4ff" }, 1000)
      // the ring's own accent where it reads
      guide.colorOverrides = ({})
      tryVerify(function() { return String(find(c, "focusRing").border.color) === "#ffd23f" }, 1000)
    }

    function test_the_ring_follows_the_selection() {
      open(screenOf([{ id: "r", title: "R", layout: "row", items: [item("a", null), item("b", null)] }]))
      tryVerify(function() { return cards().length === 2 }, 2000)
      view.move("right")
      tryVerify(function() { var b = cards().filter(function(x) { return x.modelData.id === "b" })[0]; return b && find(b, "focusRing").visible }, 1000)
      var a = cards().filter(function(x) { return x.modelData.id === "a" })[0]
      verify(!find(a, "focusRing").visible)
    }

    // accent, ink and page all the same gray: the ring still shows, with a halo
    function test_the_ring_shows_when_nothing_reads() {
      guide.colorOverrides = ({ accent: "#777777", text: "#777777" })
      guide.elementOverrides = ({ background: { fill: "#777777" } })
      open(screenOf([{ id: "r", title: "R", layout: "row", items: [item("a", null), item("b", null)] }]))
      var c = null
      tryVerify(function() { c = cards().filter(function(x) { return x.current })[0]; return !!c }, 2000)
      verify(find(c, "focusRing").visible)
      var halo = find(c, "focusHalo")
      verify(halo.visible, "a halo where the ring's color doesn't read")
      verify(String(halo.border.color) === "#000000" || String(halo.border.color) === "#ffffff")
    }

    // a card with no picture first, then two posters: the row still learns
    // posters (the row's count comes with every report, so the first report
    // doesn't decide alone)
    function test_a_row_starting_without_a_picture_learns_posters() {
      open(screenOf([{ id: "mixed", title: "M", layout: "row", items: [item("n0", null), item("p1", pic("poster.png")), item("p2", pic("poster.png"))] }]))
      tryVerify(function() { return view.model.lines.length === 1 && view.model.lines[0].shape === "poster" }, 3000)
    }

    // a report from a card made for another app is dropped
    function test_a_report_for_another_app_is_dropped() {
      open(screenOf([{ id: "movies", title: "Movies", layout: "row", items: [item("m1", null), item("m2", null), item("m3", null)] }]))
      view.pictureSettled("movies", 0, 2 / 3, 3, "file:0\nother.app", view.epoch)
      view.pictureSettled("movies", 1, 2 / 3, 3, "file:0\nother.app", view.epoch)
      view.pictureSettled("movies", 2, 2 / 3, 3, "file:0\nother.app", view.epoch)
      wait(100)
      verify(view.model.lines[0].shape !== "poster", "not counted for this app")
    }

    // a gradient page: a title that reads only at its ends gives way, with a plate
    function test_the_title_reads_all_along_a_gradient() {
      guide.elementOverrides = ({ background: { fill: { from: "#000000", to: "#ffffff", direction: "down" } }, posterTitle: { text: { color: "#757575" } } })
      open(screenOf([{ id: "r", title: "R", layout: "row", items: [item("a", null), item("b", null)] }]))
      var c = null
      tryVerify(function() { c = cards().filter(function(x) { return x.current })[0]; return !!c }, 2000)
      verify(String(find(c, "cardTitle").color) !== "#757575", "not the gray that only reads at the gradient's ends")
      verify(c.selectedTitle.plate !== "", "nothing reads against all of it: a backing plate")
    }

    // a list row whose picture the helper can't get, after it was made, still
    // counts toward its row's shape (as a failure)
    function test_a_list_rows_late_failure_counts() {
      var rt = open(screenOf([{ id: "l", title: "L", layout: "list", items: [
        item("f0", { token: "1".repeat(32) }), item("f1", { token: "2".repeat(32) }), item("p2", pic("poster.png")), item("w3", pic("wide.png")), item("w4", pic("wide.png"))] }]))
      tryVerify(function() { return rt.asked.length >= 2 }, 2000)
      rt.answer("1".repeat(32), "")
      rt.answer("2".repeat(32), "")
      // positions 0 and 1 failed, 2 a poster: the first three settled say poster
      tryVerify(function() { return view.model.lines.length === 1 && view.model.lines[0].shape === "poster" }, 3000)
    }

    // shapes learned for one source of an app don't carry to another
    function test_learned_shapes_stay_with_their_source() {
      open(screenOf([{ id: "movies", title: "Movies", layout: "row", items: [item("m1", pic("poster.png")), item("m2", pic("poster.png")), item("m3", pic("poster.png"))] }]))
      tryVerify(function() { return view.model.lines[0].shape === "poster" }, 3000)
      store.source = "file:0123456789abcdef"
      compare(view.model.lines[0].shape, "wide", "the same id from a file hasn't learned anything")
      store.source = "bundled"
      compare(view.model.lines[0].shape, "poster")
    }

    // ---- a big grid ----------------------------------------------------------
    function test_a_big_grid_makes_only_the_cards_on_the_screen() {
      var many = []
      for (var i = 0; i < 200; i++) many.push(item("g" + i, null))
      open(screenOf([{ id: "all", title: "All", layout: "grid", items: many }]))
      var grid = null
      tryVerify(function() { grid = find(screen, "appGrid"); return !!grid && grid.count === 200 }, 2000)
      wait(100)
      var made = cards().length
      verify(made > 0 && made <= 60, "only the cards on the screen and a line more: " + made)
      // scrolling down keeps it small, and the selection's card is made
      for (var k = 0; k < 20; k++) view.move("down")
      wait(400)
      made = cards().length
      verify(made <= 60, "still small after scrolling: " + made)
      var sel = cards().filter(function(x) { return x.current })[0]
      verify(!!sel, "the selected card exists")
      // no gap: every card whose cell is on the screen exists
      var line = view.model.lines[0]
      var shown = []
      var made2 = {}
      cards().forEach(function(c) { made2[c.modelData.id] = true })
      var lines = find(screen, "appLines")
      for (var i = 0; i < 200; i++) {
        var r = Math.floor(i / line.cols)
        var y = lines.mapToItem(screen, 0, line.y + Math.round(guide.u * 0.5) + view.model.geometry.titleH + r * line.cellH - lines.contentY).y
        var onScreen = y + line.cardH > lines.mapToItem(screen, 0, 0).y && y < lines.mapToItem(screen, 0, lines.height).y
        if (onScreen) shown.push("g" + i)
      }
      verify(shown.length > 0, "some cards are on the screen")
      var missing = shown.filter(function(id) { return !made2[id] })
      compare(missing, [], "every card on the screen exists")
    }

    // ---- milestone 2: the looks ------------------------------------------------
    function full(id) {
      var it = item(id, pic("wide.png"))
      it.images = { poster: pic("poster.png"), wide: pic("wide.png"), backdrop: pic("wide.png") }
      it.meta = "2019 · 2 h 10 min · PG-13"
      it.text = "What " + id + " is about, in a line or two: the top of the screen and a featured row show it."
      return it
    }
    function lookScreen() {
      var heroes = [0, 1, 2].map(function(i) { var it = full("hero" + i); it.title = "Featured " + i; if (i === 0) it.images.logo = pic("square.png"); return it })
      var cont = [0, 1, 2, 3].map(function(i) { var it = full("c" + i); it.progress = 0.4; it.watched = i === 1; return it })
      var latest = [0, 1, 2, 3, 4, 5].map(function(i) { return full("l" + i) })
      var logos = [0, 1, 2].map(function(i) { var it = item("team" + i, pic("square.png")); it.images = { logo: pic("square.png") }; return it })
      return screenOf([{ id: "featured", title: "Featured", layout: "hero", items: heroes },
                       { id: "continue", title: "Continue watching", layout: "row", shape: "wide", items: cont },
                       { id: "latest", title: "Recently added", layout: "row", shape: "poster", items: latest },
                       { id: "teams", title: "Teams", layout: "row", shape: "logo", items: logos }])
    }
    function setLook(name) { guide.currentTheme = { id: "test", apps: name ? { look: name } : {} } }
    function line(id) { return view.model.lines.filter(function(l) { return l.id === id })[0] }

    function test_each_look_draws_as_the_plan_says_data() {
      return [{ tag: "classic" }, { tag: "posters" }, { tag: "cinematic" }, { tag: "wall" }, { tag: "compact" }]
    }
    function test_each_look_draws_as_the_plan_says(d) {
      setLook(d.tag)
      open(lookScreen())
      compare(view.model.screen.look, d.tag)
      var wantTop = d.tag === "cinematic" || d.tag === "wall"
      tryVerify(function() { return find(screen, "appTop").visible === wantTop }, 2000, "the top shows what's selected: " + wantTop)
      compare(line("featured").layout, "hero", "a look never re-lays-out a row")
      compare(line("teams").shape, "logo", "a row of logos stays logos")
      compare(line("continue").shape, { classic: "wide", posters: "poster", cinematic: "wide", wall: "poster", compact: "wide" }[d.tag])
      compare(line("latest").shape, { classic: "poster", posters: "poster", cinematic: "wide", wall: "poster", compact: "poster" }[d.tag])
      compare(line("latest").size, { classic: "medium", posters: "medium", cinematic: "large", wall: "small", compact: "small" }[d.tag])
      compare(line("latest").titles, { classic: "below", posters: "below", cinematic: "selected", wall: "off", compact: "below" }[d.tag])
      compare(view.model.screen.background.mode, { classic: "details", posters: "details", cinematic: "focus", wall: "focus", compact: "none" }[d.tag], "the background each look gives")
      verify(find(screen, "opaqueBase").visible && find(screen, "themeColors").visible, "on an opaque base, the theme's colors")
      var strip = find(screen, "identityStrip")
      verify(strip.visible && strip.height >= Math.ceil(guide.u * 3.2), "the strip, always")
    }

    function test_titles_under_cards_and_the_top() {
      setLook("cinematic")
      open(lookScreen())
      view.move("down")                                       // to Continue watching
      tryVerify(function() { return cards().filter(function(c) { return c.line.id === "continue" }).length >= 3 }, 2000)
      var cs = cards().filter(function(c) { return c.line.id === "continue" })
      verify(cs.some(function(c) { return c.current && c.titled }), "Cinematic: the selected card's title")
      verify(cs.filter(function(c) { return !c.current }).every(function(c) { return !c.titled }), "and only it")
      compare(find(screen, "topTitle").text, "c0", "the top tells what's selected")
      compare(find(screen, "topMeta").text, "2019 · 2 h 10 min · PG-13")
      verify(find(screen, "topText").text.indexOf("What c0 is about") === 0)
      compare(find(screen, "topKicker").text, "Continue watching", "its row's name")
      setLook("wall")
      tryVerify(function() { return cards().filter(function(c) { return c.line.id === "continue" }).every(function(c) { return !c.titled }) }, 2000, "Wall: none (the top shows it)")
      compare(line("continue").captionH, 0, "and no room kept for them")
      setLook("classic")
      tryVerify(function() { return cards().filter(function(c) { return c.line.id === "continue" }).every(function(c) { return c.titled }) }, 2000, "Classic: every card")
      verify(!find(screen, "appTop").visible)
      // a watched one is marked
      var w = cards().filter(function(c) { return c.modelData.id === "c1" })[0]
      verify(find(w, "watchedMark").visible, "✓ on the watched one")
      verify(!find(cards().filter(function(c) { return c.modelData.id === "c0" })[0], "watchedMark").visible)
    }

    function test_a_look_change_keeps_the_selection_and_asks_again() {
      setLook("classic")
      var rt = open(lookScreen())
      view.move("down")
      view.move("right")
      var was = view.sel
      var before = rt.demand
      var stack = view.stack.length
      setLook("wall")
      compare([view.sel.row, view.sel.item], [was.row, was.item], "the same row and item")
      verify(rt.demand > before, "a new look is a new demand")
      compare(view.stack.length, stack, "drawn again in place: nothing reloaded")
      compare(rt.calls.length, 1, "nothing asked of the app")
    }

    function test_the_focus_background_rests_and_never_shows_the_last_picture() {
      setLook("cinematic")
      var t = function(n) { return n.padEnd(32, "0") }
      var its = [0, 1, 2].map(function(i) { var it = item("f" + i, null); it.images = { backdrop: { token: t("bd" + i) } }; return it })
      its.push(item("bare", null))
      var rt = open(screenOf([{ id: "r", title: "R", layout: "row", items: its }]))
      var bd = find(screen, "appBackdrop")
      var asked = function(n) { return rt.asked.filter(function(a) { return a.token === t(n) && a.prio === "focus" }).length }
      wait(120)
      compare(asked("bd0"), 0, "not before the cursor has rested 300 ms")
      tryVerify(function() { return asked("bd0") === 1 }, 1000, "rested: its backdrop is wanted, first")
      rt.answer(t("bd0"), root.pics + "wide.png", 1920, 1080)
      tryVerify(function() { return find(screen, "focusBlur").active }, 2000, "drawn, blurred")
      // passing over an item quicker than 300 ms never fetches its picture
      view.move("right")
      wait(100)
      view.move("right")
      tryVerify(function() { return asked("bd2") === 1 }, 1000)
      compare(asked("bd1"), 0, "passed over: never asked for")
      // an item with neither picture: the theme's colors at once, never the last one
      view.move("right")
      tryVerify(function() { return !find(screen, "focusBlur").active && bd.shownImg === null }, 1000)
      // a new view calls a waiting change off
      view.move("left")
      wait(80)
      view.enter(guide.byUser)
      rt.last().done("screen", screenOf([{ id: "x", title: "X", layout: "row", items: [item("x1", null)] }]))
      wait(450)
      compare(bd.shownImg, null, "the change waiting for the screen before was called off")
    }

    function test_a_featured_row() {
      var rt = open(lookScreen())
      var hero = null
      tryVerify(function() { hero = find(screen, "appHero"); return !!hero }, 2000)
      tryVerify(function() { return find(hero, "heroLogo").visible }, 3000, "its title logo, whole")
      verify(!find(hero, "heroTitle").parent.visible, "in place of its title")
      verify(find(hero, "focusRing").visible, "the cursor is on it: the guide's ring")
      compare(findAll(find(hero, "heroDots"), function(x) { return x.radius !== undefined && x.width === Math.round(guide.u * 0.7) }).length, 3, "a dot an item")
      view.move("right")
      tryVerify(function() { return find(hero, "heroTitle").text === "Featured 1" && find(hero, "heroTitle").parent.visible }, 2000, "→: the next item, its title (it has no logo)")
      compare(find(hero, "heroMeta").text, "2019 · 2 h 10 min · PG-13")
      verify(find(hero, "heroText").text.length > 0)
      view.move("down")
      verify(!find(hero, "focusRing").visible)
      compare(find(hero, "heroTitle").text, "Featured 1", "it keeps showing the item it was on")
      view.move("up")
      compare(view.sel.item, "hero1")
      compare(view.enterTarget ? 0 : 0, 0)
    }

    function test_details_classic_and_cinematic() {
      var d = { title: "The Long Night", subtitle: "", text: "An overview of it, in a few lines.", facts: [{ label: "Director", value: "Someone" }],
                actions: [{ id: "p", label: "Play", kind: "play" }], rows: [], image: pic("poster.png"), backdrop: pic("wide.png"),
                logo: pic("square.png"), meta: "2019 · 2 h 10 min", chips: ["Drama", "4K"], style: "cinematic" }
      setLook("compact")
      open(d, "detail")
      compare(view.model.detailStyle, "classic", "Compact sets its own")
      verify(!find(screen, "cinematicHead").visible)
      tryVerify(function() { return find(screen, "detailPicture").width > 0 }, 2000, "Classic: its picture")
      compare(find(screen, "detailMeta").text, "2019 · 2 h 10 min")
      compare(findAll(screen, function(x) { return x.objectName === "detailChip" && x.visible }).length, 2, "its chips")
      setLook("classic")
      compare(view.model.detailStyle, "cinematic", "Classic follows the app's style")
      tryVerify(function() { return find(screen, "cinematicHead").visible }, 2000)
      tryVerify(function() { return find(screen, "detailLogo").visible }, 3000, "its title logo")
      verify(!find(screen, "cinematicTitle").visible, "in place of the title")
      compare(find(screen, "detailPicture").width, 0, "no poster")
      tryVerify(function() { return find(screen, "cinematicBackdrop").visible }, 3000, "its backdrop across the screen")
      verify(find(screen, "cinematicShade").visible, "under its shade")
      compare(findAll(screen, function(x) { return x.objectName === "detailChip" && x.visible }).length, 2)
    }

    function test_the_strip_and_the_floors_under_hostile_themes_data() {
      // every background (details, focus, none), both details pages, and a featured row
      return [{ tag: "classic", look: "classic" }, { tag: "posters", look: "posters" }, { tag: "cinematic", look: "cinematic" },
              { tag: "wall", look: "wall" }, { tag: "compact", look: "compact" },
              { tag: "classic details", look: "compact", details: true }, { tag: "cinematic details", look: "cinematic", details: true }]
    }
    function test_the_strip_and_the_floors_under_hostile_themes(d) {
      guide.colorOverrides = { text: "#00000000", bgTop: "#ffffff", accent: "#ffffff" }
      guide.elementOverrides = { appCardTitle: { text: { size: 0.2, color: "#00000000" } }, appCardSub: { text: { size: 0.2 } },
                                 appTopTitle: { text: { size: 0.2, color: "#00000000" } }, "appCard:current": { grow: 1, padding: 10 },
                                 appCard: { padding: 10, shape: "path", path: "M0,0 L100,0 L50,100 Z" }, appBadge: { text: { size: 0.2 } } }
      store.from = "file"
      setLook(d.look)
      if (d.details) open({ title: "The Long Night", subtitle: "", text: "An overview.", facts: [], actions: [{ id: "p", label: "Play", kind: "play" }],
                            rows: [{ id: "more", title: "More", layout: "row", items: [full("m0"), full("m1")] }], image: pic("poster.png"),
                            backdrop: pic("wide.png"), logo: pic("square.png"), meta: "2019", chips: ["Drama"], style: "cinematic" }, "detail")
      else open(lookScreen())
      var strip = find(screen, "identityStrip")
      compare(String(strip.color), "#101118", "the guide's own fill: the theme's text wouldn't read")
      compare(String(find(strip, "stripName").color), "#f2f2f2")
      verify(find(strip, "stripName").font.pixelSize >= guide.u * 1.2, "its name at least 1.2 units")
      verify(strip.height >= Math.ceil(guide.u * 3.2), "at least 3.2 units high")
      var badge = find(strip, "originBadge")
      verify(badge.visible, "a badge for a file install")
      compare(badge.color.a, 1, "solid")
      verify(strip.z > 0 && strip.opacity === 1 && strip.visible)
      // nothing the app or the theme draws covers it: the body starts under it and clips, and every
      // picture behind the screen is under it in the drawing order
      var lines = find(screen, "appLines")
      verify(lines.parent.clip && lines.parent.mapToItem(screen, 0, 0).y >= strip.height, "a grown card can't reach it")
      verify(find(screen, "appBackdrop").z < strip.z, "the pictures behind are under it")
      // the floors, on the cards there are
      view.move("down")                                      // a row of cards (on a details page, past its buttons)
      tryVerify(function() { return cards().length > 0 }, 2000)
      cards().forEach(function(c) {
        verify(c.titleStyle.text.size * guide.u >= Math.max(12, 0.7 * guide.u) - 0.01, "card text at least max(12 px, 0.7 units)")
        verify(c.subStyle.text.size * guide.u >= Math.max(12, 0.7 * guide.u) - 0.01)
        verify(c.badgeStyle.text.size * guide.u >= Math.max(12, 0.7 * guide.u) - 0.01)
      })
      var sel = cards().filter(function(c) { return c.current })[0]
      if (sel && sel.titled) verify(find(sel, "cardTitle").color.a === 1, "the selected title drawn opaque")
      if (view.model.screen.topShown) {
        var top = find(screen, "topTitle")
        verify(top.font.pixelSize >= 1.4 * guide.u - 0.5, "the top title at least 1.4 units: " + top.font.pixelSize)
        verify(top.color.a === 1, "drawn opaque: a see-through title gives way")
      }
    }

    // the top of the screen coming takes room from the rows: the selected
    // one stays in view
    function test_the_selection_stays_in_view_when_the_top_comes() {
      setLook("classic")
      open(lookScreen())
      view.move("down")
      view.move("down")                                           // Recently added
      var lines = find(screen, "appLines")
      var inView = function() {
        var l = line(view.sel.row)
        return l.y >= lines.contentY - 1 && l.y + l.height <= lines.contentY + lines.height + 1
      }
      tryVerify(inView, 2000, "in view in Classic")
      setLook("wall")                                             // the top comes, the rows get less room
      tryVerify(function() { return find(screen, "appTop").visible }, 2000)
      tryVerify(inView, 2000, "still in view with the top shown")
    }

    // the guide's ring round the selected card is whole: nothing clips it,
    // even under a theme that makes it grow all it can
    function test_the_ring_is_whole_in_a_row() {
      guide.elementOverrides = { "appCard:current": { grow: 1 } }
      setLook("cinematic")
      open(lookScreen())
      view.move("down")
      var c = null
      tryVerify(function() { c = cards().filter(function(x) { return x.current })[0]; return !!c }, 2000)
      wait(300)                                                   // its grow, animated
      compare(find(c, "focusRing").parent.scale, 1.15, "held to 15%")
      var list = c.parent.parent
      compare(list.objectName, "rowCards")
      var halo = find(c, "focusHalo")
      var tl = halo.mapToItem(list, 0, 0), br = halo.mapToItem(list, halo.width, halo.height)
      verify(tl.y >= 0 && br.y <= list.height, "the ring and its halo inside what the row clips: " + tl.y + " to " + br.y + " of " + list.height)
    }

    // ---- milestone 3: your rows, live -------------------------------------------------
    function selectedId() { var l = screen.ls[screen.sel.line]; return l && l.items ? l.items[screen.sel.col].id : "" }
    function test_hiding_reordering_and_relaying_rows_keeps_the_selection() {
      var rows = ["a", "b", "c"].map(function(r) { return { id: r, title: r.toUpperCase(), layout: "row", items: [0, 1, 2].map(function(i) { return item(r + i, null) }) } })
      open(screenOf(rows))
      view.move("down")
      view.move("right")
      compare(selectedId(), "b1", "on the middle row's second item")
      screensStub.entry = { incarnation: "0123456789abcdef", rows: { "r:a": { show: false } } }
      compare(selectedId(), "b1", "a row above hidden: the same item")
      compare(screen.ls.length, 2)
      screensStub.entry = { incarnation: "0123456789abcdef", order: ["c", "b", "a"] }
      compare(screen.ls.map(function(l) { return l.id }).join(","), "c,b,a", "your order first")
      compare(selectedId(), "b1", "reordered: the same item")
      screensStub.entry = { incarnation: "0123456789abcdef", rows: { "r:b": { layout: "grid" } } }
      compare(screen.ls.filter(function(l) { return l.id === "b" })[0].layout, "grid")
      compare(selectedId(), "b1", "re-laid out: the same item")
      screensStub.entry = { incarnation: "0123456789abcdef", rows: { "r:b": { show: false } } }
      verify(["a", "c"].indexOf(screen.ls[screen.sel.line].id) >= 0, "its row hidden: a row beside it")
      verify(view.move("down") || view.move("up"), "and the arrows still go")
      screensStub.entry = { incarnation: "0123456789abcdef", rows: { "r:a": { show: false }, "r:b": { show: false }, "r:c": { show: false } } }
      var shown = function(it) {
        if (!it || !it.visible) return null
        if (typeof it.text === "string" && it.text.indexOf("Every row is hidden") === 0) return it
        var kids = it.children || []
        for (var i = 0; i < kids.length; i++) { var f = shown(kids[i]); if (f) return f }
        return null
      }
      verify(shown(screen), "every row hidden: the screen says how to bring them back")
      screensStub.entry = null
      compare(screen.ls.length, 3, "back as the app has them")
    }

    // ---- milestone 2, ycodex round 1 ---------------------------------------------
    function test_the_shade_is_never_under_the_floor() {
      // a see-through shade color can't take the floor away
      guide.elementOverrides = { appShade: { color: "#00000000" } }
      setLook("cinematic")
      open(lookScreen())
      view.move("down")
      tryVerify(function() { return find(screen, "focusBlur").active && find(screen, "appBackdrop").focusDrawn }, 3000)
      var bd = find(screen, "appBackdrop")
      compare(bd.shadeSolid.a, 1, "drawn opaque")
      verify(bd.dim >= 0.3)
      guide.elementOverrides = ({})
    }

    // a theme's picture behind the guide is lifted to the floor from what its
    // own shade really darkens: a see-through bgBottom darkens by its alpha only.
    // The top-up is drawn in the app shade's color: rows with that color
    // apart from bgBottom's check the two are modelled as one shade, mixed
    function test_the_guides_theme_picture_is_lifted_to_the_floor_data() {
      return [{ tag: "dim 0, opaque", dim: 0, bottom: "#030a2b" }, { tag: "dim 0.2, opaque", dim: 0.2, bottom: "#030a2b" },
              { tag: "dim 0.2, transparent bgBottom", dim: 0.2, bottom: "#00000000" }, { tag: "dim 0.2, half bgBottom", dim: 0.2, bottom: "#80030a2b" },
              { tag: "dim 0.5: already there", dim: 0.5, bottom: "#030a2b" },
              { tag: "dim 0.2, a red top-up over a blue shade", dim: 0.2, bottom: "#0000ff", shade: "#ff0000" },
              { tag: "dim 0.1, a white top-up, white accent and text", dim: 0.1, bottom: "#000000", shade: "#ffffff", accent: "#ffffff", text: "#ffffff" }]
    }
    function test_the_guides_theme_picture_is_lifted_to_the_floor(d) {
      var colors = { bgBottom: d.bottom }
      if (d.accent) colors.accent = d.accent
      if (d.text) colors.text = d.text
      guide.colorOverrides = colors
      if (d.shade) guide.elementOverrides = { appShade: { color: d.shade } }
      guide.backgroundSource = "file://" + root.pics + "wide.png"
      guide.bgDim = d.dim
      guide.bgFloored = true
      setLook("classic")
      open(lookScreen())
      var pic = find(screen, "guidePicture")
      tryVerify(function() { return pic.visible }, 3000, "the guide's picture, drawn on the app's screen")
      var bottomAlpha = Looks.rgba(d.bottom).a
      var guideDark = d.dim * bottomAlpha
      var top = find(screen, "guideTopUp")
      var lifted = top.visible ? top.opacity : 0
      var total = 1 - (1 - guideDark) * (1 - lifted)
      verify(total >= 0.3 - 0.005, "at least 30% shade in all: " + total)
      if (guideDark >= 0.3) verify(!top.visible, "already there: nothing added")
      // what's behind is modelled as it's drawn: both shades, as one
      var bd = find(screen, "appBackdrop")
      if (d.shade) compare(bd.shadeHex, d.shade, "the top-up is in the app shade's own color")
      var want = Looks.stackShades(d.bottom, d.dim, bd.shadeHex, lifted)
      verify(bd.behind.picture)
      verify(Math.abs(bd.behind.dim - want.alpha) < 0.001 && bd.behind.dimColor === want.color, JSON.stringify(bd.behind) + " " + JSON.stringify(want))
      if (d.shade && lifted > 0) verify(want.color !== d.shade && want.color !== Looks.hex(Looks.rgba(d.bottom)), "mixed, neither color alone: " + want.color)
      // the ring and the selected title read on what that gives
      var page = Looks.behindColors(bd.behind)
      verify(Looks.worst(screen.ringColor, page) >= 3 || screen.ringHalo !== "", "the ring reads on it: " + JSON.stringify(page))
      verify(Looks.worst(screen.selectedTitle.color, page) >= 4.5 || screen.selectedTitle.plate !== "", "and the selected title")
      // your own picture goes as you set it
      guide.bgFloored = false
      verify(!find(screen, "guideTopUp").visible)
      guide.backgroundSource = ""
      guide.bgDim = 0.6
      guide.colorOverrides = ({})
      guide.elementOverrides = ({})
    }

    // the screen's backdrop covers the whole window, the rail's strip too: a
    // note of the guide's drawn before it (the key hints note) never shows on
    // an app's screen, so it can't be in a picture of it
    function test_a_guide_note_drawn_before_it_is_under_it() {
      guide.railSpace = 96
      screen.anchors.leftMargin = 96
      guideNote.visible = true
      open(screenOf([{ id: "r", title: "R", layout: "row", items: [item("n0", null), item("n1", null)] }]))
      wait(300)
      var red = function(c) { return c.r > 0.9 && c.g < 0.1 && c.b < 0.1 }
      var img = grabImage(root.Window.window.contentItem)
      var inStrip = pixelOf(img, guideNote, 16, 24)        // in the rail's strip
      var underIt = pixelOf(img, guideNote, 150, 24)       // under the screen itself
      verify(!red(inStrip), "not in the rail's strip: " + inStrip)
      verify(!red(underIt), "nor under the screen: " + underIt)
      screen.visible = false
      wait(50)
      img = grabImage(root.Window.window.contentItem)
      verify(red(pixelOf(img, guideNote, 16, 24)) && red(pixelOf(img, guideNote, 150, 24)), "without the screen it would show")
      screen.visible = true
      guideNote.visible = false
      screen.anchors.leftMargin = 0
      guide.railSpace = 0
    }

    // under a see-through theme the base is still opaque, as the model says
    function test_a_see_through_theme_still_draws_an_opaque_base() {
      guide.colorOverrides = { bgBottom: "#00000000", bgTop: "#00000000", accent: "#ffffff", text: "#ffffff" }
      guide.elementOverrides = { background: { fill: "#00000000" } }
      setLook("cinematic")
      open(screenOf([{ id: "r", title: "R", layout: "row", items: [item("n0", null), item("n1", null)] }]))
      wait(300)
      verify(find(screen, "opaqueBase").visible, "black, then the window's color: nothing under the screen shows")
      var page = Looks.behindColors(find(screen, "appBackdrop").behind)
      compare(page.indexOf("#000000") >= 0, true, "the model's page is the drawn black")
      verify(Looks.worst(screen.ringColor, page) >= 3 || screen.ringHalo !== "", "the ring reads on it")
      verify(Looks.worst(screen.selectedTitle.color, page) >= 4.5 || screen.selectedTitle.plate !== "", "and the selected title")
      guide.colorOverrides = ({})
      guide.elementOverrides = ({})
    }

    function test_the_ring_reads_against_whats_really_behind() {
      // a white page, white accent and text: with no picture drawn, the page is what's behind
      guide.colorOverrides = { bgTop: "#ffffff", bgBottom: "#ffffff", accent: "#ffffff", text: "#ffffff" }
      setLook("cinematic")
      var its = [0, 1].map(function(i) { return item("n" + i, null) })    // no backdrops: no picture ever
      open(screenOf([{ id: "r", title: "R", layout: "row", items: its }]))
      wait(400)
      var bd = find(screen, "appBackdrop")
      verify(!bd.behind.picture, "no picture is modelled when none is drawn")
      verify(Looks.contrast(screen.ringColor, "#ffffff") >= 3 || screen.ringHalo !== "", "the ring reads on the white page: " + screen.ringColor + " / " + screen.ringHalo)
    }

    function test_a_picture_that_cant_be_drawn_never_leaves_the_last_one() {
      setLook("cinematic")
      var a = item("a", null); a.images = { backdrop: pic("wide.png") }
      var b = item("b", null); b.images = { backdrop: pic("broken.png") }
      open(screenOf([{ id: "r", title: "R", layout: "row", items: [a, b] }]))
      var bd = find(screen, "appBackdrop")
      tryVerify(function() { return bd.focusDrawn }, 3000, "a's picture, drawn")
      view.move("right")
      tryVerify(function() { return bd.keyOf(bd.shownImg) === root.pics + "broken.png" }, 2000)
      wait(600)
      verify(!bd.focusDrawn, "b's can't be drawn: nothing is, never a's")
    }

    function test_moving_on_doesnt_ask_for_the_last_picture_again() {
      setLook("cinematic")
      var t = function(n) { return n.padEnd(32, "0") }
      var its = [0, 1].map(function(i) { var it = item("d" + i, null); it.images = { backdrop: { token: t("dm" + i) } }; return it })
      var rt = open(screenOf([{ id: "r", title: "R", layout: "row", items: its }]))
      tryVerify(function() { return rt.asked.some(function(a) { return a.token === t("dm0") && a.prio === "focus" }) }, 2000)
      var epoch = rt.demand
      view.move("right")                                          // dm0 never came; the demand moves on
      wait(100)
      verify(!rt.asked.some(function(a) { return a.token === t("dm0") && a.epoch > epoch }), "the old picture isn't asked for under the new demand")
    }

    function test_the_selected_card_and_button_are_over_their_neighbours() {
      setLook("cinematic")
      open(lookScreen())
      view.move("down")
      tryVerify(function() { return cards().some(function(c) { return c.current }) }, 2000)
      var cs = cards().filter(function(c) { return c.line.id === "continue" })
      verify(cs.filter(function(c) { return c.current }).every(function(c) { return c.z > 0 }), "the selected one raised")
      verify(cs.filter(function(c) { return !c.current }).every(function(c) { return c.z === 0 }))
      // a details page's buttons
      open({ title: "D", subtitle: "", text: "", facts: [], actions: [{ id: "a", label: "A", kind: "play" }, { id: "b", label: "B", kind: "action" }], rows: [], image: null, backdrop: null }, "detail")
      var rings = findAll(screen, function(x) { return x.objectName === "focusRing" && x.visible })
      verify(rings.length >= 1)
      verify(rings[0].parent.z > 0, "the focused button raised over the next")
    }

    function test_only_the_selected_button_grows() {
      guide.elementOverrides = { appButton: { grow: 1 }, "appButton:focused": { grow: 1 } }
      open({ title: "D", subtitle: "", text: "", facts: [], actions: [{ id: "a", label: "Play", kind: "play" }, { id: "b", label: "Watched", kind: "action" }],
             rows: [], image: null, backdrop: null }, "detail")
      wait(300)
      var buttons = function() { return findAll(screen, function(x) { return x.modelData !== undefined && x.modelData.label !== undefined && x.current !== undefined && x.scale !== undefined }) }
      var byLabel = function(l) { return buttons().filter(function(b) { return b.modelData.label === l })[0] }
      compare([byLabel("Play").scale, byLabel("Watched").scale], [1.15, 1], "the focused one at most 15%, the other not at all")
      view.move("right")
      wait(300)
      compare([byLabel("Play").scale, byLabel("Watched").scale], [1, 1.15], "after moving: the other way round")
      guide.elementOverrides = ({})
    }

    function test_only_the_selected_card_grows() {
      guide.elementOverrides = { appCard: { grow: 1 }, appButton: { grow: 1 } }
      setLook("classic")
      open(lookScreen())
      view.move("down")
      tryVerify(function() { return cards().length > 2 }, 2000)
      wait(400)                                                   // its grow, animated
      cards().forEach(function(c) {
        var frame = find(c, "focusRing").parent
        compare(frame.scale, c.current ? 1 + Math.min(0.15, Looks.growOf(c.style)) : 1, c.modelData.id)
      })
    }

    function test_app_pictures_are_decoded_at_most_960_a_side() {
      setLook("cinematic")
      open({ title: "D", subtitle: "", text: "", facts: [], actions: [], rows: [], image: null, backdrop: pic("wide.png"), style: "cinematic" }, "detail")
      var cine = find(screen, "cinematicBackdrop")
      verify(cine.sourceSize.width <= 960 && cine.sourceSize.height <= 960, cine.sourceSize)
      setLook("classic")
      open(lookScreen())
      var hero = null
      tryVerify(function() { hero = find(screen, "appHero"); return !!hero }, 2000)
      var box = findAll(hero, function(x) { return x.image !== undefined && x.image && x.image.decodeW !== undefined })[0]
      verify(box && box.image.decodeW <= 960 && box.image.decodeH <= 960, "the hero's: " + (box ? box.image.decodeW + "x" + box.image.decodeH : "none"))
    }

    function test_cards_and_list_rows_show_their_line() {
      var m = item("m", null); m.meta = "2026 · 90 min"
      var both = item("both", null); both.meta = "2026 · 90 min"; both.subtitle = "S1 E2"
      var sub = item("sub", null); sub.subtitle = "S1 E3"
      open(screenOf([{ id: "r", title: "R", layout: "row", items: [m, both, sub] }, { id: "l", title: "L", layout: "list", items: [m, both] }]))
      tryVerify(function() { return cards().length >= 3 }, 2000)
      var lineOf = function(id) { return find(cards().filter(function(c) { return c.modelData.id === id })[0], "cardLine").text }
      compare(lineOf("m"), "2026 · 90 min", "a card shows its meta")
      compare(lineOf("both"), "2026 · 90 min", "meta first")
      compare(lineOf("sub"), "S1 E3", "else its subtitle")
      var texts = findAll(screen, function(x) { return x.text === "2026 · 90 min" && x.visible })
      verify(texts.length >= 3, "the list's rows too: " + texts.length)
      // the list's row with both: its meta, not its subtitle
      var rowBoth = findAll(screen, function(x) { return x.modelData !== undefined && x.modelData && x.modelData.id === "both" && x.rowGap === undefined && x.cardW === undefined && x.url !== undefined })[0]
      verify(!!rowBoth, "the list row")
      var shown = findAll(rowBoth, function(x) { return x.text !== undefined && x.visible }).map(function(x) { return x.text })
      verify(shown.indexOf("2026 · 90 min") >= 0 && shown.indexOf("S1 E2") < 0, "meta first in a list row: " + shown.join(" | "))
    }

    function test_a_live_badge_keeps_the_floor() {
      guide.elementOverrides = { liveBadge: { text: { size: 0.2 } } }
      var live = item("live", null); live.badge = "LIVE"
      open(screenOf([{ id: "r", title: "R", layout: "row", items: [live] }]))
      tryVerify(function() { return cards().length === 1 }, 2000)
      var c = cards()[0]
      verify(c.liveStyle.text.size * guide.u >= Math.max(12, 0.7 * guide.u) - 0.01, "LIVE no smaller than card text may be")
      var label = findAll(c, function(x) { return x.text === "● Live" })[0]
      verify(!!label && label.visible, "the LIVE label")
      verify(label.font.pixelSize >= Math.max(12, 0.7 * guide.u) - 0.5, "drawn at the floor: " + label.font.pixelSize)
      compare(label.parent.s, c.liveStyle, "its box takes the floored style too")
    }

    // every look over the fixture screen, as drawn: saved to look at, as
    // /tmp/om-pg-look-<look>.png
    function test_snapshots_of_every_look_data() {
      return [{ tag: "classic" }, { tag: "posters" }, { tag: "cinematic" }, { tag: "wall" }, { tag: "compact" }, { tag: "cinematic-details" }, { tag: "classic-details" }]
    }
    function test_snapshots_of_every_look(d) {
      if (GraphicsInfo.api === GraphicsInfo.Software) skip("needs a GPU renderer: run with QT_QPA_PLATFORM=wayland")
      var name = d.tag.split("-")[0]
      setLook(name)
      if (d.tag.indexOf("details") > 0) {
        open({ title: "The Long Night", subtitle: "", text: "An overview of it, in a few lines: who, where and what happens, cut to fit.",
               facts: [{ label: "Director", value: "Someone" }, { label: "Runtime", value: "2 h 10 min" }],
               actions: [{ id: "p", label: "Play", kind: "play" }, { id: "w", label: "Watched", kind: "action" }],
               rows: [{ id: "cast", title: "Cast", layout: "row", shape: "circle", items: [0, 1, 2, 3].map(function(i) { return item("Actor " + i, pic("square.png")) }) }],
               image: pic("poster.png"), backdrop: pic("wide.png"), logo: pic("square.png"), meta: "2019 · 2 h 10 min · PG-13", chips: ["Drama", "Mystery", "4K"],
               style: name === "cinematic" ? "cinematic" : "classic" }, "detail")
      } else {
        open(lookScreen())
        view.move("down")
      }
      // the whole screen in the window, whatever size the compositor gave it
      var w = root.Window.window
      var was = [root.width, root.height]
      if (w && w.width > 0 && w.height > 0) { root.width = w.width; root.height = w.height }
      wait(1200)
      var img = grabImage(root.Window.window.contentItem)
      root.width = was[0]
      root.height = was[1]
      verify(img.width > 0)
      img.save("/tmp/om-pg-look-" + d.tag + ".png")
    }
  }
}
