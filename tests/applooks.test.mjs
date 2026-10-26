// node tests/applooks.test.mjs
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const L = new Function(readFileSync(new URL("../AppLooks.js", import.meta.url), "utf8").replace(".pragma library", "") +
  "; return { model, autoShape, cellRect, ringColor, ringHalo, titleColor, contrast, fillColors, behindColors, SHAPES, cardImage, FLOORS, " +
  "LOOKS, lookOf, screenOf, checkChoices, rowHas, detailStyleOf, backdropOf, logoOf, stripColors, floored, CARD_TEXT, TOP_TITLE, DIM, SHADE_FLOOR, growOf, MAX_GROW, stackShades, topUp, appsForTheme, allMatching }")()

// ---- auto shape -------------------------------------------------------------
const POSTER = 2 / 3, WIDE = 16 / 9
// three posters
assert.equal(L.autoShape({ 0: POSTER, 1: POSTER, 2: 0.7 }, 10, false), "poster")
// out of order: it waits for the first three positions, whatever arrives first
assert.equal(L.autoShape({ 2: WIDE }, 10, false), "", "waits for positions 0 and 1")
assert.equal(L.autoShape({ 2: WIDE, 0: POSTER }, 10, false), "", "still waits for position 1")
assert.equal(L.autoShape({ 2: WIDE, 0: POSTER, 1: POSTER }, 10, false), "poster")
assert.equal(L.autoShape({ 1: POSTER, 0: POSTER, 2: WIDE }, 10, false), "poster", "the same answer in any order")
// a later position settling first doesn't count toward the first three
assert.equal(L.autoShape({ 5: WIDE, 6: WIDE, 7: WIDE, 0: POSTER, 1: POSTER, 2: POSTER }, 10, false), "poster")
// ties and failures
assert.equal(L.autoShape({ 0: POSTER, 1: WIDE, 2: 0 }, 10, false), "wide", "a tie means wide")
assert.equal(L.autoShape({ 0: 0, 1: 0, 2: 0 }, 10, false), "wide", "no samples means wide")
assert.equal(L.autoShape({ 0: 0, 1: POSTER, 2: 0 }, 10, false), "poster", "one sample is a majority of one")
// mixed ratios: squares win two to one
assert.equal(L.autoShape({ 0: 1.0, 1: 1.1, 2: POSTER }, 10, false), "autoSquare")
// the boundaries: under 0.8 poster, 0.8 to 1.25 square, over 1.25 wide
assert.equal(L.autoShape({ 0: 0.79 }, 1, false), "poster")
assert.equal(L.autoShape({ 0: 0.8 }, 1, false), "autoSquare")
assert.equal(L.autoShape({ 0: 1.25 }, 1, false), "autoSquare")
assert.equal(L.autoShape({ 0: 1.26 }, 1, false), "wide")
// a short row needs only its own positions
assert.equal(L.autoShape({ 0: POSTER, 1: POSTER }, 2, false), "poster")
// after 2 s: the first three that settled, by position (position 0 never did)
assert.equal(L.autoShape({ 1: POSTER, 3: POSTER, 4: WIDE }, 10, false), "", "position 0 hasn't settled")
assert.equal(L.autoShape({ 1: POSTER, 3: POSTER, 4: WIDE, 6: WIDE, 7: WIDE }, 10, true), "poster")
assert.equal(L.autoShape({}, 10, true), "wide", "nothing settled in 2 s: wide")

// ---- the model's geometry ---------------------------------------------------
const env = { width: 1280, u: 10, layout: { libraryPosterWidth: 8.6, libraryThumbWidth: 15.5 } }
const row = (id, layout, n) => ({ id, title: id, layout, items: Array.from({ length: n }, (_, i) => ({ id: id + i, title: "t", kind: "open" })) })
const screen = { kind: "screen", value: { rows: [row("p", "row", 4), row("w", "row", 4), row("s", "grid", 9), row("l", "list", 3)] } }
let m = L.model(screen, Object.assign({}, env, { learned: { "r:p": "poster", "r:s": "autoSquare", "r:l": "poster" } }))
const [p, w, s, l] = m.lines
assert.deepEqual([p.shape, p.cardW, p.cardH, p.fit], ["poster", 86, 129, "fill"], "a poster is 2:3, filled")
assert.deepEqual([w.shape, w.cardW, w.cardH, w.fit], ["wide", 155, 87, "fill"], "wide (unlearned) is 16:9, filled")
assert.deepEqual([s.shape, s.cardW, s.cardH, s.fit], ["autoSquare", 100, 100, "fit"], "a learned square is drawn whole")
assert.equal(s.cols, Math.floor((1280 - 40 + 12) / 112), "a grid's columns from its own cards")
assert.equal(s.height, 26 + Math.ceil(9 / s.cols) * s.cellH + 10)
assert.deepEqual([l.picH, l.picW], [26, 17], "a list row's picture takes the row's shape")
assert.deepEqual(m.lines.map(x => x.y), [0, p.height, p.height + w.height, p.height + w.height + s.height], "each line's place")
assert.equal(m.height, p.height + w.height + s.height + l.height)
// a grid cell's place, and a row's card (its box and caption, not the whole line)
assert.deepEqual(L.cellRect(s, s.cols + 1, m.geometry), { x: 112, y: 26 + s.cellH, w: 100, h: 100 + 36 })
assert.deepEqual(L.cellRect(p, 2, m.geometry), { x: 2 * p.cellW, y: 26, w: 86, h: 129 + 36 })
// an unknown learned shape is ignored; no env at all still makes a model
m = L.model(screen, { learned: { "r:p": "bogus" } })
assert.equal(m.lines[0].shape, "wide")
assert.equal(m.geometry.u, 16)
assert.equal(m.geometry.width, 1280)
// a detail's actions come first
const detail = { kind: "detail", value: { title: "D", actions: [{ id: "a", label: "A", kind: "play" }], rows: [row("more", "row", 2)] } }
m = L.model(detail, env)
assert.deepEqual(m.lines.map(x => x.kind), ["actions", "row"])

// ---- the focus ring -----------------------------------------------------------
const NAVY = ["#0a1a3a", "#050d1e"]
// the accent reads against the page: it's the ring
assert.equal(L.ringColor("#ffcc00", "#f2f2f2", "#0a1a3a", NAVY), "#ffcc00")
// hostile: the accent is the background's own color, see-through, or none
assert.equal(L.ringColor("#0a1a3a", "#f2f2f2", "#0a1a3a", NAVY), "#f2f2f2", "an accent like the background gives way to the ink")
assert.equal(L.ringColor("#80ffcc00", "#f2f2f2", "#0a1a3a", NAVY), "#f2f2f2", "a see-through accent gives way")
assert.equal(L.ringColor("transparent", "#f2f2f2", "#0a1a3a", NAVY), "#f2f2f2", "none gives way")
// on a light page, a pale accent gives way to whichever of ink and background reads more
assert.equal(L.ringColor("#ffff66", "#ffffff", "#101010", ["#fafafa", "#eeeeee"]), "#101010")
// against a gradient, both ends count: mid-gray reads against both black and
// white (5.9 and 3.6), a pale gray only against black
assert.equal(L.ringColor("#888888", "#ffffff", "#000000", ["#000000", "#ffffff"]), "#888888")
assert.equal(L.ringColor("#dddddd", "#ffffff", "#000000", ["#000000", "#ffffff"]), "#ffffff")

// accent, ink and page all alike: no single color reads, so the ring gets a halo
assert.equal(L.ringColor("#777777", "#777777", "#777777", ["#777777"]), "#777777")
assert.notEqual(L.ringHalo("#777777", ["#777777"]), "", "a halo")
assert.ok(L.contrast(L.ringHalo("#777777", ["#777777"]), "#777777") >= 3, "and the halo reads against the page")
assert.equal(L.ringHalo("#ffd23f", NAVY), "", "a ring that reads needs none")

// ---- the selected title -------------------------------------------------------
assert.deepEqual(L.titleColor("#f2f2f2", "#f2f2f2", "#0a1a3a", NAVY), { color: "#f2f2f2", plate: "" })
// hostile: transparent, the page's own color, see-through
assert.deepEqual(L.titleColor("transparent", "#f2f2f2", "#0a1a3a", NAVY), { color: "#f2f2f2", plate: "" })
assert.deepEqual(L.titleColor("#0a1a3a", "#f2f2f2", "#0a1a3a", NAVY), { color: "#f2f2f2", plate: "" })
assert.deepEqual(L.titleColor("#80f2f2f2", "#f2f2f2", "#0a1a3a", NAVY), { color: "#f2f2f2", plate: "" }, "drawn opaque: a see-through color gives way")
// the ink and the background both like the page: a backing plate
const t = L.titleColor("#0a1a3a", "#0a1a3a", "#0a1a3a", NAVY)
assert.equal(t.color, "#0a1a3a")
assert.equal(t.plate, "#ffffff")
assert.ok(L.contrast(t.color, t.plate) >= 4.5, "the plate makes it read")
// a mid-gray page: neither ink nor background reaches 4.5 against both ends, so a plate
const g = L.titleColor("#777777", "#777777", "#787878", ["#767676", "#7a7a7a"])
assert.notEqual(g.plate, "")
// the page's colors: a gradient's all along it, or one color
const bw = L.fillColors({ from: "#000000", to: "#ffffff", direction: "down" })
assert.equal(bw.length, 17)
assert.deepEqual([bw[0], bw[8], bw[16]], ["#000000", "#808080", "#ffffff"])
assert.deepEqual(L.fillColors("#123456"), ["#123456"])

// a gray that reads against both ends of a black-to-white gradient doesn't
// read in its middle: it gives way, and the ring's mid-gray accent too
const g2 = L.titleColor("#757575", "#ffffff", "#000000", bw)
assert.notEqual(g2.color, "#757575", "not accepted against the gradient's middle")
assert.notEqual(g2.plate, "", "nothing reads against all of it: a plate")
assert.notEqual(L.ringColor("#888888", "#ffffff", "#000000", bw), "#888888")

// behind a title: the page; your picture under its shade; a details backdrop over either
const navy = L.behindColors({ fill: "#071447" })
assert.deepEqual(navy, ["#071447"])
const pic = L.behindColors({ fill: "#071447", picture: true, dim: 0.6, dimColor: "#030a2b" })
assert.equal(pic.length, 10, "a picture can be any color (black to white) or see-through (the page), under the shade")
assert.ok(L.contrast("#ffffff", pic[8]) < L.contrast("#ffffff", pic[0]), "a white picture region is the hardest for a light title")
const back = L.behindColors({ fill: "#000000", backdrop: true, backdropOpacity: 0.22 })
assert.equal(back.length, 5)
// a gray title accepted against plain black isn't against a white backdrop region over it
assert.deepEqual(L.titleColor("#757575", "#f2f2f2", "#000000", ["#000000"]), { color: "#757575", plate: "" })
assert.notEqual(L.titleColor("#757575", "#f2f2f2", "#000000", back).color, "#757575")
// a see-through page shows the window's own color: white text over a
// transparent page on a white window isn't white on "transparent"
const seeThrough = L.behindColors({ fill: "transparent", base: "#ffffff" })
assert.deepEqual(seeThrough, ["#ffffff"])
assert.notEqual(L.titleColor("#ffffff", "#ffffff", "#ffffff", seeThrough).plate, "", "nothing white reads on white: a plate")
assert.notEqual(L.ringHalo(L.ringColor("#ffffff", "#ffffff", "#ffffff", seeThrough), seeThrough), "", "and the ring gets its halo")
// a see-through gradient shows the window all along it
const clearGradient = L.behindColors({ fill: { from: "transparent", to: "transparent", direction: "down" }, base: "#ffffff" })
assert.ok(clearGradient.every(c => c === "#ffffff"), "transparent to transparent over white: white everywhere: " + clearGradient)
assert.notEqual(L.titleColor("#ffffff", "#ffffff", "#ffffff", clearGradient).plate, "", "white on it gets a plate")
assert.notEqual(L.ringHalo(L.ringColor("#ffffff", "#ffffff", "#ffffff", clearGradient), clearGradient), "", "and the ring a halo")
const halfGradient = L.behindColors({ fill: { from: "#80000000", to: "#80000000", direction: "down" }, base: "#ffffff" })
assert.ok(halfGradient.every(c => c === "#7f7f7f"), "half see-through black over white: mid-gray all along: " + halfGradient)
// a gradient from opaque black to transparent, over white: black to white
const fade = L.behindColors({ fill: { from: "#000000", to: "transparent", direction: "down" }, base: "#ffffff" })
assert.deepEqual([fade[0], fade[16]], ["#000000", "#ffffff"])
// ends see-through by different amounts blend premultiplied, as Qt draws
// them: half red to solid blue over white, a quarter, half and three quarters
// along (grabbed from Qt, on the GPU and in software)
const near = (x, y) => [1, 3, 5].every(i => Math.abs(parseInt(x.substr(i, 2), 16) - parseInt(y.substr(i, 2), 16)) <= 1)
const mixed = L.behindColors({ fill: { from: "#80ff0000", to: "#ff0000ff", direction: "down" }, base: "#ffffff" })
for (const [i, drawn] of [[4, "#bf5f9f"], [8, "#7f3fbf"], [12, "#3f1fdf"]])
  assert.ok(near(mixed[i], drawn), "step " + i + " is " + mixed[i] + ", Qt draws " + drawn)
// a red fading out stays red as it thins: the transparent end adds no black
const thin = L.behindColors({ fill: { from: "#ff0000", to: "transparent", direction: "down" }, base: "#ffffff" })
assert.ok(near(thin[8], "#ff8080"), "half way, half red over white: " + thin[8])
// half red to quarter blue over white: half way, Qt draws #df9fbf
const quarter = L.behindColors({ fill: { from: "#80ff0000", to: "#400000ff", direction: "down" }, base: "#ffffff" })
assert.ok(near(quarter[8], "#df9fbf"), "half way: " + quarter[8])
// a ring that read only against the straight blend (3.006:1) gets its halo
// against what's drawn (a quarter along, #bf58bf: 2.33:1)
const magenta = L.behindColors({ fill: { from: "#20ffffff", to: "#ff00ff00", direction: "down" }, base: "#ff00ff" })
assert.ok(near(magenta[4], "#bf58bf"), "a quarter along: " + magenta[4])
const gray = L.ringColor("#484848", "#484848", "#484848", magenta)
assert.notEqual(L.ringHalo(gray, magenta), "", "the ring " + gray + " gets its halo")

// half see-through fill over a white window
assert.deepEqual(L.behindColors({ fill: "#80000000", base: "#ffffff" }), ["#7f7f7f"])
// the shade keeps its own alpha: a half see-through shade at full dim is half
const shaded = L.behindColors({ fill: "#000000", picture: true, dim: 1, dimColor: "#80000000" })
assert.ok(shaded.indexOf("#808080") >= 0 || shaded.indexOf("#7f7f7f") >= 0, "a white picture region under a half shade is mid-gray: " + shaded)
// a see-through part of the picture shows the page under the shade
assert.ok(L.behindColors({ fill: "#ff0000", picture: true, dim: 0, dimColor: "#000000" }).indexOf("#ff0000") >= 0)

// Retro's own title still reads over a backdrop on its navy
assert.deepEqual(L.titleColor("#f2f4ff", "#f2f4ff", "#071447", L.behindColors({ fill: { from: "#071447", to: "#030a2b" }, backdrop: true, backdropOpacity: 0.22 })),
                 { color: "#f2f4ff", plate: "" })

console.log("applooks: all passed")

// ---- milestone 1: the app's hints and app.json defaults (§3, §4.1, §5) -----
{
  const env1 = { width: 1280, u: 10, layout: { libraryPosterWidth: 8.6, libraryThumbWidth: 15.5, librarySquareWidth: 10 } }
  const items = [{ id: "a", title: "A", image: { token: "img" }, images: { poster: { token: "pos" }, wide: { token: "wid" }, logo: { token: "log" } } }]
  const row = (id, extra) => Object.assign({ id, title: id, items }, extra || {})
  const defaults = { "d:latest": { id: "latest", shape: "poster", size: "large", layout: "grid" }, "d:lib-x": { id: "lib-x", shape: "wide" },
                     "d:hero": { id: "hero", layout: "hero" } }
  const screen1 = { kind: "screen", value: { rows: [
    row("hinted", { shape: "logo", size: "small", layout: "list" }),   // the app's hint wins over everything below it
    row("latest"),                                                     // app.json's default
    row("lib-x", { shape: "poster" }),                                 // the hint beats app.json
    row("learned"),                                                    // what it learned
    row("auto"),                                                       // still deciding
    row("hero", { layout: null }),                                     // app.json says hero
    row("asked-hero", { layout: "hero" }) ] } }
  const m1 = L.model(screen1, Object.assign({}, env1, { defaults, learned: { "r:learned": "poster", "r:latest": "wide", "r:lib-x": "square" } }))
  const by = Object.fromEntries(m1.lines.map(l => [l.id, l]))
  assert.deepEqual([by.hinted.shape, by.hinted.from, by.hinted.size, by.hinted.layout], ["logo", "app", "small", "list"])
  assert.deepEqual([by.latest.shape, by.latest.from, by.latest.size, by.latest.layout], ["poster", "app", "large", "grid"], "app.json beats what it learned")
  assert.deepEqual([by["lib-x"].shape, by["lib-x"].from], ["poster", "app"], "the row's hint beats app.json")
  assert.deepEqual([by.learned.shape, by.learned.from, by.learned.size, by.learned.layout], ["poster", "learned", "medium", "row"])
  assert.deepEqual([by.auto.shape, by.auto.from], ["wide", "auto"])
  assert.deepEqual([by.hero.layout, by["asked-hero"].layout], ["hero", "hero"], "heroes draw as heroes (milestone 2)")
  // sizes: 0.72, 1, 1.4 of the library width, never under its minimum
  assert.equal(by.latest.cardW, Math.round(10 * 8.6 * 1.4), "a large poster")
  assert.equal(by.hinted.cardW, Math.round(10 * 10 * 0.72), "a small logo, over its floor")
  const tiny = L.model({ kind: "screen", value: { rows: [row("p", { shape: "poster", size: "small" }), row("w", { shape: "wide", size: "small" }), row("s", { shape: "square", size: "small" })] } },
                       { width: 1280, u: 10, layout: { libraryPosterWidth: 5, libraryThumbWidth: 9, librarySquareWidth: 5 } })
  assert.deepEqual(tiny.lines.map(l => l.cardW), [10 * L.FLOORS.poster, 10 * L.FLOORS.thumb, 10 * L.FLOORS.square], "small at the minimum widths stays at them")
  // which picture a card shows
  const pic = id => L.cardImage(items[0], by[id])
  assert.equal(pic("latest").token, "pos", "a poster row: the item's poster")
  assert.equal(pic("hinted").token, "log", "a logo row: its logo")
  assert.equal(pic("auto").token, "img", "still deciding: its own image, what it learns from")
  assert.equal(pic("learned").token, "pos", "learned posters: its poster")
  assert.equal(L.cardImage({ id: "b", title: "B", image: { token: "only" } }, by.latest).token, "only", "no poster: its image")
  assert.equal(L.cardImage({ id: "c", title: "C" }, by.latest), null, "neither: the title")
  const circ = L.model({ kind: "screen", value: { rows: [row("cast", { shape: "circle" }), row("sq")] } }, Object.assign({}, env1, { learned: { "r:sq": "autoSquare" } }))
  assert.equal(L.cardImage(items[0], circ.lines[0]).token, "img", "a circle shows the item's own image")
  assert.equal(L.cardImage(items[0], circ.lines[1]).token, "img", "a learned square shows its own image")
  // row ids that are object keys elsewhere don't reach the defaults' prototype
  const odd = L.model({ kind: "screen", value: { rows: [row("__proto__"), row("constructor"), row("hasOwnProperty")] } }, Object.assign({}, env1, { defaults }))
  assert.deepEqual(odd.lines.map(l => [l.shape, l.size, l.layout]), [["wide", "medium", "row"], ["wide", "medium", "row"], ["wide", "medium", "row"]])
}

console.log("applooks: milestone 1 passed")

// ---- milestone 2: the looks and the precedence table (§3, §4.7) -----------
{
  const env2 = { width: 1280, u: 10, layout: { libraryPosterWidth: 8.6, libraryThumbWidth: 15.5, librarySquareWidth: 10 } }
  const mk = (n, pics) => Array.from({ length: n }, (_, i) => Object.assign({ id: "i" + i, title: "T" + i }, pics(i)))
  const both = mk(3, i => ({ image: { token: "img" + i }, images: { poster: { token: "p" + i }, wide: { token: "w" + i }, backdrop: { token: "b" + i } } }))
  const logos = mk(3, i => ({ image: { token: "img" + i }, images: { logo: { token: "l" + i } } }))
  const posterOnly = mk(3, i => ({ images: { poster: { token: "p" + i } } }))
  const plain = mk(3, i => ({ image: { token: "img" + i } }))
  const row = (id, items, extra) => Object.assign({ id, title: id, items }, extra || {})
  const screenOf = rows => ({ kind: "screen", value: { rows } })
  const at = (m, id) => m.lines.find(l => l.id === id)

  // ---- the look in force: yours for this app, all apps, the theme, the app, Classic
  assert.deepEqual(L.lookOf({}, ""), { look: "classic", from: "default" })
  assert.deepEqual(L.lookOf({}, "posters"), { look: "posters", from: "app" })
  assert.deepEqual(L.lookOf({ theme: { look: "wall" } }, "posters"), { look: "wall", from: "theme" }, "the theme beats the app")
  assert.deepEqual(L.lookOf({ all: { look: "compact" }, theme: { look: "wall" } }, "posters"), { look: "compact", from: "all" })
  assert.deepEqual(L.lookOf({ mine: { look: "cinematic" }, all: { look: "compact" } }, "posters"), { look: "cinematic", from: "mine" })
  // "app" at a layer hands it to the app's suggestion, skipping the layers under it
  assert.deepEqual(L.lookOf({ mine: { look: "app" }, all: { look: "compact" } }, "posters"), { look: "posters", from: "app" })
  assert.deepEqual(L.lookOf({ all: { look: "app" }, theme: { look: "wall" } }, ""), { look: "classic", from: "default" }, "app, and the app suggests none: Classic")
  // nonsense and prototype names are ignored
  assert.deepEqual(L.lookOf({ mine: { look: "toString" }, all: { look: "__proto__" }, theme: { look: 3 } }, "constructor"), { look: "classic", from: "default" })
  assert.deepEqual(L.lookOf(null, undefined), { look: "classic", from: "default" })

  // ---- screen properties: the first set wins, then the look's, then Classic's
  let sc = L.screenOf({}, "cinematic")
  assert.deepEqual([sc.top, sc.details, sc.titles, sc.size, sc.background.mode], ["selected", "cinematic", "selected", "large", "focus"])
  assert.ok(Object.values(sc.from).every(f => f === "look"))
  sc = L.screenOf({ theme: { top: "off", size: "small" } }, "cinematic")
  assert.deepEqual([sc.top, sc.from.top, sc.size, sc.from.size, sc.details, sc.from.details], ["off", "theme", "small", "theme", "cinematic", "look"])
  sc = L.screenOf({ all: { top: "selected" }, theme: { top: "off" } }, "classic")
  assert.deepEqual([sc.top, sc.from.top], ["selected", "all"], "yours for all apps beats the theme")
  sc = L.screenOf({ mine: { titles: "off" }, all: { titles: "selected" } }, "classic")
  assert.deepEqual([sc.titles, sc.from.titles], ["off", "mine"])
  // "look" at a layer hands it to the look, skipping what's under it
  sc = L.screenOf({ mine: { size: "look" }, all: { size: "large" } }, "wall")
  assert.deepEqual([sc.size, sc.from.size], ["small", "look"])
  sc = L.screenOf({ all: { details: "look" }, theme: { details: "classic" } }, "cinematic")
  assert.deepEqual([sc.details, sc.from.details], ["cinematic", "look"])
  // the background: whole, with its dim (the default when it gives none)
  sc = L.screenOf({ theme: { background: { mode: "wallpaper", dim: 0.4 } } }, "cinematic")
  assert.deepEqual([sc.background, sc.from.background], [{ mode: "wallpaper", image: "", dim: 0.4 }, "theme"])
  sc = L.screenOf({ mine: { background: "look" }, theme: { background: { mode: "none" } } }, "cinematic")
  assert.deepEqual([sc.background, sc.from.background], [{ mode: "focus", image: "", dim: L.DIM }, "look"])
  sc = L.screenOf({ all: { background: { mode: "focus", dim: 7 } } }, "classic")
  assert.equal(sc.background.dim, 0.95, "darken stops at 0.95")
  sc = L.screenOf({ all: { background: { mode: "image" } } }, "classic")
  assert.equal(sc.from.background, "look", "a picture background with no picture isn't one")
  // the five looks' own values (§4.7)
  const looks = Object.fromEntries(["classic", "posters", "cinematic", "wall", "compact"].map(n => [n, L.screenOf({}, n)]))
  assert.deepEqual(Object.values(looks).map(x => [x.size, x.titles, x.top, x.background.mode, x.details]), [
    ["app", "below", "off", "details", "app"], ["app", "below", "off", "details", "app"], ["large", "selected", "selected", "focus", "cinematic"],
    ["small", "off", "selected", "focus", "app"], ["small", "below", "off", "none", "classic"]])
  assert.deepEqual(L.screenOf({}, "bogus").look, "classic")

  // ---- row shape: yours, the look's picture rule (where the items have it), the hint, app.json, learned, auto
  const rows = [row("both", both), row("logos", logos, { shape: "logo" }), row("hinted", both, { shape: "wide" }), row("plain", plain),
                row("posterOnly", posterOnly), row("dflt", both)]
  const defaults = { "d:dflt": { id: "dflt", shape: "square" } }
  let m = L.model(screenOf(rows), Object.assign({}, env2, { suggested: "posters", defaults }))
  assert.equal(m.screen.look, "posters")
  assert.deepEqual(["both", "logos", "hinted", "plain", "posterOnly", "dflt"].map(id => [at(m, id).shape, at(m, id).from]),
    [["poster", "look"], ["logo", "app"], ["poster", "look"], ["wide", "auto"], ["poster", "look"], ["poster", "look"]],
    "posters wherever there are any: a row of logos stays logos, one without posters as the app says")
  m = L.model(screenOf(rows), Object.assign({}, env2, { suggested: "cinematic", defaults }))
  assert.deepEqual(["both", "logos", "hinted", "posterOnly", "dflt"].map(id => [at(m, id).shape, at(m, id).from]),
    [["wide", "look"], ["logo", "app"], ["wide", "look"], ["wide", "auto"], ["wide", "look"]], "wide wherever there are any")
  m = L.model(screenOf(rows), Object.assign({}, env2, { suggested: "classic", defaults }))
  assert.deepEqual(["both", "hinted", "dflt"].map(id => [at(m, id).shape, at(m, id).from]), [["wide", "auto"], ["wide", "app"], ["square", "app"]], "Classic: as the app says")
  // yours for a row beats the look
  m = L.model(screenOf(rows), Object.assign({}, env2, { suggested: "posters", choices: { mine: { rows: { "r:both": { shape: "circle" }, "r:logos": { shape: "autoSquare" } } } } }))
  assert.deepEqual([at(m, "both").shape, at(m, "both").from, at(m, "logos").shape], ["circle", "mine", "logo"], "a learned-only shape isn't a choice")
  // which items count: one with no picture at all doesn't stop a row; one with another picture does
  assert.equal(L.rowHas({ items: [{ images: { poster: {} } }, { title: "none" }] }, "poster"), true)
  assert.equal(L.rowHas({ items: [{ images: { poster: {} } }, { image: { token: "x" } }] }, "poster"), false)
  assert.equal(L.rowHas({ items: [{ images: { poster: {} } }, { images: { wide: {} } }] }, "poster"), false)
  assert.equal(L.rowHas({ items: [{ title: "a" }, { title: "b" }] }, "poster"), false, "none has it: no switch")
  assert.equal(L.rowHas({ items: [{ images: { __proto__: { poster: {} } } }] }, "poster"), false, "only its own pictures")

  // ---- row size: yours, the screen's (1–3), the look's (unless app), the hint, app.json, medium
  const srows = [row("h", plain, { size: "large" }), row("d", plain), row("n", plain)]
  const sdef = { "d:d": { id: "d", size: "small" } }
  m = L.model(screenOf(srows), Object.assign({}, env2, { defaults: sdef }))
  assert.deepEqual(m.lines.map(l => [l.size, l.sizeFrom]), [["large", "app"], ["small", "app"], ["medium", "default"]], "Classic: as the app says")
  m = L.model(screenOf(srows), Object.assign({}, env2, { defaults: sdef, suggested: "wall" }))
  assert.deepEqual(m.lines.map(l => [l.size, l.sizeFrom]), [["small", "look"], ["small", "look"], ["small", "look"]], "the look's size beats the hint")
  m = L.model(screenOf(srows), Object.assign({}, env2, { defaults: sdef, suggested: "wall", choices: { theme: { size: "medium" } } }))
  assert.deepEqual(m.lines.map(l => l.size), ["medium", "medium", "medium"], "the theme's size beats the look's")
  m = L.model(screenOf(srows), Object.assign({}, env2, { defaults: sdef, suggested: "wall", choices: { all: { size: "look" }, theme: { size: "medium" } } }))
  assert.deepEqual(m.lines.map(l => l.size), ["small", "small", "small"], "look at a layer: the look's")
  m = L.model(screenOf(srows), Object.assign({}, env2, { defaults: sdef, choices: { mine: { size: "large", rows: { "r:n": { size: "small" } } } } }))
  assert.deepEqual(m.lines.map(l => [l.size, l.sizeFrom]), [["large", "mine"], ["large", "mine"], ["small", "mine"]], "yours for the row first")

  // ---- row layout: yours (hero only where the app made one), the hint, app.json, row
  const lrows = [row("g", plain, { layout: "grid" }), row("hd", plain), row("x", plain)]
  m = L.model(screenOf(lrows), Object.assign({}, env2, { defaults: { "d:hd": { id: "hd", layout: "hero" } } }))
  assert.deepEqual(m.lines.map(l => [l.layout, l.layoutFrom]), [["grid", "app"], ["hero", "app"], ["row", "default"]])
  m = L.model(screenOf(lrows), Object.assign({}, env2, { defaults: { "d:hd": { id: "hd", layout: "hero" } },
    choices: { mine: { rows: { "r:g": { layout: "list" }, "r:hd": { layout: "row" }, "r:x": { layout: "hero" } } } } }))
  assert.deepEqual(m.lines.map(l => [l.layout, l.layoutFrom]), [["list", "mine"], ["row", "mine"], ["row", "default"]], "a hero only where the app made one")
  m = L.model(screenOf(lrows), Object.assign({}, env2, { suggested: "cinematic", defaults: { "d:hd": { id: "hd", layout: "hero" } } }))
  assert.deepEqual(m.lines.map(l => l.layout), ["grid", "hero", "row"], "a look never re-lays-out rows")

  // ---- titles: yours, the screen's, the look's, below; off only with the top on
  m = L.model(screenOf([row("a", plain)]), Object.assign({}, env2, { suggested: "wall" }))
  assert.deepEqual([at(m, "a").titles, at(m, "a").titlesFrom, at(m, "a").captionH], ["off", "look", 0], "Wall: off (its top shows the title)")
  m = L.model(screenOf([row("a", plain)]), Object.assign({}, env2, { suggested: "wall", choices: { mine: { top: "off" } } }))
  assert.deepEqual([at(m, "a").titles, at(m, "a").captionH > 0], ["selected", true], "off without the top: the selected card keeps its title")
  m = L.model(screenOf([row("a", plain)]), Object.assign({}, env2, { suggested: "cinematic", choices: { theme: { titles: "below" } } }))
  assert.deepEqual([at(m, "a").titles, at(m, "a").titlesFrom], ["below", "theme"])
  m = L.model(screenOf([row("a", plain)]), Object.assign({}, env2, { choices: { mine: { titles: "off", top: "selected", rows: { "r:a": { titles: "below" } } } } }))
  assert.deepEqual([at(m, "a").titles, at(m, "a").titlesFrom], ["below", "mine"], "yours for the row first")
  // a details page has its own top: off there keeps the selected title
  const dpage = { kind: "detail", value: { title: "D", actions: [], rows: [row("a", plain)] } }
  m = L.model(dpage, Object.assign({}, env2, { suggested: "wall" }))
  assert.deepEqual([m.screen.top, m.screen.topShown, at(m, "a").titles], ["selected", false, "selected"])
  const off = L.model(screenOf([row("a", plain)]), Object.assign({}, env2, { suggested: "wall" })).lines[0]
  const below = L.model(screenOf([row("a", plain)]), Object.assign({}, env2, { choices: { theme: { size: "small" } } })).lines[0]
  assert.equal(below.height - off.height, below.captionH, "no captions: the row is shorter by them")

  // ---- hero geometry: one item across, its own height; a cell is the whole of it
  m = L.model(screenOf([row("hero", both, { layout: "hero" })]), env2)
  const hl = m.lines[0]
  assert.deepEqual([hl.cardW, hl.cardH, hl.captionH, hl.height], [1280 - 40, 220, 0, 26 + 220 + 16])
  assert.deepEqual(L.cellRect(hl, 2, m.geometry), { x: 0, y: 26, w: 1240, h: 220 })

  // ---- details: yours (the screen's), the look's own, the app's, classic
  const dv = style => ({ kind: "detail", value: { title: "D", style, actions: [], rows: [] } })
  assert.equal(L.model(dv("cinematic"), env2).detailStyle, "cinematic", "Classic follows the app")
  assert.equal(L.model(dv(undefined), env2).detailStyle, "classic")
  assert.equal(L.model(dv("cinematic"), Object.assign({}, env2, { suggested: "compact" })).detailStyle, "classic", "Compact sets its own")
  assert.equal(L.model(dv(undefined), Object.assign({}, env2, { suggested: "cinematic" })).detailStyle, "cinematic", "Cinematic sets its own")
  assert.equal(L.model(dv("cinematic"), Object.assign({}, env2, { suggested: "wall" })).detailStyle, "cinematic", "Wall follows the app")
  assert.equal(L.model(dv(undefined), Object.assign({}, env2, { suggested: "cinematic", choices: { mine: { details: "classic" } } })).detailStyle, "classic", "yours beats the look")
  assert.equal(L.model(dv("cinematic"), Object.assign({}, env2, { suggested: "compact", choices: { mine: { details: "app" } } })).detailStyle, "cinematic", "as the app says, chosen")
  assert.equal(L.model({ kind: "screen", value: { rows: [] } }, env2).detailStyle, undefined, "only on a details page")

  // ---- the pictures behind: backdrop, else wide, else none; a logo, else none
  assert.equal(L.backdropOf(both[0]).token, "b0")
  assert.equal(L.backdropOf({ images: { wide: { token: "w" } } }).token, "w")
  assert.equal(L.backdropOf({ image: { token: "i" } }), null, "never the card's own picture")
  assert.equal(L.backdropOf({ backdrop: { token: "db" } }).token, "db", "a details page's backdrop")
  assert.equal(L.logoOf({ images: { logo: { token: "l" } } }).token, "l")
  assert.equal(L.logoOf({ logo: { token: "dl" } }).token, "dl")
  assert.equal(L.logoOf({ title: "x" }), null)

  // ---- choices as given (a theme's apps object)
  let c = L.checkChoices({ look: "wall", top: "off", details: "cinematic", titles: "selected", size: "large", background: { mode: "wallpaper", dim: 0.333 } }, "apps", true)
  assert.deepEqual([c.choices, c.ignored], [{ look: "wall", top: "off", details: "cinematic", titles: "selected", size: "large", background: { mode: "wallpaper", dim: 0.33 } }, []])
  c = L.checkChoices({ look: "app", top: "look", background: "look" }, "apps", true)
  assert.deepEqual([c.choices, c.ignored], [{ look: "app" }, []], "for a theme, look is the same as leaving it out")
  c = L.checkChoices({ top: "look", background: "look" }, "apps", false)
  assert.deepEqual(c.choices, { top: "look", background: "look" }, "yours may say look")
  c = L.checkChoices({ look: "neon", top: 1, size: "huge", background: { mode: "image", image: "/x.png" }, rows: {}, ["__proto__"]: { look: "wall" } }, "apps", true)
  assert.deepEqual(c.choices, {})
  assert.equal(c.ignored.length, 6, c.ignored.join(" | "))
  assert.ok(c.ignored.some(x => /apps\.background/.test(x)), "a picture of your own waits for milestone 3")
  c = L.checkChoices({ background: { mode: "none", dim: "dark", extra: 1 } }, "apps", true)
  assert.deepEqual(c.choices, { background: { mode: "none" } })
  assert.equal(c.ignored.length, 2)
  assert.deepEqual(L.checkChoices([], "apps", true).choices, {})
  assert.equal(L.checkChoices("wall", "apps", true).ignored.length, 1)
  assert.ok(L.checkChoices({ ["k".repeat(5000)]: 1 }, "apps", true).ignored[0].length < 200, "a long key is cut in what's said")

  // ---- the identity strip and the floors
  assert.deepEqual(L.stripColors("#071447", "#f2f4ff"), { fill: "#071447", text: "#f2f4ff" }, "Retro's own: it follows the theme")
  assert.deepEqual(L.stripColors("#071447", "#0a1850"), { fill: "#101118", text: "#f2f2f2" }, "text like its fill: the guide's own")
  assert.deepEqual(L.stripColors("#071447", "#80f2f4ff"), { fill: "#101118", text: "#f2f2f2" }, "see-through text: the guide's own")
  assert.deepEqual(L.stripColors("#00000000", "#ffffff"), { fill: "#000000", text: "#ffffff" }, "a see-through fill is drawn opaque")
  assert.equal(L.floored({ text: { size: 0.2 } }, L.CARD_TEXT, 12, 1).text.size, 1, "12 px at a 12 px unit")
  assert.equal(L.floored({ text: { size: 0.2 } }, L.CARD_TEXT, 30, 1).text.size, 0.7, "0.7 units when that's more")
  assert.equal(L.floored({ text: { size: 0.2 } }, L.TOP_TITLE, 12, 1).text.size, 1.4)
  assert.equal(L.floored({ text: { size: 0.2 } }, L.TOP_TITLE, 12, 2).text.size, 0.7, "a drawing that doubles it needs half")
  const big = { text: { size: 3, color: "#fff" } }
  assert.equal(L.floored(big, L.CARD_TEXT, 12, 1), big, "over its floor: untouched")
  const small = { fill: "x", text: { size: 0.1, color: "#fff" } }
  const f = L.floored(small, L.CARD_TEXT, 16, 1)
  assert.deepEqual([small.text.size, f.text.size, f.text.color, f.fill], [0.1, 0.75, "#fff", "x"], "a copy: the theme's style isn't changed")
}

// a selected card grows at most 15%, whatever the style says
assert.equal(L.growOf({ grow: 0.05 }), 0.05)
assert.equal(L.growOf({ grow: 1 }), L.MAX_GROW, "a hostile grow is held to 15%")
assert.equal(L.growOf({ grow: -1 }), 0)
assert.equal(L.growOf({ grow: "big" }), 0)
assert.equal(L.growOf(null), 0)

// two shades as one, each at its own alpha; and the lift to a floor
assert.deepEqual(L.stackShades("#00000000", 0.5, "#000000", 0), { color: "#000000", alpha: 0 }, "a transparent shade darkens nothing")
const st = L.stackShades("#000000", 0.2, "#ffffff", 0.125)
assert.ok(Math.abs(st.alpha - 0.3) < 1e-9, "0.2 then 0.125: 0.3 in all")
assert.equal(L.stackShades("#80000000", 0.4, "#000000", 0).alpha, 0.4 * 128 / 255, "a half-alpha shade at 0.4 darkens by 0.2")
assert.equal(L.topUp(0.5, 0.3), 0, "already darker: nothing")
assert.ok(Math.abs(1 - (1 - 0.1) * (1 - L.topUp(0.1, 0.3)) - 0.3) < 1e-9)

// ---- saving a theme keeps the all-apps look (milestone 3, §10) ----------------------
{
  // what every app gets, from yours for all apps over a theme's
  const resolved = (all, theme) => {
    const c = { all: all, theme: L.checkChoices(theme, "apps", true, () => true).choices }
    const s = L.screenOf(c, L.lookOf(c, "").look)
    return JSON.stringify({ look: s.look, top: s.top, details: s.details, titles: s.titles, size: s.size, background: s.background })
  }
  // saved: the new theme's apps are the theme's with yours over them; once it's
  // on, yours that it now gives are dropped
  const saveAndApply = (all, theme, copied) => {
    let apps = L.appsForTheme(theme, all)
    if (copied && apps.background && apps.background.image) apps = Object.assign({}, apps, { background: Object.assign({}, apps.background, { image: copied }) })
    const checked = L.checkChoices(apps, "apps", true, () => true).choices
    const left = JSON.parse(JSON.stringify(all))
    L.allMatching(all, checked).forEach(k => delete left[k])
    return { theme: checked, all: left }
  }
  const oldPic = "/home/u/.config/om-pg/themes/aperture/pic-00000000000000aa.png"
  const copy = "/home/u/.config/om-pg/themes/mine/pic-0123456789abcdef.png"
  const yours = "/home/u/.config/om-pg/app-pictures/" + "a".repeat(32) + ".png"
  const cases = [
    ["no overrides", {}, { look: "cinematic" }, null],
    ["a size-only override over a theme's look", { size: "large" }, { look: "wall", top: "off" }, null],
    // the theme's own picture, inherited: the save copies it in under a new name (the same picture)
    ["an inherited background picture", {}, { look: "classic", background: { mode: "image", image: oldPic, dim: 0.5 } }, copy],
    ["your own background picture for all apps", { look: "posters", background: { mode: "image", image: yours, dim: 0.4 } }, { look: "classic" }, copy]
  ]
  for (const [name, all, theme, copied] of cases) {
    const before = resolved(all, theme)
    const after = saveAndApply(all, theme, copied)
    const same = resolved(after.all, after.theme).split(copied || "\u0000").join(theme.background && theme.background.image && !all.background ? theme.background.image : copied || "\u0000")
    assert.equal(same, before, name + ": the same look before and after")
  }
  // a key you set wins over the theme's, look and app included; unset keeps the theme's
  assert.deepEqual(L.appsForTheme({ look: "wall", top: "off" }, { look: "app" }), { look: "app", top: "off" })
  assert.deepEqual(L.appsForTheme({ look: "wall" }, { titles: "look" }), { look: "wall", titles: "look" })
  // only what the theme gives exactly is dropped from yours
  assert.deepEqual(L.allMatching({ look: "wall", size: "large", top: "off" }, { look: "wall", size: "small" }), ["look"])
  assert.deepEqual(L.allMatching({ background: { mode: "none", dim: 0.4 } }, { background: { mode: "none", dim: 0.4 } }), ["background"])
  assert.deepEqual(L.allMatching({}, { look: "wall" }), [])
  // each app's own choices never go into a theme (appsForTheme takes only the screen's keys)
  assert.deepEqual(L.appsForTheme({}, { look: "wall", rows: { "r:x": { show: false } }, order: ["x"] }), { look: "wall" })
}

console.log("applooks: milestone 2 passed")

// api 4: a table (its head, a line each item) and a ticker (one line); only
// the row itself makes either, and nothing (yours, a theme's) changes them
{
  const g = { width: 1280, u: 10, layout: { libraryPosterWidth: 8.6, libraryThumbWidth: 15.5 } }
  const tbl = { id: "st", title: "S", layout: "table", columns: [{ label: "#", align: "end" }], items: [{ id: "a", title: "A", kind: "info", cells: ["1"] }, { id: "b", title: "B", kind: "info", cells: ["2"] }] }
  const tick = { id: "news", title: "N", layout: "ticker", items: [{ id: "n", title: "N", kind: "open" }] }
  const mine = { mine: { rows: { "r:st": { layout: "grid" }, "r:news": { layout: "row" } } } }
  const tm = L.model({ kind: "screen", value: { rows: [tbl, tick] } }, Object.assign({}, g, { choices: mine }))
  const [t, k] = tm.lines
  assert.deepEqual([t.layout, t.layoutFrom, k.layout], ["table", "app", "ticker"], "yours doesn't change a table or a ticker")
  assert.deepEqual(t.columns, tbl.columns)
  assert.equal(t.height, 26 + 24 + 2 * 28 + 2 + 10, "its title, its head, two lines and a gap")
  assert.equal(k.height, 26 + 32 + 16)
  assert.deepEqual(L.cellRect(t, 1, tm.geometry), { x: 0, y: 26 + 24 + 30, w: 1280 - 40, h: 28 })
  assert.deepEqual(L.cellRect(k, 0, tm.geometry), { x: 0, y: 26, w: 1280 - 40, h: 32 })
  // a row that only app.json called a table isn't one (a table needs its columns)
  assert.equal(L.model({ kind: "screen", value: { rows: [{ id: "x", title: "X", items: tbl.items }] } }, Object.assign({}, g, { defaults: { "d:x": { layout: "table" } } })).lines[0].layout, "row")
}
// A details page's buttons in tablet mode (touch: the finger, in px): at
// least a finger tall, their line making room for them and for the selected
// one's growth (up to MAX_GROW, round its middle), so the rows after it
// never meet them; without tablet mode, as before (4.2 units)
{
  const detail = { kind: "detail", value: { title: "T", actions: [{ id: "p", label: "Play", kind: "play" }],
                                            rows: [{ id: "more", title: "More", layout: "row", items: [{ id: "m0", title: "t", kind: "open" }] }] } }
  for (const u of [10, 12, 13, 16, 18]) {
    const g0 = L.model(detail, { width: 1280, u: u, layout: {} }).geometry
    assert.equal(g0.actionsH, Math.round(u * 4.2), "no tablet mode: the line as before, u " + u)
    assert.equal(g0.actionH, Math.round(u * 3.2))
    for (const finger of [44, 53, 66, 72]) {
      const m = L.model(detail, { width: 1280, u: u, layout: {}, touch: finger })
      const g = m.geometry, line = m.lines[0]
      assert.equal(line.layout, "actions")
      assert.ok(g.actionH >= finger, "a finger tall: " + g.actionH + " ≥ " + finger)
      const grow = g.actionH * L.MAX_GROW / 2
      assert.ok(g.actionY - grow >= 0, "the selected one inside its line's top, u " + u + " finger " + finger)
      assert.ok(g.actionY + g.actionH + grow <= line.height, "and its bottom: " + (g.actionY + g.actionH + grow) + " ≤ " + line.height + ", u " + u + " finger " + finger)
      assert.equal(m.lines[1].y, line.height, "the next row from the line's own height")
    }
  }
}
console.log("applooks: api 4 all passed")
