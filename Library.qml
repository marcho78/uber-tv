import QtQuick
import Quickshell
import Quickshell.Io

// On demand: the movies and series from your playlists (a playlist entry
// that's a video file goes here instead of the guide), the videos of your
// YouTube channels and your own (My Videos, Videos.qml), what you've watched
// and where you stopped, and My List.
// Kept in ~/.config/om-pg/library.json (the movies, My List) and
// history.json (where you stopped in each).
Scope {
  id: library

  required property var guide

  // [{ id, title, url, poster, description, genre, series, season, episode, year, source, added }]
  property var items: []
  // id -> { position, duration, updated, finished, title, subtitle, poster, kind, ref, owners, ownersMore }
  // (owners: a YouTube video's channels, by address, for the channel lock;
  // ownersMore: more than fit)
  property var history: ({})
  property var myList: []            // ids, newest first
  property bool loaded: false
  property bool historyLoaded: false
  // A file that couldn't be read is never saved over (the guide keeps
  // what it had, and says so: Guide.qml filesProblem)
  property bool libraryUnread: false
  property bool historyUnread: false
  readonly property string problem: libraryUnread || historyUnread
    ? (libraryUnread && historyUnread ? "Your library (library.json) and where you stopped (history.json) weren't read (not valid JSON): the guide keeps both files as they are"
       : libraryUnread ? "Your library (library.json) wasn't read (not valid JSON): the guide keeps that file as it is"
       : "Where you stopped (history.json) wasn't read (not valid JSON): the guide keeps that file as it is")
      + " (changes aren't saved until it's fixed or moved away, and the guide restarted)."
    : ""

  readonly property string path: guide.configDir + "/library.json"
  readonly property string historyPath: guide.configDir + "/history.json"
  readonly property int maxItems: 20000
  readonly property int maxHistory: 400
  readonly property int maxOwners: 100

  // A playlist entry that's a video file (or an IPTV provider's movie or
  // episode), not a live stream
  function isVodUrl(url) {
    var u = String(url || "").split(/[?#]/)[0].toLowerCase()
    return /\.(mp4|m4v|mkv|webm|mov|avi|wmv|flv|mpg|mpeg|ogv)$/.test(u) || /\/(movie|movies|series)\/[^\/]+\/[^\/]+\/[^\/]+$/.test(u)
  }

  // A short, steady id from a URL
  function idFor(url) {
    var a = 0x811c9dc5
    var b = 5381
    var s = String(url)
    for (var i = 0; i < s.length; i++) {
      var c = s.charCodeAt(i)
      a = Math.imul(a ^ c, 0x01000193) >>> 0
      b = (Math.imul(b, 33) + c) >>> 0
    }
    return "v" + a.toString(16) + b.toString(16)
  }

  // A playlist entry as a library item: its name, year, and series and
  // episode when the name says (Show S01E02, Show - S1 E2)
  function itemFrom(cand, source) {
    var name = String(cand.name || "").trim().slice(0, 200) || String(cand.url).split("/").pop()
    var ep = name.match(/^(.*?)[\s._-]*S(\d{1,2})[\s._-]*E(\d{1,3})\b[\s._-]*(.*)$/i)
    var year = name.match(/\((\d{4})\)/)
    return {
      id: library.idFor(cand.url), title: name, url: cand.url,
      poster: guide.isStreamUrl(cand.logo) ? cand.logo : "",
      description: String(cand.description || "").trim().slice(0, 800),
      genre: String(cand.category || "").slice(0, 40) || "Movies",
      series: ep ? ep[1].trim() : "", season: ep ? Number(ep[2]) : 0, episode: ep ? Number(ep[3]) : 0,
      year: year ? Number(year[1]) : 0, source: String(source || "").slice(0, 300), added: Math.floor(Date.now() / 1000)
    }
  }

  // Adds playlist entries; answers { added, already }. One already there
  // gets what it was missing (a poster, a description).
  function add(cands, source) {
    var at = {}
    for (var i = 0; i < library.items.length; i++) at[library.items[i].url] = i
    var list = library.items.slice()
    var fresh = []
    var already = 0
    var filled = false
    for (var c = 0; c < cands.length; c++) {
      var u = cands[c].url
      if (at[u] !== undefined) {
        already++
        if (at[u] < 0) continue
        var had = list[at[u]]
        var more = library.itemFrom(cands[c], source)
        if ((!had.description && more.description) || (!had.poster && more.poster)) {
          var both = {}
          for (var k in had) both[k] = had[k]
          if (!had.description) both.description = more.description
          if (!had.poster) both.poster = more.poster
          list[at[u]] = both
          filled = true
        }
        continue
      }
      at[u] = -1
      fresh.push(library.itemFrom(cands[c], source))
    }
    if (fresh.length || filled) {
      library.items = list.concat(fresh).slice(0, library.maxItems)
      library.save()
    }
    return { added: fresh.length, already: already }
  }

  function remove(ids) {
    var gone = {}
    for (var i = 0; i < ids.length; i++) gone[ids[i]] = true
    library.items = library.items.filter(function(it) { return !gone[it.id] })
    library.myList = library.myList.filter(function(id) { return !gone[id] })
    library.save()
  }

  function item(id) {
    for (var i = 0; i < library.items.length; i++) if (library.items[i].id === id) return library.items[i]
    return null
  }

  // The genres, in the order they came, with how many each
  readonly property var genres: {
    var seen = {}
    var out = []
    for (var i = 0; i < items.length; i++) {
      var g = items[i].genre
      if (!(g in seen)) { seen[g] = out.length; out.push({ genre: g, count: 0 }) }
      out[seen[g]].count++
    }
    return out
  }

  // ---- where you stopped -------------------------------------------------

  // Remembers where you are in something; finished when near its end
  function record(entry, position, duration) {
    if (!entry || !entry.id) return
    var h = {}
    for (var k in library.history) h[k] = library.history[k]
    var finished = duration > 0 && position >= duration - Math.min(90, duration * 0.05)
    // a YouTube video's channels: those it's on now, whoever asked, with the
    // kept ones; more than fit, if the record or the entry says so
    var was = h[entry.id] || {}
    var o = library.owners(was.owners, entry.kind === "youtube" && entry.videoId ? guide.videoOwners(entry.videoId, entry.owners) : entry.owners,
                           was.ownersMore === true || entry.ownersMore === true)
    h[entry.id] = { position: Math.max(0, Math.round(position)), duration: Math.round(duration || 0), updated: Math.floor(Date.now() / 1000),
                    finished: finished, title: entry.title || "", subtitle: entry.subtitle || "", poster: entry.poster || "",
                    kind: entry.kind || "", ref: entry.videoId || entry.url || "", owners: o.owners, ownersMore: o.more }
    var ids = Object.keys(h)
    if (ids.length > library.maxHistory) {
      ids.sort(function(a, b) { return h[a].updated - h[b].updated })
      for (var i = 0; i < ids.length - library.maxHistory; i++) delete h[ids[i]]
    }
    library.history = h
    historySaver.restart()
  }

  // A video's channels, by address: kept ones, then any new (a channel's lock
  // covers its videos after it's renamed or removed: Guide.qml videoLockedBy).
  // { owners, more }: at most maxOwners; more if any didn't fit, now or
  // before (wasMore), and then the lock fails closed for that video
  function owners(kept, more, wasMore) {
    var out = []
    var over = wasMore === true
    var all = (Array.isArray(kept) ? kept : []).concat(Array.isArray(more) ? more : [])
    for (var i = 0; i < all.length; i++) {
      var u = all[i]
      if (typeof u !== "string" || !u || u.length > 2048 || out.indexOf(u) >= 0) continue
      if (out.length >= library.maxOwners) { over = true; break }
      out.push(u)
    }
    return { owners: out, more: over }
  }

  // Older records, kept without their channels' addresses: ownersOf(record)
  // gives them, while they can still be found (Guide.qml fillVideoOwners)
  function fillOwners(ownersOf) {
    var h = null
    for (var id in library.history) {
      var r = library.history[id]
      if (r.kind !== "youtube" || (r.owners || []).length) continue
      var o = library.owners([], ownersOf(r), r.ownersMore)
      if (!o.owners.length) continue
      if (!h) { h = {}; for (var k in library.history) h[k] = library.history[k] }
      h[id] = Object.assign({}, r, { owners: o.owners, ownersMore: o.more })
    }
    if (!h) return
    library.history = h
    historySaver.restart()
  }

  // Where to start: where you stopped, unless that's the very start or the end
  function resumeAt(id) {
    var h = library.history[id]
    if (!h || h.finished || h.position < 30) return 0
    if (h.duration && h.position > h.duration - 60) return 0
    return h.position
  }

  // Takes something off Continue watching (and forgets where you were)
  function forget(id) {
    if (!library.history[id]) return
    var h = {}
    for (var k in library.history) if (k !== id) h[k] = library.history[k]
    library.history = h
    historySaver.restart()
  }

  // Settings: forget where you stopped in everything; empty My List
  function forgetAll() {
    library.history = ({})
    historySaver.restart()
  }

  function emptyList() {
    library.myList = []
    library.save()
  }

  function progress(id) {
    var h = library.history[id]
    return h && h.duration ? Math.min(1, h.position / h.duration) : 0
  }

  // What you started and didn't finish, newest first
  function unfinished(kind) {
    var out = []
    for (var id in library.history) {
      var h = library.history[id]
      if (h.finished || h.position < 30 || (kind && h.kind !== kind)) continue
      out.push({ id: id, title: h.title, subtitle: h.subtitle, poster: h.poster, kind: h.kind, ref: h.ref, owners: h.owners, updated: h.updated,
                 progress: h.duration ? h.position / h.duration : 0 })
    }
    return out.sort(function(a, b) { return b.updated - a.updated }).slice(0, 30)
  }

  // ---- My List -------------------------------------------------------------

  function inList(id) { return library.myList.indexOf(id) >= 0 }

  function toggleList(entry) {
    if (library.inList(entry.id)) library.myList = library.myList.filter(function(x) { return x !== entry.id })
    else {
      library.myList = [entry.id].concat(library.myList).slice(0, 500)
      // a YouTube video isn't in the library: remember enough to show it
      if (!library.item(entry.id) && !library.history[entry.id]) library.record(entry, 0, entry.duration || 0)
    }
    library.save()
    return library.inList(entry.id)
  }

  // ---- saving and loading --------------------------------------------------

  function save() { saver.restart() }

  Timer {
    id: saver
    interval: 400
    onTriggered: if (!library.guide.wiping && !library.libraryUnread) libraryFile.setText(JSON.stringify({ version: 1, items: library.items, myList: library.myList }) + "\n")
  }

  Timer {
    id: historySaver
    interval: 2000
    onTriggered: if (!library.guide.wiping && !library.historyUnread) historyFile.setText(JSON.stringify(library.history) + "\n")
  }

  // Saved right away (closing the guide, stopping a video)
  function flush() {
    if (library.guide.wiping) { historySaver.stop(); saver.stop(); return }   // a restore or a reset: they're being replaced
    if (historySaver.running && !library.historyUnread) { historySaver.stop(); historyFile.setText(JSON.stringify(library.history) + "\n") }
    if (saver.running && !library.libraryUnread) { saver.stop(); libraryFile.setText(JSON.stringify({ version: 1, items: library.items, myList: library.myList }) + "\n") }
  }

  function clean(raw) {
    var out = []
    var seen = {}
    var list = raw && Array.isArray(raw.items) ? raw.items : []
    for (var i = 0; i < list.length && out.length < library.maxItems; i++) {
      var it = list[i]
      if (!it || !guide.isStreamUrl(it.url) || seen[it.url]) continue
      seen[it.url] = true
      out.push({ id: library.idFor(it.url), title: String(it.title || "").slice(0, 200) || "Untitled", url: it.url,
                 poster: guide.isStreamUrl(it.poster) ? it.poster : "", description: String(it.description || "").slice(0, 800),
                 genre: String(it.genre || "").slice(0, 40) || "Movies", series: String(it.series || "").slice(0, 200),
                 season: Number(it.season) || 0, episode: Number(it.episode) || 0, year: Number(it.year) || 0,
                 source: String(it.source || "").slice(0, 300), added: Number(it.added) || 0 })
    }
    return out
  }

  // What you watch is yours alone: both files readable by you only
  Process {
    id: privateFiles
    command: ["/usr/bin/sh", "-c", "PATH=/usr/bin; for f in \"$@\"; do [ -f \"$f\" ] && chmod 600 -- \"$f\"; done; true", "sh", library.path, library.historyPath]
  }

  FileView {
    id: libraryFile
    path: library.path
    printErrors: false
    onSaved: privateFiles.running = true
    onLoaded: {
      try {
        var raw = JSON.parse(text())
        if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("not an object")
        library.items = library.clean(raw)
        library.myList = Array.isArray(raw.myList) ? raw.myList.filter(function(x) { return typeof x === "string" && /^(v[0-9a-f]+|yt:[A-Za-z0-9_-]{11})$/.test(x) }) : []
        library.libraryUnread = false
      } catch (e) { console.warn("om-pg: " + library.path + " is not valid JSON"); library.libraryUnread = true }
      library.loaded = true
    }
    onLoadFailed: library.loaded = true
  }

  FileView {
    id: historyFile
    path: library.historyPath
    printErrors: false
    onSaved: privateFiles.running = true
    onLoaded: {
      var h = {}
      try {
        var raw = JSON.parse(text())
        if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("not an object")
        for (var id in raw) {
          var e = raw[id]
          if (!e || typeof e !== "object" || !/^(v[0-9a-f]+|yt:[A-Za-z0-9_-]{11})$/.test(id)) continue
          h[id] = { position: Number(e.position) || 0, duration: Number(e.duration) || 0, updated: Number(e.updated) || 0, finished: e.finished === true,
                    title: String(e.title || "").slice(0, 200), subtitle: String(e.subtitle || "").slice(0, 200),
                    poster: guide.isStreamUrl(e.poster) ? e.poster : "", kind: ["movie", "youtube", "file"].indexOf(e.kind) >= 0 ? e.kind : "",
                    ref: String(e.ref || "").slice(0, 2048) }
          var o = library.owners(e.owners, [], e.ownersMore)
          h[id].owners = o.owners
          h[id].ownersMore = o.more
        }
        library.historyUnread = false
      } catch (e) { console.warn("om-pg: " + library.historyPath + " is not valid JSON"); library.historyUnread = true }
      library.history = h
      library.historyLoaded = true
    }
    onLoadFailed: library.historyLoaded = true
  }
}
