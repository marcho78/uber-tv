.pragma library

// The phone remote's templates: the whole phone page (which controls, where,
// how big, how they look, what the now-playing card and the guide list
// show) as data, like a theme. Twelve are built in (remotes/ in the plugin);
// yours and agents' are in ~/.config/om-pg/remotes/, apart from the TV's
// themes. Here: what a template may say, the checker (anything else is
// dropped with a reason), the caps, and the resolver (each color role from
// the TV's theme unless the template gives its own), which is what the
// guide sends the phones. The page (remote/index.html) draws only resolved
// templates, and sets styles only from the checked values below.
//
// Units are 1% of the phone's width. Colors in a template are #rrggbb or
// #aarrggbb (as in themes), a role's name, or none; a resolved template has
// them as CSS colors (#rrggbb or #rrggbbaa) or transparent.

var ID = /^[a-z0-9][a-z0-9-]{0,31}$/

// Each color role and the theme slot it follows
var ROLES = { bg: "bgTop", bgTo: "bgBottom", card: "cell", cardEdge: "cellBorder", key: "keyFace", keyText: "keyText",
              keyEdge: "keyEdge", accent: "accent", accentText: "selectedText", text: "text", textDim: "textDim", alert: "alert" }
var ROLE_NAMES = Object.keys(ROLES)
// Retro's slots: what a role is when the theme gives nothing
var RETRO = { bgTop: "#071447", bgBottom: "#030a2b", cell: "#1b3591", cellBorder: "#3b5bd1", keyFace: "#e4e9ff", keyText: "#0b1550",
              keyEdge: "#46559a", accent: "#ffd23f", selectedText: "#141414", text: "#f2f4ff", textDim: "#9fb0f0", alert: "#ff4d4d" }

// The fonts Uber TV ships (served to the phone at /api/font/<id>), or the phone's own
var FONTS = ["system", "dm-mono", "dm-mono-medium", "orbitron"]
var FONT_ROLES = ["body", "display", "mono"]
var WEIGHTS = { thin: 100, light: 300, normal: 400, medium: 500, semibold: 600, bold: 700, black: 900 }
var CASES = ["upper", "lower", "title", "none"]
var SHAPES = ["rect", "pill", "circle", "chamfer"]   // chamfer: the top left and bottom right corners cut (by radius)
var STATES = ["pressed", "on", "unavailable", "alert", "alt"]

// The controls a template can place. label: the word it shows; icon: the
// one it draws; faces: what it can show; variants: other ways to draw it
var CONTROLS = {
  now:       { about: "the now-playing card: what's on (its lines are in now)" },
  tabs:      { about: "REMOTE and GUIDE: the guide tab shows the channel list in place of what's below the tabs" },
  power:     { label: "POWER", icon: "power", faces: ["label", "icon", "both"], cmd: "power" },
  mute:      { label: "MUTE", icon: "mute", faces: ["label", "icon", "both"], cmd: "mute" },
  options:   { label: "⋯", icon: "dots", faces: ["label", "icon"], cmd: "options" },
  dpad:      { about: "the arrows with OK in the middle", variants: ["cross", "plus", "ring"] },
  back:      { label: "BACK", icon: "back", faces: ["label", "icon", "both"], cmd: "back" },
  guide:     { label: "GUIDE", icon: "guide", faces: ["label", "icon", "both"], cmd: "guide" },
  window:    { icon: "window", faces: ["icon"], cmd: "window", about: "full screen or the mini player, one button" },
  home:      { label: "HOME", icon: "home", faces: ["label", "icon", "both"], cmd: "home" },
  chup:      { label: "CH ▲", icon: "up", faces: ["label", "icon", "both"], cmd: "chup", short: "CH" },
  chdown:    { label: "CH ▼", icon: "down", faces: ["label", "icon", "both"], cmd: "chdown", short: "CH" },
  rocker:    { about: "channel up and down together", variants: ["vertical", "row", "tall", "split"] },
  pad:       { about: "the number pad: 1 to 9, 0, ⌫ and GO (hidden while the number pad is off)" },
  padToggle: { label: "123", faces: ["label"], about: "shows or hides the number pad" },
  rewind:    { icon: "rewind", faces: ["icon"], cmd: "rewind", about: "back 30 s (a movie: 10 s)" },
  playpause: { icon: "pause", faces: ["icon"], cmd: "playpause", about: "pause or play" },
  forward:   { icon: "forward", faces: ["icon"], cmd: "forward", about: "forward 30 s (a movie: 10 s)" },
  live:      { label: "LIVE", faces: ["label"], cmd: "live", about: "back to Live" },
  status:    { about: "a strip of readouts: signal, REC, behind live, sound" },
  gap:       { about: "empty space" },
  expand:    { icon: "more", faces: ["icon"], about: "shows the expanded layout (layout.expanded)" },
  collapse:  { icon: "collapse", faces: ["icon"], about: "back from the expanded layout" },
  swipe:     { about: "a touch pad: a swipe moves, a tap is OK" },
  list:      { about: "the channel list, as the guide tab shows it: a tap watches" }
}
var CONTROL_NAMES = Object.keys(CONTROLS)
var NOW_LINES = ["channel", "name", "number", "hero", "title", "times", "progress", "dvr", "mode"]
var NOW_SIDES = ["logo", "number", "none"]
var LIST_COLUMNS = ["number", "logo", "name", "title", "live", "rec"]
var PANELS = ["sheet", "dock", "group"]

// Keys: these start from the key element's style, then their own
var KEYS = ["power", "mute", "options", "back", "guide", "window", "home", "live", "rewind", "playpause", "forward", "padToggle",
            "expand", "collapse", "chup", "chdown", "arrow", "ok", "digit", "erase", "go", "rocker"]

// Every element and its own properties (beyond the box's and the text's)
var ELEMENTS = {
  page: "the page behind everything (fill: a color or a gradient)",
  header: "the line across the top: UBER TV · REMOTE (or nothing) and ⚙",
  settingsButton: "⚙, top right",
  card: "the now-playing card",
  nowLogo: "the channel's logo (or its initials) in the card; size: its side",
  nowChannel: "number and channel name: 132 · Sky News",
  nowName: "the channel's name alone",
  nowNumber: "the channel's number (also when it sits beside the lines)",
  nowHero: "the number, very large",
  nowTitle: "what's on",
  nowTimes: "when it's on and the time left",
  nowDvr: "REC until… and pause and rewind",
  nowMode: "FULL SCREEN, MINI…",
  bar: "the bar of how far in (or what's kept): fill, track, knob, height",
  barLabel: "the words under the bar",
  typed: "the number being typed (or the passcode's dots)",
  ask: "the TV's question, with its two answers",
  tabs: "REMOTE and GUIDE, around both",
  tab: "each of them (on: the one open)",
  key: "every key, before its own style",
  power: "POWER", mute: "MUTE (on: muted)", options: "⋯", back: "BACK", guide: "GUIDE", window: "full screen or mini player",
  home: "HOME", live: "LIVE", rewind: "back 30 s", playpause: "pause or play", forward: "forward 30 s",
  padToggle: "123 (on: the number pad shown)", expand: "the expand key (four squares)", collapse: "the collapse key",
  chup: "CH ▲", chdown: "CH ▼",
  dpad: "the d-pad's own shape (plus and ring); a cross has none",
  arrow: "each arrow", ok: "OK",
  rocker: "channel up and down as one shape (tall and split): its text and icon draw both halves", rockerLabel: "CHANNEL or CH by the rocker",
  digit: "each number key", erase: "⌫", go: "GO",
  status: "the readout strip", statusItem: "each readout (alert: REC)",
  swipe: "the touch pad (its text color draws the marks)",
  list: "the channel list's box", listRow: "each channel (on: the one on)", listNumber: "its number",
  listName: "its name", listTitle: "what it's showing", listTag: "● LIVE (alert: ● REC)", band: "a category's band",
  sheet: "a sheet from the bottom", dock: "a floating dock", group: "a plain group of rows", handle: "the sheet's grab handle"
}
var ELEMENT_NAMES = Object.keys(ELEMENTS)
var OWN = { bar: { track: "color", knob: "color", height: [0.2, 6] }, nowLogo: { size: [6, 40] } }

// Caps
var MAX_ROWS = 16, MAX_ITEMS = 6, MAX_CONTROLS = 40, MAX_ELEMENTS = 40, MAX_NAME = 40, MAX_DESCRIPTION = 120

// What every element is before a template's style: plain and readable on
// any theme. Templates mostly say more.
var DEFAULTS = {
  page: { fill: { from: "bg", to: "bgTo", direction: "down" } },
  header: { text: { color: "accent", font: "display", size: 3.4, weight: "bold", case: "upper", letterSpacing: 0.12 } },
  settingsButton: { text: { color: "textDim", size: 4.6 } },
  card: { fill: "card", border: { width: 0.25, color: "cardEdge" }, radius: 1.6, padding: 2.6 },
  nowLogo: { fill: "bgTo", border: { width: 0.25, color: "cardEdge" }, radius: 1, text: { color: "text", size: 3.4, weight: "bold" } },
  nowChannel: { text: { color: "accent", size: 3.3, weight: "bold" } },
  nowName: { text: { color: "textDim", size: 2.8, weight: "bold", case: "upper", letterSpacing: 0.12 } },
  nowNumber: { text: { color: "accent", size: 9, weight: "bold" } },
  nowHero: { text: { color: "text", size: 30, weight: "thin" } },
  nowTitle: { text: { color: "text", size: 4.6, weight: "bold" } },
  nowTimes: { text: { color: "textDim", size: 2.9 } },
  nowDvr: { text: { color: "alert", size: 2.9, weight: "bold" } },
  nowMode: { text: { color: "accent", size: 2.7, weight: "bold", case: "upper" } },
  bar: { fill: "accent", track: "cardEdge", knob: "text", height: 0.9, radius: 1 },
  barLabel: { text: { color: "textDim", size: 2.7 } },
  typed: { fill: "bgTo", border: { width: 0.3, color: "accent" }, radius: 1.6, text: { color: "accent", size: 7, weight: "bold", letterSpacing: 0.3 } },
  ask: { fill: "card", border: { width: 0.3, color: "accent" }, radius: 1.6, padding: 2.4, text: { color: "text", size: 3.1 } },
  tabs: { border: { width: 0.25, color: "cardEdge" }, radius: 1.6 },
  tab: { text: { color: "textDim", size: 3, weight: "bold", case: "upper", letterSpacing: 0.1 } },
  "tab:on": { fill: "accent", text: { color: "accentText" } },
  key: { fill: "key", border: { width: 0.25, color: "keyEdge" }, radius: 2, text: { color: "keyText", size: 4, weight: "bold" }, icon: 6 },
  "key:pressed": { opacity: 0.7 },
  "key:on": { fill: "accent", text: { color: "accentText" } },
  "key:unavailable": { opacity: 0.4 },
  power: { fill: "alert", text: { color: "#ffffff" } },
  ok: { fill: "accent", shape: "circle", text: { color: "accentText" } },
  go: { fill: "accent", text: { color: "accentText" } },
  dpad: { fill: "key", border: { width: 0.25, color: "keyEdge" } },
  arrow: {},
  rocker: { fill: "key", border: { width: 0.25, color: "keyEdge" }, radius: 3 },
  rockerLabel: { text: { color: "textDim", size: 2.5, weight: "bold", case: "upper" } },
  status: {},
  statusItem: { border: { width: 0.25, color: "cardEdge" }, radius: 0.8, padding: 1, text: { color: "text", font: "mono", size: 2.6, case: "upper" } },
  "statusItem:alert": { border: { color: "alert" }, text: { color: "alert" } },
  "statusItem:unavailable": { opacity: 0.4 },
  swipe: { fill: "card", border: { width: 0.25, color: "cardEdge" }, radius: 4, text: { color: "textDim" } },
  list: {},
  listRow: { border: { width: 0.25, color: "cardEdge", sides: ["bottom"] }, padding: 2 },
  "listRow:on": { fill: "card" },
  listNumber: { text: { color: "accent", size: 3.6, weight: "bold" } },
  listName: { text: { color: "text", size: 3.4, weight: "bold" } },
  listTitle: { text: { color: "textDim", size: 3 } },
  listTag: { text: { color: "textDim", size: 2.6, weight: "bold", case: "upper" } },
  "listTag:alert": { text: { color: "alert" } },
  band: { border: { width: 0.25, color: "accent", sides: ["bottom"] }, padding: 1.6, text: { color: "accent", size: 2.9, weight: "bold", case: "upper", letterSpacing: 0.1 } },
  sheet: { fill: "card", radius: [5, 5, 0, 0], padding: 3 },
  dock: { fill: "card", radius: 6, padding: 2 },
  group: { padding: 0 },
  handle: { fill: "textDim", radius: 1 }
}

// ---- small helpers ---------------------------------------------------------

function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }
function copy(v) { return v === undefined ? undefined : JSON.parse(JSON.stringify(v)) }
function merge(a, b) {
  if (b === undefined) return copy(a)
  if (!isObject(a) || !isObject(b)) return copy(b)
  var out = copy(a)
  for (var k in b) out[k] = isObject(out[k]) && isObject(b[k]) ? merge(out[k], b[k]) : copy(b[k])
  return out
}
function isHex(v) { return typeof v === "string" && /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v) }
function num(v, lo, hi) { return typeof v === "number" && isFinite(v) && v >= lo && v <= hi }
function round(v) { return Math.round(v * 1000) / 1000 }
// plain words: no control characters, one line, at most n characters
function plain(v, n) {
  if (typeof v !== "string") return ""
  return v.replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]+/g, " ").replace(/\s+/g, " ").trim().slice(0, n)
}

// #aarrggbb (a theme's) as CSS #rrggbbaa; #rrggbb as it is
function css(hex) {
  if (!isHex(hex)) return "transparent"
  var h = hex.toLowerCase()
  return h.length === 9 ? "#" + h.slice(3) + h.slice(1, 3) : h
}

// ---- checking ---------------------------------------------------------------

function checkColor(v) {
  if (typeof v !== "string") return undefined
  var t = v.trim()
  if (isHex(t)) return t.toLowerCase()
  if (t === "none" || t === "transparent") return "none"
  return ROLE_NAMES.indexOf(t) >= 0 ? t : undefined
}

function checkLength(v, lo, hi) { return num(v, lo, hi) ? round(v) : undefined }

function checkProp(name, v, element) {
  var own = (OWN[element] || {})[name]
  if (own === "color") { var oc = checkColor(v); return oc === undefined ? { error: "a color" } : { value: oc } }
  if (Array.isArray(own)) { var ol = checkLength(v, own[0], own[1]); return ol === undefined ? { error: own[0] + " to " + own[1] } : { value: ol } }
  switch (name) {
  case "fill":
    if (isObject(v)) {
      var from = checkColor(v.from), to = checkColor(v.to)
      if (from === undefined || to === undefined) return { error: "a color, or {from, to, direction}" }
      return { value: { from: from, to: to, direction: ["down", "up", "right", "left"].indexOf(v.direction) >= 0 ? v.direction : "down" } }
    }
    var f = checkColor(v)
    return f === undefined ? { error: "a color (#rrggbb, #aarrggbb, a role or none), or {from, to, direction}" } : { value: f }
  case "border":
    if (v === "none") return { value: { width: 0 } }
    if (!isObject(v)) return { error: "{width, color, sides} or none" }
    var b = {}, bad = []
    for (var k in v) {
      if (k === "width") { var w = checkLength(v.width, 0, 3); if (w === undefined) bad.push("width (0 to 3)"); else b.width = w }
      else if (k === "color") { var c = checkColor(v.color); if (c === undefined) bad.push("color"); else b.color = c }
      else if (k === "sides") {
        var sides = typeof v.sides === "string" ? [v.sides] : v.sides
        if (Array.isArray(sides) && sides.length && sides.length <= 4 && sides.every(function(s) { return ["all", "top", "bottom", "left", "right"].indexOf(s) >= 0 }))
          b.sides = sides.indexOf("all") >= 0 ? "all" : sides.slice()
        else bad.push("sides (all, or some of top, bottom, left, right)")
      } else bad.push(k)
    }
    return bad.length ? { value: b, error: "border." + bad.join(", border.") } : { value: b }
  case "radius":
    if (Array.isArray(v) && v.length === 4) {
      var corners = v.map(function(x) { return checkLength(x, 0, 50) })
      return corners.some(function(x) { return x === undefined }) ? { error: "0 to 50, or four: [top left, top right, bottom right, bottom left]" } : { value: corners }
    }
    var r = checkLength(v, 0, 50)
    return r === undefined ? { error: "0 to 50, or four: [top left, top right, bottom right, bottom left]" } : { value: r }
  case "shape":
    return SHAPES.indexOf(v) >= 0 ? { value: v } : { error: SHAPES.join(", ") }
  case "shadow":
    if (v === "none") return { value: "none" }
    if (!isObject(v)) return { error: "{color, blur, x, y} or none" }
    var sh = { color: checkColor(v.color), blur: checkLength(v.blur, 0, 20), x: checkLength(v.x, -10, 10), y: checkLength(v.y, -10, 10) }
    if (sh.color === undefined) sh.color = "#99000000"
    if (sh.blur === undefined) sh.blur = 2
    if (sh.x === undefined) sh.x = 0
    if (sh.y === undefined) sh.y = 0.6
    return { value: sh }
  case "padding":
    var p = checkLength(v, 0, 10)
    return p === undefined ? { error: "0 to 10" } : { value: p }
  case "opacity":
    var o = checkLength(v, 0.1, 1)
    return o === undefined ? { error: "0.1 to 1" } : { value: o }
  case "place":
    return v === "center" || v === "corner" ? { value: v } : { error: "center, or corner: the icon top left and the label bottom left (a tile)" }
  case "icon":
    var ic = checkLength(v, 2, 24)
    return ic === undefined ? { error: "an icon's size, 2 to 24" } : { value: ic }
  }
  return { error: "not a property" }
}

function checkText(name, v) {
  switch (name) {
  case "color": var c = checkColor(v); return c === undefined ? { error: "a color" } : { value: c }
  case "font": return FONT_ROLES.indexOf(v) >= 0 ? { value: v } : { error: "body, display or mono (fonts says which font each is)" }
  case "size": var s = checkLength(v, 1.5, 40); return s === undefined ? { error: "1.5 to 40" } : { value: s }
  case "weight":
    if (num(v, 100, 900)) return { value: Math.round(v / 100) * 100 }
    return WEIGHTS[v] ? { value: v } : { error: Object.keys(WEIGHTS).join(", ") + ", or 100 to 900" }
  case "case": return CASES.indexOf(v) >= 0 ? { value: v } : { error: CASES.join(", ") }
  case "letterSpacing": var l = checkLength(v, -0.2, 1); return l === undefined ? { error: "-0.2 to 1 (of the letters' size)" } : { value: l }
  case "italic": return typeof v === "boolean" ? { value: v } : { error: "true or false" }
  }
  return { error: "not a text property" }
}

// One element's style: { style, dropped }
function checkStyle(name, given) {
  var style = {}, dropped = []
  for (var k in given) {
    if (k === "text") {
      if (!isObject(given.text)) { dropped.push(name + ".text (an object)"); continue }
      var t = {}
      for (var tk in given.text) {
        var tr = checkText(tk, given.text[tk])
        if (tr.value !== undefined) t[tk] = tr.value
        if (tr.error) dropped.push(name + ".text." + tk + " (" + tr.error + ")")
      }
      if (Object.keys(t).length) style.text = t
      continue
    }
    var r = checkProp(k, given[k], name.split(":")[0])
    if (r.value !== undefined) style[k] = r.value
    if (r.error) dropped.push(name + "." + k + " (" + r.error + ")")
  }
  return { style: style, dropped: dropped }
}

function checkElements(given, dropped) {
  var out = {}
  if (given === undefined) return out
  if (!isObject(given)) { dropped.push("elements (an object: element to its style)"); return out }
  var n = 0
  for (var name in given) {
    var parts = name.split(":")
    if (ELEMENT_NAMES.indexOf(parts[0]) < 0) { dropped.push("elements." + name + " (no such element; remoteControls lists them)"); continue }
    if (parts.length > 2 || (parts.length === 2 && STATES.indexOf(parts[1]) < 0)) { dropped.push("elements." + name + " (states: " + STATES.join(", ") + ")"); continue }
    if (!isObject(given[name])) { dropped.push("elements." + name + " (an object of properties)"); continue }
    if (n >= MAX_ELEMENTS) { dropped.push("elements." + name + " (at most " + MAX_ELEMENTS + " entries)"); continue }
    var res = checkStyle(name, given[name])
    for (var i = 0; i < res.dropped.length; i++) dropped.push("elements." + res.dropped[i])
    out[name] = res.style
    n += 1
  }
  return out
}

// One item of a row: a control's name or { control, weight, scale, face, variant, arrows, alt, show, side, align }.
// alt draws a key with its element's alt state on top (a key that looks
// different in one place: round when minimized, a pill in the sheet)
function checkItem(v, at, dropped) {
  var it = typeof v === "string" ? { control: v } : isObject(v) ? v : null
  if (!it || typeof it.control !== "string") { dropped.push(at + " (a control's name, or {control, …})"); return null }
  var c = CONTROLS[it.control]
  if (!c) { dropped.push(at + " (no such control: " + plain(it.control, 40) + ")"); return null }
  var out = { control: it.control }
  for (var k in it) {
    var x = it[k]
    if (k === "control") continue
    if (k === "weight" && num(x, 0.2, 6)) out.weight = round(x)
    else if (k === "scale" && num(x, 0.3, 1)) out.scale = round(x)
    else if (k === "face" && (c.faces || []).indexOf(x) >= 0) out.face = x
    else if (k === "variant" && (c.variants || []).indexOf(x) >= 0) out.variant = x
    else if (k === "arrows" && it.control === "dpad" && (x === "triangle" || x === "chevron")) out.arrows = x
    else if (k === "alt" && KEYS.indexOf(it.control) >= 0 && typeof x === "boolean") { if (x) out.alt = true }
    else if (it.control === "now" && (k === "show" || k === "side" || k === "align" || k === "prefix")) {
      var nw = checkNow({ show: k === "show" ? x : undefined, side: k === "side" ? x : undefined, align: k === "align" ? x : undefined,
                          prefix: k === "prefix" ? x : undefined }, at, dropped)
      if (nw[k] !== undefined) out[k] = nw[k]
    } else dropped.push(at + "." + k + " (" + itemHelp(it.control, k) + ")")
  }
  return out
}

function itemHelp(control, k) {
  var c = CONTROLS[control]
  if (k === "weight") return "0.2 to 6"
  if (k === "scale") return "0.3 to 1"
  if (k === "face") return c.faces ? c.faces.join(", ") : control + " has no face"
  if (k === "variant") return c.variants ? c.variants.join(", ") : control + " has no variants"
  if (k === "arrows") return "triangle or chevron, on dpad"
  if (k === "alt") return KEYS.indexOf(control) >= 0 ? "true or false" : "only on keys"
  return "not a setting of " + control
}

function checkNow(v, at, dropped) {
  var out = {}
  if (v === undefined) return out
  if (!isObject(v)) { dropped.push(at + " (an object)"); return out }
  if (v.show !== undefined) {
    if (Array.isArray(v.show)) {
      out.show = []
      for (var i = 0; i < v.show.length && i < 12; i++) {
        if (NOW_LINES.indexOf(v.show[i]) >= 0 && out.show.indexOf(v.show[i]) < 0) out.show.push(v.show[i])
        else dropped.push(at + ".show[" + i + "] (" + NOW_LINES.join(", ") + ", each once)")
      }
    } else dropped.push(at + ".show (a list of: " + NOW_LINES.join(", ") + ")")
  }
  if (v.side !== undefined) { if (NOW_SIDES.indexOf(v.side) >= 0) out.side = v.side; else dropped.push(at + ".side (" + NOW_SIDES.join(", ") + ")") }
  if (v.align !== undefined) { if (v.align === "left" || v.align === "center") out.align = v.align; else dropped.push(at + ".align (left or center)") }
  if (v.prefix !== undefined) { if (typeof v.prefix === "boolean") out.prefix = v.prefix; else dropped.push(at + ".prefix (true or false: CH before the number)") }
  return out
}

// A list of rows (and panels of rows): { rows, count } with each control at
// most once (the pad-on and pad-off rows counted apart)
function checkRows(given, at, dropped, inPanel, seen) {
  var rows = []
  if (!Array.isArray(given)) { dropped.push(at + " (a list of rows)"); return rows }
  for (var i = 0; i < given.length; i++) {
    var e = given[i], where = at + "[" + i + "]"
    if (!isObject(e)) { dropped.push(where + " (a row: {row: [...], height})"); continue }
    if (e.panel !== undefined) {
      if (inPanel) { dropped.push(where + " (no panel inside a panel)"); continue }
      if (PANELS.indexOf(e.panel) < 0) { dropped.push(where + ".panel (" + PANELS.join(", ") + ")"); continue }
      var inner = checkRows(e.rows, where + ".rows", dropped, true, seen)
      if (!inner.length) { dropped.push(where + " (a panel with no rows)"); continue }
      var panel = { panel: e.panel, rows: inner }
      if (e.handle === true) panel.handle = true
      for (var pk in e) if (["panel", "rows", "handle"].indexOf(pk) < 0) dropped.push(where + "." + pk + " (not a setting of a panel)")
      rows.push(panel)
      continue
    }
    if (seen.rows >= MAX_ROWS) { dropped.push(where + " (at most " + MAX_ROWS + " rows)"); continue }
    if (!Array.isArray(e.row)) { dropped.push(where + ".row (a list of controls)"); continue }
    var row = { row: [], height: checkLength(e.height, 4, 60) }
    if (row.height === undefined) { if (e.height !== undefined) dropped.push(where + ".height (4 to 60)"); row.height = 10 }
    if (e.grow === true) row.grow = true
    if (e.dim === true) row.dim = true
    if (e.pad === "on" || e.pad === "off") row.pad = e.pad
    else if (e.pad !== undefined) dropped.push(where + ".pad (on or off: the row shows only with the number pad shown, or hidden)")
    if (e.gap !== undefined) { var g = checkLength(e.gap, 0, 6); if (g === undefined) dropped.push(where + ".gap (0 to 6)"); else row.gap = g }
    for (var rk in e) if (["row", "height", "grow", "dim", "pad", "gap"].indexOf(rk) < 0) dropped.push(where + "." + rk + " (not a setting of a row)")
    for (var j = 0; j < e.row.length; j++) {
      var iw = where + ".row[" + j + "]"
      if (row.row.length >= MAX_ITEMS) { dropped.push(iw + " (at most " + MAX_ITEMS + " in a row)"); continue }
      var item = checkItem(e.row[j], iw, dropped)
      if (!item) continue
      if (item.control !== "gap") {
        var conds = row.pad ? [row.pad] : ["on", "off"]
        if (conds.some(function(c) { return seen[c].indexOf(item.control) >= 0 })) { dropped.push(iw + " (" + item.control + " is already in this layout)"); continue }
        if (seen.controls >= MAX_CONTROLS) { dropped.push(iw + " (at most " + MAX_CONTROLS + " controls)"); continue }
        conds.forEach(function(c) { seen[c].push(item.control) })
        seen.controls += 1
      }
      row.row.push(item)
    }
    if (!row.row.length) { dropped.push(where + " (a row with no controls)"); continue }
    seen.rows += 1
    rows.push(row)
  }
  return rows
}

function controlsIn(rows) {
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var inner = rows[i].panel ? rows[i].rows : [rows[i]]
    for (var j = 0; j < inner.length; j++) for (var k = 0; k < inner[j].row.length; k++) out.push(inner[j].row[k].control)
  }
  return out
}

// Takes a control out of a list of rows (rows left empty go too)
function without(rows, control) {
  var out = []
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].panel) {
      var inner = without(rows[i].rows, control)
      if (inner.length) out.push(merge(rows[i], { rows: inner }))
      continue
    }
    var r = copy(rows[i])
    r.row = r.row.filter(function(it) { return it.control !== control })
    if (r.row.length) out.push(r)
  }
  return out
}

function newSeen() { return { rows: 0, controls: 0, on: [], off: [] } }

// A template as given (from a file, an agent, an edit): { template, dropped }
// or { error } when it can't be a template at all
function check(given) {
  if (!isObject(given)) return { error: "a template is a JSON object" }
  var dropped = []
  var id = typeof given.id === "string" ? given.id.trim() : ""
  if (!ID.test(id)) return { error: "id: 1 to 32 of a–z, 0–9 and -, starting with a letter or digit" }
  var name = plain(given.name, MAX_NAME)
  if (!name) return { error: "name: a few words (at most " + MAX_NAME + " characters)" }
  if (typeof given.name === "string" && given.name.trim().length > MAX_NAME) dropped.push("name (cut to " + MAX_NAME + " characters)")
  var t = { id: id, name: name, description: plain(given.description, MAX_DESCRIPTION) }
  if (typeof given.description === "string" && given.description.trim().length > MAX_DESCRIPTION) dropped.push("description (cut to " + MAX_DESCRIPTION + " characters)")
  var known = ["id", "name", "description", "colors", "fonts", "header", "face", "pad", "layout", "now", "guideList", "elements"]
  for (var k in given) if (known.indexOf(k) < 0) dropped.push(k + " (not part of a template)")

  t.colors = {}
  if (given.colors !== undefined) {
    if (!isObject(given.colors)) dropped.push("colors (role to #rrggbb)")
    else for (var role in given.colors) {
      if (ROLE_NAMES.indexOf(role) < 0) { dropped.push("colors." + role + " (roles: " + ROLE_NAMES.join(", ") + ")"); continue }
      var cv = typeof given.colors[role] === "string" ? given.colors[role].trim() : ""
      if (isHex(cv)) t.colors[role] = cv.toLowerCase()
      else dropped.push("colors." + role + " (#rrggbb or #aarrggbb)")
    }
  }
  t.fonts = { body: "system", display: "system", mono: "dm-mono" }
  if (given.fonts !== undefined) {
    if (!isObject(given.fonts)) dropped.push("fonts ({body, display, mono})")
    else for (var fr in given.fonts) {
      if (FONT_ROLES.indexOf(fr) < 0) dropped.push("fonts." + fr + " (body, display or mono)")
      else if (FONTS.indexOf(given.fonts[fr]) < 0) dropped.push("fonts." + fr + " (" + FONTS.join(", ") + ")")
      else t.fonts[fr] = given.fonts[fr]
    }
  }
  t.header = given.header === "none" ? "none" : "title"
  if (given.header !== undefined && given.header !== "none" && given.header !== "title") dropped.push("header (title or none)")
  t.face = given.face === "icon" ? "icon" : "label"
  if (given.face !== undefined && given.face !== "icon" && given.face !== "label") dropped.push("face (label or icon)")
  t.pad = given.pad === "off" ? "off" : "on"
  if (given.pad !== undefined && given.pad !== "off" && given.pad !== "on") dropped.push("pad (on or off)")

  var layout = isObject(given.layout) ? given.layout : {}
  if (!isObject(given.layout)) return { error: "layout: { portrait: [rows] }" }
  for (var lk in layout) if (["portrait", "expanded", "landscape"].indexOf(lk) < 0) dropped.push("layout." + lk + " (portrait, expanded or landscape)")
  t.layout = { portrait: checkRows(layout.portrait, "layout.portrait", dropped, false, newSeen()) }
  if (!t.layout.portrait.length) return { error: "layout.portrait: at least one row with a control", dropped: dropped }
  if (layout.expanded !== undefined) {
    var ex = checkRows(layout.expanded, "layout.expanded", dropped, false, newSeen())
    if (ex.length) t.layout.expanded = ex
  }
  // expand and collapse only where they lead somewhere
  if (t.layout.expanded && controlsIn(t.layout.portrait).indexOf("expand") < 0) {
    dropped.push("layout.expanded (layout.portrait has no expand control to show it)")
    delete t.layout.expanded
  }
  if (!t.layout.expanded && controlsIn(t.layout.portrait).indexOf("expand") >= 0) { dropped.push("expand (there's no layout.expanded)"); t.layout.portrait = without(t.layout.portrait, "expand") }
  if (controlsIn(t.layout.portrait).indexOf("collapse") >= 0) { dropped.push("layout.portrait: collapse (only in layout.expanded)"); t.layout.portrait = without(t.layout.portrait, "collapse") }
  if (t.layout.expanded) {
    if (controlsIn(t.layout.expanded).indexOf("expand") >= 0) { dropped.push("layout.expanded: expand (only in layout.portrait)"); t.layout.expanded = without(t.layout.expanded, "expand") }
    if (controlsIn(t.layout.expanded).indexOf("collapse") < 0) dropped.push("layout.expanded has no collapse control (BACK on the phone can't close it either)")
  }
  if (!t.layout.portrait.length) return { error: "layout.portrait: at least one row with a control", dropped: dropped }
  if (layout.landscape !== undefined) {
    var ls = isObject(layout.landscape) ? layout.landscape : null
    if (!ls) dropped.push("layout.landscape ({left: [controls], right: [controls]})")
    else {
      t.layout.landscape = {}
      ;["left", "right"].forEach(function(side) {
        if (ls[side] === undefined) return
        if (!Array.isArray(ls[side])) { dropped.push("layout.landscape." + side + " (a list of controls)"); return }
        var names = ls[side].filter(function(c, i) {
          var ok = typeof c === "string" && CONTROLS[c] && c !== "gap" && ls[side].indexOf(c) === i
          if (!ok) dropped.push("layout.landscape." + side + "[" + i + "] (a control's name, once)")
          return ok
        })
        t.layout.landscape[side] = names.slice(0, MAX_CONTROLS)
      })
      if (t.layout.landscape.left && t.layout.landscape.right) {
        dropped.push("layout.landscape.right (give left or right, not both: left is used)")
        delete t.layout.landscape.right
      }
    }
  }
  t.now = merge({ show: ["channel", "title", "times", "dvr"], side: "logo", align: "left", prefix: false }, checkNow(given.now, "now", dropped))
  for (var nk in (isObject(given.now) ? given.now : {})) if (["show", "side", "align", "prefix"].indexOf(nk) < 0) dropped.push("now." + nk + " (show, side, align or prefix)")
  t.guideList = { show: ["number", "logo", "name", "title", "live", "rec"] }
  if (given.guideList !== undefined) {
    var gl = isObject(given.guideList) && Array.isArray(given.guideList.show) ? given.guideList.show : null
    if (!gl) dropped.push("guideList ({show: [" + LIST_COLUMNS.join(", ") + "]})")
    else t.guideList.show = gl.filter(function(c, i) {
      var ok = LIST_COLUMNS.indexOf(c) >= 0 && gl.indexOf(c) === i
      if (!ok) dropped.push("guideList.show[" + i + "] (" + LIST_COLUMNS.join(", ") + ", each once)")
      return ok
    })
  }
  t.elements = checkElements(given.elements, dropped)
  return { template: t, dropped: dropped }
}

// ---- resolving --------------------------------------------------------------

// The color a style names: a role (the template's own, else the theme's slot,
// else Retro's), a hex, or none
function colorOf(v, roles) {
  if (v === undefined || v === null || v === "none") return "transparent"
  if (isHex(v)) return css(v)
  return roles[v] || "transparent"
}

function resolveStyle(s, roles, fonts) {
  var r = copy(s)
  if (s.fill !== undefined) r.fill = isObject(s.fill) ? { from: colorOf(s.fill.from, roles), to: colorOf(s.fill.to, roles), direction: s.fill.direction } : colorOf(s.fill, roles)
  if (isObject(s.border)) r.border = { width: s.border.width || 0, color: colorOf(s.border.color, roles), sides: s.border.sides || "all" }
  if (isObject(s.shadow)) r.shadow = { color: colorOf(s.shadow.color, roles), blur: s.shadow.blur, x: s.shadow.x, y: s.shadow.y }
  if (s.track !== undefined) r.track = colorOf(s.track, roles)
  if (s.knob !== undefined) r.knob = colorOf(s.knob, roles)
  if (isObject(s.text)) {
    if (s.text.color !== undefined) r.text.color = colorOf(s.text.color, roles)
    if (s.text.font !== undefined) r.text.font = fonts[s.text.font] || "system"
    if (s.text.weight !== undefined) r.text.weight = typeof s.text.weight === "number" ? s.text.weight : WEIGHTS[s.text.weight]
  }
  return r
}

// A checked template made ready for the phone, with the TV's theme colors
// on now (slots: the guide's colors, by slot name): every color a CSS color,
// every font a font id, every element's style complete (defaults under the
// template's), and the template's settings as they are
function resolve(t, slots) {
  var roles = {}
  for (var i = 0; i < ROLE_NAMES.length; i++) {
    var role = ROLE_NAMES[i]
    var v = t.colors[role] || (slots && isHex(slots[ROLES[role]]) ? slots[ROLES[role]] : "") || RETRO[ROLES[role]]
    roles[role] = css(v)
  }
  var styles = {}
  var names = {}
  for (var d in DEFAULTS) names[d] = true
  for (var e in t.elements) names[e] = true
  for (var n in names) styles[n] = resolveStyle(merge(DEFAULTS[n] || {}, t.elements[n]), roles, t.fonts)
  return {
    id: t.id, name: t.name, description: t.description, header: t.header, face: t.face, pad: t.pad,
    fonts: copy(t.fonts), colors: roles, layout: copy(t.layout), now: copy(t.now), guideList: copy(t.guideList), styles: styles
  }
}

// ---- for agents -------------------------------------------------------------

// What a template can use, for remoteControls
function controls() {
  var cs = []
  for (var c in CONTROLS) {
    var x = CONTROLS[c]
    var row = { control: c }
    if (x.label) row.label = x.label
    if (x.icon) row.icon = x.icon
    if (x.faces) row.faces = x.faces
    if (x.variants) row.variants = x.variants
    if (x.about) row.about = x.about
    cs.push(row)
  }
  var els = []
  for (var e in ELEMENTS) els.push({ element: e, about: ELEMENTS[e], own: OWN[e] ? Object.keys(OWN[e]) : undefined, key: KEYS.indexOf(e) >= 0 || undefined })
  return {
    controls: cs, nowLines: NOW_LINES, nowSides: NOW_SIDES, listColumns: LIST_COLUMNS, panels: PANELS, elements: els, states: STATES,
    box: ["fill", "border", "radius", "shape", "shadow", "padding", "opacity", "icon", "place"], text: ["color", "font", "size", "weight", "case", "letterSpacing", "italic"],
    shapes: SHAPES, fonts: FONTS, roles: ROLES,
    caps: { rows: MAX_ROWS, perRow: MAX_ITEMS, controls: MAX_CONTROLS, elements: MAX_ELEMENTS, name: MAX_NAME, description: MAX_DESCRIPTION, bytes: 65536, yours: 50 }
  }
}

// Where each control lands on a phone w by h pixels (its layout, or the
// expanded one), as the page lays it out: the space under the header split
// by the rows' heights (percent), never a key row under 44 px (the tabs 32),
// what's left to the rows that grow, each row's width by its items' weights;
// a round key is as wide as it's tall. Keys drawn under 44 px a side are
// named; scrolls: the rows don't fit (the page scrolls).
function sizes(t, w, h, which, padOn) {
  var rows = (which === "expanded" && t.layout.expanded) ? t.layout.expanded : t.layout.portrait
  var pad = padOn === undefined ? t.pad === "on" : !!padOn
  var W = Math.min(w, 464) - 24
  var U = Math.min(W, 440) / 100
  var H = h - 48
  var gap = Math.round(2 * U)
  var styleOf = function(name) { var s = merge(DEFAULTS[name] || {}, t.elements[name]); return KEYS.indexOf(name) >= 0 ? merge(merge(DEFAULTS.key, t.elements.key), s) : s }
  var keep = function(r) { return !r.pad || (r.pad === "on") === pad }
  var fixed = 0, entries = 0, flat = []
  for (var i = 0; i < rows.length; i++) {
    var e = rows[i]
    if (e.panel) {
      var inner = e.rows.filter(keep)
      if (!inner.length) continue
      var pp = (styleOf(e.panel).padding || 0) * U
      fixed += pp * 2 + (e.handle ? 4 * U : 0) + gap * Math.max(0, inner.length - 1)
      inner.forEach(function(r) { flat.push({ r: r, width: W - pp * 2 }) })
    } else if (keep(e)) flat.push({ r: e, width: W })
    else continue
    entries += 1
  }
  fixed += gap * Math.max(0, entries - 1)
  var avail = Math.max(120, H - fixed)
  var hasKey = function(r) { return r.row.some(function(it) { return KEYS.indexOf(it.control) >= 0 || ["dpad", "pad", "rocker"].indexOf(it.control) >= 0 }) }
  var minOf = function(r) { return hasKey(r) ? 44 : r.row.some(function(it) { return it.control === "tabs" }) ? 32 : r.row.every(function(it) { return it.control === "gap" }) ? 0 : 24 }
  var sum = 0, growing = 0
  flat.forEach(function(f) { f.h = Math.max(minOf(f.r), Math.floor(avail * f.r.height / 100)); sum += f.h; if (f.r.grow) growing += 1 })
  var left = avail - sum
  if (left > 0 && growing) flat.forEach(function(f) { if (f.r.grow) f.h += Math.floor(left / growing) })
  var out = [], small = []
  flat.forEach(function(f) {
    var items = f.r.row.filter(function(it) { return pad || it.control !== "pad" })
    var total = 0
    items.forEach(function(it) { total += it.weight || 1 })
    var rg = f.r.gap !== undefined ? f.r.gap * U : gap
    var free = f.width - rg * Math.max(0, items.length - 1)
    items.forEach(function(it) {
      if (it.control === "gap") return
      var cw = free * (it.weight || 1) / total, k = it.scale || 1
      var st = styleOf(it.control)
      if (it.alt) st = merge(st, merge(t.elements["key:alt"], t.elements[it.control + ":alt"]))
      var round = KEYS.indexOf(it.control) >= 0 && st.shape === "circle"
      var s = round ? { control: it.control, w: Math.round(Math.min(cw, f.h) * k), h: Math.round(Math.min(cw, f.h) * k) }
                    : { control: it.control, w: Math.round(cw * k), h: Math.round(f.h * k) }
      out.push(s)
      if (KEYS.indexOf(it.control) >= 0 && (s.w < 44 || s.h < 44)) small.push(it.control)
    })
  })
  return { controls: out, under44: small, scrolls: sum + fixed > H }
}
