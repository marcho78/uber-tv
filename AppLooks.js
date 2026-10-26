.pragma library

// The presentation model of an app's screen: one place decides how every
// line is drawn (its layout, its pictures' shape, the cards' size, their
// titles, and how many columns a grid has at this width) and how the screen
// around them looks (the look in force, the top of the screen, the
// background, the details page), and both the drawing (ui/AppScreen.qml)
// and the arrows (AppNav.js) read it. Who decides what follows the plan's
// precedence: your choice for this app, then
// for all apps, then the theme's, then the look's, then the app's hints.
// Also the shape a row learns from its first pictures, the contrast rules
// for the focus ring, the selected title and the identity strip, and the
// 10-foot floors. Kept apart from the QML so it can be tested on its own
// (tests/applooks.test.mjs).

// A shape: its box (height over width), how the picture sits in it, and
// which library width it takes
var SHAPES = {
  poster: { aspect: 1.5, fit: "fill", base: "poster" },        // 2:3
  wide: { aspect: 9 / 16, fit: "fill", base: "thumb" },        // 16:9
  square: { aspect: 1, fit: "fill", base: "square" },
  logo: { aspect: 9 / 16, fit: "fit", base: "square" },        // whole, with space around it
  circle: { aspect: 1, fit: "fill", base: "square", round: true },
  autoSquare: { aspect: 1, fit: "fit", base: "square" }        // learned, not asked for: drawn whole like a logo
}
var SIZES = { small: 0.72, medium: 1, large: 1.4 }
// a square card's width, in units, if the layout has no librarySquareWidth
var SQUARE_WIDTH = 10
// the narrowest each library width goes (Look.js LAYOUT's minimums), in
// units: a small card never comes out narrower (§11's floors)
var FLOORS = { poster: 5, thumb: 9, square: 5 }
// which of an item's pictures a card in each shape shows (images: API 3);
// a circle and a learned square show the item's own image
var PICTURE_OF = { poster: "poster", wide: "wide", square: "square", logo: "logo" }

function num(v, d) { return typeof v === "number" && isFinite(v) && v > 0 ? v : d }

// An object's own property, never one it inherits: row ids, and anything
// read from JSON, can be named like Object's own ("__proto__", "toString")
function own(o, k) { return o !== null && typeof o === "object" && Object.prototype.hasOwnProperty.call(o, k) ? o[k] : undefined }

// ---- the looks (§4.7) -------------------------------------------------------
// What each look sets: its picture rule ("app": as the app says; poster or
// wide: that shape wherever a row's items have that picture), the cards'
// size ("app": as the app says), the titles under cards, the top of the
// screen, the background, and the details page ("app": as the app says,
// else classic). A look never hides, reorders or re-lays-out rows.
var LOOKS = {
  classic: { picture: "app", size: "app", titles: "below", top: "off", background: "details", details: "app" },
  posters: { picture: "poster", size: "app", titles: "below", top: "off", background: "details", details: "app" },
  cinematic: { picture: "wide", size: "large", titles: "selected", top: "selected", background: "focus", details: "cinematic" },
  wall: { picture: "poster", size: "small", titles: "off", top: "selected", background: "focus", details: "app" },
  compact: { picture: "app", size: "small", titles: "below", top: "off", background: "none", details: "classic" }
}
var LOOK_NAMES = ["classic", "posters", "cinematic", "wall", "compact"]
// What each screen property takes, besides "look" (as the look) and leaving
// it unset (the next layer down decides)
var CHOICES = {
  top: ["selected", "off"],
  details: ["classic", "cinematic", "app"],
  titles: ["below", "selected", "off"],
  size: ["small", "medium", "large"]
}
var BACKGROUNDS = ["focus", "details", "guide", "wallpaper", "image", "none"]
// How dark the background is when nothing says, and the least shade over a
// picture an app or a theme sent (your wallpaper or a picture you picked may
// go lighter)
var DIM = 0.75
var SHADE_FLOOR = 0.3
// Who chooses, from the top: you for this app, you for all apps, the theme
var LAYERS = ["mine", "all", "theme"]

// The look in force: yours for this app, for all apps, the theme's, the
// app's suggestion (its app.json), else Classic. "app" at one of the first
// three hands it to the app's suggestion. Answers { look, from }.
function lookOf(choices, suggested) {
  for (var i = 0; i < LAYERS.length; i++) {
    var v = own(own(choices, LAYERS[i]), "look")
    if (v === "app") break
    if (typeof v === "string" && own(LOOKS, v)) return { look: v, from: LAYERS[i] }
  }
  if (typeof suggested === "string" && own(LOOKS, suggested)) return { look: suggested, from: "app" }
  return { look: "classic", from: "default" }
}

// A background as a choice: { mode, image, dim }, or null when it isn't one
function backgroundOf(b) {
  if (b === null || typeof b !== "object" || BACKGROUNDS.indexOf(b.mode) < 0) return null
  var image = b.mode === "image" && typeof b.image === "string" ? b.image : ""
  if (b.mode === "image" && !image) return null
  var dim = typeof b.dim === "number" && isFinite(b.dim) ? Math.max(0, Math.min(0.95, b.dim)) : DIM
  return { mode: b.mode, image: image, dim: dim }
}

// The screen's properties (the top, the background, the details page, the
// titles under cards, the cards' size): the first of yours for this app,
// yours for all apps and the theme's that's set wins, else the look's, else
// Classic's. "look" at one of those hands it to the look. Answers each, and
// where each came from (from).
function screenOf(choices, look) {
  var L = own(LOOKS, look) || LOOKS.classic
  var out = { look: own(LOOKS, look) ? look : "classic", from: {} }
  for (var k in CHOICES) {
    for (var i = 0; i < LAYERS.length; i++) {
      var v = own(own(choices, LAYERS[i]), k)
      if (v === "look") break
      if (CHOICES[k].indexOf(v) >= 0) { out[k] = v; out.from[k] = LAYERS[i]; break }
    }
    if (out[k] === undefined) { out[k] = L[k] !== undefined ? L[k] : LOOKS.classic[k]; out.from[k] = "look" }
  }
  for (var j = 0; j < LAYERS.length && !out.background; j++) {
    var b = own(own(choices, LAYERS[j]), "background")
    if (b === "look") break
    var c = backgroundOf(b)
    if (c) { out.background = c; out.from.background = LAYERS[j] }
  }
  if (!out.background) { out.background = { mode: L.background, image: "", dim: DIM }; out.from.background = "look" }
  return out
}

// A details page's style: the screen's (classic or cinematic), or as the
// app says: the page's own style, else classic
function detailStyleOf(value, screen) {
  var d = screen ? screen.details : "app"
  if (d === "classic" || d === "cinematic") return d
  return value && value.style === "cinematic" ? "cinematic" : "classic"
}

// The lengths every line is made of, in pixels, for this width and unit
// (touch: tablet mode's finger, in px, or 0: a details page's buttons are
// at least that tall, and their line makes room for them and for the
// selected one's growth)
function geometry(env) {
  var u = num(env && env.u, 16)
  var lay = env && env.layout ? env.layout : {}
  var actionH = Math.max(Math.round(u * 3.2), num(env && env.touch, 0))
  return {
    u: u,
    width: num(env && env.width, 1280),
    titleH: Math.round(u * 2.6),
    captionH: Math.round(u * 3.6),
    gap: Math.round(u * 1.2),
    margin: Math.round(u * 2),
    rowPad: Math.round(u * 1.6),
    listRowH: Math.round(u * 3.4),
    listGap: Math.round(u * 0.2),
    tableHeadH: Math.round(u * 2.4),
    tableRowH: Math.round(u * 2.8),
    tickerH: Math.round(u * 3.2),
    actionH: actionH,
    actionY: Math.round(Math.max(u * 0.4, actionH * 0.12)),
    actionsH: Math.round(actionH + Math.max(u, actionH * 0.3)),
    heroH: Math.round(u * 22),
    widths: { poster: num(lay.libraryPosterWidth, 8.6), thumb: num(lay.libraryThumbWidth, 15.5), square: num(lay.librarySquareWidth, SQUARE_WIDTH) }
  }
}

// The app's defaults for a row (app.json's layout.rows, API 3), by its id
function defaultOf(row, defaults) {
  var k = "d:" + row.id
  return defaults && Object.prototype.hasOwnProperty.call(defaults, k) ? defaults[k] : null
}

// Your choices for a row (Customize, from milestone 3), by its id
function mineOf(row, ctx) { return own(ctx && ctx.rows, "r:" + row.id) || null }

// Whether a row's items have the picture for a shape: every item with any
// picture has that one, and at least one does. A row of logos stays logos;
// an item with no picture at all counts neither way.
function rowHas(row, key) {
  var found = false
  for (var i = 0; i < row.items.length; i++) {
    var it = row.items[i]
    var pics = it.images && typeof it.images === "object" ? it.images : {}
    if (own(pics, key)) { found = true; continue }
    if (it.image) return false
    for (var p in pics) if (own(pics, p)) return false
  }
  return found
}

// A row's shape, and where it came from: your choice for the row ("mine");
// the look's picture rule, where the row's items have that picture
// ("look"); the app's hint on the row, else its app.json default for the
// row id ("app"); else what the row learned from its first pictures
// ("learned"); else wide while it's still working that out ("auto").
function shapeOf(row, learned, defaults, ctx) {
  var mine = mineOf(row, ctx)
  if (mine && own(SHAPES, mine.shape) && mine.shape !== "autoSquare") return { shape: mine.shape, from: "mine" }
  var pic = ctx && own(LOOKS, ctx.look) ? LOOKS[ctx.look].picture : "app"
  if (pic !== "app" && rowHas(row, pic)) return { shape: pic, from: "look" }
  var d = defaultOf(row, defaults)
  if (own(SHAPES, row.shape) && row.shape !== "autoSquare") return { shape: row.shape, from: "app" }
  if (d && own(SHAPES, d.shape) && d.shape !== "autoSquare") return { shape: d.shape, from: "app" }
  var k = "r:" + row.id
  if (learned && Object.prototype.hasOwnProperty.call(learned, k) && own(SHAPES, learned[k])) return { shape: learned[k], from: "learned" }
  return { shape: "wide", from: "auto" }
}

// A row's size, and where it came from: your choice for the row; the
// screen's (yours for this app or all apps, the theme's, or the look's own
// when it isn't "as the app says"); the app's hint; its app.json default;
// else medium
function sizeOf(row, defaults, ctx) {
  var mine = mineOf(row, ctx)
  if (mine && own(SIZES, mine.size)) return { size: mine.size, from: "mine" }
  var sc = ctx && ctx.screen
  if (sc && own(SIZES, sc.size)) return { size: sc.size, from: sc.from.size }
  var d = defaultOf(row, defaults)
  if (own(SIZES, row.size)) return { size: row.size, from: "app" }
  if (d && own(SIZES, d.size)) return { size: d.size, from: "app" }
  return { size: "medium", from: "default" }
}

// A row's layout, and where it came from: your choice for the row (a hero
// only where the app made it one), the app's hint, its app.json default,
// else a row
var LAYOUTS = ["row", "grid", "list", "hero"]
// api 4's table and ticker: only the row itself says so, and nothing changes
// them (a table's cells, a ticker's moving text, aren't cards)
var FIXED = ["table", "ticker"]
function layoutOf(row, defaults, ctx) {
  if (FIXED.indexOf(row.layout) >= 0) return { layout: row.layout, from: "app" }
  var d = defaultOf(row, defaults)
  var app = LAYOUTS.indexOf(row.layout) >= 0 ? row.layout : d && LAYOUTS.indexOf(d.layout) >= 0 ? d.layout : ""
  var mine = mineOf(row, ctx)
  if (mine && LAYOUTS.indexOf(mine.layout) >= 0 && (mine.layout !== "hero" || app === "hero")) return { layout: mine.layout, from: "mine" }
  if (app) return { layout: app, from: "app" }
  return { layout: "row", from: "default" }
}

// The titles under a row's cards, and where that came from: your choice for
// the row, else the screen's (yours, all apps', the theme's or the look's),
// else every card. Off only while the top of the screen is shown with
// what's selected (on a screen: a details page has its own top instead);
// otherwise the selected card keeps its title.
function titlesOf(row, ctx) {
  var mine = mineOf(row, ctx)
  var sc = ctx && ctx.screen
  var t = mine && CHOICES.titles.indexOf(mine.titles) >= 0 ? { titles: mine.titles, from: "mine" }
        : sc && CHOICES.titles.indexOf(sc.titles) >= 0 ? { titles: sc.titles, from: sc.from.titles }
        : { titles: "below", from: "default" }
  if (t.titles === "off" && !(sc && sc.topShown)) t.titles = "selected"
  return t
}

// The picture a card shows: the item's picture for its row's final shape,
// else its own image (the title when there's neither). While the row is
// still working out its shape, its own image: what it learns from.
function cardImage(item, line) {
  if (!item) return null
  var key = line && line.from !== "auto" ? own(PICTURE_OF, line.shape) : ""
  var pics = item.images && typeof item.images === "object" ? item.images : {}
  return (key && own(pics, key)) || item.image || null
}

// The picture behind a hero item, or behind the screen for the selected
// item (the focus background): its backdrop, else its wide picture, else
// none. A details page's own backdrop is its backdrop.
function backdropOf(thing) {
  if (!thing) return null
  var pics = thing.images && typeof thing.images === "object" ? thing.images : {}
  return own(pics, "backdrop") || own(pics, "wide") || thing.backdrop || null
}

// A hero item's title logo, else none (its title is drawn)
function logoOf(thing) {
  if (!thing) return null
  var pics = thing.images && typeof thing.images === "object" ? thing.images : {}
  return own(pics, "logo") || thing.logo || null
}

function rowLine(r, g, learned, defaults, ctx) {
  var sh0 = shapeOf(r, learned, defaults, ctx)
  var shape = sh0.shape
  var sh = SHAPES[shape]
  var sz = sizeOf(r, defaults, ctx)
  var size = sz.size
  var cardW = Math.max(1, Math.round(g.u * Math.max(g.widths[sh.base] * SIZES[size], FLOORS[sh.base])))
  var cardH = Math.max(1, Math.round(cardW * sh.aspect))
  var n = r.items.length
  var lay = layoutOf(r, defaults, ctx)
  var layout = lay.layout
  var ti = titlesOf(r, ctx)
  var captionH = ti.titles === "off" ? 0 : g.captionH
  var line = { kind: "row", id: r.id, title: r.title || "", layout: layout, layoutFrom: lay.from, items: r.items,
               shape: shape, from: sh0.from, size: size, sizeFrom: sz.from, titles: ti.titles, titlesFrom: ti.from,
               fit: sh.fit, round: !!sh.round, cardW: cardW, cardH: cardH, captionH: captionH,
               gap: g.gap, cols: 1, cellW: cardW + g.gap, cellH: cardH + captionH + g.gap, height: 0 }
  if (layout === "hero") {
    // one big item at a time, across the screen
    line.cardW = Math.max(1, g.width - 2 * g.margin)
    line.cardH = g.heroH
    line.captionH = 0
    line.cellW = line.cardW + g.gap
    line.cellH = line.cardH + g.gap
    line.height = g.titleH + g.heroH + g.rowPad
  } else if (layout === "grid") {
    line.cols = Math.max(1, Math.floor((g.width - 2 * g.margin + g.gap) / line.cellW))
    line.height = g.titleH + Math.ceil(n / line.cols) * line.cellH + Math.round(g.u)
  } else if (layout === "list") {
    line.rowH = g.listRowH
    line.rowGap = g.listGap
    line.picH = g.listRowH - Math.round(g.u * 0.8)
    line.picW = Math.round(line.picH / sh.aspect)
    line.height = g.titleH + n * g.listRowH + Math.max(0, n - 1) * g.listGap + Math.round(g.u)
  } else if (layout === "table") {
    // its columns' labels, then a line each item (its cells), like a list
    line.columns = Array.isArray(r.columns) ? r.columns : []
    line.headH = g.tableHeadH
    line.rowH = g.tableRowH
    line.rowGap = g.listGap
    line.captionH = 0
    line.height = g.titleH + g.tableHeadH + n * g.tableRowH + Math.max(0, n - 1) * g.listGap + Math.round(g.u)
  } else if (layout === "ticker") {
    // one line of text moving across; one stop for the cursor
    line.captionH = 0
    line.rowH = g.tickerH
    line.height = g.titleH + g.tickerH + g.rowPad
  } else {
    line.height = g.titleH + cardH + captionH + g.rowPad
  }
  return line
}

// The model of a view (a screen, or an item's details): its lines, top to
// bottom, each with its own geometry and its place (y) in the list, and the
// screen around them (screen: the look in force, the top, the background,
// the details page, the titles and the size, each with where it came
// from; detailStyle on a details page).
// env: { width, u, layout (the guide's layout settings), learned (row
// shapes this app's rows learned: "r:<row id>" -> shape), defaults (the
// app's app.json row defaults: "d:<row id>" -> { shape, size, layout }),
// choices ({ mine, all, theme }: yours for this app, yours for all apps,
// the theme's; mine.rows: yours for its rows, "r:<row id>" -> { shape,
// size, layout, titles }), suggested (the app's suggested look) }
function model(view, env) {
  var g = geometry(env)
  var choices = env && env.choices
  var lk = lookOf(choices, env && env.suggested)
  var screen = screenOf(choices, lk.look)
  screen.lookFrom = lk.from
  // the top shows what's selected on a screen; a details page's own top
  // (its picture or backdrop, title, line and text) stands in for it
  screen.topShown = screen.top === "selected" && !!view && view.kind === "screen"
  var mine = own(choices, "mine")
  var ctx = { look: lk.look, screen: screen, rows: own(mine, "rows") }
  var lines = []
  var hidden = 0, shown = 0
  if (view && view.value) {
    if (view.kind === "detail" && view.value.actions && view.value.actions.length)
      lines.push({ kind: "actions", id: "", layout: "actions", items: view.value.actions, cols: 1, height: g.actionsH })
    arranged(view.value.rows || [], mine).forEach(function(r) {
      if (!r.items || !r.items.length) return
      var my = mineOf(r, ctx)
      if (my && my.show === false) { hidden++; return }                  // hidden: listed in Customize, not drawn
      var line = rowLine(r, g, env && env.learned, env && env.defaults, ctx)
      if (my && my.name) line.title = my.name
      lines.push(line)
      shown++
    })
  }
  var y = 0
  lines.forEach(function(l) { l.y = y; y += l.height })
  var out = { lines: lines, height: y, geometry: g, screen: screen, allHidden: hidden > 0 && shown === 0 }
  if (view && view.kind === "detail" && view.value) out.detailStyle = detailStyleOf(view.value, screen)
  return out
}

// Where a card or list row is in its line: { x, y, w, h }, relative to the
// line (y counts from the line's top)
function cellRect(line, col, g) {
  if (line.layout === "grid") {
    var r = Math.floor(col / Math.max(1, line.cols))
    return { x: (col % line.cols) * line.cellW, y: g.titleH + r * line.cellH, w: line.cardW, h: line.cardH + line.captionH }
  }
  if (line.layout === "list") return { x: 0, y: g.titleH + col * (line.rowH + line.rowGap), w: g.width - 2 * g.margin, h: line.rowH }
  if (line.layout === "table") return { x: 0, y: g.titleH + line.headH + col * (line.rowH + line.rowGap), w: g.width - 2 * g.margin, h: line.rowH }
  if (line.layout === "ticker") return { x: 0, y: g.titleH, w: g.width - 2 * g.margin, h: line.rowH }
  if (line.kind === "actions") return { x: 0, y: 0, w: 0, h: line.height }
  if (line.layout === "hero") return { x: 0, y: g.titleH, w: line.cardW, h: line.cardH }
  return { x: col * line.cellW, y: g.titleH, w: line.cardW, h: line.cardH + line.captionH }
}

// ---- checking choices -------------------------------------------------------
// Choices as given (a theme's apps object, or yours), checked: only the
// keys and values a screen takes. For a theme, "look" is the same as
// leaving a key out. A background picture (mode image) is taken only where
// imageOk(path) says it's one the guide copied in (a picture you picked);
// a theme's waits for the confirmed theme writer. Answers { choices,
// ignored }; ignored names what was left out and why.
function checkChoices(given, where, forTheme, imageOk) {
  var out = {}
  var ignored = []
  var name = function(k) { return where + "." + String(k).slice(0, 40) }
  if (given === null || typeof given !== "object" || Array.isArray(given))
    return { choices: out, ignored: [where + " (an object: look, top, details, titles, size, background)"] }
  for (var k in given) {
    var v = given[k]
    if (k === "look") {
      if (v === "app" || (typeof v === "string" && own(LOOKS, v))) out.look = v
      else ignored.push(name(k) + " (app, " + LOOK_NAMES.join(", ") + ")")
    } else if (own(CHOICES, k)) {
      if (v === "look") { if (!forTheme) out[k] = v }
      else if (CHOICES[k].indexOf(v) >= 0) out[k] = v
      else ignored.push(name(k) + " (" + CHOICES[k].concat(["look"]).join(", ") + ")")
    } else if (k === "background") {
      if (v === "look") { if (!forTheme) out.background = v; continue }
      var picture = v !== null && typeof v === "object" && v.mode === "image" && typeof v.image === "string" && typeof imageOk === "function" && imageOk(v.image)
      if (v === null || typeof v !== "object" || Array.isArray(v) || (["focus", "details", "guide", "wallpaper", "none"].indexOf(v.mode) < 0 && !picture)) {
        ignored.push(name(k) + " ({mode: focus, details, guide, wallpaper or none" + (typeof imageOk === "function" ? ", or image with a picture you picked" : "") + "; dim: 0 to 0.95})")
        continue
      }
      var b = { mode: v.mode }
      if (picture) b.image = v.image
      for (var bk in v) {
        if (bk === "mode" || (bk === "image" && picture)) continue
        if (bk === "dim" && typeof v.dim === "number" && isFinite(v.dim)) b.dim = Math.round(Math.max(0, Math.min(0.95, v.dim)) * 100) / 100
        else ignored.push(name(k) + "." + String(bk).slice(0, 40) + (bk === "dim" ? " (0 to 0.95)" : " (mode, image and dim)"))
      }
      out.background = b
    } else ignored.push(name(k) + " (look, top, details, titles, size or background)")
  }
  return { choices: out, ignored: ignored }
}

// ---- the shape a row learns ------------------------------------------------
// From the first 3 items by position whose pictures have settled (loaded,
// failed, or none to load): each loaded one's width over height under 0.8
// is a poster, 0.8 to 1.25 square (drawn whole), over 1.25 wide; the
// majority wins, and ties or no samples mean wide. It decides once the
// first positions have all settled (so the order pictures arrive in
// doesn't matter), or when force says 2 s have passed (then the first 3
// that have settled, by position). settled: { position: ratio, or 0 for
// failed or none }; count: the row's items. Answers the shape, or "" while
// it waits.
function autoShape(settled, count, force) {
  var k = Math.min(3, count)
  if (!force) for (var i = 0; i < k; i++) if (settled[i] === undefined) return ""
  var at = Object.keys(settled).map(Number).filter(function(p) { return p >= 0 }).sort(function(a, b) { return a - b }).slice(0, 3)
  var votes = { poster: 0, autoSquare: 0, wide: 0 }
  at.forEach(function(p) {
    var r = settled[p]
    if (r > 0) votes[r < 0.8 ? "poster" : r <= 1.25 ? "autoSquare" : "wide"] += 1
  })
  var best = "", most = 0, tie = false
  ;["poster", "autoSquare", "wide"].forEach(function(s) {
    if (votes[s] > most) { best = s; most = votes[s]; tie = false }
    else if (votes[s] === most && most > 0) tie = true
  })
  return !most || tie ? "wide" : best
}

// ---- contrast ----------------------------------------------------------------
// A color as { r, g, b, a } (0 to 1): "#rrggbb", "#aarrggbb", or none
function rgba(c) {
  var s = String(c === undefined || c === null ? "" : c).trim().toLowerCase()
  var m = /^#([0-9a-f]{2})?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/.exec(s)
  if (!m) return { r: 0, g: 0, b: 0, a: 0 }   // none, transparent, or not a color: nothing drawn
  return { r: parseInt(m[2], 16) / 255, g: parseInt(m[3], 16) / 255, b: parseInt(m[4], 16) / 255, a: m[1] === undefined ? 1 : parseInt(m[1], 16) / 255 }
}

function over(top, bottom) {
  var t = rgba(top), b = rgba(bottom)
  var a = t.a + b.a * (1 - t.a)
  if (a <= 0) return { r: 0, g: 0, b: 0, a: 0 }
  return { r: (t.r * t.a + b.r * b.a * (1 - t.a)) / a, g: (t.g * t.a + b.g * b.a * (1 - t.a)) / a, b: (t.b * t.a + b.b * b.a * (1 - t.a)) / a, a: a }
}

function hex(c) {
  var h = function(v) { return ("0" + Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16)).slice(-2) }
  return "#" + h(c.r) + h(c.g) + h(c.b)
}

// WCAG relative luminance of an opaque color
function luminance(c) {
  var lin = function(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
}

// The contrast between a color and what's behind it (a see-through one is
// laid over it first; the behind color over black, if it's see-through too)
function contrast(fg, behind) {
  var b = over(behind, "#000000")
  var f = over(fg, hex(b))
  var l1 = luminance(f), l2 = luminance(b)
  return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05)
}

function worst(fg, behinds) {
  var w = Infinity
  ;(behinds || []).forEach(function(b) { w = Math.min(w, contrast(fg, b)) })
  return w === Infinity ? 1 : w
}

// The ink or the background, whichever reads more against what's behind
function better(ink, background, behinds) {
  return worst(ink, behinds) >= worst(background, behinds) ? ink : background
}

// The focus ring's color: the accent where it reads (3:1) against every
// color around the card, else the ink or the background, whichever reads
// more. Always opaque: a theme can't make it see-through.
function ringColor(accent, ink, background, around) {
  var a = rgba(accent)
  if (a.a >= 1 && worst(accent, around) >= 3) return hex(a)
  return hex(over(better(ink, background, around), "#000000"))
}

// Where the ring's color doesn't reach 3:1 against everything around the
// card (an accent, ink and page all alike, say), a second band, black or
// white, whichever suits the ring better, so the ring is always seen.
// Answers that color, or "" for none.
function ringHalo(ring, around) {
  if (worst(ring, around) >= 3) return ""
  return contrast(ring, "#000000") >= contrast(ring, "#ffffff") ? "#000000" : "#ffffff"
}

// The selected title: its own color where it's opaque and reads (4.5:1)
// against what's behind it, else the ink or the background, whichever reads
// more; where neither does, a backing plate of black or white, whichever
// suits that color better. Answers { color, plate } (plate "" for none).
function titleColor(color, ink, background, behind) {
  var c = rgba(color)
  if (c.a >= 1 && worst(color, behind) >= 4.5) return { color: hex(c), plate: "" }
  var pick = hex(over(better(ink, background, behind), "#000000"))
  if (worst(pick, behind) >= 4.5) return { color: pick, plate: "" }
  return { color: pick, plate: contrast(pick, "#000000") >= contrast(pick, "#ffffff") ? "#000000" : "#ffffff" }
}

// A color as "#rrggbb", or "#aarrggbb" when it's see-through
function hexa(c) {
  if (c.a >= 1) return hex(c)
  return "#" + ("0" + Math.round(Math.max(0, Math.min(1, c.a)) * 255).toString(16)).slice(-2) + hex(c).slice(1)
}

// A gradient's colors, from one end to the other, in steps, see-through ones
// kept see-through. Qt blends them premultiplied, each color weighted by its
// own alpha (measured on the GPU and in software): a transparent end adds no
// color, and laid over the window, each step is the even blend of the two
// ends laid over it.
function blend(from, to, steps) {
  var a = rgba(from), b = rgba(to)
  var out = []
  for (var i = 0; i <= steps; i++) {
    var t = i / steps, alpha = a.a + (b.a - a.a) * t
    var k = alpha > 0 ? 1 / alpha : 0
    out.push(hexa({ r: (a.r * a.a * (1 - t) + b.r * b.a * t) * k, g: (a.g * a.a * (1 - t) + b.g * b.a * t) * k,
                    b: (a.b * a.a * (1 - t) + b.b * b.a * t) * k, a: alpha }))
  }
  return out
}

// The colors behind the page: a style's fill (a color, or a gradient's colors
// all along it, not just its ends)
function fillColors(fill) {
  if (fill && typeof fill === "object") return blend(String(fill.from), String(fill.to), 16)
  return [String(fill || "")]
}

// Every color that can be directly behind a card's title, or around a card:
// the page's fill, over the guide window's own color (a see-through fill
// shows it); or, over that, your picture (any color, or the page where the
// picture is see-through) under the dimming shade, which keeps its own
// alpha; and on a details screen, its backdrop (any color) at its opacity
// over all that. opts: { fill, base, picture, dim, dimColor, backdrop,
// backdropOpacity }; base is the window's color (bgBottom).
function behindColors(opts) {
  opts = opts || {}
  var grays = function(n) { var out = []; for (var i = 0; i <= n; i++) { var v = Math.round(255 * i / n); out.push(hex({ r: v / 255, g: v / 255, b: v / 255 })) } return out }
  // c with its own alpha times a
  var withAlpha = function(c, a) {
    var x = rgba(c)
    var h = ("0" + Math.round(Math.max(0, Math.min(1, x.a * a)) * 255).toString(16)).slice(-2)
    return "#" + h + hex(x).slice(1)
  }
  var window = hex(over(opts.base || "#000000", "#000000"))
  var base = fillColors(opts.fill).map(function(c) { return hex(over(c, window)) })
  if (opts.picture) {
    var shade = withAlpha(opts.dimColor || "#000000", opts.dim || 0)
    base = grays(8).concat(base).map(function(px) { return hex(over(shade, px)) })
  }
  if (!opts || !opts.backdrop) return base
  var out = []
  base.forEach(function(b) {
    grays(4).forEach(function(px) { out.push(hex(over(withAlpha(px, opts.backdropOpacity || 0), b))) })
  })
  return out
}

// ---- shades, one over another ---------------------------------------------------
// Two shades laid one over the other (each its color at its darkness; a
// see-through color counts at its own alpha), as one: { color, alpha }
function stackShades(lowColor, lowDark, highColor, highDark) {
  var l = rgba(lowColor), h = rgba(highColor)
  var la = Math.max(0, Math.min(1, lowDark)) * l.a
  var ha = Math.max(0, Math.min(1, highDark)) * h.a
  var a = 1 - (1 - la) * (1 - ha)
  if (a <= 0) return { color: "#000000", alpha: 0 }
  var mix = function(lc, hc) { return (hc * ha + lc * la * (1 - ha)) / a }
  return { color: hex({ r: mix(l.r, h.r), g: mix(l.g, h.g), b: mix(l.b, h.b) }), alpha: a }
}
// How much more shade lifts what's there to the floor (0 if it's there already)
function topUp(dark, floor) { return dark >= floor ? 0 : 1 - (1 - floor) / (1 - dark) }

// ---- your choices for rows (Customize) -----------------------------------------
var ROW_SHAPES = ["poster", "wide", "square", "logo", "circle"]
var ROW_KEYS = ["show", "name", "shape", "size", "layout", "titles"]
// A name you gave a row: plain text (no control characters), at most 40
// characters (code points, never half a pair)
function plainName(v) {
  if (typeof v !== "string") return ""
  var out = []
  for (var ch of v.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, " ").trim()) { if (out.length >= 40) break; out.push(ch) }
  return out.join("")
}
// Your choices for one row: shown or not, your name for it, its pictures,
// size, layout and titles. Answers { row, ignored }.
function checkRowChoices(given, where) {
  var out = {}
  var ignored = []
  if (given === null || typeof given !== "object" || Array.isArray(given)) return { row: out, ignored: [where + " (an object: show, name, shape, size, layout, titles)"] }
  for (var k in given) {
    var v = given[k]
    if (k === "show") { if (typeof v === "boolean") out.show = v; else ignored.push(where + ".show (true or false)") }
    else if (k === "name") {
      // plain text of at most 40 characters: a longer one is refused, never cut
      var t = typeof v === "string" ? v.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, " ").trim() : null
      if (t === null || Array.from(t).length > 40) ignored.push(where + ".name (text, at most 40 characters)")
      else if (t) out.name = t
    }
    else if (k === "shape") { if (ROW_SHAPES.indexOf(v) >= 0) out.shape = v; else ignored.push(where + ".shape (" + ROW_SHAPES.join(", ") + ")") }
    else if (k === "size") { if (CHOICES.size.indexOf(v) >= 0) out.size = v; else ignored.push(where + ".size (" + CHOICES.size.join(", ") + ")") }
    else if (k === "layout") { if (LAYOUTS.indexOf(v) >= 0) out.layout = v; else ignored.push(where + ".layout (" + LAYOUTS.join(", ") + ")") }
    else if (k === "titles") { if (CHOICES.titles.indexOf(v) >= 0) out.titles = v; else ignored.push(where + ".titles (" + CHOICES.titles.join(", ") + ")") }
    else ignored.push(where + "." + String(k).slice(0, 40) + " (" + ROW_KEYS.join(", ") + ")")
  }
  return { row: out, ignored: ignored }
}
// One app's entry as kept: its incarnation, its screen choices, its rows
// ("r:<row id>" -> choices; at most 40) and their order (at most 40 row
// ids). Maps never inherit (Object.create(null)). Answers { entry, ignored }.
function checkEntry(given, where, imageOk) {
  var ignored = []
  if (given === null || typeof given !== "object" || Array.isArray(given)) return { entry: null, ignored: [where + " (an object)"] }
  if (typeof given.incarnation !== "string" || !/^[0-9a-f]{16}$/.test(given.incarnation)) return { entry: null, ignored: [where + ".incarnation (16 hex digits)"] }
  var screen = {}
  for (var k in given) if (k !== "incarnation" && k !== "rows" && k !== "order") screen[k] = given[k]
  var c = checkChoices(screen, where, false, imageOk)
  var entry = { incarnation: given.incarnation }
  for (var ck in c.choices) entry[ck] = c.choices[ck]
  ignored = ignored.concat(c.ignored)
  var rows = Object.create(null)
  var n = 0
  if (given.rows !== undefined) {
    if (given.rows === null || typeof given.rows !== "object" || Array.isArray(given.rows)) ignored.push(where + ".rows (an object)")
    else for (var rk in given.rows) {
      if (rk.slice(0, 2) !== "r:" || rk.length < 3 || rk.length > 66) { ignored.push(where + ".rows (keys are r:<row id>)"); continue }
      if (n >= 40) { ignored.push(where + ".rows (at most 40)"); break }
      var r = checkRowChoices(given.rows[rk], where + ".rows")
      ignored = ignored.concat(r.ignored)
      if (Object.keys(r.row).length) { rows[rk] = r.row; n++ }
    }
  }
  if (n) entry.rows = rows
  if (given.order !== undefined) {
    var seen = Object.create(null)
    var order = Array.isArray(given.order) ? given.order.filter(function(id) {
      if (typeof id !== "string" || !id || id.length > 64 || seen["r:" + id]) return false
      seen["r:" + id] = true
      return true
    }).slice(0, 40) : []
    if (!Array.isArray(given.order) || order.length !== given.order.length) ignored.push(where + ".order (at most 40 row ids, each once)")
    if (order.length) entry.order = order
  }
  return { entry: entry, ignored: ignored }
}

// ---- saving a theme saves the all-apps look you see (§10) ----------------------
var SCREEN_KEYS = ["look", "top", "background", "details", "titles", "size"]
// The new theme's apps: the theme's on now, with yours for all apps over it
// key by key (a key you set wins, look and app included; one you left unset
// keeps the theme's). Each app's own choices stay out.
function appsForTheme(themeApps, all) {
  var out = {}
  SCREEN_KEYS.forEach(function(k) {
    var v = all && typeof all === "object" && Object.prototype.hasOwnProperty.call(all, k) ? all[k]
          : themeApps && typeof themeApps === "object" && Object.prototype.hasOwnProperty.call(themeApps, k) ? themeApps[k] : undefined
    if (v !== undefined) out[k] = JSON.parse(JSON.stringify(v))
  })
  return out
}
// Once that theme is on: the keys of yours for all apps that it now gives
// exactly (they're dropped, so the look doesn't change)
function allMatching(all, themeApps) {
  return SCREEN_KEYS.filter(function(k) {
    return all && themeApps && Object.prototype.hasOwnProperty.call(all, k) && Object.prototype.hasOwnProperty.call(themeApps, k)
           && JSON.stringify(all[k]) === JSON.stringify(themeApps[k])
  })
}

// The rows of a view as you arranged them: the ones you ordered first, in
// that order, the rest after them in the app's order
function arranged(rows, mine) {
  var order = mine && Array.isArray(mine.order) ? mine.order : []
  var at = Object.create(null)
  rows.forEach(function(r, i) { if (r && typeof r.id === "string") at["r:" + r.id] = i })
  var out = []
  var used = Object.create(null)
  order.forEach(function(id) { var k = "r:" + id; if (k in at && !used[k]) { out.push(rows[at[k]]); used[k] = true } })
  rows.forEach(function(r) { if (!(r && typeof r.id === "string" && used["r:" + r.id])) out.push(r) })
  return out
}

// ---- the identity strip (§11) -----------------------------------------------
// Its fill follows the theme while the theme's text reads on it (4.5:1),
// otherwise the guide's own; always opaque (a see-through fill is laid over
// black), so nothing under it shows through
var STRIP_OWN = { fill: "#101118", text: "#f2f2f2" }
function stripColors(fill, text) {
  var f = hex(over(fill, "#000000"))
  var t = rgba(text)
  if (t.a >= 1 && contrast(text, f) >= 4.5) return { fill: f, text: hex(t) }
  return { fill: STRIP_OWN.fill, text: STRIP_OWN.text }
}

// ---- how much a selected card or button grows -------------------------------
// A theme's or your grow, at most 15%: the rows keep room for that and the
// guide's ring round it, so a hostile grow can't push the ring out of sight
var MAX_GROW = 0.15
function growOf(style) {
  var g = style && typeof style.grow === "number" && isFinite(style.grow) ? style.grow : 0
  return Math.max(0, Math.min(MAX_GROW, g))
}

// ---- the 10-foot floors (§11) -----------------------------------------------
// Card text is at least max(12 px, 0.7 units); the top title at least 1.4
// units. Applied after themes and your styles.
var CARD_TEXT = { units: 0.7, px: 12 }
var TOP_TITLE = { units: 1.4, px: 0 }
// A text style no smaller than its floor at this unit: its size (in units)
// raised where it's under; factor is how much the drawing scales it
function floored(style, floor, u, factor) {
  var t = style && style.text ? style.text : null
  if (!t) return style
  var need = Math.max(floor.units, floor.px / num(u, 16)) / num(factor, 1)
  if (num(t.size, 1) >= need) return style
  var out = {}
  for (var k in style) out[k] = style[k]
  out.text = {}
  for (var j in t) out.text[j] = t[j]
  out.text.size = need
  return out
}
