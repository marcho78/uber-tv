import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtMultimedia
import qs.Commons
import "Schedule.js" as Schedule
import "Look.js" as Look
import "AppLooks.js" as AppLooks
import "Shortcut.js" as Shortcut
import "Awake.js" as AwakeRules
import "Saver.js" as SaverRules
import "ChannelLock.js" as LockRules
import "Dvr.js" as DvrRules
import "Timeshift.js" as Ts
import "ui"

// The guide: a full-screen, old-school program grid of YouTube channels with
// the TV built in. Tuning a channel plays whatever it is "airing" right now,
// joined partway through like live TV, in the preview box or full screen.
// Video comes from bin/om-pg-streamer, which hands Qt's player a YouTube
// stream it can play and seek.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool watching: false

  // [{ name, url, category, items, state, channelId, live }], state being
  // "loading", "ready" or "error", live { id, title } while the channel is
  // streaming live. Kept grouped by category, in order.
  property var channels: []

  // Cable-style numbers: uncategorized channels 1–99, then each category
  // its own hundred (101…, 201…), so filtering never renumbers anything.
  readonly property var numbers: {
    var blocks = {}
    var next = 1
    var count = {}
    var out = []
    for (var i = 0; i < channels.length; i++) {
      var c = channels[i].category || ""
      if (!(c in blocks)) blocks[c] = c ? next++ : 0
      count[c] = (count[c] || 0) + 1
      out.push(blocks[c] * 100 + count[c])
    }
    return out
  }
  readonly property var categories: {
    var seen = {}
    var out = []
    for (var i = 0; i < channels.length; i++) {
      var c = channels[i].category || ""
      if (!(c in seen)) { seen[c] = true; out.push(c) }
    }
    return out
  }
  readonly property bool hasCategories: categories.length > 1 || (categories.length === 1 && categories[0] !== "")

  // The categories to show; none listed means all. Remembered in settings.json.
  property var shownCategories: []
  // Channel logos (L), off unless asked for. Also in settings.json.
  property bool showLogos: true
  // The phone remote (T): off unless turned on, and only after agreeing to
  // what it opens. See bin/om-pg-remote. Enabled, port and the firewall
  // rules it added are kept in settings.json.
  property bool remoteEnabled: false
  property int remotePort: 24750
  property var remoteRules: []        // "subnet port" rules this guide added to the firewall
  property var remoteNet: null        // { address, subnet, hostname, port }
  property bool remoteReady: false
  property bool remoteStopping: false
  property string remoteStep: ""      // "", "confirm", "firewall", "on", "off"
  property string firewallFor: ""     // why the password prompt is up: "allow" or "remove"
  property var remotePairing: null    // { code, url, qr, expires }
  property var remoteDevices: []
  property int remoteCursor: 0
  property string remoteArmed: ""       // a phone waiting for its second Enter to be unpaired
  property string remoteMessage: ""
  property bool firewallActive: false
  property bool firewallBusy: false
  property real remoteClock: Date.now() / 1000
  readonly property bool remoteAllowedHere: !firewallActive || (!!remoteNet && remoteRules.indexOf(remoteNet.subnet + " " + remotePort) >= 0)

  // The key hints under the guide (K), on unless hidden. Also in settings.json.
  property bool showKeyHints: true
  // the splash when Uber TV turns on (Settings → General), and whether it's
  // off now: closed with nothing playing on (the mini player keeps it on)
  property bool splashOn: true
  // the credits at the foot of the nav rail (Settings → About). In settings.json.
  property bool railCredits: true
  property bool tvOff: true
  readonly property var splash: splashItem
  // Uber TV's own updates (Updates.qml), and the release notes box's scrolling
  readonly property var updates: updatesItem
  signal scrollNotes(real by)
  // Backups, restore and reset (Backups.qml). While a restore or a reset is
  // under way, nothing of Uber TV writes its files: they're being replaced
  readonly property var backups: backupsItem
  property bool wiping: false
  // the firewall rule taken out or not: told to whoever asked (a reset)
  property var firewallThen: null
  property string firewallRule: ""
  property bool keyHintsNote: false   // "hidden; K shows them" for a moment after hiding

  // The mini player (P): the TV in a small window on top, while you work.
  // Where it sits and how big it is are remembered in settings.json.
  property bool pip: false
  property real pipW: 0             // 0: a quarter of the screen's width
  property real pipRight: 24
  property real pipBottom: 24
  property bool pipBannerShown: false
  // Whether the pointer is over the mini player, from asking Hyprland: hover
  // events alone get stuck (closing it with the pointer over it, then
  // reopening it elsewhere), and a stuck one would keep the keyboard.
  property bool pipPointerIn: false
  // The channels in the grid, by index into channels.
  // Which sources to show (F): "both", "youtube" or "iptv". In settings.json.
  property string shownSource: "both"
  property string sourceDraft: "both"
  readonly property bool hasIptv: channels.some(function(c) { return c.kind === "iptv" })
  readonly property int sourceRow: hasIptv ? 1 : 0   // the filter box's source line, when there are IPTV channels
  readonly property var visibleRows: {
    var all = []
    var out = []
    for (var i = 0; i < channels.length; i++) {
      all.push(i)
      var c = channels[i]
      var source = c.kind === "iptv" ? "iptv" : "youtube"
      if (hasIptv && shownSource !== "both" && source !== shownSource) continue
      if (!shownCategories.length || shownCategories.indexOf(c.category || "") >= 0) out.push(i)
    }
    return out.length ? out : all
  }
  readonly property bool filtered: visibleRows.length < channels.length
  property real fetchedAt: 0
  property real liveCheckedAt: 0     // when every channel was last asked what's live (not saved: none at start)
  readonly property int staleAfter: 3 * 3600

  property real now: Date.now() / 1000
  readonly property int liveBucket: Math.floor(now / 900)   // quarters of an hour: a live stream's picture is asked for again in each
  readonly property int slot: 1800
  readonly property int slotsShown: Math.round(layout.hours * 2)
  readonly property int span: slot * slotsShown
  readonly property int maxSlotOffset: 24
  property int slotOffset: 0
  readonly property real windowStart: slotStart(now) + slotOffset * slot
  // The half hour a moment falls in, by the clock here: on the hour and half
  // past where the time zone is a quarter hour off too (UTC+5:45)
  function slotStart(t) {
    var off = -new Date(t * 1000).getTimezoneOffset() * 60
    return Math.floor((t + off) / root.slot) * root.slot - off
  }
  readonly property real windowEnd: windowStart + span

  property int row: 0
  // The time the cursor sits at, so moving between channels keeps its place.
  property real cursorTime: now
  readonly property real cursorAt: Math.max(windowStart, Math.min(windowEnd - 1, cursorTime))
  readonly property var selected: showAt(row, cursorAt)

  // Which screen the guide shows: the program guide, or the library (V)
  property string screen: "guide"
  property string libraryTab: "movies"   // movies, ondemand, videos, recordings, mylist
  // The library's tabs, in their order (yours, or an agent's: setLibraryTabs):
  // My Videos only while it's on, Recordings while it's on or there are some
  readonly property var libraryTabKinds: [{ key: "movies", label: "Movies & Series" }, { key: "ondemand", label: "On Demand" },
                                          { key: "videos", label: "My Videos" }, { key: "recordings", label: "Recordings" }, { key: "mylist", label: "My List" }]
  property var libraryOrder: []           // tab keys in your order; the rest follow in theirs
  readonly property var libraryTabs: checkedLibraryOrder(libraryOrder).map(function(k) { return libraryTabKinds.filter(function(t) { return t.key === k })[0] })
                                     .filter(function(t) { return libraryTabShown(t.key) })
  function libraryTabShown(key) {
    return key === "videos" ? videos.enabled : key === "recordings" ? dvr.settings.on || dvr.recordings.length > 0 : true
  }
  // Tab keys from settings or a command: known ones once each, in that order, then the others in theirs
  function checkedLibraryOrder(given) {
    var known = libraryTabKinds.map(function(t) { return t.key })
    var out = []
    var list = Array.isArray(given) ? given : []
    for (var i = 0; i < list.length; i++) if (known.indexOf(list[i]) >= 0 && out.indexOf(list[i]) < 0) out.push(list[i])
    for (var k = 0; k < known.length; k++) if (out.indexOf(known[k]) < 0) out.push(known[k])
    return out
  }
  property int libRow: 0
  property var libCols: ({})             // row key -> where the cursor was in it
  property var libDetail: null           // the card whose details are open
  property int libEpisode: 0             // the episode under the cursor, in a series' details

  // The library's rows for the tab that's open: [{ key, title, shape:
  // "poster"|"thumb", cards: [{ id, kind, title, sub, poster, videoId,
  // entry, episodes }] }]
  readonly property var libraryRows: {
    var rows = []
    if (libraryTab === "movies") {
      var going = library.unfinished("movie").map(function(h) {
        var it = library.item(h.id)
        return it ? root.movieCard(it) : null
      }).filter(function(c) { return c })
      if (going.length) rows.push({ key: "continue-movies", title: "Continue watching", shape: "poster", cards: going })
      var byGenre = {}
      var order = []
      var series = {}
      for (var i = 0; i < library.items.length; i++) {
        var it = library.items[i]
        if (!(it.genre in byGenre)) { byGenre[it.genre] = []; order.push(it.genre) }
        if (it.series) {
          var sk = it.genre + "|" + it.series.toLowerCase()
          if (!series[sk]) {
            series[sk] = { id: "s:" + sk, kind: "series", title: it.series, sub: "", poster: it.poster, episodes: [] }
            byGenre[it.genre].push(series[sk])
          }
          series[sk].episodes.push(it)
        } else byGenre[it.genre].push(root.movieCard(it))
      }
      for (var s in series) {
        series[s].episodes.sort(function(a, b) { return a.season - b.season || a.episode - b.episode })
        series[s].sub = series[s].episodes.length + (series[s].episodes.length === 1 ? " episode" : " episodes")
      }
      for (var g = 0; g < order.length; g++) rows.push({ key: "g:" + order[g], title: order[g], shape: "poster", cards: byGenre[order[g]] })
    } else if (libraryTab === "ondemand") {
      var watching = library.unfinished("youtube").filter(function(h) { return !root.videoLockedBy(h.ref || h.id, h.subtitle) })
                            .map(function(h) { return root.videoCardFrom(h.id, h.title, h.subtitle, h.ref, h.duration) })
      if (watching.length) rows.push({ key: "continue-videos", title: "Continue watching", shape: "thumb", cards: watching })
      for (var c = 0; c < channels.length; c++) {
        var ch = channels[c]
        if (ch.kind === "iptv" || !ch.items || !ch.items.length || channelLockItem.blocks(ch)) continue
        // a video that's also on a locked channel is locked with it
        rows.push({ key: "c:" + ch.url, title: ch.name, shape: "thumb",
                    cards: ch.items.filter(function(v) { return !root.videoLockedBy(v.id) }).slice(0, 80)
                             .map(function(v) { return root.videoCardFrom("yt:" + v.id, v.title, ch.name, v.id, v.duration) }) })
      }
    } else if (libraryTab === "recordings") {
      // what needs you first, then what's recording, then what's recorded
      var groups = DvrRules.rows(dvr.recordings)
      for (var gi = 0; gi < groups.length; gi++)
        rows.push({ key: groups[gi].key, title: groups[gi].title, shape: "thumb", cards: groups[gi].list.map(root.recordingCard) })
    } else if (libraryTab === "videos") {
      var started = library.unfinished("file").map(function(h) {
        var v = videos.item(h.id)
        return v ? root.fileCard(v) : null
      }).filter(function(c) { return c })
      if (started.length) rows.push({ key: "continue-files", title: "Continue watching", shape: "thumb", cards: started })
      var folders = videos.folders
      for (var f = 0; f < folders.length; f++)
        rows.push({ key: "f:" + folders[f].folder, title: folders[f].folder || videos.usedFolder.split("/").pop() || "Videos", shape: "thumb",
                    cards: folders[f].items.slice(0, 400).map(root.fileCard) })
    } else {
      var movies = []
      var clips = []
      var files = []
      for (var m = 0; m < library.myList.length; m++) {
        var id = library.myList[m]
        var item = library.item(id)
        if (item) { movies.push(root.movieCard(item)); continue }
        var file = videos.enabled ? videos.item(id) : null
        if (file) { files.push(root.fileCard(file)); continue }
        var e = root.entryFor(id)
        if (e && e.videoId && !root.videoLockedBy(e.videoId, e.subtitle, e.owners, e.ownersMore)) clips.push(root.videoCardFrom(id, e.title, e.subtitle, e.videoId, e.duration))
      }
      if (movies.length) rows.push({ key: "list-movies", title: "Movies & series", shape: "poster", cards: movies })
      if (clips.length) rows.push({ key: "list-videos", title: "Videos", shape: "thumb", cards: clips })
      if (files.length) rows.push({ key: "list-files", title: "My Videos", shape: "thumb", cards: files })
    }
    return rows
  }

  function movieCard(it) {
    return { id: it.id, kind: "movie", title: it.title.replace(/\s*\((\d{4})\)\s*$/, ""), sub: [it.year ? String(it.year) : "", it.series ? "S" + it.season + " E" + it.episode : ""].filter(function(x) { return x }).join(" · "),
             poster: it.poster, shape: "poster", entry: root.movieEntry(it), when: it.added || 0 }
  }

  function videoCardFrom(id, title, channelName, videoId, duration) {
    var mins = Math.round((duration || 0) / 60)
    var kept = library.history["yt:" + videoId] || {}
    return { id: id, kind: "youtube", title: title, sub: (channelName ? channelName + " · " : "") + (mins ? mins + " min" : ""), videoId: videoId, shape: "wide",
             entry: { id: id, kind: "youtube", title: title, subtitle: channelName || "", poster: "", videoId: videoId, duration: duration || 0,
                      owners: root.videoOwners(videoId, kept.owners), ownersMore: kept.ownersMore === true } }
  }

  // A recording (DVR.qml), as a card: a locked channel's shows no picture or
  // description, nor its title while the lock hides titles
  function recordingCard(rec) {
    var hide = dvr.hidden(rec)
    var locked = dvr.locked(rec)
    var name = (rec.channel || {}).name || ""
    var title = hide ? "Locked recording" : (rec.titles && rec.titles.length > 1 ? rec.titles.join(" · ") : rec.title || name || "Recording")
    // one still to come (or missed) goes by its show's times
    var later = (DvrRules.waiting(rec) || rec.state === "missed") && !!rec.show
    var when = later ? rec.show.start : rec.started || rec.created || 0
    var going = DvrRules.active(rec)
    var sub = hide ? "" : [name, when ? root.dayTime(when) + (later ? " – " + root.clock(rec.show.end) : "") : "",
                          later ? "" : going ? (rec.kind === "youtube-video" ? "saving" : "until " + root.clock(rec.end)) : root.lengthLabel(rec.duration)].filter(function(x) { return x }).join(" · ")
    var entry = DvrRules.playable(rec) ? root.recordingEntry(rec, title, hide, locked) : null
    var from = rec.started || rec.created || 0
    var ch = locked ? null : dvr.channelOf(rec)
    return { id: entry ? entry.id : "rec:" + rec.id, kind: "recording", rec: rec, title: title, sub: sub, poster: locked ? "" : (rec.thumb || ""), shape: "wide",
             logo: ch ? root.logoFor(ch) : "",   // shown until (or without) its picture
             entry: entry, recState: DvrRules.stateOf(rec), recProgress: going && rec.end > from ? Math.max(0, Math.min(1, (root.now - from) / (rec.end - from))) : 0, when: when }
  }

  // "Today, 9:00 PM", "Tomorrow, 8:30 AM", "Fri, 9:00 PM", "Oct 19, 9:00 PM"
  function dayTime(t) {
    var d = new Date(t * 1000), today = new Date()
    today.setHours(0, 0, 0, 0)
    var days = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - today) / 86400000)
    return (days === 0 ? "Today" : days === 1 ? "Tomorrow" : days > 1 && days < 7 ? Qt.formatDateTime(d, "ddd") : Qt.formatDateTime(d, "MMM d")) + ", " + root.clock(t)
  }

  function recordingEntry(rec, title, hide, locked) {
    var url = root.fileUrl(rec.path)
    return { id: library.idFor(url), kind: "file", title: title, subtitle: [hide ? "" : (rec.channel || {}).name, "Recording", root.lengthLabel(rec.duration)].filter(function(x) { return x }).join(" · "),
             poster: locked ? "" : rec.thumb || "", url: url, duration: rec.duration || 0, description: locked ? "" : rec.desc || "",
             recId: rec.id, recHash: (rec.channel || {}).hash || "" }
  }

  // A recording's card from the library or Home: played (a locked channel's
  // asks for its passcode first), or, while it records, its channel live
  function playRecording(card, fromStart) {
    var rec = dvr.byId[card.rec.id] || card.rec
    if (DvrRules.active(rec)) {
      var ch = dvr.channelOf(rec)
      var r = ch ? root.channels.indexOf(ch) : -1
      if (r < 0) return "that channel isn't in the guide"
      root.libDetail = null
      root.row = r
      root.watch(r)
      return "ok"
    }
    var c = root.recordingCard(rec)
    if (!c.entry) return "nothing to play"
    var lockCh = dvr.lockChannelOf(rec)
    if (lockCh && channelLockItem.blocks(lockCh)) {
      if (!root.opened) root.summonGuide(false)
      channelLockItem.askUnlock(lockCh, function() { root.playRecording(card, fromStart) })
      return "asked for the passcode"
    }
    root.libDetail = null
    root.playVod(c.entry, fromStart ? 0 : undefined)
    return "ok"
  }

  // A recording's choices, in its details (OK on its card): ↑ ↓ choose, OK picks
  property string recArmed: ""            // a recording waiting for its second OK to be deleted
  readonly property string recordingsPlace: dvr.placeLabel
  readonly property var recorder: dvr        // for Commands.qml
  readonly property var libDetailRec: libDetail && libDetail.kind === "recording" ? dvr.byId[libDetail.rec.id] || libDetail.rec : null
  // its card as it is now (stopped, done), not as it was when its details opened
  readonly property var libDetailRecCard: libDetailRec ? recordingCard(libDetailRec) : null
  readonly property var recActions: {
    var rec = libDetailRec
    if (!rec) return []
    var deleting = recArmed === rec.id
    var series = dvr.ruleOf(rec) ? [{ key: "stopSeries", label: "Stop recording this series" }] : []
    if (DvrRules.active(rec))
      return dvr.stopping[rec.id] ? [{ key: "none", label: "Stopping…" }]
           : rec.kind === "youtube-video" ? [{ key: "stop", label: "Stop saving" }]
           : [{ key: "watch", label: "Watch live" }, { key: "stop", label: "Stop recording" }].concat(series)
    // still to come (or a conflict): cancel it, its series, or watch its channel now
    if (DvrRules.waiting(rec))
      return [{ key: "cancel", label: "Cancel recording" }].concat(series).concat([{ key: "channel", label: "Watch " + ((rec.channel || {}).name || "the channel") + " now" }])
    if (rec.state === "missed")
      return series.concat([{ key: "delete", label: deleting ? "OK again" : "Take it off the list…", danger: true }])
    if (DvrRules.playable(rec)) {
      var at = root.libResumeAt(root.recordingCard(rec).id)
      return [{ key: "play", label: at > 0 ? "Resume" : "Play" }].concat(at > 0 ? [{ key: "start", label: "Start over" }] : []).concat(series)
             .concat([{ key: "delete", label: deleting ? "OK again to delete it" : "Delete recording…", danger: true }])
    }
    if (DvrRules.stateOf(rec) === "Drive missing")
      return [{ key: "delete", label: deleting ? "OK again (the file stays on the drive)" : "Take it off the list…", danger: true }]
    return [{ key: "delete", label: deleting ? "OK again to delete it" : "Delete…", danger: true }]
  }
  function recAct(i) {
    var a = root.recActions[i === undefined ? root.libEpisode : i]
    var rec = root.libDetailRec
    if (!a || !rec) return
    if (a.key !== "delete") root.recArmed = ""
    if (a.key === "play" || a.key === "watch") root.playRecording(root.libDetail, false)
    else if (a.key === "start") root.playRecording(root.libDetail, true)
    else if (a.key === "stop") dvr.stop(rec.id)
    else if (a.key === "cancel") { root.libDetail = null; dvr.cancel(rec.id) }
    else if (a.key === "stopSeries") {
      var rule = dvr.ruleOf(rec)
      if (!rule) return
      if (DvrRules.waiting(rec)) root.libDetail = null   // still to come, it goes with the series, as Cancel's
      dvr.stopSeries(rule.id)
    }
    else if (a.key === "channel") {
      var ch = dvr.channelByHash(rec.channel, rec.provider)
      var r = ch ? root.channels.indexOf(ch) : -1
      if (r >= 0) { root.libDetail = null; root.row = r; root.watch(r) }
    }
    else if (a.key === "delete") {
      if (root.recArmed !== rec.id) { root.recArmed = rec.id; return }
      root.recArmed = ""
      root.libDetail = null
      dvr.remove(rec.id)
    }
  }
  onLibDetailChanged: { recArmed = ""; if (libDetail && libDetail.kind === "recording") dvr.refresh() }

  // OK (or Enter, Space) in an item's details: a recording's choice, or play
  function libDetailOk() {
    if (root.libDetail && root.libDetail.kind === "recording") root.recAct()
    else root.libPlay(false)
  }

  // A video of yours (My Videos), as a card and as something to play
  function fileCard(v) {
    return { id: v.id, kind: "file", title: v.title, sub: [root.lengthLabel(v.duration), Qt.formatDateTime(new Date(v.mtime * 1000), "MMM d")].filter(function(x) { return x }).join(" · "),
             poster: v.thumb, shape: "wide", entry: root.fileEntry(v), when: v.mtime }
  }

  function fileEntry(v) {
    var home = Quickshell.env("HOME")
    var shown = v.path.indexOf(home + "/") === 0 ? "~" + v.path.slice(home.length) : v.path
    return { id: v.id, kind: "file", title: v.title, subtitle: ["My Videos", v.folder, root.lengthLabel(v.duration)].filter(function(x) { return x }).join(" · "),
             poster: v.thumb, url: root.fileUrl(v.path), duration: v.duration, description: shown + " · " + root.sizeLabel(v.size) }
  }

  function lengthLabel(seconds) {
    var t = Math.round(seconds || 0)
    if (!t) return ""
    if (t < 60) return t + " s"
    var h = Math.floor(t / 3600)
    var m = Math.round((t % 3600) / 60)
    return h ? h + " h " + m + " min" : m + " min"
  }

  function sizeLabel(bytes) {
    var b = Number(bytes) || 0
    return b >= 1e9 ? (b / 1e9).toFixed(1) + " GB" : b >= 1e6 ? Math.round(b / 1e6) + " MB" : Math.max(1, Math.round(b / 1e3)) + " KB"
  }

  function libraryIdFor(url) { return library.idFor(url) }
  function myVideos() { return videos.items }
  function myVideoFolders() { return videos.enabled ? videos.folders.map(function(f) { return f.folder || "." }) : [] }
  function videosOn() { return videos.enabled }
  readonly property bool videosScanning: videos.scanning
  readonly property bool videosMissing: videos.missing
  readonly property string videosFolder: videos.usedFolder

  readonly property var libCard: {
    var row = libraryRows[libRow]
    if (!row) return null
    return row.cards[Math.min(row.cards.length - 1, libCols[row.key] || 0)] || null
  }

  property string libraryFrom: "guide"
  function openLibrary(tab) {
    if (!root.vod && root.reception !== "off" && !root.pip && !root.watching) root.turnOff()   // the preview stops: nothing plays under the library
    if (root.libraryTabs.some(function(t) { return t.key === tab })) root.libraryTab = tab
    else if (!root.libraryTabs.some(function(t) { return t.key === root.libraryTab })) root.libraryTab = "movies"
    if (root.libraryTab === "videos") videos.freshen()
    if (root.libraryTab === "recordings") dvr.refresh()
    if (root.screen !== "library") root.libraryFrom = root.screen
    root.screen = "library"
    root.libDetail = null
    root.libRow = Math.max(0, Math.min(root.libRow, root.libraryRows.length - 1))
    keys.forceActiveFocus()
  }

  // Back from the library to where it was opened from
  function leaveLibrary() {
    if (root.libraryFrom === "home" && root.homeEnabled) root.openHome()
    else root.closeLibrary()
  }

  // To the program guide (from the library, or Home)
  function closeLibrary() {
    root.screen = "guide"
    root.libDetail = null
    keys.forceActiveFocus()
    previewTimer.restart()
    Qt.callLater(function() { root.showRow(root.row) })
  }

  function libTab(d) {
    var tabs = root.libraryTabs.map(function(t) { return t.key })
    root.libraryTab = tabs[(Math.max(0, tabs.indexOf(root.libraryTab)) + d + tabs.length) % tabs.length]
    if (root.libraryTab === "videos") videos.freshen()
    if (root.libraryTab === "recordings") dvr.refresh()
    root.libRow = 0
    root.libDetail = null
  }

  function moveLib(dRow, dCol) {
    var rows = root.libraryRows
    if (!rows.length) return
    if (dRow) root.libRow = Math.max(0, Math.min(rows.length - 1, root.libRow + dRow))
    if (dCol) {
      var row = rows[root.libRow]
      var cols = {}
      for (var k in root.libCols) cols[k] = root.libCols[k]
      cols[row.key] = Math.max(0, Math.min(row.cards.length - 1, (cols[row.key] || 0) + dCol))
      root.libCols = cols
    }
  }

  function libEnter() {
    if (!root.libCard) return
    root.libDetail = root.libCard
    root.libEpisode = 0
    if (root.libCard.kind === "series") {   // the first episode not yet finished
      var eps = root.libCard.episodes
      for (var i = 0; i < eps.length; i++) if (!(library.history[eps[i].id] || {}).finished) { root.libEpisode = i; break }
    }
  }

  function libEpisodeMove(d) {
    if (root.libDetail && root.libDetail.kind === "recording") {
      root.libEpisode = Math.max(0, Math.min(root.recActions.length - 1, root.libEpisode + d))
      if (root.recActions[root.libEpisode] && root.recActions[root.libEpisode].key !== "delete") root.recArmed = ""
      return
    }
    if (!root.libDetail || root.libDetail.kind !== "series") return
    root.libEpisode = Math.max(0, Math.min(root.libDetail.episodes.length - 1, root.libEpisode + d))
  }

  // Plays what's under the cursor (or in the open details): from where you
  // stopped, or from the start
  function libPlay(fromStart) {
    var card = root.libDetail || root.libCard
    if (!card) return
    if (card.kind === "recording") return root.playRecording(card, fromStart)
    var entry = card.kind === "series" ? root.movieEntry(card.episodes[root.libDetail ? root.libEpisode : 0]) : card.entry
    root.libDetail = null
    root.playVod(entry, fromStart ? 0 : undefined)
  }

  function libToggleList() {
    var card = root.libDetail || root.libCard
    if (!card) return
    if (card.kind === "recording") return   // recordings aren't put on My List (the footer has no L there)
    var entry = card.kind === "series" ? root.movieEntry(card.episodes[root.libEpisode] || card.episodes[0]) : card.entry
    if (!entry) return
    library.toggleList(entry)
  }

  // X on Continue watching: off it
  function libForget() {
    var row = root.libraryRows[root.libRow]
    if (!row || row.key.indexOf("continue") !== 0 || !root.libCard) return
    library.forget(root.libCard.id)
  }

  // From outside, by id: omarchy-shell shell call marcho78.om-pg forgetWatched <id>
  function forgetWatched(id) { library.forget(String(id)); return "ok" }
  function toggleMyList(id) {
    var e = root.entryFor(id)
    return e ? String(library.toggleList(e)) : "nothing with that id"
  }

  function inLibraryList(id) { return library.inList(id) }
  function libProgress(id) { return library.progress(id) }
  function libFinished(id) { return !!(library.history[id] || {}).finished }
  function libResumeAt(id) { return library.resumeAt(id) }

  // ---- Search (/) -------------------------------------------------------------

  // Type, and what matches shows in rows: channels, what's on now and later
  // today, movies and series, your YouTube channels' videos, and My Videos.
  // ↓ goes into the results, Enter opens one. The last few searches are kept
  // (Settings clears them).
  property string searchQuery: ""
  property string searchTerms: ""        // the query, a moment after you stop typing
  property bool searchInResults: false   // in the results (or the recent searches), not the field
  property int searchRow: 0
  property var searchCols: ({})
  property var recentSearches: []
  property string searchFrom: "home"

  // What matches the words, as rows of cards (the Search screen, and the search command)
  function searchRowsFor(text) {
    var terms = String(text || "").toLowerCase().split(/\s+/).filter(function(t) { return t })
    if (!terms.length) return []
    var has = function(hay) {
      hay = String(hay || "").toLowerCase()
      return terms.every(function(t) { return hay.indexOf(t) >= 0 })
    }
    var max = 60
    var rows = []
    var push = function(key, title, shape, cards, more) { if (cards.length) rows.push({ key: key, title: title, shape: shape, cards: cards, more: more }) }

    // channels by name, number or category; shows on now and later today by
    // title: what the guide shows (its categories and sources)
    var chans = [], onNow = [], later = []
    var moreChans = false
    for (var vr = 0; vr < root.visibleRows.length; vr++) {
      var r = root.visibleRows[vr]
      var ch = root.channels[r]
      var show = root.showAt(r, root.now)
      if (has(ch.name + " " + (ch.category || "") + " " + root.numbers[r])) {
        if (chans.length >= max) moreChans = true
        else {
          var cc = root.channelCard(r, show) || { id: "ch:" + ch.url, kind: "channel", r: r, videoId: "", poster: ch.kind === "iptv" && !channelLockItem.blocks(ch) ? ch.logo : "", logo: root.logoFor(ch), live: false, progress: 0 }
          cc.title = ch.name
          cc.sub = "CH " + root.numbers[r] + (show && show.title && show.title !== ch.name ? " · " + show.title : ch.category ? " · " + root.categoryName(ch.category) : "")
          chans.push(cc)
        }
      }
      var listed = ch.kind === "iptv" && listings.has(ch.url)
      if (ch.kind === "iptv" ? !listed : ch.state !== "ready") continue
      if (root.titlesHidden(ch)) continue   // a locked channel's shows aren't found by their titles
      if (show && !show.live && onNow.length < max && has(show.title)) onNow.push(root.channelCard(r, show))
      if ((ch.live && !listed) || later.length >= max) continue
      var coming = root.lockedShows(ch, listed ? listings.between(ch.url, root.now, root.now + 12 * 3600) : Schedule.airing(root.lineupOf(ch), root.now, root.now + 12 * 3600), root.now, root.now)
      for (var c = 0; c < coming.length && later.length < max; c++)
        if (coming[c].start > root.now && has(coming[c].title)) later.push(root.channelCard(r, coming[c], true))
    }
    later.sort(function(a, b) { return a.start - b.start })
    push("s-channels", "Channels", "thumb", chans, moreChans)
    push("s-now", "On now", "thumb", onNow, onNow.length >= max)
    push("s-later", "Later today", "thumb", later, later.length >= max)

    // movies and series, a series once
    var movies = []
    var series = {}
    for (var i = 0; i < library.items.length && movies.length < max; i++) {
      var it = library.items[i]
      if (!has(it.title + " " + it.genre + " " + it.series + " " + (it.year || ""))) continue
      if (it.series) {
        var sk = it.genre + "|" + it.series.toLowerCase()
        if (!series[sk]) {
          series[sk] = { id: "s:" + sk, kind: "series", title: it.series, sub: "", poster: it.poster, episodes: [] }
          movies.push(series[sk])
        }
        series[sk].episodes.push(it)
      } else movies.push(root.movieCard(it))
    }
    for (var sk2 in series) {
      series[sk2].episodes.sort(function(a, b) { return a.season - b.season || a.episode - b.episode })
      series[sk2].sub = series[sk2].episodes.length + (series[sk2].episodes.length === 1 ? " episode" : " episodes")
    }
    push("s-movies", "Movies & series", "poster", movies, movies.length >= max)

    // your YouTube channels' videos
    var clips = []
    for (var y = 0; y < root.channels.length && clips.length < max; y++) {
      var yc = root.channels[y]
      if (yc.kind === "iptv" || !yc.items || channelLockItem.blocks(yc)) continue
      for (var j = 0; j < yc.items.length && clips.length < max; j++)
        if (has(yc.items[j].title + " " + yc.name) && !root.videoLockedBy(yc.items[j].id)) clips.push(root.videoCardFrom("yt:" + yc.items[j].id, yc.items[j].title, yc.name, yc.items[j].id, yc.items[j].duration))
    }
    push("s-videos", "Videos", "thumb", clips, clips.length >= max)

    // My Videos
    var files = []
    if (videos.enabled)
      for (var f = 0; f < videos.items.length && files.length < max; f++)
        if (has(videos.items[f].title + " " + videos.items[f].folder + " " + videos.items[f].path.split("/").pop())) files.push(root.fileCard(videos.items[f]))
    push("s-files", "My Videos", "thumb", files, files.length >= max)
    return rows
  }

  readonly property var searchRows: searchTerms ? searchRowsFor(searchTerms) : []
  readonly property int searchCount: searchRows.reduce(function(n, row) { return n + row.cards.length }, 0)
  readonly property var searchCard: {
    var row = searchRows[searchRow]
    if (!row) return null
    return row.cards[Math.min(row.cards.length - 1, searchCols[row.key] || 0)] || null
  }

  Timer {
    id: searchTimer
    interval: 220
    onTriggered: {
      root.searchTerms = root.searchQuery.trim()
      root.searchRow = 0
      root.searchCols = ({})
    }
  }

  function openSearch(query) {
    if (root.screen !== "search") root.searchFrom = root.screen
    if (!root.vod && root.reception !== "off" && !root.pip && !root.watching) root.turnOff()
    root.screen = "search"
    root.libDetail = null
    root.railOpen = false
    root.dialog = ""
    root.searchInResults = false
    if (query !== undefined && query !== null && String(query) !== "") {
      root.searchQuery = String(query).slice(0, 80)
      root.searchTerms = root.searchQuery.trim()
      root.searchRow = 0
      root.searchCols = ({})
    }
    keys.forceActiveFocus()
    return "ok"
  }

  // Esc: back where you came from; the query goes
  function leaveSearch() {
    root.searchQuery = ""
    root.searchTerms = ""
    root.searchInResults = false
    root.libDetail = null
    if (root.searchFrom === "apps" && appsStore.on) { root.railOpen = false; root.openApps(true); return }
    root.go(root.searchFrom === "guide" ? "tv" : root.searchFrom === "library" ? root.libraryTab
          : root.searchFrom === "settings" ? "settings" : "home")
  }

  function searchType(ch) {
    if (root.searchQuery.length >= 80) return
    root.searchQuery += ch
    root.searchInResults = false
    searchTimer.restart()
  }

  function searchBackspace() {
    root.searchQuery = root.searchQuery.slice(0, -1)
    root.searchInResults = false
    if (!root.searchQuery.trim()) { searchTimer.stop(); root.searchTerms = "" }
    else searchTimer.restart()
  }

  function searchClear() {
    searchTimer.stop()
    root.searchQuery = ""
    root.searchTerms = ""
    root.searchInResults = false
  }

  function rememberSearch(q) {
    q = String(q || "").trim()
    if (q.length < 2) return
    root.recentSearches = [q].concat(root.recentSearches.filter(function(x) { return x.toLowerCase() !== q.toLowerCase() })).slice(0, 8)
    root.saveSettings()
  }

  // ↑↓←→: from the field into the results (or your recent searches) and back
  function moveSearch(dRow, dCol) {
    dRow = Number(dRow) || 0
    dCol = Number(dCol) || 0
    if (!root.searchTerms) {
      var n = root.recentSearches.length
      if (!n) return
      if (!root.searchInResults) { if (dRow > 0) { root.searchInResults = true; root.searchRow = 0 } return }
      if (dRow < 0 && root.searchRow === 0) { root.searchInResults = false; return }
      root.searchRow = Math.max(0, Math.min(n - 1, root.searchRow + dRow))
      return
    }
    var rows = root.searchRows
    if (!rows.length) return
    if (!root.searchInResults) {
      if (dRow > 0) { searchTimer.stop(); root.searchInResults = true; root.searchRow = 0 }
      return
    }
    if (dRow < 0 && root.searchRow === 0) { root.searchInResults = false; return }
    if (dRow) root.searchRow = Math.max(0, Math.min(rows.length - 1, root.searchRow + dRow))
    if (dCol) {
      var row = rows[root.searchRow]
      var cols = {}
      for (var k in root.searchCols) cols[k] = root.searchCols[k]
      cols[row.key] = Math.max(0, Math.min(row.cards.length - 1, (cols[row.key] || 0) + dCol))
      root.searchCols = cols
    }
  }

  function searchAtLeft() {
    if (!root.searchInResults || !root.searchTerms) return true
    var row = root.searchRows[root.searchRow]
    return !row || (root.searchCols[row.key] || 0) === 0
  }

  // Enter: in the field, into the results; on a recent search, search it;
  // on a card, open it (play, watch, or a movie's details)
  function searchEnter() {
    if (!root.searchInResults) {
      if (root.searchQuery.trim() !== root.searchTerms) { searchTimer.stop(); root.searchTerms = root.searchQuery.trim(); root.searchRow = 0; root.searchCols = ({}) }
      if (root.searchRows.length) { root.rememberSearch(root.searchTerms); root.searchInResults = true; root.searchRow = 0 }
      return
    }
    if (!root.searchTerms) {
      var q = root.recentSearches[root.searchRow]
      if (q) { root.searchQuery = q; root.searchTerms = q; root.searchRow = 0; root.searchCols = ({}); root.searchInResults = false }
      return
    }
    root.openSearchCard(root.searchCard, false)
  }

  // Space on a card: plays it straight away (a movie too)
  function searchPlay() {
    if (root.searchInResults && root.searchTerms) root.openSearchCard(root.searchCard, true)
    else root.searchEnter()
  }

  function openSearchCard(c, play) {
    if (!c) return
    root.rememberSearch(root.searchTerms)
    if (c.kind === "channel") {
      if (c.starting && c.start > root.now) root.showInGuide(c.r, c.start)
      else { root.row = c.r; root.watch(c.r) }
    } else if (c.kind === "series" || (c.kind === "movie" && !play)) {
      root.libDetail = c
      root.libEpisode = 0
      if (c.kind === "series")
        for (var i = 0; i < c.episodes.length; i++) if (!(library.history[c.episodes[i].id] || {}).finished) { root.libEpisode = i; break }
    } else if (c.entry) root.playVod(c.entry)
  }

  // The guide, on a channel at a time later today (a show from Search)
  function showInGuide(r, start) {
    root.libDetail = null
    root.screen = "guide"
    root.row = r
    var base = root.slotStart(root.now)
    root.slotOffset = Math.max(0, Math.min(root.maxSlotOffset, Math.floor((start - base) / root.slot)))
    root.cursorTime = start
    keys.forceActiveFocus()
    previewTimer.restart()
    Qt.callLater(function() { root.showRow(r) })
  }

  // ---- Home ----------------------------------------------------------------

  // The home screen: the first screen when it's on (Settings), with Esc in
  // the guide and the library coming back to it. What's on it is yours:
  // its sections in order, each on or off, rows you add (a genre, a YouTube
  // channel, a category), which tiles show, and its background. In settings.json.
  property bool homeEnabled: true
  readonly property var homeTypes: ({
    doors: "Tiles: Live TV, Movies, On Demand, My Videos, My List", "continue": "Continue watching", onNow: "On now",
    latest: "New on your channels", videos: "New in My Videos", soon: "Starting soon", mylist: "My List", searches: "Your recent searches",
    apps: "Your apps", recordings: "Your recordings"
  })
  readonly property var defaultHomeSections: [{ type: "doors", on: true }, { type: "continue", on: true }, { type: "onNow", on: true },
                                              { type: "latest", on: true }, { type: "videos", on: true }, { type: "soon", on: true }, { type: "mylist", on: false }]
  property var homeSections: defaultHomeSections
  readonly property var homeTileKinds: [{ key: "tv", label: "Live TV" }, { key: "movies", label: "Movies & Series" },
                                        { key: "ondemand", label: "On Demand" }, { key: "videos", label: "My Videos" }, { key: "mylist", label: "My List" }]
  property var homeTiles: homeTileKinds.map(function(t) { return t.key })
  // none: the theme's colors; guide: the guide's picture; wallpaper: your
  // Omarchy wallpaper; image: a picture you pick; focus: the picture of
  // what's selected
  property var homeBackground: ({ mode: "focus", image: "", dim: 0.6 })
  // Multiview's background: the theme's colors as they are (mvBackground), a
  // color of your own, the theme's own picture, your Omarchy wallpaper or a
  // picture you picked, darkened by dim. In settings.json; themes carry one.
  property var multiviewBackground: ({ mode: "none", image: "", color: "", dim: 0.6 })
  property var recentChannels: []       // urls, the last ones you watched first
  property bool resumeWatch: false      // closed while watching a channel: opening plays it again (settings.json)
  property int homeRow: 0
  property var homeCols: ({})
  property bool homeEditing: false      // the Customize panel (C)
  property int homeCursor: 0
  property bool homeAdding: false       // its list of rows to add

  // A section's name, as the panel and the row titles say it
  function homeTitle(sec) {
    if (sec.title) return sec.title
    if (sec.type === "genre") return sec.key
    if (sec.type === "folder") return sec.key === "." ? "My Videos" : String(sec.key).split("/").pop()
    if (sec.type === "upcoming") {
      var u = root.indexOf(sec.key)
      return u >= 0 ? "Coming up on " + root.channels[u].name : "A channel you removed"
    }
    if (sec.type === "category") return "On now: " + root.categoryName(sec.key)
    if (sec.type === "appRow") {
      var ap = appsStore.record(String(sec.key).split("/")[0])
      var rk = String(sec.key).split("/").slice(1).join("/")
      var hr = ap ? (ap.home || []).filter(function(h) { return h.key === rk })[0] : null
      return ap ? ap.name + ": " + (hr ? hr.label : rk) + (appHomeItem.stale(sec.key) ? " (couldn't update)" : "") : "An app you removed"
    }
    if (sec.type === "channel") {
      var i = root.indexOf(sec.key)
      return i >= 0 ? root.channels[i].name : "A channel you removed"
    }
    return root.homeTypes[sec.type] || sec.type
  }

  // A channel's card for On now: what's on it, how far in
  function channelCard(r, show, starting) {
    var ch = root.channels[r]
    if (!ch || !show) return null
    var mins = Math.max(0, Math.ceil((show.end - root.now) / 60))
    return { id: "ch:" + ch.url + (starting ? ":" + show.start : ""), kind: "channel", shape: "wide", r: r, title: show.title, start: show.start, starting: !!starting, when: show.start,
             sub: (starting ? root.clock(show.start) + " · " : "") + "CH " + root.numbers[r] + " · " + ch.name + (!starting && !show.live ? " · " + mins + " min left" : ""),
             videoId: ch.kind === "iptv" ? "" : show.id || "", poster: ch.kind === "iptv" && !channelLockItem.blocks(ch) ? ch.logo : "", live: !!show.live,
             logo: root.logoFor(ch),   // shown until its picture is (none for a locked channel)
             progress: starting || show.live ? 0 : Math.max(0, Math.min(1, (root.now - show.start) / Math.max(1, show.end - show.start))) }
  }

  // The sections as shown: [{ key, type, title, shape, cards }], the empty ones left out
  // Home on screen: not under the splash, a channel full screen or an app's
  // media, nor with the guide closed. Its rows and cards are worked out only
  // then: they follow the clock and every listing, on the thread that draws
  // the picture (the mini player leaves Home showing)
  readonly property bool homeOnScreen: screen === "home" && opened && !watching && !appPlaying && !splashItem.running
  readonly property var homeView: {
    if (!homeOnScreen) return []
    var out = []
    for (var i = 0; i < homeSections.length; i++) {
      var sec = homeSections[i]
      if (!sec.on) continue
      var cards = []
      var shape = "thumb"
      if (sec.type === "doors") {
        shape = "tile"
        var yt = channels.filter(function(c) { return c.kind !== "iptv" }).length
        var subs = { tv: channels.length.toLocaleString(Qt.locale("en_US"), "f", 0) + (channels.length === 1 ? " channel" : " channels"),
                     movies: library.items.length.toLocaleString(Qt.locale("en_US"), "f", 0) + " in your library", ondemand: yt + (yt === 1 ? " YouTube channel" : " YouTube channels"),
                     videos: videos.items.length + (videos.items.length === 1 ? " video" : " videos"), mylist: library.myList.length + " saved" }
        cards = homeTiles.map(function(k) { return root.homeTileKinds.filter(function(t) { return t.key === k })[0] })   // in your order
                    .filter(function(t) { return t && (t.key !== "videos" || videos.enabled) })
                    .map(function(t) { return { id: "door:" + t.key, kind: "door", door: t.key, title: t.label, sub: subs[t.key] } })
      } else if (sec.type === "continue") {
        cards = library.unfinished("").map(function(h) {
          var it = library.item(h.id)
          var file = h.kind === "file" ? (videos.enabled ? videos.item(h.id) : null) : null
          var c = it ? root.movieCard(it) : file ? root.fileCard(file) : h.kind === "file" || root.videoLockedBy(h.ref || h.id, h.subtitle) ? null : root.videoCardFrom(h.id, h.title, h.subtitle, h.ref, 0)
          if (c) c.progress = h.progress
          return c
        }).filter(function(c) { return c })
      } else if (sec.type === "onNow" || sec.type === "category") {
        var seen = {}
        var order = []
        if (sec.type === "onNow") for (var rc = 0; rc < recentChannels.length; rc++) { var ri = root.indexOf(recentChannels[rc]); if (ri >= 0) order.push(ri) }
        for (var v = 0; v < visibleRows.length && order.length < 60; v++) order.push(visibleRows[v])
        for (var o = 0; o < order.length && cards.length < 24; o++) {
          var r = order[o]
          var ch = channels[r]
          if (seen[r] || !ch || (sec.type === "category" && (ch.category || "") !== sec.key)) continue
          seen[r] = true
          var card = root.channelCard(r, root.showAt(r, now))
          if (card) cards.push(card)
        }
      } else if (sec.type === "latest") {
        for (var c = 0; c < channels.length; c++) {
          var chl = channels[c]
          if (chl.kind === "iptv" || !chl.items || !chl.items.length || channelLockItem.blocks(chl) || root.videoLockedBy(chl.items[0].id)) continue
          cards.push(root.videoCardFrom("yt:" + chl.items[0].id, chl.items[0].title, chl.name, chl.items[0].id, chl.items[0].duration))
        }
      } else if (sec.type === "soon") {
        for (var s2 = 0; s2 < visibleRows.length && cards.length < 20; s2++) {
          var rs = visibleRows[s2]
          var cs = channels[rs]
          if (!cs || (cs.kind === "iptv" ? !listings.has(cs.url) : cs.live)) continue
          var nowShow = root.showAt(rs, now)
          var next = nowShow ? root.nextShow(rs, nowShow) : null
          if (next && next.start > now && next.start - now <= 3600) cards.push(root.channelCard(rs, next, true))
        }
        cards.sort(function(a, b) { return a.sub < b.sub ? -1 : 1 })
      } else if (sec.type === "mylist") {
        for (var m = 0; m < library.myList.length; m++) {
          var lid = library.myList[m]
          var li = library.item(lid)
          if (li) { cards.push(root.movieCard(li)); continue }
          var lf = videos.enabled ? videos.item(lid) : null
          if (lf) { cards.push(root.fileCard(lf)); continue }
          var le = root.entryFor(lid)
          if (le && le.videoId && !root.videoLockedBy(le.videoId, le.subtitle, le.owners, le.ownersMore)) cards.push(root.videoCardFrom(lid, le.title, le.subtitle, le.videoId, le.duration))
        }
      } else if (sec.type === "videos") {
        if (videos.enabled) cards = videos.items.slice(0, 30).map(root.fileCard)
      } else if (sec.type === "recordings") {
        // recording now, then the latest recorded
        cards = dvr.recordings.filter(function(x) { return DvrRules.active(x) }).concat(dvr.recordings.filter(function(x) { return x.state === "done" }))
                  .slice(0, 30).map(root.recordingCard)
      } else if (sec.type === "folder") {
        var fl = videos.enabled ? videos.folders.filter(function(x) { return (x.folder || ".") === sec.key })[0] : null
        if (fl) cards = fl.items.slice(0, 200).map(root.fileCard)
      } else if (sec.type === "upcoming") {
        var ur = root.indexOf(sec.key)
        var uc = channels[ur]
        if (uc) {
          var coming = root.titlesHidden(uc) ? [] : root.lockedShows(uc, uc.kind === "iptv" ? listings.between(uc.url, now, now + 12 * 3600)
                     : uc.state === "ready" && !uc.live ? Schedule.airing(root.lineupOf(uc), now, now + 12 * 3600) : [], now, now)
          cards = coming.filter(function(x) { return x.start > now }).slice(0, 40).map(function(x) { return root.channelCard(ur, x, true) })
        }
      } else if (sec.type === "searches") {
        cards = recentSearches.map(function(q) { return { id: "q:" + q, kind: "search", shape: "wide", title: q, sub: "Search again" } })
      } else if (sec.type === "apps") {
        cards = appsStore.ready.map(function(a) { return { id: "app:" + a.id, kind: "app", shape: "wide", appId: a.id, title: a.name, sub: a.author, color: a.color, poster: a.icon || "", when: a.used, from: a.from } })
      } else if (sec.type === "appRow") {
        cards = appHomeItem.cardsFor(sec.key).slice()   // sorted below: never the cache itself
      } else if (sec.type === "genre") {
        cards = library.items.filter(function(it) { return it.genre === sec.key }).slice(0, 80).map(root.movieCard)
      } else if (sec.type === "channel") {
        var ci = root.indexOf(sec.key)
        var chc = channels[ci]
        if (chc && chc.items && !channelLockItem.blocks(chc)) cards = chc.items.filter(function(v2) { return !root.videoLockedBy(v2.id) }).slice(0, 60).map(function(v2) { return root.videoCardFrom("yt:" + v2.id, v2.title, chc.name, v2.id, v2.duration) })
      }
      if (sec.type !== "doors") {
        if (sec.sort === "az") cards.sort(function(x, y) { return String(x.title).localeCompare(String(y.title)) })
        else if (sec.sort === "newest" || sec.sort === "oldest") {
          if (cards.every(function(x) { return typeof x.when === "number" })) cards.sort(function(x, y) { return sec.sort === "newest" ? y.when - x.when : x.when - y.when })
          else if (sec.sort === "oldest") cards.reverse()   // they come newest first
        }
        if (sec.limit > 0) cards = cards.slice(0, sec.limit)
        // your shape for the row: every card in it (an app's row asks for that picture)
        if (sec.shape === "poster" || sec.shape === "wide") cards = cards.map(function(c) { var o = {}; for (var x in c) o[x] = c[x]; o.shape = sec.shape; return o })
      }
      if (cards.length) out.push({ key: sec.type + ":" + (sec.key || ""), type: sec.type, title: root.homeTitle(sec), shape: shape, cards: cards,
                                   size: { small: 0.72, large: 1.4 }[sec.size] || 1 })
    }
    return out
  }

  readonly property var homeCard: {
    var sec = homeView[homeRow]
    if (!sec) return null
    return sec.cards[Math.min(sec.cards.length - 1, homeCols[sec.key] || 0)] || null
  }

  // What the top of Home says about what's selected
  readonly property var homeHero: {
    var c = homeCard
    if (!c) return { kicker: "Welcome", title: "Your TV", meta: "Add channels with A in the guide, or a playlist of movies.", progress: 0 }
    if (c.kind === "appItem" || c.kind === "appStatus") {
      var owner = appsStore.record(c.appId)
      return { kicker: owner ? owner.name : "App", title: c.title, meta: c.sub || "", progress: c.progress || 0 }
    }
    if (c.kind === "door") {
      var about = { tv: "Every channel, what's on now and next.",
                    movies: "Movies and series from your playlists, by genre.",
                    ondemand: "Every video of your YouTube channels, from the start.",
                    videos: "The videos in your Videos folder: screen recordings, downloads, your own.",
                    mylist: "What you saved to watch later." }
      return { kicker: c.title, title: c.door === "tv" ? "The program guide" : c.title, meta: about[c.door] + " " + c.sub + ".", progress: 0 }
    }
    if (c.kind === "channel") return { kicker: c.live ? "Live" : c.starting ? "Starting soon" : "On now", title: c.title, meta: c.sub, progress: c.progress }
    if (c.kind === "search") return { kicker: "Search again", title: "“" + c.title + "”", meta: "Enter searches channels, shows, movies and videos for it.", progress: 0 }
    if (c.kind === "app") { var ra = appsStore.record(c.appId) || {}; return { kicker: "App · " + (ra.author || ""), title: c.title, meta: (ra.description || "") + (/full screen/i.test(ra.description || "") ? "" : " Opens full screen."), progress: 0 } }
    var e = c.entry || {}
    var p = library.progress(c.id)
    return { kicker: p > 0.01 && !(library.history[c.id] || {}).finished ? "Continue watching" : c.kind === "movie" ? "Movie" : c.kind === "file" ? "My Videos" : "Video",
             title: c.title, meta: [e.subtitle, (e.description || "").slice(0, 220)].filter(function(x) { return x }).join(" · "), progress: p }
  }

  // The top of Home with "What's on your last channel": the channel you
  // watched last, what's on it now
  readonly property var homeLastChannel: {
    var r = recentChannels.length ? root.indexOf(recentChannels[0]) : -1
    var ch = channels[r]
    if (!ch) return { kicker: "Your last channel", title: "Nothing watched yet", meta: "Watch a channel and what's on it shows here.", progress: 0 }
    var show = root.showAt(r, now)
    var listed = show && !show.live
    return { kicker: "Your last channel · CH " + root.numbers[r] + " · " + ch.name, title: show ? show.title : ch.name,
             meta: listed ? root.airTime(show) + (show.desc ? " · " + show.desc : "") : "Live now", progress: listed ? Math.max(0, Math.min(1, (now - show.start) / Math.max(1, show.end - show.start))) : 0 }
  }

  // Multiview's picture: a URL, or "" for the theme's colors
  readonly property string multiviewBackdrop: {
    var b = multiviewBackground
    if (b.mode === "image" && b.image) return fileUrl(b.image)
    if (b.mode === "wallpaper") return wallpaperUrl
    if (b.mode === "theme") {
      var tb = Look.themeBackground(currentTheme, { image: "", from: "" })
      return tb.mode === "image" && tb.image ? fileUrl(tb.image) : tb.mode === "wallpaper" ? wallpaperUrl : ""
    }
    return ""
  }

  // The background: a path or URL, or "" for the theme's colors
  readonly property string homeBackdrop: {
    var mode = homeBackground.mode
    if (mode === "image" && homeBackground.image) return fileUrl(homeBackground.image)
    if (mode === "wallpaper") return wallpaperUrl
    if (mode === "guide") return backgroundSource
    if (mode === "focus" && homeCard && homeCard.kind !== "door" && homeCard.kind !== "app") return posterFor(homeCard.entry || { poster: homeCard.poster, videoId: homeCard.videoId, live: homeCard.live })
    if (mode === "focus") return backgroundSource
    return ""
  }

  function openHome() {
    if (!root.homeEnabled) { root.screen = "guide"; return }
    if (!root.vod && root.reception !== "off" && !root.pip && !root.watching) root.turnOff()
    root.screen = "home"
    root.libDetail = null
    // (hidden, Home has no rows to measure: the cursor stays where it was)
    if (root.homeOnScreen) root.homeRow = Math.max(0, Math.min(root.homeRow, root.homeView.length - 1))
    keys.forceActiveFocus()
  }

  function moveHome(dRow, dCol) {
    dRow = Number(dRow) || 0
    dCol = Number(dCol) || 0
    var view = root.homeView
    if (!view.length) return
    if (dRow) root.homeRow = Math.max(0, Math.min(view.length - 1, root.homeRow + dRow))
    if (dCol) {
      var sec = view[root.homeRow]
      var cols = {}
      for (var k in root.homeCols) cols[k] = root.homeCols[k]
      cols[sec.key] = Math.max(0, Math.min(sec.cards.length - 1, (cols[sec.key] || 0) + dCol))
      root.homeCols = cols
    }
  }

  // Enter on Home: a tile goes there, a channel plays live, the rest plays on demand
  function homeOpen() {
    var c = root.homeCard
    if (!c) return
    if (c.kind === "door") {
      if (c.door === "tv") root.closeLibrary()
      else root.openLibrary(c.door)
    } else if (c.kind === "channel") {
      if (c.starting && c.start > root.now) { root.showInGuide(c.r, c.start); return }
      root.row = c.r
      root.watch(c.r)
    } else if (c.kind === "search") root.openSearch(c.title)
    else if (c.kind === "app") root.openApp(c.appId)
    else if (c.kind === "appItem" || c.kind === "appStatus") appHomeItem.open(c, root.byUser)
    else if (c.kind === "recording") root.playRecording(c, false)
    else if (c.entry) root.playVod(c.entry)
  }

  // ---- customizing Home (C) ---------------------------------------------------

  // A row's options: its name (yours, or its own), card size, how many cards,
  // and their order
  readonly property var homeSizes: ["small", "medium", "large"]
  readonly property var homeLimits: [0, 6, 12, 24]
  readonly property var homeSorts: ["default", "newest", "oldest", "az"]
  function homeSizeLabel(v) { return { small: "Small", medium: "Medium", large: "Large" }[v] || "Medium" }
  // a Home row's pictures: each card its own (auto), or posters, or wide
  readonly property var homeShapes: ["", "poster", "wide"]
  function homeShapeLabel(v) { return { poster: "Posters", wide: "Wide" }[v] || "Auto" }
  function homeLimitLabel(v) { return v ? v + " at most" : "All" }
  function homeSortLabel(v) { return { "default": "As it comes", newest: "Newest first", oldest: "Oldest first", az: "A to Z" }[v] || "As it comes" }
  property int homeOptions: -1          // the section whose options are open
  property bool homeRenaming: false     // typing its name
  property string homeRenameStart: ""   // ...starting from this

  // The top of Home, the clock and the chips (layout, so themes can set them too)
  readonly property var homeTopModes: ["selected", "clock", "channel", "off"]
  function homeTopLabel(v) { return { selected: "What's selected", clock: "A big clock", channel: "What's on your last channel", off: "Nothing" }[v] || v }
  readonly property string homeTop: !layout.homeHero ? "off" : layout.homeTop
  function setHomeTop(v) {
    if (v === "off") root.setLayoutOverride("homeHero", false)
    else { root.setLayoutOverride("homeHero", true); root.setLayoutOverride("homeTop", v) }
  }
  readonly property var homeClockSpots: ["left", "right", "none"]
  function homeClockLabel(v) { return { left: "Left", right: "Right", none: "Off" }[v] || v }

  // The panel's rows: the screen, the background, the sections, the tiles;
  // or adding a row; or one row's options
  readonly property var homePanelRows: {
    if (homeAdding) {
      var add = [{ type: "header", label: "ADD A ROW" }]
      var have = {}
      for (var a = 0; a < homeSections.length; a++) have[homeSections[a].type + ":" + (homeSections[a].key || "")] = true
      for (var t in homeTypes) if (t !== "doors" && !have[t + ":"] && (t !== "videos" || videos.enabled) && (t !== "apps" || appsStore.on)
                                  && (t !== "recordings" || root.libraryTabShown("recordings"))) add.push({ type: "add", sec: { type: t, on: true }, label: homeTypes[t] })
      var appRows = []
      appsStore.ready.forEach(function(ap) {
        ;(ap.kind === "app" ? ap.home || [] : []).forEach(function(h) {
          if (!have["appRow:" + ap.id + "/" + h.key]) appRows.push({ type: "add", sec: { type: "appRow", key: ap.id + "/" + h.key, on: true }, label: ap.name + ": " + h.label })
        })
      })
      if (appRows.length) add = add.concat([{ type: "header", label: "AN APP'S ROW" }]).concat(appRows)
      var genres = library.genres
      if (genres.length) add.push({ type: "header", label: "MOVIE GENRES" })
      for (var g = 0; g < genres.length; g++) if (!have["genre:" + genres[g].genre]) add.push({ type: "add", sec: { type: "genre", key: genres[g].genre, on: true }, label: genres[g].genre })
      var folders = videos.enabled ? videos.folders : []
      if (folders.length) add.push({ type: "header", label: "A MY VIDEOS FOLDER" })
      for (var f = 0; f < folders.length; f++) {
        var fk = folders[f].folder || "."
        if (!have["folder:" + fk]) add.push({ type: "add", sec: { type: "folder", key: fk, on: true }, label: folders[f].folder || "The folder itself" })
      }
      var yts = channels.filter(function(c) { return c.kind !== "iptv" })
      if (yts.length) add.push({ type: "header", label: "A YOUTUBE CHANNEL'S VIDEOS" })
      for (var y = 0; y < yts.length && y < 60; y++) if (!have["channel:" + yts[y].url]) add.push({ type: "add", sec: { type: "channel", key: yts[y].url, on: true }, label: yts[y].name })
      var listed = channels.filter(function(c) { return c.kind === "iptv" ? listings.has(c.url) : c.state === "ready" && !c.live })
      if (listed.length) add.push({ type: "header", label: "COMING UP ON A CHANNEL" })
      for (var l = 0; l < listed.length && l < 120; l++) if (!have["upcoming:" + listed[l].url]) add.push({ type: "add", sec: { type: "upcoming", key: listed[l].url, on: true }, label: listed[l].name })
      var cats = categories.filter(function(c) { return c })
      if (cats.length) add.push({ type: "header", label: "ON NOW IN A CATEGORY" })
      for (var cc = 0; cc < cats.length; cc++) if (!have["category:" + cats[cc]]) add.push({ type: "add", sec: { type: "category", key: cats[cc], on: true }, label: root.categoryName(cats[cc]) })
      return add
    }
    if (homeOptions >= 0 && homeSections[homeOptions]) {
      var opts = [{ type: "header", label: root.homeTitle(homeSections[homeOptions]).toUpperCase() }, { type: "optOn" }, { type: "optName" }]
      if (homeSections[homeOptions].type !== "doors") opts = opts.concat([{ type: "optSize" }, { type: "optShape" }, { type: "optLimit" }, { type: "optSort" }])
      if (!homeTypes[homeSections[homeOptions].type]) opts.push({ type: "optRemove" })
      return opts
    }
    var rows = [{ type: "header", label: "SCREEN" }, { type: "screenTop" }, { type: "screenClock" }, { type: "screenChips" },
                { type: "header", label: "BACKGROUND" }, { type: "bgMode" }, { type: "bgPick" }, { type: "bgDim" },
                { type: "header", label: "ROWS" }]
    for (var i = 0; i < homeSections.length; i++) rows.push({ type: "section", index: i })
    rows.push({ type: "addRow" })
    rows.push({ type: "header", label: "TILES" })
    // the ones on, in their order, then the rest
    var order = homeTiles.concat(homeTileKinds.map(function(x) { return x.key }).filter(function(x) { return homeTiles.indexOf(x) < 0 }))
    for (var k = 0; k < order.length; k++) {
      var kind = homeTileKinds.filter(function(x) { return x.key === order[k] })[0]
      if (kind) rows.push({ type: "tile", key: kind.key, label: kind.label + (kind.key === "videos" && !videos.enabled ? " (off in Settings)" : "") })
    }
    rows.push({ type: "header", label: "" })
    rows.push({ type: "homeReset" })
    return rows
  }

  function openHomePanel() {
    root.homeEditing = true
    root.homeAdding = false
    root.homeOptions = -1
    root.homeRenaming = false
    root.homeCursor = 1
    keys.forceActiveFocus()
  }

  // Esc: out of renaming, a row's options or adding, then the panel itself
  function closeHomePanel() {
    if (root.homeRenaming) { root.homeRenaming = false; keys.forceActiveFocus(); return }
    if (root.homeOptions >= 0) { var at = root.homeOptions; root.homeOptions = -1; root.homeCursor = root.homeRowAt("section", at); return }
    if (root.homeAdding) { root.homeAdding = false; root.homeCursor = root.homeRowAt("addRow"); return }
    root.homeEditing = false
    root.saveSettings()
  }

  // Where a row is in the panel's list
  function homeRowAt(type, index) {
    var rows = root.homePanelRows
    for (var i = 0; i < rows.length; i++) if (rows[i].type === type && (index === undefined || rows[i].index === index)) return i
    return 1
  }

  function moveHomePanel(d) {
    d = Number(d) || 0
    var rows = root.homePanelRows
    var n = rows.length
    var c = root.homeCursor
    do { c = (c + d + n) % n } while (rows[c].type === "header")
    root.homeCursor = c
  }

  readonly property var homeBgModes: ["focus", "guide", "wallpaper", "image", "none"]
  readonly property var mvBgModes: ["none", "color", "theme", "wallpaper", "image"]
  function solidHex(v) { return typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v) }
  function homeBgLabel(mode) {
    return { focus: "What's selected", guide: "The guide's picture", wallpaper: "Omarchy wallpaper", image: "A picture you pick", none: "None: the theme's colors" }[mode] || mode
  }

  property string homePictureNote: ""   // a picture for Home that couldn't be used, and why
  // A picture Home may show: the guide's own copy of one you picked
  // (app-pictures), or a theme's, in that theme's folder (the plugin's or
  // yours); anything else is checked and copied first (homePicture)
  function homePictureOk(p) {
    if (typeof p !== "string" || !p) return false
    if (appScreensItem.pictureOk(p)) return true
    var inThemes = function(base) {
      if (p.indexOf(base + "/") !== 0) return false
      var rest = p.slice(base.length + 1).split("/")
      return rest.length === 2 && /^[a-z0-9][a-z0-9-]{0,31}$/.test(rest[0]) && !!Look.themePicture(rest[1], true)
    }
    return inThemes(root.themesDir) || inThemes(root.pluginDir + "/themes")
  }
  // A picture for Home, by its full path: checked and copied by the helper,
  // then shown (with mode, if given). Only the latest pick lands, and only
  // while Home's background hasn't been changed since (by you, a command, a
  // theme or a reset; its darkness alone aside: it lands with the new
  // darkness): an older one finishing late is dropped. done(res), if given.
  property int homePickSeq: 0
  function homePicture(path, mode, done) {
    root.homePickSeq += 1
    var mine = root.homePickSeq
    root.importPicture(path, function(res) {
      if (mine !== root.homePickSeq) return
      if (res.ok) root.setHomeBackground(mode ? { mode: mode, image: res.path } : { image: res.path }, true)
      else root.homePictureNote = "Not used: " + res.error + "."
      if (done) done(res)
    })
  }
  // A picture you picked, checked (a plain file, never a link, at most 40
  // MiB, PNG, JPEG or WebP, at most 8192 a side and 40 MP) and copied into
  // the guide's own folder by the helper (bin/om-pg-apps picture-import).
  // done({ ok, path }) or done({ ok: false, error }) in the guide's words.
  function importPicture(path, done) {
    root.homePictureNote = ""
    var r = pictureImporter.createObject(root)
    r.finished.connect(function(ok, output) {
      var res
      try { res = JSON.parse(String(output).trim().split("\n").pop()) } catch (e) { res = {} }
      done(res.ok && typeof res.path === "string" ? { ok: true, path: res.path }
           : { ok: false, error: typeof res.error === "string" && res.error && res.error.indexOf("/") < 0 ? res.error : "it couldn't be copied" })
      Qt.callLater(function() { r.destroy() })
    })
    r.start(["/usr/bin/python3", appsStore.helper, "picture-import"], JSON.stringify({ into: root.configDir + "/app-pictures", from: String(path) }))
  }
  Component { id: pictureImporter; Run { timeoutMs: 60000; maxBytes: 64 * 1024; okCodes: [0, 1]; splitMarker: "\n" } }
  // Copies no choice names any more go, once what's kept is read (and only
  // ones older than ten minutes: a pick may still be on its way)
  property bool picturesPruned: false
  function prunePictures() {
    if (root.picturesPruned || !appScreensItem.loaded || !root.settingsLoaded) return
    root.picturesPruned = true
    var keep = {}
    var note = function(b) { if (b && typeof b === "object" && typeof b.image === "string") keep[b.image.split("/").pop()] = true }
    ;[appScreensItem.now, appScreensItem.disk].forEach(function(st) {
      note((st.all || {}).background)
      for (var k in st.apps) note(st.apps[k].background)
    })
    note(root.homeBackground)
    note(root.multiviewBackground)
    var br = root.beforeReset
    if (br) {
      if (br.appsAll) note(br.appsAll.background)
      note(br.homeBackground)
      note(br.multiviewBackground)
      if (br.home) note(br.home.background)
    }
    var r = pictureImporter.createObject(root)
    r.finished.connect(function() { Qt.callLater(function() { r.destroy() }) })
    r.start(["/usr/bin/python3", appsStore.helper, "picture-prune"], JSON.stringify({ into: root.configDir + "/app-pictures", keep: Object.keys(keep) }))
  }
  Connections {
    target: appScreensItem
    function onLoadedChanged() { root.prunePictures() }
  }

  // landing: a picture you picked, now copied in (anything else but the
  // darkness is a newer choice than a pick still on its way)
  function setHomeBackground(changes, landing) {
    if (!landing && Object.keys(changes).some(function(k) { return k !== "dim" })) root.homePickSeq += 1
    var b = { mode: root.homeBackground.mode, image: root.homeBackground.image, dim: root.homeBackground.dim }
    for (var k in changes) b[k] = changes[k]
    root.homeBackground = b
    root.saveSettings()
  }
  // Home's background put in place whole (a theme, a reset, undo): a pick
  // still on its way no longer lands
  function replaceHomeBackground(b) {
    root.homePickSeq += 1
    root.homeBackground = b
  }

  // Multiview's background, as Home's: a change saved; one put in place
  // whole (a theme, a reset, undo); a picture checked and copied first, and
  // only the latest pick lands
  property int mvPickSeq: 0
  function setMultiviewBackground(changes, landing) {
    if (!landing && Object.keys(changes).some(function(k) { return k !== "dim" })) root.mvPickSeq += 1
    var b = { mode: root.multiviewBackground.mode, image: root.multiviewBackground.image, color: root.multiviewBackground.color, dim: root.multiviewBackground.dim }
    for (var k in changes) b[k] = changes[k]
    root.multiviewBackground = b
    root.saveSettings()
  }
  function replaceMultiviewBackground(b) {
    root.mvPickSeq += 1
    root.multiviewBackground = b
  }
  function multiviewPicture(path, done) {
    root.mvPickSeq += 1
    var mine = root.mvPickSeq
    root.importPicture(path, function(res) {
      if (mine !== root.mvPickSeq) return
      if (res.ok) root.setMultiviewBackground({ mode: "image", image: res.path }, true)
      if (done) done(res)
    })
  }

  function cycle(list, now, d) { return list[(Math.max(0, list.indexOf(now)) + (d || 1) + list.length) % list.length] }

  // A section with some of its options changed
  function withSection(index, changes) {
    var list = root.homeSections.slice()
    var sec = {}
    for (var k in list[index]) sec[k] = list[index][k]
    for (var c in changes) { if (changes[c] === undefined || changes[c] === "") delete sec[c]; else sec[c] = changes[c] }
    list[index] = sec
    root.homeSections = list
  }

  // Space on a row: on or off (a section, a tile, the chips); the rest as Enter
  function homePanelToggle() {
    var r = root.homePanelRows[root.homeCursor]
    if (r && r.type === "section") { root.withSection(r.index, { on: !root.homeSections[r.index].on }); root.saveSettings() }
    else root.homePanelAct(1)
  }

  // Enter and ← → in the panel
  function homePanelAct(d) {
    var r = root.homePanelRows[root.homeCursor]
    if (!r) return
    d = Number(d) || 0
    var list = root.homeSections.slice()
    var o = root.homeOptions
    if (r.type === "screenTop") root.setHomeTop(root.cycle(root.homeTopModes, root.homeTop, d))
    else if (r.type === "screenClock") root.setLayoutOverride("homeClock", root.cycle(root.homeClockSpots, root.layout.homeClock, d))
    else if (r.type === "screenChips") root.setLayoutOverride("homeChips", !root.layout.homeChips)
    else if (r.type === "bgMode") {
      var modes = root.homeBgModes.filter(function(m) { return m !== "image" || root.homeBackground.image })
      root.setHomeBackground({ mode: root.cycle(modes, root.homeBackground.mode, d) })
    } else if (r.type === "bgPick") {
      root.openPicker(true, "home")
    } else if (r.type === "bgDim") {
      root.setHomeBackground({ dim: Math.round(Math.max(0, Math.min(0.95, root.homeBackground.dim + (d || 1) * 0.05)) * 100) / 100 })
    } else if (r.type === "section") {
      // ← → do nothing here; Enter opens its options (the tiles have none: on or off)
      if (d < 0) return
      if (list[r.index].type === "doors") { root.homePanelToggle(); return }
      root.homeOptions = r.index
      root.homeCursor = 1
    } else if (r.type === "addRow") {
      root.homeAdding = true
      root.homeCursor = 0
      root.moveHomePanel(1)
    } else if (r.type === "add") {
      list.push(r.sec)
      root.homeSections = list
      root.homeAdding = false
      root.homeCursor = root.homeRowAt("section", list.length - 1)
    } else if (r.type === "tile") {
      var tiles = root.homeTiles.slice()
      root.homeTiles = tiles.indexOf(r.key) >= 0 ? tiles.filter(function(t) { return t !== r.key }) : tiles.concat([r.key])
      root.homeCursor = root.homeRowAt("tile") + root.homePanelRows.slice(root.homeRowAt("tile")).findIndex(function(x) { return x.key === r.key })
    } else if (r.type === "homeReset") {
      root.homeSections = root.defaultHomeSections
      root.homeTiles = root.homeTileKinds.map(function(t) { return t.key })
      root.replaceHomeBackground({ mode: "focus", image: "", dim: 0.6 })
      root.setLayoutOverride("homeHero", undefined)
      root.setLayoutOverride("homeTop", undefined)
      root.setLayoutOverride("homeClock", undefined)
      root.setLayoutOverride("homeChips", undefined)
    } else if (o >= 0 && list[o]) {
      var sec = list[o]
      if (r.type === "optOn") root.withSection(o, { on: !sec.on })
      else if (r.type === "optName") { if (d >= 0) { root.homeRenameStart = root.homeTitle(sec); root.homeRenaming = true } return }
      else if (r.type === "optSize") root.withSection(o, { size: root.cycle(root.homeSizes, sec.size || "medium", d) })
      else if (r.type === "optShape") root.withSection(o, { shape: root.cycle(root.homeShapes, sec.shape || "", d) })
      else if (r.type === "optLimit") root.withSection(o, { limit: root.cycle(root.homeLimits, sec.limit || 0, d) })
      else if (r.type === "optSort") root.withSection(o, { sort: root.cycle(root.homeSorts, sec.sort || "default", d) })
      else if (r.type === "optRemove") {
        root.homeSections = list.filter(function(x, i) { return i !== o })
        root.homeOptions = -1
        root.homeCursor = root.homeRowAt("addRow")
      }
    }
    root.saveSettings()
  }

  // The name typed for the row whose options are open ("" for its own)
  function renameHomeSection(text) {
    var o = root.homeOptions
    root.homeRenaming = false
    keys.forceActiveFocus()
    if (o < 0 || !root.homeSections[o]) return
    var t = String(text || "").trim().slice(0, 40)
    var own = root.homeTitle({ type: root.homeSections[o].type, key: root.homeSections[o].key })
    root.withSection(o, { title: t && t !== own ? t : undefined })
    root.saveSettings()
  }

  // Shift ↑↓ on a section or a tile (that's on): moves it
  function moveHomeSection(d) {
    d = Number(d) || 0
    var r = root.homePanelRows[root.homeCursor]
    if (r && r.type === "tile") {
      var tiles = root.homeTiles.slice()
      var at = tiles.indexOf(r.key)
      if (at < 0 || at + d < 0 || at + d >= tiles.length) return
      tiles.splice(at, 1)
      tiles.splice(at + d, 0, r.key)
      root.homeTiles = tiles
      root.homeCursor += d
      root.saveSettings()
      return
    }
    if (!r || r.type !== "section") return
    var to = r.index + d
    if (to < 0 || to >= root.homeSections.length) return
    var list = root.homeSections.slice()
    var sec = list.splice(r.index, 1)[0]
    list.splice(to, 0, sec)
    root.homeSections = list
    root.homeCursor += d
    root.saveSettings()
  }

  // Del on a row you added: takes it off (the built-in ones turn off instead)
  function removeHomeSection() {
    var r = root.homePanelRows[root.homeCursor]
    if (!r || r.type !== "section") return
    var sec = root.homeSections[r.index]
    if (root.homeTypes[sec.type]) { root.homePanelToggle(); return }
    root.homeSections = root.homeSections.filter(function(x, i) { return i !== r.index })
    root.saveSettings()
  }

  // Sections from settings or a command, checked: built-in ones once, rows
  // you add with their key, and each one's options
  function checkedHomeSections(given) {
    if (!Array.isArray(given)) return null
    var out = []
    var seen = {}
    for (var i = 0; i < given.length && out.length < 40; i++) {
      var g = given[i]
      if (!g || typeof g.type !== "string") continue
      var builtIn = !!root.homeTypes[g.type]
      if (!builtIn && ["genre", "channel", "category", "folder", "upcoming", "appRow"].indexOf(g.type) < 0) continue
      var key = builtIn ? "" : String(g.key || "").slice(0, 2048)
      if (!builtIn && !key) continue
      // an app's row: "<app id>/<row key>", as its app.json declares it
      if (g.type === "appRow" && !/^[a-z][a-z0-9-]{0,30}(\.[a-z0-9][a-z0-9-]{0,30}){1,5}\/[a-z][A-Za-z0-9_]{0,31}$/.test(key)) continue
      if (seen[g.type + ":" + key]) continue
      seen[g.type + ":" + key] = true
      var sec = builtIn ? { type: g.type, on: g.on !== false } : { type: g.type, key: key, on: g.on !== false }
      if (typeof g.title === "string" && g.title.trim()) sec.title = g.title.trim().slice(0, 40)
      if (root.homeSizes.indexOf(g.size) >= 0 && g.size !== "medium") sec.size = g.size
      if (root.homeLimits.indexOf(Number(g.limit)) > 0) sec.limit = Number(g.limit)
      if (root.homeSorts.indexOf(g.sort) > 0) sec.sort = g.sort
      // its pictures: posters or wide for every card (left out: each card its own)
      if (!builtIn || g.type !== "doors") { if (g.shape === "poster" || g.shape === "wide") sec.shape = g.shape }
      out.push(sec)
    }
    return out
  }

  // On demand: what's playing from the library or a YouTube channel, from
  // the start (not joined partway), or null for a channel. { id, kind:
  // "movie"|"youtube", title, subtitle, poster, url | videoId, duration }
  property var vod: null
  property bool vodBarShown: false
  property bool vodPaused: false
  readonly property real playPosition: vod ? (seekTarget >= 0 ? seekTarget : player.position) : 0
  // Where a burst of skips is going (ms), not yet asked of the player; -1: none
  property real seekTarget: -1
  onVodChanged: { root.seekTarget = -1; seekGap.stop() }
  readonly property real playDuration: vod ? player.duration : 0

  // The TV
  property int tunedRow: -1
  property var onAir: null          // { id, title, start, end } of what's playing
  property string reception: "off"  // "off", "tuning", "on" or "lost"
  property bool started: false      // the stream being tuned has been told to play
  property bool bufferNext: false   // the tune on its way is to watch (pause and rewind's buffer takes it)
  property bool iptvRetried: false  // one retry when an IPTV stream drops
  readonly property bool identUp: reception === "tuning" || reception === "lost" || identHold.running
  // what the tuning card says (the TV's and the mini player's)
  readonly property string identStatus: timeshift.stalled ? "stalled"
                                       : reception === "tuning" ? (vod ? "loading" : timeshift.filling ? "filling" : "tuning")
                                       : reception === "lost" ? "lost" : ""
  property bool muted: false
  property bool bannerShown: false
  property int port: 0              // the streamer's, once it is up
  property string streamBase: ""    // its address, secret included

  // Your channel list. Until you add or remove one, the bundled list.
  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/om-pg"
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/om-pg"

  // Listings saved between runs, so the guide opens with them at once.
  property var cachedListings: ({})   // url -> { items, channelId, logoUrl, plan }

  // The daily lineup: each channel's schedule is planned once per TV day
  // (4 AM to 4 AM) from its listing, so new uploads don't shift what's on
  // mid-show. "latest" (settings.json) plans from every new listing instead;
  // R re-plans now either way.
  property string lineupMode: "daily"
  readonly property int dayStartsAt: 4 * 3600
  property var replanning: ({})       // urls whose next listing replaces the plan
  readonly property string listPath: configDir + "/channels.json"
  property bool ownListMissing: false
  property string listProblem: ""
  readonly property string filesProblem: [root.settingsProblem, root.listProblem, library.problem].filter(function(p) { return p }).join(" ")
  property string defaultList: ""
  property string demoList: ""
  property string demoSaid: ""          // what Load the demo channels did
  // Contributors (contributors.json, newest first), in Settings → About
  property string contributorsList: ""
  property int contributorPick: 0
  readonly property var contributors: {
    var parsed = null
    try { parsed = JSON.parse(contributorsList || "[]") } catch (e) {}
    var out = []
    for (var i = 0; Array.isArray(parsed) && i < parsed.length && out.length < 500; i++) {
      var c = parsed[i]
      if (!c || !/^[A-Za-z0-9][A-Za-z0-9-]{0,38}$/.test(String(c.handle))) continue
      out.push({ handle: String(c.handle), did: String(c.did || "").slice(0, 80), version: String(c.version || "").slice(0, 20) })
    }
    return out
  }
  // The demo lineup's channels (checked as your list is) and how many categories
  readonly property var demoLineup: {
    var parsed = null
    try { parsed = JSON.parse(demoList || "[]") } catch (e) {}
    var out = []
    var cats = {}
    for (var i = 0; Array.isArray(parsed) && i < parsed.length; i++) {
      var c = parsed[i]
      if (!c || !root.isYouTube(c.url)) continue
      var category = typeof c.category === "string" ? c.category.trim().slice(0, 40) : ""
      if (category) cats[category] = true
      out.push({ name: String(c.name || c.url).slice(0, 60), url: c.url, category: category,
                 liveId: typeof c.liveId === "string" && /^[\w-]{11}$/.test(c.liveId) ? c.liveId : "" })
    }
    return { channels: out, categories: Object.keys(cats).length }
  }

  // Manage mode (E): mark, move, rename, recategorize, remove
  property bool managing: false
  property var marked: ({})         // url -> true
  readonly property int markedCount: Object.keys(marked).length
  property var removeTargets: []    // urls the remove box asks about
  property string catQuery: ""
  property int catCursor: 0
  readonly property var catOptions: {
    var q = catQuery.trim()
    var ql = q.toLowerCase()
    var out = []
    var exists = categories.some(function(c) { return c.toLowerCase() === ql }) || ql === "my channels"
    if (q && !exists) out.push({ label: q.slice(0, 40), value: q.slice(0, 40), isNew: true })
    for (var i = 0; i < categories.length; i++) {
      if (!categories[i]) continue
      if (!ql || categories[i].toLowerCase().indexOf(ql) >= 0) out.push({ label: categories[i], value: categories[i] })
    }
    if (!ql || "my channels".indexOf(ql) >= 0) out.push({ label: "My channels (no category)", value: "" })
    return out
  }

  // The add, remove, filter, file-picker, rename and category boxes
  property string dialog: ""        // "", "add", "remove", "filter", "pick", "rename", "category", "remote", "help" or "style"
  property bool pickImages: false   // the picker is looking for a picture
  property string pickArea: ""      // ...for this area (imageSlots), or "" for the background
  property bool pickFolders: false  // the picker is looking for a folder (My Videos)
  property bool pickApps: false     // ...for an app's package, or its app.json (Developer mode)
  property bool pickSignedApps: false // ...for a signed .tvapp (Unknown sources), kept inside HOME
  property var pickFiles: []        // [{ path, shown, mtime }], newest first
  property string pickQuery: ""
  property int pickCursor: 0
  property bool pickSearching: false
  // Browse (Tab): one folder at a time, from your home folder up to / (a USB
  // stick, say): [{ path, name, where, mtime, dir, up, here }]
  property bool pickBrowse: false
  property string pickDir: ""
  property var pickEntries: []
  readonly property var pickMatches: {
    var terms = pickQuery.toLowerCase().split(/\s+/).filter(function(t) { return t })
    var out = []
    if (pickBrowse) {
      for (var j = 0; j < pickEntries.length; j++) {
        var e = pickEntries[j]
        if (e.up || e.here || terms.every(function(t) { return e.name.toLowerCase().indexOf(t) >= 0 })) out.push(e)
      }
      return out
    }
    for (var i = 0; i < pickFiles.length && out.length < 300; i++) {
      var p = pickFiles[i].shown.toLowerCase()
      if (terms.every(function(t) { return p.indexOf(t) >= 0 })) out.push(pickFiles[i])
    }
    return out
  }
  property var filterDraft: []
  property int filterCursor: 0
  property string addStatus: ""
  property bool addFailed: false
  property int jobTotal: 0          // links being checked for adding
  property int jobDone: 0
  property var job: null            // { added, already, failed, single, problem, name }
  property var checks: ({})         // url -> the name it came with, while being checked
  property var searches: ({})       // search URL -> the channel name being looked up
  property int jobId: 0             // marks the channels an import adds, to put them in order
  property string lastSaved: ""

  // yt-dlp runs, a few at a time: a subscriptions import can be hundreds.
  property var queue: []
  property int inFlight: 0
  readonly property int maxInFlight: 4

  readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")).replace(/\/$/, "")

  // Colors. Every slot's default comes from the theme (Retro, for now);
  // what you pick in the style panel (S) is kept in settings.json on top of
  // it, so it carries over to other themes. Any of them can be see-through
  // (#aarrggbb), say program cells over a background picture.
  readonly property var colorSlots: [
    { section: "GUIDE", key: "text", label: "Text", value: "#f2f4ff" },
    { section: "GUIDE", key: "textDim", label: "Secondary text", value: "#9fb0f0" },
    { section: "GUIDE", key: "accent", label: "Accent", value: "#ffd23f" },
    { section: "GUIDE", key: "timeline", label: "Timeline (now line)", value: "#ff4d4d" },
    { section: "GUIDE", key: "cell", label: "Program cell", value: "#1b3591" },
    { section: "GUIDE", key: "cellBorder", label: "Cell border", value: "#3b5bd1" },
    { section: "GUIDE", key: "channelCell", label: "Channel cell", value: "#0f2470" },
    { section: "GUIDE", key: "selected", label: "Selected program", value: "#ffd23f" },
    { section: "GUIDE", key: "selectedText", label: "Selected program text", value: "#141414" },
    { section: "GUIDE", key: "header", label: "Time bar", value: "#ffd23f" },
    { section: "GUIDE", key: "headerText", label: "Time bar text", value: "#141414" },
    { section: "GUIDE", key: "band", label: "Category band", value: "#030a2b" },
    { section: "GUIDE", key: "bandText", label: "Category band text", value: "#ffd23f" },
    { section: "GUIDE", key: "infoPanel", label: "Info panel", value: "#40000000" },
    { section: "GUIDE", key: "preview", label: "Preview box", value: "#000000" },
    { section: "GUIDE", key: "alert", label: "Alerts (no signal, tuned dot)", value: "#ff4d4d" },
    { section: "BACKGROUND", key: "bgTop", label: "Background, top", value: "#071447" },
    { section: "BACKGROUND", key: "bgBottom", label: "Background, bottom", value: "#030a2b" },
    { section: "LOWER THIRD", key: "ltBg", label: "Background", value: "#eb081447" },
    { section: "LOWER THIRD", key: "ltBorder", label: "Border", value: "#3b5bd1" },
    { section: "LOWER THIRD", key: "ltNumber", label: "Channel number", value: "#ffd23f" },
    { section: "LOWER THIRD", key: "ltChannel", label: "Channel name", value: "#9fb0f0" },
    { section: "LOWER THIRD", key: "ltTitle", label: "Show title", value: "#f2f4ff" },
    { section: "LOWER THIRD", key: "ltProgress", label: "Progress bar", value: "#ffd23f" },
    { section: "LOWER THIRD", key: "ltTrack", label: "Progress track", value: "#1b3591" },
    { section: "LOWER THIRD", key: "ltClock", label: "Clock", value: "#f2f4ff" },
    { section: "LOWER THIRD", key: "ltTime", label: "Show times", value: "#ffd23f" },
    { section: "CHANNEL CARD", key: "cardBackdrop", label: "Backdrop", value: "#d1000000" },
    { section: "CHANNEL CARD", key: "cardName", label: "Number and name", value: "#ffd23f" },
    { section: "CHANNEL CARD", key: "cardStatus", label: "Tuning text", value: "#9fb0f0" },
    { section: "CHANNEL CARD", key: "cardFrame", label: "Logo frame", value: "#3b5bd1" },
    { section: "BOXES & KEYS", key: "boxBg", label: "Box background", value: "#071447" },
    { section: "BOXES & KEYS", key: "boxBorder", label: "Box border", value: "#ffd23f" },
    { section: "BOXES & KEYS", key: "scrim", label: "Shade behind boxes", value: "#bf030a2b" },
    { section: "BOXES & KEYS", key: "keyFace", label: "Keycap", value: "#e4e9ff" },
    { section: "BOXES & KEYS", key: "keyText", label: "Keycap letter", value: "#0b1550" },
    { section: "BOXES & KEYS", key: "keyEdge", label: "Keycap edge", value: "#46559a" },
    { section: "BOXES & KEYS", key: "miniBar", label: "Mini player bar", value: "#eb030a2b" }
  ]
  property var colorOverrides: ({})
  readonly property var colors: {
    var p = {}
    var theme = currentTheme.colors || {}
    for (var i = 0; i < colorSlots.length; i++) {
      var key = colorSlots[i].key
      var v = colorOverrides[key] || theme[key] || colorSlots[i].value
      p[key] = Look.isOmarchy(v) ? omarchyColors[v.slice(8)] || colorSlots[i].value : v
    }
    return p
  }
  // Your Omarchy theme's colors (colors.toml), for themes that follow it
  // ("omarchy.blue"). Read again each time the guide opens.
  property var omarchyColors: ({})

  // Themes. Retro is built in (the slots' own values); the others are files:
  // the plugin's in themes/, and yours (or an agent's, through addTheme) in
  // ~/.config/om-pg/themes/. A theme gives the slots their defaults, and may
  // set the picture, the banner and the card when it's put on.
  readonly property var retroTheme: ({ id: "retro", name: "Retro", builtIn: true, colors: {},
                                       description: "The old-school cable guide: navy blue and marquee yellow." })
  property var themes: [retroTheme]
  readonly property string defaultThemeId: "premiere"   // a first start's, and the original look (reset original)
  property string themeId: defaultThemeId
  property bool themePending: false     // a first start's theme, put on once the theme files are read
  readonly property var currentTheme: {
    for (var i = 0; i < themes.length; i++) if (themes[i].id === themeId) return themes[i]
    return retroTheme
  }
  readonly property string themesDir: configDir + "/themes"

  // The settings box (,) and the AI agent skill
  property int settingsCursor: 0
  property bool agentSkill: false      // the skill linked into agents' skill folders
  property bool agentAsked: false      // the first-open question has been asked
  property bool agentSettled: false    // you turned it on or off, or said no: the strip stops asking
  property bool demoAsked: true        // a first start asks, once, about the demo channels
  property bool appsAsked: true        // and about turning apps on
  property bool recAsked: true         // the strip about Recordings answered, once (new and updated)
  property var skillLinks: []          // where it's linked
  property string skillSaved: ""        // where Save the agent skill put its copy (~ for home)
  property bool skillSaveFailed: false
  property bool settingsLoaded: false
  readonly property string skillDir: pluginDir + "/skills/program-guide"
  readonly property color navy: colors.bgTop
  readonly property color navyDeep: colors.bgBottom
  readonly property color cell: colors.cell
  readonly property color cellEdge: colors.cellBorder
  readonly property color channelCell: colors.channelCell
  readonly property color ink: colors.text
  readonly property color dimInk: colors.textDim
  readonly property color marquee: colors.accent
  readonly property color marqueeInk: colors.selectedText
  readonly property color nowLine: colors.alert
  readonly property color miniBarColor: colors.miniBar

  // Pictures for areas of the guide, over the area's color and under its
  // text. Yours (imageOverrides, full paths) go over the theme's (names in
  // its folder). row: its name in the style panel; fit and opacity: the
  // starting ones.
  readonly property var imageSlots: [
    { key: "masthead", row: "Logo, in place of the title", fit: "fit", opacity: 1 },
    { key: "infoPanel", row: "Info panel", fit: "fill", opacity: 0.6 },
    { key: "header", row: "Time bar", fit: "fill", opacity: 0.8 },
    { key: "band", row: "Category bands", fit: "fill", opacity: 0.8 },
    { key: "channelCell", row: "Channel column", fit: "tile", opacity: 0.35 },
    { key: "cell", row: "Program cells", fit: "tile", opacity: 0.35 },
    { key: "lt", row: "Picture", fit: "fill", opacity: 0.9 },
    { key: "card", row: "Picture", fit: "fill", opacity: 1 },
    { key: "box", row: "Box picture", fit: "fill", opacity: 0.5 }
  ]
  readonly property var imageFits: ["fill", "fit", "stretch", "tile", "center", "frame"]
  property var imageOverrides: ({})    // area -> { src: a full path, or "" for none; fit; opacity }
  readonly property var areaImages: {
    var out = {}
    var theme = currentTheme.images || {}
    for (var i = 0; i < imageSlots.length; i++) {
      var slot = imageSlots[i]
      var spec = imageOverrides[slot.key] !== undefined ? imageOverrides[slot.key] : theme[slot.key]
      var path = !spec || !spec.src ? "" : spec.src.charAt(0) === "/" ? spec.src : currentTheme.dir ? currentTheme.dir + "/" + spec.src : ""
      out[slot.key] = !path ? null : { url: fileUrl(path), path: path, fit: imageFits.indexOf(spec.fit) >= 0 ? spec.fit : slot.fit,
                                       opacity: typeof spec.opacity === "number" ? spec.opacity : slot.opacity }
    }
    return out
  }

  // A file's path as a URL (spaces, # and the like escaped)
  function fileUrl(path) {
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
  }

  // A picture behind the guide: "none", "wallpaper" (Omarchy's) or "image".
  property string bgMode: "none"
  property string bgImage: ""
  property real bgDim: 0.6
  // where the picture came from: "theme" (put on with a theme, or a reset to
  // it), "user" (picked in the style panel, or given to the background
  // command) or "" (not known: saved before this was kept); recorded where
  // it's chosen, and kept in settings.json (Look.bgProvenance)
  property string bgFrom: ""
  // your Omarchy wallpaper (it follows the theme you put on)
  readonly property string wallpaperUrl: fileUrl(Quickshell.env("HOME") + "/.local/state/omarchy/current/background")
  // an app's screen keeps the picture behind under the 30% floor unless it's
  // surely yours (one of unknown origin too); yours and your wallpaper go as
  // you set them
  readonly property bool bgFloored: Look.bgFloored(bgMode, bgImage, bgFrom)
  readonly property string backgroundSource: bgMode === "wallpaper" ? wallpaperUrl
                                            : bgMode === "image" && bgImage ? fileUrl(bgImage) : ""
  // The lower third (the channel banner) and the channel card: on, and for how long.
  property bool ltShow: true
  property real ltSeconds: 4
  property bool cardShow: true
  property real cardSeconds: 1.4

  // The style panel (S)
  property int styleCursor: 1
  property string styleEditing: ""    // the slot the picker is open on
  property string styleBefore: ""     // its override before picking ("" for none)
  property string styleArmed: ""      // the reset row waiting for its second Enter
  property bool styleNaming: false     // the box naming a look to save as a theme is open
  property string namingNote: ""       // what it says under the name (taken, built in…)
  property string styleRefused: ""     // a theme change refused while another is being made
  onStyleRefusedChanged: if (root.styleRefused) styleRefusedTimer.restart()
  property string namingArmed: ""      // a taken name, waiting for Enter again to replace it
  property var beforeReset: null       // the look before the last reset, for undo
  property string lookSaving: ""       // a reset's or undo's write for all apps, still out (its token)
  // Which list the panel shows: main, parts, element (one part), layout or
  // fonts. Esc goes back up through styleStack.
  property string styleView: "main"
  property string styleElement: ""     // the part being styled (element key)
  property string styleState: ""       // ...in this state, or "" for as it is
  property var styleStack: []          // [{ view, cursor }] to go back to
  readonly property string styleTarget: styleState ? styleElement + ":" + styleState : styleElement
  readonly property string styleAbout: {
    var about = (Look.BY_KEY[styleElement] || {}).about || ""
    return about.charAt(0).toUpperCase() + about.slice(1)
  }
  readonly property var usableFonts: Look.usableFonts(installedFonts)
  readonly property var styleRows: styleView === "parts" ? partRows : styleView === "element" ? elementRows
                                 : styleView === "layout" ? layoutRows : styleView === "fonts" ? fontRows : mainStyleRows
  readonly property var partRows: {
    var rows = []
    var section = ""
    for (var i = 0; i < Look.ELEMENTS.length; i++) {
      var el = Look.ELEMENTS[i]
      if (el.section !== section) { section = el.section; rows.push({ type: "header", label: section }) }
      rows.push({ type: "part", key: el.key, label: el.label })
    }
    return rows
  }
  readonly property var elementRows: {
    var el = Look.BY_KEY[styleElement]
    if (!el) return [{ type: "header", label: "" }]
    var rows = [{ type: "header", label: el.section }]
    if (el.states) rows.push({ type: "state" })
    var props = Look.propList(styleElement, styleState)
    for (var i = 0; i < props.length; i++) {
      var r = props[i]
      rows.push({ type: "prop", path: r.path, kind: r.kind, label: r.label, step: r.step, min: r.min, max: r.max, options: r.options })
    }
    rows.push({ type: "header", label: "" })
    rows.push({ type: "resetPart" })
    return rows
  }
  readonly property var layoutRows: [{ type: "header", label: "LAYOUT" }].concat(Look.LAYOUT.map(function(l) {
    return { type: "layout", key: l.key, label: l.label }
  }))
  readonly property var fontRows: [{ type: "header", label: "FONTS" }, { type: "font", key: "body", label: "Body: most text" },
                                   { type: "font", key: "display", label: "Display: title, clocks, numbers" }, { type: "font", key: "mono", label: "Mono: tags" }]
  readonly property var mainStyleRows: {
    var rows = [{ type: "header", label: "THEME" }, { type: "theme" }, { type: "saveTheme" },
                { type: "open", view: "parts", label: "Parts: shapes, sizes, text" }, { type: "open", view: "layout", label: "Layout" },
                { type: "open", view: "fonts", label: "Fonts" }]
    var section = ""
    for (var i = 0; i < colorSlots.length; i++) {
      var slot = colorSlots[i]
      if (slot.section !== section) {
        section = slot.section
        if (section === "LOWER THIRD") {
          rows.push({ type: "header", label: "PICTURES" })
          for (var g = 0; g < 6; g++) rows.push({ type: "image", key: imageSlots[g].key, label: imageSlots[g].row })
        }
        rows.push({ type: "header", label: section })
        if (section === "BACKGROUND") { rows.push({ type: "bg" }); rows.push({ type: "dim" }) }
        if (section === "LOWER THIRD") { rows.push({ type: "lt" }); rows.push({ type: "image", key: "lt", label: "Picture" }) }
        if (section === "CHANNEL CARD") { rows.push({ type: "card" }); rows.push({ type: "image", key: "card", label: "Picture" }) }
        if (section === "BOXES & KEYS") rows.push({ type: "image", key: "box", label: "Box picture" })
      }
      rows.push({ type: "color", key: slot.key, label: slot.label })
    }
    rows.push({ type: "header", label: "RESET" })
    if (themeId !== defaultThemeId) rows.push({ type: "resetTheme" })
    rows.push({ type: "resetOriginal" })
    if (beforeReset) rows.push({ type: "undoReset" })
    return rows
  }
  readonly property var pickerSwatches: ["#000000", "#ffffff", "#f2f4ff", "#9fb0f0", "#ffd23f", "#ff4d4d", "#f97316", "#22c55e",
                                         "#06b6d4", "#3b5bd1", "#1b3591", "#0f2470", "#071447", "#030a2b", "#a855f7", "#ec4899",
                                         "#64748b", "#1e293b", "#0f172a", "#00000000"]
  readonly property string fontFamily: Style.font.menuFamily

  // Element styles (Look.js): every part of the guide, styled by the theme,
  // with yours (the style panel, or setStyle) on top. And the fonts a theme
  // can set, by role: body, display (the title and clocks), mono.
  property var elementOverrides: ({})   // element (or element:state) -> its style
  property var fontOverrides: ({})      // role -> family
  readonly property var installedFonts: Qt.fontFamilies()
  readonly property var colorKeys: colorSlots.map(function(c) { return c.key })
  readonly property var fonts: {
    var theme = currentTheme.fonts || {}
    var out = {}
    for (var i = 0; i < Look.FONT_ROLES.length; i++) {
      var role = Look.FONT_ROLES[i]
      out[role] = fontOverrides[role] || theme[role] || fontFamily
    }
    return out
  }
  readonly property var look: Look.resolve(currentTheme.elements, elementOverrides, colors, fonts, omarchyColors)
  // How it's laid out (Look.js LAYOUT): the theme's, with yours on top
  property var layoutOverrides: ({})
  readonly property var layout: Look.effectiveLayout(currentTheme.layout, layoutOverrides)

  readonly property real u: Math.max(10, Math.round((windowed && guideWindow.height > 100 ? guideWindow.height : panel.height) / 60))

  // Text that reads on a fill: the color asked for, or dark on a light
  // fill and light on a dark one when the two are too alike
  function textOn(fill, normal) {
    if (!fill || fill === "transparent" || typeof fill === "object" && !("r" in fill)) return normal
    var f = Qt.lighter(fill, 1.0)
    if (f.a < 0.35) return normal
    var n = Qt.lighter(normal, 1.0)
    var lf = 0.2126 * f.r + 0.7152 * f.g + 0.0722 * f.b
    var ln = 0.2126 * n.r + 0.7152 * n.g + 0.0722 * n.b
    if (Math.abs(lf - ln) > 0.4) return normal
    return lf > 0.5 ? "#141414" : "#f4f4f4"
  }
  // on the row under the cursor in a list (settings, the style panel, Home's panel…)
  readonly property color currentRowText: textOn(look["listRow:current"].fill, colors.text)
  readonly property color currentRowDim: textOn(look["listRow:current"].fill, colors.textDim)
  readonly property real gap: layout.gap > 0 ? Math.max(1, Math.round(layout.gap * u)) : 0
  readonly property real chanW: u * layout.channelWidth
  readonly property real rowH: u * layout.rowHeight

  function open(payloadJson) {
    if (root.windowed && root.opened && !root.windowHere()) root.bringWindowHere()
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    if (root.pip) {   // back from the mini player
      root.pip = false
      player.videoOutput = video
    }
    // back from an app (it closed, or the guide's key over it): where you were
    var back = payload.back === true || (root.appUp !== "" && !payload.screen && payload.watch !== true)
    var fromOff = root.tvOff && !back
    root.tvOff = false
    root.opened = true
    root.watching = payload.watch === true && root.reception !== "off"
    if (["home", "guide", "library", "search"].indexOf(payload.screen) >= 0) root.screen = payload.screen === "home" && !root.homeEnabled ? "guide" : payload.screen
    else if (back) { var at = root.appsTiles.findIndex(function(t) { return t.id === root.appUp }); if (at >= 0) root.appsTile = at }
    else if (!root.watching) root.screen = root.homeEnabled ? "home" : "guide"
    root.homeEditing = false
    root.railOpen = false
    root.railEditing = false
    omarchyTheme.reload()
    videos.freshen()
    listings.freshen()
    root.now = Date.now() / 1000
    root.slotOffset = 0
    root.cursorTime = root.now
    // on the channel you were on: the one tuned, or after a restart the first
    // of your recent ones
    var last = root.tunedRow >= 0 && root.tunedRow < root.channels.length ? root.tunedRow : root.indexOf(root.recentChannels[0] || "")
    if (last >= 0) root.row = last
    // never on a channel the filter hides
    if (root.visibleRows.indexOf(root.row) < 0) root.row = root.visibleRows[0] || 0
    // closed while watching it: back to watching it (not a locked one: that waits for you)
    var resume = root.resumeWatch && !back && !payload.screen && payload.watch !== true && last >= 0 && root.row === last
                 && !channelLockItem.blocks(root.channels[last])
    root.rollDay()
    if (root.now - root.fetchedAt > root.staleAfter) root.refresh()
    else {
      root.fetchMissing()
      if (root.now - root.liveCheckedAt > 900) root.checkLive()   // what's live isn't kept: after a restart, none is known
    }
    streamer.running = true
    if (resume) root.watch(last)
    previewTimer.restart()
    agentAskTimer.restart()
    if (fromOff && root.splashOn) splashItem.start()
    Qt.callLater(function() { keys.forceActiveFocus(); root.showRow(root.row) })
  }

  // The preview box plays whichever channel the cursor rests on.
  onRowChanged: {
    if (root.opened && !root.watching) previewTimer.restart()
    warmTimer.restart()
  }

  function previewRow() {
    if (!root.opened || root.watching || root.managing || root.screen !== "guide" || multiviewItem.active) return
    if (root.mvWaitingFor === root.mvRequest) return   // an agent's Multiview on its way
    var ch = root.channels[root.row]
    if (!root.airs(ch)) return
    // a locked one shows a lock instead (Enter asks for the passcode)
    if (channelLockItem.blocks(ch)) { if (root.reception !== "off" && !root.pip) root.turnOff(); return }
    // one from a provider a recording is using waits too (a preview isn't worth a 2nd stream)
    if (dvr.needsAsk(ch) && !(root.row === root.tunedRow && root.reception !== "off")) { if (root.reception !== "off" && !root.pip) root.turnOff(); return }
    if (root.row === root.tunedRow && (root.reception === "tuning" || root.reception === "on")) return
    root.tune(root.row)
  }

  // The channel on, checked again (the lock changed, it was read, or an
  // unlock ran out): one that's blocked now stops, in the guide, full screen
  // or the mini player (a movie isn't a channel)
  function enforceLock() {
    if (root.multiview) root.multiview.enforceLock()   // a tile on a channel that's locked now stops, sound or not
    if (root.vod) {
      if (root.vod.videoId && root.videoLockedBy(root.vod.videoId, root.vod.subtitle, root.vod.owners, root.vod.ownersMore)) root.turnOff()
      // a recording of a channel that's locked now stops too
      else if (root.vod.recId && dvr.locked(dvr.byId[root.vod.recId] || { channel: { hash: root.vod.recHash } })) root.turnOff()
      return
    }
    if (root.reception === "off" || root.tunedRow < 0) return
    if (channelLockItem.blocks(root.channels[root.tunedRow])) root.turnOff()
  }

  // A locked channel you asked for: the passcode first (the guide comes up
  // for it, if it's away), then on with what you were doing. True if it asked
  function askToWatch(r, then) {
    var ch = root.channels[r]
    if (!channelLockItem.blocks(ch)) return false
    if (!root.opened) root.summonGuide(false)
    return channelLockItem.askUnlock(ch, then)
  }

  // Asks the streamer for what the channels around the cursor are airing
  // now, so its cache has them ready before anyone tunes in.
  function warm() {
    if (!root.streamBase) return
    var t = Date.now() / 1000
    var v = root.visibleRows
    var p = Math.max(0, v.indexOf(root.row))
    for (var q = Math.max(0, p - 2); q <= Math.min(v.length - 1, p + 5); q++) {
      var ch = root.channels[v[q]]
      if (!root.airs(ch) || ch.kind === "iptv") continue   // IPTV streams play directly
      var id = ch.live ? ch.live.id : root.lineupOf(ch)[Schedule.locate(root.lineupOf(ch), t).index].id
      var request = new XMLHttpRequest()
      request.open("GET", root.streamBase + "/play/" + id + ".m3u8")
      request.send()
    }
  }

  // The guide going away turns the TV off, unless it went into the mini player.
  // In a window on another desktop, the guide's key brings it to you instead.
  function close() {
    if (root.windowed && root.opened && !root.pip && !root.windowHere()) { root.bringWindowHere(); return }
    root.closeNow()
  }

  function closeNow() {
    root.mvRequest += 1   // an agent's Multiview still on its way doesn't start
    if (root.appOpening) root.cancelAppOpen()   // put away while one was coming: it's called off
    var wasOpen = root.opened   // (closing runs twice: here, and as the shell hides it)
    root.opened = false
    splashItem.skip()
    channelLockItem.abandon()   // the lock's box and anything it was asking go with the guide
    if (!root.pip) {
      var resume = root.watching && !root.vod && root.tunedRow >= 0   // watching a channel: opening plays it again
      if (wasOpen && resume !== root.resumeWatch) { root.resumeWatch = resume; root.saveSettings() }
      root.turnOff(); channelLockItem.relock(); root.tvOff = true
    }
    library.flush()
  }

  // ---- full screen, or a window ----

  // Full screen: over everything, the Omarchy bar too (a layer of the shell).
  // A window: an ordinary window, maximized, the bar showing; it stays on its
  // desktop while you work on another, and the guide's key brings it back to
  // you. W switches, and Settings; settings.json keeps it.
  property string displayMode: "full"
  readonly property bool windowed: displayMode === "window"
  // Keeping the screen awake: off, while a video plays, or while the guide
  // is on screen (Awake.js). In settings.json.
  property string awake: AwakeRules.DEFAULT
  readonly property bool keptAwake: awakeItem.holding
  property bool remapping: false

  function setDisplay(mode) {
    mode = mode === "window" ? "window" : "full"
    if (mode === root.displayMode) return mode
    root.displayMode = mode
    root.placeScreen()
    root.saveSettings()
    return mode
  }

  function toggleDisplay() { return root.setDisplay(root.windowed ? "full" : "window") }

  // The guide's contents go in whichever is showing
  function placeScreen() {
    var into = root.windowed ? guideWindow.contentItem : panel.contentItem
    if (into && screenItem.parent !== into) screenItem.parent = into
    Qt.callLater(function() { keys.forceActiveFocus() })
  }

  // Whether the guide's window is on the desktop you're on
  function windowHere() {
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    var ws = Hyprland.focusedWorkspace
    for (var i = 0; i < tops.length; i++) {
      var t = tops[i]
      if (t && t.title === guideWindow.title && t.workspace && ws) return t.workspace.id === ws.id
    }
    return true
  }

  // Shows the window again, which puts it on the desktop you're on
  function bringWindowHere() {
    root.remapping = true
    remapTimer.restart()
  }

  // Omarchy keeps apps from maximizing themselves (its windows rule), so the
  // window asks Hyprland once it's up: maximized, set outright (a toggle, or
  // Omarchy's takeover of a fullscreen desktop, could leave it fullscreen,
  // over the bar), and again a second later
  property int maximizeTries: 0
  function maximizeWindow() {
    root.maximizeTries = 0
    maximizeTimer.interval = 250
    if (Hyprland.refreshToplevels) Hyprland.refreshToplevels()
    maximizeTimer.restart()
  }

  Timer {
    id: maximizeTimer
    interval: 250
    onTriggered: {
      var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
      for (var i = 0; i < tops.length; i++) {
        var t = tops[i]
        if (!t || t.title !== guideWindow.title) continue
        var a = String(t.address || "")
        if (!a) break
        if (!/^0x/.test(a)) a = "0x" + a
        Hyprland.dispatch('hl.dsp.window.fullscreen_state({ internal = 1, client = 1, window = "address:' + a + '" })')
        if (root.maximizeTries < 100) { root.maximizeTries = 100; maximizeTimer.interval = 1000; maximizeTimer.restart() }
        else maximizeTimer.interval = 250
        return
      }
      if (++root.maximizeTries < 8) maximizeTimer.restart()
    }
  }

  Timer {
    id: remapTimer
    interval: 80
    onTriggered: {
      root.remapping = false
      Qt.callLater(function() { keys.forceActiveFocus() })
    }
  }

  function dismiss() {
    root.closeNow()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "marcho78.om-pg")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // Listings

  // Channels already loaded keep their listings, so saving the list (or
  // editing the file by hand) doesn't refetch everything.
  // False if raw isn't a list of channels (nothing changes then)
  function loadChannels(raw) {
    var parsed
    try { parsed = JSON.parse(raw) } catch (e) { console.warn("om-pg: " + root.listPath + " is not valid JSON"); return false }
    if (!Array.isArray(parsed)) return false
    var known = {}
    for (var j = 0; j < root.channels.length; j++) known[root.channels[j].url] = root.channels[j]
    var list = []
    for (var i = 0; i < parsed.length; i++) {
      var c = parsed[i]
      var category = c && typeof c.category === "string" ? c.category.trim().slice(0, 40) : ""
      if (c && c.kind === "iptv" && root.isStreamUrl(c.url)) {
        list.push(root.iptvChannel(c.name || c.url, c.url, category, c.logo, c.tvgId, c.src))
        continue
      }
      if (!c || !root.isYouTube(c.url)) {
        if (c && c.url) console.warn("om-pg: skipping " + JSON.stringify(c.url) + " in " + root.listPath + ": not a YouTube link or an IPTV stream")
        continue
      }
      var liveId = typeof c.liveId === "string" && /^[\w-]{11}$/.test(c.liveId) ? c.liveId : ""   // the live stream it was added by
      var had = known[c.url]
      list.push(had ? root.changed(had, { name: c.name || c.url, category: category, liveId: liveId })
                    : { name: c.name || c.url, url: c.url, category: category, items: [], state: "loading", channelId: "", liveId: liveId })
    }
    root.setChannels(list)
    root.applyCache()
    if (root.opened) root.fetchMissing()
    root.migrateVod()
    return true
  }

  // Playlists added before the library put their movies in the guide as
  // channels. Those move to the library (a copy of the list is kept first,
  // as channels.json.before-library).
  property bool vodMoved: false
  function migrateVod() {
    if (root.vodMoved || !library.loaded || !root.channels.length) return
    var movies = root.channels.filter(function(c) { return c.kind === "iptv" && library.isVodUrl(c.url) })
    root.vodMoved = true
    if (movies.length) listBackup.running = true   // then moveVod, once the copy is made
  }

  function moveVod() {
    var movies = root.channels.filter(function(c) { return c.kind === "iptv" && library.isVodUrl(c.url) })
    if (!movies.length) return
    library.add(movies.map(function(c) { return { url: c.url, name: c.name, category: c.category, logo: c.logo, description: "" } }), "your guide")
    root.setChannels(root.channels.filter(function(c) { return !(c.kind === "iptv" && library.isVodUrl(c.url)) }))
    root.saveChannels()
    console.log("om-pg: moved " + movies.length + " movies from the guide to the library")
  }

  // IPTV

  // A stream a player may open: http or https, nothing else.
  function isStreamUrl(url) {
    return /^https?:\/\/[^\s"'<>]+$/.test(String(url || "")) && String(url).length < 2048
  }

  // An IPTV channel: always live, playing its stream directly. Until there's
  // a guide for it (EPG), its row is one LIVE block with its name. src: the
  // playlist it came from, as an opaque id (Dvr.js providerOf: two streams
  // from one provider may be one too many)
  function iptvChannel(name, url, category, logo, tvgId, src) {
    name = String(name || "").trim().slice(0, 60) || "Channel"
    return {
      kind: "iptv", name: name, url: url, category: category || "", src: /^[0-9a-f]{12}$/.test(String(src || "")) ? String(src) : "",
      logo: root.isStreamUrl(logo) ? logo : "", tvgId: String(tvgId || "").slice(0, 100),
      items: [], state: "ready", channelId: "", live: { id: "", title: name }
    }
  }

  // An M3U playlist's channels: names, logos, groups (as categories) and
  // streams. YouTube links in it become YouTube channels; other links that
  // aren't web streams (rtmp, udp, files) are left out.
  function parseM3u(text) {
    var out = []
    var info = null
    var lines = String(text).split(/\r?\n/)
    for (var i = 0; i < lines.length && out.length < 3000; i++) {
      var line = lines[i].trim()
      if (!line) continue
      if (/^#EXTM3U/i.test(line)) {   // its program listings, if it names them
        var g = line.match(/(?:url-tvg|x-tvg-url)="([^"]*)"/gi) || []
        out.guides = []
        for (var gi = 0; gi < g.length; gi++)
          g[gi].replace(/^[^"]*"|"$/g, "").split(",").forEach(function(u) { u = u.trim(); if (/^https?:\/\//.test(u) && out.guides.indexOf(u) < 0) out.guides.push(u) })
        continue
      }
      if (/^#EXTINF/i.test(line)) {
        var attrs = {}
        var head = line
        var comma = -1
        var quoted = false
        for (var k = 0; k < line.length; k++) {   // the name follows the first comma outside quotes
          if (line.charAt(k) === '"') quoted = !quoted
          else if (line.charAt(k) === "," && !quoted) { comma = k; break }
        }
        if (comma >= 0) head = line.slice(0, comma)
        var re = /([\w-]+)="([^"]*)"/g
        var m
        while ((m = re.exec(head)) !== null) attrs[m[1].toLowerCase()] = m[2]
        info = { name: comma >= 0 ? line.slice(comma + 1).trim() : "", attrs: attrs, desc: attrs["tvg-description"] || "" }
        continue
      }
      if (/^#EXTDESC:/i.test(line) && info) { info.desc = line.slice(9).trim(); continue }
      if (line.charAt(0) === "#") continue
      var a = info ? info.attrs : {}
      var desc = info ? info.desc : ""
      var name = (info && info.name) || a["tvg-name"] || ""
      var category = (a["group-title"] || "").split(";")[0].trim().slice(0, 40) || "IPTV"
      info = null
      var yt = root.channelUrl(line)
      if (/youtube\.com\/|youtu\.be\//.test(line) && yt) out.push({ url: yt, name: name, category: category })
      else if (root.isStreamUrl(line) && library.isVodUrl(line)) out.push({ vod: true, url: line, name: name, category: a["group-title"] ? category : "", logo: a["tvg-logo"] || "", description: desc })
      else if (root.isStreamUrl(line)) out.push({ iptv: true, url: line, name: name, category: category, logo: a["tvg-logo"] || "", tvgId: a["tvg-id"] || "" })
    }
    return out
  }

  // A pasted link that isn't YouTube: a playlist, or a single stream.
  // GitHub's page for a file becomes the file itself.
  function importIptvUrl(url) {
    url = url.replace(/^https:\/\/github\.com\/([^\/]+)\/([^\/]+)\/blob\//, "https://raw.githubusercontent.com/$1/$2/")
    root.addStatus = "Fetching the playlist…"
    // the link goes to curl on its stdin, never its command line (IPTV links
    // can hold logins, and a command line is readable by anyone on the computer)
    playlistFetcher.createObject(root, { url: url }).start(
      ["/usr/bin/curl", "-fsSL", "--proto", "=http,https", "--proto-redir", "=http,https", "--max-filesize", "20000000", "--max-time", "30", "-K", "-"],
      "url = \"" + url.replace(/\\/g, "\\\\").replace(/"/g, "\\\"") + "\"\n")
    return "fetching"
  }

  function playlistFetched(url, text, code) {
    var t = String(text || "")
    if (code !== 0 || !t) return root.rejectAdd("Couldn't fetch that link.")
    if (/^\s*#EXTM3U/.test(t) && /#EXTINF/i.test(t)) return root.addCandidates(root.parseM3u(t), url)
    if (/^\s*#EXTM3U/.test(t) && /#EXT-X-/.test(t)) {   // one stream, not a list of channels
      var host = url.replace(/^https?:\/\/([^\/:?#]+).*$/, "$1")
      return root.addCandidates([{ iptv: true, url: url, name: host, category: "IPTV", logo: "", tvgId: "" }])
    }
    return root.rejectAdd("That link isn't a playlist (M3U) or a stream.")
  }

  // A copy of channel ch with some fields changed.
  function changed(ch, changes) {
    var out = {}
    for (var k in ch) out[k] = ch[k]
    for (var c in changes) out[c] = changes[c]
    return out
  }

  // Replaces the list, keeping the tuned channel and the cursor on the same
  // channels even if they moved.
  function setChannels(list) {
    var tunedUrl = root.channels[root.tunedRow] ? root.channels[root.tunedRow].url : ""
    var rowUrl = root.channels[root.row] ? root.channels[root.row].url : ""
    root.channels = list
    root.tunedRow = root.indexOf(tunedUrl)
    if (root.tunedRow < 0 && root.reception !== "off") root.turnOff()
    var r = root.indexOf(rowUrl)
    root.row = r >= 0 ? r : Math.max(0, Math.min(root.row, list.length - 1))
  }

  // Puts a channel after the last one in its category; a new category goes
  // at the end, uncategorized channels at the top.
  function insertGrouped(list, entry) {
    var cat = entry.category || ""
    var last = -1
    for (var i = 0; i < list.length; i++) if ((list[i].category || "") === cat) last = i
    if (last >= 0) list.splice(last + 1, 0, entry)
    else if (!cat) list.unshift(entry)
    else list.push(entry)
    return list
  }

  // A channel's YouTube id, so the same channel by @handle and by id is one
  // channel. Not for playlists: a channel's playlist is a lineup of its own.
  function channelIdOf(url, listing) {
    return listing && !/[?&]list=/.test(url) ? (listing.channel_id || "") : ""
  }

  // A channel's avatar comes with its listing (no extra request); asked for at
  // 96 px, about 6 KB. Playlists have none.
  function logoOf(listing) {
    var thumbs = (listing && listing.thumbnails) || []
    var square = thumbs.filter(function(t) { return t && t.url && t.width && t.width === t.height })
                       .sort(function(a, b) { return b.width - a.width })[0]
    if (!square || !/^https:\/\/yt3\.(googleusercontent|ggpht)\.com\//.test(square.url)) return ""
    return square.url.replace(/=s\d+(-[^\/?#]*)?$/, "=s96-c-k-c0x00ffffff-no-rj")
  }

  // Through the streamer, which caches logos on disk and paces downloads.
  function logoSource(ch) {
    return root.showLogos ? root.logoFor(ch) : ""
  }

  // A channel's logo through the streamer's cache, whatever L is set to:
  // the channel-change card shows it.
  function logoFor(ch) {
    if (!root.streamBase || !ch || channelLockItem.blocks(ch)) return ""
    if (ch.kind === "iptv") return ch.logo ? root.streamBase + "/picon?src=" + encodeURIComponent(ch.logo) : ""
    if (!ch.channelId || !ch.logoUrl) return ""
    return root.streamBase + "/logo/" + ch.channelId + ".jpg?src=" + encodeURIComponent(ch.logoUrl)
  }

  function setKeyHints(on) {
    root.showKeyHints = on === true || on === "true"
    root.keyHintsNote = !root.showKeyHints
    if (root.keyHintsNote) keyHintsNoteTimer.restart()
    root.saveSettings()
    return String(root.showKeyHints)
  }

  function setLogos(on) {
    root.showLogos = on === true || on === "true"
    root.saveSettings()
    return String(root.showLogos)
  }

  // Saved only once the file has been read (before that, the guide's own
  // defaults would go over yours), and never over one that couldn't be read
  // (too big, a link, not a plain file): that file is kept as it is, and
  // state's settingsProblem says so
  function saveSettings() {
    if (!root.settingsLoaded || root.settingsProblem || root.wiping) return
    settings.setText(JSON.stringify({
      shownCategories: root.shownCategories, sources: root.shownSource, logos: root.showLogos, keyHints: root.showKeyHints, splash: root.splashOn, railCredits: root.railCredits, updates: { on: updatesItem.on, asked: updatesItem.asked }, lineup: root.lineupMode,
      remote: { enabled: root.remoteEnabled, port: root.remotePort, rules: root.remoteRules },
      pip: { width: Math.round(root.pipW), right: Math.round(root.pipRight), bottom: Math.round(root.pipBottom) },
      colors: root.colorOverrides,
      images: root.imageOverrides,
      elements: root.elementOverrides,
      fonts: root.fontOverrides,
      layout: root.layoutOverrides,
      home: { enabled: root.homeEnabled, sections: root.homeSections, tiles: root.homeTiles, background: root.homeBackground },
      multiview: { background: root.multiviewBackground },
      rail: root.railSetup,
      videos: { enabled: videos.enabled, folder: videos.folder },
      dvr: dvr.settings,
      libraryTabs: root.libraryOrder,
      search: { recent: root.recentSearches },
      display: root.displayMode,
      awake: root.awake,
      screenSaver: screenSaverItem.settings,
      listings: { sources: listings.sources },
      recent: root.recentChannels,
      resumeWatch: root.resumeWatch,
      background: { mode: root.bgMode, image: root.bgImage, dim: root.bgDim, from: root.bgFrom },
      lowerThird: { show: root.ltShow, seconds: root.ltSeconds },
      card: { show: root.cardShow, seconds: root.cardSeconds },
      theme: root.themeId,
      beforeReset: root.beforeReset,
      agent: { skill: root.agentSkill, asked: root.agentAsked, settled: root.agentSettled },
      firstStart: { demo: root.demoAsked, apps: root.appsAsked, recordings: root.recAsked },
      bar: { icon: root.barIcon, shortcut: root.shortcut }
    }, null, 2) + "\n")
  }

  function indexOfChannelId(id) {
    for (var i = 0; i < root.channels.length; i++) if (id && root.channels[i].channelId === id) return i
    return -1
  }

  function indexOf(url) {
    for (var i = 0; i < root.channels.length; i++) if (url && root.channels[i].url === url) return i
    return -1
  }

  // replan (R): the new listings become today's lineups too.
  function refresh(replan) {
    root.fetchedAt = Date.now() / 1000
    if (replan === true || replan === "true") {
      var r = {}
      for (var j = 0; j < root.channels.length; j++) r[root.channels[j].url] = true
      root.replanning = r
    }
    for (var k = 0; k < root.channels.length; k++)
      if (root.channels[k].kind !== "iptv") root.enqueue(root.channels[k].url, "listing")
    root.checkLive()
    if ((replan === true || replan === "true") && Date.now() / 1000 - listings.fetched > 600) listings.fetch()
  }

  function fetchMissing() {
    for (var k = 0; k < root.channels.length; k++) {
      if (root.channels[k].state !== "loading" || root.channels[k].kind === "iptv") continue
      root.enqueue(root.channels[k].url, "listing")
      root.checkLive(k)
    }
  }

  // Live channels

  // A channel's live streams are on its /streams tab; playlists have none.
  function liveUrlOf(url) {
    return /\/(@[^\/?#]+|channel\/[^\/?#]+|c\/[^\/?#]+|user\/[^\/?#]+)\/(videos|streams)$/.test(url)
           ? url.replace(/\/(videos|streams)$/, "/streams") : ""
  }

  // Looks up what's live on one channel (r), or on all of them.
  function checkLive(r) {
    if (r === undefined) root.liveCheckedAt = Date.now() / 1000
    for (var k = 0; k < root.channels.length; k++) {
      if (r !== undefined && k !== r) continue
      var live = root.liveUrlOf(root.channels[k].url)
      if (live) root.enqueue(live, "live")
    }
  }

  // Of a channel's streams live now, the one it was added by (a live
  // stream's link), else its round-the-clock one ("24/7", "livestream",
  // "Watch Sky News") if it says so, or the first.
  function liveChecked(url, text) {
    if (!url) return
    var listing = null
    try { listing = JSON.parse(text) } catch (e) { return }
    var on = ((listing && listing.entries) || []).filter(function(e) { return e && e.live_status === "is_live" && e.id })
    var usual = on.filter(function(e) { return /24\s*\/\s*7|live\s*stream|^watch\b/i.test(e.title || "") })[0] || on[0]
    var list = root.channels.slice()
    var touched = false
    for (var i = 0; i < list.length; i++) {
      if (root.liveUrlOf(list[i].url) !== url) continue
      var want = list[i].liveId || ""
      var pick = (want && on.filter(function(e) { return e.id === want })[0]) || usual
      var live = pick ? { id: pick.id, title: pick.title || "Live" } : null
      var was = list[i].live
      if ((was && was.id) === (live && live.id)) continue
      list[i] = root.changed(list[i], { live: live })
      touched = true
    }
    if (!touched) return
    root.channels = list
    if (root.opened && !root.watching) previewTimer.restart()
  }

  function airs(ch) {
    return !!ch && (ch.state === "ready" || !!ch.live)
  }

  // mode: "listing" (a channel's videos), "check" (a link being added) or
  // "search" (a channel name being looked up)
  function enqueue(url, mode) {
    for (var i = 0; i < root.queue.length; i++)
      if (root.queue[i].url === url && root.queue[i].mode === mode) return
    root.queue.push({ url: url, mode: mode })
    root.pump()
  }

  function pump() {
    while (root.inFlight < root.maxInFlight && root.queue.length) {
      var next = root.queue.shift()
      root.inFlight++
      fetcher.createObject(root, { url: next.url, mode: next.mode })
             .start(["/usr/bin/yt-dlp", "--flat-playlist", "-J", "--playlist-end", next.mode === "live" ? "10" : "40", "--no-warnings", "--", next.url])
    }
  }

  function received(url, text) {
    var list = root.channels.slice()
    var i = root.indexOf(url)
    var ch = list[i]
    if (!ch) return
    var items = []
    var listing = null
    try { listing = JSON.parse(text); items = Schedule.programs(listing) } catch (e) {}
    var force = !!root.replanning[url]
    if (force) {
      var r = root.changed(root.replanning, {})
      delete r[url]
      root.replanning = r
    }
    if (!items.length && ch.items.length) return
    list[i] = root.changed(ch, {
      items: items, state: items.length ? "ready" : "error", plan: root.planFor(ch, items, force),
      channelId: root.channelIdOf(url, listing), logoUrl: root.logoOf(listing)
    })
    root.channels = list
    if (i === root.row) previewTimer.restart()
    warmTimer.restart()
    cacheTimer.restart()
  }

  // The TV day a moment falls in, named by the date it starts on.
  function tvDay(t) {
    return Qt.formatDateTime(new Date(root.tvDayStart(t) * 1000), "yyyy-MM-dd")
  }

  // When the TV day holding t began: 4 AM by the clock, on the day the
  // clocks change too (not 4 hours after midnight, 3 or 5 AM then)
  function tvDayStart(t) {
    var d = new Date(t * 1000)
    d.setHours(root.dayStartsAt / 3600, 0, 0, 0)
    if (d.getTime() > t * 1000) { d.setDate(d.getDate() - 1); d.setHours(root.dayStartsAt / 3600, 0, 0, 0) }
    return d.getTime() / 1000
  }

  // What the schedule airs: today's plan, or the listing if there's none yet.
  function lineupOf(ch) {
    return ch && ch.plan && ch.plan.items && ch.plan.items.length ? ch.plan.items : (ch ? ch.items : [])
  }

  // Keeps today's plan unless asked (R), or it's a new day, or lineups follow
  // every listing.
  function planFor(ch, items, force) {
    var day = root.tvDay(Date.now() / 1000)
    if (force || root.lineupMode === "latest" || !ch.plan || ch.plan.day !== day || !ch.plan.items || !ch.plan.items.length)
      return { day: day, items: items }
    return ch.plan
  }

  // At 4 AM, every channel's lineup is planned afresh from its listing.
  // Also reachable from outside (t: a moment to plan for, for testing).
  function rollDay(t) {
    var day = root.tvDay(Number(t) || Date.now() / 1000)
    var list = root.channels.slice()
    var rolled = false
    for (var i = 0; i < list.length; i++) {
      if (!list[i].items.length || (list[i].plan && list[i].plan.day === day)) continue
      list[i] = root.changed(list[i], { plan: { day: day, items: list[i].items } })
      rolled = true
    }
    if (!rolled) return "same day"
    root.channels = list
    cacheTimer.restart()
    return "planned " + day
  }

  // The saved listings

  function cleanItems(items) {
    if (!Array.isArray(items)) return []
    return items.filter(function(v) {
      return v && /^[A-Za-z0-9_-]{11}$/.test(v.id) && v.duration >= Schedule.MIN_LENGTH && v.duration <= Schedule.MAX_LENGTH
    }).map(function(v) {
      return { id: v.id, title: String(v.title || v.id).slice(0, 300), duration: Math.round(v.duration), url: "https://www.youtube.com/watch?v=" + v.id }
    })
  }

  function loadListingCache(raw) {
    var saved
    try { saved = JSON.parse(raw) } catch (e) { return }
    if (!saved || saved.version !== 1 || typeof saved.channels !== "object") return
    var byUrl = {}
    for (var url in saved.channels) {
      var c = saved.channels[url]
      if (!root.isYouTube(url) || !c) continue
      var items = root.cleanItems(c.items)
      if (!items.length) continue
      var plan = c.plan && /^\d{4}-\d{2}-\d{2}$/.test(c.plan.day) ? { day: c.plan.day, items: root.cleanItems(c.plan.items) } : null
      byUrl[url] = {
        items: items, plan: plan && plan.items.length ? plan : null,
        channelId: /^UC[\w-]{22}$/.test(c.channelId || "") ? c.channelId : "",
        logoUrl: /^https:\/\/yt3\.(googleusercontent|ggpht)\.com\/[^\s]*$/.test(c.logoUrl || "") ? c.logoUrl : ""
      }
    }
    root.cachedListings = byUrl
    if (Number(saved.fetchedAt) > root.fetchedAt) root.fetchedAt = Number(saved.fetchedAt)
    root.applyCache()
  }

  // Fills in channels that have no listing yet from the saved ones.
  function applyCache() {
    var list = root.channels.slice()
    var filled = false
    for (var i = 0; i < list.length; i++) {
      var c = root.cachedListings[list[i].url]
      if (!c || list[i].items.length) continue
      list[i] = root.changed(list[i], { items: c.items, plan: c.plan, channelId: c.channelId, logoUrl: c.logoUrl, state: "ready" })
      filled = true
    }
    if (filled) root.channels = list
  }

  function saveListingCache() {
    if (root.wiping) return
    var out = { version: 1, fetchedAt: root.fetchedAt, channels: {} }
    for (var i = 0; i < root.channels.length; i++) {
      var ch = root.channels[i]
      if (!ch.items.length) continue
      out.channels[ch.url] = { items: ch.items, plan: ch.plan || null, channelId: ch.channelId || "", logoUrl: ch.logoUrl || "" }
    }
    listingCache.setText(JSON.stringify(out))
  }

  // The channel lock (ChannelLock.qml): a locked channel's shows say Locked,
  // one block from..to (or keep their titles if you allow it), and never come
  // with their pictures or descriptions. Everything that shows a channel's
  // shows asks here.
  function titlesHidden(ch) { return channelLockItem.blocks(ch) && !channelLockItem.titles }
  // for Recordings (DVR.qml): a channel blocked now, and one the lock protects (unlocked or not)
  function blocksChannel(ch) { return channelLockItem.blocks(ch) }
  function lockProtects(ch) { return channelLockItem.isLocked(ch) }
  // the providers Multiview's tiles stream from (a recording may be one stream too many)
  function multiviewProviders() {
    if (!root.multiview || !root.multiview.active) return []
    var out = []
    var slots = root.multiview.slots || []
    for (var i = 0; i < slots.length; i++) {
      var r = root.indexOf(slots[i])
      var p = r >= 0 ? DvrRules.providerOf(root.channels[r]) : ""
      if (p) out.push(p)
    }
    return out
  }

  // A locked channel's videos (On Demand) are locked with it: which of your
  // YouTube channels each video is on, by its id (one upload can be on
  // several)
  readonly property var videoOwner: {
    var out = {}
    for (var i = 0; i < channels.length; i++) {
      var c = channels[i]
      if (c.kind === "iptv" || !c.items) continue
      for (var j = 0; j < c.items.length; j++) {
        var id = c.items[j].id
        if (!Object.prototype.hasOwnProperty.call(out, id)) out[id] = []
        if (out[id].indexOf(i) < 0) out[id].push(i)
      }
    }
    return out
  }
  readonly property var videoChannelsByUrl: LockRules.byAddress(channels)
  function videoRows(videoId) {
    var m = String(videoId || "").match(/^(?:yt:)?([A-Za-z0-9_-]{11})$/)
    return m && Object.prototype.hasOwnProperty.call(root.videoOwner, m[1]) ? root.videoOwner[m[1]] : []
  }
  // The addresses of the channels a video is on now, with those kept with it
  // (Library.qml keeps them with what you watch or save)
  function videoOwners(videoId, kept) {
    var out = (kept || []).slice()
    root.videoRows(videoId).forEach(function(r) { if (out.indexOf(root.channels[r].url) < 0) out.push(root.channels[r].url) })
    return out
  }
  // The locked channel a video is from, or null if none is: any channel it's
  // on now, kept with it or carried by its entry (owners), so a channel
  // renamed or removed still locks it (for an older record kept without
  // them, its channel's name; for one with more than were kept, its record's
  // mark or its entry's (more), any locked channel)
  function videoLockedBy(videoId, name, owners, more) {
    var m = String(videoId || "").match(/^(?:yt:)?([A-Za-z0-9_-]{11})$/)
    var h = m ? library.history["yt:" + m[1]] || {} : {}
    var kept = (Array.isArray(h.owners) ? h.owners : []).concat(Array.isArray(owners) ? owners : [])
    return LockRules.videoChannels(root.channels, root.videoChannelsByUrl, root.videoRows(videoId), kept, name || "", channelLockItem.entries, h.ownersMore === true || more === true)
             .filter(function(c) { return channelLockItem.blocks(c) })[0] || null
  }
  // Older records, kept before the lock, get their channels' addresses while
  // their video or channel's name can still be found
  function fillVideoOwners() {
    if (!library.historyLoaded || !channelLockItem.loaded || !root.channels.length) return
    library.fillOwners(function(h) {
      return LockRules.videoChannels(root.channels, root.videoChannelsByUrl, root.videoRows(h.ref), [], h.subtitle, channelLockItem.entries, false).map(function(c) { return c.url })
    })
  }
  onVideoOwnerChanged: ownerFill.restart()
  Timer { id: ownerFill; interval: 3000; onTriggered: root.fillVideoOwners() }
  function lockedShows(ch, shows, from, to) {
    if (!channelLockItem.blocks(ch)) return shows
    if (!channelLockItem.titles) return [{ locked: true, live: false, id: "", title: "Locked", start: from, end: to }]
    return shows.map(function(s) { return Object.assign({}, s, { id: "", desc: "" }) })
  }

  function showsFor(r) {
    return root.lockedShows(root.channels[r], root.airingFor(r), root.windowStart - 3600, root.windowEnd + 3600)
  }
  function airingFor(r) {
    var ch = root.channels[r]
    if (ch && ch.kind === "iptv" && listings.has(ch.url)) return root.listedShows(ch, root.windowStart, root.windowEnd)
    if (ch && ch.live)
      return [{ live: true, id: ch.live.id, title: ch.live.title, start: root.windowStart - 3600, end: root.windowEnd + 3600 }]
    if (!ch || ch.state !== "ready") return []
    return Schedule.airing(root.lineupOf(ch), root.windowStart, root.windowEnd)
  }

  // An IPTV channel's shows from its listings between two times, the gaps
  // (no listing) filled with its LIVE block
  function listedShows(ch, from, to) {
    var list = listings.between(ch.url, from, to)
    var out = []
    var at = from - 3600
    var gap = function(a, b) { if (b - a > 60) out.push({ live: true, id: "", title: ch.live.title, start: a, end: b }) }
    for (var i = 0; i < list.length; i++) {
      gap(at, list[i].start)
      out.push(list[i])
      at = list[i].end
    }
    gap(at, to + 3600)
    return out
  }

  // What follows show s, even when it starts past the end of the grid.
  function nextShow(r, s) {
    var ch = root.channels[r]
    if (root.titlesHidden(ch) || (s && s.locked)) return null
    var after = root.nextAiring(r, s)
    return after && channelLockItem.blocks(ch) ? Object.assign({}, after, { id: "", desc: "" }) : after
  }
  function nextAiring(r, s) {
    var ch = root.channels[r]
    if (ch && ch.kind === "iptv" && listings.has(ch.url)) return listings.after(ch.url, s.end)
    if (!ch || ch.live || s.live || ch.state !== "ready" || root.lineupOf(ch).length < 2) return null
    var after = Schedule.airing(root.lineupOf(ch), s.end, s.end + 1)
    return after.length ? after[0] : null
  }

  function showAt(r, t) {
    var shows = root.showsFor(r)
    for (var i = 0; i < shows.length; i++)
      if (t >= shows[i].start && t < shows[i].end) return shows[i]
    return shows.length ? shows[0] : null
  }

  // Adding and removing channels

  // Never over a list that couldn't be read: that file is kept as it is,
  // and listProblem says so
  function saveChannels() {
    if (root.wiping || root.listProblem) return
    var out = []
    for (var i = 0; i < root.channels.length; i++) {
      var ch = root.channels[i]
      var c = { name: ch.name, url: ch.url }
      if (ch.category) c.category = ch.category
      if (ch.liveId) c.liveId = ch.liveId
      if (ch.kind === "iptv") {
        c.kind = "iptv"
        if (ch.logo) c.logo = ch.logo
        if (ch.tvgId) c.tvgId = ch.tvgId
        if (ch.src) c.src = ch.src
      }
      out.push(c)
    }
    root.lastSaved = JSON.stringify(out, null, 2) + "\n"
    ownList.setText(root.lastSaved)
    cacheTimer.restart()
  }

  function openAdd() {
    root.dialog = "add"
    root.addStatus = ""
    root.addFailed = false
    dialogBox.addInput.text = ""
    Qt.callLater(function() { dialogBox.addInput.forceActiveFocus() })
  }

  // Closing mid-check cancels what's left; channels already added stay.
  // The key list (?)
  function openHelp() { appViewItem.userActs(); root.dialog = "help"; return "ok" }

  // ---- program listings (the box, from Settings) ----
  readonly property var epg: listings      // for the ui/ files
  readonly property var apps: appsStore
  readonly property var appView: appViewItem
  readonly property var appPlayback: appPlaybackItem
  readonly property var nativeSaver: nativeSaverItem
  readonly property var screenSaver: screenSaverItem
  readonly property var channelLock: channelLockItem
  readonly property var multiview: multiviewItem
  // the computer's password, one prompt at a time (Authorize.qml)
  readonly property bool authBusy: authItem.busy
  function authorize(kind, payload, done, still) { return authItem.authorize(kind, payload, done, still) }
  function authSaid(why) { return authItem.said(why) }
  readonly property var appHome: appHomeItem
  readonly property var appScreens: appScreensItem
  readonly property var appPanel: appPanelItem
  readonly property var appAgent: appAgentItem
  readonly property var snapshots: snapshotsItem
  readonly property var themeStore: themesItem
  property string codeApp: ""      // the app with code on the screen (AppView.qml), if any
  property bool appPlaying: false  // an app's media full screen (AppPlayback.qml)
  function focusKeys() { keys.forceActiveFocus() }
  // What only you can do (turn apps or the phone remote on, install, remove,
  // change the firewall) takes this, which only the keys, the mouse and your
  // paired phone hand over. Any program in your session can call the guide's
  // functions through the shell (omarchy-shell shell call), but only with
  // words, never with this.
  readonly property var byUser: ({ user: true })
  readonly property int iptvCount: channels.filter(function(c) { return c.kind === "iptv" }).length
  property int listingsCursor: 0
  property bool listingsAdding: false     // typing a link or path
  property string listingsArmed: ""       // a source waiting for its second Enter
  property string listingsNote: ""
  readonly property var listingRows: listings.sources.map(function(x) { return { type: "source", url: x.url, from: x.from } })
                                       .concat([{ type: "add" }, { type: "fetch" }])

  function openListings() {
    root.dialog = "listings"
    root.listingsCursor = 0
    root.listingsAdding = false
    root.listingsArmed = ""
    root.listingsNote = ""
    keys.forceActiveFocus()
    return "ok"
  }

  function moveListings(d) {
    root.listingsCursor = Math.max(0, Math.min(root.listingRows.length - 1, root.listingsCursor + Number(d)))
    root.listingsArmed = ""
  }

  // Enter: a source asks once, then goes; add asks for the link; fetch fetches
  function listingsAct() {
    var r = root.listingRows[root.listingsCursor]
    if (!r) return
    if (r.type === "source") {
      if (root.listingsArmed !== r.url) { root.listingsArmed = r.url; return }
      root.listingsArmed = ""
      listings.remove(r.url)
      root.listingsCursor = Math.min(root.listingsCursor, root.listingRows.length - 1)
    } else if (r.type === "add") {
      root.listingsAdding = true
      root.listingsNote = ""
      dialogBox.listingsInput.text = ""
      Qt.callLater(function() { dialogBox.listingsInput.forceActiveFocus() })
    } else if (r.type === "fetch") listings.fetch()
  }

  function addListingsFrom(text) {
    var res = listings.add(text, "you")
    if (res !== "ok") { root.listingsNote = res.charAt(0).toUpperCase() + res.slice(1) + "."; return }
    root.listingsAdding = false
    root.listingsNote = ""
    root.listingsCursor = listings.sources.length - 1
    keys.forceActiveFocus()
  }

  function listingsBack() {
    root.listingsAdding = false
    root.listingsNote = ""
    keys.forceActiveFocus()
  }

  // A source as a short name: its site and file
  function listingName(url) {
    var u = String(url)
    if (u.charAt(0) === "/") return u.split("/").pop()
    var parts = u.replace(/^https?:\/\/(www\.)?/, "").split(/[?#]/)[0].split("/")
    return parts[0] + (parts.length > 1 && parts[parts.length - 1] ? " · " + parts[parts.length - 1] : "")
  }

  function agoLabel(t) {
    var m = Math.max(0, Math.round((Date.now() / 1000 - t) / 60))
    return m < 1 ? "just now" : m < 60 ? m + " min ago" : m < 48 * 60 ? Math.round(m / 60) + " h ago" : Math.round(m / 1440) + " days ago"
  }

  // ---- apps: the boxes ------------------------------------------------------
  // appsOn, unknownOn and devOn ask before apps, Unknown sources or Developer mode go on (Not now
  // first); appCatalog is Get apps; appReview is what an app asks for,
  // before it's installed; appInfo is an installed app's details. Only you
  // open them and move in them (by: byUser, from the keys, the mouse or your
  // phone), and only a box that's on the screen takes a yes: a program
  // calling the guide's functions can't set one up for your next Enter.
  property int appsCursor: 0
  property string appsArmed: ""          // Remove, waiting for its second Enter
  property string appInfoId: ""
  property string appsBack: ""           // where the review goes back to
  property var reviewOpen: ({})          // the review's folded rows you opened (OK opens, Esc folds)
  property var appActivity: null         // the details box's Activity, read when it opens
  property int appActivityGen: 0         // which opening of the details box a read belongs to

  readonly property var appsBoxRows: {
    if (dialog === "appsOn" || dialog === "unknownOn" || dialog === "devOn")
      return [{ type: "no", label: "Not now" }, { type: "yes", label: dialog === "appsOn" ? "Turn on apps" : dialog === "unknownOn" ? "Turn on third-party apps" : "Turn on Developer mode" }]
    if (dialog === "appReview")
      return appsStore.reviewFolds(appsStore.review).concat([{ type: "install", label: appsStore.review && appsStore.review.updateConsent ? "Agree" : appsStore.review && appsStore.review.have && !appsStore.review.replaces ? "Update to " + appsStore.review.manifest.version : "Install" }, { type: "cancel", label: "Cancel" }])
    if (dialog === "appInfo") {
      var a = appsStore.record(appInfoId)
      if (!a) return []
      var rows = appsStore.activityFolds(appActivity).concat([{ type: "toggle", label: "On" }, { type: "open", label: "Open it" }])
      if (a.kind === "app") rows.push({ type: "customize", label: "Customize its screen" })
      if (a.update) rows.push({ type: "update", label: "Update to " + a.update.version })
      rows.push({ type: "remove", label: "Remove" })
      return rows
    }
    if (dialog === "appCatalog") {
      var list = appsStore.offered
      var out = list.map(function(e) { return { type: "app", id: e.id, label: e.name, entry: e } })
      if (!out.length) out.push({ type: "retry", label: appsStore.fetching ? "Getting the catalog…" : "Try again" })
      return out
    }
    return []
  }

  // A box can be seen: the guide's open and not playing full screen (boxes
  // don't show over the TV)
  function boxShown() { return root.opened && !root.watching && !root.appPlaying }

  function askApps(by) {
    if (by !== root.byUser) return "only the user, at the screen"
    root.dialog = "appsOn"
    root.appsCursor = 0
    keys.forceActiveFocus()
  }

  function askDeveloper(by) {
    if (by !== root.byUser) return "only the user, at the screen"
    if (!appsStore.on) return
    root.dialog = "devOn"
    root.appsCursor = 0
    keys.forceActiveFocus()
  }

  function askUnknownSources(by) {
    if (by !== root.byUser) return "only the user, at the screen"
    if (!appsStore.on) return
    root.dialog = "unknownOn"
    root.appsCursor = 0
    keys.forceActiveFocus()
  }

  function openCatalog(by) {
    if (by !== root.byUser) return "only the user, at the screen"
    if (!appsStore.on) return
    root.dialog = "appCatalog"
    root.appsCursor = 0
    root.appsArmed = ""
    appsStore.status = ""
    if (!appsStore.catalog || appsStore.catalogError || !appsStore.fetchedNow || Date.now() / 1000 - (appsStore.catalog.fetched || 0) > 3600) appsStore.fetchCatalog()
    appsStore.listBundled()
    keys.forceActiveFocus()
  }

  function openAppInfo(id, by) {
    if (by !== root.byUser) return "only the user, at the screen"
    if (!appsStore.record(id)) return
    root.dialog = "appInfo"
    root.appInfoId = id
    root.appsCursor = 0
    root.appsArmed = ""
    root.appActivity = null
    root.reviewOpen = {}
    // its Activity's folded rows come before the box's own: the cursor stays
    // on the row it was on. Only this opening's read counts (an earlier one
    // for the same app, still out, is let go)
    var gen = ++root.appActivityGen
    appsStore.activity(id, function(ok, res) {
      if (gen !== root.appActivityGen || root.dialog !== "appInfo" || root.appInfoId !== id) return
      root.appActivity = res || { failed: true, sites: [], refused: [], refusedMore: 0 }
      root.appsCursor += appsStore.activityFolds(root.appActivity).length
    })
    keys.forceActiveFocus()
  }

  // The review, once an app is checked and waiting: the cursor on Install
  // for Uber TV's own, on Cancel for anyone else's code, a replace, or an
  // update adding a way to change things (Apps.qml cancelFirst)
  function openReview(back, by) {
    if (by !== root.byUser || !appsStore.review) return "only the user, at the screen"
    root.appsBack = back
    root.dialog = "appReview"
    root.reviewOpen = {}
    root.appsCursor = appsStore.reviewFolds(appsStore.review).length + (appsStore.cancelFirst(appsStore.review) ? 1 : 0)
    keys.forceActiveFocus()
  }

  function moveApps(d, by) {
    if (by !== root.byUser) return "only the user, at the screen"
    root.appsCursor = Math.max(0, Math.min(root.appsBoxRows.length - 1, root.appsCursor + Number(d)))
    root.appsArmed = ""
  }

  // While it's checking or installing, the boxes wait (keys, mouse and phone alike)
  function appsBusy() { return root.authBusy || appsStore.installing || (appsStore.inspecting && root.dialog !== "appInfo") }

  // A checked app, waiting for you: shown if you're still in the box it came from, else let go
  function reviewIfStill(box, by) {
    return function(ok) {
      if (!ok) return
      if (root.dialog === box) root.openReview(box, by)
      else appsStore.cancel()
    }
  }

  // Enter (or Space) on the row the cursor's on: the keys, the mouse or your phone (by)
  function appsAct(by) {
    if (by !== root.byUser || !root.boxShown()) return "only the user, at the screen"
    if (root.appsBusy()) return
    var r = root.appsBoxRows[root.appsCursor]
    if (!r) return
    if (root.dialog === "appsOn") {
      if (r.type === "yes") { appsStore.setOn(true); root.addAppsRow() }
      root.closeDialog()
      if (r.type === "yes" && root.screen === "settings") root.settingsCursor = 0
    } else if (root.dialog === "unknownOn") {
      if (r.type !== "yes") { root.closeDialog(); return }
      appsStore.status = ""
      root.authorize("unknownSourcesOn", null, function(given, why) {
        if (!given) { if (root.dialog === "unknownOn") appsStore.status = root.authSaid(why); return }
        appsStore.setUnknownSources(true)
        root.closeDialog()
      }, function() { return root.dialog === "unknownOn" && appsStore.on })
    } else if (root.dialog === "devOn") {
      if (r.type !== "yes") { root.closeDialog(); return }
      appsStore.status = ""
      root.authorize("developerOn", null, function(given, why) {
        if (!given) { if (root.dialog === "devOn") appsStore.status = root.authSaid(why); return }
        appsStore.setDeveloper(true)
        root.closeDialog()
      }, function() { return root.dialog === "devOn" && appsStore.on })
    } else if (root.dialog === "appCatalog") {
      if (r.type === "retry") { appsStore.fetchCatalog(); return }
      if (appsStore.fetching) { appsStore.status = "Getting the catalog. Try again in a moment."; return }
      var have = appsStore.rowRecord(r)   // the same id from elsewhere: get's review is a replace
      if (have && !appsStore.newer(r.entry.version, have.version)) { root.openAppInfo(r.id, by); return }
      appsStore.get(r.id, root.reviewIfStill("appCatalog", by))
    } else if (root.dialog === "appReview") {
      if (r.type === "fold") { root.reviewOpen = appsStore.withKey(root.reviewOpen, r.key, !root.reviewOpen[r.key]); return }
      if (r.type === "cancel") { root.reviewBack(); return }
      if (appsStore.preparing) return   // Cancel still works while it gets ready
      var asked = appsStore.review
      var id = asked ? asked.manifest.id : ""
      var install = function() { appsStore.confirm(function(ok) {
        if (root.dialog !== "appReview") return
        if (ok === "again") { root.openReview(root.appsBack, by); return }   // it asks for more than its list said: see it first
        if (ok) root.openAppInfo(id, by)
        else root.reviewBack()   // what went wrong is said where it goes back to
      }) }
      // A picked signed file always asks for the computer's password. A
      // signed online update is the already-approved developer and asks for
      // consent here, but no password.
      if (asked && asked.from === "appFile" && !asked.updateConsent) {
        var approval = { id: asked.manifest.id, version: asked.manifest.version, source: asked.source,
                         key: asked.fingerprint, sha256: asked.sha256 }
        root.authorize("appFileInstall", approval, function(given, why) {
          if (!given) { if (root.dialog === "appReview" && appsStore.review === asked) appsStore.status = root.authSaid(why); return }
          install()
        }, function() { return root.dialog === "appReview" && appsStore.review === asked && appsStore.on && appsStore.unknownSources })
      } else install()
    } else if (root.dialog === "appInfo") {
      var a = appsStore.record(root.appInfoId)
      if (!a) { root.closeDialog(); return }
      if (r.type === "fold") { root.reviewOpen = appsStore.withKey(root.reviewOpen, r.key, !root.reviewOpen[r.key]); return }
      if (r.type === "toggle") appsStore.setEnabled(a.id, !(a.enabled && !a.broken && !a.revoked))
      else if (r.type === "open") root.openApp(a.id)
      else if (r.type === "customize") { root.closeDialog(); appPanelItem.openFor(a.id, by) }
      else if (r.type === "update" && a.from === "appFile") appsStore.reviewAppUpdate(a.id, root.reviewIfStill("appInfo", by))
      else if (r.type === "update") appsStore.get(a.id, root.reviewIfStill("appInfo", by))
      else if (r.type === "remove") {
        if (root.appsArmed !== a.id) { root.appsArmed = a.id; return }
        root.appsArmed = ""
        appsStore.remove(a.id, function(ok) { if (ok && root.dialog === "appInfo") root.closeDialog() })
      }
    }
  }

  // Esc in a box
  function appsEscape() {
    if (root.appsBusy()) return
    var r = root.appsBoxRows[root.appsCursor]
    if ((root.dialog === "appReview" || root.dialog === "appInfo") && r && r.type === "fold" && root.reviewOpen[r.key]) root.reviewOpen = appsStore.withKey(root.reviewOpen, r.key, false)
    else if (root.dialog === "appReview") root.reviewBack()
    else root.closeDialog()
  }

  function reviewBack() {
    appsStore.cancel()
    if (root.appsBack === "appCatalog") { root.dialog = "appCatalog"; root.appsCursor = 0 }
    else if (root.appsBack === "appInfo") { root.dialog = "appInfo"; root.appsCursor = appsStore.activityFolds(root.appActivity).length }   // on its first own row
    else root.closeDialog()
    keys.forceActiveFocus()
  }

  // ---- an app on the screen ----
  // An app takes the whole screen, as on a TV: the guide opens its window
  // full screen (no browser bar), then makes way. Super + W (closing it),
  // the guide's own key or BACK on the phone brings the guide back, on the
  // screen you left, the app still on under it until it's closed. The guide
  // takes charge only of the window it started, never one of yours, and
  // comes back by itself only if you were in the app when it closed (it
  // never takes the keyboard while you're in something else). One called
  // off while it's coming (Esc, the guide put away, the app turned off,
  // another one opened) is closed if its window turns up late.
  property string appOpening: ""   // waiting for its window (the guide shows it's coming)
  property string appUp: ""        // the app the guide made way for
  property var appWindow: null     // its window (a Toplevel), the one the guide started
  property var appBefore: []       // the windows open before it started
  property int appWaited: 0
  property bool appInFront: false  // you're in it
  property real appTakenAt: 0      // when the guide made way for it
  property real appLeftAt: 0       // when you last left it (a window closing loses its focus first)
  property bool appHint: false     // "Super + W comes back here", over the app for a moment
  property var appStray: []        // started, then called off: [{ id, before, until }], closed when they show up
  property var appClosing: null    // the one before, asked to close
  property string appClosingId: ""

  function openApp(id) {
    var why = appsStore.cannotOpen(id)
    if (why) { appsStore.status = "Couldn't open it: " + why + "."; return why }
    // an app with code opens in the guide, its screens drawn here
    var rec = appsStore.record(id)
    if (rec && rec.kind === "app") { if (root.appOpening) root.cancelAppOpen(); return appViewItem.open(id, root.byUser) }
    root.dialog = ""
    appsStore.status = ""
    // its window, if the guide started it and it's still open
    if (root.appWindow && root.appUp === id) { root.appOpening = id; root.takeApp(root.appWindow); return "ok" }
    if (root.appOpening === id) return "ok"   // it's coming
    if (root.appOpening) root.cancelAppOpen()
    // one app at a time, as on a TV: another one the guide started closes
    if (root.appWindow) root.closeOld()
    root.appOpening = id
    root.appWaited = 0
    // one called off a moment ago is still coming: wait for it, not a second copy
    var stray = root.appStray.filter(function(x) { return x.id === id })[0]
    if (stray) {
      root.appStray = root.appStray.filter(function(x) { return x !== stray })
      root.appBefore = stray.before
    } else {
      root.appBefore = appsStore.windows()
      appsStore.start(id)
    }
    appWait.restart()
    return "ok"
  }

  // The app's window that wasn't open before the guide started it
  function newWindowOf(id, before) {
    var now = appsStore.windows()
    for (var i = 0; i < now.length; i++)
      if (before.indexOf(now[i]) < 0 && now[i] !== root.appWindow && appsStore.isWindowOf(id, now[i])) return now[i]
    return null
  }

  // Its window is there: full screen, in front, and the guide goes (unless
  // the app can't open now: turned off while it was coming, say)
  function takeApp(w) {
    appWait.stop()
    var id = root.appOpening
    var why = appsStore.cannotOpen(id)
    if (why) {
      root.appOpening = ""
      root.appBefore = []
      if (w !== root.appWindow) w.close()
      appsStore.status = "Couldn't open it: " + why + "."
      return
    }
    root.appUp = id
    root.appOpening = ""
    root.appBefore = []
    root.appWindow = w
    root.appInFront = w.activated === true
    root.appTakenAt = Date.now()
    appsStore.used(id)
    root.dismiss()
    appFront.n = 0
    appFront.interval = 150
    appFront.restart()
  }

  // Stops waiting for it; its window, if it turns up in the next 15
  // seconds, is closed (the same rule as taking one: a window for that
  // website, new since the guide started it)
  function cancelAppOpen() {
    appWait.stop()
    if (root.appOpening) {
      root.appStray = root.appStray.concat([{ id: root.appOpening, before: root.appBefore, until: Date.now() + 15000 }])
      strayWatch.start()
    }
    root.appOpening = ""
    root.appBefore = []
    if (root.opened) keys.forceActiveFocus()
  }

  // X on the Apps screen: closes the app that's on (the guide stays)
  function closeApp() {
    if (root.appWindow) root.appWindow.close()
  }

  // The one on now, asked to close for another: followed until it has (a
  // "Leave site?" can keep it open)
  function closeOld() {
    var old = root.appWindow
    root.appClosingId = root.appUp
    root.appWindow = null
    root.appUp = ""
    root.appClosing = old
    old.close()
  }

  // Its window closed (Super + W, say): the guide comes back where it was,
  // if you were in the app; closed while you're in something else, it stays
  // away
  function appClosed() {
    var was = root.appUp
    var inIt = root.appInFront || Date.now() - root.appLeftAt < 500
    root.appWindow = null
    root.appUp = ""
    root.appHint = false
    root.appInFront = false
    if (was && !root.opened && inIt) root.summonBack()
  }

  function summonBack() {
    var payload = JSON.stringify({ back: true })
    if (root.shell && typeof root.shell.summon === "function") root.shell.summon((root.manifest && root.manifest.id) || "marcho78.om-pg", payload)
    else root.open(payload)
  }

  Timer {
    id: appWait
    interval: 200
    repeat: true
    onTriggered: {
      var w = root.newWindowOf(root.appOpening, root.appBefore)
      if (w) { root.takeApp(w); return }
      if (++root.appWaited * interval < 20000) return
      var a = appsStore.record(root.appOpening)
      appsStore.status = (a ? a.name : "It") + " didn't open. Is a browser like Chromium installed?"
      root.cancelAppOpen()
    }
  }

  // Ones called off: closed if their window turns up
  Timer {
    id: strayWatch
    interval: 300
    repeat: true
    onTriggered: {
      var now = Date.now()
      var keep = []
      for (var i = 0; i < root.appStray.length; i++) {
        var x = root.appStray[i]
        var w = root.newWindowOf(x.id, x.before)
        if (w) w.close()
        else if (now < x.until) keep.push(x)
      }
      root.appStray = keep
      if (!keep.length) stop()
    }
  }

  // With the guide in a window, the app goes as the guide's window does:
  // maximized under the bar (maximizeWindow's ask). False until Hyprland
  // knows its window
  function maximizeApp() {
    var tops = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < tops.length; i++) {
      var t = tops[i]
      if (!t || t.wayland !== root.appWindow) continue
      var a = String(t.address || "")
      if (!a) break
      if (!/^0x/.test(a)) a = "0x" + a
      Hyprland.dispatch('hl.dsp.window.fullscreen_state({ internal = 1, client = 1, window = "address:' + a + '" })')
      return true
    }
    if (Hyprland.refreshToplevels) Hyprland.refreshToplevels()
    return false
  }

  // Once the guide's out of the way (its keyboard let go): the app in front,
  // full screen (maximized, with the guide in a window), and asked again a
  // moment later (a window just made can drop the first ask), unless you've
  // gone somewhere else meanwhile
  Timer {
    id: appFront
    property int n: 0
    interval: 150
    onTriggered: {
      if (!root.appWindow || root.opened) return
      if (n > 0 && root.appLeftAt > root.appTakenAt) return
      root.appWindow.activate()
      var asked = true
      if (root.windowed) asked = root.maximizeApp()
      else root.appWindow.fullscreen = true
      if (n++ === 0) { root.appHint = true; appHintTimer.restart(); interval = 600; restart() }
      else if (!asked && n < 8) { interval = 250; restart() }
      else interval = 150
    }
  }

  Timer {
    id: appHintTimer
    interval: 5000
    onTriggered: root.appHint = false
  }

  Connections {
    target: root.appWindow
    ignoreUnknownSignals: true
    function onClosed() { root.appClosed() }
    function onActivatedChanged() {
      if (!root.appWindow) return
      if (root.appInFront && !root.appWindow.activated) root.appLeftAt = Date.now()
      root.appInFront = root.appWindow.activated
    }
    // out of full screen (Super + F again, or Esc held) with the guide in a
    // window: maximized again, not tiled
    function onFullscreenChanged() {
      if (root.appWindow && !root.appWindow.fullscreen && root.windowed) root.maximizeApp()
    }
  }

  Connections {
    target: root.appClosing
    ignoreUnknownSignals: true
    function onClosed() { root.appClosing = null; root.appClosingId = "" }
  }

  // Off is off: an app turned off (or pulled, or apps off) closes, if the
  // guide started it, and one on its way is called off
  Connections {
    target: appsStore
    function onReadyChanged() {
      var isReady = function(id) { return appsStore.ready.some(function(a) { return a.id === id }) }
      if (root.appOpening && !isReady(root.appOpening)) {
        var coming = appsStore.record(root.appOpening)
        if (!appsStore.status) appsStore.status = (coming ? coming.name : "The app") + " was turned off, so it didn't open."
        root.cancelAppOpen()
      }
      if (root.appClosing && root.appClosingId && !isReady(root.appClosingId)) root.appClosing.close()
      if (!root.appUp || isReady(root.appUp)) return
      var a = appsStore.record(root.appUp)
      if (!appsStore.status) appsStore.status = (a ? a.name : "The app") + " was turned off, so it closed."
      root.closeApp()
    }
  }

  // Black or white, whichever reads on a color ("#rrggbb"; else the theme's ink)
  function inkOn(c) {
    var m = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(String(c || ""))
    if (!m) return root.ink
    var l = (0.299 * parseInt(m[1], 16) + 0.587 * parseInt(m[2], 16) + 0.114 * parseInt(m[3], 16)) / 255
    return l > 0.6 ? "#111111" : "#ffffff"
  }

  // A catalog's name mid-sentence: "the Uber TV catalog"
  function catalogName(name) { return String(name || "the catalog").replace(/^The /, "the ") }

  // Home gets its Your apps row the first time apps go on
  function addAppsRow() {
    if (root.homeSections.some(function(x) { return x.type === "apps" })) return
    var hs = root.homeSections.slice()
    var at = hs.findIndex(function(x) { return x.type === "doors" })
    hs.splice(at + 1, 0, { type: "apps", on: true })
    root.homeSections = hs
    root.saveSettings()
  }

  // ---- the Apps screen (the rail) ----
  property int appsTile: 0
  property string appsFrom: "home"
  readonly property var appsTiles: appsStore.ready.map(function(a) { return { kind: "app", id: a.id, title: a.name, sub: a.author, color: a.color, icon: a.icon, from: a.from } })
                                     .concat([{ kind: "get", title: "Get apps", sub: appsStore.offered.length ? appsStore.offered.length + " to get" : "The Uber TV catalog" }])
  // an app leaving the list (turned off, pulled) doesn't leave the cursor past the end
  onAppsTilesChanged: appsTile = Math.max(0, Math.min(appsTile, appsTiles.length - 1))

  // back: returning from Settings or Search opened here (where Apps goes back to stays)
  function openApps(back) {
    if (!appsStore.on) { root.openSettings("apps"); return }
    var fresh = root.screen !== "apps"
    if (fresh && back !== true) root.appsFrom = root.screen
    if (!root.vod && root.reception !== "off" && !root.pip && !root.watching) root.turnOff()
    root.screen = "apps"
    root.dialog = ""
    root.appsTile = Math.max(0, Math.min(root.appsTile, root.appsTiles.length - 1))
    appsStore.freshen()
    keys.forceActiveFocus()
  }

  function leaveApps() { root.go(root.appsFrom === "guide" ? "tv" : root.appsFrom === "library" ? root.libraryTab : root.appsFrom === "settings" ? "settings" : "home") }

  readonly property int appsCols: 5
  function moveAppsTile(dx, dy) {
    var n = root.appsTiles.length
    dx = Number(dx) || 0
    dy = Number(dy) || 0
    var to = root.appsTile + dx + dy * root.appsCols
    if (dy && (to < 0 || to >= n)) to = dy > 0 ? n - 1 : root.appsTile
    root.appsTile = Math.max(0, Math.min(n - 1, to))
  }

  function appsTileAct(details, by) {
    var t = root.appsTiles[root.appsTile]
    if (!t) return
    if (t.kind === "get") root.openCatalog(by)
    else if (details) root.openAppInfo(t.id, by)
    else root.openApp(t.id)
  }

  function closeDialog() {
    // a restore or a reset under way isn't called off by a click beside its box
    if ((root.dialog === "reset" && backupsItem.resetBusy()) || (root.dialog === "restore" && backupsItem.restoreStep === "busy")) return
    // an install under way isn't called off by a click beside its box
    if (["appsOn", "unknownOn", "devOn", "appCatalog", "appReview", "appInfo"].indexOf(root.dialog) >= 0 && appsStore.installing) return
    if (root.dialog === "remote") root.remoteSend({ pairing: false })
    if (root.dialog === "appReview") appsStore.cancel()
    root.appsArmed = ""
    if (root.styleEditing) root.finishPick(false)
    root.styleNaming = false
    if (root.dialog === "add") root.cancelJob()
    if (channelLockItem.boxUp) channelLockItem.abandon()
    root.dialog = ""
    keys.forceActiveFocus()
  }

  function cancelJob() {
    root.queue = root.queue.filter(function(q) { return q.mode === "listing" })
    root.checks = ({})
    root.searches = ({})
    root.job = null
    root.jobTotal = 0
    root.jobDone = 0
  }

  // A channel page (any tab but its uploads would list playlists, not
  // videos), an @handle, or a playlist.
  function channelUrl(input) {
    var s = String(input || "").trim()
    if (!s) return ""
    if (/^@[\w.-]+$/.test(s)) return "https://www.youtube.com/" + s + "/videos"
    if (!/^https?:\/\//.test(s)) s = "https://" + s
    s = s.replace(/^http:\/\//, "https://")
    var m = s.match(/^https?:\/\/(?:www\.|m\.)?youtube\.com\/(@[^\/?#]+|channel\/[^\/?#]+|c\/[^\/?#]+|user\/[^\/?#]+)(\/[^?#]*)?/)
    if (m) {
      var tab = (m[2] || "").replace(/\/$/, "")
      if (tab !== "/streams") tab = "/videos"
      return "https://www.youtube.com/" + m[1] + tab
    }
    return root.isYouTube(s) ? s : ""
  }

  // Lists can come from anyone; nothing but YouTube gets fetched.
  function isYouTube(url) {
    return /^https:\/\/(?:(?:www|m|music)\.)?youtube\.com\/[^\s]*$|^https:\/\/youtu\.be\/[^\s]*$/.test(String(url))
  }

  // One link, several, or the path to a file of them. Also reachable from
  // outside: omarchy-shell shell call marcho78.om-pg addChannel <links or path>
  function addChannel(input) {
    var text = String(input || "").trim()
    root.addFailed = false
    if (!text) return root.rejectAdd("Paste a link first.")
    if (root.jobTotal) return "busy"
    // A path, maybe quoted or as a file:// link, and maybe with spaces:
    // Takeout puts subscriptions.csv under "YouTube and YouTube Music".
    var path = text.replace(/^['"]|['"]$/g, "")
    if (/^file:\/\//.test(path)) path = decodeURIComponent(path.replace(/^file:\/\//, ""))
    if (/^(~\/|\/)/.test(path) && !/https?:\/\//.test(path) && path.indexOf("\n") < 0) return root.importFile(path)
    if (/^https?:\/\/\S+$/.test(text) && !root.channelUrl(text)) return root.importIptvUrl(text)
    return root.addCandidates(root.findChannels(text))
  }

  function importFile(path) {
    var full = path.replace(/^~(?=\/|$)/, Quickshell.env("HOME"))
    root.addStatus = "Reading " + path + "…"
    statter.createObject(root, { full: full, shown: path }).start(["/usr/bin/stat", "-L", "--printf", "%F\t%s", "--", full])
    return "reading"
  }

  // Reading /dev/zero or a huge file would hang the whole shell, bar and all.
  function statted(full, shown, text) {
    var parts = String(text).split("\t")
    if (parts.length < 2) return root.rejectAdd("Couldn't read " + shown + ".")
    if (parts[0].indexOf("regular") !== 0) return root.rejectAdd(shown + " isn't a file.")
    if (Number(parts[1]) > 5 * 1024 * 1024) return root.rejectAdd(shown + " is too big for a channel list (over 5 MB).")
    reader.createObject(root, { path: full, shown: shown })
  }

  // The channels in some text: a guide lineup (JSON), a YouTube
  // subscriptions export (subscriptions.csv from Google Takeout), or lines
  // of links, @handles and channel names (looked up on YouTube).
  function findChannels(text) {
    var t = String(text || "").trim()
    var out = []
    if (/^#EXTM3U/.test(t)) return root.parseM3u(t)
    if (t.charAt(0) === "[") {
      try {
        var lineup = JSON.parse(t)
        for (var i = 0; i < lineup.length; i++) {
          var e = lineup[i]
          if (typeof e === "string") out.push({ url: root.channelUrl(e), name: "", category: "" })
          else if (e && e.url) out.push({ url: root.channelUrl(e.url), name: e.name || "", category: typeof e.category === "string" ? e.category : "" })
        }
        return out
      } catch (err) {}
    }
    var lines = t.split(/\r?\n/)
    if (/^Channel Id,/i.test(lines[0])) {
      for (var j = 1; j < lines.length; j++) {
        var m = lines[j].match(/^(UC[\w-]{22}),[^,]*,(.*)$/)
        if (m) out.push({ url: "https://www.youtube.com/channel/" + m[1] + "/videos", name: m[2].replace(/^"|"$/g, "").replace(/""/g, '"').trim(), category: "" })
      }
      return out
    }
    var hasLinks = lines.some(function(l) { return root.linksIn(l) !== null })
    var columns = null   // from a header row: which cell is name, url, category
    var category = ""    // the heading the lines below sit under
    var first = true
    for (var n = 0; n < lines.length; n++) {
      var line = lines[n]
      var parts = root.cells(line)
      if (!parts.join("")) continue
      if (first) {
        first = false
        columns = root.headerColumns(parts)
        if (columns) continue
      }
      if (columns && parts.length > 1) {
        var cu = columns.url >= 0 ? parts[columns.url] || "" : ""
        var cn = columns.name >= 0 ? parts[columns.name] || "" : ""
        var cc = (columns.category >= 0 ? parts[columns.category] || "" : "") || category
        if (cu) out.push({ url: root.channelUrl(cu), name: cn, category: cc })
        else if (cn) out.push({ url: "", search: cn, name: "", category: cc })
        continue
      }
      var found = root.linksIn(line)
      if (found) {
        var name = ""
        var rowCategory = ""
        if (found.length === 1 && parts.length > 1) {
          // "Science,https://…[,Category]": the other cells name and file it.
          var label = parts.filter(function(p) { return p && !/https?:\/\/|^@|youtube\.com\//.test(p) })
          name = label[0] || ""
          rowCategory = label[1] || ""
        } else if (found.length === 1) {
          // "CNN — https://…": the rest of the line names it.
          name = line.replace(found[0], "").replace(/^\s*(?:[-*•·▪►>]+|\d+[.)])\s+/, "")
                     .replace(/^[\s—–:|"']+|[\s—–\-:|"']+$/g, "").trim()
        }
        for (var k = 0; k < found.length; k++)
          out.push({ url: root.channelUrl(found[k]), name: name.slice(0, 60), category: (rowCategory || category).slice(0, 40) })
        continue
      }
      // A heading: "## News", "**News**", "News:", or, among links, a short
      // line on its own (a blank line or a link line after it).
      var clean = line.trim()
      var marked = clean.match(/^#{1,6}\s*(.+)$/) || clean.match(/^\*\*(.+)\*\*$/) || clean.match(/^([^,;\t]{1,40}):$/)
      var before = n === 0 || !lines[n - 1].trim()
      var next = n + 1 < lines.length ? lines[n + 1] : ""
      if (marked || (hasLinks && parts.length === 1 && before && clean.length <= 40 && (!next.trim() || root.linksIn(next) !== null))) {
        category = (marked ? marked[1] : clean).replace(/[*:]+$/, "").trim().slice(0, 40)
        continue
      }
      // Among links, a long or chatty line is prose, not names.
      if (hasLinks && (clean.length > 60 || /[@\/]|[.!?]$/.test(clean))) continue
      // Names: "1. Veritasium", "- Tom Scott", "TED, Vsauce"
      for (var q = 0; q < parts.length; q++) {
        var nm = parts[q].replace(/^\s*(?:[-*•·▪►>]+|\d+[.)])\s*/, "").trim()
        if (nm && nm.length <= 60) out.push({ url: "", search: nm, name: "", category: category })
      }
    }
    return out
  }

  // The links and @handles on a line, or null. Links can arrive run together,
  // so it splits before each one; a bare @handle counts only at the end of a
  // line or cell, not mid-sentence ("the standard @handle format").
  function linksIn(line) {
    var spaced = String(line).replace(/(https?:\/\/)/g, " $1")
    var found = spaced.match(/https?:\/\/[^\s,;"'<>]+|(?:^|[\s,;—–:|])@[\w.-]+(?=\s*(?:$|[,;\t]))|(?:^|[\s,;])(?:www\.|m\.)?youtube\.com\/[^\s,;"'<>]+/g)
    if (!found) return null
    return found.map(function(f) { return f.replace(/^[\s,;—–:|]+/, "") })
  }

  // A header row's columns ("name,url,category", "Channel,Link"), or null.
  function headerColumns(parts) {
    var cols = { name: -1, url: -1, category: -1 }
    var known = 0
    for (var i = 0; i < parts.length; i++) {
      var p = parts[i].toLowerCase()
      if (/^(channel( name| title)?|name|title)$/.test(p)) { cols.name = i; known++ }
      else if (/^(url|link|channel (url|link)|handle|youtube( url| link)?)$/.test(p)) { cols.url = i; known++ }
      else if (/^(category|genre|group|section|tag)$/.test(p)) { cols.category = i; known++ }
      else if (/https?:\/\/|@|youtube\.com/.test(p)) return null   // a data row, not a header
    }
    // Other columns ("notes", "id") are ignored.
    return known && (parts.length > 1 || cols.url >= 0 || cols.name >= 0) ? cols : null
  }

  // A line's cells, split on commas, semicolons or tabs; "quoted, cells" stay whole.
  function cells(line) {
    var out = []
    var cur = ""
    var quoted = false
    for (var i = 0; i < line.length; i++) {
      var ch = line.charAt(i)
      if (ch === '"') {
        if (quoted && line.charAt(i + 1) === '"') { cur += '"'; i++ }
        else quoted = !quoted
      } else if (!quoted && (ch === "," || ch === ";" || ch === "\t")) {
        out.push(cur.trim())
        cur = ""
      } else {
        cur += ch
      }
    }
    out.push(cur.trim())
    return out
  }

  function searchUrl(name) {
    // sp=EgIQAg: only channels in the results
    return "https://www.youtube.com/results?search_query=" + encodeURIComponent(name) + "&sp=EgIQAg%253D%253D"
  }

  // origin: where its channels came from, for their provider (source, unless given)
  function addCandidates(found, source, origin) {
    // the program listings a playlist names come with it (once its channels are in)
    var guides = Array.isArray(found.guides) ? found.guides.slice(0, 5) : []
    // A playlist's movies and episodes (video files) go to the library
    var vods = found.filter(function(c) { return c.vod })
    var movies = vods.length ? library.add(vods, source || "") : { added: 0, already: 0 }
    found = found.filter(function(c) { return !c.vod })
    if (vods.length && !found.length) {
      root.settleJob()
      if (!movies.added) return root.rejectAdd("All of those are already in your library (V).")
      root.addStatus = "Added " + movies.added + (movies.added === 1 ? " movie" : " movies") + " to your library (V)"
                       + (movies.already ? ". " + movies.already + " already there." : ".")
      root.addFailed = false
      dialogBox.addInput.text = ""
      return root.addStatus
    }
    var list = found.filter(function(c) { return c.url || c.search })   // links and names only
    var ignored = found.length - list.length
    if (!list.length) return root.rejectAdd("No YouTube links, channel names or IPTV streams found there.")
    root.jobId++
    // IPTV streams need no checking: in they go, in the playlist's order.
    var streams = []
    var keep = []
    var seenStream = {}
    var alreadyStreams = 0
    for (var s0 = 0; s0 < list.length; s0++) {
      var cand = list[s0]
      cand.seq = s0
      if (!cand.iptv) { keep.push(cand); continue }
      if (seenStream[cand.url]) continue
      seenStream[cand.url] = true
      if (root.indexOf(cand.url) >= 0) { alreadyStreams++; continue }
      var entry = root.iptvChannel(cand.name, cand.url, cand.category, cand.logo, cand.tvgId, DvrRules.sourceId(origin !== undefined ? origin : source))
      entry.job = root.jobId
      entry.seq = s0
      streams.push(entry)
    }
    if (streams.length) {
      var withStreams = root.channels.slice()
      for (var s1 = 0; s1 < streams.length; s1++) root.insertGrouped(withStreams, streams[s1])
      root.setChannels(withStreams)
      root.saveChannels()
    }
    var guideNote = ""
    for (var gi = 0; gi < guides.length; gi++)
      if (listings.add(guides[gi], "playlist") === "ok") guideNote = " Its program listings are coming in too."
    if (!keep.length) {
      root.settleJob()
      if (!streams.length) return root.rejectAdd(alreadyStreams ? "All of those are already in your guide." : "No streams found there.")
      root.row = root.indexOf(streams[0].url)
      root.showRow(root.row)
      root.addStatus = "Added " + streams.length + " IPTV channel" + (streams.length === 1 ? "" : "s")
                       + (movies.added ? ", and " + movies.added + (movies.added === 1 ? " movie" : " movies") + " to your library (V)" : "")
                       + (alreadyStreams ? ". " + alreadyStreams + " already in your guide." : ".")
                       + (found.length >= 3000 ? " (The first 3,000 of the playlist.)" : "") + guideNote
      root.addFailed = false
      dialogBox.addInput.text = ""
      return root.addStatus
    }
    list = keep
    var seen = {}
    var fresh = []
    var already = 0
    var filed = 0
    var have = -1
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      if (c.seq === undefined) c.seq = i   // a playlist's YouTube links keep their place in it
      c.category = c.category || ""
      var key = c.url || "search:" + c.search.toLowerCase()
      if (seen[key]) continue
      seen[key] = true
      have = c.url ? root.indexOf(c.url) : root.indexOfName(c.search)
      if (have < 0) { fresh.push(c); continue }
      already++
      if (root.fileUnder(have, c.category, c.seq)) filed++
    }
    if (!fresh.length) {
      root.settleJob()
      if (filed) return root.rejectAdd("All of those are already in your guide; " + filed + " sorted into categories.")
      return root.rejectAdd(list.length === 1 ? "That's already CH " + root.numbers[have] + "."
                                              : "All of those are already in your guide.")
    }
    var checks = {}
    var searches = {}
    for (var k = 0; k < fresh.length; k++) {
      var info = { name: fresh[k].name || "", category: fresh[k].category, seq: fresh[k].seq }
      if (fresh[k].url) checks[fresh[k].url] = info
      else searches[root.searchUrl(fresh[k].search)] = root.changed(info, { name: fresh[k].search })
    }
    root.checks = checks
    root.searches = searches
    root.job = { added: streams.length, already: already + alreadyStreams, failed: 0, filed: filed, ignored: ignored, single: found.length === 1, problem: "",
                 name: "", addedNames: streams.map(function(e) { return e.name }), notFound: [] }
    root.jobTotal = fresh.length
    root.jobDone = 0
    root.addStatus = ""
    for (var n = 0; n < fresh.length; n++) {
      if (fresh[n].url) root.enqueue(fresh[n].url, "check")
      else root.enqueue(root.searchUrl(fresh[n].search), "search")
    }
    return "checking " + fresh.length
  }

  // Files a channel that has no category under one an import gives it.
  function fileUnder(i, category, seq) {
    var ch = root.channels[i]
    if (!ch || !category || ch.category) return false
    var list = root.channels.slice()
    list.splice(i, 1)
    root.setChannels(root.insertGrouped(list, root.changed(ch, { category: category, job: root.jobId, seq: seq })))
    return true
  }

  // Puts what an import added (checked four at a time, so finishing in any
  // order) back in the order it was pasted, then saves.
  function settleJob() {
    var id = root.jobId
    var mine = root.channels.filter(function(c) { return c.job === id })
    if (!mine.length) return
    mine.sort(function(a, b) { return a.seq - b.seq })
    var list = root.channels.filter(function(c) { return c.job !== id })
    for (var i = 0; i < mine.length; i++) root.insertGrouped(list, root.changed(mine[i], { job: undefined, seq: undefined }))
    root.setChannels(list)
    root.saveChannels()
  }

  function indexOfName(name) {
    var wanted = String(name).toLowerCase()
    for (var i = 0; i < root.channels.length; i++) if (root.channels[i].name.toLowerCase() === wanted) return i
    return -1
  }

  // A name looked up: its first channel result is checked like a pasted link.
  function searched(url, text) {
    var job = root.job
    if (!job || !(url in root.searches)) return   // cancelled
    var info = root.searches[url]
    var name = info.name
    delete root.searches[url]
    var results = null
    try { results = JSON.parse(text) } catch (e) {}
    var entries = (results && results.entries) || []
    var hit = null
    for (var i = 0; i < entries.length && !hit; i++)
      if (entries[i] && /^https:\/\/www\.youtube\.com\/channel\/UC[\w-]{22}$/.test(entries[i].url || "")) hit = entries[i]
    if (!hit) {
      job.failed++
      job.notFound.push(name)
      return root.finishOne("Couldn't find a channel called " + name + ".")
    }
    var channel = root.channelUrl(hit.url)
    var twin = Math.max(root.indexOf(channel), root.indexOfChannelId(hit.channel_id))
    if (twin >= 0 || channel in root.checks) {
      job.already++
      if (twin >= 0 && root.fileUnder(twin, info.category, info.seq)) job.filed++
      return root.finishOne(twin >= 0 ? "That's already CH " + root.numbers[root.indexOf(root.channels[twin].url)] + "." : "")
    }
    root.checks[channel] = { name: "", category: info.category, seq: info.seq }
    root.enqueue(channel, "check")   // checked() finishes this one
  }

  // Playlist and mix titles run long ("Mix - Ibiza Summer Mix 2026 🍓 Best
  // Of ..."): keep what comes before the first emoji, " | " or " - ".
  function shortName(raw) {
    var s = String(raw || "").replace(/ - (Videos|Live)$/, "").replace(/^Mix - /, "Mix: ").trim()
    for (var i = 1; i < s.length; i++) {
      var c = s.charCodeAt(i)
      if ((c >= 0xD800 && c <= 0xDBFF) || s.substr(i, 3) === " | " || s.substr(i, 3) === " - ") {
        s = s.slice(0, i).trim()
        break
      }
    }
    if (s.length > 32) s = s.slice(0, 32).replace(/\s+\S*$/, "") + "…"
    return s || "Channel"
  }

  function rejectAdd(message) {
    root.addStatus = message
    root.addFailed = true
    return message
  }

  function checked(url, text) {
    var job = root.job
    if (!job || !(url in root.checks)) return   // cancelled
    var info = root.checks[url]
    var given = info.name
    delete root.checks[url]

    var listing = null
    try { listing = JSON.parse(text) } catch (e) {}
    // A stream that's live now: its channel goes in instead, playing it
    var home = !info.live && listing && !listing.entries && listing.live_status === "is_live" && /^[\w-]{11}$/.test(listing.id || "") ? root.homeOf(listing) : ""
    if (home) return root.checkHome(home, listing, info)
    // That channel's videos didn't load (one that only streams has none): it airs its stream
    if (info.live && !listing) listing = { entries: [], channel: info.live.channel, channel_id: info.live.channelId }
    var items = listing && listing.entries ? Schedule.programs(listing) : []
    var problem = !listing ? "Couldn't load that link. Check it and try again."
                : !listing.entries ? "That's a single video. Paste a channel or playlist link."
                : !items.length && !info.live ? "Nothing there can air: no public videos between 5 minutes and 4 hours."
                : ""
    var channelId = root.channelIdOf(url, listing)
    var twin = problem ? -1 : root.indexOfChannelId(channelId)
    if (twin >= 0) {
      job.already++
      var twinUrl = root.channels[twin].url
      if (root.fileUnder(twin, info.category, info.seq)) job.filed++
      job.problem = "That's already CH " + root.numbers[root.indexOf(twinUrl)] + "."
      problem = job.problem
    } else if (problem) {
      job.failed++
      job.problem = problem
    } else {
      var name = given ? String(given).slice(0, 60)
                       : root.shortName(/[?&]list=/.test(url) ? listing.title : (listing.channel || listing.uploader || listing.title))
      var entry = {
        name: name, url: url, category: info.category || "", items: items, state: items.length ? "ready" : "error", channelId: channelId, logoUrl: root.logoOf(listing),
        plan: { day: root.tvDay(Date.now() / 1000), items: items },
        job: root.jobId, seq: info.seq
      }
      if (info.live) { entry.live = { id: info.live.id, title: info.live.title }; entry.liveId = info.live.id }
      root.setChannels(root.insertGrouped(root.channels.slice(), entry))
      root.saveChannels()
      root.checkLive(root.indexOf(url))
      job.added++
      job.name = name
      job.addedNames.push(name)
      if (job.added === 1) {
        root.row = root.indexOf(url)
        root.showRow(root.row)
      }
    }
    return root.finishOne(problem)
  }

  // The page of the channel a video is on, from what YouTube says about it
  function homeOf(video) {
    var links = [video.uploader_url, video.channel_url]
    for (var i = 0; i < links.length; i++) {
      var home = typeof links[i] === "string" ? root.channelUrl(links[i]) : ""
      if (root.liveUrlOf(home) && root.isYouTube(home)) return home
    }
    return ""
  }

  // A live stream's channel, checked like a pasted link and added playing
  // that stream (checked() finishes this one)
  function checkHome(home, video, info) {
    var job = root.job
    var twin = Math.max(root.indexOf(home), root.indexOfChannelId(String(video.channel_id || "")))
    if (twin >= 0 || home in root.checks) {
      job.already++
      if (twin >= 0 && root.fileUnder(twin, info.category, info.seq)) job.filed++
      return root.finishOne(twin >= 0 ? "That's already CH " + root.numbers[root.indexOf(root.channels[twin].url)] + "." : "")
    }
    root.checks[home] = root.changed(info, { live: {
      id: video.id, title: String(video.fulltitle || video.title || "Live").slice(0, 300),
      channel: String(video.channel || video.uploader || "").slice(0, 100), channelId: String(video.channel_id || "").slice(0, 64)
    } })
    root.enqueue(home, "check")
    return "checking"
  }

  // One link or name done; the last one sums up.
  function finishOne(problem) {
    var job = root.job
    root.jobDone++
    if (root.jobDone < root.jobTotal) return "checking"

    root.settleJob()
    root.job = null
    root.jobTotal = 0
    root.jobDone = 0
    if (job.added) root.showRow(root.indexOf(root.channels[root.row].url))
    if (job.single) {
      if (problem) return root.rejectAdd(problem)
      root.addStatus = "Added " + job.name
      if (root.dialog === "add") root.closeDialog()
      return "added"
    }
    var named = job.addedNames.length <= 6 ? ": " + job.addedNames.join(", ") + "." : " channels."
    root.addStatus = !job.added && !job.failed ? "All of those are already in your guide."
                     : "Added " + job.added + (job.added ? named : " channels.")
                       + (job.already ? " " + job.already + " already in your guide" + (job.filed ? ", " + job.filed + " sorted into categories." : ".") : "")
                       + (job.notFound.length ? " Couldn't find " + job.notFound.slice(0, 4).join(", ") + (job.notFound.length > 4 ? "…" : "") + "." : "")
                       + (job.failed > job.notFound.length ? " " + (job.failed - job.notFound.length) + " couldn't be added." : "")
                       + (job.ignored ? " " + job.ignored + " weren't YouTube links." : "")
    root.addFailed = job.added === 0
    dialogBox.addInput.text = ""
    return root.addStatus
  }

  // The demo lineup's channels you don't have yet
  function demoToAdd() {
    var have = {}
    for (var i = 0; i < root.channels.length; i++) have[root.channels[i].url] = true
    return root.demoLineup.channels.filter(function(c) { return !have[c.url] })
  }

  // Loads the demo lineup: the channels in it you don't have, in its
  // categories (and their hundreds); yours stay as they are. Each comes in
  // loading its listings, as at a start. Also an agent command.
  function loadDemoChannels() {
    var fresh = root.demoToAdd()
    if (!root.demoLineup.channels.length) { root.demoSaid = "The demo lineup couldn't be read."; return { added: 0, error: "the demo lineup couldn't be read" } }
    var list = root.channels.slice()
    for (var i = 0; i < fresh.length; i++)
      list = root.insertGrouped(list, { name: fresh[i].name, url: fresh[i].url, category: fresh[i].category, items: [], state: "loading", channelId: "", liveId: fresh[i].liveId })
    if (fresh.length) {
      root.setChannels(list)
      root.saveChannels()
      if (root.opened) root.fetchMissing()
    }
    root.demoSaid = fresh.length ? "Added " + fresh.length + (fresh.length === 1 ? " channel." : " channels.") : "They're all in your guide already."
    return { added: fresh.length, error: "" }
  }

  // Also reachable from outside, by channel number:
  // omarchy-shell shell call marcho78.om-pg removeChannel 101
  function removeChannel(number) {
    var i = root.numbers.indexOf(Number(number))
    if (i < 0) return "no such channel"
    root.removeUrls([root.channels[i].url])
    return "removed"
  }

  function askRemove(urls) {
    if (!urls.length) return
    root.removeTargets = urls
    root.dialog = "remove"
  }

  function removeUrls(urls) {
    var gone = {}
    for (var i = 0; i < urls.length; i++) gone[urls[i]] = true
    var keepRow = -1
    for (var r = root.row; r < root.channels.length && keepRow < 0; r++) if (!gone[root.channels[r].url]) keepRow = r
    for (r = root.row - 1; r >= 0 && keepRow < 0; r--) if (!gone[root.channels[r].url]) keepRow = r
    var rowUrl = keepRow >= 0 ? root.channels[keepRow].url : ""
    if (root.channels[root.tunedRow] && gone[root.channels[root.tunedRow].url]) root.turnOff()
    root.setChannels(root.channels.filter(function(c) { return !gone[c.url] }))
    root.row = Math.max(0, root.indexOf(rowUrl))
    root.marked = ({})
    root.saveChannels()
    if (root.dialog === "remove") root.closeDialog()
    if (root.opened) previewTimer.restart()
  }

  function remotePrompt() {
    var net = root.remoteNet
    var msg = root.remoteMessage ? "\n\n" + root.remoteMessage : ""
    if (root.remoteStep === "confirm")
      return "This opens a network port (" + root.remotePort + ") on this computer so phones on your local network ("
        + (net ? net.subnet : "…") + ") can control Uber TV from a web page.\n\n"
        + "•  Only devices on your local network can reach it, and only after you pair them with a code shown on this screen.\n"
        + "•  A paired phone works like the TV's keys: channels, playback, and the guide's boxes (apps' too). It can't reach your files or anything else on this computer, and only a phone pairs, never this computer.\n"
        + (root.firewallActive ? "•  Your firewall blocks incoming connections, so this adds one rule allowing this port from your local network. You'll be asked for your password.\n" : "")
        + "•  Turning the remote off closes the port" + (root.firewallActive ? " and offers to remove the firewall rule." : ".")
    if (root.remoteStep === "firewall")
      return root.firewallFor === "allow" ? "Enter your password in the prompt to allow phones on " + (net ? net.subnet : "your network") + " to reach port " + root.remotePort + "."
                                          : "Enter your password in the prompt to remove the firewall rule."
    if (root.remoteStep === "off")
      return "The port closes right away and paired phones stop working until you turn it on again."
        + (root.remoteNet && root.remoteRules.indexOf(root.remoteNet.subnet + " " + root.remotePort) >= 0 ? " Also remove the firewall rule? That asks for your password." : "") + msg
    if (root.remoteStep === "on")
      return (root.remoteReady ? "On. Scan the QR code with your phone's camera, or open the address on your phone and enter the code."
                               : "Starting…")
        + (root.remoteAllowedHere ? "" : "\n\nYour firewall doesn't allow this network (" + (net ? net.subnet : "") + ") yet, so phones here can't reach the remote. Press A to allow it.") + msg
    return "Control the guide from your phone's web browser: a remote with a d-pad, channel buttons and a number pad, and the guide itself, on any phone on your network. It's off." + msg
  }

  function removePrompt() {
    var urls = root.removeTargets
    if (urls.length === 1) {
      var i = root.indexOf(urls[0])
      return i >= 0 ? "Remove " + root.channelLabel(i) + " from your guide?" : ""
    }
    var names = urls.slice(0, 5).map(function(u) { var i = root.indexOf(u); return i >= 0 ? root.channels[i].name : "" })
    // Whole categories going?
    var whole = root.categories.filter(function(c) {
      var inCat = root.channels.filter(function(ch) { return (ch.category || "") === c })
      return inCat.length && inCat.every(function(ch) { return urls.indexOf(ch.url) >= 0 })
    }).map(root.categoryLabel)
    return "Remove " + urls.length + " channels from your guide? " + names.join(", ") + (urls.length > 5 ? " and " + (urls.length - 5) + " more." : ".")
           + (whole.length ? " That's all of " + whole.join(", ") + "." : "")
  }

  // Manage mode

  function setManaging(on) {
    root.managing = !!on && root.channels.length > 0
    root.marked = ({})
  }

  // What manage commands act on: the marked channels, or the one under the cursor.
  // L where channels are managed: the marked ones (or this one) locked, or
  // unlocked if all are, after the passcode (ChannelLock.qml)
  function lockTargets(by) {
    if (by !== root.byUser) return "only the user, at the screen"
    var urls = root.targets()
    channelLockItem.toggleChannels(root.channels.filter(function(c) { return urls.indexOf(c.url) >= 0 }))
  }

  function targets() {
    if (root.markedCount) return root.channels.filter(function(c) { return root.marked[c.url] }).map(function(c) { return c.url })
    return root.channels[root.row] ? [root.channels[root.row].url] : []
  }

  function toggleMark(r) {
    var ch = root.channels[Number(r)]
    if (!ch) return
    var m = root.changed(root.marked, {})
    if (m[ch.url]) delete m[ch.url]
    else m[ch.url] = true
    root.marked = m
  }

  // Marks every channel in the cursor's category, or unmarks them if all are.
  function toggleCategoryMark(r) {
    var ch = root.channels[Number(r)]
    if (!ch) return
    var inCat = root.channels.filter(function(c) { return (c.category || "") === (ch.category || "") })
    var all = inCat.every(function(c) { return root.marked[c.url] })
    var m = root.changed(root.marked, {})
    for (var i = 0; i < inCat.length; i++) {
      if (all) delete m[inCat[i].url]
      else m[inCat[i].url] = true
    }
    root.marked = m
  }

  // Shift+↑↓: swaps with the next channel up or down in the same category.
  function moveChannel(delta) {
    var i = root.row
    var j = i + Number(delta)
    var list = root.channels.slice()
    if (!list[i] || !list[j] || (list[i].category || "") !== (list[j].category || "")) return
    var t = list[i]
    list[i] = list[j]
    list[j] = t
    root.setChannels(list)
    root.showRow(root.row)
    root.saveChannels()
  }

  function openRename() {
    var ch = root.channels[root.row]
    if (!ch) return
    root.dialog = "rename"
    dialogBox.renameInput.text = ch.name
    Qt.callLater(function() { dialogBox.renameInput.forceActiveFocus(); dialogBox.renameInput.selectAll() })
  }

  function renameChannel(r, name) {
    var ch = root.channels[Number(r)]
    var clean = String(name || "").trim().slice(0, 60)
    if (!ch || !clean) return
    var list = root.channels.slice()
    list[Number(r)] = root.changed(ch, { name: clean })
    root.setChannels(list)
    root.saveChannels()
    if (root.dialog === "rename") root.closeDialog()
  }

  function openCategory() {
    if (!root.channels.length) return
    root.dialog = "category"
    root.catQuery = ""
    root.catCursor = 0
    dialogBox.categoryInput.text = ""
    Qt.callLater(function() { dialogBox.categoryInput.forceActiveFocus() })
  }

  function moveCat(delta) {
    var n = root.catOptions.length
    if (n) root.catCursor = Math.max(0, Math.min(n - 1, root.catCursor + delta))
  }

  // Files the targets under a category ("" for none), at the end of it, in order.
  function setCategory(urls, category) {
    var moving = root.channels.filter(function(c) { return urls.indexOf(c.url) >= 0 })
    var list = root.channels.filter(function(c) { return urls.indexOf(c.url) < 0 })
    for (var i = 0; i < moving.length; i++) root.insertGrouped(list, root.changed(moving[i], { category: category }))
    root.setChannels(list)
    root.marked = ({})
    root.saveChannels()
    if (root.dialog === "category") root.closeDialog()
    root.showRow(root.row)
  }

  // For scripts and debugging: omarchy-shell shell call marcho78.om-pg describe x
  // The shell's command channel has a size limit, so the list is kept short;
  // describeChannel gives one channel in full.
  function describe() {
    var chans = []
    for (var i = 0; i < Math.min(root.channels.length, 60); i++) {   // the first 60; findChannel finds the rest
      var c = root.channels[i]
      chans.push({ number: root.numbers[i], name: c.name, category: c.category, kind: c.kind || "youtube",
                   state: c.state, videos: c.items.length, live: c.live ? String(c.live.title).slice(0, 40) : null })
    }
    return JSON.stringify({
      lineupMode: root.lineupMode, fetchedAt: root.fetchedAt, today: root.tvDay(Date.now() / 1000),
      remote: { enabled: root.remoteEnabled, ready: root.remoteReady, step: root.remoteStep, net: root.remoteNet,
                firewallActive: root.firewallActive, allowedHere: root.remoteAllowedHere, running: remoteHelper.running,
                phones: root.remoteDevices.length, message: root.remoteMessage },
      opened: root.opened, dialog: root.dialog, managing: root.managing, row: root.row, pip: root.pip, watching: root.watching,
      pipPointerIn: root.pipPointerIn, pipKeys: pipWindow.keys.activeFocus, shownSource: root.shownSource,
      marked: root.channels.filter(function(c) { return root.marked[c.url] }).map(function(c) { return c.name }),
      channels: chans, channelCount: root.channels.length, iptvCount: root.channels.filter(function(c) { return c.kind === "iptv" }).length,
      shownCategories: root.shownCategories, visibleRows: root.visibleRows.length, tunedRow: root.tunedRow,
      reception: root.reception, addStatus: root.addStatus,
      player: { status: player.mediaStatus, state: player.playbackState, position: player.position, error: player.errorString,
                source: player.source.toString().slice(0, 80) }
    })
  }

  // The index of the first channel with this name ("name" or "name|iptv" / "name|youtube"), or -1.
  function findChannel(query) {
    var parts = String(query).split("|")
    for (var i = 0; i < root.channels.length; i++) {
      var c = root.channels[i]
      if (c.name === parts[0] && (!parts[1] || (c.kind || "youtube") === parts[1])) return String(i)
    }
    return "-1"
  }

  function describeChannel(r) {
    var c = root.channels[Number(r)]
    if (!c) return "{}"
    var lineup = root.lineupOf(c)
    return JSON.stringify({ number: root.numbers[Number(r)], name: c.name, url: c.url, kind: c.kind || "youtube", category: c.category,
                            logo: c.logo || c.logoUrl || "", state: c.state, videos: c.items.length, live: c.live || null,
                            planDay: c.plan ? c.plan.day : "", planned: lineup.length, planFirst: lineup.length ? lineup[0].id : "",
                            latestFirst: c.items.length ? c.items[0].id : "" })
  }

  function setMuted(on) {
    root.muted = on === true || on === "true"
    return String(root.muted)
  }

  // Moving the cursor

  function moveRow(delta) {
    delta = Number(delta)
    var v = root.visibleRows
    if (!v.length) return
    var p = Math.max(0, v.indexOf(root.row))
    root.cursorTime = root.cursorAt
    root.row = v[Math.max(0, Math.min(v.length - 1, p + delta))]
    root.showRow(root.row)
  }

  // Scrolls the grid to channel r.
  function showRow(r) {
    var p = root.visibleRows.indexOf(r)
    if (p >= 0 && root.channelList) root.channelList.positionViewAtIndex(p, ListView.Contain)
  }

  // PgUp/PgDn: the start of the next category, or of this one (then the one before).
  function jumpCategory(delta) {
    var v = root.visibleRows
    if (!v.length) return
    var cat = function(p) { return root.channels[v[p]].category || "" }
    var p = Math.max(0, v.indexOf(root.row))
    var here = cat(p)
    if (delta > 0) {
      while (p < v.length && cat(p) === here) p++
      if (p >= v.length) return
    } else {
      var start = p
      while (start > 0 && cat(start - 1) === here) start--
      if (start < p) p = start
      else {
        if (start === 0) return
        p = start - 1
        var prev = cat(p)
        while (p > 0 && cat(p - 1) === prev) p--
      }
    }
    root.cursorTime = root.cursorAt
    root.row = v[p]
    if (root.channelList) root.channelList.positionViewAtIndex(p, ListView.Beginning)
  }

  function moveTime(delta) {
    var s = root.selected
    if (delta > 0) {
      var next = s ? s.end : root.cursorAt + root.slot
      while (next >= root.windowEnd && root.slotOffset < root.maxSlotOffset) root.slotOffset++
      if (next < root.windowEnd) root.cursorTime = next
    } else {
      var prev = s ? s.start - 1 : root.cursorAt - root.slot
      while (prev < root.windowStart && root.slotOffset > 0) root.slotOffset--
      root.cursorTime = Math.max(prev, root.windowStart)
    }
  }

  // A 2nd stream from a provider a recording is using (Dvr.js providerOf):
  // asked first, once; Watch anyway lasts while that provider's recordings
  // do. Full screen or the mini player, the banner asks (its choices: Watch
  // anyway, Stay); elsewhere, a box. then: what to do once it's yes.
  property var streamAsk: null            // { row, then }
  // what the banner and the mini player ask
  readonly property string streamAskLabel: streamAsk ? "Watch " + (numbers[streamAsk.row] || "") + " " + ((channels[streamAsk.row] || {}).name || "") + " anyway" : ""
  readonly property string streamAskNote: "A 2nd stream from this provider while it records"
  function streamOk(r, then) {
    var ch = root.channels[r]
    if (!ch || (r === root.tunedRow && root.reception !== "off" && root.reception !== "lost")) return true   // already playing it
    if (!dvr.needsAsk(ch)) return true
    root.streamAsk = { row: r, then: then }
    if (root.watching || root.pip) {
      root.bannerAct = 0
      root.recStopMenu = false
      root.bannerOptions = true
      root.bannerShown = true
      bannerTimer.restart()
    } else {
      if (!root.opened) root.summonGuide(false)
      root.dialog = "recStream"
      keys.forceActiveFocus()
    }
    return false
  }
  function showChoiceText() {
    var c = root.showChoice
    if (!c) return ""
    var ch = root.channels[c.row]
    var s = c.show
    var when = s && s.start && s.end && !(ch && ch.live && !s.epg) ? root.clock(s.start) + " – " + root.clock(s.end) : ""
    var e = c.entry
    return [(root.numbers[c.row] || "") + " " + (ch ? ch.name : ""), when].filter(function(x) { return x && x.trim() }).join(" · ")
           + (!e ? (c.later && c.later.why ? "\n\n" + c.later.why : "")
              : DvrRules.active(e) ? "\n\nRecording now." : e.state === "conflict" ? "\n\n" + dvr.reasonOf(e) : "\n\nScheduled to record.")
  }
  function streamAskText() {
    var to = root.streamAsk ? root.channels[root.streamAsk.row] : null
    return (to ? to.name : "That channel") + " comes from the same provider as a recording that's running: watching it takes a 2nd stream, and a plan that allows one at a time may stop the recording. "
           + "Watch anyway, and you won't be asked again while it records."
  }
  // for Multiview's Add a channel list: a channel a recording's provider would stream twice
  function secondStreamOf(ch) { return dvr.needsAsk(ch) }

  // A show's choices in the guide (I or Space, phone ⋯; Enter still
  // watches): Watch, then recording it: Record (what's on now, to its end
  // or an hour; a later IPTV show, scheduled), Record every episode (IPTV,
  // from its listings), Save video (a scheduled YouTube channel's video, the
  // one picked). One scheduled already: Cancel recording; one recording:
  // Stop recording; a series': Stop recording this series. A locked
  // channel's cell hides its show: the passcode first, then it's the show
  // at that time (as the listings have it) that's recorded.
  property var showChoice: null          // { row, show, at, offer, later, entry, rule, series }
  property int showCursor: 0
  readonly property var showChoices: {
    var c = showChoice
    if (!c) return []
    var out = [{ key: "watch", label: "Watch" }]
    if (c.entry && DvrRules.active(c.entry)) return out.concat(dvr.stopping[c.entry.id] ? [] : [{ key: "stopRec", label: "Stop recording" }])
    if (c.entry) out.push({ key: "cancel", label: "Cancel recording" })
    else if (c.offer) out.push({ key: "record", label: c.offer.label, note: c.offer.note, unavailable: c.offer.unavailable })
    else if (c.later) out.push({ key: "schedule", label: c.later.label, note: c.later.note })
    if (c.rule) out.push({ key: "stopSeries", label: "Stop recording this series" })
    else if (c.series) out.push({ key: "series", label: "Record every episode" })
    return out
  }
  function openShowChoices() {
    var r = root.row
    var ch = root.channels[r]
    if (!ch || !root.airs(ch) || root.screen !== "guide") return
    var show = root.selected
    var now = Date.now() / 1000
    var c = { row: r, show: show, at: root.cursorAt, offer: null, later: null, entry: null, rule: null, series: false }
    var listed = ch.kind === "iptv" && dvr.settings.on && listings.has(ch.url)
    if (show && show.locked) {
      // its show hidden: on now, Record works out what's on once it's
      // unlocked; later, the show at that time, once the passcode's given
      var hiddenNow = c.at <= now + 60
      c.offer = hiddenNow ? dvr.offer(r, null) : null
      c.later = !hiddenNow && listed ? { label: "Record", note: "" } : null
      c.series = listed
    } else {
      c.entry = dvr.forShow(r, show)
      c.offer = c.entry ? null : dvr.offer(r, show)
      c.later = c.entry || c.offer ? null : dvr.laterOffer(r, show)
      var seriesOk = listed && show && show.epg === true && !!show.title
      c.rule = (c.entry ? dvr.ruleOf(c.entry) : null) || (seriesOk ? dvr.ruleFor(ch, show.title) : null)
      c.series = seriesOk
    }
    root.showChoice = c
    root.showCursor = 0
    root.dialog = "showChoices"
    keys.forceActiveFocus()
  }
  function moveShowChoice(d) { root.showCursor = Math.max(0, Math.min(root.showChoices.length - 1, root.showCursor + d)) }
  function closeShowChoices() { root.showChoice = null; if (root.dialog === "showChoices") root.dialog = ""; keys.forceActiveFocus() }
  function showChoiceAct(i) {
    var a = root.showChoices[i === undefined ? root.showCursor : i]
    var c = root.showChoice
    if (!a || !c || a.unavailable) return
    root.closeShowChoices()
    // a locked channel's hidden show: the passcode, then the show at that time
    var visible = function(then) {
      if (!c.show || !c.show.locked) { then(c.show); return }
      var ch = root.channels[c.row]
      var go = function() { var s = ch ? listings.at(ch.url, c.at) : null; if (s) then(s) }
      if (!root.askToWatch(c.row, go)) go()
    }
    if (a.key === "watch") root.watch(c.row)
    else if (a.key === "record" && c.offer) dvr.record(c.row, null, 0, c.show && !c.show.locked ? c.show : null)
    else if (a.key === "schedule") visible(function(s) { dvr.schedule(c.row, s) })
    else if (a.key === "series") visible(function(s) { dvr.recordSeries(c.row, s) })
    else if (a.key === "cancel" && c.entry) dvr.cancel(c.entry.id)
    else if (a.key === "stopSeries" && c.rule) dvr.stopSeries(c.rule.id)
    else if (a.key === "stopRec" && c.entry) dvr.stop(c.entry.id)
  }
  // For Commands.qml: whether a channel has listings, and the show listed at
  // a time (or the next one starting after)
  function listingsHave(ch) { return !!ch && listings.has(ch.url) }
  function showListed(ch, at, after) { return at ? listings.at(ch.url, at) : listings.after(ch.url, after) }
  // what's recording, for the guide (ProgramGrid, Masthead): a channel's REC, and the line at the top
  function recordingOn(ch) { return !!dvr.onChannel(ch) }
  readonly property string recordingNow: dvr.anyActive ? dvr.elsewhere() : ""
  // a title as it's shown (YouTube's 🔴 taken out: Schedule.js)
  function showTitle(t) { return Schedule.cleanTitle(t) }
  // a channel's listed shows in a span, visited without making each one (agents' shows)
  function eachListed(ch, from, to, visit) { listings.each(ch.url, from, to, visit) }
  function listedShow(s) { return listings.show(s) }

  // A recording's reason, for its details (a conflict naming the others as the lock is now)
  function recReason(rec) { return dvr.reasonOf(rec) }

  // What a program cell says about its show: "recording", "scheduled", "conflict" or ""
  function recMark(ch, show) { return dvr.markFor(ch, show) }
  function allowStream(ch) { dvr.allow(ch) }
  function answerStream(yes) {
    var a = root.streamAsk
    root.streamAsk = null
    if (root.dialog === "recStream") { root.dialog = ""; keys.forceActiveFocus() }
    if (root.bannerOptions) root.hideBanner()
    if (!a) return
    if (yes) { dvr.allow(root.channels[a.row]); a.then() }
  }

  function watch(r) {
    if (root.askToWatch(r, function() { root.watch(r) })) return
    if ((r !== root.tunedRow || root.reception === "off" || root.reception === "lost") && !root.streamOk(r, function() { root.watch(r) })) return
    if (r !== root.tunedRow || root.reception === "off" || root.reception === "lost") {
      root.bufferNext = true           // watched, so through pause and rewind's buffer from the start
      var tuned = root.tune(r)
      root.bufferNext = false
      if (tuned !== "ok") return
    }
    root.watching = true
    root.showBanner()
  }

  function showGuide() {
    root.watching = false
    if (root.tunedRow >= 0) root.row = root.tunedRow
    root.slotOffset = 0
    root.cursorTime = Date.now() / 1000
  }

  function surf(delta) {
    var v = root.visibleRows
    var n = v.length
    if (!n) return
    var p = Math.max(0, v.indexOf(root.tunedRow))
    for (var k = 0; k < n; k++) {
      p = (p + delta + n) % n
      if (root.airs(root.channels[v[p]]) && !channelLockItem.blocks(root.channels[v[p]])) break
    }
    var to = v[p]
    if (!root.streamOk(to, function() { root.tune(to); root.pip ? root.showPipBanner() : root.showBanner() })) return
    root.tune(to)
    root.showBanner()
  }

  // The file picker: channel lists in your home folder, newest first

  // images: a picture for the style panel (for area, or the background),
  // not a channel list
  function openPicker(images, area, folders, appFiles, signedApps) {
    root.cancelJob()
    root.pickImages = images === true
    root.pickFolders = folders === true
    root.pickApps = appFiles === true && appsStore.developer
    root.pickSignedApps = signedApps === true && appsStore.unknownSources
    root.pickArea = area || ""
    root.pickFiles = []
    root.dialog = "pick"
    root.pickQuery = ""
    root.pickCursor = 0
    root.pickSearching = true
    dialogBox.pickInput.text = ""
    if (root.pickBrowse) root.browseTo(root.pickDir || Quickshell.env("HOME"))
    else finder.replace(finder.argv)
    Qt.callLater(function() { dialogBox.pickInput.forceActiveFocus() })
  }

  // Tab: Search (every match in your home folder) or Browse (a folder at a time)
  function pickToggleBrowse() {
    root.pickBrowse = !root.pickBrowse
    dialogBox.pickInput.text = ""
    root.pickCursor = 0
    if (root.pickBrowse) root.browseTo(root.pickDir || Quickshell.env("HOME"))
    else if (!root.pickFiles.length) { root.pickSearching = true; finder.replace(finder.argv) }
  }

  function browseTo(dir) {
    var d = String(dir || "/").replace(/\/+$/, "") || "/"
    var home = Quickshell.env("HOME")
    if (root.pickSignedApps && d !== home && d.indexOf(home + "/") !== 0) d = home
    root.pickDir = d
    root.pickEntries = []
    root.pickCursor = 0
    root.pickSearching = true
    if (dialogBox.pickInput.text !== "") dialogBox.pickInput.text = ""
    browser.replace(["/usr/bin/find", d, "-maxdepth", "1", "-not", "-name", ".*", "-printf", "%Y\t%T@\t%p\n"])
  }

  // Backspace with nothing typed: up a folder
  function browseUp() {
    if (root.pickDir === "/" || (root.pickSignedApps && root.pickDir === Quickshell.env("HOME"))) return
    root.browseTo(root.pickDir.replace(/\/[^\/]*$/, "") || "/")
  }

  // What this picker picks, by a file's name
  function pickWants(name) {
    var n = String(name).toLowerCase()
    if (root.pickSignedApps) return /\.tvapp$/.test(n)
    if (root.pickApps) return /\.(tar\.gz|tgz)$/.test(n) || name === "app.json"
    if (root.pickFolders) return false
    if (root.pickImages) return /\.(jpe?g|png|webp)$/.test(n)
    return /\.(csv|tsv|txt|json|m3u8?)$/.test(n) && !/^(package.*|tsconfig.*|jsconfig|composer|manifest)\.json$/.test(n)
  }

  function entriesFound(text) {
    var dir = root.pickDir
    var lines = String(text).split("\n")
    // the folder itself comes first: output for another folder (one left quickly) is let go
    var first = lines[0] ? lines[0].split("\t")[2] : ""
    if (first !== dir && !(dir === "/" && first === "/")) return
    var dirs = [], files = []
    for (var i = 1; i < lines.length && dirs.length + files.length < 1000; i++) {
      var parts = lines[i].split("\t")
      if (parts.length < 3) continue
      var path = parts.slice(2).join("\t")
      var name = path.slice(path.lastIndexOf("/") + 1)
      var entry = { path: path, name: name, where: "", mtime: Number(parts[1]) }
      if (parts[0] === "d") { entry.dir = true; dirs.push(entry) }
      else if (parts[0] === "f" && root.pickWants(name)) files.push(entry)
    }
    var byName = function(a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0 }
    dirs.sort(byName)
    files.sort(byName)
    var top = []
    if (dir !== "/" && !(root.pickSignedApps && dir === Quickshell.env("HOME"))) top.push({ path: dir.replace(/\/[^\/]*$/, "") || "/", name: "Up a folder", where: "", up: true, mtime: 0 })
    if (root.pickFolders) top.push({ path: dir, name: "Use this folder", where: root.shownPath(dir), here: true, mtime: 0 })
    root.pickEntries = top.concat(dirs, files)
    root.pickSearching = false
  }

  function filesFound(text) {
    var home = Quickshell.env("HOME")
    var seen = {}
    var files = String(text).split("\n").filter(function(l) {
      var path = l.slice(l.indexOf("\t") + 1)
      if (!l || seen[path]) return false
      seen[path] = true
      return true
    }).map(function(l) {
      var tab = l.indexOf("\t")
      var path = l.slice(tab + 1)
      return { path: path, shown: path.indexOf(home + "/") === 0 ? "~" + path.slice(home.length) : path, mtime: Number(l.slice(0, tab)) }
    })
    // Lists first (.csv, .tsv, .txt), then .json, which apps also use for their own data.
    var rank = function(f) { return /\.json$/i.test(f.path) ? 1 : 0 }
    files.sort(function(a, b) { return rank(a) - rank(b) || b.mtime - a.mtime })
    root.pickFiles = files
    root.pickSearching = false
  }

  function movePick(delta) {
    var n = root.pickMatches.length
    if (!n) return
    root.pickCursor = Math.max(0, Math.min(n - 1, root.pickCursor + delta))
    dialogBox.pickView.positionViewAtIndex(root.pickCursor, ListView.Contain)
  }

  // Loads the picked file the same way as typing its path into the add box.
  function choosePick(by) {
    var f = root.pickMatches[root.pickCursor]
    if (!f) return
    if (f.up || f.dir) { root.browseTo(f.path); return }   // browsing: into it, or up
    if (root.pickSignedApps) {
      if (by === root.byUser) appsStore.getAppFile(f.path, root.reviewIfStill("pick", by))
      return
    }
    if (root.pickApps) {
      if (by === root.byUser) appsStore.getFile(f.path, root.reviewIfStill("pick", by))
      return
    }
    if (root.pickFolders) {
      root.pickFolders = false
      if (root.pickArea === "saver") root.setSaver({ folder: f.path })
      else if (root.pickArea === "recordings") dvr.useFolder(f.path)
      else root.setVideos(true, f.path)
      root.dialog = ""
      keys.forceActiveFocus()
      return
    }
    if (root.pickImages) {
      // Home's picture and an app screen's: checked by the helper and copied
      // into the guide's own folder, and only the copy is shown
      if (root.pickArea === "home") {
        root.dialog = ""
        keys.forceActiveFocus()
        root.homePicture(f.path, "image")
        return
      }
      if (root.pickArea === "multiview") {
        root.dialog = ""
        keys.forceActiveFocus()
        root.multiviewPicture(f.path)
        return
      }
      if (root.pickArea === "appScreen") {
        // the panel that asked, as it was: a late copy never lands on another
        var req = appPanelItem.pickReq
        root.dialog = ""
        keys.forceActiveFocus()
        root.importPicture(f.path, function(res) { appPanelItem.setPicture(res, req) })
        return
      }
      if (root.pickArea) {
        var now = root.areaImages[root.pickArea]
        var slot = root.imageSlotOf(root.pickArea)
        root.setImageOverride(root.pickArea, { src: f.path, fit: now ? now.fit : slot.fit, opacity: now ? now.opacity : slot.opacity })
      } else {
        root.bgImage = f.path
        root.bgMode = "image"
        root.bgFrom = "user"
      }
      root.saveSettings()
      root.backToStyle()
      return
    }
    root.dialog = "add"
    root.addFailed = false
    dialogBox.addInput.text = f.shown
    root.addChannel(f.shown)
    Qt.callLater(function() { dialogBox.addInput.forceActiveFocus() })
  }

  // The key hints under the guide, and in each box: keycaps, then what they
  // do. "+" between keys means together, "/" means either.
  readonly property var footerHints: channelLockItem.boxUp ? channelLockItem.hints : managing ? [
    { keys: ["SPACE"], label: "Mark" }, { keys: ["SHIFT", "+", "SPACE"], label: "Category" },
    { keys: ["SHIFT", "+", "↑", "↓"], label: "Move" }, { keys: ["N"], label: "Rename" }, { keys: ["C"], label: "Category" },
    { keys: ["L"], label: "Lock" }, { keys: ["DEL"], label: "Remove" }, { keys: ["?"], label: "All keys" }, { keys: ["E"], label: "Done" }
  ] : [
    { keys: ["↑", "↓"], label: "Channel" }, { keys: ["←", "→"], label: "Program" }, { keys: ["ENTER"], label: "Watch" }].concat(dvr.settings.on ? [{ keys: ["I"], label: "Record…" }] : []).concat([{ keys: ["V"], label: "Library" },
    { keys: ["/"], label: "Search" }, { keys: ["P"], label: "Mini player" }, { keys: ["W"], label: windowed ? "Full screen" : "Window" }, { keys: ["T"], label: "Phone remote" }, { keys: ["A"], label: "Add" }, { keys: ["E"], label: "Manage" },
    { keys: ["S"], label: "Style" }, { keys: [","], label: "Settings" }, { keys: ["?"], label: "All keys" }, { keys: ["K"], label: "Hide keys" },
    { keys: ["ESC"], label: homeEnabled ? "Home" : "Close" }
  ])
  readonly property var dialogHints: dialog === "remove" ? [{ keys: ["ENTER"], label: "Remove" }, { keys: ["ESC"], label: "Keep" }]
    : dialog === "filter" ? [{ keys: ["↑", "↓"], label: "Move" }, { keys: ["SPACE"], label: "On / off" }].concat(hasIptv ? [{ keys: ["←", "→"], label: "Sources" }] : [])
        .concat([{ keys: ["ENTER"], label: "Show" }, { keys: ["ESC"], label: "Cancel" }])
    : dialog === "pick" ? ((pickApps || pickSignedApps) && appsStore.inspecting ? [{ keys: [], label: "Checking it…" }]
        : pickBrowse ? [{ keys: ["↑", "↓"], label: "Pick" }, { keys: ["ENTER"], label: "Open" }, { keys: ["⌫"], label: "Up a folder" }, { keys: ["TAB"], label: "Search" }, { keys: ["ESC"], label: "Cancel" }]
        : [{ keys: [], label: "Type to search" }, { keys: ["↑", "↓"], label: "Pick" }, { keys: ["ENTER"], label: pickFolders ? "Use it" : pickApps || pickSignedApps ? "Check it" : "Open" }, { keys: ["TAB"], label: "Browse" }, { keys: ["ESC"], label: "Cancel" }])
    : dialog === "notes" ? [{ keys: ["↑", "↓"], label: "Scroll" }, { keys: ["ESC"], label: "Close" }]
    : dialog === "contributors" ? (contributors.length ? [{ keys: ["↑", "↓"], label: "Move" }, { keys: ["ENTER"], label: "Open on GitHub" }] : []).concat([{ keys: ["ESC"], label: "Close" }])
    : dialog === "reset" || dialog === "restore" ? backupsItem.hints(dialog)
    : dialog === "help" ? [{ keys: ["ESC"], label: "Close" }]
    : dialog === "agent" ? [{ keys: ["ENTER"], label: "Turn on" }, { keys: ["N"], label: "No thanks" }, { keys: ["ESC"], label: "Later" }]
    : dialog === "demo" ? [{ keys: ["Y"], label: "Load them" }, { keys: ["N"], label: "No thanks" }]
    : dialog === "recStream" ? [{ keys: ["ENTER"], label: "Watch anyway" }, { keys: ["ESC"], label: "Stay" }]
    : dialog === "showChoices" ? [{ keys: ["↑", "↓"], label: "Choose" }, { keys: ["ENTER"], label: "Pick" }, { keys: ["ESC"], label: "Back" }]
    : dialog === "remote" ? (remoteStep === "" ? [{ keys: ["ENTER"], label: "Turn on" }, { keys: ["ESC"], label: "Close" }]
        : remoteStep === "confirm" ? [{ keys: ["ENTER"], label: "Turn on" }, { keys: ["ESC"], label: "Cancel" }]
        : remoteStep === "firewall" ? [{ keys: [], label: "Waiting for your password…" }]
        : remoteStep === "off" ? [{ keys: ["ENTER"], label: "Turn off, remove rule" }, { keys: ["N"], label: "Turn off, keep rule" }, { keys: ["ESC"], label: "Cancel" }]
        : (remoteDevices.length ? [{ keys: ["↑", "↓"], label: "Phones" }, { keys: ["ENTER"], label: remoteArmed ? "Again to unpair" : "Unpair" }] : [])
            .concat(remoteAllowedHere ? [] : [{ keys: ["A"], label: "Allow this network" }])
            .concat([{ keys: ["T"], label: "Turn off" }, { keys: ["ESC"], label: "Close" }]))
    : dialog === "rename" ? [{ keys: ["ENTER"], label: "Save" }, { keys: ["ESC"], label: "Cancel" }]
    : dialog === "listings" ? (listingsAdding ? [{ keys: ["ENTER"], label: "Add" }, { keys: ["ESC"], label: "Back" }]
        : [{ keys: ["↑", "↓"], label: "Move" },
           (listingRows[listingsCursor] || {}).type === "source" ? { keys: ["ENTER"], label: listingsArmed ? "Again to remove" : "Remove" }
           : (listingRows[listingsCursor] || {}).type === "add" ? { keys: ["ENTER"], label: "Add a link or file" } : { keys: ["ENTER"], label: "Fetch now" },
           { keys: ["ESC"], label: "Close" }])
    : dialog === "appsOn" || dialog === "unknownOn" || dialog === "devOn" ? [{ keys: ["↑", "↓"], label: "Pick" }, { keys: ["ENTER"], label: (appsBoxRows[appsCursor] || {}).type === "yes" ? "Turn on" : "Not now" }, { keys: ["ESC"], label: "Not now" }]
    : dialog === "appCatalog" ? (appsStore.inspecting ? [{ keys: [], label: "Checking it…" }]
        : [{ keys: ["↑", "↓"], label: "Pick" },
           { keys: ["ENTER"], label: (appsBoxRows[appsCursor] || {}).type === "retry" ? "Try again" : appsStore.rowRecord(appsBoxRows[appsCursor]) && !appsStore.newer(((appsBoxRows[appsCursor] || {}).entry || {}).version, appsStore.rowRecord(appsBoxRows[appsCursor]).version) ? "Details" : "See what it asks for" },
           { keys: ["ESC"], label: "Close" }])
    : dialog === "appReview" ? (appsStore.installing ? [{ keys: [], label: "Installing…" }]
        : [{ keys: ["↑", "↓"], label: "Move" }, { keys: ["ENTER"], label: (appsBoxRows[appsCursor] || {}).type === "install" ? (appsStore.review && appsStore.review.updateConsent ? "Agree" : appsStore.review && appsStore.review.have && !appsStore.review.replaces ? "Update" : "Install")
                                                                       : (appsBoxRows[appsCursor] || {}).type === "fold" ? (reviewOpen[appsBoxRows[appsCursor].key] ? "Fold" : "Show all") : "Cancel" },
           { keys: ["ESC"], label: (appsBoxRows[appsCursor] || {}).type === "fold" && reviewOpen[appsBoxRows[appsCursor].key] ? "Fold" : "Cancel" }])
    : dialog === "appInfo" ? [{ keys: ["↑", "↓"], label: "Move" },
        (appsBoxRows[appsCursor] || {}).type === "fold" ? { keys: ["ENTER"], label: reviewOpen[appsBoxRows[appsCursor].key] ? "Fold" : "Show all" } :
        (appsBoxRows[appsCursor] || {}).type === "remove" ? { keys: ["ENTER"], label: appsArmed ? "Again to remove" : "Remove" }
        : (appsBoxRows[appsCursor] || {}).type === "toggle" ? { keys: ["ENTER"], label: "On / off" }
        : (appsBoxRows[appsCursor] || {}).type === "update" ? { keys: ["ENTER"], label: "See what it asks for" } : { keys: ["ENTER"], label: "Open it" },
        { keys: ["ESC"], label: "Close" }]
    : dialog === "category" ? [{ keys: [], label: "Type a new one, or" }, { keys: ["↑", "↓"], label: "Pick" }, { keys: ["ENTER"], label: "Set" }, { keys: ["ESC"], label: "Cancel" }]
    : [{ keys: ["ENTER"], label: "Add" }, { keys: ["SHIFT", "+", "ENTER"], label: "New line" }, { keys: ["CTRL", "+", "O"], label: "Pick a file" }, { keys: ["ESC"], label: "Cancel" }]

  // Every key, for the help box (?): [keys, what they do]; no keys is the mouse.
  readonly property var helpSections: [
    { title: "GUIDE", keys: [
      [["↑", "↓"], "Channel (the preview follows)"], [["←", "→"], "Program, up to 12 hours ahead"],
      [["PGUP", "PGDN"], "Previous / next category"], [["ENTER"], "Full screen"], [["I", "/", "SPACE"], "A show's choices: Watch, and Record while Recordings are on"], [["V"], "Library: movies, series, videos, recordings"], [["/"], "Search"], [["H"], "Home"], [["P"], "Mini player"],
      [["F"], "Show categories"], [["A"], "Add channels"], [["O"], "Open a channel list file"],
      [["E"], "Manage channels"], [["DEL"], "Remove a channel"], [["L"], "Logos on / off"],
      [["M"], "Mute"], [["R"], "Refresh listings, re-plan lineups"], [["K"], "Key hints on / off"], [["T"], "Phone remote"],
      [["S"], "Style: themes, colors, layout"], [["W"], "Window / full screen"], [[","], "Settings, and the AI agent skill"], [["?"], "This list"],
      [["ESC"], "Home (or close, with Home off)"],
      [["SUPER", "+", "ALT", "+", "T"], "Anywhere: open or close the guide (its shortcut, in Settings)"],
      [[], "Window / Full screen and Turn off: at the foot of the nav rail"]
    ] },
    { title: "HOME", keys: [
      [["↑", "↓", "←", "→"], "Move"], [["ENTER"], "Open, or play"], [["G"], "The guide"], [["V"], "The library"],
      [["C"], "Customize Home"], [["/"], "Search"], [["←"], "At the left edge: the nav rail"], [["C"], "On the open rail: customize it"], [["ESC"], "Close"]
    ] },
    { title: "LIBRARY (V)", keys: [
      [["↑", "↓", "←", "→"], "Move"], [["ENTER"], "Details (Recordings: choices)"], [["SPACE"], "Play, or resume (recording now: watch it live)"], [["L"], "Add to / take off My List"],
      [["TAB"], "Next tab (a number: go to one)"], [["X"], "Off Continue watching"], [["/"], "Search"], [["V"], "The guide"], [["H"], "Home"], [["ESC"], "Back"]
    ] },
    { title: "PLAYING A MOVIE OR VIDEO", keys: [
      [["SPACE", "/", "ENTER", "/", "K"], "Pause / play"], [["←", "→", "/", "J", "L"], "Back / ahead 10 s (Shift: 1 min)"],
      [["PGUP", "PGDN"], "Ahead / back 10 min"], [["HOME"], "From the start"], [["I", "/", "↑", "/", "↓"], "Show the player bar"],
      [["P"], "Mini player"], [["ESC", "/", "BACKSPACE"], "Stop: it remembers where"]
    ] },
    { title: "WATCHING FULL SCREEN", keys: [
      [["↑", "↓"], "Channel up / down"], [["ENTER", "/", "G"], "Back to the guide"], [["I", "/", "SPACE"], "Channel banner: Multiview, Record, Pause…"],
      [["J", "K", "L"], "Pause and rewind: back 30 s, pause or resume, forward 30 s (off: they offer Turn on)"],
      [["P"], "Mini player"], [["M"], "Mute"], [["ESC"], "TV off, back"]
    ] },
    { title: "MINI PLAYER (POINT AT IT)", keys: [
      [["↑", "↓"], "Channel up / down"], [["G"], "Back to the guide"], [["ENTER"], "Full screen"],
      [["M"], "Mute"], [["ESC"], "Close"], [[], "Drag to move, scroll to resize"]
    ] },
    { title: "SEARCH (/)", keys: [
      [[], "Type: channels, shows, movies, videos"], [["↓"], "Into the results"], [["ENTER"], "Open, watch or play"],
      [["DEL"], "Clear"], [["ESC"], "Back"]
    ] },
    { title: "APPS (ON THE RAIL, ONCE ON)", keys: [
      [["ENTER"], "Open one, full screen"], [["SUPER", "+", "W"], "In one: close it, back to the guide"], [["X"], "Close the one that's on"],
      [["I"], "What it's allowed, Remove"], [["G"], "Get apps"],
      [["/"], "In an app like Scores: search it"], [[","], "In one: its settings"], [["R"], "In one: load it again"],
      [["C"], "In one: customize its screen (its look, its rows)"], [["S"], "In one: the style panel"]
    ] },
    { title: "MANAGING (E)", keys: [
      [["SPACE"], "Mark a channel"], [["SHIFT", "+", "SPACE"], "Mark its whole category"], [["SHIFT", "+", "↑", "↓"], "Move it within its category"],
      [["N"], "Rename"], [["C"], "Set category"], [["L"], "Lock or unlock (the passcode first)"], [["DEL"], "Remove marked (or this one)"], [["E", "/", "ESC"], "Done"]
    ] }
  ]

  // The style panel (S)

  function isHex(v) { return /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v) }

  function clamp(v, lo, hi, otherwise) { return isNaN(v) ? otherwise : Math.max(lo, Math.min(hi, v)) }

  function slotOf(key) {
    for (var i = 0; i < root.colorSlots.length; i++) if (root.colorSlots[i].key === key) return root.colorSlots[i]
    return null
  }

  function imageSlotOf(key) {
    for (var i = 0; i < root.imageSlots.length; i++) if (root.imageSlots[i].key === key) return root.imageSlots[i]
    return null
  }

  // An area's name, said in full ("Lower third picture" rather than "Picture")
  function imageAreaName(key) {
    return { masthead: "Logo", infoPanel: "Info panel", header: "Time bar", band: "Category bands", channelCell: "Channel column",
             cell: "Program cells", lt: "Lower third", card: "Channel card", box: "Boxes", home: "Home's background", multiview: "Multiview's background" }[key] || key
  }

  // undefined takes yours off (the theme's shows); { src: "" } is none over the theme's
  function setImageOverride(key, spec) {
    var o = {}
    for (var k in root.imageOverrides) if (k !== key) o[k] = root.imageOverrides[k]
    if (spec !== undefined) o[key] = spec
    root.imageOverrides = o
  }

  // A picture setting as given (settings, a theme, a command), checked: a
  // full path to a .jpg/.png/.webp (or, from a theme, a file name in its
  // folder), "" for none, a known fit, opacity 0 to 1.
  function checkedImage(spec, key, allowNames) {
    if (!spec || typeof spec !== "object") return null
    var slot = root.imageSlotOf(key)
    var src = typeof spec.src === "string" ? spec.src : null
    var ok = src === "" || (src && /^\/.+\.(jpe?g|png|webp)$/i.test(src)) || (allowNames && src && /^[^\/\\.][^\/\\]*\.(jpe?g|png|webp)$/i.test(src))
    if (!slot || !ok) return null
    return { src: src, fit: root.imageFits.indexOf(spec.fit) >= 0 ? spec.fit : slot.fit,
             opacity: typeof spec.opacity === "number" ? Math.round(root.clamp(spec.opacity, 0, 1, slot.opacity) * 100) / 100 : slot.opacity }
  }

  // A slot's color in the theme that's on, before your own picks
  function themeColor(key) {
    var slot = root.slotOf(key)
    return (root.currentTheme.colors || {})[key] || (slot ? slot.value : "")
  }
  // which of your picks would stay on top of a theme once it's on (applyTheme
  // drops the ones it matches): colors, and styled parts
  function onTopOf(theme) {
    var colors = Object.keys(root.colorOverrides).filter(function(k) {
      var slot = root.slotOf(k)
      return root.colorOverrides[k] !== ((theme.colors || {})[k] || (slot ? slot.value : ""))
    })
    var styles = Object.keys(root.elementOverrides).filter(function(e) {
      var its = (theme.elements || {})[e] || {}
      return Object.keys(root.elementOverrides[e]).some(function(prop) { return JSON.stringify(root.elementOverrides[e][prop]) !== JSON.stringify(its[prop]) })
    })
    return { colors: colors, styles: styles }
  }

  // "" goes back to the theme's color
  function setOverride(key, value) {
    var o = {}
    for (var k in root.colorOverrides) if (k !== key) o[k] = root.colorOverrides[k]
    if (value && root.slotOf(key) && value.toLowerCase() !== root.themeColor(key)) o[key] = value.toLowerCase()
    root.colorOverrides = o
  }

  // Also reachable from outside: omarchy-shell shell call marcho78.om-pg setColor "timeline=#00ff00"
  // ("timeline=" goes back to the theme's). The om-pg commands have it too.
  function setColor(arg) {
    var at = String(arg).indexOf("=")
    var key = String(arg).slice(0, at)
    var value = String(arg).slice(at + 1).trim()
    if (at < 0 || !root.slotOf(key)) return "unknown slot; one of: " + root.colorSlots.map(function(c) { return c.key }).join(" ")
    if (value && !root.isHex(value)) return "not a color: use #rrggbb or #aarrggbb"
    root.setOverride(key, value)
    root.saveSettings()
    return root.colors[key].toString()
  }

  // What a theme sets besides colors, or the guide's own default
  function themeOption(section, field, otherwise) {
    var part = root.currentTheme[section]
    return part && part[field] !== undefined ? part[field] : otherwise
  }
  // the theme's background back (a reset of the look, or of the Background
  // row): its mode, and its picture as the theme's
  function putThemeBackground() {
    var bg = Look.themeBackground(root.currentTheme, { image: root.bgImage, from: root.bgFrom })
    root.bgImage = bg.image
    root.bgFrom = bg.from
    root.bgMode = bg.mode
  }

  // Puts a theme on: its colors under your own picks, and its picture,
  // banner and card settings if it has them.
  function applyTheme(id) {
    var theme = null
    for (var i = 0; i < root.themes.length; i++) if (root.themes[i].id === id) theme = root.themes[i]
    if (!theme) return false
    root.themeId = id
    if (theme.background) {
      if (theme.background.mode !== undefined) {
        var bg = Look.themeBackground(theme, { image: root.bgImage, from: root.bgFrom })
        root.bgImage = bg.image
        root.bgFrom = bg.from
        root.bgMode = bg.mode
      }
      if (theme.background.dim !== undefined) root.bgDim = theme.background.dim
    }
    if (theme.home && theme.home.background) {
      var hbg = theme.home.background
      var himg = hbg.image ? (hbg.image.charAt(0) === "/" ? hbg.image : theme.dir + "/" + hbg.image) : root.homeBackground.image
      root.replaceHomeBackground({ mode: hbg.mode || root.homeBackground.mode, image: himg || "", dim: hbg.dim !== undefined ? hbg.dim : root.homeBackground.dim })
    }
    if (theme.multiview && theme.multiview.background) {
      var mbg = theme.multiview.background
      var mimg = mbg.image ? (mbg.image.charAt(0) === "/" ? mbg.image : theme.dir + "/" + mbg.image) : root.multiviewBackground.image
      root.replaceMultiviewBackground({ mode: mbg.mode || root.multiviewBackground.mode, image: mimg || "", color: mbg.color || root.multiviewBackground.color || "",
                                        dim: mbg.dim !== undefined ? mbg.dim : root.multiviewBackground.dim })
    }
    if (theme.lowerThird) {
      if (theme.lowerThird.show !== undefined) root.ltShow = theme.lowerThird.show
      if (theme.lowerThird.seconds !== undefined) root.ltSeconds = theme.lowerThird.seconds
    }
    if (theme.card) {
      if (theme.card.show !== undefined) root.cardShow = theme.card.show
      if (theme.card.seconds !== undefined) root.cardSeconds = theme.card.seconds
    }
    // a pick that now matches the theme isn't yours any more
    var o = {}
    for (var k in root.colorOverrides) if (root.colorOverrides[k] !== root.themeColor(k)) o[k] = root.colorOverrides[k]
    root.colorOverrides = o
    var io = {}
    for (var a in root.imageOverrides) {
      var mine = root.imageOverrides[a]
      var its = (theme.images || {})[a]
      var itsPath = its && its.src ? (its.src.charAt(0) === "/" ? its.src : theme.dir + "/" + its.src) : ""
      if (!(its && mine.src === itsPath && mine.fit === its.fit && mine.opacity === its.opacity)) io[a] = mine
    }
    root.imageOverrides = io
    var eo = {}
    for (var e in root.elementOverrides) {
      var left = {}
      var itsStyle = (theme.elements || {})[e] || {}
      for (var prop in root.elementOverrides[e])
        if (JSON.stringify(root.elementOverrides[e][prop]) !== JSON.stringify(itsStyle[prop])) left[prop] = root.elementOverrides[e][prop]
      if (Object.keys(left).length) eo[e] = left
    }
    root.elementOverrides = eo
    var fo = {}
    for (var f in root.fontOverrides) if (root.fontOverrides[f] !== (theme.fonts || {})[f]) fo[f] = root.fontOverrides[f]
    root.fontOverrides = fo
    var lo = {}
    for (var l in root.layoutOverrides) if (root.layoutOverrides[l] !== (theme.layout || {})[l]) lo[l] = root.layoutOverrides[l]
    root.layoutOverrides = lo
    root.saveSettings()
    return true
  }

  function cycleTheme(d) {
    if (themesItem.changing) { root.styleRefused = themesItem.busyWhy; return }
    var at = 0
    for (var i = 0; i < root.themes.length; i++) if (root.themes[i].id === root.themeId) at = i
    root.applyTheme(root.themes[(at + d + root.themes.length) % root.themes.length].id)
  }

  // A theme as given (by an agent, or a file), checked: only the slots and
  // settings the guide knows, in range. Returns { theme, ignored: [what was left out] }.
  // fromDisk: read from its folder (its pictures only plain names there);
  // otherwise given to be saved (full paths too: the helper copies them in)
  function checkTheme(given, id, builtIn, dir, fromDisk) {
    // (a single-file theme from before folders has nowhere to keep a picture)
    var picture = function(v) { return fromDisk && !dir ? "" : Look.themePicture(v, fromDisk) }
    var ignored = []
    var theme = { id: id, builtIn: builtIn === true, colors: {}, images: {}, elements: {}, fonts: {}, layout: {}, dir: dir || "" }
    theme.name = typeof given.name === "string" && given.name.trim() ? given.name.trim().slice(0, 40) : id
    theme.description = typeof given.description === "string" ? given.description.trim().slice(0, 200) : ""
    for (var key in given) {
      if (["id", "name", "description", "colors", "images", "elements", "fonts", "layout", "background", "home", "multiview", "lowerThird", "card", "apps"].indexOf(key) < 0) ignored.push(key)
    }
    var colors = given.colors && typeof given.colors === "object" ? given.colors : {}
    for (var c in colors) {
      if (!root.slotOf(c)) ignored.push("colors." + c)
      else if (typeof colors[c] === "string" && Look.isOmarchy(colors[c].trim())) theme.colors[c] = colors[c].trim()
      else if (typeof colors[c] !== "string" || !root.isHex(colors[c])) ignored.push("colors." + c + " (#rrggbb, #aarrggbb, or omarchy.<name> from the Omarchy theme's colors.toml)")
      else theme.colors[c] = colors[c].toLowerCase()
    }
    var bg = given.background
    if (bg && typeof bg === "object") {
      theme.background = {}
      if (["none", "wallpaper", "image"].indexOf(bg.mode) >= 0) theme.background.mode = bg.mode
      else if (bg.mode !== undefined) ignored.push("background.mode (none, wallpaper or image)")
      if (picture(bg.image)) theme.background.image = bg.image
      else if (bg.image !== undefined) ignored.push("background.image (" + (fromDisk ? "a picture in the theme's folder" : "a full path to a .jpg, .png or .webp") + ")")
      if (theme.background.mode === "image" && !theme.background.image) { delete theme.background.mode; ignored.push("background.mode image needs background.image") }
      if (typeof bg.dim === "number") theme.background.dim = root.clamp(bg.dim, 0, 0.95, 0.6)
      else if (bg.dim !== undefined) ignored.push("background.dim (0 to 0.95)")
    }
    var images = given.images && typeof given.images === "object" ? given.images : {}
    for (var area in images) {
      var img = images[area] && typeof images[area] === "object" && (images[area].src === "" || picture(images[area].src)) ? root.checkedImage(images[area], area, true) : null
      if (img) theme.images[area] = img
      else ignored.push("images." + area + (root.imageSlotOf(area) ? " (src: a full path to a .jpg, .png or .webp)" : ""))
    }
    var els = Look.checkElements(given.elements, root.colorKeys, root.installedFonts)
    theme.elements = els.elements
    ignored = ignored.concat(els.ignored)
    var fonts = Look.checkFonts(given.fonts, root.installedFonts)
    theme.fonts = fonts.fonts
    ignored = ignored.concat(fonts.ignored)
    var layout = Look.checkLayout(given.layout)
    theme.layout = layout.layout
    ignored = ignored.concat(layout.ignored)
    // Home's background: the same choices as on Home, a picture as a full path (or a name in the theme's folder)
    var hb = given.home && typeof given.home === "object" ? given.home.background : undefined
    if (hb !== undefined) {
      if (hb && typeof hb === "object") {
        var homeBg = {}
        if (root.homeBgModes.indexOf(hb.mode) >= 0) homeBg.mode = hb.mode
        else if (hb.mode !== undefined) ignored.push("home.background.mode (" + root.homeBgModes.join(", ") + ")")
        if (picture(hb.image)) homeBg.image = hb.image
        else if (hb.image !== undefined) ignored.push("home.background.image (" + (fromDisk ? "a picture in the theme's folder" : "a full path to a .jpg, .png or .webp") + ")")
        if (homeBg.mode === "image" && !homeBg.image) { delete homeBg.mode; ignored.push("home.background.mode image needs home.background.image") }
        if (typeof hb.dim === "number") homeBg.dim = root.clamp(hb.dim, 0, 0.95, 0.6)
        else if (hb.dim !== undefined) ignored.push("home.background.dim (0 to 0.95)")
        theme.home = { background: homeBg }
      } else ignored.push("home.background ({mode, image, dim})")
    }
    // Multiview's background: none, color, theme, wallpaper or image, a picture as Home's
    var mvb = given.multiview && typeof given.multiview === "object" ? given.multiview.background : undefined
    if (mvb !== undefined) {
      if (mvb && typeof mvb === "object") {
        var mvBg = {}
        if (root.mvBgModes.indexOf(mvb.mode) >= 0) mvBg.mode = mvb.mode
        else if (mvb.mode !== undefined) ignored.push("multiview.background.mode (" + root.mvBgModes.join(", ") + ")")
        if (picture(mvb.image)) mvBg.image = mvb.image
        else if (mvb.image !== undefined) ignored.push("multiview.background.image (" + (fromDisk ? "a picture in the theme's folder" : "a full path to a .jpg, .png or .webp") + ")")
        if (mvBg.mode === "image" && !mvBg.image) { delete mvBg.mode; ignored.push("multiview.background.mode image needs multiview.background.image") }
        if (root.solidHex(mvb.color)) mvBg.color = mvb.color.toLowerCase()
        else if (mvb.color !== undefined) ignored.push("multiview.background.color (#rrggbb)")
        if (mvBg.mode === "color" && !mvBg.color) { delete mvBg.mode; ignored.push("multiview.background.mode color needs multiview.background.color") }
        if (typeof mvb.dim === "number") mvBg.dim = root.clamp(mvb.dim, 0, 0.95, 0.6)
        else if (mvb.dim !== undefined) ignored.push("multiview.background.dim (0 to 0.95)")
        theme.multiview = { background: mvBg }
      } else ignored.push("multiview.background ({mode, image, color, dim})")
    }
    // how every app's screen looks (its look, top, details, titles, size
    // and background): the theme's layer under your own choices
    // and background; its picture is a name in the theme's folder, or a full
    // path while it's being saved, which the helper copies in)
    if (given.apps !== undefined) {
      var appsLook = AppLooks.checkChoices(given.apps, "apps", true, function(v) { return !!picture(v) && (!!dir || v.charAt(0) === "/") })
      if (Object.keys(appsLook.choices).length) theme.apps = appsLook.choices
      var ab = theme.apps && theme.apps.background
      if (ab && typeof ab === "object" && ab.image && ab.image.charAt(0) !== "/") ab.image = dir + "/" + ab.image
      ignored = ignored.concat(appsLook.ignored)
    }
    var parts = [["lowerThird", 1, 15], ["card", 0.6, 5]]
    for (var p = 0; p < parts.length; p++) {
      var part = given[parts[p][0]]
      if (!part || typeof part !== "object") continue
      var out = {}
      if (typeof part.show === "boolean") out.show = part.show
      else if (part.show !== undefined) ignored.push(parts[p][0] + ".show (true or false)")
      if (typeof part.seconds === "number") out.seconds = Math.round(root.clamp(part.seconds, parts[p][1], parts[p][2], parts[p][1]) * 10) / 10
      else if (part.seconds !== undefined) ignored.push(parts[p][0] + ".seconds (" + parts[p][1] + " to " + parts[p][2] + ")")
      theme[parts[p][0]] = out
    }
    return { theme: theme, ignored: ignored }
  }

  function themeIdFrom(name) {
    return String(name || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 32)
  }

  // The theme files, read in one go: each is "\x1e<path>\n<its JSON>". A
  // theme is a folder (<id>/theme.json, its pictures beside it) or, from
  // before pictures, a single <id>.json; the folder wins.
  function themesRead(text) {
    var builtIns = {}
    var yours = {}
    var chunks = String(text).split("\x1e")
    for (var i = 0; i < chunks.length; i++) {
      var nl = chunks[i].indexOf("\n")
      if (nl < 0) continue
      var path = chunks[i].slice(0, nl)
      var folder = /\/theme\.json$/.test(path)
      var dir = folder ? path.replace(/\/theme\.json$/, "") : ""
      var id = root.themeIdFrom((folder ? dir : path).split("/").pop().replace(/\.json$/i, ""))
      var builtIn = path.indexOf(root.pluginDir + "/themes/") === 0
      var into = builtIn ? builtIns : yours
      if (!id || id === "retro" || (!builtIn && builtIns[id]) || (into[id] && into[id].dir && !folder)) continue
      try { into[id] = root.checkTheme(JSON.parse(chunks[i].slice(nl + 1)), id, builtIn, dir, true).theme }
      catch (e) { console.warn("om-pg: theme " + path + " is not valid JSON") }
    }
    var byName = function(a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1 }
    var values = function(o) { return Object.keys(o).map(function(k) { return o[k] }) }
    root.themes = [root.retroTheme].concat(values(builtIns).sort(byName), values(yours).sort(byName))
    if (root.themePending) root.putDefaultTheme()
  }

  // A first start (no settings yet: a new install, or after Reset): the
  // default theme on, with its picture, banner and card (once it's read)
  function putDefaultTheme() {
    root.themePending = !root.themes.some(function(t) { return t.id === root.defaultThemeId })
    if (!root.themePending) root.applyTheme(root.defaultThemeId)
  }

  // A theme as it goes to disk: its parts, with its pictures by full path
  // (the helper checks each and copies it into the theme's folder under a
  // new name)
  function themeOnDisk(theme) {
    var onDisk = { name: theme.name, description: theme.description, colors: theme.colors, images: {} }
    if (Object.keys(theme.fonts || {}).length) onDisk.fonts = theme.fonts
    if (Object.keys(theme.layout || {}).length) onDisk.layout = theme.layout
    if (Object.keys(theme.elements || {}).length) onDisk.elements = theme.elements
    var full = function(src) { return src && src.charAt(0) !== "/" && theme.dir ? theme.dir + "/" + src : src }
    for (var area in theme.images) {
      var img = theme.images[area]
      onDisk.images[area] = { src: full(img.src), fit: img.fit, opacity: img.opacity }
    }
    if (theme.background) {
      onDisk.background = {}
      for (var b in theme.background) onDisk.background[b] = theme.background[b]
      if (onDisk.background.image) onDisk.background.image = full(onDisk.background.image)
    }
    if (theme.home && theme.home.background) {
      var hb = {}
      for (var hk in theme.home.background) hb[hk] = theme.home.background[hk]
      if (hb.image) hb.image = full(hb.image)
      onDisk.home = { background: hb }
    }
    if (theme.multiview && theme.multiview.background) {
      var mb = {}
      for (var mk in theme.multiview.background) mb[mk] = theme.multiview.background[mk]
      if (mb.image) mb.image = full(mb.image)
      onDisk.multiview = { background: mb }
    }
    if (theme.lowerThird) onDisk.lowerThird = theme.lowerThird
    if (theme.card) onDisk.card = theme.card
    if (theme.apps && Object.keys(theme.apps).length) onDisk.apps = JSON.parse(JSON.stringify(theme.apps))
    return onDisk
  }

  // Saves a theme (one confirmed transaction, Themes.qml) and only once it's
  // saved adds it and puts it on: what of yours then matches it comes off
  // (applyTheme), and so do the values for all apps it now gives (a
  // confirmed write; if that fails, the theme stays saved and on, and the
  // outcome says so). baked: what of yours went into it as it was saved
  // ({ images, all }): its pictures are copies in the theme's folder now, so
  // yours that are still exactly what was saved come off too. Answers
  // { ok, token } or { ok: false, error }.
  function saveThemeFiles(id, theme, what, baked) {
    return themesItem.save(id, root.themeOnDisk(theme), what, function(outcome, res, done) {
      if (outcome !== "saved") return
      var saved = root.checkTheme(res.theme, id, false, root.themesDir + "/" + id, true).theme
      root.themes = root.themes.filter(function(t) { return t.id !== id }).concat([saved])
      root.applyTheme(id)
      var same = function(a, b) { return a !== undefined && JSON.stringify(a) === JSON.stringify(b) }
      if (baked && baked.images) {
        // still as it was saved, and what the theme now gives there: its
        // copy of your picture, or none for your "none" ({ src: "" }); a
        // picture of yours it came back without stays yours
        var match = function(area) {
          var b = baked.images[area]
          if (!same(b, root.imageOverrides[area])) return false
          var its = saved.images && saved.images[area]
          return b && b.src === "" ? !its : !!its
        }
        var io = {}
        for (var area in root.imageOverrides) if (!match(area)) io[area] = root.imageOverrides[area]
        if (Object.keys(io).length !== Object.keys(root.imageOverrides).length) { root.imageOverrides = io; root.saveSettings() }
      }
      var drop = AppLooks.allMatching(appScreensItem.now.all, saved.apps || {})
      if (baked && baked.all) for (var k in baked.all)
        if (drop.indexOf(k) < 0 && saved.apps && saved.apps[k] !== undefined && same(baked.all[k], (appScreensItem.now.all || {})[k])) drop.push(k)
      if (!drop.length) { done(""); return }
      if (drop.indexOf("background") >= 0) appPanelItem.dropPick("all")
      var failed = "saved and on, but the values for all apps it now gives couldn't be cleared"
      var ch = appScreensItem.change("all", function(st) { drop.forEach(function(k) { delete st.all[k] }) }, "guide", "all apps: " + drop.join(", ") + " (the theme gives them)")
      if (!ch.ok) { done(failed); return }
      appScreensItem.whenDone(ch.token, function(o) { done(o === "failed" ? failed : "") })
    })
  }

  function readThemes() {
    themesItem.load()
  }

  // A picture of the guide as it is on screen, so an agent can look at what
  // it made (Snapshots.qml: the guard, the file, how it went)
  function snapshot(path) { return snapshotsItem.snapshot(path) }

  function openStyle() {
    appViewItem.userActs()
    root.dialog = "style"
    root.styleEditing = ""
    root.styleArmed = ""
    root.styleView = "main"
    root.styleStack = []
    root.readThemes()
    if (!root.styleRows[root.styleCursor] || root.styleRows[root.styleCursor].type === "header") root.styleCursor = 1
    stylePanel.list.positionViewAtIndex(root.styleCursor, ListView.Contain)
    keys.forceActiveFocus()
  }

  function backToStyle() {
    root.dialog = "style"
    root.pickImages = false
    stylePanel.list.positionViewAtIndex(root.styleCursor, ListView.Contain)
    keys.forceActiveFocus()
  }

  function moveStyle(delta) {
    var n = root.styleRows.length
    var c = root.styleCursor
    if (Math.abs(delta) > 1) {
      c = Math.max(1, Math.min(n - 1, c + delta))
      while (root.styleRows[c].type === "header") c += delta > 0 ? 1 : -1
    } else {
      do { c = (c + delta + n) % n } while (root.styleRows[c].type === "header")
    }
    root.styleCursor = c
    root.styleArmed = ""
    // the section's name comes into view with its first row
    if (c > 0 && root.styleRows[c - 1].type === "header") stylePanel.list.positionViewAtIndex(c - 1, ListView.Contain)
    stylePanel.list.positionViewAtIndex(c, ListView.Contain)
    if (c === 1) stylePanel.list.positionViewAtBeginning()
  }

  // Which section the cursor is in, for the sample under the list
  readonly property string styleSection: {
    for (var i = styleCursor; i >= 0; i--) if (styleRows[i] && styleRows[i].type === "header") return styleRows[i].label
    return ""
  }

  // The look as it is: the theme, your colors, the picture, banner and card
  function snapshotStyle() {
    var colors = {}
    for (var k in root.colorOverrides) colors[k] = root.colorOverrides[k]
    var images = {}
    for (var a in root.imageOverrides) images[a] = root.imageOverrides[a]
    return { theme: root.themeId, colors: colors, images: images, elements: JSON.parse(JSON.stringify(root.elementOverrides)),
             fonts: JSON.parse(JSON.stringify(root.fontOverrides)), layout: JSON.parse(JSON.stringify(root.layoutOverrides)),
             home: { background: { mode: root.homeBackground.mode, image: root.homeBackground.image, dim: root.homeBackground.dim } },
             multiview: { background: { mode: root.multiviewBackground.mode, image: root.multiviewBackground.image, color: root.multiviewBackground.color, dim: root.multiviewBackground.dim } },
             background: { mode: root.bgMode, image: root.bgImage, dim: root.bgDim, from: root.bgFrom },
             lowerThird: { show: root.ltShow, seconds: root.ltSeconds }, card: { show: root.cardShow, seconds: root.cardSeconds },
             appsAll: JSON.parse(JSON.stringify(appScreensItem.now.all || {})) }
  }

  // A saved look, checked as settings are (it's kept in settings.json)
  function checkedSnapshot(snap) {
    if (!snap || typeof snap !== "object") return null
    var colors = {}
    var given = snap.colors && typeof snap.colors === "object" ? snap.colors : {}
    for (var i = 0; i < root.colorSlots.length; i++) {
      var v = given[root.colorSlots[i].key]
      if (typeof v === "string" && root.isHex(v)) colors[root.colorSlots[i].key] = v.toLowerCase()
    }
    var images = {}
    for (var area in (snap.images || {})) {
      var img = root.checkedImage(snap.images[area], area, false)
      if (img) images[area] = img
    }
    var bg = snap.background || {}
    var lt = snap.lowerThird || {}
    var card = snap.card || {}
    var image = typeof bg.image === "string" && bg.image.charAt(0) === "/" ? bg.image : ""
    return { theme: typeof snap.theme === "string" && root.themeIdFrom(snap.theme) === snap.theme ? snap.theme : "retro", colors: colors, images: images,
             elements: Look.checkElements(snap.elements, root.colorKeys, root.installedFonts).elements,
             fonts: Look.checkFonts(snap.fonts, root.installedFonts).fonts,
             layout: Look.checkLayout(snap.layout).layout,
             homeBackground: (function(h) {
               h = h && h.background ? h.background : snap.homeBackground && typeof snap.homeBackground === "object" ? snap.homeBackground : {}
               var img = root.homePictureOk(h.image) ? h.image : ""
               var mode = root.homeBgModes.indexOf(h.mode) >= 0 && (h.mode !== "image" || img) ? h.mode : "focus"
               return { mode: mode, image: img, dim: root.clamp(Number(h.dim), 0, 0.95, 0.6) }
             })(snap.home),
             multiviewBackground: (function(m) {
               m = m && m.background && typeof m.background === "object" ? m.background
                 : snap.multiviewBackground && typeof snap.multiviewBackground === "object" ? snap.multiviewBackground : {}
               var img = root.homePictureOk(m.image) ? m.image : ""
               var color = root.solidHex(m.color) ? m.color.toLowerCase() : ""
               var mode = root.mvBgModes.indexOf(m.mode) >= 0 && (m.mode !== "image" || img) && (m.mode !== "color" || color) ? m.mode : "none"
               return { mode: mode, image: img, color: color, dim: root.clamp(Number(m.dim), 0, 0.95, 0.6) }
             })(snap.multiview),
             background: { mode: bg.mode === "wallpaper" || (bg.mode === "image" && image) ? bg.mode : "none", image: image,
                           dim: root.clamp(Number(bg.dim), 0, 0.95, 0.6), from: Look.bgProvenance(bg.from) },
             lowerThird: { show: lt.show !== false, seconds: root.clamp(Number(lt.seconds), 1, 15, 4) },
             card: { show: card.show !== false, seconds: root.clamp(Number(card.seconds), 0.6, 5, 1.4) },
             // (one kept before resets took yours for all apps: null, and undo leaves them)
             appsAll: snap.appsAll && typeof snap.appsAll === "object" && !Array.isArray(snap.appsAll) ? AppLooks.checkChoices(snap.appsAll, "all", false, appScreensItem.pictureOk).choices : null }
  }

  // Resets the look. "theme": your own colors off, and the theme's picture,
  // banner and card settings back. "original": Premiere, as the guide comes.
  // Either way the look before is kept, for undoReset. Themes stay saved,
  // and channels and settings aren't touched.
  function resetStyle(to) {
    if (themesItem.changing) return { ok: false, error: themesItem.busyWhy }
    if (root.lookSaving) return { ok: false, error: "the last reset is still being saved: try again in a moment" }
    var before = root.snapshotStyle()
    var was = root.beforeReset
    // yours for all apps go first (a confirmed write): refused there, nothing
    // changes at all; if that write fails later (AppScreens puts them back),
    // what the reset changed goes back too (but what you've changed since),
    // and undo is as it was. Until it's saved, no other reset or undo.
    var cleared = null
    if (Object.keys(appScreensItem.now.all || {}).length) {
      cleared = appScreensItem.change("all", function(st) { st.all = {} }, "guide", "all apps: reset")
      if (!cleared.ok) return { ok: false, error: cleared.error }
      appPanelItem.dropPick("all")
    }
    root.beforeReset = before
    if (to === "original") root.themeId = root.defaultThemeId
    root.colorOverrides = ({})
    root.imageOverrides = ({})
    root.elementOverrides = ({})
    root.fontOverrides = ({})
    root.layoutOverrides = ({})
    var themeHome = (root.currentTheme.home || {}).background || {}
    root.replaceHomeBackground({ mode: themeHome.mode || "focus",
                                 image: themeHome.image ? (themeHome.image.charAt(0) === "/" ? themeHome.image : root.currentTheme.dir + "/" + themeHome.image) : "",
                                 dim: themeHome.dim !== undefined ? themeHome.dim : 0.6 })
    var themeMv = (root.currentTheme.multiview || {}).background || {}
    root.replaceMultiviewBackground({ mode: themeMv.mode || "none",
                                      image: themeMv.image ? (themeMv.image.charAt(0) === "/" ? themeMv.image : root.currentTheme.dir + "/" + themeMv.image) : "",
                                      color: themeMv.color || "", dim: themeMv.dim !== undefined ? themeMv.dim : 0.6 })
    root.putThemeBackground()
    root.bgDim = root.themeOption("background", "dim", 0.6)
    root.ltShow = root.themeOption("lowerThird", "show", true)
    root.ltSeconds = root.themeOption("lowerThird", "seconds", 4)
    root.cardShow = root.themeOption("card", "show", true)
    root.cardSeconds = root.themeOption("card", "seconds", 1.4)
    root.saveSettings()
    if (cleared) root.whenLookSaved(cleared.token, before, root.snapshotStyle(), function() {
      if (root.beforeReset === before) root.beforeReset = was
      root.styleRefused = "the reset couldn't be saved, so the look is as it was"
    })
    return { ok: true, saving: cleared ? cleared.token : "" }
  }

  // A reset's or undo's write for all apps, out: until it's done, no other
  // reset or undo. If it fails (AppScreens puts yours for all apps back),
  // each part of the look the operation changed goes back to base, unless
  // it's been changed since (that change of yours stays); then failed().
  function whenLookSaved(token, base, applied, failed) {
    root.lookSaving = token
    appScreensItem.whenDone(token, function(o) {
      if (root.lookSaving === token) root.lookSaving = ""
      if (o !== "failed") return
      root.takeBackStyle(root.checkedSnapshot(base), root.checkedSnapshot(applied))
      failed()
      root.saveSettings()
    })
  }
  // Each part of the look that's still as applied goes back to base: your
  // colors, pictures, elements, fonts and layout setting by setting (an
  // element's style down to each of its properties), the theme, and the
  // background, Home's background, banner and card field by field. It's
  // no newer choice than a picture you picked since: that still lands.
  function takeBackStyle(base, applied) {
    var now = root.checkedSnapshot(root.snapshotStyle())
    var same = function(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
    var isObj = function(x) { return x !== null && typeof x === "object" && !Array.isArray(x) }
    // three ways: still as applied, base; changed since, what's there now,
    // and where both sides are objects, that's decided key by key
    var merge3 = function(b, a, n) {
      if (same(n, a)) return b
      if (!isObj(n) || (a !== undefined && !isObj(a)) || (b !== undefined && !isObj(b))) return n
      var out = {}
      var keys = {}
      ;[b, a, n].forEach(function(m) { for (var k in (m || {})) keys[k] = true })
      for (var k in keys) {
        var v = merge3(b ? b[k] : undefined, a ? a[k] : undefined, n[k])
        if (v !== undefined) out[k] = v
      }
      return out
    }
    var keyed = function(field) { return merge3(base[field], applied[field], now[field]) || {} }
    var part = function(field, sub) { return same(now[field][sub], applied[field][sub]) ? base[field][sub] : now[field][sub] }
    var back = { theme: same(now.theme, applied.theme) ? base.theme : now.theme,
                 colors: keyed("colors"), images: keyed("images"), elements: keyed("elements"), fonts: keyed("fonts"), layout: keyed("layout"),
                 homeBackground: { mode: part("homeBackground", "mode"), image: part("homeBackground", "image"), dim: part("homeBackground", "dim") },
                 multiviewBackground: { mode: part("multiviewBackground", "mode"), image: part("multiviewBackground", "image"),
                                        color: part("multiviewBackground", "color") || "", dim: part("multiviewBackground", "dim") },
                 background: { mode: part("background", "mode"), dim: part("background", "dim"),
                               // a picture and where it came from go together
                               image: same([now.background.image, now.background.from], [applied.background.image, applied.background.from]) ? base.background.image : now.background.image,
                               from: same([now.background.image, now.background.from], [applied.background.image, applied.background.from]) ? base.background.from : now.background.from },
                 lowerThird: { show: part("lowerThird", "show"), seconds: part("lowerThird", "seconds") },
                 card: { show: part("card", "show"), seconds: part("card", "seconds") } }
    if (back.homeBackground.mode === "image" && !back.homeBackground.image) back.homeBackground.mode = "focus"
    if (back.multiviewBackground.mode === "image" && !back.multiviewBackground.image) back.multiviewBackground.mode = "none"
    if (back.multiviewBackground.mode === "color" && !back.multiviewBackground.color) back.multiviewBackground.mode = "none"
    if (back.background.mode === "image" && !back.background.image) back.background.mode = "none"
    root.putStyle(back, true)
  }

  // The look you see (every color, yours included, the picture, banner and
  // card, and how every app's screen looks: the theme's with yours for all
  // apps over it, key by key) saved as a theme of its own, which is put on
  // once it's saved (saveThemeFiles). A name that's taken is replaced only
  // when replace is true, or it's the theme that's on (saving your changes
  // into it). Answers { ok, id, replaced, saving, theme } or { ok: false,
  // error, taken }.
  function saveLookAsTheme(name, description, replace) {
    if (themesItem.changing) return { ok: false, error: themesItem.busyWhy }
    if (root.lookSaving) return { ok: false, error: "the last reset is still being saved: try again in a moment" }
    var clean = String(name || "").trim().slice(0, 40)
    var id = root.themeIdFrom(clean)
    if (!id) return { ok: false, error: "give it a name" }
    var existing = null
    for (var i = 0; i < root.themes.length; i++) if (root.themes[i].id === id) existing = root.themes[i]
    if (id === "retro" || (existing && existing.builtIn)) return { ok: false, error: "\"" + (existing ? existing.name : "Retro") + "\" is built in: give yours another name" }
    if (existing && existing.id !== root.themeId && !replace) return { ok: false, taken: true, error: "there's already a theme called \"" + existing.name + "\"" }
    var colors = {}
    for (var c = 0; c < root.colorSlots.length; c++) {
      var slotKey = root.colorSlots[c].key
      var raw = root.colorOverrides[slotKey] || (root.currentTheme.colors || {})[slotKey]
      colors[slotKey] = raw && Look.isOmarchy(raw) ? raw : String(root.colors[slotKey]).toLowerCase()
    }
    var background = { mode: root.bgMode, dim: root.bgDim }
    if (root.bgMode === "image") background.image = root.bgImage
    var images = {}
    for (var a = 0; a < root.imageSlots.length; a++) {
      var img = root.areaImages[root.imageSlots[a].key]
      if (img) images[root.imageSlots[a].key] = { src: img.path, fit: img.fit, opacity: img.opacity }
    }
    var elements = {}
    var themeEls = root.currentTheme.elements || {}
    for (var te in themeEls) elements[te] = themeEls[te]
    for (var ye in root.elementOverrides) elements[ye] = Look.merge(elements[ye], root.elementOverrides[ye])
    var fonts = {}
    for (var r = 0; r < Look.FONT_ROLES.length; r++) {
      var role = Look.FONT_ROLES[r]
      var family = root.fontOverrides[role] || (root.currentTheme.fonts || {})[role]
      if (family) fonts[role] = family
    }
    var given = { name: clean, description: String(description || "").trim().slice(0, 200) || (existing ? existing.description : "Made from " + root.currentTheme.name + "."),
                  colors: colors, images: images, elements: elements, fonts: fonts, background: background,
                  layout: Look.merge(root.currentTheme.layout || {}, root.layoutOverrides),
                  home: { background: root.homeBackground.mode === "image" ? { mode: "image", image: root.homeBackground.image, dim: root.homeBackground.dim }
                                                                           : { mode: root.homeBackground.mode, dim: root.homeBackground.dim } },
                  multiview: { background: root.multiviewBackground.mode === "image" ? { mode: "image", image: root.multiviewBackground.image, dim: root.multiviewBackground.dim }
                                         : root.multiviewBackground.mode === "color" ? { mode: "color", color: root.multiviewBackground.color, dim: root.multiviewBackground.dim }
                                                                                     : { mode: root.multiviewBackground.mode, dim: root.multiviewBackground.dim } },
                  lowerThird: { show: root.ltShow, seconds: root.ltSeconds }, card: { show: root.cardShow, seconds: root.cardSeconds } }
    // the look every app's screen has now goes with it: the theme's, yours for all apps over it
    var apps = AppLooks.appsForTheme(root.currentTheme.apps || {}, appScreensItem.now.all)
    if (Object.keys(apps).length) given.apps = apps
    var theme = root.checkTheme(given, id, false, root.themesDir + "/" + id).theme
    var baked = { images: JSON.parse(JSON.stringify(root.imageOverrides)), all: JSON.parse(JSON.stringify(appScreensItem.now.all || {})) }
    var res = root.saveThemeFiles(id, theme, "theme " + id + ": saved from the look on screen", baked)
    if (!res.ok) return { ok: false, error: res.error }
    return { ok: true, id: id, replaced: !!existing, saving: res.token, theme: theme }
  }

  function openNaming() {
    var mine = !root.currentTheme.builtIn
    root.styleNaming = true
    root.namingNote = ""
    root.namingArmed = ""
    stylePanel.namingInput.text = mine ? root.currentTheme.name : root.currentTheme.name + " (mine)"
    Qt.callLater(function() { stylePanel.namingInput.forceActiveFocus(); stylePanel.namingInput.selectAll() })
  }

  function finishNaming(save) {
    if (save) {
      var name = stylePanel.namingInput.text.trim()
      var id = root.themeIdFrom(name)
      var done = root.saveLookAsTheme(name, "", root.namingArmed !== "" && root.namingArmed === id)
      if (!done.ok) {
        root.namingNote = done.taken ? done.error + ": Enter again replaces it, or change the name." : done.error + "."
        root.namingArmed = done.taken ? id : ""
        return
      }
    }
    root.styleNaming = false
    root.namingNote = ""
    root.namingArmed = ""
    keys.forceActiveFocus()
  }

  // Answers { ok, saving } or { ok: false, error } (the look kept for undo
  // stays when it's refused)
  function undoReset() {
    if (themesItem.changing) return { ok: false, error: themesItem.busyWhy }
    if (root.lookSaving) return { ok: false, error: "the last reset is still being saved: try again in a moment" }
    var snap = root.checkedSnapshot(root.beforeReset)
    if (!snap) return { ok: false, error: "there's no reset to undo" }
    // yours for all apps first (a confirmed write): refused there, nothing
    // changes; if that write fails later (AppScreens puts them back), what
    // the undo changed goes back to the look as reset (but what you've
    // changed since), and the look kept for undo stays
    var kept = root.beforeReset
    var asReset = root.snapshotStyle()
    var restored = null
    if (snap.appsAll && JSON.stringify(snap.appsAll) !== JSON.stringify(appScreensItem.now.all || {})) {
      restored = appScreensItem.change("all", function(st) { st.all = JSON.parse(JSON.stringify(snap.appsAll)) }, "guide", "all apps: the reset undone")
      if (!restored.ok) return { ok: false, error: restored.error }
      appPanelItem.dropPick("all")
    }
    root.beforeReset = null
    root.putStyle(snap)
    root.saveSettings()
    if (restored) root.whenLookSaved(restored.token, asReset, root.snapshotStyle(), function() {
      if (root.beforeReset === null) root.beforeReset = kept
      root.styleRefused = "the undo couldn't be saved, so the reset stays (undo it again)"
    })
    return { ok: true, saving: restored ? restored.token : "" }
  }

  // A checked look put back (undo, or a reset or undo taken back): all but
  // yours for all apps, which AppScreens keeps. takingBack: no newer choice
  // than a Home picture picked since, which still lands
  function putStyle(snap, takingBack) {
    root.themeId = snap.theme
    root.colorOverrides = snap.colors
    root.imageOverrides = snap.images
    root.elementOverrides = snap.elements
    root.fontOverrides = snap.fonts
    root.layoutOverrides = snap.layout
    if (takingBack) root.homeBackground = snap.homeBackground
    else root.replaceHomeBackground(snap.homeBackground)
    if (snap.multiviewBackground) {
      if (takingBack) root.multiviewBackground = snap.multiviewBackground
      else root.replaceMultiviewBackground(snap.multiviewBackground)
    }
    root.bgImage = snap.background.image
    root.bgMode = snap.background.mode
    root.bgFrom = Look.bgProvenance(snap.background.from)
    root.bgDim = snap.background.dim
    root.ltShow = snap.lowerThird.show
    root.ltSeconds = snap.lowerThird.seconds
    root.cardShow = snap.card.show
    root.cardSeconds = snap.card.seconds
  }

  // The rows change after a reset (undo comes, reset-to-theme goes on Premiere):
  // the cursor stays on the row asked for, or the nearest reset row.
  function styleCursorTo(types) {
    for (var t = 0; t < types.length; t++)
      for (var i = 0; i < root.styleRows.length; i++)
        if (root.styleRows[i].type === types[t]) { root.styleCursor = i; stylePanel.list.positionViewAtIndex(i, ListView.Contain); return }
  }

  function activateStyle() {
    var r = root.styleRows[root.styleCursor]
    if (!r) return
    if (r.type === "open") {
      root.styleGo(r.view, "")
    } else if (r.type === "part") {
      root.styleGo("element", r.key)
    } else if (r.type === "prop" && r.kind === "color") {
      var current = Look.getPath(Look.effective(root.currentTheme.elements, root.elementOverrides)[root.styleTarget] || {}, r.path)
      if (current && typeof current === "object") current = current.from          // a gradient: pick a plain color for it
      var shown = Look.colorOf(current, root.colors, root.omarchyColors)
      var mine = Look.getPath(root.elementOverrides[root.styleTarget] || {}, r.path)
      root.styleEditing = root.styleTarget + "|" + r.path
      root.styleBefore = mine === undefined ? "" : JSON.stringify(mine)
      stylePanel.picker.start(shown === "transparent" || shown === "auto" || shown === "inherit" ? "#00000000" : shown)
    } else if (r.type === "prop" || r.type === "layout" || r.type === "font" || r.type === "state") {
      root.adjustStyle(1)
    } else if (r.type === "resetPart") {
      if (root.styleArmed !== "resetPart") { root.styleArmed = "resetPart"; return }
      root.styleArmed = ""
      root.setElementStyle(root.styleTarget, undefined)
      root.saveSettings()
    } else if (r.type === "theme") {
      root.cycleTheme(1)
    } else if (r.type === "saveTheme") {
      root.openNaming()
    } else if (r.type === "color") {
      root.styleEditing = r.key
      root.styleBefore = root.colorOverrides[r.key] || ""
      stylePanel.picker.start(root.colors[r.key])
    } else if (r.type === "bg") {
      root.openPicker(true)
    } else if (r.type === "image") {
      root.openPicker(true, r.key)
    } else if (r.type === "lt" || r.type === "card") {
      root.toggleStyle()
    } else if (r.type === "resetTheme" || r.type === "resetOriginal") {
      if (themesItem.changing) { root.styleRefused = themesItem.busyWhy; return }
      if (root.styleArmed !== r.type) { root.styleArmed = r.type; return }
      root.styleArmed = ""
      var reset = root.resetStyle(r.type === "resetOriginal" ? "original" : "theme")
      if (!reset.ok) { root.styleRefused = reset.error; return }
      root.styleCursorTo(["undoReset", r.type])
    } else if (r.type === "undoReset") {
      var undone = root.undoReset()
      if (!undone.ok) { root.styleRefused = undone.error; return }
      root.styleCursorTo(["resetOriginal"])
    }
  }

  // The picker edits a color slot, or an element's color ("element|path")
  function previewColor(value) {
    if (!root.styleEditing) return
    var at = root.styleEditing.indexOf("|")
    if (at < 0) root.setOverride(root.styleEditing, stylePanel.picker.hex(value))
    else root.setElementProp(root.styleEditing.slice(0, at), root.styleEditing.slice(at + 1), stylePanel.picker.hex(value))
  }

  function finishPick(keep) {
    if (!root.styleEditing) return
    var at = root.styleEditing.indexOf("|")
    if (!keep && at < 0) root.setOverride(root.styleEditing, root.styleBefore)
    else if (!keep) root.setElementProp(root.styleEditing.slice(0, at), root.styleEditing.slice(at + 1),
                                        root.styleBefore ? JSON.parse(root.styleBefore) : undefined)
    root.styleEditing = ""
    root.saveSettings()
    keys.forceActiveFocus()
  }

  // Into a list (parts, layout, fonts) or a part; Esc comes back
  function styleGo(view, element) {
    root.styleStack = root.styleStack.concat([{ view: root.styleView, cursor: root.styleCursor, element: root.styleElement, state: root.styleState }])
    root.styleView = view
    if (view === "element") { root.styleElement = element; root.styleState = "" }
    root.styleArmed = ""
    root.styleCursor = 0
    root.moveStyle(1)
    stylePanel.list.positionViewAtBeginning()
  }

  function styleBack() {
    if (!root.styleStack.length) { root.closeDialog(); return }
    var back = root.styleStack[root.styleStack.length - 1]
    root.styleStack = root.styleStack.slice(0, -1)
    root.styleView = back.view
    root.styleElement = back.element
    root.styleState = back.state
    root.styleArmed = ""
    root.styleCursor = back.cursor
    stylePanel.list.positionViewAtIndex(root.styleCursor, ListView.Contain)
  }

  // Your style for one element (or element:state): set one property (value
  // undefined takes yours off), or all of it (style undefined: all off).
  // Checked like a theme's.
  function setElementStyle(name, style) {
    var all = {}
    for (var k in root.elementOverrides) if (k !== name) all[k] = root.elementOverrides[k]
    if (style !== undefined) {
      var input = {}
      input[name] = style
      var checked = Look.checkElements(input, root.colorKeys, root.installedFonts).elements[name]
      if (checked && Object.keys(checked).length) all[name] = checked
    }
    root.elementOverrides = all
  }

  function setElementProp(name, path, value) {
    root.setElementStyle(name, Look.withPath(root.elementOverrides[name] || {}, path, value))
  }

  // Your layout: one setting (value undefined: back to the theme's)
  function setLayoutOverride(key, value) {
    var all = {}
    for (var k in root.layoutOverrides) if (k !== key) all[k] = root.layoutOverrides[k]
    if (value !== undefined) {
      var input = {}
      input[key] = value
      var checked = Look.checkLayout(input).layout
      if (checked[key] !== undefined) all[key] = checked[key]
    }
    root.layoutOverrides = all
  }

  function setFontOverride(role, family) {
    var all = {}
    for (var k in root.fontOverrides) if (k !== role) all[k] = root.fontOverrides[k]
    if (family) all[role] = family
    root.fontOverrides = all
  }

  // The style an element has now (theme's with yours), at a path
  function elementValue(path) {
    return Look.getPath(Look.effective(root.currentTheme.elements, root.elementOverrides)[root.styleTarget] || {}, path)
  }

  // One step of a length ("2px" goes by pixels), a share, or along a list
  function stepped(r, v, d) {
    if (r.kind === "length") {
      if (typeof v === "string") return Math.max(0, Math.round(parseFloat(v) + d)) + "px"
      var n = Math.round(((typeof v === "number" ? v : 0) + d * r.step) * 1000) / 1000
      return Math.max(r.min, Math.min(r.max, n))
    }
    if (r.kind === "fraction") return Math.max(0, Math.min(1, Math.round(((typeof v === "number" ? v : 0) + d * r.step) * 100) / 100))
    if (r.kind === "width") {
      var w = v === "full" || v === undefined ? 1 : v
      w = Math.round((w + d * 0.05) * 100) / 100
      return w >= 1 ? "full" : Math.max(0.2, w)
    }
    var list = r.kind === "font" ? Look.FONT_ROLES.concat(root.usableFonts) : r.kind === "family" ? root.usableFonts : r.options || []
    var at = list.indexOf(v)
    return list[(at + d + list.length) % list.length]
  }

  function resetStyleRow() {
    var r = root.styleRows[root.styleCursor]
    if (!r) return
    if (r.type === "prop") root.setElementProp(root.styleTarget, r.path, undefined)
    else if (r.type === "layout") root.setLayoutOverride(r.key, undefined)
    else if (r.type === "font") root.setFontOverride(r.key, "")
    else if (r.type === "color") root.setOverride(r.key, "")
    else if (r.type === "theme") { if (themesItem.changing) root.styleRefused = themesItem.busyWhy; else root.applyTheme(root.defaultThemeId); return }
    else if (r.type === "image") {
      // yours off first (the theme's comes back); then none over the theme's
      if (root.imageOverrides[r.key] !== undefined) root.setImageOverride(r.key, undefined)
      else if (root.areaImages[r.key]) root.setImageOverride(r.key, { src: "" })
    }
    else if (r.type === "bg") root.putThemeBackground()
    else if (r.type === "dim") root.bgDim = root.themeOption("background", "dim", 0.6)
    else if (r.type === "lt") { root.ltShow = root.themeOption("lowerThird", "show", true); root.ltSeconds = root.themeOption("lowerThird", "seconds", 4) }
    else if (r.type === "card") { root.cardShow = root.themeOption("card", "show", true); root.cardSeconds = root.themeOption("card", "seconds", 1.4) }
    else return
    root.saveSettings()
  }

  function toggleStyle() {
    var r = root.styleRows[root.styleCursor]
    if (!r) return
    if (r.type === "prop" || r.type === "layout") { root.adjustStyle(1); return }
    if (r.type === "lt") root.ltShow = !root.ltShow
    else if (r.type === "card") root.cardShow = !root.cardShow
    root.saveSettings()
  }

  function adjustStyle(d) {
    var r = root.styleRows[root.styleCursor]
    if (!r) return
    if (r.type === "theme") { root.cycleTheme(d); return }
    if (r.type === "state") {
      var states = [""].concat((Look.BY_KEY[root.styleElement] || {}).states || [])
      root.styleState = states[(states.indexOf(root.styleState) + d + states.length) % states.length]
      return
    }
    if (r.type === "prop") {
      var v = root.elementValue(r.path)
      if (r.kind === "color") return
      if (r.kind === "bool") root.setElementProp(root.styleTarget, r.path, !v)
      else if (r.kind === "shadow") root.setElementProp(root.styleTarget, r.path, v && typeof v === "object" ? "none" : { color: "#99000000", blur: 1, x: 0, y: 0.3 })
      else root.setElementProp(root.styleTarget, r.path, root.stepped(r, v, d))
      root.saveSettings()
      return
    }
    if (r.type === "layout") {
      var spec = Look.LAYOUT_BY_KEY[r.key]
      var now = root.layout[r.key]
      if (spec.kind === "columns") return
      var next = spec.kind === "bool" ? !now
               : Array.isArray(spec.kind) ? spec.kind[(spec.kind.indexOf(now) + d + spec.kind.length) % spec.kind.length]
               : Math.round((now + d * (spec.step || 0.1)) * 1000) / 1000
      root.setLayoutOverride(r.key, next)
      root.saveSettings()
      return
    }
    if (r.type === "font") {
      root.setFontOverride(r.key, root.stepped({ kind: "family" }, root.fonts[r.key], d))
      root.saveSettings()
      return
    }
    if (r.type === "image") {
      var now = root.areaImages[r.key]
      if (!now) return
      var fit = root.imageFits[(root.imageFits.indexOf(now.fit) + d + root.imageFits.length) % root.imageFits.length]
      root.setImageOverride(r.key, { src: now.path, fit: fit, opacity: now.opacity })
    }
    else if (r.type === "bg") {
      var order = ["none", "wallpaper"].concat(root.bgImage ? ["image"] : [])
      root.bgMode = order[(Math.max(0, order.indexOf(root.bgMode)) + d + order.length) % order.length]
    }
    else if (r.type === "dim") root.bgDim = Math.round(root.clamp(root.bgDim + d * 0.05, 0, 0.95, 0.6) * 100) / 100
    else if (r.type === "lt") { root.ltShow = true; root.ltSeconds = root.clamp(root.ltSeconds + d, 1, 15, 4) }
    else if (r.type === "card") { root.cardShow = true; root.cardSeconds = Math.round(root.clamp(root.cardSeconds + d * 0.2, 0.6, 5, 1.4) * 10) / 10 }
    else return
    root.saveSettings()
  }

  // [ and ] on a picture row: fainter, stronger
  function fadeImage(d) {
    var r = root.styleRows[root.styleCursor]
    if (!r || r.type !== "image") return
    var now = root.areaImages[r.key]
    if (!now) return
    root.setImageOverride(r.key, { src: now.path, fit: now.fit, opacity: Math.round(root.clamp(now.opacity + d * 0.1, 0.1, 1, 1) * 100) / 100 })
    root.saveSettings()
  }

  // A row's name in the panel
  function styleRowLabel(r, current) {
    var t = r.type
    if (t === "theme") return "Theme"
    if (t === "saveTheme") return Object.keys(root.colorOverrides).length || Object.keys(root.elementOverrides).length ? "Save this look as a theme (your changes in it)" : "Save this look as a theme"
    if (t === "open" || t === "part") return r.label + "  ›"
    if (t === "state") return "Editing"
    if (t === "resetPart") return root.styleArmed === "resetPart" && current ? "Press Enter again to reset" : "This part back to the theme's"
    if (t === "bg") return "Picture"
    if (t === "dim") return "Darken the picture"
    if (t === "lt") return "Show the banner"
    if (t === "card") return "Show the card"
    if (t === "resetTheme") return root.styleArmed === "resetTheme" && current ? "Press Enter again to reset" : "Reset to " + root.currentTheme.name + ": your changes off"
    if (t === "resetOriginal") return root.styleArmed === "resetOriginal" && current ? "Press Enter again: back to the original" : "Back to the original look (Premiere)"
    if (t === "undoReset") return "Undo the last reset"
    return r.label || ""
  }

  // The color a row shows in its swatch, "image" for a picture, or "" for none
  function styleRowSwatch(r) {
    if (r.type === "color") return String(root.colors[r.key])
    if (r.type === "image") return "image"
    if (r.type === "prop" && r.kind === "color") {
      var v = root.elementValue(r.path)
      var c = Look.colorOf(v && typeof v === "object" ? v.from : v, root.colors, root.omarchyColors)
      return c === "auto" || c === "inherit" ? "transparent" : c
    }
    return ""
  }

  // Whether the row is the user's own change (shown bright)
  function styleRowYours(r) {
    if (r.type === "color") return !!root.colorOverrides[r.key]
    if (r.type === "image") return root.imageOverrides[r.key] !== undefined
    if (r.type === "prop") return Look.getPath(root.elementOverrides[root.styleTarget] || {}, r.path) !== undefined
    if (r.type === "layout") return root.layoutOverrides[r.key] !== undefined
    if (r.type === "font") return root.fontOverrides[r.key] !== undefined
    if (r.type === "part") return Object.keys(root.elementOverrides).some(function(k) { return k.split(":")[0] === r.key })
    return r.type === "theme" || r.type === "bg" || r.type === "dim" || r.type === "lt" || r.type === "card" || r.type === "state"
  }

  // Whether ← → change it (the value shows ‹ ›)
  function styleRowAdjustable(r) {
    if (r.type === "prop") return r.kind !== "color"
    if (r.type === "layout") return Look.LAYOUT_BY_KEY[r.key].kind !== "columns"
    return ["theme", "bg", "dim", "lt", "card", "font", "state"].indexOf(r.type) >= 0
  }

  function styleValue(r) {
    if (r.type === "prop") {
      var v = root.elementValue(r.path)
      if (r.kind === "color") {
        if (v && typeof v === "object") return "GRADIENT"
        var c = Look.colorOf(v, root.colors, root.omarchyColors)
        return v === undefined || v === "none" ? "NONE" : (Look.isOmarchy(v) ? v + "  " : root.colors[v] ? v + "  " : "") + (c === "auto" ? "AUTO" : c === "inherit" ? "THE TEXT'S" : c.toUpperCase())
      }
      if (r.kind === "shadow") return v && typeof v === "object" ? "ON" : "OFF"
      if (r.kind === "bool") return v ? "ON" : "OFF"
      if (v === undefined) return r.kind === "length" || r.kind === "fraction" ? "0" : r.kind === "font" ? "BODY" : r.options ? r.options[0].toUpperCase() : "—"
      if (Array.isArray(v)) return v.join(" ")
      return String(v).toUpperCase()
    }
    if (r.type === "layout") {
      var lv = root.layout[r.key]
      return Array.isArray(lv) ? lv.join(", ").toUpperCase() : typeof lv === "boolean" ? (lv ? "ON" : "OFF") : String(lv).toUpperCase()
    }
    if (r.type === "font") return root.fonts[r.key]
    if (r.type === "state") return root.styleState ? root.styleState.toUpperCase() : "AS IT IS"
    if (r.type === "color") return String(root.colors[r.key]).toUpperCase()
    if (r.type === "image") {
      var img = root.areaImages[r.key]
      return img ? img.path.split("/").pop().toUpperCase() + " · " + img.fit.toUpperCase() + " · " + Math.round(img.opacity * 100) + "%" : "NONE"
    }
    if (r.type === "theme") {
      var yours = Object.keys(root.colorOverrides).length
      return root.currentTheme.name.toUpperCase() + (yours ? " +" + yours : "") + (root.themes.length > 1 ? "  (" + (root.themes.indexOf(root.currentTheme) + 1) + "/" + root.themes.length + ")" : "")
    }
    if (r.type === "bg") return root.bgMode === "wallpaper" ? "OMARCHY WALLPAPER"
                              : root.bgMode === "image" ? root.bgImage.split("/").pop().toUpperCase() : "NONE"
    if (r.type === "dim") return Math.round(root.bgDim * 100) + "%"
    if (r.type === "lt") return root.ltShow ? "ON · " + root.ltSeconds + " S" : "OFF"
    if (r.type === "card") return root.cardShow ? "ON · " + root.cardSeconds.toFixed(1) + " S" : "OFF"
    return ""
  }

  readonly property var styleHintRows: {
    if (styleNaming) return [[{ keys: [], label: "Type a name" }, { keys: ["ENTER"], label: namingArmed ? "Replace" : "Save" }, { keys: ["ESC"], label: "Cancel" }]]
    if (styleEditing) return [
      [{ keys: ["←", "→", "↑", "↓"], label: "Shade" }, { keys: ["PGUP", "PGDN"], label: "Hue" }],
      [{ keys: ["[", "]"], label: "See-through" }, { keys: ["ENTER"], label: "Keep" }, { keys: ["ESC"], label: "Undo" }]
    ]
    var row = styleRows[styleCursor] || {}
    var t = row.type
    var back = styleView === "main" ? [{ keys: ["S", "/", "ESC"], label: "Close" }] : [{ keys: ["ESC"], label: "Back" }, { keys: ["S"], label: "Close" }]
    if (t === "open" || t === "part") return [[{ keys: ["ENTER"], label: "Open" }], [{ keys: ["↑", "↓"], label: "Move" }].concat(back)]
    if (t === "state") return [[{ keys: ["←", "→"], label: "Normal or a state" }], [{ keys: ["↑", "↓"], label: "Move" }].concat(back)]
    if (t === "prop" || t === "layout" || t === "font")
      return [(t === "prop" && row.kind === "color" ? [{ keys: ["ENTER"], label: "Pick" }]
               : t === "layout" && Look.LAYOUT_BY_KEY[row.key].kind === "columns" ? [{ keys: [], label: "Set by themes and agents" }]
               : [{ keys: ["←", "→"], label: "Change" }]).concat([{ keys: ["DEL"], label: "Theme's" }]),
              [{ keys: ["↑", "↓"], label: "Move" }].concat(back)]
    if (t === "resetPart") return [[{ keys: ["ENTER"], label: styleArmed === t ? "Again to reset" : "Reset" }], [{ keys: ["↑", "↓"], label: "Move" }].concat(back)]
    var first = t === "color" ? [{ keys: ["ENTER"], label: "Pick" }, { keys: ["DEL"], label: "Theme's" }]
              : t === "theme" ? [{ keys: ["←", "→"], label: "Change theme" }, { keys: ["DEL"], label: "Premiere" }]
              : t === "saveTheme" ? [{ keys: ["ENTER"], label: "Name it and save" }]
              : t === "image" ? (areaImages[(styleRows[styleCursor] || {}).key]
                                 ? [{ keys: ["ENTER"], label: "Pick" }, { keys: ["←", "→"], label: "Fit" }, { keys: ["[", "]"], label: "Fade" }, { keys: ["DEL"], label: "Off" }]
                                 : [{ keys: ["ENTER"], label: "Pick a picture" }].concat(imageOverrides[(styleRows[styleCursor] || {}).key] !== undefined ? [{ keys: ["DEL"], label: "Theme's" }] : []))
              : t === "bg" ? [{ keys: ["←", "→"], label: "Change" }, { keys: ["ENTER"], label: "Pick a picture" }]
              : t === "dim" ? [{ keys: ["←", "→"], label: "Less / more" }]
              : t === "lt" || t === "card" ? [{ keys: ["SPACE"], label: "On / off" }, { keys: ["←", "→"], label: "Seconds" }]
              : t === "undoReset" ? [{ keys: ["ENTER"], label: "Undo" }]
              : [{ keys: ["ENTER"], label: styleArmed === t ? "Again to reset" : "Reset" }]
    return [first, [{ keys: ["↑", "↓"], label: "Move" }].concat(back)]
  }

  // The Settings screen (,), TV style: its parts down the left (General,
  // Live TV, Library, About), the rows of the one you're on at the right,
  // each a switch, a choice, a way to a box, or something to do (a second
  // Enter does it). → goes into a part's rows, ← or Esc back out.
  readonly property var settingsParts: [
    { key: "general", label: "General", icon: "gear", about: "Home, the nav rail, the key hints, the phone remote, AI agents, and the guide's look." },
    { key: "tv", label: "Live TV", icon: "tv", about: "Channel logos, how lineups are planned, which channels show, and fetching the listings." },
    { key: "library", label: "Library", icon: "film", about: "My Videos, the movies your playlists brought in, Continue watching and My List." },
    { key: "recordings", label: "Recordings", icon: "record", about: "Recording channels to watch later: where recordings go, the space kept free, YouTube's quality, how many at once, starting early and ending late, and pause and rewind." },
    { key: "apps", label: "Apps", icon: "apps", about: "Apps from other people: Netflix, Hulu and more, each full screen, as on a TV. Off until you turn them on." },
    { key: "saver", label: "Screen saver", icon: "picture", about: "Pictures that fill the screen when nothing's playing and nobody's touched anything for a while, like a TV. The first press brings you back." },
    { key: "about", label: "About", icon: "info", about: "What this is, and where your settings and lists are kept." }
  ].concat(appsStore.developerShown || appsStore.developer   // hidden until you ask for it (Settings → About, OK 7 times), or while it's on
           ? [{ key: "developer", label: "Developer", icon: "pencil", about: "For people making apps: Developer mode, and installing an app you're building." }] : [])
  property int settingsPart: 0
  // Recordings' part open: its drives listed, and its place looked at
  onSettingsPartChanged: if ((settingsParts[settingsPart] || {}).key === "recordings") { dvr.listDrives(); dvr.checkPlace() }
  // the Developer part gone (switched off) while you're on it: back to Apps
  onSettingsPartsChanged: {
    if (settingsPart < settingsParts.length) return
    settingsPart = Math.max(0, settingsParts.findIndex(function(p) { return p.key === "apps" }))
    settingsCursor = 0
    settingsInRows = false
  }
  property bool settingsInRows: false    // in a part's rows, or on the parts

  // Each part's rows: { key, label, kind: switch|choice|opens|action|info, danger }
  readonly property var settingsGroups: {
    var library_ = [
      { key: "videos", label: "My Videos", kind: "switch" },
      { key: "videosFolder", label: "My Videos folder", kind: "opens" },
      { key: "videosScan", label: "Look for new videos now", kind: "action" },
      { key: "libraryInfo", label: "Your library", kind: "info" }
    ]
    var sources = {}
    var order = []
    for (var i = 0; i < library.items.length; i++) {
      var src = library.items[i].source || ""
      if (!(src in sources)) { sources[src] = 0; order.push(src) }
      sources[src]++
    }
    for (var o = 0; o < order.length; o++)
      library_.push({ key: "source", source: order[o], count: sources[order[o]], kind: "action", danger: true,
                      label: order[o] === "your guide" ? "Movies that were in your guide" : "Movies from " + (order[o] ? order[o].replace(/^https?:\/\/(www\.)?/, "").split(/[?#]/)[0].split("/").slice(-1)[0] || order[o] : "a playlist") })
    var apps_ = [{ key: "apps", label: "Apps", kind: "switch" }]
    if (appsStore.on) {
      apps_.push({ key: "getApps", label: "Get apps", kind: "opens" })
      apps_.push({ key: "appLooks", label: "How apps look", kind: "opens" })
      for (var a = 0; a < appsStore.installed.length; a++)
        apps_.push({ key: "app", id: appsStore.installed[a].id, label: appsStore.installed[a].name, kind: "switch", more: true })
      apps_.push({ key: "appUpdates", label: "Check for updates", kind: "action" })
      apps_.push({ key: "unknownSources", label: "Third-party apps", kind: "switch" })
      if (appsStore.unknownSources) apps_.push({ key: "signedAppFile", label: "Install a third-party app", kind: "opens" })
    }
    var rec_ = [{ key: "recOn", label: "Recordings", kind: "switch" }]
    if (dvr.settings.on) {
      rec_.push({ key: "recPlace", label: "Save recordings to", kind: "info" })
      if (!dvr.placeIsDefault) rec_.push({ key: "recDefault", label: "Use the Videos folder", kind: "action" })
      rec_.push({ key: "recFolder", label: "Choose a folder…", kind: "opens" })
      for (var dv = 0; dv < dvr.drives.length; dv++)
        rec_.push({ key: "recDrive", device: dvr.drives[dv].device, label: "Use " + (dvr.drives[dv].label || "the USB drive") + " (USB)", kind: "action" })
      rec_.push({ key: "recKeepFree", label: "Keep free", kind: "choice" },
                { key: "recQuality", label: "YouTube quality", kind: "choice" },
                { key: "recAtOnce", label: "Recordings at once", kind: "choice" },
                { key: "recPadding", label: "Start early, end late", kind: "choice" },
                { key: "recPause", label: "Pause and rewind", kind: "choice" },
                { key: "recAbout", label: "When recordings run", kind: "info" })
    }
    var developer_ = [{ key: "developer", label: "Developer mode", kind: "switch" }]
    if (appsStore.developer) developer_.push({ key: "appFile", label: "Install an unsigned app", kind: "opens" },
                                             { key: "resetAll", label: "Reset Uber TV", kind: "opens", danger: true })
    library_.push({ key: "clearHistory", label: "Clear Continue watching", kind: "action", danger: true })
    library_.push({ key: "clearList", label: "Empty My List", kind: "action", danger: true })
    return {
      general: [
        { key: "home", label: "Home screen", kind: "switch" },
        { key: "display", label: "Display mode", kind: "choice" },
        { key: "awake", label: "Keep the screen awake", kind: "choice" },
        { key: "shortcut", label: "Shortcut", kind: "choice" },
        { key: "barIcon", label: "Show in the top bar", kind: "switch" },
        { key: "rail", label: "Nav rail", kind: "opens" },
        { key: "keyHints", label: "Key hints", kind: "switch" },
        { key: "splash", label: "Splash screen", kind: "switch" },
        { key: "remote", label: "Phone remote", kind: "opens" },
        { key: "phones", label: "Paired phones", kind: "opens" },
        { key: "skill", label: "AI agent skill", kind: "switch" },
        { key: "skillSave", label: "Save the agent skill", kind: "action" },
        { key: "style", label: "Style and themes", kind: "opens" },
        { key: "clearSearches", label: "Clear recent searches", kind: "action", danger: true }
      ],
      tv: [
        { key: "logos", label: "Channel logos", kind: "switch" },
        { key: "lineup", label: "Lineups", kind: "choice" },
        { key: "listings", label: "Program listings (IPTV)", kind: "opens" },
        { key: "channelLock", label: "Channel lock", kind: "opens" },
        { key: "filter", label: "Categories and sources", kind: "opens" },
        { key: "refresh", label: "Refresh the listings now", kind: "action" },
        { key: "demo", label: "Load the demo channels", kind: "action" }
      ],
      library: library_,
      recordings: rec_,
      apps: apps_,
      developer: developer_,
      saver: [
        { key: "saverOn", label: "Screen saver", kind: "switch" },
        { key: "saverAfter", label: "Starts after", kind: "choice" },
        { key: "saverPictures", label: "Pictures", kind: "choice" },
        { key: "saverFolder", label: "Your folder", kind: "opens" },
        { key: "saverFolderPick", label: "Use another folder", kind: "opens" },
        { key: "saverEvery", label: "Change every", kind: "choice" },
        { key: "saverClock", label: "Clock", kind: "choice" },
        { key: "saverPreview", label: "Show it now", kind: "action" }
      ],
      about: [
        { key: "about", label: "Uber TV", kind: "info" },
        { key: "updateNotify", label: "Update notifications", kind: "switch" },
        { key: "updateCheck", label: "Check for updates", kind: "action" }
      ].concat(updatesItem.available ? [{ key: "updateAvailable", label: "Update now", kind: "opens" }] : []).concat([
        { key: "releaseNotes", label: "Release notes", kind: "opens" },
        { key: "files", label: "Your settings and lists", kind: "info" },
        { key: "devHow", label: "Developer mode", kind: "info" },
        { key: "backupSave", label: "Back up channels and settings", kind: "action" },
        { key: "backupRestore", label: "Restore a backup", kind: "opens" },
        { key: "contributors", label: "Contributors", kind: "opens" },
        { key: "credit", label: "@devsec_ai", icon: "xlogo", kind: "info" },
        { key: "railCredits", label: "Credits on the nav rail", kind: "switch" }
      ])
    }
  }
  readonly property var settingsRows: settingsGroups[(settingsParts[settingsPart] || settingsParts[0]).key] || []
  property string settingsArmed: ""      // a row waiting for its second Enter
  property string settingsFrom: "home"

  function openSettings(part) {
    var fresh = root.screen !== "settings"
    if (fresh) { root.settingsFrom = root.screen; root.settingsInRows = false }
    if (!root.vod && root.reception !== "off" && !root.pip && !root.watching) root.turnOff()
    root.screen = "settings"
    root.dialog = ""
    root.settingsArmed = ""
    var at = root.settingsParts.findIndex(function(p) { return p.key === part })
    if (at >= 0) { root.settingsPart = at; root.settingsCursor = 0; root.settingsInRows = true }
    if (root.settingsCursor >= root.settingsRows.length) root.settingsCursor = 0
    keys.forceActiveFocus()
  }

  function leaveSettings() {
    root.settingsArmed = ""
    if (root.settingsFrom === "apps" && appsStore.on) { root.railOpen = false; root.openApps(true); return }
    root.go(root.settingsFrom === "settings" ? "home" : root.settingsFrom === "library" ? root.libraryTab : root.settingsFrom === "guide" ? "tv" : "home")
  }

  // ↑↓ on the parts: the next part, its rows showing at the right
  function moveSettingsPart(d) {
    root.settingsPart = Math.max(0, Math.min(root.settingsParts.length - 1, root.settingsPart + Number(d)))
    root.settingsCursor = 0
    root.settingsArmed = ""
  }

  // → or Enter on a part goes into its rows; ← or Esc in them comes back
  function settingsInto() { root.settingsInRows = true; root.settingsCursor = 0; root.settingsArmed = "" }
  function settingsOut() { root.settingsInRows = false; root.settingsArmed = "" }

  function moveSettings(d) {
    root.settingsCursor = Math.max(0, Math.min(root.settingsRows.length - 1, root.settingsCursor + Number(d)))
    root.settingsArmed = ""
  }

  // ---- the nav rail ------------------------------------------------------

  // Down the left, a way to every part. ← at a screen's left edge opens it.
  // What's on it is yours (C on the rail, or Settings): its items in order,
  // each on or off. A part that's turned off (Home, My Videos) leaves it
  // until it's back on. Settings always stays.
  property bool railOpen: false
  property int railCursor: 0
  readonly property var railKinds: [{ key: "search", label: "Search", icon: "search" },
                                    { key: "home", label: "Home", icon: "home" }, { key: "tv", label: "Live TV", icon: "tv" },
                                    { key: "movies", label: "Movies & Series", icon: "film" }, { key: "ondemand", label: "On Demand", icon: "play" },
                                    { key: "videos", label: "My Videos", icon: "folder" }, { key: "recordings", label: "Recordings", icon: "record" },
                                    { key: "mylist", label: "My List", icon: "bookmark" },
                                    { key: "apps", label: "Apps", icon: "apps" }, { key: "settings", label: "Settings", icon: "gear" }]
  readonly property var defaultRailSetup: railKinds.map(function(k) { return { key: k.key, on: true } })
  property var railSetup: defaultRailSetup       // [{ key, on }], in order
  readonly property var railItems: railSetup.filter(function(it) { return (it.on || it.key === "settings") && railAvailable(it.key) })
                                            .map(function(it) { return railKind(it.key) })
  // At the rail's foot, always: a window or full screen, and turning the
  // guide off (as a TV's power button). The cursor goes on past Settings to them.
  readonly property var railSystem: (updatesItem.on && updatesItem.available ? [{ key: "update", label: "Update available: " + updatesItem.latest, icon: "update" }] : [])
                                     .concat([{ key: "display", label: windowed ? "Full screen" : "Window", icon: windowed ? "fullscreen" : "window" },
                                              { key: "off", label: "Turn off", icon: "power" }])
  property bool railEditing: false               // Customize the rail
  property int railEditCursor: 0
  property string railEditFrom: "rail"

  function railKind(key) {
    for (var i = 0; i < root.railKinds.length; i++) if (root.railKinds[i].key === key) return root.railKinds[i]
    return null
  }

  // Whether a part is turned on (so it can be on the rail), and if not, why
  function railAvailable(key) { return key === "home" ? root.homeEnabled : key === "videos" ? videos.enabled : key === "apps" ? appsStore.on : key === "recordings" ? root.libraryTabShown("recordings") : true }
  function railOffBecause(key) { return key === "home" ? "Home screen is off" : key === "videos" ? "My Videos is off" : key === "apps" ? "Apps are off" : key === "recordings" ? "Recordings are off" : "" }

  // The rail's items from settings or a command, checked: known ones once
  // each, Settings on; parts the list doesn't have yet join where they'd come
  function checkedRailSetup(given) {
    var out = []
    var seen = {}
    var list = Array.isArray(given) ? given : []
    for (var i = 0; i < list.length; i++) {
      var g = typeof list[i] === "string" ? { key: list[i], on: true } : list[i]
      if (!g || typeof g.key !== "string" || !root.railKind(g.key) || seen[g.key]) continue
      seen[g.key] = true
      out.push({ key: g.key, on: g.key === "settings" || g.on !== false })
    }
    for (var k = 0; k < root.railKinds.length; k++) {
      var key = root.railKinds[k].key
      if (seen[key]) continue
      var at = 0
      for (var b = k - 1; b >= 0; b--) {
        var before = out.findIndex(function(x) { return x.key === root.railKinds[b].key })
        if (before >= 0) { at = before + 1; break }
      }
      out.splice(at, 0, { key: key, on: true })
    }
    return out
  }

  // ---- customizing the rail (C on it, or Settings) ----
  readonly property var railModes: ["always", "focus", "none"]
  function railModeLabel(mode) {
    return { always: "Always", focus: "When you go to it (←)", none: "Never" }[mode] || mode
  }

  readonly property var railPanelRows: {
    var rows = [{ type: "header", label: "SHOW THE RAIL" }, { type: "railMode" }, { type: "header", label: "ITS ITEMS, IN ORDER" }]
    for (var i = 0; i < railSetup.length; i++) rows.push({ type: "railItem", index: i })
    rows.push({ type: "header", label: "" })
    rows.push({ type: "railReset" })
    return rows
  }

  function openRailPanel(from) {
    root.railEditFrom = from === "settings" ? "settings" : "rail"
    var key = root.railOpen ? (root.railItems[root.railCursor] || {}).key : ""
    root.railOpen = false
    root.railEditing = true
    var rows = root.railPanelRows
    root.railEditCursor = 3
    for (var i = 0; i < rows.length; i++) if (rows[i].type === "railItem" && root.railSetup[rows[i].index].key === key) root.railEditCursor = i
    keys.forceActiveFocus()
  }

  function closeRailPanel() {
    root.railEditing = false
    root.saveSettings()
    if (root.railEditFrom === "rail" && root.layout.rail !== "none") root.openRail()
  }

  function moveRailPanel(d) {
    var rows = root.railPanelRows
    var n = rows.length
    var c = root.railEditCursor
    do { c = (c + d + n) % n } while (rows[c].type === "header")
    root.railEditCursor = c
  }

  // Space, Enter and ← → in the panel
  function railPanelAct(d) {
    var r = root.railPanelRows[root.railEditCursor]
    if (!r) return
    if (r.type === "railMode") {
      var modes = root.railModes
      root.setLayoutOverride("rail", modes[(modes.indexOf(root.layout.rail) + (d || 1) + modes.length) % modes.length])
    } else if (r.type === "railItem") {
      var list = root.railSetup.slice()
      var it = list[r.index]
      if (it.key === "settings") return
      list[r.index] = { key: it.key, on: !it.on }
      root.railSetup = list
    } else if (r.type === "railReset") {
      root.railSetup = root.defaultRailSetup
      root.setLayoutOverride("rail", undefined)
    }
    root.saveSettings()
  }

  // Shift ↑↓ on an item: moves it
  function moveRailItem(d) {
    var r = root.railPanelRows[root.railEditCursor]
    if (!r || r.type !== "railItem") return
    var to = r.index + d
    if (to < 0 || to >= root.railSetup.length) return
    var list = root.railSetup.slice()
    var it = list.splice(r.index, 1)[0]
    list.splice(to, 0, it)
    root.railSetup = list
    root.railEditCursor += d
    root.saveSettings()
  }

  readonly property string railCurrent: screen === "home" ? "home" : screen === "guide" ? "tv" : screen === "library" ? libraryTab : screen === "settings" ? "settings" : screen === "search" ? "search" : screen === "apps" || screen === "app" ? "apps" : ""
  // what the screens leave free at the left for the thin rail
  readonly property real railSpace: layout.rail === "always" ? Math.round(u * layout.railWidth) : 0

  function openRail() {
    appViewItem.userActs()
    if (root.layout.rail === "none") return false
    var at = 0
    for (var i = 0; i < root.railItems.length; i++) if (root.railItems[i].key === root.railCurrent) at = i
    root.railCursor = at
    root.railOpen = true
    keys.forceActiveFocus()
    return true
  }

  function closeRail() { root.railOpen = false }

  function moveRail(d) { root.railCursor = Math.max(0, Math.min(root.railItems.length + root.railSystem.length - 1, root.railCursor + d)) }

  function railGo(i) {
    var at = i === undefined ? root.railCursor : i
    root.railOpen = false
    if (at >= root.railItems.length) {
      var sys = root.railSystem[at - root.railItems.length]
      if (sys && sys.key === "display") root.toggleDisplay()
      else if (sys && sys.key === "off") root.dismiss()
      else if (sys && sys.key === "update") root.openUpdateSetting()
      return
    }
    var it = root.railItems[at]
    if (it) root.go(it.key)
  }

  // A link in the rail's credits, clicked: the handle's X page ("x") or the
  // website ("web"), in your browser. Full screen, the guide goes so the
  // browser shows (as an app's window does); a window stays where it is.
  function openCredit(which) {
    var url = which === "web" ? "https://devsecai.sh" : "https://x.com/devsec_ai"
    root.railOpen = false
    Quickshell.execDetached(["/usr/share/omarchy/bin/omarchy-launch-browser", url])
    if (!root.windowed) root.dismiss()
  }

  // Disable, in the rail's credits: Settings → About, on their switch
  function openCreditSetting() {
    root.railOpen = false
    root.openSettings("about")
    var at = root.settingsRows.findIndex(function(r) { return r.key === "railCredits" })
    if (at >= 0) root.settingsCursor = at
  }

  // The update in the rail, clicked: Settings → About, on it
  function openUpdateSetting() {
    root.railOpen = false
    root.openSettings("about")
    var at = root.settingsRows.findIndex(function(r) { return r.key === "updateAvailable" })
    if (at >= 0) root.settingsCursor = at
  }

  // Contributors (Settings → About): the list, and a GitHub page from it in
  // your browser (full screen, the guide goes, as for the credits)
  function openContributors() {
    root.contributorPick = 0
    root.dialog = "contributors"
    keys.forceActiveFocus()
  }

  function openContributor(i) {
    var c = root.contributors[i]
    if (!c) return
    Quickshell.execDetached(["/usr/share/omarchy/bin/omarchy-launch-browser", "https://github.com/" + c.handle])
    if (!root.windowed) root.dismiss()
  }

  // Release notes (Settings → About): what's new in the update, or in this version
  function openReleaseNotes() {
    updatesItem.loadNotes()
    root.dialog = "notes"
    keys.forceActiveFocus()
  }

  // To a part: search, home, tv, movies, ondemand, videos, mylist, apps or settings
  function go(key) {
    root.railOpen = false
    if (key === "search") root.openSearch()
    else if (key === "apps") root.openApps()
    else if (key === "home") root.openHome()
    else if (key === "tv") root.closeLibrary()
    else if (key === "movies" || key === "ondemand" || key === "videos" || key === "recordings" || key === "mylist") root.openLibrary(key)
    else if (key === "settings") root.openSettings()
  }

  // Whether the cursor is at the left edge, where ← opens the rail
  function homeAtLeft() {
    var sec = root.homeView[root.homeRow]
    return !sec || (root.homeCols[sec.key] || 0) === 0
  }
  function libAtLeft() {
    var row = root.libraryRows[root.libRow]
    return !row || (root.libCols[row.key] || 0) === 0
  }
  function guideAtLeft() {
    var s = root.selected
    return root.slotOffset === 0 && (!s || s.start <= root.windowStart)
  }

  // A switch row: on or not
  function settingOn(key, row) {
    if (key === "apps") return appsStore.on
    if (key === "developer") return appsStore.developer
    if (key === "unknownSources") return appsStore.unknownSources
    if (key === "barIcon") return root.barIcon
    if (key === "app") { var a = appsStore.record((row || {}).id); return !!a && a.enabled && !a.broken && !a.revoked }
    if (key === "logos") return root.showLogos
    if (key === "keyHints") return root.showKeyHints
    if (key === "splash") return root.splashOn
    if (key === "railCredits") return root.railCredits
    if (key === "updateNotify") return updatesItem.on
    if (key === "home") return root.homeEnabled
    if (key === "videos") return videos.enabled
    if (key === "skill") return root.agentSkill
    if (key === "saverOn") return screenSaverItem.settings.on
    if (key === "recOn") return dvr.settings.on
    return false
  }

  // What a row says at its right (a switch shows itself instead)
  function settingValue(key, row) {
    var plural = function(n, one, many) { return n + " " + (n === 1 ? one : many) }
    if (key === "display") return root.windowed ? "Window" : "Full screen"
    if (key === "awake") return AwakeRules.label(root.awake)
    if (key === "saverAfter") return SaverRules.afterLabel(screenSaverItem.settings.after)
    if (key === "saverPictures") return SaverRules.picturesLabel(screenSaverItem.settings.pictures)
    if (key === "saverFolder") return root.saverNote ? "Couldn't open it" : !screenSaverItem.listed ? "" : screenSaverItem.folderMissing ? "Not made yet"
                                     : !screenSaverItem.folderPictures.length ? "Empty" : plural(screenSaverItem.folderPictures.length, "picture", "pictures")
    if (key === "saverEvery") return SaverRules.everyLabel(screenSaverItem.settings.every)
    if (key === "saverClock") return SaverRules.clockLabel(screenSaverItem.settings.clock)
    if (key === "shortcut") return !root.shortcut ? "None" : Shortcut.label(root.shortcut) + (root.shortcutStatus === "taken" ? " (taken)" : root.shortcutStatus === "failed" ? " (not set)" : "")
    if (key === "rail") return (root.layout.rail === "none" ? "Never shown" : root.layout.rail === "focus" ? "When you go to it" : "Always") + " · " + plural(root.railItems.length, "item", "items")
    if (key === "videosFolder") return root.shownPath(videos.usedFolder)
    if (key === "videosScan") return !videos.enabled ? "My Videos is off" : videos.scanning ? "Looking…" : videos.missing ? "No such folder" : plural(videos.items.length, "video", "videos")
    if (key === "lineup") return root.lineupMode === "latest" ? "Latest" : "Daily"
    if (key === "channelLock") return !channelLockItem.loaded ? (channelLockItem.failed ? "Can't be read" : "Checking…") : !channelLockItem.set ? "No passcode yet" : channelLockItem.on ? "On · " + plural(channelLockItem.entries.length, "channel", "channels") : "Off"
    if (key === "listings") return !listings.sources.length ? "None yet" : listings.busy ? "Fetching…"
                                 : listings.matched + " of " + root.iptvCount + " channels"
    if (key === "style") return root.currentTheme.name
    if (key === "filter") return root.hasIptv && root.shownSource !== "both" ? root.sourceName(root.shownSource) : root.filtered ? "Some categories" : "Everything"
    if (key === "phones") return !root.remoteEnabled ? "Phone remote is off" : !root.remoteDevices.length ? "None" : plural(root.remoteDevices.length, "phone", "phones")
    if (key === "remote") return root.remoteEnabled ? "On" + (root.remoteDevices.length ? " · " + plural(root.remoteDevices.length, "phone", "phones") : "") : "Off"
    if (key === "refresh") return root.fetchedAt ? "Listings " + Math.max(0, Math.round((root.now - root.fetchedAt) / 60)) + " min old" : ""
    if (key === "libraryInfo") return plural(library.items.length, "movie", "movies") + " · " + plural(library.genres.length, "genre", "genres")
    if (key === "source") return root.settingsArmed === "source:" + (row || {}).source ? "Enter again to remove" : (row ? row.count : 0) + " · Remove"
    if (key === "clearHistory") return root.settingsArmed === "clearHistory" ? "Enter again to clear" : library.unfinished("").length + " started"
    if (key === "clearList") return root.settingsArmed === "clearList" ? "Enter again to empty" : library.myList.length + " saved"
    if (key === "clearSearches") return root.settingsArmed === "clearSearches" ? "Enter again to clear" : root.recentSearches.length + " kept"
    if (key === "getApps") return appsStore.fetching && !appsStore.catalog && !appsStore.offered.length ? "Getting the catalog…" : appsStore.offered.length ? plural(appsStore.offered.length, "app", "apps") : appsStore.catalogError ? "Couldn't get it" : ""
    if (key === "app") {
      var ap = appsStore.record((row || {}).id)
      return !ap ? "" : ap.revoked ? (ap.from === "appFile" ? "Withdrawn by its developer" : "Pulled by the catalog") : ap.broken ? "Turned off: changed" : ap.update ? "Update available" : ap.from === "file" ? "From a file" : ap.from === "appFile" ? "From a signed app file" : ""
    }
    if (key === "appUpdates") return appsStore.fetching || appsStore.checkingAppFiles ? "Looking…" : appsStore.updateQueue.length ? "Updating…" : appsStore.updates.length ? plural(appsStore.updates.length, "update", "updates") + " available"
                                     : appsStore.catalogError || appsStore.appFileError ? "Couldn't look" : appsStore.checked ? "Looked " + root.agoLabel(appsStore.checked) : ""
    if (key === "about") return "Version " + ((root.manifest && root.manifest.version) || "1.0.0") + (updatesItem.available ? "  ·  " + updatesItem.latest + " available" : "") + (devPresses.note ? "  ·  " + devPresses.note : "")
    if (key === "updateNotify" || key === "updateCheck" || key === "updateAvailable") return updatesItem.value(key)
    if (key === "backupSave") return backupsItem.value(key)
    if (key === "files") return root.filesProblem ? "Files not read" : "~/.config/om-pg"
    if (key === "devHow") return appsStore.developerShown || appsStore.developer ? "In Settings → Developer" : "Press Enter on Uber TV 7 times"
    if (key === "credit") return "W: devsecai.sh"
    if (key === "contributors") return root.contributors.length ? plural(root.contributors.length, "person", "people") : "None yet"
    if (key === "recOn") return root.settingsArmed === "recOff" ? "Enter again to " + root.recOffWhat() : ""
    if (key === "recPlace") return dvr.placeLabel + (!dvr.placeInfo ? "" : dvr.placeInfo.problem === "drive" ? " · isn't there" : dvr.placeInfo.free ? " · " + root.sizeLabel(dvr.placeInfo.free) + " free" : "")
    if (key === "recDrive") {
      var dr = dvr.drives.filter(function(x) { return x.device === (row || {}).device })[0]
      var using = dr && dvr.settings.place && dvr.settings.place.removable && dr.mount && dvr.settings.place.mount === dr.mount
      return !dr ? "" : using ? "In use" : dr.mount ? root.sizeLabel(dr.free) + " free" : "Not opened yet"
    }
    if (key === "recKeepFree") return dvr.settings.keepFree ? dvr.settings.keepFree + " GB" : "Auto (" + dvr.keepFreeGB + " GB)"
    if (key === "recQuality") return dvr.settings.quality ? dvr.settings.quality + "p" : "Auto (" + dvr.quality + "p)"
    if (key === "recAtOnce") return String(dvr.settings.atOnce)
    if (key === "recPadding") return DvrRules.paddingLabel(dvr.settings.padding)
    if (key === "recPause") return Ts.minutesLabel(dvr.settings.timeshift)
    return ""
  }

  readonly property string settingsNote: {
    if (!settingsInRows) return (settingsParts[settingsPart] || {}).about || ""
    var key = (settingsRows[settingsCursor] || {}).key
    if (key === "logos") return "Each channel's logo in the guide. They're fetched a few at a time and kept, so the guide stays fast."
    if (key === "keyHints") return "The keys along the bottom of the guide. K turns them on or off anywhere in the guide."
    if (key === "splash") return "An old TV warming up, with the Uber TV logo, each time Uber TV turns on. About 9 seconds; any key skips it."
    if (key === "home") return "On: the guide opens on Home (continue watching, what's on, your library), and Esc in the guide goes back to it. C on Home customizes it. Off: the guide opens on the program guide, as before."
    if (key === "shortcut") return "Opens or closes the guide from anywhere. It's registered with Hyprland while the guide runs (your Hyprland config isn't changed) and taken out when the guide is turned off. Enter picks the next one; None for no shortcut."
                                   + (root.shortcutStatus === "taken" ? " " + Shortcut.label(root.shortcut) + " is already used by " + root.shortcutTakenBy + ", so it's left alone: pick another." : "")
                                   + (root.shortcutStatus === "failed" ? " Hyprland didn't take it: " + root.shortcutProblem : "")
    if (key === "barIcon") return "The TV in the Omarchy bar: click it to open or close the guide. Off, it takes no space, and the guide stays on (Omarchy keeps a plugin with a bar icon on while its icon is in the bar)."
    if (key === "display") return "Full screen covers the whole screen, the Omarchy bar too. Window fills your desktop under the Omarchy bar, as an ordinary window: it stays on its desktop while you work on another, and its key brings it back to you. W switches between them, anywhere."
    if (key === "awake") return "Omarchy's screen saver and lock wait while it's kept awake. Your Omarchy settings stay as they are. "
                                + (root.awake === "open" ? "While Uber TV is on: whenever it's on your screen, playing or not, so leaving it open keeps your computer unlocked."
                                   : root.awake === "playing" ? "While a video plays: a movie, a channel or an app's video. Paused, Omarchy takes over again."
                                   : "Off: Omarchy's screen saver and lock come as usual, even during a movie.")
    if (key === "saverOn") return "Pictures fill the screen when nothing's playing and nobody's touched anything for a while. Any press brings you back, with no password: while it's on, your computer doesn't lock while Uber TV is on screen."
    if (key === "saverAfter") return "How long with nothing playing and no key, mouse or phone press before the pictures come. Enter picks the next one."
    if (key === "saverPictures") return "Omarchy's backgrounds (its themes', and any you've added) and the pictures in your folder: both, or one of them. An empty folder shows Omarchy's."
    if (key === "saverFolder") return (root.saverNote ? "It couldn't be opened: " + root.saverNote + ". " : "") + root.shownPath(screenSaverItem.folder) + ": drop pictures here (PNG, JPEG or WebP, and folders of them). Enter opens it in your file manager, made the first time."
    if (key === "saverFolderPick") return "Show the pictures in another folder instead (and the folders in it)."
    if (key === "saverEvery") return "How long each picture stays before the next one fades in. Enter picks the next one."
    if (key === "saverClock") return "Where the clock goes, over the pictures, or off. It moves a little now and then, so nothing burns in."
    if (key === "saverPreview") return "Shows the screen saver now. Any key, mouse move or phone press ends it."
    if (key === "rail") return "The nav rail down the left: whether it shows always, only when you go to it (← at a screen's left edge), or never, and which parts are on it, in what order. A part that's turned off (Home, My Videos) leaves the rail until it's back on. Also C, on the open rail."
    if (key === "videos") return "Your own videos in the library and on Home: screen recordings, downloads, anything in your videos folder (and the folders in it), each with its length and a picture from it. Nothing is copied or uploaded. Off: My Videos leaves the library, Home and the rail."
    if (key === "videosFolder") return "The folder My Videos shows, with the folders in it (each its own row). Enter picks another; your Videos folder is " + root.shownPath(videos.defaultFolder) + "."
    if (key === "videosScan") return "The guide looks for new videos when it opens and when you open My Videos. This looks right now. Pictures and lengths are kept in ~/.cache/om-pg, so each video is looked at once."
    if (key === "listings") return "What's on your IPTV channels, show by show: program listings (XMLTV) from a link or a file you add, or that a playlist brings. They're fetched about twice a day (and with R), and matched to your channels by their ids and names; a channel without listings stays one LIVE block. "
                                 + (listings.sources.length ? listings.matched + " of your " + root.iptvCount + " IPTV channels have listings." : "None added yet.")
    if (key === "channelLock") return "A passcode you set once, and the channels it protects: watching one asks for it, on the screen or on your phone. Only a scrambled form of it is kept, in a file only you can read."
    if (key === "lineup") return "DAILY: each channel's lineup is planned at 4 AM and kept all day, like real TV. LATEST: it follows every refresh. Takes effect at the next refresh (R)."
    if (key === "skill") return "Lets AI agents (Claude Code, Codex and others) make themes, change colors, add M3U playlists and organize your channels when you ask them. On, the guide links its skill into the agent skill folders you have ("
                                + root.agentFolders.join(", ") + "); off takes those links out. The phone remote stays yours: agents can't turn it on."
                                + (root.agentSkill ? (root.skillLinks.length ? " Linked in " + root.skillLinks.length + (root.skillLinks.length === 1 ? " folder." : " folders.") : " No agent skill folders found.") : "")
    if (key === "demo") return "Adds Uber TV's demo lineup: " + root.demoLineup.channels.length + " YouTube channels in " + root.demoLineup.categories + " categories. Channels you already have are skipped, and nothing is removed."
                               + (root.demoSaid ? " " + root.demoSaid : "")
    if (key === "skillSave") return "Saves a copy of the agent skill as one file in your Downloads folder, to give to the AI assistant you use. Assistants that run commands on this computer can use it as is; a web chat can read it and tell you what to run."
                                    + (root.skillSaved ? " Saved to " + root.skillSaved + "." : root.skillSaveFailed ? " Couldn't save the agent skill." : "")
    if (key === "style") return "Themes, colors, a background picture, the channel banner and the channel card. Also S, in the guide."
    if (key === "filter") return root.hasCategories || root.hasIptv ? "Which categories show, and YouTube, IPTV or both. Also F, in the guide." : "Once your channels have categories (or there are IPTV channels), choose which show here."
    if (key === "phones") return "The phones paired as remotes, with when each was paired and last used. Pick one and press Enter twice to unpair it: it needs a new code to pair again. A phone can also unpair itself (UNPAIR on its remote page)."
    if (key === "remote") return "Your phone as a remote, on the same network: turn it on, pair a phone (a QR code, or a code to type), see the paired phones. Also T, on Home and in the guide."
    if (key === "refresh") return "Fetches every channel's listings again and plans today's lineups anew. Also R, in the guide."
    if (key === "libraryInfo") return "Movies and series from your playlists: a playlist's video files come here when you add it (A), its live channels go in the guide. V opens the library."
    if (key === "source") return "Takes the movies that playlist brought in out of the library (and off My List). The playlist's live channels stay in the guide. Press Enter twice."
    if (key === "clearHistory") return "Forgets where you stopped in every movie and video: Continue watching empties, and they start from the beginning. Press Enter twice."
    if (key === "clearList") return "Takes everything off My List. The movies and videos themselves stay. Press Enter twice."
    if (key === "clearSearches") return "Search (/) keeps your last few searches, to pick again. This forgets them. Press Enter twice."
    if (key === "about") return "A unified media center for Omarchy: YouTube, IPTV, EPG, On Demand Videos and Apps. Plugin marcho78.om-pg."
    if (key === "contributors") return "Everyone who's helped build Uber TV, and what they did. Enter opens the list."
    if (key === "devHow") return "For testing apps you're building. Press Enter or click the Uber TV row 7 times, then turn it on in Settings → Developer. It needs apps on."
    if (key === "updateNotify" || key === "updateCheck" || key === "updateAvailable") return updatesItem.note(key)
    if (key === "backupSave" || key === "backupRestore" || key === "resetAll") return backupsItem.note(key)
    var said = appsStore.status ? " " + appsStore.status : ""
    if (key === "apps") return (appsStore.on ? "Apps are on. Off stops every app at once; they stay installed, off." : "Apps bring services like Netflix and Hulu into the guide, each opening full screen. Turning them on asks first.")
                               + " They come from the Uber TV catalog, checked and signed, and you see what each asks for before it's installed. Agents can't turn apps on or install them." + said
    if (key === "appLooks") return "How every app's screen looks: its look, the top, the background, the details page, titles and card size. Left to the theme, each shows what the theme gives. One app's own choices (C on its screen) go over these."
    if (key === "getApps") return "The Uber TV catalog: apps checked and signed with its key. Pick one to see who made it and what it asks for, then install it." + (appsStore.catalogError ? " Last time: " + appsStore.catalogError + "." : "") + said
    if (key === "app") {
      var an = appsStore.record((settingsRows[settingsCursor] || {}).id)
      if (!an) return ""
      return (an.revoked ? "Turned off: " + (an.from === "appFile" ? "its developer withdrew it. " : "the catalog pulled it. ") + an.revoked + " "
            : an.broken ? "Turned off: " + an.broken.charAt(0).toLowerCase() + an.broken.slice(1) + "." + (an.update ? " Update it in its details. " : " Remove it, and install it again. ")
            : an.update ? "Version " + an.update.version + " is waiting: " + (!an.update.asks.length ? "it asks for nothing new. "
                                                                   : "it also asks to " + an.update.asks.map(function(x) { return x.charAt(0).toLowerCase() + x.slice(1) }).join(", ") + ". ")
            : an.from === "file" && !appsStore.developer ? "From a file: it opens only while Developer mode is on. "
            : !appsStore.checkedIds[an.id] && appsStore.on ? "Being checked… "
            : "") + (an.description ? an.description + " " : "") + "By " + an.author + " · version " + an.version + (an.from === "file" ? " · from a file" : an.from === "appFile" ? " · from a signed app file" : "")
            + ". Space turns it on or off; Enter shows what it's allowed, and Remove."
    }
    if (key === "appUpdates") return (appsStore.updates.length ? "Enter shows the update available for " + appsStore.updates[0].name + ": look over exactly what will be fetched, then Agree. "
                                                               : "Looks for new versions now (the guide also looks about twice a day). ") + "Catalog updates that ask for nothing new install by themselves. Signed app-file updates always wait for your agreement; a withdrawn version turns off and says why." + said
    if (key === "developer") return "For testing apps you're building. Unsigned apps get no updates and open only while Developer mode is on. Turning it on asks for your computer's password."
    if (key === "unknownSources") return "Install signed apps from other developers. You see who made each one before installing it, and it gets updates only from that developer. Turning it on asks for your computer's password."
    if (key === "signedAppFile") return "Pick a signed .tvapp in your home folder. Its developer key and everything it asks for are shown before Install asks for the computer's password. Picking the file contacts nothing." + said
    if (key === "appFile") return "A package (.tar.gz) or an app's folder (pick its app.json). It's checked the same way as the catalog's, and you see what it asks for before it's installed." + said
    if (key === "files") return (root.filesProblem ? root.filesProblem + " " : "") + "Your channels (channels.json), settings (settings.json), library (library.json), where you stopped (history.json) and themes (themes/) are kept in ~/.config/om-pg, readable by you. My Videos' pictures are in ~/.cache/om-pg."
    var recSaid = dvr.said ? " " + dvr.said : ""
    if (key === "recOn") return "Record what's on to watch later: I or Space while watching (▲ on your phone), then Record. Each recording goes on with Uber TV closed while you're logged in. Off takes Record away; your recordings stay, and so does the Recordings tab while there are some."
    if (key === "recPlace") return "Recordings are saved in " + root.shownPath(dvr.placeInfo && dvr.placeInfo.path ? dvr.placeInfo.path : (dvr.settings.place && dvr.settings.place.path) || dvr.defaultFolder + "/Uber TV Recordings")
                                   + ". A drive that isn't plugged in is never swapped for this computer's own disk: the recording doesn't start, and you're told why." + recSaid
    if (key === "recDefault") return "Save recordings in your Videos folder again (" + root.shownPath(dvr.defaultFolder) + "/Uber TV Recordings)." + recSaid
    if (key === "recFolder") return "Pick a folder of yours, or one on another disk. Hidden and system folders, Uber TV's own and temporary ones can't hold recordings." + recSaid
    if (key === "recDrive") return "Save recordings on this USB drive, in an Uber TV Recordings folder; one that isn't opened yet is opened first (no password). FAT and exFAT drives can't keep files private." + recSaid
    if (key === "recKeepFree") return "A recording stops before the drive gets fuller than this; what's recorded is kept. Auto keeps 8 GB free on a small system disk (under 64 GB), 5 GB anywhere else. Enter picks the next one."
    if (key === "recQuality") return "The size YouTube recordings are saved at; IPTV channels record as they come. About 3 GB an hour at 1080p, 1 to 2 at 720p. Auto: 720p on a small system disk, 1080p anywhere else. Enter picks the next one."
    if (key === "recAtOnce") return "How many may record at the same time (1 to 4). Each is another stream (4 to 8 Mbps at 1080p) and about 3 GB an hour on the drive: on a slow connection or a small computer, keep it low. One past it doesn't start; a scheduled one past it is a Conflict. Lowering it doesn't stop one that's recording. Enter picks the next one."
    if (key === "recPadding") return "With listings, a recording starts this much early and ends this much late, so a show that runs over isn't cut off. Enter picks the next one."
    if (key === "recPause") return "Pause, go back and catch up while you watch live TV. Keeps the last 5 or 30 minutes on the recordings drive, writing the whole time you watch."
    if (key === "recAbout") return "Recordings run while you're logged in, whether Uber TV is open or not; not at the login screen, or after you log out. Up to " + dvr.settings.atOnce + " at once (Recordings at once). The files aren't encrypted: the channel lock is Uber TV's, not the files'."
    return ""
  }

  function shownPath(path) {
    var home = Quickshell.env("HOME")
    var p = String(path)
    return p === home ? "~" : p.indexOf(home + "/") === 0 ? "~" + p.slice(home.length) : p
  }

  // The screen saver's settings, changed (checked by Saver.js) and saved;
  // its pictures are listed again when it's turned on or its folder changes
  function setSaver(changes) {
    var before = screenSaverItem.settings
    var s = Object.assign({}, before)
    for (var k in changes) s[k] = changes[k]
    screenSaverItem.settings = SaverRules.checked(s)
    root.saveSettings()
    var now = screenSaverItem.settings
    if (now.folder !== before.folder) root.saverNote = ""
    if ((now.on && !before.on) || now.folder !== before.folder) screenSaverItem.list()
  }

  // Your screen saver folder, made the first time and opened in your file
  // manager (full screen, the guide goes, or it would cover it)
  property string saverNote: ""
  function openSaverFolder() {
    screenSaverItem.openFolder(function(problem) {
      root.saverNote = problem
      if (!problem && !root.windowed) root.dismiss()
    })
  }

  // My Videos on or off, and its folder ("" keeps it)
  function setVideos(on, folder) {
    if (folder) videos.folder = folder === videos.defaultFolder ? "" : folder
    videos.enabled = on
    if (!on && root.libraryTab === "videos") root.libraryTab = "movies"
    root.saveSettings()
    if (on) { videos.items = []; videos.byId = ({}); videos.scan() }
  }

  readonly property var agentFolders: ["~/.claude/skills", "~/.codex/skills", "~/.agents/skills", "~/.hermes/skills", "~/.pi/agent/skills"]

  // by: byUser from the keys, the mouse or your phone (what only you can
  // do: apps, Developer mode, an app's switch, the phone remote, keeping
  // the screen awake); space: Space was pressed, which flips an app's switch
  // instead of opening it
  function changeSetting(d, by, space) {
    var row = root.settingsRows[root.settingsCursor]
    if (row && row.key === "about") return root.versionPressed(by)
    if (!row || row.kind === "info") return
    var you = by === root.byUser
    if (row.key === "app") {
      if (!you) return "only the user, at the screen"
      if (space === true) appsStore.setEnabled(row.id, !root.settingOn("app", row))
      else root.openAppInfo(row.id, by)
      return
    }
    if (row.key === "appUpdates") {
      appsStore.status = ""
      // one waiting for you: its details, where Update is (looking again wouldn't install it)
      if (you && appsStore.updates.length && !appsStore.fetching && !appsStore.updateQueue.length) { root.openAppInfo(appsStore.updates[0].id, by); return }
      appsStore.checkUpdates(true)
      return
    }
    if (row.kind === "action") {
      var armKey = row.key === "source" ? "source:" + row.source : row.key
      if (row.key === "refresh") { root.refresh(true); return }
      if (row.key === "saverPreview") { screenSaverItem.show(); return }
      if (row.key === "videosScan") { videos.scan(); return }
      if (row.key === "updateCheck") { updatesItem.check(false); return }
      if (row.key === "backupSave") { backupsItem.save(by); return }
      if (row.key === "skillSave") return root.saveSkill(by)
      if (row.key === "recDefault") { dvr.useDefault(); return }
      if (row.key === "recDrive") { dvr.useDrive(row.device); return }
      if (root.settingsArmed !== armKey) { root.settingsArmed = armKey; return }
      root.settingsArmed = ""
      if (row.key === "source") library.remove(library.items.filter(function(it) { return (it.source || "") === row.source }).map(function(it) { return it.id }))
      else if (row.key === "clearHistory") library.forgetAll()
      else if (row.key === "clearList") library.emptyList()
      else if (row.key === "clearSearches") { root.recentSearches = []; root.saveSettings() }
      else if (row.key === "demo") root.loadDemoChannels()
      root.settingsCursor = Math.min(root.settingsCursor, root.settingsRows.length - 1)
      return
    }
    if (row.kind === "opens") {
      if (d < 0) return
      if (row.key === "style") root.openStyle()
      else if (row.key === "filter") root.openFilter()
      else if (row.key === "remote" || row.key === "phones") root.openRemote(by)
      else if (row.key === "rail") root.openRailPanel("settings")
      else if (row.key === "listings") root.openListings()
      else if (row.key === "channelLock") { if (you) channelLockItem.openSettings() }
      else if (row.key === "videosFolder") root.openPicker(false, "videos", true)
      else if (row.key === "saverFolderPick") root.openPicker(false, "saver", true)
      else if (row.key === "recFolder") root.openPicker(false, "recordings", true)
      else if (row.key === "saverFolder") root.openSaverFolder()
      else if (row.key === "getApps") root.openCatalog(by)
      else if (row.key === "appLooks") appPanelItem.openAll(by)
      else if (row.key === "signedAppFile") { if (you) root.openPicker(false, "signedApps", false, false, true) }
      else if (row.key === "appFile") { if (you) root.openPicker(false, "apps", false, true) }
      else if (row.key === "releaseNotes") root.openReleaseNotes()
      else if (row.key === "updateAvailable") { if (you) updatesItem.updateNow() }
      else if (row.key === "contributors") root.openContributors()
      else if (row.key === "backupRestore") { if (you) backupsItem.openRestore() }
      else if (row.key === "resetAll") { if (you) backupsItem.openReset() }
      return
    }
    if (row.key === "logos") root.setLogos(!root.showLogos)
    else if (row.key === "keyHints") root.setKeyHints(!root.showKeyHints)
    else if (row.key === "splash") { root.splashOn = !root.splashOn; root.saveSettings() }
    else if (row.key === "railCredits") { root.railCredits = !root.railCredits; root.saveSettings() }
    else if (row.key === "updateNotify") updatesItem.setOn(!updatesItem.on)
    else if (row.key === "home") { root.homeEnabled = !root.homeEnabled; root.saveSettings() }
    else if (row.key === "display") root.toggleDisplay()
    else if (row.key === "awake") { if (!you) return "only the user, at the screen"; root.awake = AwakeRules.next(root.awake); root.saveSettings() }
    else if (row.key === "saverOn") { if (!you) return "only the user, at the screen"; root.setSaver({ on: !screenSaverItem.settings.on }) }
    else if (row.key === "saverAfter") root.setSaver({ after: SaverRules.next(SaverRules.AFTER, screenSaverItem.settings.after) })
    else if (row.key === "saverPictures") root.setSaver({ pictures: SaverRules.next(SaverRules.PICTURES, screenSaverItem.settings.pictures) })
    else if (row.key === "saverEvery") root.setSaver({ every: SaverRules.next(SaverRules.EVERY, screenSaverItem.settings.every) })
    else if (row.key === "saverClock") root.setSaver({ clock: SaverRules.next(SaverRules.CLOCK, screenSaverItem.settings.clock) })
    else if (row.key === "shortcut") { root.shortcut = Shortcut.CHOICES[(Shortcut.CHOICES.indexOf(root.shortcut) + 1) % Shortcut.CHOICES.length]; root.saveSettings() }
    else if (row.key === "barIcon") { root.barIcon = !root.barIcon; root.saveSettings() }
    else if (row.key === "videos") root.setVideos(!videos.enabled, "")
    else if (row.key === "recOn") {
      // off with recordings running or scheduled: they stop or are cancelled, after a second Enter
      if (dvr.settings.on && (dvr.active.length || dvr.busy || dvr.hasWaiting) && root.settingsArmed !== "recOff") { root.settingsArmed = "recOff"; return }
      root.settingsArmed = ""
      if (dvr.settings.on) dvr.turnOff(); else dvr.set({ on: true })
    }
    else if (row.key === "recKeepFree") dvr.set({ keepFree: DvrRules.next([0].concat(DvrRules.KEEP_FREE), dvr.settings.keepFree) })
    else if (row.key === "recQuality") dvr.set({ quality: DvrRules.next([0].concat(DvrRules.QUALITIES), dvr.settings.quality) })
    else if (row.key === "recAtOnce") dvr.set({ atOnce: DvrRules.next(DvrRules.AT_ONCE, dvr.settings.atOnce) })
    else if (row.key === "recPadding") dvr.set({ padding: (dvr.settings.padding + 1) % DvrRules.PADDINGS.length })
    else if (row.key === "recPause") dvr.set({ timeshift: DvrRules.next(Ts.MINUTES, dvr.settings.timeshift) })
    else if (row.key === "lineup") { root.lineupMode = root.lineupMode === "latest" ? "daily" : "latest"; root.saveSettings() }
    else if (row.key === "skill") root.setAgentSkill(!root.agentSkill)
    else if (row.key === "apps") { if (appsStore.on) appsStore.setOn(false); else root.askApps(by) }
    else if (row.key === "developer") { if (appsStore.developer) appsStore.setDeveloper(false); else root.askDeveloper(by) }
    else if (row.key === "unknownSources") { if (appsStore.unknownSources) appsStore.setUnknownSources(false); else return root.askUnknownSources(by) }
  }

  // Settings → About: OK 7 times on the version shows Developer mode's row (DeveloperPresses.qml)
  function versionPressed(by) { return devPresses.press(by) }
  DeveloperPresses {
    id: devPresses
    byUser: root.byUser
    apps: appsStore
  }

  // The AI agent skill: linked into agents' skill folders while it's on.
  function setAgentSkill(on) {
    root.agentSkill = on === true
    root.agentSettled = true
    root.agentAsked = true
    root.saveSettings()
    root.linkSkill()
  }

  function linkSkill() {
    skillLinker.replace(["/usr/bin/bash", root.pluginDir + "/bin/om-pg-skill", root.agentSkill ? "link" : "unlink", root.skillDir])
  }

  // Save the agent skill: a copy in your Downloads folder, to give to an AI
  // assistant of your choosing (on or off)
  function saveSkill(by) {
    if (by !== root.byUser) return "only the user, at the screen"
    if (skillSaver.running) return
    root.skillSaved = ""
    root.skillSaveFailed = false
    skillSaver.start(["/usr/bin/bash", root.pluginDir + "/bin/om-pg-skill", "save", root.skillDir])
  }

  // A first start asks, one at a time: the demo channels, turning apps on,
  // then the AI agent skill (each once)
  function askFirstStart() {
    if (!root.settingsLoaded || root.dialog !== "" || root.watching || !root.opened) return
    if (!root.demoAsked && root.demoToAdd().length) {
      root.demoAsked = true
      root.saveSettings()
      root.dialog = "demo"
      keys.forceActiveFocus()
      return
    }
    if (!root.appsAsked && !appsStore.on) {
      root.appsAsked = true
      root.saveSettings()
      root.askApps(root.byUser)
      return
    }
    root.askAboutAgents()
  }
  onDialogChanged: if (dialog === "" && opened && (!demoAsked || !appsAsked || !agentAsked)) agentAskTimer.restart()

  // The strip across Home and the guide (AskStrip.qml) asks one thing at a
  // time, each once: update notifications, then (once the updates look's
  // result has gone) Recordings
  readonly property string stripAsks: !updatesItem.asked ? "updates"
                                     : updatesItem.strip === "" && !root.recAsked && !dvr.settings.on ? "recordings" : ""
  readonly property string stripQuestion: stripAsks === "updates" ? "Updates are off. To get the latest updates, turn on update notifications."
                                        : stripAsks === "recordings" ? "New: Recordings. Record shows to watch later. Turn on here, or anytime in Settings → Recordings." : ""
  // where it shows: Home or the guide, nothing over it (a box, Multiview, an
  // app's video, the splash), not while you watch. The phone's TURN ON and
  // DISMISS answer it only then
  readonly property bool stripPlace: opened && !watching && dialog === "" && (screen === "home" || screen === "guide")
                                     && !managing && !homeEditing && !railEditing && !appPlaying && !(multiview && multiview.active) && !splashItem.running
  // Y (or Turn on) or N (or Dismiss): Dismiss puts it away for good, the
  // switch staying in Settings. Not again for a second, so the press (or a
  // double click) that answered one doesn't answer the next as it shows
  property real stripAnsweredAt: 0
  function stripAnswer(yes) {
    if (Date.now() - root.stripAnsweredAt < 1000) return
    root.stripAnsweredAt = Date.now()
    if (root.stripAsks === "updates") yes ? updatesItem.turnOn() : updatesItem.dismiss()
    else if (root.stripAsks === "recordings") {
      root.recAsked = true
      if (yes) dvr.set({ on: true })
      else root.saveSettings()
    }
  }

  function answerDemo(load) {
    root.closeDialog()
    if (load) root.loadDemoChannels()
  }

  // The first time the guide opens after this came in, it asks.
  function askAboutAgents() {
    if (root.agentAsked || root.agentSkill || !root.settingsLoaded || root.dialog !== "" || root.watching || !root.opened) return
    root.dialog = "agent"
  }

  function answerAgents(answer) {
    root.agentAsked = true
    if (answer === "yes") root.setAgentSkill(true)
    else if (answer === "no") { root.agentSettled = true; root.saveSettings() }
    else root.saveSettings()   // later: the strip keeps asking
    root.closeDialog()
  }

  // The filter box

  function openFilter() {
    if (!root.hasCategories && !root.hasIptv) return
    root.sourceDraft = root.shownSource
    root.filterDraft = root.shownCategories.filter(function(c) { return root.categories.indexOf(c) >= 0 })
    root.filterCursor = 0
    root.dialog = "filter"
  }

  function filterChecked(cat) {
    return !root.filterDraft.length || root.filterDraft.indexOf(cat) >= 0
  }

  // Row 0 is ALL; the rest are the categories, in the guide's order.
  function toggleFilter(i) {
    i = Number(i)
    if (i === 0) { root.filterDraft = []; return }
    var cat = root.categories[i - 1]
    var draft = root.filterDraft.length ? root.filterDraft.slice() : root.categories.slice()
    var at = draft.indexOf(cat)
    if (at >= 0) {
      if (draft.length === 1) return   // something has to show
      draft.splice(at, 1)
    } else {
      draft.push(cat)
    }
    root.filterDraft = draft.length === root.categories.length ? [] : draft
  }

  function cycleSource(delta) {
    var order = ["both", "youtube", "iptv"]
    root.sourceDraft = order[(order.indexOf(root.sourceDraft) + (delta < 0 ? 2 : 1)) % 3]
  }

  // As written; an element's case (Look.js) decides how it shows
  function sourceName(s) {
    return s === "youtube" ? "YouTube only" : s === "iptv" ? "IPTV only" : "YouTube + IPTV"
  }

  function sourceLabel(s) { return root.sourceName(s).toUpperCase() }

  function applyFilter() {
    root.shownSource = root.sourceDraft
    root.shownCategories = root.filterDraft.slice()
    root.saveSettings()
    root.closeDialog()
    if (root.visibleRows.indexOf(root.row) < 0) root.row = root.visibleRows[0] || 0
    if (root.channelList) root.channelList.positionViewAtIndex(Math.max(0, root.visibleRows.indexOf(root.row)), ListView.Contain)
  }

  function categoryName(cat) { return cat || "My Channels" }

  function categoryLabel(cat) { return root.categoryName(cat).toUpperCase() }

  function showBanner() {
    if (!root.ltShow) return
    root.bannerShown = true
    bannerTimer.restart()
  }

  // I or Space while watching: the banner with what you can do from here
  // (← → choose, Enter picks, Esc or ↓ hides). It stays while you choose.
  property bool bannerOptions: false
  property int bannerAct: 0
  // Recording (DVR.qml): the recording on the channel on, what Record would
  // do there (its note says what to know before it's pressed), and the stop
  // times, a second row of choices in place of the first
  readonly property var recOnTuned: dvr.onChannel(channels[tunedRow])
  readonly property var recOffer: bannerOptions && !recOnTuned && !vod ? dvr.offer(tunedRow) : null
  // What turning Recordings off does: "stop 1 recording and cancel 3 scheduled"
  function recOffWhat() {
    var going = dvr.active.length || (dvr.busy ? 1 : 0)
    var later = dvr.recordings.filter(DvrRules.waiting).length
    return [going ? "stop " + going + (going === 1 ? " recording" : " recordings") : "", later ? "cancel " + later + " scheduled" : ""].filter(function(x) { return x }).join(" and ")
  }
  property bool recStopMenu: false
  // J K L with pause and rewind off: the banner says so, with Turn on
  property bool tsOffMenu: false
  // Pause and rewind's choices, first (Pause focused): on a live channel
  // with it on; Pause dimmed, saying why, while it can't run
  readonly property var tsActions: !watching || vod || !timeshift.turnedOn || !Ts.supported(onAir) ? []
    : timeshift.active ? [{ key: "tsPause", label: timeshift.paused ? "Resume" : "Pause", icon: "" },
                          { key: "tsBack", label: "Back 30 s", icon: "" },
                          { key: "tsForward", label: "Forward 30 s", icon: "" },
                          { key: "tsLive", label: "Live", icon: "", unavailable: timeshift.atLive }]
    : [{ key: "tsPause", label: "Pause", icon: "", unavailable: true, note: timeshift.cantPauseText }]
  readonly property var bannerActions: {
    if (tsOffMenu) return [{ key: "tsOn", label: "Turn on", icon: "", note: "Pause and rewind is off" }]
    if (streamAsk) return [{ key: "streamYes", label: streamAskLabel, icon: "", rec: true, note: streamAskNote }, { key: "streamNo", label: "Stay", icon: "" }]
    if (recStopMenu && recOnTuned)
      return DvrRules.stopChoices(recOnTuned, onAir && onAir.epg ? onAir.end : 0, now, root.clock).map(function(c) { return { key: "recEnd", end: c.end, label: c.label, rec: true } })
    var rec = recOnTuned && dvr.stopping[recOnTuned.id] ? [{ key: "recStopping", label: "Stopping…", icon: "", rec: true, unavailable: true }]
            : recOnTuned ? [{ key: "recStop", label: "Stop recording", icon: "", rec: true,
                              note: recOnTuned.state === "starting" ? "Starting…" : recOnTuned.sleepUnprotected ? "Sleep protection unavailable" : "" },
                            { key: "recUntil", label: "Until " + root.clock(recOnTuned.end) + "  ›", icon: "", rec: true }]
            : recOffer ? [{ key: "record", label: dvr.busy ? "Starting…" : recOffer.label, icon: "record", rec: true, note: dvr.said || recOffer.note, unavailable: recOffer.unavailable }]
            : []
    return tsActions.concat([{ key: "multiview", label: "Multiview", icon: "apps" }]).concat(rec).concat([{ key: "mini", label: "Mini player", icon: "window" },
            { key: "guide", label: "Guide", icon: "tv" }, { key: "mute", label: root.muted ? "Sound on" : "Mute", icon: "" }])
  }
  // The REC badge on the banner: only on the channel that's recording, until
  // when (another channel's banner says nothing of it: the guide's top line
  // and its ● REC do)
  readonly property string recBadge: recOnTuned ? (dvr.stopping[recOnTuned.id] ? "Stopping…" : recOnTuned.state === "starting" ? "Starting to record…" : "● REC until " + root.clock(recOnTuned.end))
                                     : ""
  // and a word when watching this one and recording another from the same provider
  readonly property string recNote: !recOnTuned && !vod && tunedRow >= 0 && dvr.anyActive && dvr.sharesProvider(channels[tunedRow]) ? "Watching and recording from this provider: 2 streams" : ""
  // Record turned into Stop under the cursor: the cursor goes to Until, so a
  // second Enter doesn't stop what just started
  readonly property string recOnTunedId: recOnTuned ? recOnTuned.id : ""
  onRecOnTunedIdChanged: if (recOnTunedId && bannerOptions && !recStopMenu && (bannerActions[bannerAct] || {}).key === "recStop")
                           bannerAct = Math.max(0, bannerActions.findIndex(function(a) { return a.key === "recUntil" }))
  function openBannerOptions() {
    root.bannerAct = 0
    root.recStopMenu = false
    root.tsOffMenu = false
    dvr.said = ""
    root.bannerOptions = true
    root.bannerShown = true
    bannerTimer.restart()
    dvr.checkPlace()
  }
  function hideBanner() {
    root.streamAsk = null
    root.bannerOptions = false
    root.bannerShown = false
    root.recStopMenu = false
    root.tsOffMenu = false
    bannerTimer.stop()
  }
  // Esc, ↓ or BACK on the banner's choices: out of the stop times first, then away
  function bannerBack() {
    if (root.streamAsk) { root.answerStream(false); return }
    if (root.recStopMenu) {
      root.recStopMenu = false
      root.bannerAct = Math.max(0, root.bannerActions.findIndex(function(a) { return a.key === "recUntil" }))
      bannerTimer.restart()
      return
    }
    root.hideBanner()
  }
  function moveBannerAct(d) {
    root.bannerAct = Math.max(0, Math.min(root.bannerActions.length - 1, root.bannerAct + d))
    bannerTimer.restart()
  }
  function pickBannerAct(i) {
    var a = root.bannerActions[i === undefined ? root.bannerAct : i]
    if (!a) return
    if (a.key === "mute") { root.muted = !root.muted; bannerTimer.restart(); return }
    if (a.key === "tsOn") { root.hideBanner(); dvr.set({ timeshift: 5 }); return }
    if (a.key.indexOf("ts") === 0) {
      bannerTimer.restart()
      if (a.unavailable) return
      if (a.key === "tsPause") timeshift.togglePause()
      else if (a.key === "tsBack") timeshift.back()
      else if (a.key === "tsForward") timeshift.forward()
      else if (a.key === "tsLive") timeshift.live()
      return
    }
    if (a.key === "record") {
      bannerTimer.restart()
      if (!a.unavailable && !dvr.busy) dvr.record(root.tunedRow)
      return
    }
    if (a.key === "streamYes" || a.key === "streamNo") { root.answerStream(a.key === "streamYes"); return }
    if (a.key === "recStopping") { bannerTimer.restart(); return }
    if (a.key === "recStop") { if (root.recOnTuned) dvr.stop(root.recOnTuned.id); bannerTimer.restart(); return }
    if (a.key === "recUntil") { root.recStopMenu = true; root.bannerAct = 0; bannerTimer.restart(); return }
    if (a.key === "recEnd") {
      if (root.recOnTuned) dvr.setEnd(root.recOnTuned.id, a.end)
      root.bannerBack()
      return
    }
    root.hideBanner()
    if (a.key === "multiview") root.openMultiview()
    else if (a.key === "mini") root.goPip()
    else if (a.key === "guide") root.showGuide()
  }

  // J K L while watching a live channel: Back 30 s, Pause or Resume,
  // Forward 30 s. Off: the banner saying so, with Turn on; on but not
  // running: the banner's choices, Pause first, saying why
  function tsKey(what) {
    if (!root.watching || root.vod) return
    if (!timeshift.turnedOn) {
      root.bannerAct = 0
      root.recStopMenu = false
      root.tsOffMenu = true
      root.bannerOptions = true
      root.bannerShown = true
      bannerTimer.restart()
      return
    }
    if (!timeshift.active) { root.openBannerOptions(); return }
    if (what === "pause") timeshift.togglePause()
    else if (what === "back") timeshift.back()
    else timeshift.forward()
    root.showBanner()
  }

  // The TV

  // Also reachable from outside: omarchy-shell shell call marcho78.om-pg tune <row>
  function tune(r, at, retrying) {
    r = Number(r)
    // a locked channel plays only once it's unlocked (ChannelLock.qml): your
    // actions ask for the passcode before they come here
    if (channelLockItem.blocks(root.channels[r])) return "locked"
    // one channel on the TV instead of Multiview: its tiles stop first, and
    // an agent's Multiview still on its way doesn't start
    root.mvRequest += 1
    if (root.multiview && root.multiview.active) root.multiview.teardown()
    // an app's playback ends first, finalized, then the TV
    if (root.appPlaying) {
      appPlaybackItem.dropPending()   // asked for after it: the TV wins over an app play queued before
      appPlaybackItem.close("replaced", function() { root.tune(r, at, retrying) })
      return "ok"
    }
    if (root.vod) root.leaveVod()
    if (!retrying) root.iptvRetried = false
    var ch = root.channels[r]
    if (!root.airs(ch)) return "not ready"
    var t = at || Date.now() / 1000
    if (root.recentChannels[0] !== ch.url) {
      root.recentChannels = [ch.url].concat(root.recentChannels.filter(function(u) { return u !== ch.url })).slice(0, 12)
      recentSaver.restart()
    }
    root.tunedRow = r
    if (ch.kind !== "iptv" && !ch.live) {
      root.rollDay()
      ch = root.channels[r]
    }
    root.onAir = root.airing(ch, t)
    root.reception = "tuning"
    root.started = false
    identHold.restart()
    tuneWatchdog.restart()
    if (root.streamBase || root.onAir.iptv) root.play()
    else {
      player.stop()
      streamer.running = true   // play() runs once the streamer says where it is
    }
    return "ok"
  }

  // What a channel airs at t, as the TV plays it: an IPTV stream (its
  // listing's show, if any), a live stream from its edge, or its schedule's
  // video mid-show. The TV's tuning and Multiview's tiles both use it; a
  // scheduled channel's day is rolled (rollDay) before asking.
  function airing(ch, t) {
    if (ch.kind === "iptv") {
      var listed = listings.at(ch.url, t)
      return listed ? { id: "", stream: ch.url, title: listed.title, start: listed.start, end: listed.end, live: true, iptv: true, epg: true }
                    : { id: "", stream: ch.url, title: ch.live.title, start: t, end: t + 6 * 3600, live: true, iptv: true }
    }
    if (ch.live) return { id: ch.live.id, title: ch.live.title, start: t, end: t + 6 * 3600, live: true }
    var lineup = root.lineupOf(ch)
    var here = Schedule.locate(lineup, t)
    var item = lineup[here.index]
    return { id: item.id, title: item.title, start: t - here.offset, end: t - here.offset + item.duration }
  }

  // A channel's live stream ended: back to its videos, and look for the next
  // one. The TV and Multiview's tiles both use it.
  function liveEnded(r) {
    root.liveChecked(root.liveUrlOf(root.channels[r].url), JSON.stringify({ entries: [] }))
    root.checkLive(r)
  }

  // The streamer, for a Multiview tile that needs it before the TV did
  function startStreamer() {
    if (!root.streamBase) streamer.running = true
  }

  // An agent's Multiview (Commands.qml multiview): a request, numbered when
  // it's asked for; turning the TV off, closing, or a channel or video
  // played since overtakes it. An app's playback ends first, finalized, as
  // for the TV; then, if it's still the latest and the guide is open, the
  // tiles. While one is on its way the preview box waits (its tune would
  // overtake it: it's not a choice of yours).
  property int mvRequest: 0
  property int mvWaitingFor: -1        // the request on its way, if it's still the latest
  onAppPlayingChanged: if (appPlaying) { mvRequest += 1; timeshift.end() }   // an app's video, chosen since, overtakes it too (and the TV's buffer goes)
  function requestMultiview() { root.mvRequest += 1; root.mvWaitingFor = root.mvRequest; return root.mvRequest }
  function startMultiview(urls, request) {
    if (request !== root.mvRequest || !root.opened) { if (root.mvWaitingFor === request) root.mvWaitingFor = -1; return "overtaken" }
    if (root.appPlaying) {
      appPlaybackItem.dropPending()   // asked for after it: Multiview wins over an app play queued before
      appPlaybackItem.close("replaced", function() { root.startMultiview(urls, request) })
      return "ok"
    }
    root.mvWaitingFor = -1
    return multiviewItem.startWith(urls)
  }

  // Multiview from the channel that's on (the banner's Multiview)
  function openMultiview() {
    if (root.reception === "off" || root.tunedRow < 0 || root.vod || !root.channels[root.tunedRow]) return "nothing on"
    return multiviewItem.start(root.channels[root.tunedRow].url)
  }

  function streamUrl() {
    if (root.onAir && root.onAir.vod) return root.onAir.stream || (root.streamBase && root.onAir.id ? root.streamBase + "/play/" + root.onAir.id + ".m3u8" : "")
    if (root.onAir && root.onAir.iptv) return root.onAir.stream
    return root.onAir && root.streamBase ? root.streamBase + "/play/" + root.onAir.id + ".m3u8" : ""
  }

  // An IPTV stream offering several sizes plays the biggest up to 1080p.
  function pickBestTrack() {
    var best = -1
    var bestHeight = -1
    for (var i = 0; i < player.videoTracks.length; i++) {
      var size = player.videoTracks[i].value(MediaMetaData.Resolution)
      var h = size ? size.height : 0
      if (h <= 1080 && h > bestHeight) { bestHeight = h; best = i }
    }
    if (best >= 0 && best !== player.activeVideoTrack) player.activeVideoTrack = best
  }

  // Goes straight to the new stream. Clearing the source first makes Qt's
  // FFmpeg backend abort the next open as well ("Immediate exit requested"),
  // so only the same stream again is cleared, and set back a moment later.
  function play() {
    if (root.reception !== "tuning" || !root.streamUrl()) return
    if (timeshift.takes(root.onAir)) { timeshift.tuned(); return }
    if (timeshift.busy) { timeshift.end(function() { if (root.reception === "tuning" && !timeshift.busy) root.play() }); return }
    if (player.source.toString() === root.streamUrl()) {
      player.source = ""
      reload.restart()
    } else {
      player.source = root.streamUrl()
    }
  }

  function turnOff() {
    root.mvRequest += 1        // an agent's Multiview still on its way doesn't start
    timeshift.end()            // pause and rewind's buffer goes
    multiviewItem.teardown()   // every tile stops too, and nothing restarts one
    if (root.vod) root.leaveVod()
    player.stop()
    player.source = ""
    root.reception = "off"
    root.watching = false
    if (root.pip) {
      root.pip = false
      player.videoOutput = video
    }
  }

  // On demand

  // Plays something from the start, or from where you stopped (from: a
  // number of seconds overrides that). Full screen.
  function playVod(entry, from) {
    if (!entry || (!entry.url && !entry.videoId)) return "nothing to play"
    // a locked channel's video: the passcode first (it unlocks the channel)
    var lockedBy = entry.videoId ? root.videoLockedBy(entry.videoId, entry.subtitle, entry.owners, entry.ownersMore) : null
    if (lockedBy) {
      if (!root.opened) root.summonGuide(false)
      channelLockItem.askUnlock(lockedBy, function() { root.playVod(entry, from) })
      return "the passcode first"
    }
    root.mvRequest += 1   // an agent's Multiview still on its way doesn't start
    if (root.multiview && root.multiview.active) root.multiview.teardown()   // something on demand instead of Multiview
    if (root.appPlaying) {
      appPlaybackItem.dropPending()
      appPlaybackItem.close("replaced", function() { root.playVod(entry, from) })
      return "ok"
    }
    if (root.vod) root.leaveVod()
    timeshift.end()            // a video instead of the channel: its buffer goes
    var start = from !== undefined && from !== null ? Math.max(0, Number(from) || 0) : library.resumeAt(entry.id)
    root.vod = entry
    root.vodPaused = false
    root.tunedRow = -1
    root.onAir = { id: entry.videoId || "", stream: entry.url || "", title: entry.title, start: 0, end: 0, vod: true, resumeAt: start }
    root.reception = "tuning"
    root.started = false
    identHold.restart()
    tuneWatchdog.restart()
    root.watching = !root.pip
    root.showVodBar()
    if (root.streamBase || entry.url) root.play()
    else {
      player.stop()
      streamer.running = true
    }
    return "ok"
  }

  // Saves where you are and lets go of it (the player keeps running for
  // whatever comes next)
  function leaveVod() {
    if (!root.vod) return
    if (root.started && player.duration > 0) library.record(root.vod, player.position / 1000, player.duration / 1000)
    library.flush()
    root.vod = null
    root.vodBarShown = false
    root.vodPaused = false
  }

  // Esc: stops it, back to the library (or the guide)
  function stopVod() {
    if (!root.vod) return
    root.turnOff()
  }

  // Skips add up, and the player is asked at most every seekGap ms: each
  // seek makes FFmpeg find its place in the file, and a held key (or a remote
  // sending hundreds) asked for more than it could do, until the shell stalled
  function seekVod(seconds) {
    if (!root.vod || !root.started || player.duration <= 0) return
    var from = root.seekTarget >= 0 ? root.seekTarget : player.position
    root.seekVodTo((from + seconds * 1000) / 1000)
  }

  function seekVodTo(seconds) {
    if (!root.vod || !root.started || player.duration <= 0) return
    root.seekTarget = Math.max(0, Math.min(player.duration - 1000, seconds * 1000))
    if (!seekGap.running) root.applySeek()
    root.showVodBar()
  }

  function applySeek() {
    if (root.seekTarget < 0) return
    if (root.vod && player.duration > 0) player.position = root.seekTarget
    root.seekTarget = -1
    seekGap.restart()   // a seek asked for during the gap waits for its end
  }

  function togglePause() {
    if (!root.vod) return
    if (player.playbackState === MediaPlayer.PlayingState) player.pause()
    else player.play()
    root.showVodBar()
  }

  function showVodBar() {
    root.vodBarShown = true
    vodBarTimer.restart()
  }

  // A movie's poster, or a YouTube video's picture, through the streamer's cache
  function posterFor(entry) {
    if (!entry) return ""
    if (entry.poster && entry.poster.charAt(0) === "/") return root.fileUrl(entry.poster)
    if (!root.streamBase) return ""
    var src = entry.poster || (entry.videoId ? "https://i.ytimg.com/vi/" + entry.videoId + "/mqdefault.jpg" : "")
    if (!src) return ""
    // a live stream's picture follows what's on: kept a quarter of an hour
    // (fresh), and asked for again each quarter
    var fresh = entry.live === true && entry.videoId && !entry.poster ? "&fresh=" + root.liveBucket : ""
    return root.streamBase + "/picon?src=" + encodeURIComponent(src) + fresh
  }

  function libraryItems() { return library.items }
  function libraryGenres() { return library.genres }
  function resumeAt(id) { return library.resumeAt(id) }
  function inMyList(id) { return library.inList(id) }

  // Something to play, from a library item or a channel's video
  function movieEntry(item) {
    return { id: item.id, kind: "movie", title: item.title, poster: item.poster, url: item.url, description: item.description || "",
             subtitle: [item.series ? item.series + (item.season ? " · S" + item.season + " E" + item.episode : "") : item.genre].concat(item.year ? [item.year] : []).join(" · ") }
  }

  function videoEntry(ch, video) {
    var kept = library.history["yt:" + video.id] || {}
    return { id: "yt:" + video.id, kind: "youtube", title: video.title, subtitle: ch ? ch.name : "", poster: "", videoId: video.id, duration: video.duration || 0,
             owners: root.videoOwners(video.id, kept.owners), ownersMore: kept.ownersMore === true }
  }

  // By id: a library item or a video of yours (v…), or a YouTube video
  // (yt:…) on one of your channels or in what you've watched
  function entryFor(id) {
    id = String(id || "").trim()
    var item = library.item(id)
    if (item) return root.movieEntry(item)
    var file = videos.enabled ? videos.item(id) : null
    if (file) return root.fileEntry(file)
    var m = id.match(/^yt:([A-Za-z0-9_-]{11})$/)
    if (!m) return null
    var rows = root.videoRows(m[1])
    if (rows.length) return root.videoEntry(root.channels[rows[0]], root.channels[rows[0]].items.filter(function(v) { return v.id === m[1] })[0])
    var h = library.history[id]
    return h ? { id: id, kind: "youtube", title: h.title, subtitle: h.subtitle, poster: h.poster, videoId: m[1], duration: h.duration, owners: (h.owners || []).slice(),
                 ownersMore: h.ownersMore === true } : null
  }

  // What's on, in a line: a movie's title, or the channel
  function nowLabel() {
    return root.vod ? root.vod.title : root.channelLabel(root.tunedRow)
  }

  // The mini player

  // From the guide: the highlighted channel; from full screen: what's on.
  // Also reachable from outside: omarchy-shell shell call marcho78.om-pg goPip x
  function goPip() {
    if (root.opened && !root.watching && root.row !== root.tunedRow && root.askToWatch(root.row, root.goPip)) return "the passcode first"
    if (root.opened && !root.watching && !root.streamOk(root.row, root.goPip)) return "asked first: a 2nd stream from that provider"
    var idle = root.reception === "off" || root.reception === "lost"
    if (root.opened && !root.watching && (root.row !== root.tunedRow || idle)) {
      if (root.tune(root.row) !== "ok") return "nothing to watch"
    } else if (idle) {   // with the guide closed, what was on (or the cursor's channel)
      if (root.tune(root.tunedRow >= 0 ? root.tunedRow : root.row) !== "ok") return "nothing to watch"
    }
    if (root.reception === "off") return "nothing to watch"
    root.pip = true
    root.watching = false
    player.videoOutput = pipWindow.video
    root.showPipBanner()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide((root.manifest && root.manifest.id) || "marcho78.om-pg")
    else root.opened = false
    return "ok"
  }

  // Back to the program guide, the channel still playing in the preview box.
  function guidePip() {
    var payload = JSON.stringify({ watch: false, screen: "guide" })
    if (root.shell && typeof root.shell.summon === "function") root.shell.summon((root.manifest && root.manifest.id) || "marcho78.om-pg", payload)
    else root.open(payload)
  }

  // Back to full screen, in the guide.
  function expandPip() {
    var payload = JSON.stringify({ watch: true })
    if (root.shell && typeof root.shell.summon === "function") root.shell.summon((root.manifest && root.manifest.id) || "marcho78.om-pg", payload)
    else root.open(payload)
  }

  // Opens the guide on a screen: home, guide or library
  function summonTo(screen) {
    var payload = JSON.stringify({ watch: false, screen: screen })
    if (root.shell && typeof root.shell.summon === "function") root.shell.summon((root.manifest && root.manifest.id) || "marcho78.om-pg", payload)
    else root.open(payload)
  }

  function closePip() {
    root.turnOff()
    channelLockItem.relock()
  }

  function pipSurf(delta) {
    root.surf(delta)
    root.showPipBanner()
  }

  function pointerAt(text) {
    var m = String(text).match(/(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/)
    if (!m || !root.pip) { root.pipPointerIn = false; return }
    var x = Number(m[1])
    var y = Number(m[2])
    var left = (pipWindow.screen ? pipWindow.screen.x : 0) + pipWindow.screenW - pipWindow.margins.right - pipWindow.w
    var top = (pipWindow.screen ? pipWindow.screen.y : 0) + pipWindow.screenH - pipWindow.margins.bottom - pipWindow.h
    root.pipPointerIn = x >= left && x < left + pipWindow.w && y >= top && y < top + pipWindow.h
  }

  onPipPointerInChanged: if (pipPointerIn) pipWindow.keys.forceActiveFocus()

  // ---- the guide's shortcut and its icon in the bar ----
  // The shortcut is registered with Hyprland while the guide runs
  // (hypr/om-pg.lua, run with `hyprctl eval`); your Hyprland config is never
  // edited. A config reload clears it, so it's registered again on every
  // `configreloaded`, and it's taken back out when the guide is turned off or
  // reloaded. A shortcut another binding already uses is left alone, and
  // Settings says which. The icon is BarWidget.qml; both settings live in
  // settings.json ("bar").
  property bool barIcon: true
  property string shortcut: Shortcut.DEFAULT     // "" for none
  property string shortcutStatus: ""             // "", "ok", "off", "taken", "failed"
  property string shortcutTakenBy: ""
  property string shortcutProblem: ""
  property bool shortcutRegistering: false
  property bool shortcutAgain: false
  readonly property string shortcutModule: root.pluginDir + "/hypr/om-pg.lua"
  readonly property string pluginId: (root.manifest && root.manifest.id) || "marcho78.om-pg"

  onSettingsLoadedChanged: { if (settingsLoaded) shortcutTimer.restart(); root.prunePictures() }
  onShortcutChanged: if (settingsLoaded) shortcutTimer.restart()

  function registerShortcut() {
    if (root.shortcutRegistering) { root.shortcutAgain = true; return }
    root.shortcutRegistering = true
    shortcutBinds.start(["/usr/bin/hyprctl", "-j", "binds"])
  }

  // The shortcut pressed: the guide opens or closes, through the shell (so
  // the shell knows), the same as the bar icon and `omarchy-shell shell toggle`
  function shortcutToggle() {
    if (root.shell && typeof root.shell.toggle === "function") root.shell.toggle(root.pluginId, "{}")
    else root.toggle()
  }

  Timer {
    id: shortcutTimer
    // long enough for a reloaded guide's cleanup to land first
    interval: 350
    onTriggered: root.registerShortcut()
  }

  Run {
    id: shortcutBinds
    maxBytes: 512 * 1024
    timeoutMs: 4000
    onFinished: function(ok, output) {
      var binds = null
      if (ok) { try { binds = JSON.parse(output) } catch (e) { binds = null } }
      root.shortcutTakenBy = root.shortcut ? Shortcut.takenBy(root.shortcut, binds) : ""
      var use = root.shortcut && !root.shortcutTakenBy ? root.shortcut : null
      shortcutEval.start(["/usr/bin/hyprctl", "eval", Shortcut.registration(root.shortcutModule, use)])
    }
  }

  Run {
    id: shortcutEval
    maxBytes: 16 * 1024
    timeoutMs: 4000
    onFinished: function(ok, output) {
      // hypr/om-pg.lua raises what didn't register; hyprctl prints it as "error: …"
      var text = String(output || "").trim().replace(/^error:\s*/i, "")
      var registered = ok && (text === "" || text === "ok")
      root.shortcutProblem = registered ? "" : (text.slice(0, 300) || "Hyprland didn't answer")
      root.shortcutStatus = !root.shortcut ? "off" : root.shortcutTakenBy ? "taken" : registered ? "ok" : "failed"
      if (!registered) console.warn("om-pg: registering the shortcut with Hyprland:", root.shortcutProblem)
      root.shortcutRegistering = false
      if (root.shortcutAgain) { root.shortcutAgain = false; root.registerShortcut() }
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "custom") { if (Shortcut.parseEvent(event.data) === "toggle") root.shortcutToggle() }
      else if (event.name === "configreloaded") shortcutTimer.restart()
    }
  }

  // Turned off or reloaded: the shortcut comes back out of Hyprland (a
  // reloaded guide registers it again right after)
  Component.onDestruction: Quickshell.execDetached(["/usr/bin/hyprctl", "eval", Shortcut.registration(root.shortcutModule, null)])

  // The phone remote: only you open its box (it shows the pairing code) and
  // turn it on or off (by: byUser, from the keys, the mouse or the phone)

  function openRemote(by) {
    if (by !== root.byUser) return "only the user, at the screen"
    root.dialog = "remote"
    root.remoteMessage = ""
    root.remoteCursor = 0
    root.remoteArmed = ""
    ufwCheck.running = true
    if (root.remoteEnabled) {
      root.remoteStep = "on"
      root.remoteSend({ pairing: true })
    } else {
      root.remoteStep = ""
      remoteProbe.running = true   // only reads the network, to show it before anything opens
    }
  }

  // Enter on the off screen: show what turning it on means.
  function remoteAsk(by) {
    if (by !== root.byUser || !root.boxShown()) return "only the user, at the screen"
    if (!root.remoteNet) { root.remoteMessage = "Still checking your network…"; return }
    root.remoteMessage = ""
    root.remoteStep = "confirm"
  }

  // Enter on the agreement: the firewall first, if it needs a rule.
  function remoteAgree(by) {
    if (by !== root.byUser || !root.boxShown()) return "only the user, at the screen"
    if (root.firewallActive && !root.remoteAllowedHere) root.firewall("allow", by)
    else root.turnRemoteOn(by)
  }

  function turnRemoteOn(by) {
    if (by !== root.byUser) return "only the user, at the screen"
    root.remoteEnabled = true
    root.remoteStep = "on"
    root.saveSettings()
    root.startRemoteHelper()
  }

  function startRemoteHelper() {
    if (remoteHelper.running || !root.remoteEnabled) return
    root.remoteStopping = false
    remoteHelper.command = ["/usr/bin/python3", root.pluginDir + "/bin/om-pg-remote", String(root.remotePort)]
    remoteHelper.running = true
  }

  function turnRemoteOff(removeRule, by) {
    if (by !== root.byUser) return "only the user, at the screen"
    removeRule = removeRule === true   // never a prompt by accident
    root.remoteStopping = true
    root.remoteEnabled = false
    root.remoteReady = false
    root.remotePairing = null
    remoteHelper.running = false
    root.saveSettings()
    if (removeRule && root.remoteNet && root.remoteRules.indexOf(root.remoteNet.subnet + " " + root.remotePort) >= 0) {
      root.firewall("remove", root.byUser)   // taking the rule out, with the system's password prompt
    } else {
      root.remoteStep = ""
      root.remoteMessage = "The phone remote is off, and its port is closed."
    }
  }

  // Adds or removes the one firewall rule, with the system's password prompt.
  // The guide lets go of the keyboard while it's up.
  function firewall(what, by, given) {
    if (by !== root.byUser) return "only the user, at the screen"
    var net = root.remoteNet
    var port = root.remotePort
    if (given !== undefined) {
      var parts = String(given).split(" ")
      net = what === "remove" && parts.length === 2 ? { subnet: parts[0] } : null
      port = Number(parts[1])
    }
    if (!net || !/^\d+\.\d+\.\d+\.\d+\/\d+$/.test(net.subnet) || !(port >= 1025 && port <= 65535)) return "not a rule"
    root.firewallRule = net.subnet + " " + port
    root.firewallFor = what
    root.firewallBusy = true
    root.remoteStep = "firewall"
    firewallRun.command = what === "allow"
      ? ["/usr/bin/pkexec", "/usr/bin/ufw", "allow", "from", net.subnet, "to", "any", "port", String(port), "proto", "tcp", "comment", "om-pg phone remote"]
      : ["/usr/bin/pkexec", "/usr/bin/ufw", "delete", "allow", "from", net.subnet, "to", "any", "port", String(port), "proto", "tcp"]
    firewallRun.running = true
    return true
  }

  function firewallDone(code, by) {
    if (by !== root.byUser) return
    var rule = root.firewallRule
    root.firewallBusy = false
    Qt.callLater(function() { keys.forceActiveFocus() })
    if (root.firewallFor === "allow") {
      if (code === 0) {
        if (root.remoteRules.indexOf(rule) < 0) root.remoteRules = root.remoteRules.concat([rule])
        if (root.remoteEnabled) { root.remoteStep = "on"; root.saveSettings() }
        else root.turnRemoteOn(by)
      } else {
        root.remoteStep = root.remoteEnabled ? "on" : ""
        root.remoteMessage = "The firewall wasn't changed" + (root.remoteEnabled ? ", so phones on this network can't reach the remote." : ", so the remote stays off.")
      }
    } else {
      if (code === 0) root.remoteRules = root.remoteRules.filter(function(r) { return r !== rule })
      root.saveSettings()
      root.remoteStep = ""
      root.remoteMessage = code === 0 ? "The phone remote is off, its port is closed, and the firewall rule is removed."
                                      : "The phone remote is off and its port is closed. The firewall rule is still there."
    }
    if (root.firewallThen) {
      var then = root.firewallThen
      root.firewallThen = null
      then(code === 0)
    }
  }

  // What's waiting to be written, written now (before a backup)
  function flushAll() {
    library.flush()
    root.saveSettings()
  }

  function remoteSend(message) {
    if (remoteHelper.running && root.remoteReady) remoteHelper.write(JSON.stringify(message) + "\n")
  }

  // A line from bin/om-pg-remote (or its probe): by is byUser when it came
  // from there, and nothing else is listened to
  function remoteHeard(line, by) {
    if (by !== root.byUser) return
    var m
    try { m = JSON.parse(line) } catch (e) { return }
    if (m.ready) {
      root.remoteNet = m.ready
      root.remoteReady = true
      root.sendRemoteState()
      if (root.dialog === "remote") root.remoteSend({ pairing: true })
    } else if (m.probe) {
      root.remoteNet = m.probe
    } else if (m.pairing) {
      root.remotePairing = m.pairing
    } else if (m.devices) {
      root.remoteDevices = m.devices
      root.remoteCursor = Math.max(0, Math.min(root.remoteCursor, m.devices.length - 1))
    } else if (m.command) {
      root.remoteCommand(m.command.cmd, m.command.number, by, m.command.digits)
    } else if (m.error) {
      root.remoteMessage = m.error
    }
  }

  function forgetPhone() {
    var d = root.remoteDevices[root.remoteCursor]
    if (d) root.remoteSend({ forget: d.id })
    root.remoteArmed = ""
  }

  // Enter (or OK, or Del) on a paired phone: asks once, then unpairs it
  function unpairAct() {
    var d = root.remoteDevices[root.remoteCursor]
    if (!d) return
    if (root.remoteArmed !== d.id) { root.remoteArmed = d.id; return }
    root.forgetPhone()
  }

  function movePhones(d) {
    root.remoteCursor = Math.max(0, Math.min(root.remoteDevices.length - 1, root.remoteCursor + Number(d)))
    root.remoteArmed = ""
  }

  // What the phones show: what's on, and the channels with what each is airing.
  function remoteState() {
    var on = root.reception !== "off" && !!root.onAir
    var ch = root.channels[root.tunedRow]
    var t = Date.now() / 1000
    var list = []
    for (var i = 0; i < root.visibleRows.length; i++) {
      var r = root.visibleRows[i]
      var c = root.channels[r]
      var title = ""
      var listedNow = c.kind === "iptv" ? listings.at(c.url, t) : null
      if (listedNow) title = listedNow.title
      else if (c.live) title = c.live.title
      else if (c.state === "ready") {
        var lineup = root.lineupOf(c)
        title = lineup[Schedule.locate(lineup, t).index].title
      }
      var lockedNow = channelLockItem.blocks(c)
      list.push({ number: root.numbers[r], name: c.name, category: c.category || "", channelId: lockedNow ? "" : c.channelId || "",
                  title: root.titlesHidden(c) ? "Locked" : root.showTitle(title), live: !!c.live && !root.titlesHidden(c), locked: lockedNow })
    }
    var vod = on && root.vod ? root.vod : null
    return {
      on: on, muted: root.muted, screen: root.opened ? root.screen : "",
      passcode: channelLockItem.boxUp && channelLockItem.typing,
      // the strip's question while it's on the screen (the phone's TURN ON and DISMISS answer it)
      ask: root.stripAsks !== "" && root.stripPlace ? { text: root.stripQuestion } : null,
      // as the banner says it: recording (this channel, or another), and pause and rewind
      rec: on ? root.recBadge : "",
      pause: on && !vod && timeshift.active ? (timeshift.paused ? "Paused" : timeshift.atLive ? "" : timeshift.chipText) : "",
      mode: root.pip && on ? "mini" : root.watching && on ? "full" : root.opened ? root.screen : "off",
      now: vod ? { vod: true, title: root.showTitle(vod.title), name: vod.subtitle || "", paused: root.vodPaused }
         : on && ch ? { number: root.numbers[root.tunedRow], name: ch.name, category: ch.category || "", channelId: ch.channelId || "",
                       title: root.showTitle(root.onAir.title), live: !!root.onAir.live, start: root.onAir.start, end: root.onAir.end } : null,
      channels: list
    }
  }

  function sendRemoteState() {
    root.remoteSend({ state: root.remoteState() })
  }

  // Opens the guide, through the shell so it knows; watching if asked.
  function summonGuide(watch) {
    var payload = JSON.stringify({ watch: watch })
    if (root.shell && typeof root.shell.summon === "function") root.shell.summon((root.manifest && root.manifest.id) || "marcho78.om-pg", payload)
    else root.open(payload)
  }

  // POWER (or a channel number) with the TV off: on, full screen.
  function remotePowerOn(r) {
    if (r < 0) r = root.tunedRow >= 0 ? root.tunedRow : (root.visibleRows[0] || 0)
    if (!root.streamOk(r, function() { root.remotePowerOn(r) })) return
    root.summonGuide(root.tune(r) === "ok")
  }

  // A button on a phone, doing what the same key would on the TV.
  function remoteCommand(cmd, number, by, digits) {
    // the phone is you too: it ends an agent's open of an app
    if (by === root.byUser && appViewItem.agentOpen) appViewItem.userActs()
    // Omarchy's screen saver is up: a key closes it (a phone press can't yet)
    if (nativeSaverItem.up || nativeSaverItem.settling) return "Omarchy's screen saver is up"
    if (by === root.byUser) {
      // a press on your phone is you here: Hyprland's idle timers start over
      // as for a key (a hold, like a playing video's, still wins)
      if (Hyprland.usingLua) Hyprland.dispatch("hl.dsp.force_idle(0)")
      if (screenSaverItem.showing || screenSaverItem.settling) { screenSaverItem.wake(); return "woke the screen saver" }
      screenSaverItem.activity()
    }
    if (root.splash && root.splash.running) { root.splash.skip(); return "skipped the splash" }
    var on = root.reception !== "off"
    // the channel lock's box takes the buttons (it shows over a playing picture too)
    // while the computer's password is asked for, the phone waits
    if (root.authBusy) return "the computer's password is being asked for"
    if (channelLockItem.boxUp && by === root.byUser) { channelLockItem.remote(cmd, digits); return }
    if (cmd === "code") return   // a passcode with nothing asking for it
    // the strip's question (Home or the guide): TURN ON and DISMISS, as Y and N
    if (cmd === "yes" || cmd === "no") {
      if (root.stripAsks !== "" && root.stripPlace) root.stripAnswer(cmd === "yes")
      return
    }
    // a box that isn't on the screen (the TV's playing, or the guide's away)
    // isn't yours: it goes, and doesn't take the button
    if (root.dialog && root.dialog !== "style" && !root.boxShown()) root.closeDialog()
    // An app on the screen: BACK or GUIDE brings the guide back over it
    // (while one's opening, BACK stops waiting)
    if (root.appOpening) { if (cmd === "back") root.cancelAppOpen(); return }
    if (root.appUp && !root.opened && (cmd === "back" || cmd === "guide")) { root.summonBack(); return }
    // Multiview up: its tiles take the buttons (power stops them all)
    if (root.multiview && root.multiview.active && root.multiview.remote(cmd, number)) return
    if (cmd === "power") {
      if (!on) root.remotePowerOn(-1)
      else if (root.pip) root.closePip()
      else root.dismiss()
      return
    }
    if (cmd === "mute") { root.muted = !root.muted; return }
    if (cmd === "tune") {
      var i = root.numbers.indexOf(Number(number))
      if (i < 0) return
      if (root.askToWatch(i, function() { root.remoteCommand("tune", number, by) })) return
      if (!on && !root.opened) { root.remotePowerOn(i); return }
      if (!root.streamOk(i, function() { root.remoteCommand("tune", number, by) })) return
      if (root.tune(i) !== "ok") return
      if (root.pip) root.showPipBanner()
      else if (root.watching) root.showBanner()
      else if (root.opened) { root.row = i; root.showRow(i) }
      return
    }
    if (cmd === "guide") {
      if (root.pip) root.guidePip()
      else if (root.watching) root.showGuide()
      else if (!root.opened) root.summonGuide(false)
      else if (root.screen !== "guide") root.closeLibrary()
      return
    }
    if (cmd === "mini") { if (on || root.opened) root.goPip(); return }
    if (cmd === "full") {
      if (root.pip) root.expandPip()
      else if (root.opened && !root.watching) root.watch(root.row)
      else if (!root.opened) root.remotePowerOn(-1)
      return
    }
    // The apps boxes: the d-pad picks, OK says it (a paired phone is yours)
    if (["appsOn", "unknownOn", "devOn", "appCatalog", "appReview", "appInfo"].indexOf(root.dialog) >= 0) {
      if (appsStore.installing || (appsStore.inspecting && root.dialog !== "appInfo")) return
      if (cmd === "up") root.moveApps(-1, by)
      else if (cmd === "down") root.moveApps(1, by)
      else if (cmd === "ok") root.appsAct(by)
      else if (cmd === "back") root.appsEscape()
      return
    }
    // Customize open (an app's screen's, or Home's): the phone's arrows, OK
    // and BACK drive it, as the keys do (typing a name needs the keyboard)
    if (root.opened && !root.watching && appPanelItem.open && !root.dialog) {
      if (appPanelItem.renaming) { if (cmd === "back") appPanelItem.close(); return }
      if (cmd === "up") appPanelItem.move(-1)
      else if (cmd === "down") appPanelItem.move(1)
      else if (cmd === "left") appPanelItem.act(-1)
      else if (cmd === "right") appPanelItem.act(1)
      else if (cmd === "ok") appPanelItem.act(0)
      else if (cmd === "back") appPanelItem.close()
      return
    }
    if (root.opened && !root.watching && root.screen === "home" && root.homeEditing && !root.dialog) {
      if (root.homeRenaming) { if (cmd === "back") root.closeHomePanel(); return }
      if (cmd === "up") root.moveHomePanel(-1)
      else if (cmd === "down") root.moveHomePanel(1)
      else if (cmd === "left") root.homePanelAct(-1)
      else if (cmd === "right" || cmd === "ok") root.homePanelAct(1)
      else if (cmd === "back") root.closeHomePanel()
      return
    }
    // ⋯ (Options): what C does, on Home and on an app's screen
    if (cmd === "options") {
      if (root.dialog || root.railOpen) return
      // as I: the mini player's bar; full screen, the player bar or the banner's choices
      if (root.pip) { if (!root.streamAsk) root.showPipBanner(); return }
      if (root.watching) { root.vod ? root.showVodBar() : root.bannerOptions ? root.hideBanner() : root.openBannerOptions(); return }
      if (!root.opened) return
      if (root.screen === "home" && !root.homeEditing) root.openHomePanel()
      else if (root.screen === "guide") root.openShowChoices()
      else if (root.screen === "app" && !appViewItem.settingsOpen && !appViewItem.signIn && !appViewItem.editing) appPanelItem.openFor(appViewItem.appId, by)
      return
    }
    if (root.dialog === "showChoices") {   // a show's choices: the d-pad picks, OK says it, BACK closes
      if (cmd === "up") root.moveShowChoice(-1)
      else if (cmd === "down") root.moveShowChoice(1)
      else if (cmd === "ok") root.showChoiceAct()
      else if (cmd === "back") root.closeShowChoices()
      return
    }
    if (root.dialog === "recStream") {   // a 2nd stream from a recording's provider: OK watches anyway, BACK stays
      if (cmd === "ok") root.answerStream(true)
      else if (cmd === "back") root.answerStream(false)
      return
    }
    if (root.dialog && root.dialog !== "remote") {   // a box is open on the TV: BACK closes it
      if (cmd === "back") root.closeDialog()
      return
    }
    if (cmd === "chup" || cmd === "chdown") {
      var d = cmd === "chup" ? 1 : -1
      if (root.pip) root.pipSurf(d)
      else if (on || root.opened) {
        root.surf(d)
        if (root.opened && !root.watching) { root.row = root.tunedRow; root.showRow(root.row) }
      }
      return
    }
    if (root.pip && root.streamAsk) {   // the mini player asks (a 2nd stream): OK watches anyway, BACK stays
      if (cmd === "ok") root.answerStream(true)
      else if (cmd === "back") root.answerStream(false)
      return
    }
    if (root.vod && (root.watching || root.pip)) {
      if (cmd === "left") root.seekVod(-10)
      else if (cmd === "right") root.seekVod(10)
      else if (cmd === "ok") root.togglePause()
      else if (cmd === "back") root.stopVod()
      return
    }
    if (root.pip) {
      if (cmd === "up") root.pipSurf(1)
      else if (cmd === "down") root.pipSurf(-1)
      else if (cmd === "ok") root.expandPip()
      else if (cmd === "back") root.guidePip()
    } else if (root.watching && root.bannerOptions) {
      // the banner's choices: ◀ ▶ choose, OK picks, ▼ or BACK closes them
      if (cmd === "left") root.moveBannerAct(-1)
      else if (cmd === "right") root.moveBannerAct(1)
      else if (cmd === "ok") root.pickBannerAct()
      else if (cmd === "down" || cmd === "back") root.bannerBack()
    } else if (root.watching) {
      // ▲ opens the banner's choices (the keys' I or Space); ◀ ▶ change channel
      if (cmd === "up") root.openBannerOptions()
      else if (cmd === "left") root.surf(-1)
      else if (cmd === "right") root.surf(1)
      else if (cmd === "ok") root.showBanner()
      else if (cmd === "back") root.showGuide()
    } else if (root.opened && root.dialog === "remote") {
      if (cmd === "up" && root.remoteStep === "on") root.movePhones(-1)
      else if (cmd === "down" && root.remoteStep === "on") root.movePhones(1)
      else if (cmd === "ok" && root.remoteStep === "on") root.unpairAct()
      else if (cmd === "back") root.closeDialog()
    } else if (root.opened && root.libDetail && (root.screen === "library" || root.screen === "search")) {
      if (cmd === "up") root.libEpisodeMove(-1)
      else if (cmd === "down") root.libEpisodeMove(1)
      else if (cmd === "ok") root.libDetailOk()
      else if (cmd === "back") root.libDetail = null
    } else if (root.opened && root.screen === "search" && !root.railOpen && !root.railEditing) {
      if (cmd === "up") root.moveSearch(-1, 0)
      else if (cmd === "down") root.moveSearch(1, 0)
      else if (cmd === "left") { if (root.searchAtLeft()) root.openRail(); else root.moveSearch(0, -1) }
      else if (cmd === "right") root.moveSearch(0, 1)
      else if (cmd === "ok") root.searchEnter()
      else if (cmd === "back") { if (root.searchInResults) root.searchInResults = false; else root.leaveSearch() }
    } else if (root.opened && root.railEditing) {
      if (cmd === "up") root.moveRailPanel(-1)
      else if (cmd === "down") root.moveRailPanel(1)
      else if (cmd === "ok" || cmd === "right") root.railPanelAct(1)
      else if (cmd === "left") root.railPanelAct(-1)
      else if (cmd === "back") root.closeRailPanel()
    } else if (root.opened && root.railOpen) {
      // The nav rail: up and down pick, OK goes, BACK or left closes it
      if (cmd === "up") root.moveRail(-1)
      else if (cmd === "down") root.moveRail(1)
      else if (cmd === "ok" || cmd === "right") root.railGo()
      else if (cmd === "back" || cmd === "left") root.closeRail()
    } else if (root.opened && root.screen === "settings" && !root.settingsInRows) {
      // Settings' parts: up and down pick one, OK or right goes into it
      if (cmd === "up") root.moveSettingsPart(-1)
      else if (cmd === "down") root.moveSettingsPart(1)
      else if (cmd === "ok" || cmd === "right") root.settingsInto()
      else if (cmd === "left") root.openRail()
      else if (cmd === "back") root.leaveSettings()
    } else if (root.opened && root.screen === "settings") {
      if (cmd === "up") root.moveSettings(-1)
      else if (cmd === "down") root.moveSettings(1)
      else if (cmd === "ok" || cmd === "right") root.changeSetting(1, by)
      else if (cmd === "left" || cmd === "back") root.settingsOut()
    } else if (root.opened && root.appPlaying) {
      if (cmd === "ok") appPlaybackItem.togglePause()
      else if (cmd === "left") appPlaybackItem.seek(-10)
      else if (cmd === "right") appPlaybackItem.seek(10)
      else if (cmd === "back") appPlaybackItem.close("user", null)
    } else if (root.opened && root.screen === "app") {
      var av = appViewItem
      if (av.signIn) {
        if (cmd === "back") av.signInBack()
        else if (cmd === "up" || cmd === "down") av.signInMove(cmd === "up" ? -1 : 1)
        else if (cmd === "ok") av.signInAct(by)
        return
      }
      if (av.editing) { if (cmd === "back") av.back(); return }
      if (av.settingsOpen) {
        if (cmd === "up") av.moveSettings(-1)
        else if (cmd === "down") av.moveSettings(1)
        else if (cmd === "left") av.settingsAct(-1, by)
        else if (cmd === "right") av.settingsAct(1, by)
        else if (cmd === "ok") av.settingsAct(0, by)
        else if (cmd === "back") av.back()
        return
      }
      if (cmd === "back") av.back()
      else if (cmd === "ok") av.enter(by)
      else if (cmd === "left") { if (!av.move("left")) root.openRail() }
      else if (["up", "down", "right"].indexOf(cmd) >= 0) av.move(cmd)
    } else if (root.opened && root.screen === "apps") {
      if (cmd === "up") root.moveAppsTile(0, -1)
      else if (cmd === "down") root.moveAppsTile(0, 1)
      else if (cmd === "left") { if (root.appsTile % root.appsCols !== 0 || !root.openRail()) root.moveAppsTile(-1, 0) }
      else if (cmd === "right") root.moveAppsTile(1, 0)
      else if (cmd === "ok") root.appsTileAct(false, by)
      else if (cmd === "back") root.leaveApps()
    } else if (root.opened && root.screen === "home") {
      // Home: the arrows move, OK opens what's selected
      if (root.homeEditing) { if (cmd === "back") root.closeHomePanel(); return }
      if (cmd === "up") root.moveHome(-1, 0)
      else if (cmd === "down") root.moveHome(1, 0)
      else if (cmd === "left") { if (!root.homeAtLeft() || !root.openRail()) root.moveHome(0, -1) }
      else if (cmd === "right") root.moveHome(0, 1)
      else if (cmd === "ok") root.homeOpen()
    } else if (root.opened && root.screen === "library") {
      // The library: OK opens details, then plays; BACK goes back
      if (root.libDetail) {
        if (cmd === "ok") root.libDetailOk()
        else if (cmd === "back") root.libDetail = null
        else if (cmd === "up") root.libEpisodeMove(-1)
        else if (cmd === "down") root.libEpisodeMove(1)
      } else {
        if (cmd === "up") root.moveLib(-1, 0)
        else if (cmd === "down") root.moveLib(1, 0)
        else if (cmd === "left") { if (!root.libAtLeft() || !root.openRail()) root.moveLib(0, -1) }
        else if (cmd === "right") root.moveLib(0, 1)
        else if (cmd === "ok") root.libEnter()
        else if (cmd === "back") root.leaveLibrary()
      }
    } else if (root.opened) {
      if (cmd === "up") root.moveRow(-1)
      else if (cmd === "down") root.moveRow(1)
      else if (cmd === "left") { if (!root.guideAtLeft() || !root.openRail()) root.moveTime(-1) }
      else if (cmd === "right") root.moveTime(1)
      else if (cmd === "ok") root.watch(root.row)
      else if (cmd === "back" && root.homeEnabled) root.openHome()
    }
  }

  onOpenedChanged: remoteStateTimer.restart()
  onScreenChanged: remoteStateTimer.restart()
  onVodPausedChanged: remoteStateTimer.restart()
  onWatchingChanged: {
    remoteStateTimer.restart()
    // a channel from the guide's preview (on, or still tuning), now full screen: through pause and rewind's buffer
    if (watching && timeshift.turnedOn && !timeshift.busy && !vod && (reception === "on" || reception === "tuning") && tunedRow >= 0 && timeshift.takes(onAir)) root.tune(tunedRow)
  }
  onPipChanged: remoteStateTimer.restart()
  onMutedChanged: remoteStateTimer.restart()
  onChannelsChanged: remoteStateTimer.restart()
  onRecBadgeChanged: remoteStateTimer.restart()
  onStripAsksChanged: remoteStateTimer.restart()
  onStripPlaceChanged: remoteStateTimer.restart()
  // pause and rewind on the phone: paused, live, or behind (told again when
  // that moves by 15 s, a seek; not each second)
  readonly property string remotePause: timeshift.active && !vod ? (timeshift.paused ? "paused" : timeshift.atLive ? "live" : "behind " + Math.round(timeshift.behind / 15000)) : ""
  onRemotePauseChanged: remoteStateTimer.restart()
  onVisibleRowsChanged: remoteStateTimer.restart()

  // Media keys and the bar (MPRIS)

  // What's on, for the helper to show as the media player's track.
  function sendMpris() {
    if (!streamer.running || !root.port) return
    // Multiview has the playback: the tile with the sound, playing or paused,
    // so media keys and the bar's widget still find Uber TV
    if (root.multiview && root.multiview.active) {
      var mt = root.multiview.tileIn(root.multiview.sel)
      var mr = root.multiview.rowOf(root.multiview.sel), mch = root.channels[mr]
      streamer.write(JSON.stringify({ mpris: {
        active: true,
        status: root.multiview.paused ? "Paused" : "Playing",
        id: mt.onAir ? mt.onAir.id || "" : "",
        title: mt.onAir ? root.showTitle(mt.onAir.title) : "",
        artist: mch ? "Multiview · CH " + root.numbers[mr] + " · " + mch.name : "Multiview",
        album: mch && mch.category ? mch.category : "",
        length: 0, position: 0,
        channelId: mch ? mch.channelId || "" : "",
        canSeek: false
      } }) + "\n")
      return
    }
    var ch = root.channels[root.tunedRow]
    var on = root.reception !== "off" && !!root.onAir
    var paused = player.playbackState === MediaPlayer.PausedState
    var vod = on && root.vod ? root.vod : null
    streamer.write(JSON.stringify({ mpris: {
      active: on,
      status: !on ? "Stopped" : paused ? "Paused" : "Playing",
      id: on ? root.onAir.id : "",
      title: on ? root.showTitle(root.onAir.title) : "",
      artist: vod ? vod.subtitle || "" : on && ch ? "CH " + root.numbers[root.tunedRow] + " · " + ch.name : "",
      album: vod ? "" : on && ch && ch.category ? ch.category : "",
      length: vod ? Math.round(player.duration * 1000) : on && !root.onAir.live ? Math.round((root.onAir.end - root.onAir.start) * 1000000) : 0,
      position: on ? Math.round(player.position * 1000) : 0,
      channelId: on && ch && !vod ? (ch.channelId || "") : "",
      canSeek: !!vod
    } }) + "\n")
  }

  function mprisCommand(cmd, message) {
    if (multiviewItem.active) { multiviewItem.media(cmd); return }   // the tiles, not the TV's stopped player
    if (root.reception === "off") return
    if (root.vod && cmd === "seek") { root.seekVod(Number(message && message.by) / 1e6 || 0); return }
    if (root.vod && cmd === "setPosition") { root.seekVodTo(Number(message && message.to) / 1e6 || 0); return }
    if (root.vod && (cmd === "next" || cmd === "previous")) { root.seekVod(cmd === "next" ? 30 : -10); return }
    if (cmd === "next" || cmd === "previous") {
      var delta = cmd === "next" ? 1 : -1
      if (root.pip) root.pipSurf(delta)
      else {
        root.surf(delta)
        if (!root.watching) { root.row = root.tunedRow; root.showRow(root.row) }
      }
    } else if (timeshift.active && (cmd === "playpause" || cmd === "play" || cmd === "pause")) {
      // pause and rewind: its own pause, so its clock and Resume follow
      if (cmd === "playpause") timeshift.togglePause()
      else if (cmd === "play") { if (timeshift.paused) timeshift.resume() }
      else timeshift.pause()
    } else if (cmd === "playpause") {
      if (player.playbackState === MediaPlayer.PlayingState) player.pause()
      else player.play()
    } else if (cmd === "play") {
      player.play()
    } else if (cmd === "pause") {
      player.pause()
    } else if (cmd === "stop") {
      root.turnOff()
    } else if (cmd === "raise") {
      if (root.pip) root.guidePip()
    }
  }

  onOnAirChanged: { Qt.callLater(root.sendMpris); remoteStateTimer.restart() }
  Connections {
    target: multiviewItem
    function onActiveChanged() { Qt.callLater(root.sendMpris) }
    function onSelChanged() { Qt.callLater(root.sendMpris) }
    function onSlotsChanged() { Qt.callLater(root.sendMpris) }
    function onPausedChanged() { Qt.callLater(root.sendMpris) }
  }
  onReceptionChanged: { Qt.callLater(root.sendMpris); remoteStateTimer.restart() }
  onTunedRowChanged: { Qt.callLater(root.sendMpris); remoteStateTimer.restart() }

  function showPipBanner() {
    root.pipBannerShown = true
    pipBannerTimer.restart()
  }

  Timer {
    id: seekGap
    interval: 300
    onTriggered: root.applySeek()
  }

  // The system's default sound output: the TV's sound follows it, so
  // switching outputs is picked up (a sound server that restarts isn't: Qt
  // keeps its old device list until the shell restarts)
  MediaDevices { id: audioDevices }

  MediaPlayer {
    id: player
    videoOutput: video
    audioOutput: AudioOutput { device: audioDevices.defaultAudioOutput; muted: root.muted || splashItem.running }
    onMediaStatusChanged: {
      if (timeshift.mediaStatus(mediaStatus)) return      // pause and rewind's buffer: its own handling
      if (mediaStatus === MediaPlayer.LoadedMedia && root.reception === "tuning" && root.onAir.vod) {
        // On demand: from where you stopped, or the start
        if (root.onAir.resumeAt > 0) player.position = Math.floor(root.onAir.resumeAt * 1000)
        player.play()
        root.started = true
      } else if (mediaStatus === MediaPlayer.EndOfMedia && root.onAir && root.onAir.vod && root.started) {
        // The end: it's finished; back to where you came from
        if (root.vod) library.record(root.vod, player.duration / 1000, player.duration / 1000)
        root.stopVod()
      } else if (mediaStatus === MediaPlayer.LoadedMedia && root.reception === "tuning") {
        // Join the broadcast where it is now, not where it was when tuning
        // began. A live stream already starts at the live edge.
        var into = Date.now() / 1000 - root.onAir.start
        if (!root.onAir.live && into > 3) player.position = Math.floor(into * 1000)
        if (root.onAir.iptv) root.pickBestTrack()
        player.play()
        root.started = true
      } else if (mediaStatus === MediaPlayer.BufferedMedia && root.reception === "tuning" && root.started) {
        root.reception = "on"
      } else if (mediaStatus === MediaPlayer.EndOfMedia && root.reception === "on" && root.onAir.iptv) {
        // An IPTV stream dropped: try it once more, then call it lost.
        if (root.iptvRetried) root.reception = "lost"
        else { root.tune(root.tunedRow, 0, true); root.iptvRetried = true }
      } else if (mediaStatus === MediaPlayer.EndOfMedia && root.reception === "on" && root.onAir.live) {
        // The live stream ended: back to the channel's videos, and look again.
        root.liveEnded(root.tunedRow)
        if (root.tune(root.tunedRow) !== "ok") root.reception = "lost"
      } else if (mediaStatus === MediaPlayer.EndOfMedia && root.reception === "on") {
        root.tune(root.tunedRow, Math.max(Date.now() / 1000, root.onAir.end + 1))
      } else if (mediaStatus === MediaPlayer.InvalidMedia) {
        root.reception = "lost"
      }
    }
    // Buffered can lag well behind the picture; playback moving counts too.
    // Only once this stream has been started: swapping streams sends a last
    // position update while the old one still looks like it's playing.
    onPositionChanged: {
      if (root.reception === "tuning" && root.started
          && playbackState === MediaPlayer.PlayingState
          && (mediaStatus === MediaPlayer.BufferingMedia || mediaStatus === MediaPlayer.BufferedMedia))
        root.reception = "on"
    }
    onPlaybackStateChanged: {
      Qt.callLater(root.sendMpris)
      if (root.vod) {
        root.vodPaused = playbackState === MediaPlayer.PausedState
        if (root.vodPaused && root.started && player.duration > 0) library.record(root.vod, player.position / 1000, player.duration / 1000)
      }
    }
    onErrorOccurred: function(error, message) {
      console.warn("om-pg: player: " + message)
      if (timeshift.error()) return                       // the buffer reopens, or plays the channel directly
      root.reception = "lost"
    }
  }

  Process {
    id: streamer
    command: ["/usr/bin/python3", root.pluginDir + "/bin/om-pg-streamer"]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) {
        if (String(line).charAt(0) === "{") {   // a media key, the bar, or another MPRIS client
          try { var message = JSON.parse(line); root.mprisCommand(message.mpris, message) } catch (e) {}
          return
        }
        var parts = String(line).trim().split(" ")
        root.port = parseInt(parts[0]) || 0
        root.streamBase = root.port && parts[1] ? "http://127.0.0.1:" + root.port + "/" + parts[1] : ""
        root.play()
        root.warm()
        root.sendMpris()
      }
    }
    stderr: SplitParser {
      onRead: function(line) { console.warn("om-pg: streamer: " + line) }
    }
    onExited: {
      root.port = 0
      root.streamBase = ""
    }
  }

  // Channels go live and stop; look again every 15 minutes while open.
  Timer {
    interval: 15 * 60 * 1000
    repeat: true
    running: root.opened
    onTriggered: root.checkLive()
  }

  // The channels you watched last, saved a moment after (not on every surf)
  Timer {
    id: recentSaver
    interval: 5000
    onTriggered: root.saveSettings()
  }

  // Where you are in a VOD, every ten seconds while it plays
  Timer {
    interval: 10000
    repeat: true
    running: root.vod !== null && root.started && !root.vodPaused
    onTriggered: if (root.vod && player.duration > 0) library.record(root.vod, player.position / 1000, player.duration / 1000)
  }

  // The VOD bar goes after a moment, unless it's paused
  Timer {
    id: vodBarTimer
    interval: 4000
    onTriggered: root.vodBarShown = false
  }

  Timer {
    id: reload
    interval: 250
    onTriggered: if (root.reception === "tuning" && root.streamUrl()) player.source = root.streamUrl()
  }

  // Pause and rewind's buffer fills under its own deadline: the watchdog
  // starts once a playlist is handed to the player
  function tuneWatch(on) { if (on) tuneWatchdog.restart(); else tuneWatchdog.stop() }
  // The setting or the place changed: the buffer goes, and the channel on
  // is tuned again (through a new buffer, or directly)
  function timeshiftChanged() {
    if (root.reception === "off" || root.vod || root.tunedRow < 0) return
    if (!timeshift.busy && !(timeshift.turnedOn && root.watching && Ts.supported(root.onAir))) return
    var row = root.tunedRow
    timeshift.end(function() { if (root.reception !== "off" && !root.vod && root.tunedRow === row) root.tune(row) })
  }

  // A channel that hasn't started in this long isn't going to.
  Timer {
    id: tuneWatchdog
    interval: 20000
    onTriggered: if (root.reception === "tuning") root.reception = "lost"
  }

  // The channel-change card shows for at least this long, like a TV ident.
  Timer {
    id: identHold
    interval: root.cardSeconds * 1000
  }

  Timer {
    id: previewTimer
    interval: 600
    onTriggered: root.previewRow()
  }

  Timer {
    id: warmTimer
    interval: 1500
    onTriggered: root.warm()
  }

  // The phone remote's server, while it's on
  Process {
    id: remoteHelper
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.remoteHeard(line, root.byUser) }
    }
    stderr: SplitParser {
      onRead: function(line) { console.warn("om-pg: remote: " + line) }
    }
    onExited: {
      root.remoteReady = false
      root.remotePairing = null
      if (!root.remoteStopping && root.remoteEnabled) {
        root.remoteEnabled = false
        root.saveSettings()
        if (!root.remoteMessage) root.remoteMessage = "The phone remote stopped unexpectedly."
        if (root.remoteStep === "on") root.remoteStep = ""
      }
    }
  }

  // The network the remote would serve, read without opening anything
  Process {
    id: remoteProbe
    command: ["/usr/bin/python3", root.pluginDir + "/bin/om-pg-remote", "--probe", String(root.remotePort)]
    stdout: SplitParser {
      onRead: function(line) { root.remoteHeard(line, root.byUser) }
    }
  }

  // Whether the firewall is on (Omarchy's is, out of the box)
  Process {
    id: ufwCheck
    command: ["/usr/bin/systemctl", "is-active", "--quiet", "ufw"]
    onExited: function(code) { root.firewallActive = code === 0 }
  }

  // The password prompt and the firewall change
  Process {
    id: firewallRun
    onExited: function(code) { root.firewallDone(code, root.byUser) }
  }

  Timer {
    id: remoteStateTimer
    interval: 400
    onTriggered: root.sendRemoteState()
  }

  // Keeps the phones' "what's on now" current, and the code's countdown ticking.
  Timer {
    interval: 1000
    repeat: true
    running: root.remoteReady
    property int ticks: 0
    onTriggered: {
      root.remoteClock = Date.now() / 1000
      if (++ticks % 60 === 0) root.sendRemoteState()
    }
  }

  Run {
    id: pointerProbe
    timeoutMs: 2000
    maxBytes: 1024
    onFinished: function(ok, output) { if (ok) root.pointerAt(output) }
  }

  Timer {
    interval: 250
    repeat: true
    running: root.pip
    onTriggered: if (!pointerProbe.running) pointerProbe.start(["/usr/bin/hyprctl", "cursorpos"])
    onRunningChanged: if (!running) root.pipPointerIn = false
  }

  FileView {
    id: listingCache
    path: root.cacheDir + "/listings.json"
    printErrors: false   // not having one yet is normal
    onLoaded: root.loadListingCache(text())
  }

  // Saves a couple of seconds after listings stop arriving.
  Timer {
    id: cacheTimer
    interval: 2000
    onTriggered: root.saveListingCache()
  }

  Timer {
    id: pipBannerTimer
    interval: 3500
    onTriggered: root.pipBannerShown = false
  }

  // Keeps the media player's position honest while the TV is on.
  Timer {
    interval: 5000
    repeat: true
    running: root.reception !== "off"
    onTriggered: root.sendMpris()
  }

  Timer {
    id: keyHintsNoteTimer
    interval: 4000
    onTriggered: root.keyHintsNote = false
  }

  Timer {
    id: bannerTimer
    interval: root.bannerOptions ? 10000 : root.ltSeconds * 1000   // choosing: ten seconds from the last key
    onTriggered: { root.bannerShown = false; root.bannerOptions = false; root.recStopMenu = false; root.streamAsk = null }
  }

  // yt-dlp, by its path ("--": a URL can never be read as an option, some
  // run code), its output bounded
  Component {
    id: fetcher
    Run {
      id: proc
      property string url: ""
      property string mode: "listing"
      timeoutMs: 180000
      maxBytes: 16 * 1024 * 1024
      okCodes: [0, 1]               // 1: some entries failed; what it printed still counts
      splitMarker: "\n"
      onFinished: function(ok, output) {
        var text = ok ? output : ""
        root.inFlight--
        if (proc.mode === "check") root.checked(proc.url, text)
        else if (proc.mode === "search") root.searched(proc.url, text)
        else if (proc.mode === "live") root.liveChecked(proc.url, text)
        else root.received(proc.url, text)
        root.pump()
        Qt.callLater(function() { proc.destroy() })
      }
    }
  }

  FileView {
    id: ownList
    path: root.listPath
    printErrors: false   // not having one yet is normal
    watchChanges: true
    onFileChanged: ownList.reload()
    onSaved: privateList.running = true   // saving replaces the file, so after it
    onLoaded: {
      root.ownListMissing = false
      if (text() === root.lastSaved) return
      if (root.loadChannels(text())) { root.listProblem = ""; return }
      // unreadable: the starter list to watch, and that file kept as it is
      root.listProblem = "Your channel list (channels.json) wasn't read (it isn't a valid list): the guide shows its starter channels, and keeps that file as it is (changes aren't saved until it's fixed or moved away)."
      if (!root.channels.length && root.defaultList) root.loadChannels(root.defaultList)
    }
    onLoadFailed: {
      root.listProblem = ""
      root.ownListMissing = true
      if (root.defaultList) root.loadChannels(root.defaultList)
    }
  }

  // Hidden folders and build trees are skipped, and so are config files that
  // are never channel lists. Its output is bounded, like every command's here.
  Run {
    id: finder
    timeoutMs: 60000
    maxBytes: 8 * 1024 * 1024
    okCodes: [0, 1]                 // 1: some folders couldn't be read
    splitMarker: "\n"
    // Pictures are also looked for in Omarchy's backgrounds, which are in hidden folders.
    readonly property var argv: root.pickSignedApps
      ? ["/usr/bin/find", Quickshell.env("HOME"), "-maxdepth", "6",
              "(", "-name", ".*", "-o", "-name", "node_modules", "-o", "-name", "target", "-o", "-name", "venv",
                   "-o", "-name", "__pycache__", "-o", "-name", "vendor", ")", "-prune", "-o",
              "-type", "f", "-iname", "*.tvapp", "-size", "-26M", "-printf", "%T@\t%p\n"]
      : root.pickApps
      ? ["/usr/bin/find", Quickshell.env("HOME"), "-maxdepth", "6",
              "(", "-name", ".*", "-o", "-name", "node_modules", "-o", "-name", "target", "-o", "-name", "venv",
                   "-o", "-name", "__pycache__", "-o", "-name", "vendor", ")", "-prune", "-o",
              "-type", "f", "(", "-iname", "*.tar.gz", "-o", "-iname", "*.tgz", "-o", "-name", "app.json", ")",
              "-size", "-21M", "-printf", "%T@\t%p\n"]
      : root.pickFolders
      ? ["/usr/bin/find", Quickshell.env("HOME"), "-maxdepth", "4",
              "(", "-name", ".*", "-o", "-name", "node_modules", "-o", "-name", "target", "-o", "-name", "venv",
                   "-o", "-name", "__pycache__", "-o", "-name", "vendor", ")", "-prune", "-o",
              "-type", "d", "-printf", "%T@\t%p\n"]
      : root.pickImages
      ? ["/usr/bin/find", Quickshell.env("HOME"), Quickshell.env("HOME") + "/.config/omarchy/backgrounds/",
              Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/backgrounds/", "-maxdepth", "6",
              "(", "-name", ".*", "-o", "-name", "node_modules", "-o", "-name", "target", "-o", "-name", "venv",
                   "-o", "-name", "__pycache__", "-o", "-name", "vendor", ")", "-prune", "-o",
              "-type", "f", "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", "-o", "-iname", "*.webp", ")",
              "-size", "-40M", "-printf", "%T@\t%p\n"]
      : ["/usr/bin/find", Quickshell.env("HOME"), "-maxdepth", "6",
              "(", "-name", ".*", "-o", "-name", "node_modules", "-o", "-name", "target", "-o", "-name", "venv",
                   "-o", "-name", "__pycache__", "-o", "-name", "vendor", ")", "-prune", "-o",
              "-type", "f", "(", "-iname", "*.csv", "-o", "-iname", "*.tsv", "-o", "-iname", "*.txt", "-o", "-iname", "*.json",
                   "-o", "-iname", "*.m3u", "-o", "-iname", "*.m3u8", ")",
              "-not", "-name", "package*.json", "-not", "-name", "tsconfig*.json", "-not", "-name", "jsconfig.json",
              "-not", "-name", "composer.json", "-not", "-name", "manifest.json", "-not", "-name", "*.lock.json",
              "-size", "-5M", "-printf", "%T@\t%p\n"]
    onFinished: function(ok, output) { root.filesFound(ok ? output : "") }
  }

  // One folder's contents, for Browse
  Run {
    id: browser
    timeoutMs: 15000
    maxBytes: 4 * 1024 * 1024
    okCodes: [0, 1]
    splitMarker: "\n"
    onFinished: function(ok, output) { root.entriesFound(ok ? output : "") }
  }

  Component {
    id: statter
    Run {
      id: st
      property string full: ""
      property string shown: ""
      timeoutMs: 5000
      maxBytes: 4096
      onFinished: function(ok, output) {
        root.statted(st.full, st.shown, ok ? output : "")
        Qt.callLater(function() { st.destroy() })
      }
    }
  }

  // A playlist link being fetched: http or https only, 20 MB and 30 s at most.
  Component {
    id: playlistFetcher
    Run {
      id: pf
      property string url: ""
      timeoutMs: 35000
      maxBytes: 21 * 1000 * 1000
      splitMarker: "\n"
      onFinished: function(ok, output) {
        root.playlistFetched(pf.url, ok ? output : "", ok ? 0 : 1)
        Qt.callLater(function() { pf.destroy() })
      }
    }
  }

  // IPTV links can hold logins, so the channel list is readable by you alone.
  Process {
    id: privateList
    command: ["/usr/bin/chmod", "600", root.listPath]
  }

  // A channel list being imported
  Component {
    id: reader
    FileView {
      id: file
      property string shown: ""
      printErrors: false
      onLoaded: {
        root.addCandidates(root.findChannels(text()), undefined, file.path)
        Qt.callLater(function() { file.destroy() })
      }
      onLoadFailed: {
        root.rejectAdd("Couldn't read " + file.shown + ".")
        Qt.callLater(function() { file.destroy() })
      }
    }
  }

  // A copy of the channel list from before the library took its movies
  Process {
    id: listBackup
    command: ["/usr/bin/cp", "-n", "--", root.listPath, root.listPath + ".before-library"]
    onExited: root.moveVod()
  }

  FileView {
    id: omarchyTheme
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    onLoaded: root.omarchyColors = Look.parseOmarchy(text())
  }

  // The guide's folders readable by you alone, and its settings
  Process {
    id: privateFolders
    command: ["/usr/bin/sh", "-c", "PATH=/usr/bin; for d in \"$@\"; do [ -d \"$d\" ] && [ ! -L \"$d\" ] && chmod 700 -- \"$d\"; done; true",
              "sh", root.configDir, root.cacheDir, appsStore.dataHome, appsStore.stateHome]
  }
  Process {
    id: privateSettings
    command: ["/usr/bin/chmod", "600", root.configDir + "/settings.json"]
  }
  // settings.json is written here, and read only through the helper's
  // bounded, no-follow path (at most 1 MiB; bin/om-pg-apps private-read):
  // over that, or not a plain file, the guide keeps what it has and says so
  FileView {
    id: settings
    path: root.configDir + "/settings.json"
    printErrors: false   // not having one yet is normal
    preload: false       // never read here
    onSaved: { privateSettings.running = true; if (!privateFolders.running) privateFolders.running = true }
  }
  property string settingsProblem: ""
  Run {
    id: settingsReader
    timeoutMs: 30000
    maxBytes: 2 * 1024 * 1024
    okCodes: [0, 1]
    splitMarker: "\n"
    onFinished: function(ok, output) {
      var res
      try { res = JSON.parse(String(output).trim().split("\n").pop()) } catch (e) { res = { ok: false, error: "the helper didn't answer" } }
      if (res.ok && res.text) { root.settingsProblem = ""; root.applySettings(res.text) }
      else {
        root.settingsProblem = res.ok ? "" : "Your settings file wasn't read (" + (res.error || "it couldn't be") + "): the guide uses its own settings, and keeps that file as it is (changes aren't saved until it's fixed or moved away)."
        root.settingsMissing()
      }
    }
  }
  function readSettings() { settingsReader.start(["/usr/bin/python3", appsStore.helper, "private-read", root.configDir + "/settings.json"]) }
  function applySettings(settingsText) {
      try {
        var saved = JSON.parse(settingsText)
        if (Array.isArray(saved.shownCategories)) root.shownCategories = saved.shownCategories.filter(function(c) { return typeof c === "string" })
        root.shownSource = ["youtube", "iptv"].indexOf(saved.sources) >= 0 ? saved.sources : "both"
        root.showLogos = saved.logos !== false
        root.showKeyHints = saved.keyHints !== false
        root.splashOn = saved.splash !== false
        root.railCredits = saved.railCredits !== false
        updatesItem.on = !!saved.updates && saved.updates.on === true
        updatesItem.asked = !!saved.updates && saved.updates.asked === true
        if (saved.remote) {
          var port = Number(saved.remote.port)
          root.remotePort = port >= 1025 && port <= 65535 ? port : 24750
          root.remoteRules = Array.isArray(saved.remote.rules)
            ? saved.remote.rules.filter(function(r) { return /^\d+\.\d+\.\d+\.\d+\/\d+ \d+$/.test(r) }) : []
          root.remoteEnabled = saved.remote.enabled === true
          if (root.remoteEnabled) root.startRemoteHelper()
        }
        root.lineupMode = saved.lineup === "latest" ? "latest" : "daily"
        if (saved.pip) {
          root.pipW = Number(saved.pip.width) || 0
          root.pipRight = Number(saved.pip.right) || 24
          root.pipBottom = Number(saved.pip.bottom) || 24
        }
        var colors = {}
        if (saved.colors && typeof saved.colors === "object")
          for (var c = 0; c < root.colorSlots.length; c++) {
            var v = saved.colors[root.colorSlots[c].key]
            if (typeof v === "string" && root.isHex(v)) colors[root.colorSlots[c].key] = v.toLowerCase()
          }
        root.colorOverrides = colors
        var images = {}
        if (saved.images && typeof saved.images === "object")
          for (var area in saved.images) {
            var img = root.checkedImage(saved.images[area], area, false)
            if (img) images[area] = img
          }
        root.imageOverrides = images
        root.elementOverrides = Look.checkElements(saved.elements, root.colorKeys, root.installedFonts).elements
        root.fontOverrides = Look.checkFonts(saved.fonts, root.installedFonts).fonts
        root.layoutOverrides = Look.checkLayout(saved.layout).layout
        if (saved.home && typeof saved.home === "object") {
          root.homeEnabled = saved.home.enabled !== false
          root.homeSections = root.checkedHomeSections(saved.home.sections) || root.defaultHomeSections
          if (Array.isArray(saved.home.tiles)) {
            var kinds = root.homeTileKinds.map(function(t) { return t.key })
            root.homeTiles = saved.home.tiles.filter(function(t, i, all) { return kinds.indexOf(t) >= 0 && all.indexOf(t) === i })
          }
          var hb = saved.home.background || {}
          var hmode = root.homeBgModes.indexOf(hb.mode) >= 0 ? hb.mode : "focus"
          // only a copy (or a theme's own picture) is shown; one from before
          // (any path) is checked and copied first, and shown once it's in
          var legacy = typeof hb.image === "string" && /^\/.+\.(jpe?g|png|webp)$/i.test(hb.image) && !root.homePictureOk(hb.image) ? hb.image : ""
          root.homeBackground = { mode: hmode, image: root.homePictureOk(hb.image) ? hb.image : "", dim: root.clamp(Number(hb.dim), 0, 0.95, 0.6) }
          if (root.homeBackground.mode === "image" && !root.homeBackground.image) root.homeBackground = { mode: "focus", image: "", dim: root.homeBackground.dim }
          if (legacy) Qt.callLater(function() { root.homePicture(legacy, hmode === "image" ? "image" : "") })
        }
        if (saved.multiview && saved.multiview.background && typeof saved.multiview.background === "object") {
          var mvsb = saved.multiview.background
          var mvsimg = root.homePictureOk(mvsb.image) ? mvsb.image : ""
          var mvscolor = root.solidHex(mvsb.color) ? mvsb.color.toLowerCase() : ""
          root.multiviewBackground = { mode: root.mvBgModes.indexOf(mvsb.mode) >= 0 && (mvsb.mode !== "image" || mvsimg) && (mvsb.mode !== "color" || mvscolor) ? mvsb.mode : "none",
                                       image: mvsimg, color: mvscolor, dim: root.clamp(Number(mvsb.dim), 0, 0.95, 0.6) }
        }
        root.resumeWatch = saved.resumeWatch === true
        if (Array.isArray(saved.recent)) root.recentChannels = saved.recent.filter(function(u) { return typeof u === "string" }).slice(0, 12)
        root.railSetup = root.checkedRailSetup(saved.rail)
        if (saved.display === "window" || saved.display === "full") { root.displayMode = saved.display; root.placeScreen() }
        root.awake = AwakeRules.checked(saved.awake)
        screenSaverItem.settings = SaverRules.checked(saved.screenSaver)
        if (screenSaverItem.settings.on) screenSaverItem.list()
        if (saved.listings && Array.isArray(saved.listings.sources))
          listings.sources = saved.listings.sources.filter(function(x) { return x && listings.checkSource(x.url) })
                                   .map(function(x) { return { url: listings.checkSource(x.url), from: x.from === "playlist" ? "playlist" : "you", added: Number(x.added) || 0 } }).slice(0, 20)
        if (saved.search && Array.isArray(saved.search.recent))
          root.recentSearches = saved.search.recent.filter(function(q) { return typeof q === "string" && q.trim() }).map(function(q) { return q.slice(0, 80) }).slice(0, 8)
        if (saved.videos && typeof saved.videos === "object") {
          videos.enabled = saved.videos.enabled !== false
          videos.folder = typeof saved.videos.folder === "string" && saved.videos.folder.charAt(0) === "/" ? saved.videos.folder : ""
        } else if (saved.home && typeof saved.home === "object") {
          // My Videos is new to these settings: its tile and row join Home
          if (root.homeTiles.indexOf("videos") < 0)
            root.homeTiles = root.homeTileKinds.map(function(t) { return t.key }).filter(function(t) { return t === "videos" || root.homeTiles.indexOf(t) >= 0 })
          if (!root.homeSections.some(function(x) { return x.type === "videos" })) {
            var hs = root.homeSections.slice()
            var after = -1
            for (var hi = 0; hi < hs.length; hi++) if (hs[hi].type === "latest" || hs[hi].type === "continue") after = hi
            hs.splice(after + 1, 0, { type: "videos", on: true })
            root.homeSections = hs
          }
        }
        dvr.settings = DvrRules.checked(saved.dvr)
        if (Array.isArray(saved.libraryTabs)) root.libraryOrder = root.checkedLibraryOrder(saved.libraryTabs)
        if (saved.background) {
          root.bgFrom = Look.bgProvenance(saved.background.from)
          root.bgImage = typeof saved.background.image === "string" && saved.background.image.charAt(0) === "/" ? saved.background.image : ""
          root.bgMode = saved.background.mode === "wallpaper" || (saved.background.mode === "image" && root.bgImage) ? saved.background.mode : "none"
          root.bgDim = root.clamp(Number(saved.background.dim), 0, 0.95, 0.6)
        }
        if (saved.lowerThird) {
          root.ltShow = saved.lowerThird.show !== false
          root.ltSeconds = root.clamp(Number(saved.lowerThird.seconds), 1, 15, 4)
        }
        if (saved.card) {
          root.cardShow = saved.card.show !== false
          root.cardSeconds = root.clamp(Number(saved.card.seconds), 0.6, 5, 1.4)
        }
        // (settings from before themes had Retro: they keep it)
        root.themeId = typeof saved.theme === "string" && root.themeIdFrom(saved.theme) === saved.theme ? saved.theme : "retro"
        root.beforeReset = root.checkedSnapshot(saved.beforeReset)
        if (saved.bar) {
          root.barIcon = saved.bar.icon !== false
          if (typeof saved.bar.shortcut === "string" && (saved.bar.shortcut === "" || Shortcut.parse(saved.bar.shortcut))) root.shortcut = saved.bar.shortcut
        }
        // asked already, unless a first start left them for its next open
        root.demoAsked = !(saved.firstStart && saved.firstStart.demo === false)
        root.appsAsked = !(saved.firstStart && saved.firstStart.apps === false)
        // Recordings asked about once, whether a first start or an update (on already: nothing to ask)
        root.recAsked = !!(saved.firstStart && saved.firstStart.recordings === true) || dvr.settings.on
        if (saved.agent) {
          root.agentSkill = saved.agent.skill === true
          root.agentAsked = saved.agent.asked === true
          root.agentSettled = saved.agent.settled === true
        }
      } catch (e) {}
      root.settingsLoaded = true
      root.linkSkill()
      videos.scan()
      listings.freshen()
      dvr.loaded = true
  }
  function settingsMissing() {
      root.settingsLoaded = true
      dvr.loaded = true
      // a first start: the default theme, and the demo channels and apps to ask about
      root.demoAsked = false
      root.appsAsked = false
      root.recAsked = false
      root.saveSettings()
      root.putDefaultTheme()
      root.linkSkill()
      videos.scan()
  }

  // Links the AI agent skill into agents' skill folders, or takes the links out
  Run {
    id: skillLinker
    timeoutMs: 10000
    maxBytes: 64 * 1024
    onFinished: function(ok, output) {
      try { root.skillLinks = JSON.parse(output).linked || [] } catch (e) { root.skillLinks = [] }
    }
  }

  Run {
    id: skillSaver
    timeoutMs: 10000
    maxBytes: 16 * 1024
    onFinished: function(ok, output) {
      var r = null
      if (ok) { try { r = JSON.parse(output) } catch (e) { r = null } }
      if (r && typeof r.saved === "string" && r.saved) root.skillSaved = root.shownPath(r.saved)
      else root.skillSaveFailed = true
    }
  }

  Timer {
    id: agentAskTimer
    interval: 900
    onTriggered: root.askFirstStart()
  }

  Commands { guide: root }

  Library {
    id: library
    guide: root
    onLoadedChanged: root.migrateVod()
    onHistoryLoadedChanged: ownerFill.restart()
  }

  Videos {
    id: videos
    guide: root
  }

  // Recordings (the DVR): DVR.qml, bin/om-pg-dvr
  // Pause and rewind: the TV through the rolling buffer (Timeshift.qml)
  Timeshift {
    id: timeshift
    guide: root
    dvr: dvr
    player: player
    onMinutesChanged: root.timeshiftChanged()   // off, on, or 5 ↔ 30: a new buffer
  }
  readonly property var pauser: timeshift      // for Commands.qml
  Connections {
    target: dvr
    function onSettingsChanged() {
      var p = JSON.stringify(dvr.settings.place)
      if (p !== root.timeshiftPlace) { root.timeshiftPlace = p; if (timeshift.busy) root.timeshiftChanged() }
    }
  }
  property string timeshiftPlace: ""
  // frames on the TV's picture, for its clock (Qt's position stops where the buffer ended when it opened)
  Connections { target: video.videoSink; enabled: timeshift.owning; function onVideoFrameChanged() { timeshift.frame() } }
  Connections { target: pipWindow.video.videoSink; enabled: timeshift.owning; function onVideoFrameChanged() { timeshift.frame() } }

  DVR {
    id: dvr
    guide: root
    listings: listings
    defaultFolder: videos.defaultFolder
  }

  Updates {
    id: updatesItem
    guide: root
  }

  Backups {
    id: backupsItem
    guide: root
  }

  Listings {
    id: listings
    guide: root
  }

  Apps {
    id: appsStore
    guide: root
  }

  AppView {
    id: appViewItem
    guide: root
  }

  AppPlayback {
    id: appPlaybackItem
    guide: root
  }

  NativeSaver {
    id: nativeSaverItem
  }

  ChannelLock {
    id: channelLockItem
    guide: root
    helper: appsStore.helper
    file: root.configDir + "/lock.json"
    onRecheck: root.enforceLock()
    onBoxUpChanged: remoteStateTimer.restart()   // the phone's pad types the passcode while it's asked for
    onStepChanged: remoteStateTimer.restart()
    onLoadedChanged: ownerFill.restart()
  }

  Authorize {
    id: authItem
    ask: function(done) { channelLockItem.auth(done) }   // the prompt, run where the channel lock always ran it
  }

  ScreenSaver {
    id: screenSaverItem
    guide: root
    helper: appsStore.helper
    omarchySaverUp: nativeSaverItem.up
    eligible: SaverRules.eligible({ on: screenSaverItem.settings.on, shown: awakeItem.fullScreenShown || awakeItem.windowShown,
                                     playing: awakeItem.playing, omarchySaver: nativeSaverItem.up })
  }

  Awake {
    id: awakeItem
    mode: root.awake
    opened: root.opened
    playing: AwakeRules.videoPlays({ playing: player.playbackState === MediaPlayer.PlayingState, stalled: player.mediaStatus === MediaPlayer.StalledMedia, reception: root.reception })
             || multiviewItem.playing   // a Multiview tile on screen, really playing
             || (!!appPlaybackItem.player && !!appPlaybackItem.session && appPlaybackItem.session.state === "playing"
                 && AwakeRules.videoPlays({ playing: appPlaybackItem.player.playbackState === MediaPlayer.PlayingState,
                                            stalled: appPlaybackItem.player.mediaStatus === MediaPlayer.StalledMedia, reception: "on" }))
    fullScreen: panel
    ownWindow: guideWindow
    miniPlayer: pipWindow
    saverOn: screenSaverItem.settings.on || screenSaverItem.showing
  }

  AppHome {
    id: appHomeItem
    guide: root
  }

  // your app-screen choices (~/.config/om-pg/app-screens.json), confirmed writes
  AppScreens {
    id: appScreensItem
    guide: root
  }

  // the Customize panel's rows and changes (C on an app's screen, Settings → Apps → How apps look)
  AppPanel {
    id: appPanelItem
    guide: root
  }

  // what agents see of apps' screens and change there: handles, never an app's ids or text
  AppAgent {
    id: appAgentItem
    guide: root
  }

  // your themes on disk: one change at a time, each a confirmed transaction
  Themes {
    id: themesItem
    guide: root
  }
  Timer { id: styleRefusedTimer; interval: 4000; onTriggered: root.styleRefused = "" }

  // pictures of the guide for agents (snapshot "", appSnapshot): checked, written whole
  Snapshots {
    id: snapshotsItem
    guide: root
    target: screenItem
    folder: root.cacheDir
    dpr: screenItem.dpr
    run: appsStore.randomHex(32)
    mover: function(argv, done) {
      var r = snapshotMover.createObject(root)
      r.finished.connect(function(ok) { done(ok); Qt.callLater(function() { r.destroy() }) })
      if (!r.start(argv)) { r.destroy(); done(false) }
    }
  }
  Component { id: snapshotMover; Run { timeoutMs: 10000 } }

  // An app removed: its Home rows go too
  Connections {
    target: appsStore
    function onInstalledChanged() {
      if (!appsStore.loaded) return
      var keep = root.homeSections.filter(function(x) { return x.type !== "appRow" || !!appsStore.record(String(x.key).split("/")[0]) })
      if (keep.length !== root.homeSections.length) { root.homeSections = keep; root.saveSettings() }
    }
  }

  // ---- an app with code playing, and signing in (milestone 4) ----
  function playApp(id, rt, value) { appPlaybackItem.start(id, rt, value) }
  // Playback of that app (any app, for "") ended in order first, then then()
  function finishAppPlayback(id, reason, then) {
    var s = appPlaybackItem.session
    appPlaybackItem.dropWaiting(id || "")   // a play still waiting for the TV's buffer: never
    if (s && (!id || s.app === id)) appPlaybackItem.close(reason, then)
    else then()
  }
  function appPlaybackEnded(id, error) {
    if (error && root.codeApp === id) appViewItem.say(error, true)
    keys.forceActiveFocus()
  }
  // A QR code for a link (an app's sign-in page): /usr/bin/qrencode, as the
  // phone remote makes its own; done(path), or done("") without qrencode.
  // One at a time, and only the latest counts: a newer code calls off the one
  // being made (its result never comes) and starts only once that one has
  // exited, so no two ever write together. Two files take turns, the new one
  // never the one last shown: no more files, and none written while shown.
  Run {
    id: qrRun
    timeoutMs: 10000
    maxBytes: 4096
    onFinished: function(ok) {
      var done = root.qrDone
      root.qrDone = null
      if (ok) root.qrShown = root.qrPath
      if (done) done(ok ? root.qrPath : "")
    }
  }
  property string qrShown: ""
  property string qrPath: ""
  property var qrDone: null
  function makeQr(url, done) {
    root.qrDone = null
    if (!/^https?:\/\/[\x21-\x7e]{1,490}$/.test(String(url))) { qrRun.cancel(); done(""); return }
    var first = root.cacheDir + "/app-signin-qr-0.png"
    root.qrPath = root.qrShown === first ? root.cacheDir + "/app-signin-qr-1.png" : first
    root.qrDone = done
    qrRun.replace(["/usr/bin/qrencode", "-o", root.qrPath, "-s", "10", "-m", "2", "-l", "M", "--", String(url)])
  }

  Component.onCompleted: {
    root.readThemes()
    root.readSettings()
    Qt.callLater(root.placeScreen)
    privateFolders.running = true   // the guide's folders, yours alone
  }

  // The demo lineup (demo/channels.json): loaded when you ask, at a first
  // start or in Settings
  FileView {
    path: root.pluginDir + "/demo/channels.json"
    onLoaded: root.demoList = text()
  }

  FileView {
    path: root.pluginDir + "/contributors.json"
    onLoaded: root.contributorsList = text()
  }

  // The lineup a first run starts with
  FileView {
    path: root.pluginDir + "/channels.json"
    onLoaded: {
      root.defaultList = text()
      if (root.ownListMissing || (root.listProblem && !root.channels.length)) root.loadChannels(root.defaultList)
    }
  }

  Timer {
    interval: 5000
    repeat: true
    running: root.opened
    onTriggered: {
      root.now = Date.now() / 1000
      root.rollDay()
      root.listedAir()
    }
  }

  // An IPTV channel on: when its show changes (by its listings), what's on
  // follows, without tuning again
  function listedAir() {
    var a = root.onAir
    if (!a || !a.iptv || root.tunedRow < 0) return
    var ch = root.channels[root.tunedRow]
    if (!ch || ch.url !== a.stream) return
    var listed = listings.at(ch.url, Date.now() / 1000)
    var next = listed ? { title: listed.title, start: listed.start, end: listed.end, epg: true }
             : a.epg ? { title: ch.live.title, start: Date.now() / 1000, end: Date.now() / 1000 + 6 * 3600, epg: false } : null
    if (!next || (next.title === a.title && next.start === a.start && !!next.epg === !!a.epg)) return
    var b = {}
    for (var k in a) b[k] = a[k]
    for (var n in next) b[n] = next[n]
    root.onAir = b
  }

  function clock(t) { return Qt.formatDateTime(new Date(t * 1000), root.layout.hours24 ? "HH:mm" : "h:mm AP") }

  Component {
    id: gridList
    ProgramGrid { guide: root }
  }

  Component {
    id: tableList
    ChannelTable { guide: root }
  }

  Component {
    id: boardList
    FlapBoard { guide: root }
  }

  // The list of channels on screen (the grid's or the table's), and where the TV goes
  readonly property var channelList: listLoader.item ? listLoader.item.list : null
  readonly property Item videoSlot: root.layout.list === "table" && listLoader.item && listLoader.item.videoSlot ? listLoader.item.videoSlot : infoPanel.videoSlot
  readonly property bool agentStripUp: !agentSkill && agentAsked && !agentSettled && !managing
  // channels shown in each category
  readonly property var categoryCounts: {
    var out = {}
    for (var i = 0; i < visibleRows.length; i++) {
      var c = (channels[visibleRows[i]] || {}).category || ""
      out[c] = (out[c] || 0) + 1
    }
    return out
  }

  // The next n programs on channel r from time t (the table's lineup pane)
  function lineupFrom(r, t, n) {
    return root.lockedShows(root.channels[r], root.lineupFromRaw(r, t, n), t, t + 12 * 3600)
  }
  function lineupFromRaw(r, t, n) {
    var ch = root.channels[r]
    if (!ch) return []
    if (ch.kind === "iptv" && listings.has(ch.url)) return root.listedShows(ch, t, t + 12 * 3600).filter(function(x) { return x.end > t }).slice(0, n)
    if (ch.live) return [{ live: true, id: ch.live.id, title: ch.live.title, start: t, end: t + 3600 }]
    if (ch.state !== "ready") return []
    return Schedule.airing(root.lineupOf(ch), t, t + 12 * 3600).slice(0, n)
  }

  // As written; the info panel's case (Look.js) decides how it shows
  function airTime(s) {
    if (s.live) return "● Live now"
    var range = root.clock(s.start) + " – " + root.clock(s.end)
    if (root.now >= s.start && root.now < s.end)
      return range + "   On now · " + Math.ceil((s.end - root.now) / 60) + " min left"
    var mins = Math.round((s.start - root.now) / 60)
    return range + "   Starts in " + (mins >= 60 ? Math.floor(mins / 60) + " hr " + (mins % 60) + " min" : mins + " min")
  }

  function channelLabel(r) {
    var ch = root.channels[r]
    return ch ? "CH " + root.numbers[r] + "  " + ch.name : ""
  }

  MiniPlayer {
    id: pipWindow
    guide: root
  }

  // The guide in a window (W): ordinary, maximized, the Omarchy bar showing
  FloatingWindow {
    id: guideWindow
    title: "Uber TV"
    visible: root.opened && root.windowed && !root.remapping
    color: root.navyDeep
    implicitWidth: 1600
    implicitHeight: 1000
    minimumSize: Qt.size(900, 560)
    // closed from outside (its close key, say): the guide goes away
    onVisibleChanged: {
      if (visible) root.maximizeWindow()
      else if (root.opened && root.windowed && !root.remapping) root.dismiss()
    }
  }

  PanelWindow {
    id: panel
    // out of the way while Omarchy's screen saver is up (NativeSaver.qml)
    visible: root.opened && !root.windowed && !nativeSaverItem.up
    anchors { top: true; bottom: true; left: true; right: true }
    color: root.navyDeep
    WlrLayershell.namespace: "om-pg"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.firewallBusy || root.authBusy ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // Everything in the guide, in one item (what snapshot takes a picture of)
    Item {
      id: screenItem
      anchors.fill: parent
      readonly property real dpr: (root.windowed ? guideWindow.devicePixelRatio : panel.devicePixelRatio) || 1

      SplashScreen { id: splashItem; anchors.fill: parent; z: 100000 }

      Box {
        anchors.fill: parent
        s: root.look.background
        unit: root.u
      }

      // Your picture, if you chose one, dimmed so the guide stays readable
      Image {
        anchors.fill: parent
        visible: root.backgroundSource !== "" && status === Image.Ready
        source: root.backgroundSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: screenItem.width
        sourceSize.height: screenItem.height
      }
      Rectangle {
        anchors.fill: parent
        visible: root.backgroundSource !== ""
        color: root.navyDeep
        opacity: root.bgDim
      }

      GuideKeys {
        id: keys
        guide: root
      }

      Column {
        id: page
        visible: root.screen === "guide"
        anchors.fill: parent
        anchors.margins: root.u * 2
        anchors.leftMargin: root.u * 2 + root.railSpace
        spacing: root.u

        Masthead {
          visible: root.layout.masthead === "title" || (root.layout.masthead === "none" && root.agentStripUp)
          width: page.width
          guide: root
        }

        TopBar {
          visible: root.layout.masthead === "bar"
          width: page.width
          guide: root
        }

        // The preview box, and what's under the cursor
        InfoPanel {
          id: infoPanel
          visible: root.layout.info
          width: page.width
          guide: root
        }

        // The channels: the time grid, or the table (layout.list)
        Loader {
          id: listLoader
          width: page.width
          height: page.height - y - (footer.visible ? footer.height + page.spacing : 0)
          sourceComponent: root.layout.list === "table" ? tableList : root.layout.list === "board" ? boardList : gridList
          onLoaded: Qt.callLater(function() { root.showRow(root.row) })
        }

        Footer {
          id: footer
          width: page.width
          guide: root
        }
      }

      // Lines between the info area, the grid and the key hints (layout.dividers)
      Rectangle {
        visible: root.layout.dividers && infoPanel.visible && page.visible
        x: page.x
        y: page.y + infoPanel.y + infoPanel.height + (page.spacing - height) / 2
        width: page.width
        height: Math.max(1, Look.px(root.look.divider.height, root.u))
        color: root.look.divider.color
      }
      Rectangle {
        visible: root.layout.dividers && footer.visible && page.visible
        x: page.x
        y: page.y + footer.y - (page.spacing + height) / 2
        width: page.width
        height: Math.max(1, Look.px(root.look.divider.height, root.u))
        color: root.look.divider.color
      }

      // Just after hiding the key hints: how to get them back
      Box {
        visible: root.keyHintsNote && !root.showKeyHints && !root.watching
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: root.u * 2
        width: note.implicitWidth + root.u * 1.6
        height: root.u * 2.6
        s: root.look.box
        unit: root.u

        KeyHints {
          id: note
          anchors.centerIn: parent
          model: [{ keys: [], label: "Key hints hidden" }, { keys: ["K"], label: "Shows them again" }, { keys: ["?"], label: "Lists every key" }]
          size: root.u * 1.45
          capStyle: root.look.keycap
          labelStyle: root.look.keyLabel
          labelColor: root.ink
        }
      }

      // Home, made only while it's on screen (root.homeOnScreen); its cursor
      // stays on root
      Loader {
        anchors.fill: parent
        anchors.leftMargin: root.railSpace
        active: root.homeOnScreen
        sourceComponent: Component {
          HomeScreen { guide: root }
        }
      }

      // The library (V), made while it's open
      Loader {
        anchors.fill: parent
        anchors.leftMargin: root.railSpace
        active: root.screen === "library"
        sourceComponent: Component {
          LibraryScreen { guide: root }
        }
      }

      // Settings (,), made while it's open
      Loader {
        anchors.fill: parent
        anchors.leftMargin: root.railSpace
        active: root.screen === "settings"
        sourceComponent: Component {
          SettingsScreen { guide: root }
        }
      }

      // Search (/), made while it's open
      Loader {
        anchors.fill: parent
        anchors.leftMargin: root.railSpace
        active: root.screen === "search"
        sourceComponent: Component {
          SearchScreen { guide: root }
        }
      }

      // Apps (the rail, while apps are on), made while it's open
      Loader {
        anchors.fill: parent
        anchors.leftMargin: root.railSpace
        active: root.screen === "apps"
        sourceComponent: Component {
          AppsScreen { guide: root }
        }
      }

      // An app with code, its screens drawn by the guide
      Loader {
        anchors.fill: parent
        anchors.leftMargin: root.railSpace
        active: root.screen === "app"
        sourceComponent: Component {
          AppScreen { guide: root }
        }
      }

      // An item's details, over the library or Search
      DetailBox {
        anchors.fill: parent
        anchors.leftMargin: root.railSpace
        guide: root
      }

      // Customize an app's screen (C), or every app's: down the right, over the screen it changes
      AppCustomize {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: root.u
        guide: root
      }

      // Updates are off (the first time), or what Turn on found: above the key hints
      AskStrip {
        guide: root
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.railSpace + root.u * 3
        anchors.rightMargin: root.u * 3
        anchors.bottomMargin: root.showKeyHints ? root.u * 4.3 : root.u * 1.6
      }

      // The nav rail, over the screens, under the boxes and the TV
      NavRail {
        anchors.fill: parent
        guide: root
      }

      // An app's media, full screen
      Loader {
        anchors.fill: parent
        active: appPlaybackItem.active
        z: 50
        sourceComponent: Component {
          AppPlayer { guide: root }
        }
      }

      // Multiview: two to four channels at once, over everything but the boxes
      Multiview {
        id: multiviewItem
        anchors.fill: parent
        guide: root
      }

      DialogBox {
        id: dialogBox
        guide: root
      }

      LockBox {
        guide: root
      }

      StylePanel {
        id: stylePanel
        guide: root
      }

      TvScreen {
        id: tvScreen
        anchors.fill: parent
        guide: root
      }

      // One picture, shown in the preview box or full screen.
      VideoOutput {
        id: video
        parent: root.watching ? tvScreen : root.videoSlot
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit

        ChannelIdent {
          anchors.fill: parent
          up: root.reception !== "off" && (root.cardShow ? root.identUp : root.reception === "tuning" || root.reception === "lost") || timeshift.stalled
          logo: root.vod ? root.posterFor(root.vod) : root.logoFor(root.channels[root.tunedRow])
          number: root.vod ? "" : root.numbers[root.tunedRow] ? "CH " + root.numbers[root.tunedRow] : ""
          name: root.vod ? root.vod.title : root.channels[root.tunedRow] ? root.channels[root.tunedRow].name : ""
          status: root.identStatus
          unit: root.watching ? root.u * 1.6 : root.u * 0.62
          look: root.look
          alarm: root.colors.alert
          image: root.areaImages.card
        }

        // the channel under the cursor is from a provider a recording is
        // using: it waits (Enter asks, then watches)
        Rectangle {
          anchors.fill: parent
          visible: !root.watching && root.screen === "guide" && !channelLockItem.blocks(root.channels[root.row])
                   && !(root.row === root.tunedRow && root.reception !== "off") && dvr.needsAsk(root.channels[root.row])
          color: root.colors.preview
          Column {
            anchors.centerIn: parent
            width: parent.width - root.u * 2      // its words wrap inside the preview
            spacing: root.u * 0.4
            Icon {
              anchors.horizontalCenter: parent.horizontalCenter
              name: "record"
              size: root.u * 3
              stroke: 1.6
              color: root.ink
            }
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: "Recording from this provider · ENTER to watch"
              color: root.ink
              font.family: root.fonts.body
              font.pixelSize: root.u * 0.9
            }
          }
        }

        // the channel under the cursor is locked: a lock, not its picture
        Rectangle {
          anchors.fill: parent
          visible: !root.watching && root.screen === "guide" && channelLockItem.blocks(root.channels[root.row])
          color: root.colors.preview
          Column {
            anchors.centerIn: parent
            spacing: root.u * 0.4
            Icon {
              anchors.horizontalCenter: parent.horizontalCenter
              name: "lock"
              size: root.u * 3
              stroke: 1.6
              color: root.ink
            }
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: !channelLockItem.loaded ? (channelLockItem.failed ? "The channel lock can't be read · ENTER" : "Checking the channel lock…") : "Locked · ENTER to watch"
              color: root.ink
              font.family: root.fonts.body
              font.pixelSize: root.u * 0.9
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: root.u * 0.6
          visible: root.muted && root.reception !== "off"
          text: "MUTE"
          color: root.marquee
          font.family: root.fontFamily
          font.pixelSize: root.watching ? root.u * 1.4 : root.u * 0.9
          font.bold: true
        }
      }

      // An app coming up: its color and name, until its window's there
      Rectangle {
        id: appSplash
        anchors.fill: parent
        visible: root.appOpening !== ""
        readonly property var app: root.appOpening ? appsStore.record(root.appOpening) : null
        readonly property color ink: root.inkOn(app && app.color ? app.color : "")
        color: app && /^#[0-9a-f]{6}$/i.test(app.color || "") ? app.color : root.navyDeep
        MouseArea { anchors.fill: parent }
        Column {
          anchors.centerIn: parent
          spacing: root.u * 1.2
          Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.u * 14
            height: root.u * 8
            visible: status === Image.Ready
            source: appSplash.app && appSplash.app.icon ? root.fileUrl(appSplash.app.icon) : ""
            sourceSize.width: 512
            fillMode: Image.PreserveAspectFit
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: appSplash.app ? appSplash.app.name : ""
            color: appSplash.ink
            font.family: root.fontFamily
            font.pixelSize: Math.round(root.u * 3.6)
            font.bold: true
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: "Opening full screen…"
            color: appSplash.ink
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Math.round(root.u * 1.4)
          }
        }
        KeyHints {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.u * 2
          visible: root.showKeyHints
          model: [{ keys: ["ESC"], label: "Cancel" }]
          size: root.u * 1.55
          capStyle: root.look.keycap
          labelColor: appSplash.ink
        }
      }
    }
  }

  // Over an app, for a moment: how to come back. It takes no keys or clicks.
  PanelWindow {
    id: appHintWindow
    visible: root.appHint && !root.opened && root.appUp !== "" && !nativeSaverItem.up
    screen: panel.screen
    anchors.top: true
    margins.top: hu * 2
    implicitWidth: hintBox.width
    implicitHeight: hintBox.height
    color: "transparent"
    WlrLayershell.namespace: "om-pg-hint"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    readonly property real hu: Math.max(10, Math.round((screen ? screen.height : 1080) / 60))
    readonly property var app: appsStore.record(root.appUp)

    Box {
      id: hintBox
      width: hintKeys.implicitWidth + appHintWindow.hu * 2.4
      height: appHintWindow.hu * 3
      s: root.look.box
      unit: appHintWindow.hu
      KeyHints {
        id: hintKeys
        anchors.centerIn: parent
        model: [{ keys: ["SUPER", "+", "W"], label: "Closes " + (appHintWindow.app ? appHintWindow.app.name : "it") + " and brings back the guide" }]
               .concat(root.windowed ? [{ keys: ["SUPER", "+", "F"], label: "Full screen" }] : [])
        size: appHintWindow.hu * 1.55
        capStyle: root.look.keycap
        labelStyle: root.look.keyLabel
      }
    }
  }
}
