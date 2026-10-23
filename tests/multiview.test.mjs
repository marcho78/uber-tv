// Multiview's ties to the rest of the guide, from Guide.qml's own code
// (it loads only in the shell, so its functions are cut out and run over a
// stand-in): while Multiview is up, the media player stays registered with
// the tile that has the sound (playing or paused), so media keys and the
// bar's widget still find Uber TV; a theme saved to disk keeps Multiview's
// background, its picture as a full path; an agent sets it, a color too;
// an agent opens Multiview with channels, adds, takes off, picks the layout
// and the sound, and closes it (never a locked channel), and state says so;
// the phone's ▲ in full screen opens the banner's choices, ◀ ▶ change channel;
// an agent's watch, a moment later, puts on the channel asked for.
//   node tests/multiview.test.mjs
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const guideSrc = readFileSync(new URL("../Guide.qml", import.meta.url), "utf8")
const commandsSrc = readFileSync(new URL("../Commands.qml", import.meta.url), "utf8")
// a block of code: from its opening line to the closing brace at its indent
const block = (text, opener) => {
  const i = text.indexOf(opener)
  assert.ok(i >= 0, "missing: " + opener)
  const lineStart = text.lastIndexOf("\n", i) + 1
  const indent = text.slice(lineStart, i).match(/^ */)[0]
  const open = text.indexOf("{", i + opener.length - 1)
  const end = text.indexOf("\n" + indent + "}\n", open)
  assert.ok(end > open, "no end: " + opener)
  return text.slice(open + 1, end)
}

// ---- the media player while Multiview is up ----
{
  const sendMpris = new Function("root", "streamer", "player", "MediaPlayer", block(guideSrc, "function sendMpris() {"))
  const written = []
  const streamer = { running: true, write: line => written.push(JSON.parse(line).mpris) }
  const MediaPlayer = { PausedState: 2, PlayingState: 1 }
  const player = { playbackState: 0, duration: 0, position: 0 }
  const tile = { onAir: { id: "abc", title: "The news", live: true } }
  const multiview = { active: true, sel: 2, paused: false, tileIn: s => (s === 2 ? tile : {}), rowOf: () => 0 }
  const root = { port: 1234, reception: "off", onAir: null, vod: null, tunedRow: -1, numbers: [101],
                 channels: [{ name: "Sky News", category: "News", channelId: "UC1" }], multiview: multiview, showTitle: t => t }
  sendMpris(root, streamer, player, MediaPlayer)
  assert.equal(written[0].active, true, "the TV's player is off, but Multiview is playing: still active")
  assert.equal(written[0].status, "Playing")
  assert.equal(written[0].title, "The news", "the tile with the sound")
  assert.match(written[0].artist, /Multiview · CH 101 · Sky News/)
  multiview.paused = true
  sendMpris(root, streamer, player, MediaPlayer)
  assert.equal(written[1].active, true, "paused: still registered")
  assert.equal(written[1].status, "Paused")
  multiview.active = false
  sendMpris(root, streamer, player, MediaPlayer)
  assert.equal(written[2].active, false, "Multiview gone and the TV off: stopped")
  // the guide sends it again when Multiview starts or ends, and as its sound, channels or pause change
  for (const sig of ["onActiveChanged", "onSelChanged", "onSlotsChanged", "onPausedChanged"])
    assert.ok(new RegExp("target: multiviewItem[\\s\\S]{0,400}function " + sig + "\\(\\) \\{ Qt.callLater\\(root.sendMpris\\) \\}").test(guideSrc), sig + " resends it")
}

// ---- a theme saved to disk keeps Multiview's background ----
{
  const themeOnDisk = new Function("theme", block(guideSrc, "function themeOnDisk(theme) {"))
  const out = themeOnDisk({ name: "T", description: "", colors: {}, images: {}, dir: "/home/u/.config/om-pg/themes/t",
                            multiview: { background: { mode: "image", image: "mv.jpg", dim: 0.4 } } })
  assert.deepEqual(out.multiview, { background: { mode: "image", image: "/home/u/.config/om-pg/themes/t/mv.jpg", dim: 0.4 } },
                   "its mode, darkness and picture (as a full path, for the helper to copy)")
  const none = themeOnDisk({ name: "T", colors: {}, images: {} })
  assert.equal(none.multiview, undefined, "none given: none written")
  const color = themeOnDisk({ name: "T", colors: {}, images: {}, multiview: { background: { mode: "color", color: "#1e2a3b", dim: 0.6 } } })
  assert.deepEqual(color.multiview, { background: { mode: "color", color: "#1e2a3b", dim: 0.6 } }, "a color, as it is")
}

// ---- an agent sets Multiview's background ----
{
  const command = new Function("guide", "commands", "Quickshell", "mode", "dim",
                               block(commandsSrc, "function multiviewBackground(mode: string, dim: string): string {"))
  const solidHex = new Function("v", guideSrc.match(/function solidHex\(v\) \{ (.*) \}\n/)[1])   // (one line)
  const set = [], pictures = []
  const guide = { multiviewBackground: {}, solidHex, setMultiviewBackground: c => set.push(c), multiviewPicture: p => pictures.push(p) }
  const commands = { okReply: o => ({ ok: true, ...o }), failReply: e => ({ ok: false, error: e }) }
  const Quickshell = { env: () => "/home/u" }
  assert.equal(command(guide, commands, Quickshell, "#1E2A3B", "").ok, true)
  assert.deepEqual(set.pop(), { mode: "color", color: "#1e2a3b" }, "a color")
  command(guide, commands, Quickshell, "theme", "0.4")
  assert.deepEqual(set.pop(), { mode: "theme", dim: 0.4 }, "the theme's background, and how dark")
  command(guide, commands, Quickshell, "", "0.2")
  assert.deepEqual(set.pop(), { dim: 0.2 }, "only how dark: the rest kept")
  command(guide, commands, Quickshell, "~/Pictures/a.jpg", "")
  assert.equal(pictures.pop(), "/home/u/Pictures/a.jpg", "a picture: checked and copied first")
  for (const bad of ["red", "#12345", "#11223344"])
    assert.equal(command(guide, commands, Quickshell, bad, "").ok, false, bad + ": refused")
  assert.equal(set.length, 0, "nothing set by a refused one")
}

// ---- an agent's Multiview (Commands.qml) ----
{
  const fn = (opener, params) => new Function("guide", "commands", "multiviewSoon", ...params, block(commandsSrc, opener))
  const helpers = { multiviewRows: ["numbers"], multiviewInfo: [], multiviewSlot: ["number"], channelInfo: ["r"] }
  const ipc = { multiview: ["numbers"], multiviewAdd: ["number"], multiviewRemove: ["number"], multiviewLayout: ["layout"], multiviewSound: ["number"] }
  const layoutsFor = n => n <= 1 ? ["single"] : n === 2 ? ["side", "featured"] : n === 3 ? ["featured", "grid", "row"] : ["grid", "featured"]
  const channels = [101, 102, 103, 104, 105, 106].map(n => ({ url: "u/" + n, name: "C" + n, kind: "youtube" }))
  const mv = { active: false, slots: ["", "", "", ""], order: [], sel: 0, layout: "single", mode: "tiles", pickMode: "add", paused: false, started: null, exited: 0,
               get count() { return this.order.length }, layoutsFor,
               rowOf(s) { return this.slots[s] ? channels.findIndex(c => c.url === this.slots[s]) : -1 },
               startWith(urls) { this.started = urls },
               addTile(url) { const f = this.slots.indexOf(""); if (f < 0 || this.slots.includes(url)) return -1; this.slots[f] = url; this.order.push(f); this.layout = layoutsFor(this.count)[0]; return f },
               remove(s) { this.order = this.order.filter(x => x !== s); this.slots[s] = "" },
               select(s) { this.sel = s },
               setLayout(l) { if (!layoutsFor(this.count).includes(l)) return false; this.layout = l; return true },
               exit() { this.exited++; this.active = false } }
  const locked = { "u/105": true }
  const guide = { numbers: [101, 102, 103, 104, 105, 106], channels, visibleRows: [0, 1, 2, 3, 4, 5], opened: true, pip: false, tunedRow: -1, summoned: 0,
                  airs: ch => ch.url !== "u/106", guidePip() { guide.summoned++ }, multiview: mv, mvRequest: 0, requestMultiview() { return ++guide.mvRequest },
                  channelLock: { loaded: true, blocks: ch => !!locked[ch.url], isLocked: ch => !!locked[ch.url] },
                  recorder: { needsAsk: () => false } }
  const timer = { restarts: 0, restart() { timer.restarts++ } }
  const commands = { okReply: o => ({ ok: true, ...o }), failReply: e => ({ ok: false, error: e }), pendingMultiview: null,
                     multiviewOff: "Multiview isn't on (multiview \"<numbers>\" opens it)" }
  for (const [name, params] of Object.entries(helpers)) { const f = fn("function " + name + "(", params); commands[name] = (...a) => f(guide, commands, timer, ...a) }
  const call = {}
  for (const [name, params] of Object.entries(ipc)) { const f = fn("function " + name + "(" + params[0] + ": string): string {", params); call[name] = (...a) => f(guide, commands, timer, ...a) }
  const close = fn("function multiviewClose(): string {", [])
  call.multiviewClose = () => close(guide, commands, timer)

  // opening: 1 to 4 channels that can play, by number
  const opened = call.multiview("101, 102,103")
  assert.equal(opened.ok, true)
  assert.deepEqual(commands.pendingMultiview.urls, ["u/101", "u/102", "u/103"], "started a moment later, by address")
  assert.equal(commands.pendingMultiview.request, guide.mvRequest, "as a numbered request")
  assert.equal(timer.restarts, 1)
  assert.equal(opened.layout, "featured")
  assert.equal(guide.summoned, 0, "the guide's open: not summoned")
  for (const [bad, why] of [["", /1 to 4/], ["101,102,103,104,106", /up to 4/], ["999", /no channel 999/], ["101,101", /twice/],
                            ["106", /nothing to show/], ["105", /locked: only the user/], ["abc", /no channel abc/]])
    assert.match(call.multiview(bad).error || "", why, bad)
  guide.opened = false
  call.multiview("101")
  assert.equal(guide.summoned, 1, "closed: the guide opens first")
  guide.opened = true
  guide.pip = true
  call.multiview("101")
  assert.equal(guide.summoned, 2, "the mini player: back to the guide")
  guide.pip = false

  // the rest need Multiview on
  for (const name of ["multiviewAdd", "multiviewRemove", "multiviewLayout", "multiviewSound"])
    assert.match(call[name]("101").error || "", /isn't on/, name)
  assert.match(call.multiviewClose().error || "", /isn't on/)
  Object.assign(mv, { active: true, slots: ["u/101", "u/102", "", ""], order: [0, 1], sel: 0, layout: "side" })

  // adding: one that can play, not on already, up to four
  assert.match(call.multiviewAdd("102").error, /already/)
  assert.match(call.multiviewAdd("105").error, /locked/)
  assert.match(call.multiviewAdd("101,103").error, /one channel/)
  let r = call.multiviewAdd("103")
  assert.deepEqual(r.multiview.channels.map(c => c.number), [101, 102, 103])
  assert.equal(r.multiview.layout, "featured")
  call.multiviewAdd("104")
  assert.match(call.multiviewAdd("106").error, /four/, "four: full")

  // the layout: one for how many
  assert.match(call.multiviewLayout("row").error, /with 4 channels: grid, featured/)
  assert.equal(call.multiviewLayout("featured").multiview.layout, "featured")

  // the sound
  assert.match(call.multiviewSound("106").error, /isn't on Multiview/)
  r = call.multiviewSound("103")
  assert.equal(r.multiview.sound, 103)
  assert.deepEqual(r.multiview.channels.map(c => c.sound), [false, false, true, false])

  // taking off; with one left it closes (Multiview's remove does it)
  r = call.multiviewRemove("102")
  assert.deepEqual(r.multiview.channels.map(c => c.number), [101, 103, 104])
  assert.equal(r.note, undefined)
  assert.match(call.multiviewRemove("102").error, /isn't on Multiview/)
  Object.assign(mv, { slots: ["u/101", "", "u/103", ""], order: [0, 2] })
  assert.match(call.multiviewRemove("103").note, /Multiview closed: channel 101 plays full screen/, "the one left")

  // closing
  Object.assign(mv, { active: true, slots: ["u/101", "", "u/103", ""], order: [0, 2], sel: 2 })
  assert.match(call.multiviewClose().note, /Multiview closed: channel 103 plays full screen/, "the one with the sound")
  assert.equal(mv.exited, 1)

  // state: null while off
  mv.active = false
  assert.equal(commands.multiviewInfo(), null)
  assert.match(commandsSrc, /multiview: commands\.multiviewInfo\(\),/, "state reports it")
}

// ---- an agent's Multiview starts only if nothing's overtaken it, and after an app's video lets go ----
{
  const fired = new Function("guide", "commands", "multiviewSoon", commandsSrc.match(/id: multiviewSoon[\s\S]*?onTriggered: \{([\s\S]*?)\n    \}\n/)[1])
  const realStart = new Function("root", "appPlaybackItem", "multiviewItem", "urls", "request", block(guideSrc, "function startMultiview(urls, request) {"))
  const request = new Function("root", guideSrc.match(/function requestMultiview\(\) \{ (.*) \}\n/)[1])
  const started = [], closes = []
  let dropped = 0, waiting = null
  const app = { dropPending() { dropped++ }, close(reason, then) { closes.push(reason); waiting = then } }
  const tiles = { startWith(urls) { started.push(urls); return "ok" } }
  const root = { mvRequest: 0, opened: true, appPlaying: false }
  root.startMultiview = (u, r) => realStart(root, app, tiles, u, r)
  root.requestMultiview = () => request(root)
  const timer = { restarts: 0, restart() { timer.restarts++ } }
  const commands = { pendingMultiview: null }
  const ask = urls => { commands.pendingMultiview = { urls, request: root.requestMultiview(), tries: 0 } }
  const closeGuide = () => { root.mvRequest += 1; root.opened = false }   // closeNow (its mvRequest += 1 is checked below)

  // nothing in the way: the tiles
  ask(["u/1", "u/2"]); fired(root, commands, timer)
  assert.deepEqual(started.pop(), ["u/1", "u/2"])
  assert.equal(commands.pendingMultiview, null)

  // closed before it fires: nothing starts, however long it waits
  ask(["u/1", "u/2"]); closeGuide()
  for (let i = 0; i < 12; i++) fired(root, commands, timer)
  assert.equal(started.length, 0, "closed: Multiview stays off")
  assert.equal(commands.pendingMultiview, null)
  root.opened = true

  // the guide still opening: it waits for it, then starts
  ask(["u/3", "u/4"]); root.opened = false
  fired(root, commands, timer)
  assert.equal(timer.restarts, 1, "waits")
  root.opened = true
  fired(root, commands, timer)
  assert.deepEqual(started.pop(), ["u/3", "u/4"])

  // something else played since (a channel, a video, the TV off, an app's video): overtaken
  ask(["u/1", "u/2"]); root.mvRequest += 1
  fired(root, commands, timer)
  assert.equal(started.length, 0, "overtaken")

  // an app's video playing: it lets go first (finalized), then the tiles; one queued after it is dropped
  root.appPlaying = true
  ask(["u/1", "u/2"]); fired(root, commands, timer)
  assert.deepEqual(closes, ["replaced"], "the app's playback closed as replaced")
  assert.equal(dropped, 1)
  assert.equal(started.length, 0, "no tile before the app's player is gone")
  root.appPlaying = false; waiting()
  assert.deepEqual(started.pop(), ["u/1", "u/2"], "then Multiview")

  // closed while the app's video is letting go: nothing starts after
  root.appPlaying = true
  ask(["u/1", "u/2"]); fired(root, commands, timer)
  closeGuide(); root.appPlaying = false; waiting()
  assert.equal(started.length, 0, "closed meanwhile: Multiview stays off")

  // the preview box waits while one is on its way (its tune would overtake
  // it), and plays again once it's started or dropped (the real previewRow)
  const previewFn = new Function("root", "multiviewItem", "channelLockItem", "dvr", block(guideSrc, "function previewRow() {"))
  const preview = (r, m, l) => previewFn(r, m, l, { needsAsk: () => false })
  let tunes = 0
  Object.assign(root, { opened: true, appPlaying: false, watching: false, managing: false, screen: "guide", channels: [{ url: "u/9" }], row: 0, tunedRow: -1, reception: "off",
                        mvWaitingFor: -1, airs: () => true, tune() { tunes++; root.mvRequest += 1 } })
  const notActive = { active: false }, unlocked = { blocks: () => false }
  const waitReq = new Function("root", guideSrc.match(/function requestMultiview\(\) \{ (.*) \}\n/)[1])
  root.requestMultiview = () => waitReq(root)
  preview(root, notActive, unlocked)
  assert.equal(tunes, 1, "nothing on its way: the preview plays")
  ask(["u/1", "u/2"]); preview(root, notActive, unlocked)
  assert.equal(tunes, 1, "on its way: the preview waits")
  fired(root, commands, timer)
  assert.deepEqual(started.pop(), ["u/1", "u/2"], "and Multiview starts")
  preview(root, notActive, unlocked)
  assert.equal(tunes, 2, "started: the preview's itself again")
  ask(["u/1", "u/2"]); root.opened = false
  for (let i = 0; i < 12; i++) fired(root, commands, timer)
  root.opened = true; preview(root, notActive, unlocked)
  assert.equal(tunes, 3, "dropped (the guide never opened): the preview's itself again")

  // what overtakes it: turning off, closing, a channel, a video, an app's video
  for (const opener of ["function turnOff() {", "function closeNow() {", "function tune(r, at, retrying) {", "function playVod(entry, from) {"])
    assert.match(block(guideSrc, opener), /root\.mvRequest \+= 1/, opener)
  assert.match(guideSrc, /onAppPlayingChanged: if \(appPlaying\) \{ mvRequest \+= 1/)
}

// ---- the phone in full screen: ▲ opens the banner's choices (Multiview
// first), ◀ ▶ change channel; with the choices up ◀ ▶ choose, OK picks,
// ▼ or BACK closes them (the real handler and banner functions) ----
{
  const remoteCommand = new Function("root", "appViewItem", "nativeSaverItem", "screenSaverItem", "Hyprland", "channelLockItem", "cmd", "number", "by",
                                     block(guideSrc, "function remoteCommand(cmd, number, by, digits) {"))
  const fn = (opener, param) => new Function("root", "bannerTimer", param, block(guideSrc, opener))
  const open = new Function("root", "bannerTimer", "dvr", block(guideSrc, "function openBannerOptions() {")), hide = fn("function hideBanner() {", "_")
  const move = fn("function moveBannerAct(d) {", "d"), pick = fn("function pickBannerAct(i) {", "i")
  const bannerTimer = { restart() {}, stop() {} }
  assert.match(block(guideSrc, "readonly property var bannerActions: {"), /return tsActions\.concat\(\[\{ key: "multiview", label: "Multiview", icon: "apps" \}\]\)\.concat\(rec\)\.concat\(\[\{ key: "mini",[^\n]*\n\s*\{ key: "guide",[^\n]*\{ key: "mute"/, "the choices, Multiview first (then a recording's); pause and rewind's before it, while that's on")
  const you = {}, seen = []
  const root = { byUser: you, splash: null, reception: "playing", authBusy: false, dialog: "", appOpening: false, appUp: false,
                 multiview: { active: false }, pip: false, vod: null, opened: true, watching: true, screen: "guide",
                 bannerOptions: false, bannerShown: false, bannerAct: 0, muted: false, ltShow: true,
                 bannerActions: [{ key: "multiview" }, { key: "mini" }, { key: "guide" }, { key: "mute" }],
                 surf: d => seen.push("surf " + d), showBanner: () => seen.push("banner"), showGuide: () => seen.push("guide"),
                 openMultiview: () => seen.push("multiview"), goPip: () => seen.push("mini") }
  root.openBannerOptions = () => open(root, bannerTimer, { said: "", checkPlace() {} })
  root.hideBanner = () => hide(root, bannerTimer)
  root.bannerBack = () => root.hideBanner()
  root.moveBannerAct = d => move(root, bannerTimer, d)
  root.pickBannerAct = i => pick(root, bannerTimer, i)
  const idle = { up: false, settling: false, showing: false, activity() {}, wake() {} }
  const press = cmd => remoteCommand(root, { agentOpen: null }, idle, idle, { usingLua: false }, { boxUp: false }, cmd, 0, you)

  press("right"); press("left")
  assert.deepEqual(seen.splice(0), ["surf 1", "surf -1"], "◀ ▶ change channel")
  press("down")
  assert.deepEqual([seen.splice(0), root.bannerOptions], [[], false], "▼ with nothing up: nothing (not a channel)")
  press("up")
  assert.deepEqual([seen.splice(0), root.bannerOptions, root.bannerShown, root.bannerAct], [[], true, true, 0], "▲: the banner's choices, not a channel")
  press("up")
  assert.deepEqual([seen.splice(0), root.bannerOptions], [[], true], "▲ again: they stay")
  press("right"); press("right"); press("left")
  assert.deepEqual([seen.splice(0), root.bannerAct], [[], 1], "with them up, ◀ ▶ choose (the channel stays)")
  press("down")
  assert.deepEqual([root.bannerOptions, root.bannerShown], [false, false], "▼ closes them")
  press("up"); press("back")
  assert.deepEqual([seen.splice(0), root.bannerOptions, root.watching], [[], false, true], "so does BACK, still full screen")
  press("up"); press("ok")
  assert.deepEqual([seen.splice(0), root.bannerOptions], [["multiview"], false], "OK picks: Multiview, the first")
  press("ok"); press("back")
  assert.deepEqual(seen.splice(0), ["banner", "guide"], "nothing up: OK shows the banner, BACK the guide, as before")
}

// ---- cancelling the picture picker from Multiview's gear goes back to Multiview, not the style panel ----
{
  const dialogSrc = readFileSync(new URL("../ui/DialogBox.qml", import.meta.url), "utf8")
  assert.match(dialogSrc, /Key_Escape\) guide\.pickImages && guide\.pickArea !== "home" && guide\.pickArea !== "multiview" \? guide\.backToStyle\(\) : guide\.closeDialog\(\)/)
}

// ---- an agent's watch, a moment later: the channel asked for ----
// The guide (or the mini player) comes up first, so watch goes on 600 ms
// later; a category set or a channel removed meanwhile moves the rows, and
// it's the channel asked for that comes on, not whatever took its row
{
  const watch = new Function("guide", "commands", "watchSoon", "number", block(commandsSrc, "function watch(number: string): string {"))
  const watchSoonSrc = commandsSrc.slice(commandsSrc.indexOf("id: watchSoon"))
  const fired = new Function("guide", "commands", watchSoonSrc.match(/onTriggered: \{/) ? block(watchSoonSrc, "onTriggered: {") : watchSoonSrc.match(/onTriggered: (.*)\n/)[1])
  const watched = []
  const guide = {
    channels: [{ url: "u/news", name: "News" }, { url: "u/kids", name: "Kids" }, { url: "u/film", name: "Films" }], numbers: [101, 102, 103],
    opened: true, airs: () => true, channelLock: { blocks: () => false, isLocked: () => false }, recorder: { needsAsk: () => false }, visibleRows: [0, 1, 2], watch: r => watched.push(guide.channels[r].url),
    indexOf(url) { for (let i = 0; i < guide.channels.length; i++) if (url && guide.channels[i].url === url) return i; return -1 },
  }
  const commands = { pendingWatch: commandsSrc.match(/property int pendingWatch/) ? -1 : "", okReply: o => ({ ok: true, ...o }), failReply: e => ({ ok: false, error: e }),
                     rowsFor: n => guide.numbers.indexOf(Number(n)) >= 0 ? [guide.numbers.indexOf(Number(n))] : [],
                     channelInfo: r => ({ number: guide.numbers[r], name: guide.channels[r].name }) }
  const watchSoon = { restart() {} }
  assert.equal(watch(guide, commands, watchSoon, "102").ok, true)
  // meanwhile: News moved into another category, after Films
  guide.channels = [guide.channels[1], guide.channels[2], guide.channels[0]]
  fired(guide, commands)
  assert.deepEqual(watched, ["u/kids"], "Kids comes on, as asked, wherever it is now")
  // meanwhile: the channel asked for was removed: nothing comes on
  watch(guide, commands, watchSoon, "101")                 // Kids again (row 0 now)
  guide.channels = [guide.channels[1], guide.channels[2]]
  fired(guide, commands)
  assert.deepEqual(watched, ["u/kids"], "removed meanwhile: no other channel comes on in its place")
  fired(guide, commands)
  assert.deepEqual(watched, ["u/kids"], "and it goes on once only")
}

console.log("multiview: ok")
