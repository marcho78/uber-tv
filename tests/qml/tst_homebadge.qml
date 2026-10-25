import QtQuick
import QtTest
import "../../ui"
import "../../Look.js" as Look

// Home drawn for real (ui/HomeScreen.qml, offscreen at 1280×720) over a
// pretend guide in Retro's colors, its rows as Guide.qml's homeView gives
// them: on Home, as on the Apps screen, an app's
// card from a signed app file shows the file badge, as does an unsigned file;
// page, and Uber TV's own (bundled, the catalog) none; it's in the card's
// top right corner, solid, and drawn over everything the app has a say in:
// its color, a picture that reaches that corner (black, white, or made to
// match the badge) and its name at its longest; the same on a tile; and an
// app's own Home row shows where the app is from beside its name, in the
// row however long the app makes that name. One is made for each app's
// card, where it's drawn; a card that isn't an app's never has one.
// Run: /usr/lib/qt6/bin/qmltestrunner -input tests/qml
Item {
  id: root
  width: 1280
  height: 720

  readonly property string pics: Qt.resolvedUrl("../fixtures/pictures/").toString().replace(/^file:\/\//, "")
  readonly property var retro: ({ text: "#f2f4ff", textDim: "#9fb0f0", accent: "#ffd23f", timeline: "#ff4d4d", cell: "#1b3591", cellBorder: "#3b5bd1", channelCell: "#0f2470", selected: "#ffd23f", selectedText: "#141414", header: "#ffd23f", headerText: "#141414", band: "#030a2b", bandText: "#ffd23f", infoPanel: "#40000000", preview: "#000000", alert: "#ff4d4d", bgTop: "#071447", bgBottom: "#030a2b", ltBg: "#eb081447", ltBorder: "#3b5bd1", ltNumber: "#ffd23f", ltChannel: "#9fb0f0", ltTitle: "#f2f4ff", ltProgress: "#ffd23f", ltTrack: "#1b3591", ltClock: "#f2f4ff", ltTime: "#ffd23f", cardBackdrop: "#d1000000", cardName: "#ffd23f", cardStatus: "#9fb0f0", cardFrame: "#3b5bd1", boxBg: "#071447", boxBorder: "#ffd23f", scrim: "#bf030a2b", keyFace: "#e4e9ff", keyText: "#0b1550", keyEdge: "#46559a", miniBar: "#eb030a2b" })
  // what fill-match.svg is made of: the badge's fill, with lines in its
  // icon's and its edge's colors (the badge in Retro's colors)
  readonly property var matched: ({ fill: "#071447", icon: "#ffffff", edge: "#ffd23f" })

  // each the same Scores by "Uber TV", in its red, with the same picture:
  // only where it's from tells them apart
  function appCard(id, from, picture, name) {
    return { id: "app:" + id, kind: "app", shape: "wide", appId: id, title: name, sub: "Uber TV", color: "#d62828", poster: picture, when: 0, from: from }
  }
  function appsRowOf(picture, name, froms) {
    var f = froms || ["bundled", "catalog", "appFile", "file"]
    return { key: "apps:", type: "apps", title: "Your apps", shape: "thumb", size: 1,
             cards: [root.appCard("tv.uber.scores", f[0], picture, name), root.appCard("tv.uber.flix", f[1], picture, name),
                     root.appCard("tv.alex.scores", f[2], picture, name), root.appCard("dev.me.scores", f[3], picture, name)] }
  }
  readonly property var appsRow: root.appsRowOf(root.pics + "square.png", "Scores")
  readonly property var doorsRow: ({ key: "doors:", type: "doors", title: "Tiles", shape: "tile", size: 1,
                                     cards: [{ id: "door:tv", kind: "door", door: "tv", title: "Live TV", sub: "3 channels" },
                                             { id: "door:movies", kind: "door", door: "movies", title: "Movies & Series", sub: "0 in your library" }] })
  // an app's own Home row: its cards are its items
  function appRow(appId, label) {
    return { key: "appRow:" + appId + "/now", type: "appRow", title: "Scores: " + label, shape: "thumb", size: 1,
             cards: [{ id: "ai:" + appId + ":1", kind: "appItem", appId: appId, item: { id: "1" }, title: "A vs B", sub: "Scores", poster: "", shape: "wide", live: true, progress: 0 }] }
  }

  QtObject {
    id: store
    property var installed: [{ id: "tv.uber.scores", from: "bundled" }, { id: "tv.uber.flix", from: "catalog" },
                             { id: "tv.alex.scores", from: "appFile" }, { id: "dev.me.scores", from: "file" }]
    function record(id) { for (var i = 0; i < store.installed.length; i++) if (store.installed[i].id === id) return store.installed[i]; return null }
  }

  QtObject {
    id: guide
    property string lastInput: "keyboard"
    function noteInput(kind) { lastInput = kind }   // tablet mode: what was used last
    property real u: 16
    readonly property var colors: root.retro
    readonly property var fonts: ({ body: "Sans", display: "Sans", mono: "Monospace" })
    readonly property var look: Look.resolve({}, {}, guide.colors, guide.fonts, {})
    readonly property var layout: Look.effectiveLayout({}, {})
    readonly property color ink: colors.text
    readonly property color dimInk: colors.textDim
    readonly property color cellEdge: colors.cellBorder
    readonly property var apps: store
    readonly property string homeTop: "off"           // no big title: room for the rows
    readonly property var homeHero: ({ kicker: "Welcome", title: "Your TV", meta: "", progress: 0 })
    readonly property var homeLastChannel: ({ kicker: "", title: "", meta: "", progress: 0 })
    property var homeBackground: ({ mode: "none", image: "", dim: 0.6 })
    readonly property string homeBackdrop: ""
    readonly property var homeCard: null
    property var homeView: [root.doorsRow, root.appsRow]
    property int homeRow: 0
    property var homeCols: ({})
    property bool remoteEnabled: false
    property var remoteDevices: []
    property real fetchedAt: 0
    property real now: 0
    property bool showKeyHints: true
    property bool windowed: false
    property bool homeEditing: false
    property bool homeAdding: false
    property int homeOptions: -1
    property bool homeRenaming: false
    property string homeRenameStart: ""
    property var homePanelRows: []
    property int homeCursor: 0
    property var homeSections: []
    property var homeTiles: []
    property string homePictureNote: ""
    property var areaImages: ({})
    readonly property var appHome: ({ pictureBroken: function() {}, pictureDrawn: function() {} })
    function clock(t) { return "8:42 PM" }
    function showTitle(t) { return t }
    function posterFor(entry) { return entry && entry.poster ? "file://" + entry.poster : "" }
    function homeOpen() {}
  }

  HomeScreen { id: home; anchors.fill: parent; guide: guide }

  TestCase {
    name: "HomeBadge"
    when: windowShown

    // every item under one that passes, a ListView's cards included
    function under(item, test, out) {
      out = out || []
      if (test(item)) out.push(item)
      var kids = item.children || []
      for (var i = 0; i < kids.length; i++) under(kids[i], test, out)
      return out
    }
    function badges(item) { return under(item, function(it) { return it.objectName === "originBadge" }) }
    // the card (what), or the row (cards), a badge is drawn in
    function owner(item, what) {
      for (var p = item.parent; p; p = p.parent)
        if (p.modelData && p.modelData[what] !== undefined) return p
      return null
    }
    // the badges made for an app's cards (shown or not), the ones shown, and
    // whether its cards are drawn yet
    function madeOn(appId) {
      return badges(home).filter(function(b) { var c = owner(b, "kind"); return c && c.modelData.appId === appId })
    }
    function shownOn(appId) { return madeOn(appId).filter(function(b) { return b.visible }) }
    function drawn(appId) {
      return under(home, function(it) { return !!it.modelData && it.modelData.kind !== undefined && it.modelData.appId === appId }).length > 0
    }
    // the badges shown in a row (on its cards or by its name)
    function shownIn(rowKey) {
      return badges(home).filter(function(b) { var r = owner(b, "cards"); return b.visible && r && r.modelData.key === rowKey })
    }

    // the picture on a badge's card, by its file
    function pictureBy(badge, file) {
      var card = owner(badge, "kind")
      return card ? under(card, function(it) { return it.fillMode !== undefined && it.status !== undefined && String(it.source).indexOf(file) >= 0 })[0] || null : null
    }
    // where a picture is drawn, in root's coordinates: shown whole, it's
    // centered in its item
    function drawnAt(pic) {
      var a = pic.mapToItem(root, (pic.width - pic.paintedWidth) / 2, (pic.height - pic.paintedHeight) / 2)
      var b = pic.mapToItem(root, (pic.width + pic.paintedWidth) / 2, (pic.height + pic.paintedHeight) / 2)
      return { x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y }
    }
    // whether a pixel's whole square is in a rectangle
    function within(r, p) { return p.x >= r.x && p.x + 1 <= r.x + r.w && p.y >= r.y && p.y + 1 <= r.y + r.h }
    // the pixel (in root's coordinates) at a point of a badge, its x and y
    // as parts of its width
    function at(badge, fx, fy) {
      var q = badge.mapToItem(root, fx * badge.width, fy * badge.width)
      return { x: Math.floor(q.x), y: Math.floor(q.y) }
    }
    // the pixels a badge covers whole, in root's coordinates: inside its
    // rounded square and a pixel clear of its outer edge (whatever is under
    // that edge blends into it)
    function covered(badge) {
      var w = badge.width, r = badge.radius, m = 1
      var o = badge.mapToItem(root, 0, 0)
      var inside = function(x, y) {
        if (x < m || y < m || x > w - m || y > w - m) return false
        var cx = Math.min(Math.max(x, r), w - r), cy = Math.min(Math.max(y, r), w - r)
        return (x - cx) * (x - cx) + (y - cy) * (y - cy) <= (r - m) * (r - m)
      }
      var out = []
      for (var py = Math.floor(o.y); py < o.y + w; py++)
        for (var px = Math.floor(o.x); px < o.x + w; px++) {
          var x = px - o.x, y = py - o.y
          if (inside(x, y) && inside(x + 1, y) && inside(x, y + 1) && inside(x + 1, y + 1)) out.push({ x: px, y: py })
        }
      return out
    }
    function colors(img, points) { return points.map(function(p) { return String(img.pixel(p.x, p.y)) }) }
    // the first of these pixels that isn't as it was ("" when none)
    function changed(now, was, points) {
      for (var i = 0; i < points.length; i++)
        if (now[i] !== was[i]) return points[i].x + "," + points[i].y + " is " + now[i] + ", was " + was[i]
      return ""
    }

    function init() {
      guide.homeView = [root.doorsRow, root.appsRow]
      guide.homeRow = 0
      guide.homeCols = ({})
    }

    function test_a_card_shows_where_its_app_is_from() {
      tryVerify(function() { return root.appsRow.cards.every(function(c) { return drawn(c.appId) }) }, 3000, "Home draws the apps' cards")
      compare(shownOn("tv.alex.scores").length, 1, "one from a signed app file: a badge")
      compare(shownOn("tv.alex.scores")[0].from, "appFile", "the file")
      compare(shownOn("dev.me.scores").length, 1, "one from a file: a badge")
      compare(shownOn("dev.me.scores")[0].from, "file", "the page")
      compare(shownOn("tv.uber.scores").length, 0, "Uber TV's own, bundled: none")
      compare(shownOn("tv.uber.flix").length, 0, "Uber TV's catalog: none")
      compare(shownIn("doors:").length, 0, "the tiles that aren't apps: none")
      compare(badges(home).filter(function(b) { var c = owner(b, "kind"); return c && c.modelData.kind !== "app" }).length, 0, "none even made for a card that isn't an app's")
      // one made for each app's card, in its frame (none in the tile it isn't)
      tryVerify(function() { return root.appsRow.cards.every(function(c) { return madeOn(c.appId).length === 1 }) }, 3000, "one badge made for each app's card")
    }

    // in its card's picture frame, in the top right corner, over the app's
    // picture and color, solid: the pixels it covers are its own whatever is
    // under them. The pictures are the shape of the frame's picture area
    // (424×200 at the default card width), so drawn whole they fill it and
    // reach the badge's corner, as an app's own wide icon can: black, white,
    // and one made to match it (its fill, with lines in its icon's and its
    // edge's colors). A badge drawn under the picture, or see-through, shows it
    function test_drawn_over_its_picture_in_the_corner() {
      var seen = {}
      for (var file of ["fill-black.svg", "fill-white.svg", "fill-match.svg"]) {
        guide.homeView = [root.doorsRow, root.appsRowOf(root.pics + file, "Scores")]
        tryVerify(function() {
          return ["tv.alex.scores", "dev.me.scores"].every(function(id) {
            var b = shownOn(id), pic = b.length === 1 ? pictureBy(b[0], file) : null
            return pic !== null && pic.status === Image.Ready
          })
        }, 5000, file + " drawn on the signed and unsigned file cards, with their badges")
        var img = grabImage(root)
        for (var id of ["tv.alex.scores", "dev.me.scores"]) {
          var b = shownOn(id)[0]
          var frame = b.parent.parent
          var at0 = b.mapToItem(frame, 0, 0)
          verify(at0.x >= frame.width / 2 && at0.x + b.width <= frame.width, "on the right: " + at0.x + " of " + frame.width)
          verify(at0.y >= 0 && at0.y + b.height <= frame.height / 2, "at the top: " + at0.y + " of " + frame.height)
          compare(b.color.a, 1, "solid")
          if (file === "fill-match.svg") {
            compare(String(b.color), root.matched.fill, "the picture made to match has the badge's fill")
            compare(String(b.ink), root.matched.icon, "and its icon's color")
            compare(String(b.border.color), root.matched.edge, "and its edge's")
          }
          var pic = drawnAt(pictureBy(b, file))
          // its fill, between its edge and its icon: where the picture is
          // under it, and where only the app's color is
          for (var q of [[0.12, 0.5], [0.12, 0.7], [0.3, 0.88], [0.5, 0.88]]) {
            var p = at(b, q[0], q[1])
            verify(within(pic, p), id + ": " + file + " is under " + q + " (" + p.x + "," + p.y + " in " + JSON.stringify(pic) + ")")
            compare(String(img.pixel(p.x, p.y)), String(b.color), id + ": its own fill at " + q + " over " + file)
          }
          for (var q2 of [[0.5, 0.12], [0.88, 0.5]]) {
            var p2 = at(b, q2[0], q2[1])
            verify(!within(pic, p2), id + ": only the app's color under " + q2)
            compare(String(img.pixel(p2.x, p2.y)), String(b.color), id + ": its own fill at " + q2 + " over the app's color")
          }
          // every pixel it covers whole with the picture under it, its
          // middle (its icon) included: the same over each picture
          var over = covered(b).filter(function(p) { return within(pic, p) })
          var mid = at(b, 0.5, 0.5)
          verify(over.some(function(p) { return p.x === mid.x && p.y === mid.y }), id + ": " + file + " is under its middle")
          verify(over.length >= b.width * b.width / 8, id + ": " + file + " is under " + over.length + " of its pixels")
          var got = colors(img, over)
          if (seen[id] === undefined) seen[id] = { points: over, colors: got }
          compare(JSON.stringify(over), JSON.stringify(seen[id].points), id + ": the same pixels under " + file + " as under fill-black.svg")
          compare(changed(got, seen[id].colors, over), "", id + ": its pixels over " + file + ", as over fill-black.svg")
        }
      }
    }

    // with no picture the app's name is drawn in its frame, on its color; at
    // its longest (40 characters, no space: three full lines, accents on
    // top) it reaches the badge's corner, and the badge stays over it
    function test_drawn_over_its_name() {
      var name = "ÅÉÎÕÛ".repeat(8)
      // the signed app-file card as Home draws it now (its name, from, no picture):
      // its badge, once its name is drawn in its frame
      var now = function(title, from) {
        var cards = under(home, function(it) { return !!it.modelData && it.modelData.kind === "app" && it.modelData.appId === "tv.alex.scores" })
        var c = cards.length === 1 ? cards[0].modelData : null
        if (!c || c.title !== title || c.from !== from || c.poster !== "") return null
        var made = badges(cards[0])
        return made.length === 1 && made[0].parent.parent.children.some(function(k) { return k.text === title && k.visible }) ? made[0] : null
      }
      guide.homeView = [root.doorsRow, root.appsRowOf("", "Scores")]
      tryVerify(function() { var b = now("Scores", "appFile"); return b !== null && b.visible }, 3000, "the signed file's card: its badge, its short name")
      var spots = covered(now("Scores", "appFile"))
      var own = colors(grabImage(root), spots)
      // the same card as Uber TV's own (no badge): where its name is drawn
      guide.homeView = [root.doorsRow, root.appsRowOf("", name, ["bundled", "catalog", "bundled", "file"])]
      tryVerify(function() { var b = now(name, "bundled"); return b !== null && !b.visible }, 3000, "the same card as Uber TV's own: no badge, its long name")
      var bare = grabImage(root)
      var inked = spots.filter(function(p) { return String(bare.pixel(p.x, p.y)) !== "#d62828" })
      verify(inked.length >= 10, "its name is drawn where the badge goes: " + inked.length + " pixels")
      // from a signed app file again: the badge's own pixels, over its name
      guide.homeView = [root.doorsRow, root.appsRowOf("", name)]
      tryVerify(function() { var b = now(name, "appFile"); return b !== null && b.visible }, 3000, "the signed file's card: its badge, its long name")
      compare(JSON.stringify(covered(now(name, "appFile"))), JSON.stringify(spots), "in the same place")
      compare(changed(colors(grabImage(root), spots), own, spots), "", "the badge's own pixels, its name under them")
    }

    // an app's card drawn as a tile (a row of tiles) gets it too
    function test_on_a_tile_too() {
      guide.homeView = [{ key: "apps:", type: "apps", title: "Your apps", shape: "tile", size: 1, cards: root.appsRow.cards }]
      tryVerify(function() { return shownOn("tv.alex.scores").length === 1 && shownOn("dev.me.scores").length === 1 }, 3000, "a signed file's tile and an unsigned file's: a badge each")
      compare(shownOn("tv.alex.scores")[0].from, "appFile")
      compare(shownOn("dev.me.scores")[0].from, "file")
      compare(shownOn("tv.uber.scores").length + shownOn("tv.uber.flix").length, 0, "Uber TV's own: none")
      // one made for each app's tile (none in the card frame it isn't)
      tryVerify(function() { return root.appsRow.cards.every(function(c) { return madeOn(c.appId).length === 1 }) }, 3000, "one badge made for each app's tile")
    }

    // an app's own Home row: where the app is from, beside the row's name
    // (its items' cards are the app's, and carry none of their own)
    function test_an_apps_own_row() {
      for (var t of [["tv.alex.scores", "appFile"], ["dev.me.scores", "file"], ["tv.uber.scores", ""], ["tv.uber.flix", ""]]) {
        var key = "appRow:" + t[0] + "/now"
        guide.homeView = [root.appRow(t[0], "Scores now")]
        tryVerify(function() { return drawn(t[0]) && under(home, function(it) { return !!it.modelData && it.modelData.key === key }).length > 0 }, 3000, "Home draws the row")
        compare(badges(home).filter(function(b) { var c = owner(b, "kind"); return c && c.modelData.appId === t[0] }).length, 0, "none made for an item's card")
        var seen = shownIn(key)
        compare(seen.length, t[1] ? 1 : 0, t[0] + ": " + (t[1] || "Uber TV's own: none"))
        if (!t[1]) continue
        var b = seen[0]
        compare(b.from, t[1])
        verify(owner(b, "kind") === null, "by the row's name, not on an item's card")
        var title = b.parent.children.filter(function(k) { return k.text === "Scores: Scores now" })[0]
        verify(title, "the row's name")
        verify(b.x >= title.x + title.contentWidth && b.x <= title.x + title.contentWidth + guide.u * 2, "just after its name: " + b.x + " vs " + (title.x + title.contentWidth))
        verify(b.y >= title.y && b.y + b.height <= title.y + title.height, "on its line")
      }
      // its name at its longest (the app's name and the row's label, 40 wide
      // letters each, and that it couldn't update: wider than the screen) is
      // cut short, and the badge stays beside what's shown of it, in the row
      var long = "W".repeat(40)
      var named = root.appRow("tv.alex.scores", long)
      named.title = long + ": " + long + " (couldn't update)"
      guide.homeView = [named]
      tryVerify(function() { return shownIn(named.key).length === 1 && shownIn(named.key)[0].parent.children.some(function(k) { return k.text === named.title }) }, 3000, "Home draws the row with its long name")
      var lb = shownIn(named.key)[0]
      var lt = lb.parent.children.filter(function(k) { return k.text === named.title })[0]
      verify(lt.truncated, "its name cut short")
      verify(lb.x >= lt.x + lt.contentWidth && lb.x <= lt.x + lt.contentWidth + guide.u * 2, "just after what's shown of it: " + lb.x + " vs " + (lt.x + lt.contentWidth))
      verify(lb.x + lb.width <= lb.parent.width - guide.u * 3, "in the row: " + (lb.x + lb.width) + " of " + lb.parent.width)
      // only an app's own row: a row of anything else whose name looks like an
      // app's id (a playlist's genre, say) has none, nor a row drawn as tiles
      // (its name isn't shown)
      var tiled = root.appRow("tv.alex.scores", "Scores now")
      tiled.shape = "tile"
      for (var row of [{ key: "genre:Xtv.alex.scores", type: "genre", title: "Xtv.alex.scores", shape: "thumb", size: 1, cards: root.appsRow.cards.slice(0, 1) }, tiled]) {
        guide.homeView = [row]
        tryVerify(function() { return under(home, function(it) { return !!it.modelData && it.modelData.key === row.key && it.modelData.shape === row.shape }).length > 0 }, 3000, "Home draws " + row.key)
        compare(shownIn(row.key).filter(function(b) { return owner(b, "kind") === null }).length, 0, row.type + " " + row.shape + ": none by its name")
      }
    }
  }
}
