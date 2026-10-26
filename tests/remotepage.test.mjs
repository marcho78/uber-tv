// node tests/remotepage.test.mjs
// The phone remote's page (remote/index.html), its script run on a small
// stand-in DOM: it draws every built-in template (resolved by Remote.js),
// each key sends its command, the number pad types a channel (it goes after
// a moment, or on GO or OK) and, while the TV asks for the channel lock's
// passcode, a pad of its own types that instead (dots, never sent by itself;
// GO or OK sends it as text, a leading 0 and all). 123 and ⚙'s choices save
// this phone's prefs; a new revision fetches the template again and redraws;
// expand and collapse switch layouts; the touch pad's swipe moves and a tap
// is OK; a channel in the list tunes. Styles come only from checked values:
// a hostile template's strings stay text and its bad values are dropped.
// The page's own Classic (drawn before the TV sends one) is Remote.js's.
import { readFileSync, readdirSync } from "node:fs"
import assert from "node:assert/strict"

const root = new URL("../", import.meta.url)
const html = readFileSync(new URL("remote/index.html", root), "utf8")
const script = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)].pop()[1]
const R = new Function(readFileSync(new URL("Remote.js", root), "utf8").replace(".pragma library", "") + "; return { check, resolve }")()
const resolved = (id, slots) => R.resolve(R.check(JSON.parse(readFileSync(new URL("remotes/" + id + ".json", root), "utf8"))).template, slots || {})

// ---- a small DOM: elements with children, styles, attributes, listeners ----
class El {
  constructor(tag) { this.tagName = String(tag).toUpperCase(); this.children = []; this.parentNode = null; this.style = {}; this.attrs = {}; this.listeners = {}; this.dataset = {}; this._text = ""; this.className = ""; this.scrollTop = 0 }
  get classList() {
    const el = this
    const set = () => new Set(el.className.split(/\s+/).filter(Boolean))
    return { add: (c) => { const s = set(); s.add(c); el.className = [...s].join(" ") }, remove: (c) => { const s = set(); s.delete(c); el.className = [...s].join(" ") },
             toggle: (c, on) => { const s = set(); (on === undefined ? !s.has(c) : on) ? s.add(c) : s.delete(c); el.className = [...s].join(" ") }, contains: (c) => set().has(c) }
  }
  get id() { return this.attrs.id || "" }
  set id(v) { this.attrs.id = String(v) }
  get textContent() { return this._text + this.children.map((c) => c.textContent).join("") }
  set textContent(v) { for (const c of this.children) c.parentNode = null; this.children = []; this._text = String(v) }
  get childNodes() { return this.children }
  get firstChild() { return this.children[0] || null }
  get lastChild() { return this.children[this.children.length - 1] || null }
  appendChild(c) { if (c.parentNode) c.parentNode.removeChild(c); c.parentNode = this; this.children.push(c); return c }
  append(...cs) { for (const c of cs) this.appendChild(typeof c === "string" ? text(c) : c) }
  insertBefore(c, ref) { if (c.parentNode) c.parentNode.removeChild(c); c.parentNode = this; const i = ref ? this.children.indexOf(ref) : -1; i < 0 ? this.children.push(c) : this.children.splice(i, 0, c); return c }
  removeChild(c) { const i = this.children.indexOf(c); if (i >= 0) this.children.splice(i, 1); c.parentNode = null; return c }
  remove() { if (this.parentNode) this.parentNode.removeChild(this) }
  setAttribute(k, v) { if (k === "style") throw new Error("a style string set as an attribute"); this.attrs[k] = String(v); if (k === "class") this.className = String(v) }
  getAttribute(k) { return k in this.attrs ? this.attrs[k] : null }
  removeAttribute(k) { if (k === "style") this.style = {}; delete this.attrs[k] }
  addEventListener(t, f) { (this.listeners[t] = this.listeners[t] || []).push(f) }
  fire(t, ev) { for (const f of this.listeners[t] || []) f(Object.assign({ target: this, preventDefault() {}, clientX: 0, clientY: 0 }, ev || {})) }
  click() { this.fire("click") }
  focus() {}
  *walk() { yield this; for (const c of this.children) yield* c.walk() }
}
const text = (t) => { const n = new El("#text"); n._text = t; return n }

function page(opts) {
  const o = Object.assign({ remote: null, state: { on: false } }, opts)
  const doc = new El("html")
  const body = doc.appendChild(new El("body"))
  const main = body.appendChild(new El("main")); main.id = "main"
  const head = main.appendChild(new El("header")); head.id = "head"
  for (const [tag, id] of [["h1", "title"], ["button", "gear"]]) { const e = head.appendChild(new El(tag)); e.id = id }
  const pair = main.appendChild(new El("section")); pair.id = "pair"
  for (const [tag, id] of [["input", "code"], ["div", "pairError"], ["button", "pairButton"]]) { const e = pair.appendChild(new El(tag)); e.id = id }
  const area = main.appendChild(new El("section")); area.id = "area"
  const find = (pred) => { for (const e of doc.walk()) if (pred(e)) return e; return null }
  const all = (pred) => [...doc.walk()].filter(pred)
  const sent = []
  const remote = { rev: 1, current: o.remote, prefs: { template: null, pad: null, size: 0 }, list: [], fetched: 0, fail: o.failFirst || 0, hold: null }
  const timers = []
  const env = {
    document: {
      body, fonts: { add() {} },
      querySelector: (s) => { const m = s.match(/^#(.+)$/); return m ? find((e) => e.id === m[1]) : null },
      querySelectorAll: () => [],
      createElement: (t) => new El(t),
      createElementNS: (ns, t) => new El(t),
      createTextNode: (t) => text(t),
    },
    navigator: {},
    innerWidth: o.size ? o.size[0] : 390, innerHeight: o.size ? o.size[1] : 763,
    addEventListener() {},
    setInterval: () => 0,
    confirm: () => true,
    EventSource: class { close() {} },
    fetch: async (path, req) => {
      if (req && req.body) {
        const body = JSON.parse(req.body)
        sent.push(Object.assign({ path }, body))
        if (path === "/api/remote") { Object.assign(remote.prefs, body); remote.rev += 1; return { ok: true, status: 200, json: async () => ({ ok: true, prefs: remote.prefs }) } }
        return { ok: true, status: 204, json: async () => ({}) }
      }
      if (path === "/api/state") return { ok: true, status: 200, json: async () => o.state }
      if (path === "/api/remote") {
        remote.fetched += 1
        if (remote.fail > 0) { remote.fail -= 1; throw new Error("the network dropped it") }
        if (remote.hold) await new Promise((r) => remote.hold.push(r))
        // what the helper has now, as it answers
        const now = { rev: remote.rev, template: remote.current, prefs: remote.prefs, list: remote.list }
        return { ok: true, status: 200, json: async () => now }
      }
      return { ok: false, status: 404, json: async () => ({}) }
    },
    setTimeout: (f) => { timers.push(f); return timers.length },
    clearTimeout: (i) => { if (i) timers[i - 1] = null },
  }
  const names = Object.keys(env)
  const p = new Function(...names, script + "\n;return { render, draw, get tpl() { return tpl }, get view() { return view }, FALLBACK }")(...names.map((n) => env[n]))
  const settle = () => new Promise((r) => setTimeout(r, 0)).then(() => new Promise((r) => setTimeout(r, 0)))
  const button = (label) => find((e) => e.tagName === "BUTTON" && (e.getAttribute("aria-label") === label || e.textContent === label))
  return {
    p, remote, area, settle, find, all, button, timers,
    sent: async () => { await settle(); return sent.splice(0) },
    press: (label) => { const b = button(label); assert.ok(b, "no key: " + label); b.fire("pointerdown"); b.fire("pointerup"); b.click() },
    wait: () => { const due = timers.splice(0); due.forEach((f) => f && f()) },
    typed: () => (find((e) => e.id === "typed") || { textContent: "" }).textContent,
    labels: () => all((e) => e.tagName === "BUTTON").map((e) => e.getAttribute("aria-label")),
  }
}
const LIVE = { on: true, mode: "full", media: "live", signal: "on", muted: false, channels: [
  { number: 131, name: "Al Jazeera", category: "News", title: "Inside Story" },
  { number: 132, name: "Sky News", category: "News", title: "The Evening News", rec: true },
  { number: 501, name: "NASA", category: "YouTube", title: "Earth", live: true }],
  now: { number: 132, name: "Sky News", title: "The Evening News", start: 0, end: 1 }, remoteRev: 1 }

// ---- the page's own Classic is Remote.js's Classic with Retro's colors ----
{
  const t = page()
  assert.deepEqual(t.p.FALLBACK, resolved("classic"), "the page's Classic is Classic resolved with Retro (regenerate the FALLBACK block in remote/index.html if classic.json changed)")
}

// ---- every built-in draws, with its controls ----
const ARIA = { power: "Power", mute: "Mute", options: "Options", back: "Back", guide: "Guide", window: "Full screen or mini player", home: "Home", live: "Live",
               rewind: "Back 30 seconds", playpause: "Pause", forward: "Forward 30 seconds", chup: "Channel up", chdown: "Channel down", padToggle: "Number pad",
               expand: "More buttons", collapse: "Fewer buttons" }
for (const f of readdirSync(new URL("remotes/", root))) {
  const id = f.slice(0, -5)
  const tpl = resolved(id, { accent: "#82fb9c", bgTop: "#0b0c16" })
  const t = page({ remote: tpl, state: LIVE })
  t.p.render(LIVE)
  await t.settle()
  assert.equal(t.p.tpl.id, id, id + " is drawn")
  const labels = t.labels()
  const want = (rows) => rows.flatMap((e) => (e.panel ? e.rows : [e])).filter((r) => r.pad !== "on" || tpl.pad !== "off").flatMap((r) => r.row.map((i) => i.control))
  for (const c of want(tpl.layout.portrait)) {
    if (ARIA[c] && c !== "collapse") assert.ok(labels.includes(ARIA[c]), id + ": its " + c + " key")
    if (c === "dpad") for (const d of ["Up", "Down", "Left", "Right", "OK"]) assert.ok(labels.includes(d), id + ": the d-pad's " + d)
  }
  // nothing was set as a style string; every color set is a checked one
  for (const e of t.all(() => true)) for (const [k, v] of Object.entries(e.style)) {
    if (/color$|^background$/i.test(k) && typeof v === "string" && !/gradient/.test(v)) assert.match(v, /^(#[0-9a-f]{6}([0-9a-f]{2})?|transparent)$/, id + ": " + k + " = " + v)
  }
}

// ---- keys send their commands ----
{
  const t = page({ remote: resolved("classic"), state: LIVE })
  t.p.render(LIVE)
  await t.settle()
  for (const [label, cmd] of [["Power", "power"], ["Mute", "mute"], ["Back", "back"], ["Guide", "guide"], ["Full screen or mini player", "window"],
                              ["Back 30 seconds", "rewind"], ["Pause", "playpause"], ["Forward 30 seconds", "forward"], ["Up", "up"], ["Left", "left"], ["OK", "ok"],
                              ["Channel up", "chup"], ["Channel down", "chdown"], ["Options", "options"]]) {
    t.press(label)
    assert.deepEqual((await t.sent()).map((s) => s.cmd), [cmd], label)
  }
  t.press("Live")
  assert.deepEqual(await t.sent(), [], "LIVE does nothing while the picture's at Live (unavailable)")
  // 123 hides the number pad: this phone's pref, saved
  t.press("Number pad")
  assert.deepEqual(await t.sent(), [{ path: "/api/remote", pad: "off" }], "123 saves the number pad off")
}

// ---- the number pad: a channel ----
{
  const t = page({ remote: resolved("classic"), state: LIVE })
  t.p.render(LIVE)
  await t.settle()
  for (const d of "101") t.press(d)
  assert.equal(t.typed(), "CHANNEL101")
  t.wait()
  assert.deepEqual((await t.sent()).map((s) => [s.cmd, s.number]), [["tune", 101]], "it goes after a moment")
  for (const d of "102") t.press(d)
  t.press("GO")
  assert.deepEqual((await t.sent()).map((s) => [s.cmd, s.number]), [["tune", 102]], "or on GO")
  for (const d of "103") t.press(d)
  t.press("OK")
  assert.deepEqual((await t.sent()).map((s) => [s.cmd, s.number]), [["tune", 103]], "or on OK (not an OK as well)")
  t.press("OK")
  assert.deepEqual((await t.sent()).map((s) => s.cmd), ["ok"], "with nothing typed, OK is OK")
}

// ---- the passcode: its own pad, over any template ----
{
  const t = page({ remote: resolved("pebble"), state: LIVE })   // Pebble has no number pad of its own
  t.p.render(LIVE)
  await t.settle()
  t.p.render(Object.assign({}, LIVE, { passcode: true }))
  for (const d of "0246") t.press(d)
  assert.equal(t.find((e) => e.id === "codeDots").textContent, "PASSCODE••••", "dots, never the digits")
  t.wait()
  assert.deepEqual(await t.sent(), [], "never sent by itself")
  t.press("GO")
  assert.deepEqual((await t.sent()).map((s) => [s.cmd, s.digits]), [["code", "0246"]], "GO sends it as text, a leading 0 and all")
  t.p.render(LIVE)
  assert.equal(t.find((e) => e.id === "codeDots"), null, "the pad goes once the TV stops asking")
}

// ---- a new revision fetches the template again and redraws ----
{
  const t = page({ remote: resolved("classic"), state: LIVE })
  t.p.render(LIVE)
  await t.settle()
  const before = t.remote.fetched
  t.remote.current = resolved("player")
  t.remote.rev = 7
  t.p.render(Object.assign({}, LIVE, { remoteRev: 7 }))
  await t.settle()
  assert.equal(t.remote.fetched, before + 1, "fetched again")
  assert.equal(t.p.tpl.id, "player", "and drawn")
  t.p.render(Object.assign({}, LIVE, { remoteRev: 7 }))
  await t.settle()
  assert.equal(t.remote.fetched, before + 1, "the same revision again: no fetch")
  // with none sent, the page's own Classic
  t.remote.current = null
  t.remote.rev = 8
  t.p.render(Object.assign({}, LIVE, { remoteRev: 8 }))
  await t.settle()
  assert.equal(t.p.tpl.id, "classic")
}

// ---- a fetch that fails is tried again; the newest revision wins ----
{
  const t = page({ remote: resolved("player"), state: LIVE, failFirst: 1 })   // the page's own start fetches, and that fails
  await t.settle()
  assert.equal(t.p.tpl.id, "classic", "the first fetch failed: the page's own Classic meanwhile")
  t.wait()                                   // the retry
  await t.settle()
  assert.equal(t.p.tpl.id, "player", "tried again, and this phone's template is drawn")
}
{
  const t = page({ remote: resolved("classic"), state: LIVE })
  t.p.render(LIVE)
  await t.settle()
  t.remote.fail = 1
  t.remote.current = resolved("surfer"); t.remote.rev = 2
  t.p.render(Object.assign({}, LIVE, { remoteRev: 2 }))
  await t.settle()
  assert.equal(t.p.tpl.id, "classic", "a failed fetch changes nothing yet")
  t.p.render(Object.assign({}, LIVE, { remoteRev: 2 }))
  await t.settle()
  assert.equal(t.p.tpl.id, "surfer", "the same revision told again is fetched again: it wasn't applied")
}
{
  const t = page({ remote: resolved("classic"), state: LIVE })
  t.p.render(LIVE)
  await t.settle()
  t.remote.hold = []
  t.remote.current = resolved("player"); t.remote.rev = 2
  t.p.render(Object.assign({}, LIVE, { remoteRev: 2 }))
  await t.settle()
  t.remote.current = resolved("tiles"); t.remote.rev = 3
  t.p.render(Object.assign({}, LIVE, { remoteRev: 3 }))   // while the first is out
  await t.settle()
  const held = t.remote.hold
  t.remote.hold = null
  held.forEach((r) => r())
  await t.settle(); await t.settle()
  assert.equal(t.p.tpl.id, "tiles", "the newest revision told is drawn in the end")
}

// ---- the card's bar: a finger along it sends the TV there, for what it was drawn for ----
{
  const S = Object.assign({}, LIVE, { play: 7, ts: { on: true, running: true, paused: false, atLive: false, behind: 150, window: 1800 } })
  const t = page({ remote: resolved("player"), state: S })
  t.p.render(S)
  await t.settle()
  const bar = t.find((e) => e.className === "barbox")
  assert.ok(bar, "the card's bar")
  bar.getBoundingClientRect = () => ({ left: 100, width: 200 })
  bar.fire("pointerdown", { clientX: 250 })
  bar.fire("pointermove", { clientX: 150 })
  const label = t.find((e) => e.className === "barlabels")
  assert.ok(label.textContent.startsWith("22:30 behind live"), "the time follows the finger: " + label.textContent)
  t.p.render(Object.assign({}, S, { play: 8 }))       // something else starts while the finger's down
  bar.fire("pointerup", { clientX: 150 })
  assert.deepEqual((await t.sent()).map((s) => [s.cmd, s.at, s.play]), [["seek", 0.25, 7]], "let go: seek, at a fraction, with the play it was drawn for")
  // no play token (an older TV): no drag
  const u = page({ remote: resolved("player"), state: LIVE })
  u.p.render(LIVE)
  await u.settle()
  const b2 = u.find((e) => e.className === "barbox")
  b2.getBoundingClientRect = () => ({ left: 0, width: 100 })
  b2.fire("pointerdown", { clientX: 10 }); b2.fire("pointerup", { clientX: 10 })
  assert.deepEqual(await u.sent(), [], "nothing to seek: nothing sent")
}

// ---- the bar drags only where the TV seeks ----
{
  const TS = { on: true, running: true, paused: false, atLive: false, behind: 150, window: 1800 }
  const drag = async (state) => {
    const t = page({ remote: resolved("player"), state })
    t.p.render(state)
    await t.settle()
    const bar = t.find((e) => e.className === "barbox")
    bar.getBoundingClientRect = () => ({ left: 0, width: 100 })
    bar.fire("pointerdown", { clientX: 40 }); bar.fire("pointerup", { clientX: 40 })
    return { t, bar, sent: await t.sent() }
  }
  for (const mode of ["guide", "mini"]) {
    const { sent } = await drag(Object.assign({}, LIVE, { mode, play: 4, ts: TS }))
    assert.deepEqual(sent, [], "a live channel in the " + mode + ": the bar shows, but doesn't seek")
  }
  const full = await drag(Object.assign({}, LIVE, { mode: "full", play: 4, ts: TS }))
  assert.deepEqual(full.sent.map((s) => [s.cmd, s.at, s.play]), [["seek", 0.4, 4]], "full screen: one seek")
  // leaving full screen during a drag: it's off, nothing sent
  const S = Object.assign({}, LIVE, { mode: "full", play: 4, ts: TS })
  const t = page({ remote: resolved("player"), state: S })
  t.p.render(S)
  await t.settle()
  const bar = t.find((e) => e.className === "barbox")
  bar.getBoundingClientRect = () => ({ left: 0, width: 100 })
  bar.fire("pointerdown", { clientX: 40 })
  t.p.render(Object.assign({}, S, { mode: "guide" }))
  bar.fire("pointerup", { clientX: 60 })
  assert.deepEqual(await t.sent(), [], "the guide came up mid-drag: nothing sent")
}

// ---- an app's video: its card and bar, though the TV's channel is off ----
{
  const A = { on: false, mode: "app", media: "app", paused: false, play: 9, muted: false, channels: [],
              now: { vod: true, app: true, title: "Big Buck Bunny", name: "Jellyfin", paused: false, position: 300, length: 600 } }
  const t = page({ remote: resolved("player"), state: A })
  t.p.render(A)
  await t.settle()
  const card = t.find((e) => e.className === "card")
  assert.ok(card.textContent.includes("Big Buck Bunny") && card.textContent.includes("Jellyfin"), "its title on the card: " + card.textContent.slice(0, 80))
  const bar = t.find((e) => e.className === "barbox")
  bar.getBoundingClientRect = () => ({ left: 0, width: 100 })
  bar.fire("pointerdown", { clientX: 75 }); bar.fire("pointerup", { clientX: 75 })
  assert.deepEqual((await t.sent()).map((s) => [s.cmd, s.at, s.play]), [["seek", 0.75, 9]], "dragged: a seek with its play")
  t.press("Pause")
  assert.deepEqual((await t.sent()).map((s) => s.cmd), ["playpause"], "its transport keys work")
}
{
  const state = read => read
  const guideSrc = readFileSync(new URL("Guide.qml", root), "utf8")
  const i = guideSrc.indexOf("function remoteState() {")
  const body = guideSrc.slice(i, guideSrc.indexOf("\n  }\n", i))
  assert.match(body, /now: app \? \{ vod: true, app: true, title: root\.showTitle\(String\(app\.title \|\| ""\)\.slice\(0, 200\)\), name: String\(app\.subtitle \|\| ""\)\.slice\(0, 200\),/, "the guide tells the phones an app video's title (bounded)")
  assert.match(body, /position: Math\.round\(appPlaybackItem\.position\), length: app\.live \? 0 : Math\.round\(appPlaybackItem\.duration\)/, "and its place and length (a live one: no length, so no drag)")
  assert.match(guideSrc, /onRemoteAppChanged: remoteStateTimer\.restart\(\)/, "told again as it plays (every 15 s, a seek)")
}

// ---- sideways: landscape.right puts the controls it names on the right ----
{
  const tpl = resolved("classic")
  tpl.layout.landscape = { right: ["dpad"] }
  const t = page({ remote: tpl, state: LIVE, size: [800, 400] })
  t.p.render(LIVE)
  await t.settle()
  const cols = t.find((e) => e.className === "cols")
  assert.ok(cols && cols.children.length === 2, "two columns")
  const inCol = (i, label) => [...cols.children[i].walk()].some((e) => e.tagName === "BUTTON" && e.getAttribute("aria-label") === label)
  assert.ok(inCol(1, "Up") && !inCol(0, "Up"), "the d-pad, named in right, is on the right")
  assert.ok(inCol(0, "Power"), "the rest on the left")
}

// ---- expand and collapse; the touch pad; the list ----
{
  const t = page({ remote: resolved("swipe"), state: LIVE })
  t.p.render(LIVE)
  await t.settle()
  assert.ok(!t.labels().includes("Power"), "minimized: no power key")
  t.press("More buttons")
  await t.settle()
  assert.ok(t.labels().includes("Power") && t.labels().includes("Fewer buttons"), "expanded: the sheet's keys")
  t.press("Fewer buttons")
  await t.settle()
  assert.ok(!t.labels().includes("Power"), "collapsed again")
  const pad = t.find((e) => e.getAttribute("aria-label") === "Touch pad: swipe to move, tap for OK")
  pad.fire("pointerdown", { clientX: 100, clientY: 100 }); pad.fire("pointerup", { clientX: 180, clientY: 110 })
  pad.fire("pointerdown", { clientX: 100, clientY: 100 }); pad.fire("pointerup", { clientX: 96, clientY: 30 })
  pad.fire("pointerdown", { clientX: 100, clientY: 100 }); pad.fire("pointerup", { clientX: 104, clientY: 103 })
  assert.deepEqual((await t.sent()).map((s) => s.cmd), ["right", "up", "ok"], "a swipe moves, a tap is OK")
}
{
  const t = page({ remote: resolved("glance"), state: LIVE })
  t.p.render(LIVE)
  await t.settle()
  const row = t.find((e) => e.className === "chan" && e.textContent.includes("NASA"))
  row.click()
  assert.deepEqual((await t.sent()).map((s) => [s.cmd, s.number]), [["tune", 501]], "a channel in the list tunes")
  const rec = t.find((e) => e.className === "chan" && e.textContent.includes("Sky News"))
  assert.ok(rec.textContent.includes("● REC"), "the channel recording says so")
}

// ---- ⚙: template, number pad, size; the sheet's words are text ----
{
  const t = page({ remote: resolved("classic"), state: LIVE })
  t.remote.list = [{ id: "classic", name: "Classic", description: "d" }, { id: "evil", name: "<img src=x onerror=alert(1)>", description: "<script>" }]
  t.p.render(LIVE)
  await t.settle()
  t.find((e) => e.id === "gear").click()
  const pick = t.find((e) => e.getAttribute("aria-label") === "<img src=x onerror=alert(1)>")
  assert.ok(pick && pick.textContent.startsWith("<img src=x onerror=alert(1)>"), "a name is shown as text")
  assert.ok(!t.all((e) => e.tagName === "IMG" || e.tagName === "SCRIPT").some((e) => e.getAttribute("src") === "x"), "and makes no element")
  pick.click()
  t.press("+")
  assert.deepEqual((await t.sent()).map((s) => [s.path, s.template, s.size]), [["/api/remote", "evil", undefined], ["/api/remote", undefined, 1]], "a template picked, the size one larger")
}

// ---- a hostile template: bad values are dropped, never set ----
{
  const evil = resolved("classic")
  evil.styles.key = { fill: "red; background: url(//x)", border: { width: "9px", color: "#zzz" }, radius: "1e9", shadow: { color: "url(x)", blur: NaN, x: 1, y: 1 },
                      shape: "polygon", text: { color: "expression(x)", font: "Evil Sans", size: "12px", weight: "900; x", case: "shout", letterSpacing: Infinity }, icon: "big" }
  evil.styles.page = { fill: { from: "#000000", to: "url(x)", direction: "sideways" } }
  const t = page({ remote: evil, state: LIVE })
  t.p.render(LIVE)
  await t.settle()
  const k = t.button("Power")
  assert.equal(k.style.background, "#ff4d4d", "power keeps its own fill (Retro's alert)")
  const m = t.button("Mute")
  assert.equal(m.style.background, "transparent", "a fill that isn't a color is transparent")
  assert.ok(!JSON.stringify(m.style).includes("url(") && !JSON.stringify(m.style).includes("expression"), "nothing of it reaches a style")
  assert.ok(!/Evil/.test(m.style.fontFamily || ""), "an unknown font is the phone's own")
  assert.equal(m.style.textTransform, "none", "an unknown case is none")
}

console.log("remote page: all good")
