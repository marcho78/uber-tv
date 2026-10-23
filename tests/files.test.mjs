// Your channel list (channels.json) is never saved over when it couldn't be
// read: the guide shows its starter channels, keeps that file as it is, and
// says so (filesProblem). Guide.qml can't load outside the shell, so its own
// code is read and run over a stand-in guide, as tests/look.test.mjs does:
// node tests/files.test.mjs
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const guideSrc = readFileSync(new URL("../Guide.qml", import.meta.url), "utf8")
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
const ownListSrc = guideSrc.slice(guideSrc.indexOf("id: ownList"))
const loadChannels = new Function("root", "raw", block(guideSrc, "function loadChannels("))
const saveChannels = new Function("root", "ownList", "cacheTimer", block(guideSrc, "function saveChannels("))
const onLoaded = new Function("root", "text", block(ownListSrc, "onLoaded: {"))
const onLoadFailed = new Function("root", block(ownListSrc, "onLoadFailed: {"))

const starter = JSON.stringify([{ name: "Starter", url: "https://www.youtube.com/@starter" }])
function guide() {
  const written = []
  const root = {
    channels: [], lastSaved: "", listProblem: "", ownListMissing: false, wiping: false, opened: false,
    listPath: "/home/u/.config/om-pg/channels.json", defaultList: starter,
    isStreamUrl: u => /^https?:\/\//.test(u || ""), isYouTube: u => /youtube\.com/.test(u || ""),
    iptvChannel: (name, url, category) => ({ name, url, category, kind: "iptv" }),
    changed: (had, c) => Object.assign({}, had, c), setChannels: list => { root.channels = list },
    applyCache() {}, fetchMissing() {}, migrateVod() {},
  }
  root.loadChannels = raw => loadChannels(root, raw)
  root.save = () => saveChannels(root, { setText: t => written.push(t) }, { restart() {} })
  root.loaded = text => onLoaded(root, () => text)
  return { root, written }
}

const warn = console.warn
console.warn = () => {}
try {
  {
    const { root, written } = guide()
    root.loaded('[{"name": "Mine", "url": "https://www.youtube.com/@mine"}]')
    assert.equal(root.listProblem, "")
    assert.deepEqual(root.channels.map(c => c.name), ["Mine"])
    root.save()
    assert.equal(written.length, 1, "a list that was read is saved")
  }
  for (const bad of ['[{"name": "Mine", "url": ', "{}", "null", '"x"']) {
    const { root, written } = guide()
    root.loaded(bad)
    assert.match(root.listProblem, /wasn't read/, "unreadable: " + JSON.stringify(bad))
    assert.deepEqual(root.channels.map(c => c.name), ["Starter"], "the starter channels to watch: " + JSON.stringify(bad))
    root.channels = root.channels.concat([{ name: "Added", url: "https://www.youtube.com/@added" }])
    root.save()
    assert.deepEqual(written, [], "an unreadable list is never saved over: " + JSON.stringify(bad))

    // fixed by hand: read again, saved again
    root.loaded('[{"name": "Fixed", "url": "https://www.youtube.com/@fixed"}]')
    assert.equal(root.listProblem, "")
    root.save()
    assert.equal(written.length, 1, "a list fixed by hand is saved again")
  }
  {
    // moved away: no list, so the starter one, and saving is fine
    const { root, written } = guide()
    root.loaded("nope")
    onLoadFailed(root)
    assert.equal(root.listProblem, "")
    assert.equal(root.ownListMissing, true)
    root.save()
    assert.equal(written.length, 1, "a list moved away doesn't stop saving")
  }
  // the problem is shown in Settings → Files and to agents
  assert.match(guideSrc, /readonly property string filesProblem: \[root\.settingsProblem, root\.listProblem, library\.problem\]/)
  assert.match(guideSrc, /if \(key === "files"\) return root\.filesProblem \?/)
} finally {
  console.warn = warn
}
console.log("files: all good")
