// node tests/look.test.mjs
import { readFileSync } from "node:fs"
import assert from "node:assert/strict"

const src = readFileSync(new URL("../Look.js", import.meta.url), "utf8").replace(".pragma library", "")
const L = new Function(src + "; return { ELEMENTS, BY_KEY, LAYOUT, checkElements, checkFonts, checkLayout, effectiveLayout, checkStyle, effective, resolve, px, describe, merge, themeUsable, bgProvenance, bgFloored, themeBackground, themePicture, isOmarchy, FONT_ROLES }")()

const slots = ["text", "textDim", "accent", "cell", "cellBorder", "selected", "selectedText", "header", "headerText", "band", "bandText",
               "channelCell", "bgTop", "bgBottom", "preview", "infoPanel", "alert", "timeline", "keyFace", "keyText", "keyEdge",
               "boxBg", "boxBorder", "scrim", "ltBg", "ltBorder", "ltNumber", "ltChannel", "ltTitle", "ltProgress", "ltTrack",
               "ltClock", "ltTime", "cardBackdrop", "cardName", "cardStatus", "cardFrame"]
const families = ["Adwaita Sans", "JetBrainsMono Nerd Font", "Nimbus Sans Narrow"]

// Every element's own (Retro) style passes its own checks: nothing ignored.
for (const el of L.ELEMENTS) {
  // "auto" and "inherit" are defaults only: a lighter face, the cell's text color
  const res = L.checkStyle(el.key, el.style, slots.concat(["auto", "inherit"]), null)
  const ignored = res.ignored
  assert.deepEqual(ignored, [], el.key)
  for (const [state, s] of Object.entries(el.stateStyle || {})) {
    assert.ok(el.states.includes(state), el.key + ":" + state)
    assert.deepEqual(L.checkStyle(el.key, s, slots, null, state).ignored, [], el.key + ":" + state)
  }
}

// Colors, lengths, shapes and text, checked.
{
  const { elements, ignored } = L.checkElements({
    programCell: { fill: "#1A1A1C", radius: 0.4, border: { width: "2px", color: "none" }, text: { size: 1.1, weight: "medium", case: "none" } },
    "programCell:selected": { fill: "#f2f2f2", shadow: { blur: 1.5 }, text: { color: "#000000" } },
    band: { fill: "none", text: { letterSpacing: 0.15, color: "textDim" } },
    title: { color: "accent", font: "Adwaita Sans", size: 1.6 },             // a text-only element takes text properties on their own
    lowerThird: { shape: "pill", width: 0.6, align: "left", margin: 2, shadow: { color: "#80000000", blur: 1.5, y: 0.4 } },
    preview: { shape: "path", path: "M0,10 Q0,0 10,0 L100,0 L100,100 L0,100 Z" },
  }, slots, families)
  assert.deepEqual(ignored, [])
  assert.equal(elements.programCell.fill, "#1a1a1c")
  assert.deepEqual(elements.programCell.border, { width: "2px", color: "none" })
  assert.deepEqual(elements.title, { text: { color: "accent", font: "Adwaita Sans", size: 1.6 } })
  assert.equal(elements["programCell:selected"].shadow.blur, 1.5)
  assert.equal(elements.lowerThird.width, 0.6)
}

// What isn't right is left out, and said.
{
  const { elements, ignored } = L.checkElements({
    programCell: { fill: "red", shadow: { blur: 1 }, color: "#fff", text: { size: 99, wobble: 1 } },
    "programCell:hover": { fill: "#000000" },
    nosuch: { fill: "#000000" },
    title: { font: "Comic Sans MS" },
    lowerThird: { shape: "blob", width: 2 },
  }, slots, families)
  assert.equal(elements.programCell.text.size, 12)            // clamped
  assert.equal(elements.programCell.fill, undefined)
  assert.equal(elements.title, undefined)
  const said = ignored.join("\n")
  for (const bit of ["programCell.fill", "programCell.shadow", "programCell.color (goes under text)", "programCell.text.wobble",
                     "programCell:hover", "nosuch", "title.text.font", "lowerThird.shape", "lowerThird.width"])
    assert.ok(said.includes(bit), bit + " in\n" + said)
}

// Fonts: roles to installed families only.
{
  const { fonts, ignored } = L.checkFonts({ body: "adwaita sans", display: "Nope", mono: "monospace", heading: "x" }, families)
  assert.deepEqual(fonts, { body: "Adwaita Sans", mono: "monospace" })
  assert.equal(ignored.length, 2)
  // a list: the first one installed
  assert.deepEqual(L.checkFonts({ body: ["Inter", "Nimbus Sans Narrow", "sans-serif"], display: ["Nope", "Nada"] }, families).fonts, { body: "Nimbus Sans Narrow" })
}

// Layers: Retro, then the theme, then yours; a state over its element.
{
  const theme = { programCell: { radius: 0.4, text: { color: "#dddddd", size: 1.1 } }, "programCell:selected": { fill: "#ffffff" } }
  const yours = { programCell: { fill: "#222222" } }
  const eff = L.effective(theme, yours)
  assert.equal(eff.programCell.fill, "#222222")
  assert.equal(eff.programCell.radius, 0.4)
  assert.equal(eff["programCell:selected"].fill, "#ffffff")
  assert.equal(eff["programCell:selected"].radius, 0.4)                // inherited
  assert.equal(eff["programCell:selected"].text.size, 1.1)             // inherited
  assert.equal(eff["programCell:selected"].text.color, "selectedText") // the state's own beats the element's
  assert.equal(L.ELEMENTS.find(e => e.key === "programCell").style.radius, undefined)   // Retro's untouched
}

// Resolving: slot names to colors, roles to families, "none" to clear.
{
  const colors = { cell: "#1b3591", cellBorder: "#3b5bd1", text: "#f2f4ff", selected: "#ffd23f", selectedText: "#141414", accent: "#ffd23f",
                   bgTop: "#071447", bgBottom: "#030a2b" }
  const look = L.resolve({ band: { fill: "none" } }, {}, colors, { body: "Sans", display: "Display", mono: "Mono" })
  assert.equal(look.programCell.fill, "#1b3591")
  assert.deepEqual(look.programCell.border, { width: "1px", color: "#3b5bd1", sides: "all" })
  assert.equal(look["programCell:selected"].text.color, "#141414")
  assert.equal(look["programCell:selected"].text.weight, 700)
  assert.equal(look.title.text.font, "Display")
  assert.equal(look.programCell.text.font, "Sans")
  assert.equal(look.band.fill, "transparent")
  assert.deepEqual(look.background.fill, { from: "#071447", to: "#030a2b", direction: "down" })
  assert.equal(look.channelCell.border.width, 0)                       // a clear border draws nothing
}

// Layout: known settings in range; Retro's under the theme's under yours.
{
  const { layout, ignored } = L.checkLayout({ masthead: "none", clock: "info", upNext: 2.6, hours: 2, rowHeight: 99, wobble: 1, preview: "top",
                                              columns: ["name", "now", "name", "sparkle"] })
  assert.deepEqual(layout, { masthead: "none", clock: "info", upNext: 3, hours: 2, rowHeight: 8, columns: ["name", "now"] })
  assert.equal(ignored.length, 3)
  const eff = L.effectiveLayout({ hours: 2, upNext: 2 }, { upNext: 0 })
  assert.equal(eff.hours, 2)
  assert.equal(eff.upNext, 0)
  assert.equal(eff.masthead, "title")
  assert.equal(eff.rowHeight, 3.4)
  for (const spec of L.LAYOUT) assert.deepEqual(L.checkLayout({ [spec.key]: spec.value }).ignored, [], spec.key)
}

assert.equal(L.px(2, 17), 34)
assert.equal(L.px("3px", 17), 3)
assert.ok(L.describe("programCell", {}, {}).states.includes("selected"))

// ---- milestone 2: an app's screen's parts follow the guide's (§9) ----------
{
  // one hop, no cycles: every twin exists and follows nothing
  for (const el of L.ELEMENTS.filter(e => e.follows)) {
    assert.ok(L.BY_KEY[el.follows], el.key + " follows " + el.follows)
    assert.ok(!L.BY_KEY[el.follows].follows, el.key + ": its twin follows nothing")
    for (const st of el.states || []) assert.ok((L.BY_KEY[el.follows].states || []).includes(st), el.key + ":" + st + " has a twin state")
  }
  const apps = L.ELEMENTS.filter(e => e.section === "APPS").map(e => e.key)
  assert.deepEqual(apps, ["appCard", "appCardTitle", "appCardSub", "appRowTitle", "appBadge", "appProgress", "appTopKicker", "appTopTitle", "appTopMeta",
                          "appTopText", "appDetailTitle", "appDetailMeta", "appDetailText", "appFactLabel", "appFactValue", "appChip", "appButton", "appShade",
                          "appTableHead", "appTable", "appTicker", "appChart", "appOrigin", "appPageTitle", "appPageHeading", "appPageText"])
  // Multiview: every tile framed thinly in the cell border, the one with the
  // sound in the accent, thicker; its labels and badge follow the library's
  const mv = L.ELEMENTS.filter(e => e.section === "MULTIVIEW").map(e => e.key)
  assert.deepEqual(mv, ["mvBackground", "mvTile", "mvStrip", "mvName", "mvShow", "mvSound"])
  assert.deepEqual(L.effective({}, {}).mvBackground, L.effective({}, {}).background, "Multiview's background is the guide's until styled")
  const mvEff = L.effective({}, {})
  assert.equal(mvEff.mvTile.border.color, "cellBorder")
  assert.ok(mvEff.mvTile.border.width > 0, "unselected tiles have a border too")
  assert.equal(mvEff["mvTile:current"].border.color, "accent")
  assert.ok(mvEff["mvTile:current"].border.width > mvEff.mvTile.border.width, "the sound's is thicker")
  assert.deepEqual(mvEff.mvName, mvEff.posterTitle)
  assert.deepEqual(mvEff.mvSound, mvEff.cardBadge)
  // agents and themes style every Multiview part (setStyle and a theme's
  // elements both go through checkElements), and the user's own goes on top
  const mvSet = L.checkElements({ mvBackground: { fill: "#102030" }, mvTile: { border: { width: 0.15, color: "alert" }, radius: 0 },
                                  "mvTile:current": { border: { color: "#ffffff" } }, mvStrip: { fill: "#c0000000" },
                                  mvName: { text: { color: "accent" } }, mvShow: { text: { color: "textDim" } }, mvSound: { fill: "alert" } }, slots, families)
  assert.deepEqual(mvSet.ignored, [])
  const themed = L.effective(mvSet.elements, {})
  assert.equal(themed.mvBackground.fill, "#102030")
  assert.deepEqual([themed.mvTile.border.width, themed.mvTile.border.color, themed.mvTile.radius], [0.15, "alert", 0])
  assert.equal(themed["mvTile:current"].border.color, "#ffffff")
  assert.equal(themed.mvStrip.fill, "#c0000000")
  assert.equal(themed.mvName.text.color, "accent")
  assert.equal(themed.mvShow.text.color, "textDim")
  assert.equal(themed.mvSound.fill, "alert")
  assert.equal(L.effective(mvSet.elements, { mvTile: { border: { width: 0.05 } } }).mvTile.border.width, 0.05, "the user's over the theme's")
  // where an app is from (code apps v2 §6): solid by default, in the box's colors
  assert.deepEqual(L.effective({}, {}).appOrigin, { color: "boxBg", edge: "boxBorder", size: 1.7 })
  // with nothing styled, each looks like its twin (and appCard grows when current)
  let eff = L.effective({}, {})
  assert.deepEqual(eff.appCardTitle, eff.posterTitle)
  assert.deepEqual(eff.appTopTitle, eff.heroTitle)
  assert.equal(eff.appCard.fill, eff.posterCard.fill)
  assert.deepEqual([eff.appCard.grow, eff["appCard:current"].grow], [0, 0.05], "today's 1.05")
  assert.deepEqual(eff["appCard:current"].border, eff["posterCard:current"].border, "a lit border, as the library's")
  assert.deepEqual(eff["appButton:focused"].fill, eff["menuRow:focused"].fill)
  // api 4's parts look like their twins too, and the chart's line is the accent
  assert.deepEqual(eff["appTable:focused"].fill, eff["menuRow:focused"].fill)
  assert.deepEqual(eff.appPageText, eff.boxText)
  assert.deepEqual(eff.appTableHead, eff.posterSub)
  assert.equal(eff.appChart.color, "accent")
  // posterCard:current, styled by a theme, reaches appCard:current
  eff = L.effective({ "posterCard:current": { border: { color: "#ff00ff" } }, posterCard: { radius: 1.2 } }, {})
  assert.equal(eff["appCard:current"].border.color, "#ff00ff")
  assert.equal(eff.appCard.radius, 1.2, "the twin's base reaches the base")
  assert.equal(eff["appCard:current"].radius, 1.2, "and the state")
  // its own styles go on top: base over the twin's state, its state over all
  eff = L.effective({ posterCard: { fill: "#111111" }, "posterCard:current": { fill: "#222222" }, appCard: { fill: "#333333" } }, { "appCard:current": { border: { width: 0.3 } } })
  assert.equal(eff.appCard.fill, "#333333")
  assert.equal(eff["appCard:current"].fill, "#333333", "its own base over its twin's state")
  assert.equal(eff["appCard:current"].border.width, 0.3, "yours on its state, on top")
  assert.equal(eff["posterCard:current"].fill, "#222222", "the twin isn't touched")
  // an inherited shadow: gone from the base (cards are drawn many times), kept on current
  eff = L.effective({ posterCard: { shadow: { color: "#000000", blur: 2, x: 0, y: 0.3 } } }, {})
  assert.equal(eff.posterCard.shadow.blur, 2)
  assert.equal(eff.appCard.shadow, undefined, "removed from appCard's base")
  assert.equal(eff["appCard:current"].shadow.blur, 2, "the selected one may keep it")
  const r = L.resolve({ posterCard: { shadow: { color: "#000000", blur: 2, x: 0, y: 0.3 } } }, {}, { cell: "#123456", accent: "#ffd23f", text: "#ffffff" }, { body: "Sans", display: "Sans", mono: "Mono" }, {})
  assert.equal(r.appCard.shadow, undefined)
  assert.ok(r["appCard:current"].shadow)
  // and a theme can't give appCard's base one of its own
  const chk = L.checkElements({ appCard: { shadow: { blur: 1 } }, "appCard:current": { shadow: { blur: 1 } } }, slots, families)
  assert.equal(chk.ignored.length, 1)
  assert.ok(chk.elements["appCard:current"].shadow)
  // the appShade follows Home's shade's color
  eff = L.effective({ homeShade: { color: "#102030" } }, {})
  assert.equal(eff.appShade.color, "#102030")
  assert.equal(L.describe("appCard", {}, {}).follows, "posterCard")
}

// a theme with only the look of apps' screens is one to use (addTheme)
assert.equal(L.themeUsable({ colors: {}, elements: {}, fonts: {}, layout: {}, apps: { look: "cinematic" } }), true)
assert.equal(L.themeUsable({ colors: {}, elements: {}, fonts: {}, layout: {} }), false)
assert.equal(L.themeUsable({ colors: { text: "#fff" } }), true)
assert.equal(L.themeUsable(null), false)

// The picture behind the guide: where it came from, when an app's screen
// keeps it under the 30% floor (unless it's surely yours), and what a theme
// puts back.
assert.equal(L.bgProvenance("theme"), "theme")
assert.equal(L.bgProvenance("user"), "user")
for (const v of [undefined, null, "", "User", "wallpaper", 1, {}]) assert.equal(L.bgProvenance(v), "", String(v))
assert.equal(L.bgFloored("image", "/p/t.jpg", "theme"), true)
assert.equal(L.bgFloored("image", "/p/t.jpg", ""), true, "not known where it came from: floored")
assert.equal(L.bgFloored("image", "/p/u.jpg", "user"), false, "yours goes as you set it")
assert.equal(L.bgFloored("wallpaper", "", ""), false, "and your wallpaper")
assert.equal(L.bgFloored("none", "/p/t.jpg", "theme"), false)
assert.equal(L.bgFloored("image", "", "theme"), false)
{
  // settings.json, and the look kept for undo, from before "from" was kept
  // (milestone 1 wrote { mode, image, dim }): floored until it's picked again
  const legacy = { mode: "image", image: "/home/u/.config/om-pg/themes/t/bg.jpg", dim: 0.1 }
  assert.equal(L.bgFloored(legacy.mode, legacy.image, L.bgProvenance(legacy.from)), true)
}
{
  // theme T with a picture; you pick U; Background reset (the row or the look): T's, the theme's
  const T = { id: "t", dir: "/home/u/.config/om-pg/themes/t", background: { mode: "image", image: "bg.jpg", dim: 0.1 } }
  let now = L.themeBackground(T, { image: "", from: "" })
  assert.deepEqual(now, { mode: "image", image: T.dir + "/bg.jpg", from: "theme" })
  now = { mode: "image", image: "/home/u/Pictures/u.jpg", from: "user" }
  assert.equal(L.bgFloored(now.mode, now.image, now.from), false)
  now = L.themeBackground(T, now)
  assert.deepEqual(now, { mode: "image", image: T.dir + "/bg.jpg", from: "theme" })
  assert.equal(L.bgFloored(now.mode, now.image, now.from), true)
  // a picture given by its full path stays so
  assert.equal(L.themeBackground({ dir: "/x", background: { mode: "image", image: "/abs/p.png" } }, now).image, "/abs/p.png")
  // a theme with image mode and no picture of its own: yours stays yours; with none at all, none
  assert.deepEqual(L.themeBackground({ dir: "/x", background: { mode: "image" } }, { image: "/home/u/u.jpg", from: "user" }),
                   { mode: "image", image: "/home/u/u.jpg", from: "user" })
  assert.deepEqual(L.themeBackground({ dir: "/x", background: { mode: "image", image: "" } }, { image: "", from: "" }),
                   { mode: "none", image: "", from: "" })
  // none and the wallpaper: the mode (the picture kept, not drawn); no background at all: none
  assert.equal(L.themeBackground({ dir: "/x", background: { mode: "wallpaper" } }, now).mode, "wallpaper")
  assert.equal(L.themeBackground({ dir: "/x" }, now).mode, "none")
  assert.equal(L.themeBackground(null, { image: "/a.jpg", from: "odd" }).from, "", "an odd from is unknown")
}
{
  // Guide.qml can't load outside the shell, so its own code is read and run:
  // the functions that put a picture behind the guide, taken from Guide.qml
  // and Commands.qml as they are, run over a stand-in guide.
  const guideSrc = readFileSync(new URL("../Guide.qml", import.meta.url), "utf8")
  const commandsSrc = readFileSync(new URL("../Commands.qml", import.meta.url), "utf8")
  // a block of code: from its opening line to the closing brace at its indent
  const block = (text, opener) => {
    const i = text.indexOf(opener)
    assert.ok(i >= 0, "missing: " + opener)
    const lineStart = text.lastIndexOf("\n", i) + 1
    const indent = text.slice(lineStart, i).match(/^ */)[0]
    const open = text.indexOf("{", i + opener.length - 1)
    // all on one line: to the brace that closes it there
    const line = text.slice(open, text.indexOf("\n", open))
    let depth = 0
    for (let k = 0; k < line.length; k++) {
      if (line[k] === "{") depth++
      else if (line[k] === "}" && --depth === 0) return line.slice(1, k)
    }
    const end = text.indexOf("\n" + indent + "}\n", open)
    assert.ok(end > open, "no end: " + opener)
    return text.slice(open + 1, end)
  }
  // the stores the guide's code reaches: the theme turn, and your choices for all apps (AppScreens)
  const appLooksSrc = readFileSync(new URL("../AppLooks.js", import.meta.url), "utf8").replace(".pragma library", "")
  const AL = new Function(appLooksSrc + "; return { checkChoices, appsForTheme, allMatching }")()
  const themesItem = { changing: false, busyWhy: "a theme change is still being made: try again in a moment" }
  const appScreensItem = { now: { all: {} }, writes: [], watchers: {}, pictureOk: () => false,
    change(key, fn, from, what) { const st = { all: JSON.parse(JSON.stringify(appScreensItem.now.all)), apps: {} }; fn(st); appScreensItem.now = { all: st.all }; appScreensItem.writes.push(what); return { ok: true, token: "w-test-" + appScreensItem.writes.length } },
    whenDone(token, f) { appScreensItem.watchers[token] = f } }   // (held: a test says how each write went)
  const appPanelItem = { dropped: [], dropPick(key) { appPanelItem.dropped.push(key) } }
  const fn = (text, name, params) => new Function("root", "Look", "guide", "commands", "Quickshell", "appsStore", "keys", "dialogBox", "themesItem", "appScreensItem", "AppLooks", "appPanelItem", ...params,
                                                  block(text, "function " + name + "("))
  const real = {}
  for (const [name, params] of [["themeOption", ["section", "field", "otherwise"]], ["putThemeBackground", []], ["applyTheme", ["id"]],
                                ["choosePick", ["by"]], ["resetStyleRow", []], ["resetStyle", ["to"]], ["undoReset", []],
                                ["snapshotStyle", []], ["checkedSnapshot", ["snap"]], ["clamp", ["v", "lo", "hi", "otherwise"]],
                                ["putStyle", ["snap", "takingBack"]], ["replaceHomeBackground", ["b"]], ["replaceMultiviewBackground", ["b"]], ["whenLookSaved", ["token", "base", "applied", "failed"]],
                                ["takeBackStyle", ["base", "applied"]]])
    real[name] = fn(guideSrc, name, params)
  const loadBackground = new Function("root", "Look", "saved", block(guideSrc, "if (saved.background) {"))
  const backgroundCommand = new Function("guide", "commands", "Quickshell", "mode", "dim", block(commandsSrc, "function background(mode: string, dim: string): string {"))

  const T = { id: "t", name: "T", dir: "/home/u/.config/om-pg/themes/t", background: { mode: "image", image: "bg.jpg", dim: 0.1 } }
  const byUser = {}
  const root = {
    themes: [{ id: "retro", name: "Retro" }, T], themeId: "retro",
    bgMode: "none", bgImage: "", bgFrom: "", bgDim: 0.6,
    colorOverrides: {}, imageOverrides: {}, elementOverrides: {}, fontOverrides: {}, layoutOverrides: {},
    homeBackground: { mode: "focus", image: "", dim: 0.6 }, multiviewBackground: { mode: "none", image: "", color: "", dim: 0.6 }, mvBgModes: ["none", "color", "theme", "wallpaper", "image"], mvPickSeq: 0, ltShow: true, ltSeconds: 4, cardShow: true, cardSeconds: 1.4,
    beforeReset: null, byUser: byUser, colorSlots: [], colorKeys: [], installedFonts: [], homeBgModes: ["focus", "image", "none"], homePickSeq: 0, styleRefused: "", lookSaving: "",
    pickMatches: [], pickCursor: 0, pickApps: false, pickFolders: false, pickImages: true, pickArea: "",
    styleRows: [{ type: "bg" }], styleCursor: 0, saves: 0,
    get currentTheme() { return root.themes.find(t => t.id === root.themeId) || {} },
    saveSettings() { root.saves++ }, backToStyle() {}, themeColor() { return "" }, isHex: () => true, solidHex: v => typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v), checkedImage: () => null, homePictureOk: () => false,
    themeIdFrom: id => id
  }
  for (const name of Object.keys(real)) root[name] = (...args) => real[name](root, L, null, null, null, null, null, null, themesItem, appScreensItem, AL, appPanelItem, ...args)
  const floored = () => L.bgFloored(root.bgMode, root.bgImage, root.bgFrom)
  const now = () => ({ mode: root.bgMode, image: root.bgImage, from: root.bgFrom })
  const pick = path => { root.pickMatches = [{ path: path }]; root.pickCursor = 0; root.choosePick(byUser) }
  const tPic = { mode: "image", image: T.dir + "/bg.jpg", from: "theme" }
  const uPic = { mode: "image", image: "/home/u/Pictures/u.jpg", from: "user" }

  // T on: its picture, the theme's, floored
  assert.equal(root.applyTheme("t"), true)
  assert.deepEqual(now(), tPic)
  assert.equal(floored(), true)
  // you pick U: yours, as you set it
  pick(uPic.image)
  assert.deepEqual(now(), uPic)
  assert.equal(floored(), false)
  // Background reset (the row alone): T's again, the theme's, floored
  root.resetStyleRow()
  assert.deepEqual(now(), tPic, "the row reset puts the theme's picture back, as the theme's")
  assert.equal(floored(), true)
  // the whole look reset, then undone: T's, then U as yours again
  pick(uPic.image)
  root.resetStyle("theme")
  assert.deepEqual(now(), tPic)
  assert.equal(root.undoReset().ok, true)
  assert.deepEqual(now(), uPic, "undo gives yours back as yours")
  // putting T on again over yours: the theme's
  root.applyTheme("retro")
  assert.deepEqual(now(), uPic, "a theme with no picture leaves yours")
  root.applyTheme("t")
  assert.deepEqual(now(), tPic)
  // a reset kept by the version before (no "from"), undone: not known, floored
  root.beforeReset = { theme: "t", background: { mode: "image", image: "/home/u/old.jpg", dim: 0.1 } }
  assert.equal(root.undoReset().ok, true)
  assert.deepEqual(now(), { mode: "image", image: "/home/u/old.jpg", from: "" })
  assert.equal(floored(), true)
  // the resets take yours for all apps too (a confirmed write), and undo puts them back
  appScreensItem.now = { all: { look: "wall", size: "large" } }
  root.applyTheme("t")
  const rs = root.resetStyle("theme")
  assert.deepEqual(rs, { ok: true, saving: "w-test-" + appScreensItem.writes.length })
  assert.deepEqual(appScreensItem.now.all, {}, "a reset clears yours for all apps")
  appScreensItem.watchers[rs.saving]("saved")
  const ur = root.undoReset()
  assert.equal(ur.ok, true)
  assert.deepEqual(appScreensItem.now.all, { look: "wall", size: "large" }, "and undo puts them back")
  appScreensItem.watchers[ur.saving]("saved")
  // a reset kept by the version before (no appsAll): undoing it leaves yours for all apps as they are
  root.beforeReset = { theme: "t", background: { mode: "none", dim: 0.6 } }
  appScreensItem.now = { all: { top: "off" } }
  assert.equal(root.undoReset().ok, true)
  assert.deepEqual(appScreensItem.now.all, { top: "off" })
  // while a theme change is out, no reset and no undo
  themesItem.changing = true
  const was = JSON.stringify(now()) + JSON.stringify(appScreensItem.now)
  assert.equal(root.resetStyle("theme").ok, false)
  root.beforeReset = root.snapshotStyle()
  assert.equal(root.undoReset().ok, false)
  assert.equal(JSON.stringify(now()) + JSON.stringify(appScreensItem.now), was, "nothing changed")
  themesItem.changing = false
  root.beforeReset = null
  // the all-apps write refused (full, too big): neither a reset nor an undo changes anything,
  // and the look kept for undo stays
  {
    appScreensItem.now = { all: { look: "wall" } }
    root.colorSlots = [{ key: "text", value: "#ffffff" }]
    const realChange = appScreensItem.change
    appScreensItem.change = () => ({ ok: false, error: "still saving: try again in a moment" })
    root.colorOverrides = { text: "#123456" }
    const was = JSON.stringify([now(), root.colorOverrides, root.themeId, root.beforeReset, appScreensItem.now])
    assert.deepEqual(root.resetStyle("theme"), { ok: false, error: "still saving: try again in a moment" })
    assert.equal(JSON.stringify([now(), root.colorOverrides, root.themeId, root.beforeReset, appScreensItem.now]), was, "a refused reset changes nothing")
    appScreensItem.change = realChange
    const rr = root.resetStyle("theme")
    assert.equal(rr.ok, true)
    appScreensItem.watchers[rr.saving]("saved")
    const kept = JSON.stringify(root.beforeReset)
    appScreensItem.change = () => ({ ok: false, error: "still saving: try again in a moment" })
    const was2 = JSON.stringify([now(), root.colorOverrides, root.themeId, appScreensItem.now])
    assert.deepEqual(root.undoReset(), { ok: false, error: "still saving: try again in a moment" })
    assert.equal(JSON.stringify([now(), root.colorOverrides, root.themeId, appScreensItem.now]), was2, "a refused undo changes nothing")
    assert.equal(JSON.stringify(root.beforeReset), kept, "and keeps the look to undo to")
    appScreensItem.change = realChange
    const uu = root.undoReset()
    assert.equal(uu.ok, true)
    assert.deepEqual(root.colorOverrides, { text: "#123456" })
    appScreensItem.watchers[uu.saving]("saved")
    root.colorOverrides = {}
    root.colorSlots = []
    appScreensItem.now = { all: {} }
  }
  // the all-apps write accepted but failing later (AppScreens puts yours for
  // all apps back): what the reset changed goes back, but a change you made
  // since stays, and undo is as it was; an undo goes back to the look as
  // reset the same way, and keeps the look to undo to. Unconfirmed and saved
  // hold. Until the write is done, no other reset, undo or save as a theme.
  // Each drops a picture still being copied for all apps.
  {
    root.colorSlots = [{ key: "text", value: "#ffffff" }, { key: "accent", value: "#ffd23f" }]
    root.colorOverrides = { text: "#123456", accent: "#654321" }
    root.layoutOverrides = { dividers: true }
    root.beforeReset = null
    appScreensItem.now = { all: { look: "wall" } }
    appPanelItem.dropped = []
    const disk = JSON.stringify(appScreensItem.now)
    const r = root.resetStyle("theme")
    assert.equal(r.ok, true)
    assert.deepEqual([root.colorOverrides, root.layoutOverrides], [{}, {}], "reset at once")
    assert.deepEqual(appPanelItem.dropped, ["all"], "a picture on its way for all apps no longer lands")
    assert.equal(root.lookSaving, r.saving, "its write is out")
    assert.deepEqual(root.resetStyle("theme"), { ok: false, error: "the last reset is still being saved: try again in a moment" }, "no second reset meanwhile")
    assert.equal(root.undoReset().ok, false, "nor an undo")
    root.colorOverrides = { accent: "#abcdef" }                 // a change of yours meanwhile
    root.homePickSeq += 1                                       // and a Home picture picked, still being copied
    const pick = root.homePickSeq
    appScreensItem.now = JSON.parse(disk)
    appScreensItem.watchers[r.saving]("failed")
    assert.equal(root.homePickSeq, pick, "the picture picked meanwhile still lands")
    assert.deepEqual(root.colorOverrides, { text: "#123456", accent: "#abcdef" }, "the write failed: what the reset changed goes back, your change since stays")
    assert.deepEqual(root.layoutOverrides, { dividers: true })
    assert.equal(root.beforeReset, null, "and undo is as it was")
    assert.equal(root.lookSaving, "", "and the next reset may go")
    assert.ok(root.styleRefused.indexOf("couldn't be saved") > 0, root.styleRefused)
    const r2 = root.resetStyle("theme")
    appScreensItem.watchers[r2.saving]("unconfirmed")
    assert.deepEqual(root.colorOverrides, {}, "unconfirmed isn't a failure: it holds")
    const kept = root.beforeReset
    assert.ok(kept, "the look to undo to")
    const u = root.undoReset()
    assert.deepEqual(root.colorOverrides, { text: "#123456", accent: "#abcdef" }, "undone at once")
    assert.deepEqual(appPanelItem.dropped, ["all", "all", "all"])
    root.layoutOverrides = { dividers: false }                  // a change of yours meanwhile
    root.homePickSeq += 1                                       // and a Home picture picked, still being copied
    const pick2 = root.homePickSeq
    appScreensItem.now = { all: {} }
    appScreensItem.watchers[u.saving]("failed")
    assert.equal(root.homePickSeq, pick2, "the picture picked meanwhile still lands")
    assert.deepEqual(root.colorOverrides, {}, "the undo failed: what it changed goes back to the look as reset")
    assert.deepEqual(root.layoutOverrides, { dividers: false }, "your change since stays")
    assert.equal(root.beforeReset, kept, "and the look to undo to stays, to try again")
    const u2 = root.undoReset()
    appScreensItem.watchers[u2.saving]("saved")
    assert.deepEqual(root.colorOverrides, { text: "#123456", accent: "#abcdef" }, "saved: it holds")
    assert.equal(root.beforeReset, null)
    assert.equal(root.lookSaving, "")
    root.colorOverrides = {}
    root.layoutOverrides = {}
    root.colorSlots = []
    root.beforeReset = null
    root.styleRefused = ""
    appScreensItem.now = { all: {} }
  }
  // what a failed write takes back: each part still as the operation left
  // it goes back to base, field by field; a picture with where it came
  // from, together; anything you've changed since stays
  {
    const U = "/home/u/Pictures/u.jpg", Tbg = T.dir + "/bg.jpg"
    root.colorSlots = [{ key: "text", value: "#ffffff" }, { key: "accent", value: "#ffd23f" }]
    const set = o => { root.themeId = o.theme; root.colorOverrides = o.colors; root.layoutOverrides = o.layout; root.bgMode = o.bg[0]; root.bgImage = o.bg[1]; root.bgFrom = o.bg[2]; root.bgDim = o.bg[3]
                       root.ltShow = o.lt[0]; root.ltSeconds = o.lt[1]; root.cardShow = o.card[0]; root.cardSeconds = o.card[1]; root.homeBackground = o.home }
    set({ theme: "t", colors: { text: "#111111", accent: "#222222" }, layout: { dividers: true }, bg: ["image", U, "user", 0.3], lt: [false, 9], card: [false, 3], home: { mode: "none", image: "", dim: 0.5 } })
    const base = root.snapshotStyle()
    set({ theme: "retro", colors: {}, layout: {}, bg: ["image", Tbg, "theme", 0.6], lt: [true, 4], card: [true, 1.4], home: { mode: "focus", image: "", dim: 0.6 } })
    const applied = root.snapshotStyle()
    // since: your accent, the darkness, the banner's seconds and Home's darkness
    root.colorOverrides = { accent: "#333333" }
    root.bgDim = 0.8
    root.ltSeconds = 12
    root.homeBackground = { mode: "focus", image: "", dim: 0.7 }
    root.takeBackStyle(root.checkedSnapshot(base), root.checkedSnapshot(applied))
    assert.equal(root.themeId, "t", "the theme back")
    assert.deepEqual(root.colorOverrides, { text: "#111111", accent: "#333333" }, "your text color back, your accent since stays")
    assert.deepEqual(root.layoutOverrides, { dividers: true })
    assert.deepEqual([root.bgMode, root.bgImage, root.bgFrom, root.bgDim], ["image", U, "user", 0.8], "your picture back, as yours; the darkness since stays")
    assert.deepEqual([root.ltShow, root.ltSeconds, root.cardShow, root.cardSeconds], [false, 12, false, 3])
    assert.deepEqual(root.homeBackground, { mode: "none", image: "", dim: 0.7 }, "Home's mode back, its darkness since stays")
    // a picture changed since (with its provenance) stays whole
    set({ theme: "retro", colors: {}, layout: {}, bg: ["image", Tbg, "theme", 0.6], lt: [true, 4], card: [true, 1.4], home: { mode: "focus", image: "", dim: 0.6 } })
    root.bgImage = "/home/u/Pictures/v.jpg"
    root.bgFrom = "user"
    root.themeId = "other"
    root.takeBackStyle(root.checkedSnapshot(base), root.checkedSnapshot(applied))
    assert.deepEqual([root.bgImage, root.bgFrom], ["/home/u/Pictures/v.jpg", "user"], "the picture you picked since stays, as yours")
    assert.equal(root.themeId, "other", "and so does a theme you put on since")
    // an element's style, down to each property: one changed since stays,
    // and the others the operation changed go back
    root.elementOverrides = { title: { text: { size: 1.6, color: "#111111" } } }
    const baseEl = root.snapshotStyle()
    root.elementOverrides = {}
    const appliedEl = root.snapshotStyle()
    root.elementOverrides = { title: { text: { color: "#222222" } } }   // one property of yours since
    root.takeBackStyle(root.checkedSnapshot(baseEl), root.checkedSnapshot(appliedEl))
    assert.deepEqual(root.elementOverrides, { title: { text: { size: 1.6, color: "#222222" } } }, "the size back, your color since stays")
    root.elementOverrides = {}
    root.takeBackStyle(root.checkedSnapshot(baseEl), root.checkedSnapshot(appliedEl))
    assert.deepEqual(root.elementOverrides, { title: { text: { size: 1.6, color: "#111111" } } }, "untouched since: all of it back")
    root.elementOverrides = { title: { text: { size: 2 } } }
    const baseEl2 = root.snapshotStyle()
    root.elementOverrides = { title: { text: { size: 1.6, color: "#111111" } }, clock: { text: { color: "#333333" } } }
    const appliedEl2 = root.snapshotStyle()
    root.elementOverrides = { clock: { text: { color: "#333333" } } }   // you took the title's off since
    root.takeBackStyle(root.checkedSnapshot(baseEl2), root.checkedSnapshot(appliedEl2))
    assert.deepEqual(root.elementOverrides, {}, "what you took off since stays off; what's still as applied goes back")
    root.elementOverrides = {}
    // a Home picture picked since, still being copied, isn't cancelled by it
    root.homeBackground = { mode: "focus", image: "", dim: 0.6 }
    const seq = root.homePickSeq
    root.takeBackStyle(root.checkedSnapshot(base), root.checkedSnapshot(applied))
    assert.equal(root.homePickSeq, seq, "no newer choice than a pick on its way: it still lands")
    root.colorOverrides = {}
    root.layoutOverrides = {}
    root.colorSlots = []
    root.themeId = "retro"
    root.bgMode = "none"; root.bgImage = ""; root.bgFrom = ""; root.bgDim = 0.6
    root.ltShow = true; root.ltSeconds = 4; root.cardShow = true; root.cardSeconds = 1.4
    root.homeBackground = { mode: "focus", image: "", dim: 0.6 }
  }
  // checking the look kept for undo twice changes nothing (Home's picture
  // and Multiview's background included: it's checked when settings load,
  // and again when undo uses it)
  {
    const homeCopy = "/home/u/.config/om-pg/app-pictures/" + "d".repeat(32) + ".png"
    const realOk = root.homePictureOk
    root.homePictureOk = p => p === homeCopy
    root.homeBgModes = ["focus", "details", "image", "none"]
    const once = root.checkedSnapshot({ theme: "t", home: { background: { mode: "image", image: homeCopy, dim: 0.4 } }, background: { mode: "none" },
                                        multiview: { background: { mode: "color", color: "#1E2A3B", dim: 0.3 } } })
    const twice = root.checkedSnapshot(once)
    assert.deepEqual(twice.homeBackground, { mode: "image", image: homeCopy, dim: 0.4 }, "the checked shape, checked again, is the same")
    assert.deepEqual(twice.multiviewBackground, { mode: "color", image: "", color: "#1e2a3b", dim: 0.3 }, "Multiview's color, checked again, kept")
    assert.deepEqual(twice, once)
    assert.equal(root.checkedSnapshot({ multiview: { background: { mode: "color", color: "red" } } }).multiviewBackground.mode, "none", "a color that isn't #rrggbb: as it is")
    assert.equal(root.checkedSnapshot({ multiview: { background: { mode: "color", color: "#11223344" } } }).multiviewBackground.mode, "none", "see-through isn't a background")
    root.homePictureOk = realOk
  }
  // a theme saved from the look: yours that went into it, and are still as saved, come off once it's on
  // (its pictures are copies in its folder now, so a byte-for-byte match can't be what decides)
  {
    const saveThemeFiles = new Function("root", "themesItem", "appScreensItem", "AppLooks", "appPanelItem", "id", "theme", "what", "baked", block(guideSrc, "function saveThemeFiles(id, theme, what, baked) {"))
    const run = (edits, trim) => {
      let pending = null
      const store = { save: (id, onDisk, what, committed) => { pending = committed; return { ok: true, token: "w-x-1" } } }
      const changes = []
      const screens = { now: { all: { size: "large", look: "wall", background: { mode: "image", image: "/cfg/app-pictures/" + "a".repeat(32) + ".png", dim: 0.4 } } },
                        change(key, fn, from, what) { const st = { all: JSON.parse(JSON.stringify(screens.now.all)) }; fn(st); screens.now = { all: st.all }; changes.push(what); return { ok: true, token: "w-x-2" } },
                        whenDone(token, f) { f("saved") } }
      const sroot = { themesDir: "/cfg/themes", themes: [], applied: [], saves: 0,
                      imageOverrides: { masthead: { src: "/home/u/logo.png", fit: "fit", opacity: 1 }, header: { src: "/home/u/bar.png", fit: "fill", opacity: 0.8 }, band: { src: "" } },
                      themeOnDisk: t => t, checkTheme: t => ({ theme: t }), applyTheme(id) { sroot.applied.push(id) }, saveSettings() { sroot.saves++ } }
      const baked = { images: JSON.parse(JSON.stringify(sroot.imageOverrides)), all: JSON.parse(JSON.stringify(screens.now.all)) }
      saveThemeFiles(sroot, store, screens, AL, appPanelItem, "mine", {}, "theme mine", baked)
      edits(sroot, screens)                              // what you change while it's being saved
      let doneWhy = null
      const theme = { name: "Mine", images: { masthead: { src: "pic-0000000000000001.png" }, header: { src: "pic-0000000000000002.png" } },
                      apps: { size: "large", look: "wall", background: { mode: "image", image: "pic-0000000000000003.png", dim: 0.4 } } }
      if (trim) trim(theme)                              // what the saved theme came back without
      pending("saved", { theme, old: [] }, why => { doneWhy = why })
      return { sroot, screens, doneWhy }
    }
    appPanelItem.dropped = []
    let r = run(() => {})
    assert.deepEqual(appPanelItem.dropped, ["all"], "its background for all apps dropped: a picture on its way for them doesn't land")
    assert.deepEqual(r.sroot.applied, ["mine"], "put on once saved")
    assert.deepEqual(r.sroot.imageOverrides, {}, "your area pictures it now holds come off, and so does your none where it has none")
    assert.deepEqual(r.screens.now.all, {}, "and so do your values for all apps it now gives, its background picture included")
    assert.equal(r.doneWhy, "")
    r = run((sroot, screens) => { sroot.imageOverrides.header = { src: "/home/u/new-bar.png", fit: "fill", opacity: 0.8 }; screens.now.all.size = "small" })
    assert.deepEqual(Object.keys(r.sroot.imageOverrides), ["header"], "one you changed meanwhile stays yours")
    assert.deepEqual(r.screens.now.all, { size: "small" }, "as does a value for all apps you changed meanwhile")
    r = run(() => {}, theme => { delete theme.images.header; delete theme.apps.background })
    assert.deepEqual(Object.keys(r.sroot.imageOverrides), ["header"], "a picture the saved theme came back without stays yours")
    assert.deepEqual(Object.keys(r.screens.now.all), ["background"], "as does a value for all apps it doesn't give")
    r = run(() => {}, theme => { theme.images.band = { src: "pic-0000000000000004.png" } })
    assert.deepEqual(Object.keys(r.sroot.imageOverrides), ["band"], "your none stays where the saved theme has a picture (it still hides it)")
  }
  // the pictures the pruner keeps: every choice's, Home's, and what the look kept for undo needs (either shape)
  {
    const prune = new Function("root", "appScreensItem", "pictureImporter", "appsStore", "Qt", block(guideSrc, "function prunePictures() {"))
    const pics = c => "/home/u/.config/om-pg/app-pictures/" + c.repeat(32) + ".png"
    let started = null
    const importer = { createObject: () => ({ finished: { connect() {} }, start: (argv, input) => { started = { argv, input: JSON.parse(input) } } }) }
    const proot = { picturesPruned: false, settingsLoaded: true, configDir: "/home/u/.config/om-pg", homeBackground: { mode: "image", image: pics("a") },
                    beforeReset: { homeBackground: { mode: "image", image: pics("b") }, home: { background: { image: pics("c") } }, appsAll: { background: { mode: "image", image: pics("d") } } } }
    const store = { loaded: true, now: { all: { background: { image: pics("e") } }, apps: { k: { background: { image: pics("f") } } } }, disk: { all: {}, apps: {} } }
    prune(proot, store, importer, { helper: "/x/om-pg-apps" }, { callLater: f => f() })
    assert.deepEqual(started.argv.slice(-1), ["picture-prune"])
    assert.deepEqual(started.input.keep.sort(), ["a", "b", "c", "d", "e", "f"].map(c => c.repeat(32) + ".png"), "every picture still named, the undo's Home one included")
  }
  // settings.json: the version before's (no "from") is floored; yours and the theme's as kept
  for (const [given, from, isFloored] of [[undefined, "", true], ["user", "user", false], ["theme", "theme", true], ["odd", "", true]]) {
    loadBackground(root, L, { background: { mode: "image", image: "/home/u/kept.jpg", dim: 0.1, from: given } })
    assert.deepEqual(now(), { mode: "image", image: "/home/u/kept.jpg", from: from }, String(given))
    assert.equal(floored(), isFloored, String(given))
  }
  // the background command: a picture given is yours; the wallpaper goes as set
  const g = { get bgMode() { return root.bgMode }, set bgMode(v) { root.bgMode = v }, get bgImage() { return root.bgImage }, set bgImage(v) { root.bgImage = v },
              get bgFrom() { return root.bgFrom }, set bgFrom(v) { root.bgFrom = v }, set bgDim(v) { root.bgDim = v }, saveSettings() {} }
  const cmds = { okReply: x => x, failReply: e => ({ error: e }), styleState: () => ({ background: {} }) }
  root.applyTheme("t")
  backgroundCommand(g, cmds, { env: () => "/home/u" }, "~/Pictures/c.png", "")
  assert.deepEqual(now(), { mode: "image", image: "/home/u/Pictures/c.png", from: "user" })
  assert.equal(floored(), false)
  backgroundCommand(g, cmds, { env: () => "/home/u" }, "wallpaper", "")
  assert.equal(floored(), false)
  // Guide.qml and Commands.qml load only in the shell: a root object with a
  // handler or property given twice ("Property value set multiple times")
  // would keep the whole guide from loading, so that's checked here
  for (const [name, text] of [["Guide.qml", guideSrc], ["Commands.qml", commandsSrc]]) {
    const seen = {}
    text.split("\n").forEach((line, i) => {
      const m = /^  (?:(?:readonly )?property \S+ (\w+)|(on[A-Z]\w*):)/.exec(line)
      if (!m) return
      const key = m[1] || m[2]
      assert.ok(!seen[key], name + ":" + (i + 1) + " gives " + key + " again (first at " + seen[key] + ")")
      seen[key] = i + 1
    })
  }
  // a theme read from its folder names pictures only there; one given to be
  // saved may give full paths (the helper copies them in): the real checkTheme
  assert.equal(L.themePicture("bg.png", true), "bg.png")
  assert.equal(L.themePicture("/tmp/not-in-theme.png", true), "", "read from disk: no outside path")
  assert.equal(L.themePicture("/home/u/Pictures/p.jpg", false), "/home/u/Pictures/p.jpg", "to be saved: a full path")
  for (const bad of ["../x.png", "sub/x.png", ".hidden.png", "x.gif", "", null, 3]) assert.equal(L.themePicture(bad, true), "", String(bad))
  const checkTheme = fn(guideSrc, "checkTheme", ["given", "id", "builtIn", "dir", "fromDisk"])
  const realImageSlotOf = fn(guideSrc, "imageSlotOf", ["key"])
  const realCheckedImage = fn(guideSrc, "checkedImage", ["spec", "key", "allowNames"])
  const troot = { colorSlots: [], colorKeys: [], installedFonts: [], homeBgModes: ["focus", "details", "image", "none"],
                  imageSlots: [{ key: "masthead", fit: "fit", opacity: 1 }], imageFits: ["fill", "fit"], isHex: v => /^#[0-9a-f]{6}$/i.test(v) }
  troot.clamp = (...a) => real.clamp(troot, L, null, null, null, null, null, null, themesItem, appScreensItem, AL, appPanelItem, ...a)
  troot.imageSlotOf = k => realImageSlotOf(troot, L, null, null, null, null, null, null, themesItem, appScreensItem, AL, appPanelItem, k)
  troot.checkedImage = (sp, k, an) => realCheckedImage(troot, L, null, null, null, null, null, null, themesItem, appScreensItem, AL, appPanelItem, sp, k, an)
  troot.slotOf = () => null
  const outside = "/tmp/not-in-theme.png"
  const given = { name: "T", colors: { text: "#ffffff" }, background: { mode: "image", image: outside, dim: 0.3 },
                  images: { masthead: { src: outside, fit: "fit", opacity: 1 } }, home: { background: { mode: "image", image: outside } },
                  apps: { look: "wall", background: { mode: "image", image: outside, dim: 0.4 } } }
  const fromDisk = checkTheme(troot, L, null, null, null, null, null, null, themesItem, appScreensItem, AL, appPanelItem, given, "t", false, "/home/u/.config/om-pg/themes/t", true)
  assert.equal(fromDisk.theme.background.image, undefined, "a theme on disk: no outside background")
  assert.deepEqual(fromDisk.theme.images, {}, "nor area picture")
  assert.equal((fromDisk.theme.home || { background: {} }).background.image, undefined, "nor Home's")
  assert.ok(!fromDisk.theme.apps || !fromDisk.theme.apps.background, "nor an app screen's")
  assert.ok(fromDisk.ignored.some(x => x.indexOf("a picture in the theme's folder") >= 0), JSON.stringify(fromDisk.ignored))
  const inFolder = JSON.parse(JSON.stringify(given).split(outside).join("pic-0123456789abcdef.png"))
  const ok = checkTheme(troot, L, null, null, null, null, null, null, themesItem, appScreensItem, AL, appPanelItem, inFolder, "t", false, "/home/u/.config/om-pg/themes/t", true)
  assert.equal(ok.theme.background.image, "pic-0123456789abcdef.png", "a name in its folder is fine")
  assert.equal(ok.theme.images.masthead.src, "pic-0123456789abcdef.png")
  assert.equal(ok.theme.apps.background.image, "/home/u/.config/om-pg/themes/t/pic-0123456789abcdef.png", "an app screen's, resolved in its folder")
  const flat = checkTheme(troot, L, null, null, null, null, null, null, themesItem, appScreensItem, AL, appPanelItem, inFolder, "t", false, "", true)
  assert.equal(flat.theme.background.image, undefined, "a single-file theme (no folder) names no picture")
  const toSave = checkTheme(troot, L, null, null, null, null, null, null, themesItem, appScreensItem, AL, appPanelItem, given, "t", false, "/home/u/.config/om-pg/themes/t", false)
  assert.equal(toSave.theme.background.image, outside, "to be saved: a full path (the helper checks it and copies it in)")
  assert.equal(toSave.theme.apps.background.image, outside)
  // Multiview's background in a theme: a color is #rrggbb, and the color mode needs one
  troot.mvBgModes = ["none", "color", "theme", "wallpaper", "image"]
  troot.solidHex = v => typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v)
  const mvTheme = mv => checkTheme(troot, L, null, null, null, null, null, null, themesItem, appScreensItem, AL, appPanelItem,
                                   { name: "T", colors: {}, multiview: { background: mv } }, "t", false, "/home/u/.config/om-pg/themes/t", false)
  const mvOk = mvTheme({ mode: "color", color: "#ABCDEF", dim: 0.2 })
  assert.deepEqual(mvOk.theme.multiview, { background: { mode: "color", color: "#abcdef", dim: 0.2 } })
  assert.ok(!mvOk.ignored.includes("multiview"), JSON.stringify(mvOk.ignored))
  const mvBad = mvTheme({ mode: "color", color: "blue" })
  assert.deepEqual(mvBad.theme.multiview, { background: {} }, "no color: no color mode, the user's kept")
  assert.ok(mvBad.ignored.some(x => x.indexOf("multiview.background.color") >= 0), JSON.stringify(mvBad.ignored))
  assert.ok(!mvBad.ignored.includes("multiview"), JSON.stringify(mvBad.ignored))
  assert.match(guideSrc, /root\.checkTheme\(JSON\.parse\(chunks\[i\]\.slice\(nl \+ 1\)\), id, builtIn, dir, true\)/, "themesRead checks what it reads as from disk")
  assert.match(guideSrc, /root\.checkTheme\(res\.theme, id, false, root\.themesDir \+ "\/" \+ id, true\)/, "and the saved theme the helper gives back")
  // Home shows only the guide's copy of a picture (or a theme's own); a pick
  // is checked and copied first, and only the latest lands
  {
    const cfg = "/home/u/.config/om-pg"
    const copy = cfg + "/app-pictures/" + "a".repeat(32) + ".png"
    const screensWithPics = { pictureOk: p => typeof p === "string" && p.indexOf(cfg + "/app-pictures/") === 0 && /^[0-9a-f]{32}\.(png|jpg|webp)$/.test(p.slice(cfg.length + 14)) }
    const hroot = { themesDir: cfg + "/themes", pluginDir: "/plugin", homePickSeq: 0, homePictureNote: "", imports: [], sets: [],
                    homeBackground: { mode: "focus", image: "", dim: 0.6 }, homeBgModes: ["focus", "details", "image", "none"], homeEnabled: true,
                    homeTileKinds: [], defaultHomeSections: [], checkedHomeSections: () => null }
    const hfn = (name, params) => { const f = fn(guideSrc, name, params); return (...a) => f(hroot, L, null, null, null, null, null, null, themesItem, screensWithPics, AL, appPanelItem, ...a) }
    hroot.homePictureOk = hfn("homePictureOk", ["p"])
    hroot.homePicture = hfn("homePicture", ["path", "mode", "done"])
    hroot.importPicture = (path, done) => hroot.imports.push({ path, done })
    hroot.saveSettings = () => {}
    hroot.setHomeBackground = hfn("setHomeBackground", ["changes", "landing"])
    hroot.replaceHomeBackground = hfn("replaceHomeBackground", ["b"])
    hroot.clamp = (v, lo, hi, o) => isNaN(v) ? o : Math.max(lo, Math.min(hi, v))
    assert.equal(hroot.homePictureOk(copy), true, "the guide's own copy")
    assert.equal(hroot.homePictureOk(cfg + "/themes/aperture/background.png"), true, "a theme's own picture")
    assert.equal(hroot.homePictureOk("/plugin/themes/retro/pic-0123456789abcdef.jpg"), true)
    for (const bad of ["/tmp/not-an-image.png", "/home/u/Pictures/p.png", cfg + "/themes/aperture/../../x.png", cfg + "/themes/a/b/c.png", cfg + "/app-pictures/x.png", ""])
      assert.equal(hroot.homePictureOk(bad), false, bad)
    // two picks: the older finishing last never lands
    hroot.homePicture("/home/u/one.png", "image")
    hroot.homePicture("/home/u/two.png", "image")
    hroot.imports[1].done({ ok: true, path: cfg + "/app-pictures/" + "b".repeat(32) + ".png" })
    hroot.imports[0].done({ ok: true, path: cfg + "/app-pictures/" + "c".repeat(32) + ".png" })
    assert.equal(hroot.homeBackground.image, cfg + "/app-pictures/" + "b".repeat(32) + ".png", "only the latest pick lands")
    assert.equal(hroot.homeBackground.mode, "image")
    hroot.homePicture("/tmp/not-an-image.png", "image")
    hroot.imports[2].done({ ok: false, error: "a picture isn't a PNG, JPEG or WebP" })
    assert.equal(hroot.homePictureNote, "Not used: a picture isn't a PNG, JPEG or WebP.", "a refusal says why")
    // a later choice for Home's background, from anywhere, wins over a pick
    // still being copied; the darkness alone doesn't (it lands with it)
    const wall = cfg + "/app-pictures/" + "d".repeat(32) + ".png"
    for (const [what, later] of [["the mode row (or a command)", () => hroot.setHomeBackground({ mode: "none" })],
                                 ["a theme, a reset or undo", () => hroot.replaceHomeBackground({ mode: "focus", image: "", dim: 0.6 })]]) {
      hroot.imports = []
      hroot.homeBackground = { mode: "focus", image: "", dim: 0.6 }
      hroot.homePicture("/home/u/late.png", "image")
      later()
      const was = JSON.stringify(hroot.homeBackground)
      hroot.imports[0].done({ ok: true, path: wall })
      assert.equal(JSON.stringify(hroot.homeBackground), was, what + ": the late picture doesn't land")
    }
    hroot.imports = []
    hroot.homePicture("/home/u/late.png", "image")
    hroot.setHomeBackground({ dim: 0.35 })
    hroot.imports[0].done({ ok: true, path: wall })
    assert.deepEqual(hroot.homeBackground, { mode: "image", image: wall, dim: 0.35 }, "darker meanwhile: the picture, with the newer darkness")
    // settings: a copy is shown; a path from before isn't, and is checked and copied first
    const loadHome = new Function("root", "Look", "Qt", "saved", block(guideSrc, 'if (saved.home && typeof saved.home === "object") {'))
    const later = []
    hroot.imports = []
    loadHome(hroot, L, { callLater: f => later.push(f) }, { home: { background: { mode: "image", image: copy, dim: 0.5 } } })
    assert.deepEqual(hroot.homeBackground, { mode: "image", image: copy, dim: 0.5 }, "a copy, shown")
    loadHome(hroot, L, { callLater: f => later.push(f) }, { home: { background: { mode: "image", image: "/tmp/not-an-image.png", dim: 0.5 } } })
    assert.equal(hroot.homeBackground.image, "", "a path from before (hand-edited, or older): never shown as it is")
    assert.equal(hroot.homeBackground.mode, "focus")
    later.forEach(f => f())
    assert.equal(hroot.imports[0].path, "/tmp/not-an-image.png", "it goes through the helper's checks")
    hroot.imports[0].done({ ok: true, path: copy })
    assert.deepEqual([hroot.homeBackground.mode, hroot.homeBackground.image], ["image", copy], "and its copy is shown once it's in")
    // the setHome command: a picture goes through the helper too
    const setHome = new Function("guide", "commands", "json", block(commandsSrc, "function setHome(json: string): string {"))
    hroot.imports = []
    const replied = setHome(Object.assign(hroot, { homeSections: [], homeTiles: [], saveSettings() {} }), { okReply: x => x, failReply: e => ({ error: e }) },
                            JSON.stringify({ background: { mode: "image", image: "/home/u/Pictures/p.png", dim: 0.3 } }))
    assert.equal(hroot.imports.length, 1, "the command's picture is checked and copied first")
    assert.notEqual(hroot.homeBackground.image, "/home/u/Pictures/p.png", "never shown as given")
    assert.ok(replied.note && replied.note.indexOf("checked and copied first") >= 0, JSON.stringify(replied))
  }
  // settings are saved only once they've been read, and never over a file that couldn't be
  const saveSettings = new Function("root", "settings", "listings", "videos", "screenSaverItem", "updatesItem", "dvr", block(guideSrc, "function saveSettings() {"))
  let writes = 0
  const settingsFile = { setText() { writes++ } }
  const stand = flags => new Proxy(Object.assign({ pipW: 0, pipRight: 24, pipBottom: 24 }, flags), { get: (t, k) => (k in t ? t[k] : undefined) })
  saveSettings(stand({ settingsLoaded: false, settingsProblem: "" }), settingsFile, { sources: [] }, {}, { settings: {} }, { on: false, asked: false }, { settings: {} })
  assert.equal(writes, 0, "not before the file's been read: the defaults would go over yours")
  saveSettings(stand({ settingsLoaded: true, settingsProblem: "Your settings file wasn't read (it's bigger than 1024 KB)" }), settingsFile, { sources: [] }, {}, { settings: {} }, { on: false, asked: false }, { settings: {} })
  assert.equal(writes, 0, "never over a file that couldn't be read")
  saveSettings(stand({ settingsLoaded: true, settingsProblem: "" }), settingsFile, { sources: [] }, {}, { settings: {} }, { on: false, asked: false }, { settings: {} })
  assert.equal(writes, 1, "once read, saved")
  // and the exact assignments, where the run above can't reach (the helper's three, in both its users)
  for (const name of ["putThemeBackground", "applyTheme"]) {
    const body = block(guideSrc, "function " + name + "(")
    for (const line of ["root.bgImage = bg.image", "root.bgFrom = bg.from", "root.bgMode = bg.mode"]) assert.ok(body.includes(line), name + ": " + line)
  }
  assert.ok(!/"theme"\s*\?\s*"theme"\s*:\s*"user"/.test(guideSrc), "nothing reads a missing from as yours")
  assert.match(guideSrc, /\n  property string bgFrom: ""\n/)
  assert.match(guideSrc, /readonly property bool bgFloored: Look\.bgFloored\(bgMode, bgImage, bgFrom\)/)
  assert.match(guideSrc, /\n    run: appsStore\.randomHex\(32\)\n/, "a snapshot run of 128 bits each start")
  assert.ok(block(guideSrc, "function saveLookAsTheme(").includes('if (root.lookSaving) return { ok: false'), "no save as a theme while a reset is being saved")

  // the phone is you too: any of your phone's commands ends an agent's open
  // of an app before it does anything else; another caller's doesn't
  {
    const remoteCommand = new Function("root", "appViewItem", "nativeSaverItem", "screenSaverItem", "Hyprland", "channelLockItem", "cmd", "number", "by", block(guideSrc, "function remoteCommand(cmd, number, by, digits, extra) {"))
    const you = {}
    const run = by => {
      let ended = 0
      const view = { agentOpen: { guard() {} }, userActs() { ended++; view.agentOpen = null } }
      const stop = new Proxy({ byUser: you }, { get: (t, k) => { if (k in t) return t[k]; throw new Error("stop") } })
      const idle = { up: false, settling: false, showing: false, activity() {}, wake() {} }
      try { remoteCommand(stop, view, idle, idle, { usingLua: false }, { boxUp: false }, "options", 0, by) } catch (e) { if (e.message !== "stop") throw e }
      return ended
    }
    assert.equal(run(you), 1, "your phone's command ends it first")
    assert.equal(run({}), 0, "another caller's doesn't")
    // a press on your phone counts as you being here: Hyprland's idle timers
    // start over, and the screen saver wakes (that press does nothing else);
    // while Omarchy's own screen saver is up, it does nothing at all
    const phone = (native, showing) => {
      const seen = { dispatched: [], woke: 0, activity: 0 }
      const saver = { showing, settling: false, activity() { seen.activity++ }, wake() { seen.woke++ } }
      const hypr = { usingLua: true, dispatch(d) { seen.dispatched.push(d) } }
      const stop = new Proxy({ byUser: you }, { get: (t, k) => { if (k in t) return t[k]; throw new Error("stop") } })
      try { seen.answer = remoteCommand(stop, { agentOpen: null }, { up: native, settling: false }, saver, hypr, { boxUp: false }, "down", 0, you) } catch (e) { if (e.message !== "stop") throw e }
      return seen
    }
    let p = phone(false, true)
    assert.deepEqual([p.dispatched, p.woke, p.answer], [["hl.dsp.force_idle(0)"], 1, "woke the screen saver"], "the screen saver showing: it wakes, and the press stops there")
    p = phone(false, false)
    assert.deepEqual([p.dispatched, p.activity, p.answer], [["hl.dsp.force_idle(0)"], 1, undefined], "otherwise its wait starts over, and the press goes on to the guide")
    p = phone(true, false)
    assert.deepEqual([p.dispatched, p.woke, p.activity], [[], 0, 0], "Omarchy's screen saver up: nothing (a key closes it; the lock still comes)")
  }
  // the channel lock: closing Uber TV or the box abandons its session, a
  // blocked channel never tunes, and the channel on is checked again when
  // the lock changes (tests/qml/tst_channellock.qml has the session itself)
  assert.ok(block(guideSrc, "function closeNow() {").includes("channelLockItem.abandon()"), "closing Uber TV abandons the lock's box")
  assert.ok(block(guideSrc, "function closeDialog() {").includes("channelLockItem.abandon()"), "closing the box abandons it")
  assert.ok(block(guideSrc, "function tune(r, at, retrying) {").includes('if (channelLockItem.blocks(root.channels[r])) return "locked"'), "tune refuses a blocked channel")
  assert.match(guideSrc, /onRecheck: root\.enforceLock\(\)/, "the lock asks the guide to check the channel on")
  assert.ok(block(guideSrc, "function enforceLock() {").includes("root.turnOff()"), "a channel blocked now stops")

  // a locked channel's shows: one Locked block, or their titles without
  // pictures or descriptions if titles may show; an unlocked one's as they are
  {
    const lockedShows = new Function("root", "channelLockItem", "ch", "shows", "from", "to", block(guideSrc, "function lockedShows(ch, shows, from, to) {"))
    const shows = [{ id: "v1", title: "Painting", desc: "happy trees", start: 100, end: 200 }, { id: "v2", title: "More", desc: "d", start: 200, end: 300 }]
    const lockOf = (blocks, titles) => ({ blocks: () => blocks, titles })
    assert.deepEqual(lockedShows({}, lockOf(false, false), {}, shows, 0, 999), shows, "not locked (or unlocked): as they are")
    assert.deepEqual(lockedShows({}, lockOf(true, false), {}, shows, 0, 999), [{ locked: true, live: false, id: "", title: "Locked", start: 0, end: 999 }],
      "locked, titles hidden: one Locked block over the whole span, nothing of theirs")
    assert.deepEqual(lockedShows({}, lockOf(true, true), {}, shows, 0, 999).map(s => [s.title, s.id, s.desc]), [["Painting", "", ""], ["More", "", ""]],
      "locked, titles shown: titles only, no pictures (id) or descriptions")
    for (const name of ["function showsFor(r) {", "function lineupFrom(r, t, n) {"]) assert.ok(block(guideSrc, name).includes("root.lockedShows("), name + " goes through the lock")
    assert.ok(block(guideSrc, "function nextShow(r, s) {").includes("root.titlesHidden(ch)"), "the next show too")
    assert.ok(block(guideSrc, "function logoFor(ch) {").includes("channelLockItem.blocks(ch)"), "no logo for a locked channel")
    assert.ok(block(guideSrc, "function channelCard(r, show, starting) {").includes("!channelLockItem.blocks(ch) ? ch.logo"), "nor a poster")
    assert.match(guideSrc, /if \(root\.titlesHidden\(ch\)\) continue   \/\/ a locked channel's shows aren't found by their titles/, "Search doesn't find them by title")
    assert.match(guideSrc, /title: root\.titlesHidden\(c\) \? "Locked" : root\.showTitle\(title\)/, "nor does the phone's guide show them")
    // a locked channel's videos (On Demand) are locked with it: by every
    // channel a video is on (one upload can be on several, in any order),
    // and by the channels' addresses kept with what you watched or saved, so
    // a renamed or removed channel still locks its older videos (an older
    // record kept without them: by its channel's name, every one of that name)
    const librarySrc = readFileSync(new URL("../Library.qml", import.meta.url), "utf8")
    const LR = new Function(readFileSync(new URL("../ChannelLock.js", import.meta.url), "utf8").replace(".pragma library", "") +
      "; return { index, blocks, byAddress, videoChannels }")()
    const ownerOf = new Function("channels", block(guideSrc, "readonly property var videoOwner: {"))
    const fns = {
      videoRows: ["videoId"], videoOwners: ["videoId", "kept"], videoLockedBy: ["videoId", "name", "owners", "more"], videoEntry: ["ch", "video"],
      entryFor: ["id"], fillVideoOwners: [], videoCardFrom: ["id", "title", "channelName", "videoId", "duration"],
    }
    const sig = { videoRows: "function videoRows(videoId) {", videoOwners: "function videoOwners(videoId, kept) {", videoLockedBy: "function videoLockedBy(videoId, name, owners, more) {",
                  videoEntry: "function videoEntry(ch, video) {", entryFor: "function entryFor(id) {", fillVideoOwners: "function fillVideoOwners() {",
                  videoCardFrom: "function videoCardFrom(id, title, channelName, videoId, duration) {" }
    const libFns = { owners: ["kept", "more", "wasMore"], fillOwners: ["ownersOf"], record: ["entry", "position", "duration"] }
    const libSig = { owners: "function owners(kept, more, wasMore) {", fillOwners: "function fillOwners(ownersOf) {", record: "function record(entry, position, duration) {" }
    // a stand-in guide: channels, the lock (entries; the lock on, unlocked by
    // address), and the library's history
    const tv = (channels, entries, history, unlocked = {}) => {
      const lock = { entries, loaded: true, blocks: ch => !!ch && LR.blocks(true, LR.index(entries, channels), unlocked, ch, 1000) }
      const library = { history: history || {}, historyLoaded: true, maxHistory: 400, maxOwners: 100, item: () => null, saved: 0 }
      const historySaver = { restart: () => library.saved++ }
      const root = { channels, videoOwner: ownerOf(channels), videoChannelsByUrl: LR.byAddress(channels) }
      for (const f in libFns) { const run = new Function("library", "historySaver", "guide", ...libFns[f], block(librarySrc, libSig[f])); library[f] = (...a) => run(library, historySaver, root, ...a) }
      const videos = { enabled: false }
      for (const f in fns) { const run = new Function("root", "channelLockItem", "library", "LockRules", "videos", ...fns[f], block(guideSrc, sig[f])); root[f] = (...a) => run(root, lock, library, LR, videos, ...a) }
      root.movieEntry = () => null
      return { root, lock, library }
    }
    const V = "DY81aE0tvMk", V2 = "abcdefghijk"
    const creator = () => ({ kind: "youtube", name: "Bob Ross", url: "https://www.youtube.com/@bobross", items: [{ id: V, title: "Happy trees", duration: 60 }] })
    const playlist = () => ({ kind: "youtube", name: "Open playlist", url: "https://www.youtube.com/playlist?list=PL1", items: [{ id: V, title: "Happy trees", duration: 60 }, { id: V2, title: "Other", duration: 30 }] })
    const news = { kind: "iptv", name: "Bob Ross", url: "https://iptv/1" }
    const lockA = [{ url: "https://www.youtube.com/@bobross", name: "Bob Ross" }]
    for (const order of ["locked first", "open first"]) {
      const a = creator(), b = playlist()
      const t = tv(order === "locked first" ? [a, b, news] : [news, b, a], lockA)
      assert.equal(t.root.videoLockedBy("yt:" + V, ""), a, "a video on a locked channel and an open playlist is locked (" + order + ")")
      assert.equal(t.root.videoLockedBy(V, "Open playlist"), a, "with or without yt:, whatever the name says (" + order + ")")
      assert.equal(t.root.videoLockedBy("yt:" + V2, ""), null, "the open playlist's own video isn't (" + order + ")")
      const e = t.root.entryFor("yt:" + V)
      assert.deepEqual(e.owners.slice().sort(), [a.url, b.url].sort(), "its entry has every channel it's on (" + order + ")")
      assert.equal(t.root.videoLockedBy(e.videoId, e.subtitle), a, "so playing it from its entry asks (" + order + ")")
      // playing it asks for the passcode, for the locked one; agents' play refuses it
      const asked = []
      const playVod = new Function("root", "channelLockItem", "library", "entry", "from", block(guideSrc, "function playVod(entry, from) {"))
      const proot = Object.assign({}, t.root, { opened: true, summonGuide() {} })
      assert.equal(playVod(proot, { askUnlock: ch => asked.push(ch) }, t.library, e), "the passcode first", "playVod asks (" + order + ")")
      assert.deepEqual(asked, [a], "for the locked channel (" + order + ")")
      const play = new Function("guide", "commands", "playSoon", "id", block(commandsSrc, "function play(id: string): string {"))
      const said = play(t.root, { failReply: m => "no: " + m, okReply: () => "played" }, { restart() {} }, "yt:" + V)
      assert.match(said, /^no: that video is from a locked channel/, "agents' play refuses it (" + order + ")")
      // unlocked: it plays
      const u = tv(order === "locked first" ? [a, b, news] : [news, b, a], lockA, {}, { [a.url]: 0 })
      assert.equal(u.root.videoLockedBy("yt:" + V, ""), null, "unlocked, it isn't (" + order + ")")
    }
    {
      // watched, then aged out of its channel's list: the address kept with it
      const t = tv([creator(), playlist()], lockA)
      t.library.record(t.root.entryFor("yt:" + V), 100, 600)
      assert.deepEqual(t.library.history["yt:" + V].owners.slice().sort(), [creator().url, playlist().url].sort(), "what you watch keeps every channel it's on")
      const kept = { ["yt:" + V]: t.library.history["yt:" + V] }
      const renamed = Object.assign(creator(), { name: "New name", items: [] })
      let g = tv([renamed, Object.assign(playlist(), { items: [] }), news], lockA, kept)
      assert.equal(g.root.videoLockedBy("yt:" + V, "Bob Ross"), renamed, "renamed: still locked, by its address")
      const e = g.root.entryFor("yt:" + V)
      assert.deepEqual(e.owners.slice().sort(), [creator().url, playlist().url].sort(), "an aged-out video's entry has the kept addresses")
      assert.equal(g.root.videoLockedBy(e.videoId, e.subtitle), renamed, "and playing it asks")
      g = tv([Object.assign(playlist(), { items: [] }), news], lockA, kept)
      const gone = g.root.videoLockedBy("yt:" + V, "Bob Ross")
      assert.deepEqual(gone && [gone.url, gone.name], [creator().url, "Bob Ross"], "removed: still locked, by its lock entry (unlocking it unlocks that address)")
      g = tv([Object.assign(playlist(), { items: [] }), news], lockA, kept, { [creator().url]: 0 })
      assert.equal(g.root.videoLockedBy("yt:" + V, "Bob Ross"), null, "and once that's unlocked, it plays")
      g = tv([Object.assign(playlist(), { items: [] }), news], [], kept)
      assert.equal(g.root.videoLockedBy("yt:" + V, "Bob Ross"), null, "removed from the lock too: nothing locks it")
      // a name never counts once addresses are kept: an open channel's video
      // isn't locked by a locked channel of the same name
      const open = { kind: "youtube", name: "Bob Ross", url: "https://www.youtube.com/@other", items: [] }
      g = tv([open, Object.assign(creator(), { items: [] })], lockA, { ["yt:" + V2]: { kind: "youtube", subtitle: "Bob Ross", ref: V2, owners: [open.url] } })
      assert.equal(g.root.videoLockedBy("yt:" + V2, "Bob Ross"), null, "kept addresses, not names")
      // the record keeps its addresses as more come, strings only
      t.library.record({ id: "yt:" + V, kind: "youtube", videoId: V, owners: ["https://x/1", 7, ""] }, 200, 600)
      assert.deepEqual(t.library.history["yt:" + V].owners.slice().sort(), [creator().url, playlist().url, "https://x/1"].sort(), "kept, and the new ones (no others)")
    }
    {
      // played from a card, as On Demand, Search, Home, Continue watching and
      // My List do: the card's entry has its channels, and so does what's
      // recorded, even from an entry that has none (the record works them out)
      const old = Object.assign(creator(), { name: "Old name" })
      const lockOld = [{ url: old.url, name: "Old name" }]
      const t = tv([Object.assign({}, old, { name: "New name" }), news], lockOld, {}, { [old.url]: 0 })   // renamed, unlocked for now
      const card = t.root.videoCardFrom("yt:" + V, "Happy trees", "New name", V, 60)
      assert.deepEqual(card.entry.owners, [old.url], "a card's entry has its channels")
      t.library.record(card.entry, 100, 600)
      assert.deepEqual(t.library.history["yt:" + V].owners, [old.url], "and what's recorded from it")
      t.library.record({ id: "yt:" + V2, kind: "youtube", title: "x", subtitle: "New name", videoId: V2 }, 100, 600)
      assert.deepEqual(t.library.history["yt:" + V2].owners, [], "a video on none of your channels: none")
      const t2 = tv([Object.assign({}, old, { name: "New name" })], lockOld, {}, { [old.url]: 0 })
      t2.library.record({ id: "yt:" + V, kind: "youtube", title: "x", subtitle: "New name", videoId: V }, 100, 600)
      assert.deepEqual(t2.library.history["yt:" + V].owners, [old.url], "an entry with none: the record works them out itself")
      const kept = { ["yt:" + V]: t.library.history["yt:" + V] }
      let g = tv([news], lockOld, kept)
      assert.equal(g.root.videoLockedBy("yt:" + V, "New name").url, old.url, "then removed (its lock entry still says Old name): locked")
      assert.equal(g.root.videoLockedBy("yt:" + V, "New name", card.entry.owners).url, old.url, "and so is the card made before")
      g = tv([Object.assign({}, old, { name: "Newer", items: [] }), news], lockOld, kept)
      assert.equal(g.root.videoLockedBy("yt:" + V, "New name").name, "Newer", "or aged out and renamed again: locked")
      // a card's owners count at playback even if nothing was kept
      g = tv([news], lockOld, {})
      assert.equal(g.root.videoLockedBy("yt:" + V, "New name", [old.url]).url, old.url, "the entry's owners count when playing")
      assert.equal(g.root.videoLockedBy("yt:" + V, "New name"), null, "(without them, nothing says where it's from)")
    }
    {
      // more channels than are kept: the record says so, and the video is
      // locked whenever any locked channel is blocked (it fails closed)
      const opens = Array.from({ length: 100 }, (_, i) => ({ kind: "youtube", name: "Open " + i, url: "https://www.youtube.com/playlist?list=O" + i, items: [{ id: V, title: "Happy trees" }] }))
      const t = tv(opens.concat([creator()]), lockA, {}, { [creator().url]: 0 })   // the creator 101st, unlocked for now
      t.library.record(t.root.videoCardFrom("yt:" + V, "Happy trees", "Open 0", V, 60).entry, 100, 600)
      const r = t.library.history["yt:" + V]
      assert.deepEqual([r.owners.length, r.owners.includes(creator().url), r.ownersMore], [100, false, true], "100 kept, the locked one past them, and it says more")
      const aged = opens.concat([Object.assign(creator(), { items: [] })])
      let g = tv(aged, lockA, { ["yt:" + V]: r })
      assert.equal(g.root.videoLockedBy("yt:" + V, "Open 0").url, creator().url, "aged out of the creator's list, locked again: still locked")
      g = tv(aged, lockA, { ["yt:" + V]: Object.assign({}, r, { ownersMore: false }) })
      assert.equal(g.root.videoLockedBy("yt:" + V, "Open 0"), null, "(without the mark it would play)")
      g = tv(aged, [], { ["yt:" + V]: r })
      assert.equal(g.root.videoLockedBy("yt:" + V, "Open 0"), null, "nothing locked: it plays")
      g = tv(aged, lockA, { ["yt:" + V]: r }, { [creator().url]: 0 })
      assert.equal(g.root.videoLockedBy("yt:" + V, "Open 0"), null, "every locked channel unlocked: it plays")
      // the mark goes with what's playing: started from Continue watching
      // while the creator's unlocked for an hour, then history cleared, then
      // the hour's up: it stops, and the next save marks it again
      const unlockedHour = tv(aged, lockA, { ["yt:" + V]: r }, { [creator().url]: 2000 })
      const playing = unlockedHour.root.videoCardFrom("yt:" + V, "Happy trees", "Open 0", V, 0).entry
      assert.deepEqual([playing.owners.length, playing.ownersMore], [100, true], "a card's entry has the mark")
      assert.equal(unlockedHour.root.entryFor("yt:" + V).ownersMore, true, "so does one by its id")
      const goneAll = tv([Object.assign(creator(), { items: [] }), news], lockA, { ["yt:" + V]: r }).root.entryFor("yt:" + V)
      assert.deepEqual([goneAll.owners.length, goneAll.ownersMore], [100, true], "and one off every channel's list, from history alone")
      assert.equal(unlockedHour.root.videoLockedBy(playing.videoId, playing.subtitle, playing.owners, playing.ownersMore), null, "unlocked: it plays")
      const cleared = tv(aged, lockA, {})   // history cleared, the hour's up
      let off = 0
      const enforceLock = new Function("root", "channelLockItem", block(guideSrc, "function enforceLock() {"))
      enforceLock(Object.assign({}, cleared.root, { vod: playing, turnOff: () => off++ }), cleared.lock)
      assert.equal(off, 1, "history cleared, then the unlock runs out: it stops")
      assert.equal(cleared.root.videoLockedBy(playing.videoId, playing.subtitle, playing.owners), null, "(without the entry's mark it would play)")
      cleared.library.record(playing, 200, 600)
      assert.deepEqual([cleared.library.history["yt:" + V].owners.length, cleared.library.history["yt:" + V].ownersMore], [100, true], "and the next save marks it again")
      assert.equal(tv(aged, lockA, {}).root.entryFor("yt:" + V).ownersMore, false, "(nothing kept, nothing marked)")
      const again = t.library.owners(r.owners, [], r.ownersMore)
      assert.deepEqual([again.owners.length, again.more], [100, true], "the mark stays")
      assert.deepEqual(t.library.owners(["a", "b"], ["b", "c"], false), { owners: ["a", "b", "c"], more: false }, "without repeats")
      // history.json read back: addresses checked, the mark kept, more than fit marked
      const load = new Function("library", "guide", "text", block(librarySrc.slice(librarySrc.indexOf("id: historyFile")), "onLoaded: {"))
      const lib = { owners: t.library.owners, maxOwners: 100 }
      load(lib, { isStreamUrl: () => false }, () => JSON.stringify({
        ["yt:" + V]: { kind: "youtube", owners: ["https://a", 7, "", "https://a", "https://b"] },
        ["yt:" + V2]: { kind: "youtube", owners: Array.from({ length: 150 }, (_, i) => "https://x/" + i) },
        "yt:zzzzzzzzzzz": { kind: "youtube", owners: "https://a", ownersMore: true } }))
      assert.deepEqual([lib.history["yt:" + V].owners, lib.history["yt:" + V].ownersMore], [["https://a", "https://b"], false], "read back: strings, no repeats")
      assert.deepEqual([lib.history["yt:" + V2].owners.length, lib.history["yt:" + V2].ownersMore], [100, true], "more than fit: marked")
      assert.deepEqual([lib.history["yt:zzzzzzzzzzz"].owners, lib.history["yt:zzzzzzzzzzz"].ownersMore], [[], true], "the mark read back")
    }
    {
      // older records, kept without addresses: by their channel's name, every
      // channel and lock entry of that name (both orders), until filled in
      const old = { ["yt:" + V2]: { kind: "youtube", subtitle: "Bob Ross", ref: V2, owners: [] } }
      const twin = { kind: "youtube", name: "Bob Ross", url: "https://www.youtube.com/@twin", items: [] }
      for (const chans of [[twin, Object.assign(creator(), { items: [] })], [Object.assign(creator(), { items: [] }), twin]]) {
        const g = tv(chans, lockA, JSON.parse(JSON.stringify(old)))
        assert.equal(g.root.videoLockedBy("yt:" + V2, "Bob Ross").url, creator().url, "a duplicate name: locked if any of that name is")
        g.root.fillVideoOwners()
        assert.deepEqual(g.library.history["yt:" + V2].owners.slice().sort(), [twin.url, creator().url].sort(), "filled in: every channel of that name")
        assert.equal(g.library.saved, 1, "and saved")
      }
      // filled in by its name while it's still found, then the channel's renamed: still locked
      let g = tv([Object.assign(creator(), { items: [] })], lockA, JSON.parse(JSON.stringify(old)))
      g.root.fillVideoOwners()
      const filled = g.library.history
      g = tv([Object.assign(creator(), { name: "New name", items: [] })], lockA, filled)
      assert.equal(g.root.videoLockedBy("yt:" + V2, "Bob Ross").name, "New name", "filled in, then renamed: still locked")
      // the channel already gone, its lock entry kept: filled in from the entry
      g = tv([news], lockA, JSON.parse(JSON.stringify(old)))
      g.root.fillVideoOwners()
      assert.deepEqual(g.library.history["yt:" + V2].owners, [creator().url], "filled in from the lock entry of that name")
      // not before the lock's been read, and not when nothing's found
      g = tv([news], lockA, JSON.parse(JSON.stringify(old)))
      g.lock.loaded = false
      g.root.fillVideoOwners()
      assert.deepEqual([g.library.history["yt:" + V2].owners, g.library.saved], [[], 0], "the lock not read yet: left for later")
      g = tv([news], [], JSON.parse(JSON.stringify(old)))
      g.root.fillVideoOwners()
      assert.deepEqual([g.library.history["yt:" + V2].owners, g.library.saved], [[], 0], "nothing of that name: left as it is")
      assert.equal(tv([news], lockA, {}).root.videoLockedBy("yt:zzzzzzzzzzz", "Someone"), null, "a video from none of your channels")
      assert.equal(tv([news], lockA, {}).root.videoLockedBy("not an id", ""), null)
      assert.deepEqual(tv([{ kind: "youtube", name: "x", url: "u", items: [{ id: "constructor" }] }], [], {}).root.videoRows("constructor"), [0], "an id that's a JavaScript word")
      assert.deepEqual(tv([news], [], {}).root.videoRows("constructor"), [])
    }
    assert.ok(block(librarySrc, "function unfinished(kind) {").includes("owners: h.owners"), "Continue watching carries them")
    assert.match(guideSrc, /onHistoryLoadedChanged: ownerFill\.restart\(\)/, "older records are filled in once history's read")
    assert.match(guideSrc, /onLoadedChanged: ownerFill\.restart\(\)/, "and the lock's")
    assert.match(guideSrc, /onVideoOwnerChanged: ownerFill\.restart\(\)/, "and when your channels' videos change")
    for (const [where, text] of [["function playVod(entry, from) {", "root.videoLockedBy(entry.videoId, entry.subtitle, entry.owners, entry.ownersMore)"],
                                 ["function enforceLock() {", "root.videoLockedBy(root.vod.videoId, root.vod.subtitle, root.vod.owners, root.vod.ownersMore)"]])
      assert.ok(block(guideSrc, where).includes(text), where + " asks the lock about videos")
    assert.ok(block(commandsSrc, "function play(id: string): string {").includes("guide.videoLockedBy(entry.videoId, entry.subtitle, entry.owners, entry.ownersMore)"), "agents' play too, with the entry's channels")
    // every surface: a locked channel's rows left out, and each video on an
    // open channel's rows checked too (it may be on a locked one as well)
    for (const text of ['if (ch.kind === "iptv" || !ch.items || !ch.items.length || channelLockItem.blocks(ch)) continue',
                        'cards: ch.items.filter(function(v) { return !root.videoLockedBy(v.id) })',
                        'if (yc.kind === "iptv" || !yc.items || channelLockItem.blocks(yc)) continue',
                        '&& !root.videoLockedBy(yc.items[j].id)) clips.push(',
                        'if (chl.kind === "iptv" || !chl.items || !chl.items.length || channelLockItem.blocks(chl) || root.videoLockedBy(chl.items[0].id)) continue',
                        'if (chc && chc.items && !channelLockItem.blocks(chc)) cards = chc.items.filter(function(v2) { return !root.videoLockedBy(v2.id) })',
                        'library.unfinished("youtube").filter(function(h) { return !root.videoLockedBy(h.ref || h.id, h.subtitle) })',
                        'root.videoLockedBy(h.ref || h.id, h.subtitle) ? null : root.videoCardFrom(',
                        'if (e && e.videoId && !root.videoLockedBy(e.videoId, e.subtitle, e.owners, e.ownersMore)) clips.push(',
                        'if (le && le.videoId && !root.videoLockedBy(le.videoId, le.subtitle, le.owners, le.ownersMore)) cards.push('])
      assert.ok(guideSrc.includes(text), "a locked channel's videos are left out: " + text.slice(0, 70))
    // the only places YouTube videos become cards: the ones above
    assert.equal((guideSrc.match(/root\.videoCardFrom\(/g) || []).length, 8, "every video card is one of those")
  }

  // the key hints note (K) is drawn before an app's screen, in the same
  // parent and with no z of either: the screen's backdrop (the rail's strip
  // too, tst_appscreen) is over it, so it's never in a picture of the app's
  // screen and needn't count as covering it
  {
    const lines = guideSrc.split("\n")
    const indent = l => l.length - l.trimStart().length
    const opener = (at, kind) => { for (let i = at; i >= 0; i--) if (lines[i].trim() === kind + " {") return i; return -1 }
    const close = at => { for (let i = at + 1; i < lines.length; i++) if (lines[i].trim() === "}" && indent(lines[i]) === indent(lines[at])) return i; return -1 }
    const note = opener(lines.findIndex(l => l.includes("visible: root.keyHintsNote")), "Box")
    const app = opener(lines.findIndex(l => l.trim() === 'active: root.screen === "app"'), "Loader")
    assert.ok(note > 0 && app > 0, "both found")
    assert.ok(note < app, "the note comes first")
    assert.equal(indent(lines[note]), indent(lines[app]), "at the same depth")
    for (let i = note; i < app; i++) assert.ok(lines[i].trim() === "" || indent(lines[i]) >= indent(lines[note]), "in the same parent (line " + (i + 1) + ")")
    for (const at of [note, app]) {
      const body = lines.slice(at + 1, close(at)).filter(l => indent(l) === indent(lines[at]) + 2)
      assert.ok(!body.some(l => /^\s*z\s*:/.test(l)), "no z: " + lines[at].trim())
    }
  }
}

console.log("look: all good")
