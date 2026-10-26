// node tests/remotetemplates.test.mjs
// The phone remote's templates (Remote.js, remotes/*.json): the twelve built
// in pass the checker with nothing dropped; anything a template may not say
// is dropped with a reason (controls, rows, panels, items, elements, states,
// properties), each cap at its edge and one past it; a control at most once
// per layout (the pad-on and pad-off rows apart); expand and collapse only
// where they lead somewhere; names and descriptions plain text, cut to their
// length. Resolving: each color role from the TV's theme unless the template
// gives its own, #aarrggbb as CSS #rrggbbaa, every color a CSS hex or
// transparent and every font a shipped id, with any theme on. Sizes: where
// each control lands on a 360×640 and a 390×844 phone, no built-in key
// under 44 px there.
import { readFileSync, readdirSync } from "node:fs"
import assert from "node:assert/strict"

const root = new URL("../", import.meta.url)
const src = readFileSync(new URL("Remote.js", root), "utf8").replace(".pragma library", "")
const R = new Function(src + "; return { check, resolve, sizes, controls, css, ROLES, ROLE_NAMES, CONTROL_NAMES, ELEMENT_NAMES, FONTS, MAX_ROWS, MAX_ITEMS, MAX_CONTROLS, MAX_ELEMENTS, DEFAULTS, KEYS }")()

const BUILT_IN = ["classic", "minimal", "player", "surfer", "big-buttons", "premium", "techie", "pebble", "swipe", "dock", "glance", "tiles"]
const files = readdirSync(new URL("remotes/", root)).filter((f) => f.endsWith(".json"))
assert.deepEqual(files.map((f) => f.slice(0, -5)).sort(), [...BUILT_IN].sort(), "the twelve built-in templates, in their own folder")

const themes = { retro: {} }
for (const d of readdirSync(new URL("themes/", root))) {
  try { themes[d] = JSON.parse(readFileSync(new URL("themes/" + d + "/theme.json", root), "utf8")).colors } catch {}
}
assert.ok(Object.keys(themes).length >= 6, "the built-in themes")

const CSS = /^(#[0-9a-f]{6}([0-9a-f]{2})?|transparent)$/
function colorsIn(v, at, out) {
  if (v && typeof v === "object") for (const k of Object.keys(v)) colorsIn(v[k], at + "." + k, out)
  else if (typeof v === "string" && /(fill|color|track|knob|from|to)$/.test(at)) out.push([at, v])
  return out
}

// ---- every built-in passes, nothing dropped, and resolves with every theme ----
const built = {}
for (const id of BUILT_IN) {
  const given = JSON.parse(readFileSync(new URL("remotes/" + id + ".json", root), "utf8"))
  const res = R.check(given)
  assert.ok(!res.error, id + ": " + res.error)
  assert.deepEqual(res.dropped, [], id + " drops nothing")
  assert.equal(res.template.id, id, id + ": its id is its file's name")
  assert.ok(res.template.name && res.template.description, id + " has a name and a description")
  assert.ok(res.template.name.length <= 40 && res.template.description.length <= 120, id + ": name and description within their lengths")
  built[id] = res.template
  for (const [theme, slots] of Object.entries(themes)) {
    const r = R.resolve(res.template, slots)
    for (const [at, c] of colorsIn(r.styles, "styles", [])) assert.match(c, CSS, id + " with " + theme + ": " + at + " = " + c)
    for (const role of R.ROLE_NAMES) assert.match(r.colors[role], /^#[0-9a-f]{6}([0-9a-f]{2})?$/, id + " with " + theme + ": role " + role)
    for (const font of Object.values(r.fonts)) assert.ok(R.FONTS.includes(font), id + ": font " + font)
    for (const s of Object.values(r.styles)) if (s.text && s.text.font !== undefined) assert.ok(R.FONTS.includes(s.text.font), id + ": a style's font " + s.text.font)
  }
  // where its keys land: none under 44 px a side on a small or an ordinary phone
  for (const [w, h] of [[360, 640], [390, 844]]) {
    for (const which of ["portrait", "expanded"]) {
      if (which === "expanded" && !res.template.layout.expanded) continue
      const s = R.sizes(res.template, w, h, which)
      assert.deepEqual(s.under44, [], id + " " + which + " on " + w + "×" + h + ": keys under 44 px")
      assert.ok(s.controls.length > 0, id + ": sizes lists its controls")
    }
  }
}
// the minimalist ones expand and collapse
for (const id of ["pebble", "swipe", "dock", "glance", "tiles"]) assert.ok(built[id].layout.expanded, id + " has an expanded layout")

// ---- colors: the theme's unless the template's own; #aarrggbb as CSS ----
{
  assert.equal(R.css("#b8151828"), "#151828b8", "a theme's #aarrggbb is CSS #rrggbbaa")
  assert.equal(R.css("#82FB9C"), "#82fb9c")
  assert.equal(R.css("red"), "transparent")
  const t = R.check({ id: "x", name: "X", colors: { accent: "#ff0000" }, layout: { portrait: [{ row: ["power"], height: 10 }] } }).template
  const r = R.resolve(t, { accent: "#00ff00", text: "#123456", alert: "omarchy.red" })
  assert.equal(r.colors.accent, "#ff0000", "the template's own color wins")
  assert.equal(r.colors.text, "#123456", "else the theme's slot")
  assert.equal(r.colors.alert, "#ff4d4d", "a slot that isn't a hex (unresolved) falls back to Retro's")
  assert.equal(r.colors.bg, "#071447", "no theme: Retro's")
  assert.equal(r.styles.power.fill, r.colors.alert, "a role in a style resolves to its color")
}

// ---- what a template may not say is dropped, with a reason ----
const base = (extra) => Object.assign({ id: "t", name: "T", layout: { portrait: [{ row: ["power"], height: 10 }] } }, extra || {})
const dropped = (given) => { const r = R.check(given); assert.ok(!r.error, r.error); return r }
{
  assert.ok(R.check(null).error && R.check([]).error, "not an object")
  assert.ok(R.check(base({ id: "Bad Id" })).error, "a bad id")
  assert.ok(R.check(base({ id: "x".repeat(33) })).error, "an id too long")
  assert.ok(!R.check(base({ id: "x".repeat(32) })).error, "an id at its length")
  assert.ok(R.check(base({ name: "" })).error, "no name")
  assert.ok(R.check(base({ layout: { portrait: [] } })).error, "no rows")
  assert.ok(R.check(base({ layout: null })).error, "no layout")
  let r = dropped(base({ name: "N".repeat(45), description: "D".repeat(130) }))
  assert.equal(r.template.name.length, 40)
  assert.equal(r.template.description.length, 120)
  assert.ok(r.dropped.some((d) => d.startsWith("name")) && r.dropped.some((d) => d.startsWith("description")))
  r = dropped(base({ name: "A\u0000B\nC D <b>x</b>" }))
  assert.equal(r.template.name, "A B C D <b>x</b>", "plain text: control characters and line breaks go, the rest stays text")
  r = dropped(base({ colors: { accent: "red", nope: "#ffffff", text: "#FFFFFF" }, fonts: { body: "comic", mono: "dm-mono", x: "system" }, header: "big", face: "both", pad: "maybe", extra: 1 }))
  assert.deepEqual(r.template.colors, { text: "#ffffff" })
  assert.equal(r.template.fonts.body, "system")
  assert.equal(r.template.header, "title")
  assert.equal(r.template.face, "label")
  assert.equal(r.template.pad, "on")
  for (const why of ["colors.accent", "colors.nope", "fonts.body", "fonts.x", "header", "face", "pad", "extra"]) assert.ok(r.dropped.some((d) => d.startsWith(why)), why)

  r = dropped(base({ layout: { portrait: [
    { row: ["power", "nope", { control: "dpad", variant: "star" }, { control: "back", weight: 9, scale: 0.1, face: "both", alt: "yes" }], height: 10 },
    { row: [{ control: "now", show: ["title", "bogus", "title"], side: "left" }], height: 3 },
    "not a row",
    { row: [], height: 10 },
    { panel: "sheet", rows: [{ panel: "dock", rows: [{ row: ["home"], height: 10 }] }] },
    { panel: "bubble", rows: [{ row: ["home"], height: 10 }] },
    { row: ["power"], height: 10 },
    { row: ["mute"], height: 10, pad: "sometimes", grow: "yes", odd: 1 }
  ] } }))
  const p = r.template.layout.portrait
  assert.deepEqual(p[0].row.map((i) => i.control), ["power", "dpad", "back"], "unknown controls go; the rest stay")
  assert.equal(p[0].row[1].variant, undefined, "a variant that isn't one goes")
  assert.equal(p[0].row[2].weight, undefined, "a weight out of range goes")
  assert.equal(p[0].row[2].scale, undefined, "a scale out of range goes")
  assert.equal(p[0].row[2].face, "both")
  assert.equal(p[1].height, 10, "a height out of range takes the default")
  assert.deepEqual(p[1].row[0].show, ["title"], "a card's lines: known ones, each once")
  for (const why of ["layout.portrait[0].row[1] (no such control", "layout.portrait[0].row[2].variant", "layout.portrait[0].row[3].weight", "layout.portrait[0].row[3].scale",
                     "layout.portrait[0].row[3].alt", "layout.portrait[1].height", "layout.portrait[1].row[0].show[1]", "layout.portrait[1].row[0].show[2]",
                     "layout.portrait[1].row[0].side", "layout.portrait[2]", "layout.portrait[3] (a row with no controls)",
                     "layout.portrait[4].rows[0] (no panel inside a panel)", "layout.portrait[5].panel", "layout.portrait[6].row[0] (power is already in this layout)",
                     "layout.portrait[7].pad", "layout.portrait[7].odd"])
    assert.ok(r.dropped.some((d) => d.startsWith(why)), "dropped: " + why + "\n" + r.dropped.join("\n"))
  assert.equal(p.filter((e) => e.panel).length, 0, "a panel left empty goes")

  // the number pad's rows count apart: a control once with the pad shown, once with it hidden
  r = dropped(base({ layout: { portrait: [{ row: ["pad", "rocker"], height: 30, pad: "on" }, { row: ["rocker"], height: 8, pad: "off" }, { row: ["rocker"], height: 8 }] } }))
  assert.equal(r.template.layout.portrait.length, 2, "the pad-on and pad-off rows each have it once; a row for both doesn't")

  // expand and collapse only where they lead somewhere
  r = dropped(base({ layout: { portrait: [{ row: ["power", "expand", "collapse"], height: 10 }] } }))
  assert.deepEqual(r.template.layout.portrait[0].row.map((i) => i.control), ["power"], "no expanded layout: expand goes; collapse is only for the expanded one")
  r = dropped(base({ layout: { portrait: [{ row: ["power"], height: 10 }], expanded: [{ row: ["mute", "collapse"], height: 10 }] } }))
  assert.equal(r.template.layout.expanded, undefined, "an expanded layout nothing opens goes")
  r = dropped(base({ layout: { portrait: [{ row: ["power", "expand"], height: 10 }], expanded: [{ row: ["mute", "expand"], height: 10 }] } }))
  assert.deepEqual(r.template.layout.expanded[0].row.map((i) => i.control), ["mute"], "expand only in the minimized layout")
  assert.ok(r.dropped.some((d) => d.includes("no collapse control")), "an expanded layout without collapse is said")

  // landscape: control names, once each
  r = dropped(base({ layout: { portrait: [{ row: ["power"], height: 10 }], landscape: { left: ["dpad", "dpad", "nope", "gap", 5], right: "x" } } }))
  assert.deepEqual(r.template.layout.landscape.left, ["dpad"])
  assert.equal(r.dropped.filter((d) => d.startsWith("layout.landscape")).length, 5)
  r = dropped(base({ layout: { portrait: [{ row: ["power"], height: 10 }], landscape: { right: ["dpad"] } } }))
  assert.deepEqual(r.template.layout.landscape, { right: ["dpad"] }, "right alone is kept")
  r = dropped(base({ layout: { portrait: [{ row: ["power"], height: 10 }], landscape: { left: ["now"], right: ["dpad"] } } }))
  assert.deepEqual(r.template.layout.landscape, { left: ["now"] }, "both: left is used")
  assert.ok(r.dropped.some((d) => d.startsWith("layout.landscape.right (give left or right")))

  // the card and the list
  r = dropped(base({ now: { show: ["hero", "dvr"], side: "number", align: "middle", prefix: "yes", other: 1 }, guideList: { show: ["number", "rec", "rec", "x"] } }))
  assert.deepEqual(r.template.now.show, ["hero", "dvr"])
  assert.equal(r.template.now.side, "number")
  assert.equal(r.template.now.align, "left")
  assert.deepEqual(r.template.guideList.show, ["number", "rec"])
  for (const why of ["now.align", "now.prefix", "now.other", "guideList.show[2]", "guideList.show[3]"]) assert.ok(r.dropped.some((d) => d.startsWith(why)), why)
}

// ---- elements: names, states, properties, ranges ----
{
  const r = dropped(base({ elements: {
    key: { fill: "accent", radius: 51, shape: "star", border: { width: 4, color: "nope", style: "dashed" }, shadow: { blur: 30 }, opacity: 0, icon: 30, place: "left",
           text: { size: 41, weight: "heavy", case: "shout", letterSpacing: 2, font: "Comic Sans", italic: "yes", color: "#12345" } },
    "key:hover": {}, "nope": {}, "key:on:off": {}, card: "red", bar: { track: "textDim", knob: "#ffffff", height: 7 }, nowLogo: { size: 41 },
    page: { fill: { from: "bg", to: "nope" } }, tabs: { radius: [1, 2, 3] }
  } }))
  const k = r.template.elements.key
  assert.deepEqual(Object.keys(k).sort(), ["border", "fill", "shadow"], "only what checks out stays")
  assert.deepEqual(k.border, {}, "a border's bad parts go")
  assert.equal(k.shadow.blur, 2, "a shadow out of range takes its default parts")
  assert.equal(k.text, undefined)
  assert.deepEqual(r.template.elements.bar, { track: "textDim", knob: "#ffffff" })
  assert.ok(r.dropped.some((d) => d.startsWith("elements.key.border (") && ["border.width", "border.color", "border.style"].every((x) => d.includes(x))), "a border's bad parts, each named")
  for (const why of ["elements.key.radius", "elements.key.shape",
                     "elements.key.opacity", "elements.key.icon", "elements.key.place", "elements.key.text.size", "elements.key.text.weight", "elements.key.text.case",
                     "elements.key.text.letterSpacing", "elements.key.text.font", "elements.key.text.italic", "elements.key.text.color",
                     "elements.key:hover", "elements.nope", "elements.key:on:off", "elements.card", "elements.bar.height", "elements.nowLogo.size",
                     "elements.page.fill", "elements.tabs.radius"])
    assert.ok(r.dropped.some((d) => d.startsWith(why)), "dropped: " + why + "\n" + r.dropped.join("\n"))
}

// ---- the caps, at the edge and one past ----
{
  const rowsOf = (n) => Array.from({ length: n }, () => ({ row: ["gap"], height: 4 })).concat([{ row: ["power"], height: 4 }])
  let r = dropped(base({ layout: { portrait: rowsOf(R.MAX_ROWS - 1) } }))
  assert.equal(r.template.layout.portrait.length, R.MAX_ROWS, "16 rows")
  r = dropped(base({ layout: { portrait: rowsOf(R.MAX_ROWS) } }))
  assert.equal(r.template.layout.portrait.length, R.MAX_ROWS, "the 17th row goes")
  assert.ok(r.dropped.some((d) => d.includes("at most 16 rows")))

  r = dropped(base({ layout: { portrait: [{ row: ["power", "mute", "back", "guide", "home", "live"], height: 10 }] } }))
  assert.equal(r.template.layout.portrait[0].row.length, R.MAX_ITEMS, "6 in a row")
  r = dropped(base({ layout: { portrait: [{ row: ["power", "mute", "back", "guide", "home", "live", "window"], height: 10 }] } }))
  assert.equal(r.template.layout.portrait[0].row.length, R.MAX_ITEMS, "the 7th goes")
  assert.ok(r.dropped.some((d) => d.includes("at most 6 in a row")))

  // 40 controls: the pad-on and pad-off rows can hold each once, so 41 is reachable
  const all = R.CONTROL_NAMES.filter((c) => !["gap", "expand", "collapse"].includes(c))
  const rowsFor = (names, pad) => { const out = []; for (let i = 0; i < names.length; i += 6) out.push({ row: names.slice(i, i + 6), height: 4, pad }); return out }
  const on = all.slice(0, 20), off = all.slice(0, 21)
  r = dropped(base({ layout: { portrait: rowsFor(on, "on").concat(rowsFor(off.slice(0, 20), "off")) } }))
  const count = (rows) => rows.reduce((n, e) => n + e.row.filter((i) => i.control !== "gap").length, 0)
  assert.equal(count(r.template.layout.portrait), R.MAX_CONTROLS, "40 controls")
  r = dropped(base({ layout: { portrait: rowsFor(on, "on").concat(rowsFor(off, "off")) } }))
  assert.equal(count(r.template.layout.portrait), R.MAX_CONTROLS, "the 41st goes")
  assert.ok(r.dropped.some((d) => d.includes("at most 40 controls")))

  const els = {}
  const names = R.ELEMENT_NAMES.slice(0, R.MAX_ELEMENTS)
  for (const n of names) els[n] = { opacity: 0.9 }
  r = dropped(base({ elements: els }))
  assert.equal(Object.keys(r.template.elements).length, R.MAX_ELEMENTS, "40 element entries")
  els[R.ELEMENT_NAMES[R.MAX_ELEMENTS]] = { opacity: 0.9 }
  r = dropped(base({ elements: els }))
  assert.equal(Object.keys(r.template.elements).length, R.MAX_ELEMENTS, "the 41st goes")
  assert.ok(r.dropped.some((d) => d.includes("at most 40 entries")))

  for (const [h, ok] of [[4, true], [60, true], [3.9, false], [60.1, false]]) {
    r = dropped(base({ layout: { portrait: [{ row: ["power"], height: h }] } }))
    assert.equal(r.template.layout.portrait[0].height, ok ? h : 10, "height " + h)
  }
  for (const [w, ok] of [[0.2, true], [6, true], [0.19, false], [6.1, false]]) {
    r = dropped(base({ layout: { portrait: [{ row: [{ control: "power", weight: w }], height: 10 }] } }))
    assert.equal(r.template.layout.portrait[0].row[0].weight, ok ? w : undefined, "weight " + w)
  }
  for (const [s, ok] of [[0.3, true], [1, true], [0.29, false], [1.01, false]]) {
    r = dropped(base({ layout: { portrait: [{ row: [{ control: "power", scale: s }], height: 10 }] } }))
    assert.equal(r.template.layout.portrait[0].row[0].scale, ok ? s : undefined, "scale " + s)
  }
  for (const [g, ok] of [[0, true], [6, true], [-0.1, false], [6.1, false]]) {
    r = dropped(base({ layout: { portrait: [{ row: ["power"], height: 10, gap: g }] } }))
    assert.equal(r.template.layout.portrait[0].gap, ok ? g : undefined, "gap " + g)
  }
}

// ---- for agents ----
{
  const c = R.controls()
  assert.ok(c.controls.find((x) => x.control === "window").faces.includes("icon"))
  assert.equal(c.caps.rows, 16)
  assert.ok(c.elements.some((e) => e.element === "bar" && e.own.includes("knob")))
}

console.log("remote templates: all good")
