import QtQuick
import Quickshell
import Quickshell.Io
import "Look.js" as Look
import "Saver.js" as SaverRules
import "AppAsks.js" as Asks
import "Dvr.js" as DvrRules
import "Timeshift.js" as Ts

// The guide's commands, for scripts and AI agents: omarchy-shell om-pg <command> ...
// (skills/program-guide/SKILL.md says how to use them). Each answers with
// JSON. The phone remote isn't here: turning it on stays yours. Nor is turning
// apps on or installing them: agents can see apps and turn one off, no more.
Scope {
  id: commands

  required property var guide

  function okReply(extra) {
    var out = { ok: true }
    for (var k in extra) out[k] = extra[k]
    return JSON.stringify(out)
  }

  function failReply(message) { return JSON.stringify({ ok: false, error: message }) }

  function onOff(v) {
    var t = String(v).trim().toLowerCase()
    return t === "on" || t === "true" || t === "yes" || t === "1" ? true : t === "off" || t === "false" || t === "no" || t === "0" ? false : null
  }

  // Channel numbers ("101", "101,102", "101-110") to channel indexes
  function rowsFor(numbers) {
    var out = []
    var parts = String(numbers).split(/[,\s]+/).filter(function(x) { return x })
    for (var i = 0; i < parts.length; i++) {
      var range = parts[i].match(/^(\d+)-(\d+)$/)
      var from = range ? Number(range[1]) : Number(parts[i])
      var to = range ? Number(range[2]) : from
      if (isNaN(from) || isNaN(to) || to - from > 5000) continue
      for (var n = from; n <= to; n++) {
        var r = guide.numbers.indexOf(n)
        if (r >= 0 && out.indexOf(r) < 0) out.push(r)
      }
    }
    return out
  }

  // Multiview's channels from numbers: 1 to 4, each one that can play now
  // (as watch checks); the first problem, or their rows
  function multiviewRows(numbers) {
    var parts = String(numbers).split(/[,\s]+/).filter(function(x) { return x })
    if (!parts.length) return { error: "give 1 to 4 channel numbers, with commas: multiview \"101,501\" (channels <words> finds them)" }
    if (parts.length > 4) return { error: "Multiview holds up to 4 channels" }
    var rows = []
    for (var i = 0; i < parts.length; i++) {
      var r = /^\d+$/.test(parts[i]) ? guide.numbers.indexOf(Number(parts[i])) : -1
      if (r < 0) return { error: "no channel " + parts[i] + " (channels <words> finds its number)" }
      if (rows.indexOf(r) >= 0) return { error: "channel " + parts[i] + " is given twice" }
      if (!guide.airs(guide.channels[r])) return { error: "channel " + parts[i] + " has nothing to show yet" }
      if (guide.channelLock && guide.channelLock.blocks(guide.channels[r]))
        return { error: !guide.channelLock.loaded ? "the channel lock hasn't been read (" + (guide.channelLock.failed || "it's being read") + "): no channel plays until it is"
                                                  : "channel " + parts[i] + " is locked: only the user can unlock it, with the passcode, at the screen" }
      rows.push(r)
    }
    return { rows: rows }
  }

  // Multiview for state: its channels in order (which has the sound), the
  // layout and the ones it can take; null while it's off
  function multiviewInfo() {
    var mv = guide.multiview
    if (!mv || !mv.active) return null
    var sound = mv.rowOf(mv.sel)
    return { channels: mv.order.map(function(s) {
               var r = mv.rowOf(s)
               var c = r >= 0 ? commands.channelInfo(r) : { number: null, name: "" }
               c.sound = s === mv.sel
               return c
             }),
             layout: mv.layout, layouts: mv.layoutsFor(mv.count), sound: sound >= 0 ? guide.numbers[sound] : null,
             fullScreen: mv.mode === "full", adding: mv.mode === "picker", paused: mv.paused }
  }

  // The tile showing a channel number, or -1
  function multiviewSlot(number) {
    var mv = guide.multiview, n = Number(String(number).trim())
    for (var k = 0; k < mv.order.length; k++) if (guide.numbers[mv.rowOf(mv.order[k])] === n) return mv.order[k]
    return -1
  }

  readonly property string multiviewOff: "Multiview isn't on (multiview \"<numbers>\" opens it)"

  // ---- recordings (DVR.qml) ----
  readonly property string recordingsOff: "Recordings are off (setRecordingSettings {\"on\": true} turns them on, when the user asks)"

  // A recording as agents see it: a locked channel's says nothing about itself
  function recordingInfo(rec) {
    var d = guide.recorder
    var hide = d.hidden(rec) || d.locked(rec)
    return { id: rec.id, state: DvrRules.stateOf(rec), kind: rec.kind, locked: hide || undefined,
             title: hide ? "Locked recording" : (rec.titles && rec.titles.length > 1 ? rec.titles.join(" · ") : rec.title || ""),
             channel: hide ? undefined : { name: (rec.channel || {}).name || "", number: (rec.channel || {}).number || 0 },
             started: DvrRules.waiting(rec) ? undefined : rec.started || rec.created || 0, until: DvrRules.active(rec) && rec.end ? rec.end : undefined,
             show: rec.show && !hide ? { start: rec.show.start, end: rec.show.end, episode: rec.ep || undefined, episodeTitle: rec.sub || undefined } : undefined,
             records: DvrRules.waiting(rec) ? { from: rec.start, to: rec.end } : undefined,
             series: rec.rule && guide.recorder.ruleOf(rec) ? rec.rule : undefined,
             seconds: rec.duration || undefined, bytes: rec.bytes || undefined,
             why: rec.reason ? d.reasonOf(rec) : undefined,
             file: hide || !rec.path ? undefined : rec.path }
  }

  // A series rule as agents see it (a locked channel's names nothing)
  function seriesInfo(rule) {
    var hide = rule.private === true
    return { id: rule.id, title: hide ? "Locked series" : rule.title, locked: hide || undefined,
             channel: hide ? undefined : { name: (rule.channel || {}).name || "", number: (rule.channel || {}).number || 0 } }
  }

  // Pause and rewind for an agent: on, a live channel on the TV, its buffer
  // ready; what's in the way otherwise (it never turns on or starts anything)
  function pauseProblem() {
    var p = guide.pauser
    if (!p.turnedOn) return "pause and rewind is off (Settings → Recordings; setRecordingSettings {\"pauseAndRewind\": 5} turns it on, when the user asks)"
    if (guide.reception === "off" || guide.vod || (guide.multiview && guide.multiview.active) || !Ts.supported(guide.onAir)) return "no live channel is on the TV"
    if (!p.active) return p.filling ? "its buffer is still starting: try again in a moment" : (p.cantPauseText || "it isn't running on this channel")
    return ""
  }
  function liveInfo() {
    var p = guide.pauser
    return { paused: p.paused, live: p.atLive, behindSeconds: p.atLive ? 0 : Math.round(p.behind / 1000) }
  }

  function recordingSettingsInfo() {
    var d = guide.recorder
    var s = d.settings
    return { on: s.on, place: { label: d.placeLabel, path: d.placeInfo && d.placeInfo.path || "", drive: !!(s.place && s.place.removable),
                                there: !(d.placeInfo && d.placeInfo.problem === "drive"), free: d.placeInfo && d.placeInfo.free || undefined },
             keepFree: s.keepFree || "auto", keepFreeNow: d.keepFreeGB, quality: s.quality || "auto", qualityNow: d.quality,
             padding: { early: DvrRules.PADDINGS[s.padding][0], late: DvrRules.PADDINGS[s.padding][1] }, atOnce: s.atOnce, pauseAndRewind: s.timeshift,
             drives: d.drives.map(function(x) { return { device: x.device, label: x.label, mounted: !!x.mount, free: x.mount ? x.free : undefined } }) }
  }

  // The show on channel number at when (HH:MM today, tomorrow if it's gone
  // by; next: the next one; now, for a series: on now), from its listings:
  // { row, show } or { error }
  function laterShow(number, when, nowToo) {
    var r = commands.rowsFor(number)[0]
    if (r === undefined) return { error: "no channel " + number + " (channels <words> finds its number)" }
    var ch = guide.channels[r]
    if (ch.kind !== "iptv" || !guide.listingsHave(ch)) return { error: "that channel has no listings to schedule from (an IPTV channel with listings)" }
    if (guide.channelLock && guide.channelLock.blocks(ch))
      return { error: "that channel is locked: only the user can record it, with the passcode, at the screen" }
    var t = String(when).trim().toLowerCase()
    var now = Date.now() / 1000
    var at = 0
    var hm = t.match(/^(\d{1,2}):(\d{2})$/)
    var dm = t.match(/^(\d{4})-(\d{2})-(\d{2})[ t](\d{1,2}):(\d{2})$/)   // a day and time, as shows gives it
    var said = nowToo ? "a clock time (21:30), a day and time (2026-10-21 21:30), a show's start from shows, now or next"
                      : "a clock time (21:30), a day and time (2026-10-21 21:30), a show's start from shows, or next"
    // a local time that is one (not past 23:59, nor skipped when the clocks go forward)
    var local = function(y, mo, d, h, mi) {
      var x = new Date(y, mo - 1, d, h, mi, 0, 0)
      return x.getFullYear() === y && x.getMonth() === mo - 1 && x.getDate() === d && x.getHours() === h && x.getMinutes() === mi ? x.getTime() / 1000 : 0
    }
    if (hm) {
      var dt = new Date()
      at = local(dt.getFullYear(), dt.getMonth() + 1, dt.getDate(), Number(hm[1]), Number(hm[2]))
      if (at && at + 60 < now) {   // tomorrow, by the calendar (a day isn't always 24 hours)
        dt.setDate(dt.getDate() + 1)
        at = local(dt.getFullYear(), dt.getMonth() + 1, dt.getDate(), Number(hm[1]), Number(hm[2]))
      }
      if (!at) return { error: "no such time then: " + said }
    } else if (dm) {
      at = local(Number(dm[1]), Number(dm[2]), Number(dm[3]), Number(dm[4]), Number(dm[5]))
      if (!at) return { error: "no such day and time: " + said }
    } else if (/^\d{9,11}$/.test(t)) at = Number(t)   // a show's start (seconds), as shows gives it: the hour that repeats, when the clocks go back, too
    else if (t === "now" && nowToo) at = now
    else if (t !== "next") return { error: said }
    var show = at ? guide.showListed(ch, at) : guide.showListed(ch, 0, now)
    if (!show) return { error: "no show listed then on that channel" }
    if (show.end <= now) return { error: "that show is over" }
    return { row: r, show: show }
  }

  function recordingById(id) {
    return guide.recorder.byId[String(id).trim()] || null
  }

  function channelInfo(r) {
    var c = guide.channels[r]
    return { number: guide.numbers[r], name: c.name, kind: c.kind || "youtube", category: c.category || "", live: !!c.live,
             shown: guide.visibleRows.indexOf(r) >= 0, locked: !!guide.channelLock && guide.channelLock.isLocked(c) }
  }

  function themeInfo(t) {
    return { id: t.id, name: t.name, description: t.description || "", builtIn: !!t.builtIn, current: t.id === guide.themeId,
             pictures: Object.keys(t.images || {}).filter(function(k) { return t.images[k].src }),
             elements: Object.keys(t.elements || {}), fonts: t.fonts || {}, layout: t.layout || {}, apps: t.apps || {} }
  }

  // setStyle fonts {"body": "Adwaita Sans", "display": null}: null (or
  // "theme") takes yours off; "theme" alone takes all of them off
  function setFonts(text) {
    var all = {}
    for (var k in guide.fontOverrides) all[k] = guide.fontOverrides[k]
    var ignored = []
    if (text === "theme") all = {}
    else {
      var given
      try { given = JSON.parse(text) } catch (e) { return commands.failReply("not valid JSON: " + e.message) }
      if (!given || typeof given !== "object" || Array.isArray(given)) return commands.failReply("fonts by role: {\"body\": ..., \"display\": ..., \"mono\": ...}")
      var set = {}
      for (var role in given) {
        if (given[role] === null || given[role] === "theme") delete all[role]
        else set[role] = given[role]
      }
      var checked = Look.checkFonts(set, guide.installedFonts)
      for (var r in checked.fonts) all[r] = checked.fonts[r]
      ignored = checked.ignored
    }
    guide.fontOverrides = all
    guide.saveSettings()
    return commands.okReply({ fonts: guide.fonts, yours: all, ignored: ignored })
  }

  // setStyle layout {"masthead": false, "upNext": 2}: null takes one of
  // yours off; "theme" alone takes all of them off
  function setLayout(text) {
    var all = {}
    for (var k in guide.layoutOverrides) all[k] = guide.layoutOverrides[k]
    var ignored = []
    if (text === "theme") all = {}
    else {
      var given
      try { given = JSON.parse(text) } catch (e) { return commands.failReply("not valid JSON: " + e.message) }
      if (!given || typeof given !== "object" || Array.isArray(given)) return commands.failReply("layout settings: {\"masthead\": false, ...} (elements \"\" lists them)")
      var set = {}
      for (var key in given) {
        if (given[key] === null) delete all[key]
        else set[key] = given[key]
      }
      var checked = Look.checkLayout(set)
      for (var c in checked.layout) all[c] = checked.layout[c]
      ignored = checked.ignored
    }
    guide.layoutOverrides = all
    guide.saveSettings()
    return commands.okReply({ layout: guide.layout, yours: all, ignored: ignored })
  }

  function styleState() {
    return { theme: guide.themeId, themeName: guide.currentTheme.name, yourColors: guide.colorOverrides, yourPictures: guide.imageOverrides,
             yourStyles: guide.elementOverrides, yourFonts: guide.fontOverrides, yourLayout: guide.layoutOverrides, fonts: guide.fonts, layout: guide.layout,
             background: { mode: guide.bgMode, image: guide.bgImage, dim: guide.bgDim },
             lowerThird: { show: guide.ltShow, seconds: guide.ltSeconds }, card: { show: guide.cardShow, seconds: guide.cardSeconds } }
  }

  readonly property var commandHelp: [
    ["help", "these commands"],
    ["state", "the guide at a glance: open, channels, theme, filters, settings, Recordings (on, how many recording, how many waiting (Scheduled or Conflict), series), pause and rewind (on, running, paused, how far behind live), and Multiview (its channels in order, layout and sound) while it's on"],
    ["open", "opens the guide"],
    ["display <full|window|\"\">", "how the guide shows: full (over everything, the Omarchy bar too) or window (an ordinary maximized window, the bar showing, on its own desktop); \"\" just says which"],
    ["close", "closes the guide (and turns the TV off)"],
    ["watch <number>", "a channel full screen (not a locked one: only the user unlocks those, with the passcode)"],
    ["multiview <numbers>", "Multiview: up to 4 channels at once, with commas (multiview \"101,501,801\"), the first with the sound; one alone opens with the Add a channel list for the user. Not locked channels. It takes over the screen: only when the user asks"],
    ["multiviewAdd <number>", "adds a channel to Multiview (up to 4); the layout becomes its count's first"],
    ["multiviewRemove <number>", "takes a channel off Multiview; with one left, Multiview closes and that one plays full screen"],
    ["multiviewLayout <side|featured|grid|row>", "Multiview's layout: two channels side or featured; three featured, grid or row; four grid or featured (featured: the first channel big)"],
    ["multiviewSound <number>", "which of Multiview's channels has the sound"],
    ["multiviewClose", "closes Multiview: the channel with the sound plays full screen"],
    ["themes", "the themes: [{id, name, description, builtIn, current, pictures, elements, fonts, layout}]"],
    ["theme <id>", "puts a theme on"],
    ["addTheme <json>", "saves a theme (its JSON itself, not a path) in ~/.config/om-pg/themes and puts it on; an id or name already there is replaced"],
    ["saveTheme <name> <description>", "saves the look on screen (the theme, the user's own colors, styles, fonts and layout, the pictures, banner and card) as a theme; the name of the theme that's on updates it (\"\" description keeps or makes one)"],
    ["removeTheme <id>", "deletes one of the user's themes (only when the user asks)"],
    ["slots", "every color slot: [{key, section, label, theme, yours, now}]"],
    ["style", "the theme, the user's own colors, pictures, styles, fonts and layout, and the banner and card settings"],
    ["setColor <key> <#hex>", "one slot's color on top of the theme (\"\" for the theme's)"],
    ["resetColors", "takes the user's own colors off, back to the theme's (the picture, banner and card stay)"],
    ["reset <theme|original|undo>", "theme: the user's own changes (colors, pictures, styles, fonts, layout) off, the theme's settings back; original: Premiere, as the guide comes; undo: the look before the last reset"],
    ["elements <name|\"\">", "every part of the guide that can be styled (\"\"), or one: its properties, states, and Retro's, the theme's, the user's and the style now"],
    ["setStyle <element> <json|theme>", "styles one element (or element:state) over the theme, as the user's: {\"radius\": 0.4, \"text\": {\"size\": 1.1}}; null takes a property off; theme takes all of it off; setStyle fonts {\"body\": \"Adwaita Sans\"} sets fonts; setStyle layout {\"masthead\": false} lays it out"],
    ["fonts <words>", "installed font families matching the words (\"\" for all), and the fonts on now"],
    ["snapshot \"\"", "a picture (PNG) of the guide as it is on screen, to look at what you made: the guide must be open, with no sensitive screen up (the phone remote's box, an app's sign-in or settings, a text field). Answers its file's name; state's snapshot says when it's written, or why it wasn't"],
    ["images", "every picture area: [{area, name, picture, fit, opacity, from}] (from: yours, theme, or \"\" for none)"],
    ["setImage <area> <picture> <fit> <opacity>", "an area's picture: a picture's full path, none, theme (back to the theme's) or \"\" (keep it); fit fill|fit|stretch|tile|center|frame; opacity 0.1 to 1 (\"\" keeps either)"],
    ["background <none|wallpaper|/path/to/picture> <dim>", "the picture behind the guide; dim 0 to 0.95 (\"\" keeps it)"],
    ["record <number> <length>", "records a channel from now: length \"\" for its show's end plus the end-late minutes with listings (an hour without), or minutes (90) or hours (2h), 12 hours at most; a scheduled YouTube channel's show is its video, saved whole. Not locked channels. As many at once as Settings → Recordings allows (2 unless the user chose 1 to 4)"],
    ["recordUntil <id> <minutes|HH:MM>", "a new stop time for a recording: minutes from now, or a clock time today (within 12 hours of its start)"],
    ["recordShow <number> <HH:MM|YYYY-MM-DD HH:MM|next>", "records a later show (IPTV with listings): the one on at that time today (tomorrow, if it's gone by), on that day at that time, or at a show's start in seconds (shows gives both: the start for the hour that repeats when the clocks go back), or the next one; Scheduled, or a Conflict when it'd be one too many (Recordings at once; it names the others). Not locked channels"],
    ["recordSeries <number> <HH:MM|YYYY-MM-DD HH:MM|now|next>", "Record every episode of the show on at that time (a day and time as shows gives it; now: on now; next: the next one): this one too if it's on, then each episode the listings have, not one recorded already. Not locked channels"],
    ["cancelRecording <id>", "cancels a scheduled recording (an episode of a series isn't scheduled again), or a series by its id (its rule, and its shows not started yet; what it recorded stays). Only when the user asks"],
    ["stopRecording <id>", "stops a recording (what's recorded is kept)"],
    ["recordings", "the recordings (the first 300): their state (Scheduled, Conflict, Starting, Recording, Saving, Done, Missed, Incomplete, Failed, Drive missing), title, channel, show times, length, why one didn't go as planned, and file; the series (Record every episode); plus the settings"],
    ["playRecording <id>", "plays a recording full screen, from where the user stopped (not a locked channel's)"],
    ["startOver <id>", "plays a recording, a library item or one of the user's videos full screen from the start (playRecording and play resume where the user stopped); not a locked channel's"],
    ["removeRecording <id>", "deletes a recording: its file, its details and its picture. Only when the user asks"],
    ["recordingDrives", "the USB drives plugged in (mounted or not), for setRecordingSettings' place"],
    ["recordingSettings", "Recordings' settings: on, where recordings go (and its free space), space kept free, YouTube quality, how many at once, start early and end late, pause and rewind (minutes kept, 0 off)"],
    ["setRecordingSettings <json>", "changes them: {\"on\", \"place\": \"videos\" | \"/a/folder\" | \"drive:/dev/sdb1\" (a mounted one), \"keepFree\": \"auto\" or 2, 5, 8, 10, 20 (GB), \"quality\": \"auto\" or 1080, 720, 480, \"padding\": 0, 1 or 2 (none, 1 and 2 minutes, 2 and 5), \"atOnce\": 1 to 4 (how many may record at the same time; 2 unless the user says: each is another stream and ~3 GB an hour), \"pauseAndRewind\": 0, 5 or 30 (minutes the live channel on the TV is kept, to pause and go back; 0 off; it writes to the recordings drive the whole time you watch), \"stopAndCancel\": true to turn off while recording}"],
    ["pauseLive", "pauses the live channel on the TV, or resumes it if it's paused (pause and rewind: only while it's on and its buffer is ready); answers paused, live, and how far behind live"],
    ["seekLive <seconds>", "moves the live channel on the TV back (negative) or forward by that many seconds, as far as pause and rewind's buffer goes (past live is live)"],
    ["goLive", "the live channel on the TV back to live (pause and rewind)"],
    ["libraryTabs", "the library's tabs in order (Movies & Series, On Demand, My Videos, Recordings, My List), and which show"],
    ["setLibraryTabs <keys>", "their order, with commas (recordings,movies); the ones left out follow in theirs"],
    ["multiviewBackground <none|#rrggbb|theme|wallpaper|/path/to/picture> <dim>", "Multiview's background: as it is (the theme's colors), a color, the theme's background, the Omarchy wallpaper or a picture; dim 0 to 0.95 darkens a picture (\"\" keeps either)"],
    ["lowerThird <on|off|\"\"> <seconds|\"\">", "the channel banner in full screen (1 to 15 s)"],
    ["card <on|off|\"\"> <seconds|\"\">", "the card shown when changing channel (0.6 to 5 s)"],
    ["home", "Home: on or not, its sections in order (with on/off), its tiles, its background, and the rows that can be added"],
    ["setHome <json>", "changes Home: {\"sections\": [{\"type\": \"continue\", \"on\": true}, {\"type\": \"genre\", \"key\": \"Feature Films\", \"on\": true, \"title\": \"Old movies\", \"size\": \"large\", \"limit\": 12, \"sort\": \"az\"}…], \"tiles\": [\"tv\", \"movies\"…] (in order), \"background\": {\"mode\": \"image\", \"image\": \"/path.jpg\", \"dim\": 0.6}, \"on\": true}; any part can be left out; rows: the built-in ones, or genre, channel, category, folder (a My Videos folder, . for itself), upcoming (a channel's url) with a key"],
    ["rail", "the nav rail: when it shows (always, focus: when the user goes to it, none) and its items in order, each on or off, and whether its part is turned on"],
    ["setRail <items> <always|focus|none|\"\">", "the nav rail's items, in order, with commas (search, home, tv, movies, ondemand, videos, recordings, mylist, apps, settings): the ones named are on, the rest off (settings stays); \"\" keeps them. Then when it shows (\"\" keeps it)"],
    ["videos <words>", "My Videos: on or not, its folder, and the videos in it matching the words (\"\" for the newest 100): {total, videos: [{id, title, folder, duration, added, resumeAt, inMyList}]}"],
    ["screenSaver", "the screen saver: on or not (only the user turns it on, in Settings: it keeps the computer from locking while Uber TV is on screen), showing now, the minutes before it starts, the pictures (both, omarchy or folder), how often they change, the clock, and the user's folder with how many pictures it has"],
    ["setScreenSaver '<json>'", "changes the screen saver: {\"after\": 10 (1, 2, 5, 10, 15 or 30 minutes), \"pictures\": \"both|omarchy|folder\", \"every\": 20 (10, 20, 30 or 60 seconds), \"clock\": \"bottomRight|bottomLeft|topRight|topLeft|middle|off\"}; turning it on and choosing its folder stay the user's. Answers what changed and what was ignored, and why"],
    ["setVideos <on|off|\"\"> <folder|\"\">", "My Videos on or off, and the folder it shows (a full path; \"\" keeps it, default the user's Videos folder)"],
    ["listings", "program listings (XMLTV) for IPTV channels: the sources, how many channels each matched, any error, when they were fetched, and how many IPTV channels have listings"],
    ["addListings <link|path>", "adds a source of program listings: a link to an XMLTV file (.xml, .xml.gz, .xml.xz) or a full path to one; it's fetched at once"],
    ["removeListings <link|path>", "takes a source of program listings off (only when the user asks)"],
    ["search <words>", "what matches the words, as Search shows it: channels (number, name, what's on), shows on now and later today, movies and series, YouTube videos and the user's videos, each with what to give watch or play"],
    ["shows <number> <words>", "the shows ahead in the listings (IPTV channels with listings, about a day and a half): a channel's (\"\" for every channel), the ones whose title or episode has the words (\"\" for all); the first 100, soonest first: {number, channel, title, episode, episodeNumber, start, end, when, onNow, recording}. Not a locked channel's. recordShow and recordSeries take its when"],
    ["library <words>", "movies and series in the library matching the words (\"\" for the first 100): {total, genres, items: [{id, title, genre, year, series, resumeAt, inMyList}]}"],
    ["play <id>", "plays a library item or one of the user's videos (its id from library or videos) or a YouTube video (yt:<video id>) full screen, from where the user stopped"],
    ["channels <words>", "channels matching the words (\"\" for the first 100): {total, channels: [{number, name, kind, category, live, shown}]}"],
    ["categories", "the categories with how many channels each, and what's shown"],
    ["addChannels <text>", "adds an M3U/M3U8 playlist (a URL or a file's full path), a channel list file, or YouTube links, @handles and names (one a line)"],
    ["demoChannels", "the demo lineup that comes with Uber TV: how many channels, its categories, and how many of them aren't in the guide yet"],
    ["loadDemoChannels", "adds the demo lineup's channels that aren't in the guide yet, in its categories; nothing is removed (only when the user asks, or agrees)"],
    ["status", "how the last addChannels went: {busy, checking, done, message, failed}"],
    ["show <both|youtube|iptv|\"\"> <categories|\"\"|->", "what the guide shows: a source and categories with commas (\"\" all, - keeps them)"],
    ["rename <number> <name>", "renames a channel"],
    ["setCategory <numbers> <category>", "files channels under a category (\"\" for none); numbers like 101,102 or 101-110"],
    ["removeChannels <numbers>", "removes channels (only when the user asks)"],
    ["logos <on|off>", "channel logos in the guide"],
    ["keyHints <on|off>", "the key hints along the bottom"],
    ["refresh", "fetches the listings again"],
    ["apps", "apps: whether they're on, Developer mode, the catalog, and the installed apps (id, name, version, on or off, on the screen now, where from, whether it's been checked, what each is allowed to do, any problem, an update waiting)"],
    ["appOff <id>", "turns one installed app off; it stays installed. Turning apps or an app on, installing, updating and removing them stay the user's, in Settings → Apps: there's no command for those"],
    ["appScreen <app id|all>", "how an app's screen looks and what's on it, by handle: its choices and the result, its rows in screen order {handle, position, label, shape, size, layout, titles, shown, from}, and while it's the screen its open and info items {handle, row, position, kind}; also onScreen, state, picturesPending, covered and view. Never an app's own ids or text"],
    ["setAppScreen <app id|all> '<json>'", "changes the user's choices for an app's screen (or all apps'): look, top, background, details, titles, size (null takes one off), rows by handle and order (a list of handles; not for all). Answers what it will save, what it ignored and why, and a saving token: state's saving says when it's saved"],
    ["resetAppScreen <app id|all>", "an app's screen follows all apps' settings again (all: the theme's). Only when the user asks"],
    ["openApp <app id> \"<handle or empty>\"", "opens an app that comes with the guide at its first screen, or (with a live item handle from appScreen) at that item: a screen for an open item, details for an info one. Never plays, presses a button, signs in or opens settings, and not while a box is open, something plays or the app has stopped working. Answers the view id it asked for"],
    ["appSnapshot <view>", "a picture (PNG) of an app's screen, only while that view is on the screen with nothing of the guide's over it (no box, Customize, rail, app box, nothing playing). Answers its file's name; state's snapshot says when it's written, or why it wasn't"]
  ]

  IpcHandler {
    id: ipc
    target: "om-pg"

    function help(): string {
      return commands.okReply({ commands: commands.commandHelp.map(function(c) { return { command: "omarchy-shell om-pg " + c[0], does: c[1] } }) })
    }

    function state(): string {
      return commands.okReply({ opened: guide.opened, watching: guide.watching, miniPlayer: guide.pip,
                            tuned: guide.tunedRow >= 0 && guide.channels[guide.tunedRow] ? commands.channelInfo(guide.tunedRow) : null,
                            channels: guide.channels.length, iptv: guide.channels.filter(function(c) { return c.kind === "iptv" }).length,
                            shownNow: guide.visibleRows.length, categories: guide.categories.length,
                            source: guide.shownSource, shownCategories: guide.shownCategories,
                            theme: guide.themeId, logos: guide.showLogos, keyHints: guide.showKeyHints, lineup: guide.lineupMode,
                            awake: guide.awake, keptAwake: guide.keptAwake, omarchySaver: !!guide.nativeSaver && guide.nativeSaver.up,
                            screenSaver: guide.screenSaver ? { on: guide.screenSaver.settings.on, showing: guide.screenSaver.showing } : null,
                            channelLock: guide.channelLock ? { passcode: guide.channelLock.set, on: guide.channelLock.on, locked: guide.channelLock.entries.length } : null,
                            adding: guide.jobTotal > 0 || /…$/.test(guide.addStatus),
                            saving: guide.appScreens ? guide.appScreens.saving : null,
                            snapshot: guide.snapshots ? guide.snapshots.report : null,
                            multiview: commands.multiviewInfo(),
                            recordings: { on: guide.recorder.settings.on, recording: guide.recorder.active.length,
                                          scheduled: guide.recorder.recordings.filter(DvrRules.waiting).length, series: guide.recorder.rules.length },
                            pauseAndRewind: { on: guide.pauser.turnedOn, running: guide.pauser.active, paused: guide.pauser.active && guide.pauser.paused,
                                              behindSeconds: guide.pauser.active && !guide.pauser.atLive ? Math.round(guide.pauser.behind / 1000) : 0 },
                            settingsProblem: guide.settingsProblem || undefined,
                            filesProblem: guide.filesProblem || undefined })
    }

    function open(): string {
      if (!guide.opened) guide.summonTo(guide.homeEnabled ? "home" : "guide")
      return commands.okReply({ note: "the guide is open", screen: guide.homeEnabled ? "home" : "guide" })
    }

    function display(mode: string): string {
      var m = String(mode).trim()
      if (m && m !== "full" && m !== "window") return commands.failReply("full, window or \"\"")
      if (m) guide.setDisplay(m)
      return commands.okReply({ display: guide.displayMode, note: guide.displayMode === "window" ? "an ordinary window, maximized, the Omarchy bar showing" : "full screen, over everything" })
    }

    function close(): string {
      guide.dismiss()
      return commands.okReply({ note: "the guide is closed" })
    }

    function watch(number: string): string {
      var r = commands.rowsFor(number)[0]
      if (r === undefined) return commands.failReply("no channel " + number + " (channels <words> finds its number)")
      if (!guide.airs(guide.channels[r])) return commands.failReply("that channel has nothing to show yet")
      if (guide.channelLock && guide.channelLock.blocks(guide.channels[r]))
        return commands.failReply(!guide.channelLock.loaded ? "the channel lock hasn't been read (" + (guide.channelLock.failed || "it's being read") + "): no channel plays until it is"
                                                            : "that channel is locked: only the user can unlock it, with the passcode, at the screen")
      if (guide.recorder.needsAsk(guide.channels[r]))
        return commands.failReply("a recording is using that channel's provider: watching it takes a 2nd stream, and a one-stream plan may stop the recording. Ask the user (the guide asks them when they go to it)")
      if (!guide.opened) guide.guidePip()
      commands.pendingWatch = guide.channels[r].url
      watchSoon.restart()
      return commands.okReply({ channel: commands.channelInfo(r) })
    }

    function multiview(numbers: string): string {
      var got = commands.multiviewRows(numbers)
      if (got.rows && got.rows.some(function(r) { return guide.recorder.needsAsk(guide.channels[r]) }))
        return commands.failReply("a recording is using the provider of one of those channels: it would take a 2nd stream, and a one-stream plan may stop the recording. Ask the user")
      if (got.error) return commands.failReply(got.error)
      if (!guide.opened || guide.pip) guide.guidePip()
      // a moment later (the guide opening), unless something's overtaken it (Guide.startMultiview)
      commands.pendingMultiview = { urls: got.rows.map(function(r) { return guide.channels[r].url }), request: guide.requestMultiview(), tries: 0 }
      multiviewSoon.restart()
      return commands.okReply({ channels: got.rows.map(commands.channelInfo), layout: guide.multiview.layoutsFor(got.rows.length)[0],
                                note: got.rows.length === 1 ? "one channel: Multiview opens with the Add a channel list, for the user to add more" : undefined })
    }

    function record(number: string, length: string): string {
      var d = guide.recorder
      if (!d.settings.on) return commands.failReply(commands.recordingsOff)
      var r = commands.rowsFor(number)[0]
      if (r === undefined) return commands.failReply("no channel " + number + " (channels <words> finds its number)")
      if (!guide.airs(guide.channels[r])) return commands.failReply("that channel has nothing to show yet")
      if (guide.channelLock && guide.channelLock.blocks(guide.channels[r]))
        return commands.failReply("that channel is locked: only the user can record it, with the passcode, at the screen")
      var len = String(length).trim().toLowerCase()
      var end = 0
      if (len) {
        var m = len.match(/^(\d+)\s*(m|min|minutes?|h|hours?)?$/)
        if (!m) return commands.failReply("a length in minutes (90) or hours (2h), or \"\" for its show's end (an hour without listings)")
        var secs = Number(m[1]) * (m[2] && m[2].charAt(0) === "h" ? 3600 : 60)
        if (secs < 60 || secs > DvrRules.MAX_HOURS * 3600) return commands.failReply("a minute to 12 hours")
        end = Math.round(Date.now() / 1000 + secs)
      }
      var o = d.offer(r)
      if (!o) return commands.failReply("nothing to record on that channel now")
      if (o.unavailable) return commands.failReply(o.note)
      if (d.busy) return commands.failReply("a recording is starting: ask again in a moment")
      var res = d.record(r, null, end)
      if (res !== "ok") return commands.failReply(res)
      return commands.okReply({ channel: commands.channelInfo(r), kind: o.job.kind, until: o.job.kind === "youtube-video" ? undefined : (end || o.job.end),
                                note: (o.note ? o.note + "; " : "") + "starting: recordings says when it's recording, or why it couldn't" })
    }

    function pauseLive(): string {
      var why = commands.pauseProblem()
      if (why) return commands.failReply(why)
      var res = guide.pauser.togglePause()
      return res === "ok" ? commands.okReply(commands.liveInfo()) : commands.failReply(res)
    }

    function seekLive(seconds: string): string {
      var n = Number(String(seconds).trim())
      if (String(seconds).trim() === "" || !isFinite(n)) return commands.failReply("seconds: a number (negative goes back)")
      var why = commands.pauseProblem()
      if (why) return commands.failReply(why)
      var res = guide.pauser.seekBy(n)
      return res === "ok" ? commands.okReply(commands.liveInfo()) : commands.failReply(res)
    }

    function goLive(): string {
      var why = commands.pauseProblem()
      if (why) return commands.failReply(why)
      var res = guide.pauser.live()
      return res === "ok" ? commands.okReply(commands.liveInfo()) : commands.failReply(res)
    }

    function recordUntil(id: string, when: string): string {
      var rec = commands.recordingById(id)
      if (!rec) return commands.failReply("no recording " + id + " (recordings lists them)")
      if (!DvrRules.active(rec) || rec.kind === "youtube-video") return commands.failReply("that one isn't recording")
      var t = String(when).trim()
      var now = Date.now() / 1000
      var end = 0
      var hm = t.match(/^(\d{1,2}):(\d{2})$/)
      if (hm) {
        var d = new Date()
        d.setHours(Number(hm[1]), Number(hm[2]), 0, 0)
        end = d.getTime() / 1000
        if (end <= now) end += 86400
      } else if (/^\d+$/.test(t)) end = now + Number(t) * 60
      else return commands.failReply("minutes from now (30), or a clock time (21:30)")
      var latest = (rec.start || rec.created || now) + DvrRules.MAX_HOURS * 3600   // from when it began
      if (end > latest) return commands.failReply("past 12 hours from its start (" + guide.clock(latest) + " at the latest)")
      guide.recorder.setEnd(rec.id, end)
      return commands.okReply({ id: rec.id, until: Math.round(end) })
    }

    function stopRecording(id: string): string {
      var rec = commands.recordingById(id)
      if (!rec) return commands.failReply("no recording " + id + " (recordings lists them)")
      if (!DvrRules.active(rec)) return commands.failReply("that one isn't recording")
      guide.recorder.stop(rec.id)
      return commands.okReply({ id: rec.id, note: "stopping: what's recorded is kept" })
    }

    function recordings(): string {
      guide.recorder.refresh()
      return commands.okReply({ settings: commands.recordingSettingsInfo(),
                                recordings: guide.recorder.recordings.slice(0, 300).map(commands.recordingInfo),
                                series: guide.recorder.rules.map(commands.seriesInfo) })
    }

    function recordShow(number: string, when: string): string {
      var d = guide.recorder
      if (!d.settings.on) return commands.failReply(commands.recordingsOff)
      var got = commands.laterShow(number, when, false)
      if (got.error) return commands.failReply(got.error)
      if (got.show.start <= Date.now() / 1000 + 60) return commands.failReply("that show is on now: record " + number + " records it")
      var o = d.laterOffer(got.row, got.show)
      if (!o) return commands.failReply("that show can't be scheduled")
      var res = d.schedule(got.row, got.show, null)
      if (res !== "ok") return commands.failReply(res)
      return commands.okReply({ channel: commands.channelInfo(got.row), title: got.show.title, start: got.show.start, end: got.show.end,
                                note: (o.why || o.note ? (o.why || o.note) + "; " : "") + "scheduling: recordings says Scheduled, or Conflict and why" })
    }

    function recordSeries(number: string, when: string): string {
      var d = guide.recorder
      if (!d.settings.on) return commands.failReply(commands.recordingsOff)
      var got = commands.laterShow(number, when, true)
      if (got.error) return commands.failReply(got.error)
      var res = d.recordSeries(got.row, got.show, null)
      if (res !== "ok") return commands.failReply(res)
      return commands.okReply({ channel: commands.channelInfo(got.row), title: got.show.title,
                                note: "every episode from now on as the listings have them (about a day and a half ahead, fetched twice a day); recordings lists the series and what's scheduled" })
    }

    function cancelRecording(id: string): string {
      var d = guide.recorder
      var key = String(id).trim()
      var rule = d.rules.filter(function(x) { return x.id === key })[0]
      if (rule) {
        d.stopSeries(rule.id)
        return commands.okReply({ series: rule.id, note: "the series stops: its shows not started yet are cancelled, what it recorded stays" })
      }
      var rec = commands.recordingById(key)
      if (!rec) return commands.failReply("no recording or series " + id + " (recordings lists them)")
      if (DvrRules.active(rec)) return commands.failReply("that one is recording: stopRecording stops it")
      if (!DvrRules.waiting(rec)) return commands.failReply("that one isn't scheduled (" + DvrRules.stateOf(rec) + ")")
      d.cancel(rec.id)
      return commands.okReply({ id: rec.id, note: rec.rule ? "cancelled; its series won't schedule this episode again" : "cancelled" })
    }

    function playRecording(id: string): string {
      var rec = commands.recordingById(id)
      if (!rec) return commands.failReply("no recording " + id + " (recordings lists them)")
      if (guide.recorder.locked(rec)) return commands.failReply("that's a locked channel's recording: only the user can unlock it, with the passcode, at the screen")
      if (!DvrRules.playable(rec)) return commands.failReply(DvrRules.stateOf(rec) === "Drive missing" ? "its drive isn't plugged in" : "it isn't ready to play (" + DvrRules.stateOf(rec) + ")")
      if (!guide.opened) guide.guidePip()
      commands.pendingRecording = { id: rec.id, tries: 0 }
      recordingSoon.restart()
      return commands.okReply({ id: rec.id, note: "playing once the guide is up (checked again then)" })
    }

    // a recording, a library item or one of the user's videos, from the start
    function startOver(id: string): string {
      var key = String(id).trim()
      var rec = commands.recordingById(key)
      if (rec) {
        if (guide.recorder.locked(rec)) return commands.failReply("that's a locked channel's recording: only the user can unlock it, with the passcode, at the screen")
        if (!DvrRules.playable(rec)) return commands.failReply(DvrRules.stateOf(rec) === "Drive missing" ? "its drive isn't plugged in" : "it isn't ready to play (" + DvrRules.stateOf(rec) + ")")
        if (!guide.opened) guide.guidePip()
        commands.pendingRecording = { id: rec.id, tries: 0, fromStart: true }
        recordingSoon.restart()
        return commands.okReply({ id: rec.id, from: 0, note: "playing from the start once the guide is up (checked again then)" })
      }
      var entry = guide.entryFor(key)
      if (!entry) return commands.failReply("nothing with id \"" + id + "\" (recordings lists recordings, library \"<words>\" movies, videos \"<words>\" the user's videos; a YouTube video is yt:<its id>)")
      if (entry.videoId && guide.videoLockedBy(entry.videoId, entry.subtitle, entry.owners, entry.ownersMore)) return commands.failReply("that video is from a locked channel: only the user can unlock it, with the passcode, at the screen")
      if (!guide.opened) guide.guidePip()
      commands.pendingPlay = entry
      commands.pendingFrom = 0
      playSoon.restart()
      return commands.okReply({ playing: entry.title, from: 0 })
    }

    // the shows ahead in the listings: a channel's, or all channels' matching the words
    function shows(number: string, words: string): string {
      var rows = []
      if (String(number).trim()) {
        var one = commands.rowsFor(number)[0]
        if (one === undefined) return commands.failReply("no channel " + number + " (channels <words> finds its number)")
        var c1 = guide.channels[one]
        if (c1.kind !== "iptv" || !guide.listingsHave(c1)) return commands.failReply("that channel has no listings (an IPTV channel with listings)")
        if (guide.titlesHidden(c1)) return commands.failReply("that channel is locked: its shows aren't listed")
        rows = [one]
      } else for (var i = 0; i < guide.channels.length; i++) rows.push(i)
      var terms = String(words).toLowerCase().split(/\s+/).filter(function(t) { return t })
      var now = Date.now() / 1000
      // every match counted, only the soonest 100 kept (in order, as they're found)
      var kept = []
      var total = 0
      var before = function(a, b) { return a.s[0] - b.s[0] || a.n - b.n }
      for (var k = 0; k < rows.length; k++) {
        var ch = guide.channels[rows[k]]
        if (ch.kind !== "iptv" || !guide.listingsHave(ch) || guide.titlesHidden(ch)) continue   // a locked channel's shows aren't found by their titles
        var n = guide.numbers[rows[k]]
        guide.eachListed(ch, now, now + 2 * 86400, function(s) {
          if (terms.length) {
            var hay = (s[2] + " " + (s[5] || "")).toLowerCase()
            for (var q = 0; q < terms.length; q++) if (hay.indexOf(terms[q]) < 0) return
          }
          total++
          var f = { r: rows[k], ch: ch, n: n, s: s }
          if (kept.length >= 100 && before(f, kept[kept.length - 1]) >= 0) return
          var lo = 0, hi = kept.length
          while (lo < hi) { var mid = (lo + hi) >> 1; if (before(kept[mid], f) <= 0) lo = mid + 1; else hi = mid }
          kept.splice(lo, 0, f)
          if (kept.length > 100) kept.pop()
        })
      }
      return commands.okReply({ total: total, more: total > 100,
                                shows: kept.map(function(f) {
                                  var s = guide.listedShow(f.s)
                                  return { number: guide.numbers[f.r], channel: f.ch.name, title: s.title, episode: s.sub || undefined, episodeNumber: s.ep || undefined,
                                           start: s.start, end: s.end, when: Qt.formatDateTime(new Date(s.start * 1000), "yyyy-MM-dd HH:mm"),
                                           onNow: s.start <= now, recording: guide.recMark(f.ch, s) || undefined }
                                }),
                                note: "watch <number> puts one on now; recordShow <number> \"<when>\" records a later one, recordSeries every episode" })
    }

    function removeRecording(id: string): string {
      var rec = commands.recordingById(id)
      if (!rec) return commands.failReply("no recording " + id + " (recordings lists them)")
      guide.recorder.remove(rec.id)
      return commands.okReply({ id: rec.id, note: DvrRules.stateOf(rec) === "Drive missing" ? "taken off the list (its file stays on the drive)" : "deleted: its file, details and picture" })
    }

    function recordingDrives(): string {
      guide.recorder.listDrives()
      return commands.okReply({ drives: commands.recordingSettingsInfo().drives, note: "listed again just now: ask again in a moment for the newest" })
    }

    function recordingSettings(): string {
      guide.recorder.checkPlace()
      return commands.okReply(commands.recordingSettingsInfo())
    }

    function setRecordingSettings(json: string): string {
      var given
      try { given = JSON.parse(String(json)) } catch (e) { return commands.failReply("not valid JSON: " + e.message) }
      if (!given || typeof given !== "object" || Array.isArray(given)) return commands.failReply("{\"on\", \"place\", \"keepFree\", \"quality\", \"padding\", \"atOnce\", \"pauseAndRewind\"}")
      var d = guide.recorder
      var ignored = []
      var changes = {}
      var note = ""
      for (var k in given) if (["on", "place", "keepFree", "quality", "padding", "atOnce", "pauseAndRewind", "stopAndCancel"].indexOf(k) < 0) ignored.push(k)
      if (given.on !== undefined) {
        if (typeof given.on !== "boolean") ignored.push("on (true or false)")
        else if (!given.on && d.settings.on && (d.active.length || d.busy || d.hasWaiting) && given.stopAndCancel !== true)
          return commands.failReply("turning Recordings off would " + guide.recOffWhat() + ": "
                                    + (d.active.concat(d.recordings.filter(DvrRules.waiting)).map(function(r) { return commands.recordingInfo(r).title || "a recording" }).join(", ") || "one starting")
                                    + ". Ask the user; then again with \"stopAndCancel\": true")
        else if (!given.on && d.settings.on) d.turnOff()
        else if (given.on) changes.on = true
      }
      if (given.keepFree !== undefined) {
        if (given.keepFree === "auto") changes.keepFree = 0
        else if (DvrRules.KEEP_FREE.indexOf(given.keepFree) >= 0) changes.keepFree = given.keepFree
        else ignored.push("keepFree (\"auto\" or " + DvrRules.KEEP_FREE.join(", ") + ")")
      }
      if (given.quality !== undefined) {
        if (given.quality === "auto") changes.quality = 0
        else if (DvrRules.QUALITIES.indexOf(given.quality) >= 0) changes.quality = given.quality
        else ignored.push("quality (\"auto\" or " + DvrRules.QUALITIES.join(", ") + ")")
      }
      if (given.padding !== undefined) {
        if (given.padding === 0 || given.padding === 1 || given.padding === 2) changes.padding = given.padding
        else ignored.push("padding (0, 1 or 2)")
      }
      if (given.atOnce !== undefined) {
        if (DvrRules.AT_ONCE.indexOf(given.atOnce) >= 0) changes.atOnce = given.atOnce
        else ignored.push("atOnce (" + DvrRules.AT_ONCE.join(", ") + ")")
      }
      if (given.pauseAndRewind !== undefined) {
        if (Ts.MINUTES.indexOf(given.pauseAndRewind) >= 0) changes.timeshift = given.pauseAndRewind
        else ignored.push("pauseAndRewind (" + Ts.MINUTES.join(", ") + ")")
      }
      if (Object.keys(changes).length) d.set(changes)
      if (given.place !== undefined) {
        var pl = String(given.place).trim()
        if (pl === "videos") d.useDefault()
        else if (pl.indexOf("drive:") === 0) {
          var dev = pl.slice(6)
          var drive = d.drives.filter(function(x) { return x.device === dev })[0]
          if (!drive) ignored.push("place (no such drive: recordingDrives lists them)")
          else if (!drive.mount) ignored.push("place (that drive isn't opened: the user opens it in Settings → Recordings)")
          else { d.useFolder(drive.mount); note = "checked and made ready first: recordingSettings says where, in a moment" }
        } else if (pl.charAt(0) === "/") { d.useFolder(pl); note = "checked and made ready first: recordingSettings says where, in a moment (or why not)" }
        else ignored.push("place (\"videos\", a folder's full path, or \"drive:<device>\")")
      }
      return commands.okReply({ settings: commands.recordingSettingsInfo(), ignored: ignored, note: note || undefined })
    }

    function libraryTabs(): string {
      return commands.okReply({ tabs: guide.checkedLibraryOrder(guide.libraryOrder).map(function(k) {
        var t = guide.libraryTabKinds.filter(function(x) { return x.key === k })[0]
        return { key: k, label: t.label, shown: guide.libraryTabShown(k) }
      }), note: "My Videos shows while it's on; Recordings while it's on or there are some" })
    }

    function setLibraryTabs(keys: string): string {
      var list = String(keys).split(",").map(function(k) { return k.trim().toLowerCase() }).filter(function(k) { return k })
      var known = guide.libraryTabKinds.map(function(t) { return t.key })
      var ignored = list.filter(function(k) { return known.indexOf(k) < 0 })
      guide.libraryOrder = guide.checkedLibraryOrder(list)
      guide.saveSettings()
      return commands.okReply({ order: guide.libraryOrder, ignored: ignored.map(function(k) { return k + " (" + known.join(", ") + ")" }) })
    }

    function multiviewAdd(number: string): string {
      var mv = guide.multiview
      if (!mv.active) return commands.failReply(commands.multiviewOff)
      if (mv.count >= 4) return commands.failReply("Multiview holds four channels: take one off first (multiviewRemove <number>)")
      var got = commands.multiviewRows(number)
      if (got.rows && got.rows.some(function(r) { return guide.recorder.needsAsk(guide.channels[r]) }))
        return commands.failReply("a recording is using that channel's provider: it would take a 2nd stream, and a one-stream plan may stop the recording. Ask the user")
      if (got.error) return commands.failReply(got.error)
      if (got.rows.length !== 1) return commands.failReply("one channel number")
      if (mv.addTile(guide.channels[got.rows[0]].url) < 0) return commands.failReply("channel " + String(number).trim() + " is on Multiview already")
      if (mv.mode === "picker" && mv.pickMode === "add" && mv.count >= 4) mv.mode = "tiles"
      return commands.okReply({ multiview: commands.multiviewInfo() })
    }

    function multiviewRemove(number: string): string {
      var mv = guide.multiview
      if (!mv.active) return commands.failReply(commands.multiviewOff)
      var slot = commands.multiviewSlot(number)
      if (slot < 0) return commands.failReply("channel " + String(number).trim() + " isn't on Multiview")
      var closes = mv.count <= 2
      var left = mv.order.filter(function(x) { return x !== slot })[0]
      var leftNumber = left !== undefined && mv.rowOf(left) >= 0 ? guide.numbers[mv.rowOf(left)] : null
      mv.remove(slot)
      return commands.okReply({ multiview: commands.multiviewInfo(),
                                note: closes ? "Multiview closed" + (leftNumber !== null ? ": channel " + leftNumber + " plays full screen" : "") : undefined })
    }

    function multiviewLayout(layout: string): string {
      var mv = guide.multiview
      if (!mv.active) return commands.failReply(commands.multiviewOff)
      if (!mv.setLayout(String(layout).trim()))
        return commands.failReply("with " + mv.count + " channel" + (mv.count === 1 ? "" : "s") + ": " + mv.layoutsFor(mv.count).join(", "))
      return commands.okReply({ multiview: commands.multiviewInfo() })
    }

    function multiviewSound(number: string): string {
      var mv = guide.multiview
      if (!mv.active) return commands.failReply(commands.multiviewOff)
      var slot = commands.multiviewSlot(number)
      if (slot < 0) return commands.failReply("channel " + String(number).trim() + " isn't on Multiview")
      mv.select(slot)
      return commands.okReply({ multiview: commands.multiviewInfo() })
    }

    function multiviewClose(): string {
      var mv = guide.multiview
      if (!mv.active) return commands.failReply(commands.multiviewOff)
      var sound = mv.rowOf(mv.sel)
      mv.exit()
      return commands.okReply({ note: "Multiview closed" + (sound >= 0 ? ": channel " + guide.numbers[sound] + " plays full screen" : "") })
    }

    function themes(): string {
      return commands.okReply({ themes: guide.themes.map(commands.themeInfo) })
    }

    function theme(id: string): string {
      if (guide.themeStore.changing) return commands.failReply(guide.themeStore.busyWhy)
      if (!guide.applyTheme(String(id).trim()))
        return commands.failReply("no theme \"" + id + "\"; there's " + guide.themes.map(function(t) { return t.id }).join(", "))
      return commands.okReply({ theme: commands.themeInfo(guide.currentTheme), yourColorsOnTop: Object.keys(guide.colorOverrides) })
    }

    function addTheme(json: string): string {
      var text = String(json).trim()
      if (/^[~\/]/.test(text)) return commands.failReply("give the theme's JSON itself, not a path: omarchy-shell om-pg addTheme \"$(cat theme.json)\"")
      if (text.length > 65536) return commands.failReply("that's too big for a theme")
      var given
      try { given = JSON.parse(text) } catch (e) { return commands.failReply("not valid JSON: " + e.message) }
      if (!given || typeof given !== "object" || Array.isArray(given)) return commands.failReply("a theme is a JSON object: {\"name\": ..., \"colors\": {...}}")
      var id = guide.themeIdFrom(given.id || given.name)
      if (!id) return commands.failReply("give the theme a name")
      if (id === "retro" || guide.themes.some(function(t) { return t.id === id && t.builtIn })) return commands.failReply("\"" + id + "\" is a built-in theme: give yours another name")
      var checked = guide.checkTheme(given, id, false, guide.themesDir + "/" + id)
      if (!Look.themeUsable(checked.theme))
        return commands.failReply("nothing it could use: give colors (slots: " + guide.colorKeys.join(" ") + "), elements, fonts, layout or apps")
      // saved as one confirmed transaction, and put on only once it's saved
      var onTop = guide.onTopOf(checked.theme)
      var saving = guide.saveThemeFiles(id, checked.theme, "theme " + id + ": added")
      if (!saving.ok) return commands.failReply(saving.error)
      return commands.okReply({ theme: commands.themeInfo(checked.theme), folder: guide.themesDir + "/" + id, ignored: checked.ignored,
                            slotsLeftAtRetro: guide.colorSlots.filter(function(c) { return !checked.theme.colors[c.key] }).map(function(c) { return c.key }),
                            yourColorsOnTop: onTop.colors, yourStylesOnTop: onTop.styles, saving: saving.token,
                            note: "it's put on once state's saving says saved for this token" })
    }

    function saveTheme(name: string, description: string): string {
      var done = guide.saveLookAsTheme(String(name), String(description), false)
      if (!done.ok) return commands.failReply(done.error + (done.taken ? ": give it another name, or (if the user wants that one replaced) removeTheme it first" : ""))
      return commands.okReply({ theme: commands.themeInfo(done.theme), folder: guide.themesDir + "/" + done.id, replaced: done.replaced, saving: done.saving,
                                note: "it's put on once state's saving says saved for this token" })
    }

    function removeTheme(id: string): string {
      var t = null
      for (var i = 0; i < guide.themes.length; i++) if (guide.themes[i].id === String(id).trim()) t = guide.themes[i]
      if (!t) return commands.failReply("no theme \"" + id + "\"")
      if (t.builtIn) return commands.failReply("\"" + t.id + "\" is built in: it can't be removed")
      // removed as a confirmed transaction; once it's gone from disk, it's gone from the list
      var res = guide.themeStore.remove(t.id, "theme " + t.id + ": removed", function(outcome) {
        if (outcome === "failed") return
        guide.themes = guide.themes.filter(function(x) { return x.id !== t.id })
        if (guide.themeId === t.id) guide.applyTheme(guide.defaultThemeId)
      })
      if (!res.ok) return commands.failReply(res.error)
      return commands.okReply({ removing: t.id, saving: res.token, note: "it's gone once state's saving says saved for this token" })
    }

    function slots(): string {
      return commands.okReply({ slots: guide.colorSlots.map(function(c) {
        return { key: c.key, section: c.section, label: c.label, theme: guide.themeColor(c.key), yours: guide.colorOverrides[c.key] || "", now: guide.colors[c.key] }
      }) })
    }

    function style(): string {
      return commands.okReply(commands.styleState())
    }

    function setColor(key: string, value: string): string {
      var k = String(key).trim()
      var v = String(value).trim()
      if (!guide.slotOf(k)) return commands.failReply("no slot \"" + k + "\"; slots are " + guide.colorSlots.map(function(c) { return c.key }).join(" "))
      if (v && !guide.isHex(v)) return commands.failReply("not a color: use #rrggbb, or #aarrggbb to make it see-through")
      guide.setOverride(k, v)
      guide.saveSettings()
      return commands.okReply({ key: k, now: guide.colors[k], yours: guide.colorOverrides[k] || "" })
    }

    function reset(what: string): string {
      var w = String(what).trim().toLowerCase()
      if (w === "undo") {
        var undone = guide.undoReset()
        if (!undone.ok) return commands.failReply(undone.error)
        return commands.okReply({ note: "the look from before the last reset is back", style: commands.styleState(), saving: undone.saving || undefined })
      }
      if (w !== "theme" && w !== "original") return commands.failReply("reset theme (the user's changes off, the theme stays), reset original (Premiere, as it comes) or reset undo")
      var done = guide.resetStyle(w)
      if (!done.ok) return commands.failReply(done.error)
      return commands.okReply({ note: w === "original" ? "back to the original look: Premiere, no changes" : "back to " + guide.currentTheme.name + " as the theme has it",
                            undo: "omarchy-shell om-pg reset undo", style: commands.styleState(), saving: done.saving || undefined })
    }

    function resetColors(): string {
      guide.colorOverrides = ({})
      guide.saveSettings()
      return commands.okReply({ theme: guide.themeId })
    }

    function images(): string {
      return commands.okReply({ images: guide.imageSlots.map(function(slot) {
        var now = guide.areaImages[slot.key]
        var mine = guide.imageOverrides[slot.key]
        return { area: slot.key, name: guide.imageAreaName(slot.key), picture: now ? now.path : "", fit: now ? now.fit : slot.fit,
                 opacity: now ? now.opacity : slot.opacity, from: mine !== undefined ? (mine.src ? "yours" : "") : now ? "theme" : "" }
      }), fits: guide.imageFits })
    }

    function setImage(area: string, picture: string, fit: string, opacity: string): string {
      var key = String(area).trim()
      var slot = guide.imageSlotOf(key)
      if (!slot) return commands.failReply("no area \"" + key + "\"; areas are " + guide.imageSlots.map(function(s) { return s.key }).join(" "))
      var pic = String(picture).trim()
      var now = guide.areaImages[key]
      var spec
      if (pic === "theme") {
        guide.setImageOverride(key, undefined)
        guide.saveSettings()
        return commands.okReply({ area: key, now: guide.areaImages[key] ? guide.areaImages[key].path : "" })
      }
      if (pic === "none") spec = { src: "" }
      else if (pic === "") {
        if (!now) return commands.failReply("there's no picture there yet: give one (a full path)")
        spec = { src: now.path, fit: now.fit, opacity: now.opacity }
      }
      else if (/^(~\/|\/).+\.(jpe?g|png|webp)$/i.test(pic))
        spec = { src: pic.replace(/^~(?=\/)/, Quickshell.env("HOME")), fit: now ? now.fit : slot.fit, opacity: now ? now.opacity : slot.opacity }
      else return commands.failReply("a picture's full path (.jpg, .png or .webp), none, theme, or \"\" to keep it")
      var f = String(fit).trim().toLowerCase()
      if (f) {
        if (guide.imageFits.indexOf(f) < 0) return commands.failReply("fit is one of " + guide.imageFits.join(", "))
        if (spec.src) spec.fit = f
      }
      var o = String(opacity).trim()
      if (o) {
        if (isNaN(Number(o)) || Number(o) < 0.1 || Number(o) > 1) return commands.failReply("opacity is 0.1 to 1")
        if (spec.src) spec.opacity = Math.round(Number(o) * 100) / 100
      }
      guide.setImageOverride(key, spec)
      guide.saveSettings()
      var after = guide.areaImages[key]
      return commands.okReply({ area: key, picture: after ? after.path : "", fit: after ? after.fit : "", opacity: after ? after.opacity : 0 })
    }

    function background(mode: string, dim: string): string {
      var m = String(mode).trim()
      if (m === "none" || m === "wallpaper") guide.bgMode = m
      else if (/^(~\/|\/).+\.(jpe?g|png|webp)$/i.test(m)) {
        guide.bgImage = m.replace(/^~(?=\/)/, Quickshell.env("HOME"))
        guide.bgMode = "image"
        guide.bgFrom = "user"
      }
      else if (m) return commands.failReply("none, wallpaper, or a picture's full path (.jpg, .png or .webp)")
      var d = String(dim).trim()
      if (d) {
        if (isNaN(Number(d)) || Number(d) < 0 || Number(d) > 0.95) return commands.failReply("dim is 0 (none) to 0.95")
        guide.bgDim = Math.round(Number(d) * 100) / 100
      }
      guide.saveSettings()
      return commands.okReply({ background: commands.styleState().background })
    }

    function multiviewBackground(mode: string, dim: string): string {
      var m = String(mode).trim()
      var changes = {}
      var picture = ""
      if (m === "none" || m === "theme" || m === "wallpaper") changes.mode = m
      else if (guide.solidHex(m)) { changes.mode = "color"; changes.color = m.toLowerCase() }
      else if (/^(~\/|\/).+\.(jpe?g|png|webp)$/i.test(m)) picture = m.replace(/^~(?=\/)/, Quickshell.env("HOME"))
      else if (m) return commands.failReply("none, a color (#rrggbb), theme, wallpaper, or a picture's full path (.jpg, .png or .webp)")
      var d = String(dim).trim()
      if (d) {
        if (isNaN(Number(d)) || Number(d) < 0 || Number(d) > 0.95) return commands.failReply("dim is 0 (none) to 0.95")
        changes.dim = Math.round(Number(d) * 100) / 100
      }
      if (Object.keys(changes).length) guide.setMultiviewBackground(changes)
      // a picture is checked and copied by the helper first, and shown once it's in
      if (picture) guide.multiviewPicture(picture)
      return commands.okReply({ background: guide.multiviewBackground, note: picture ? "the picture is checked and copied first: Multiview shows it once it's in" : undefined })
    }

    function lowerThird(show: string, seconds: string): string {
      var on = commands.onOff(show)
      if (String(show).trim() && on === null) return commands.failReply("on or off (\"\" keeps it)")
      var secs = String(seconds).trim()
      if (secs && (isNaN(Number(secs)) || Number(secs) < 1 || Number(secs) > 15)) return commands.failReply("seconds: 1 to 15")
      if (on !== null) guide.ltShow = on
      if (secs) guide.ltSeconds = Math.round(Number(secs))
      guide.saveSettings()
      return commands.okReply({ lowerThird: commands.styleState().lowerThird })
    }

    function card(show: string, seconds: string): string {
      var on = commands.onOff(show)
      if (String(show).trim() && on === null) return commands.failReply("on or off (\"\" keeps it)")
      var secs = String(seconds).trim()
      if (secs && (isNaN(Number(secs)) || Number(secs) < 0.6 || Number(secs) > 5)) return commands.failReply("seconds: 0.6 to 5")
      if (on !== null) guide.cardShow = on
      if (secs) guide.cardSeconds = Math.round(Number(secs) * 10) / 10
      guide.saveSettings()
      return commands.okReply({ card: commands.styleState().card })
    }

    function elements(name: string): string {
      var key = String(name).trim()
      var theme = guide.currentTheme.elements || {}
      var yours = guide.elementOverrides
      if (key) {
        var d = Look.describe(key.split(":")[0], theme, yours)
        return d ? commands.okReply(d) : commands.failReply("no element \"" + key + "\" (elements \"\" lists them)")
      }
      return commands.okReply({
        about: "Every part of the guide, styled by the theme, with the user's own (setStyle) on top. elements <name> shows one: what it takes, Retro's style, the theme's, the user's and what's on screen now.",
        lengths: "units, a 60th of the screen's height (so a theme looks the same on any screen), or \"2px\"; keycap radius, depth and text sizes go by the key's height",
        colors: "#rrggbb, #aarrggbb, a color slot's name (accent, cell…: the theme's colors, with the user's) or none",
        box: { fill: "a color, or {from, to, direction: down|up|right|left}", border: "{width, color, sides: all or [top, bottom, left, right]} or none",
               radius: "a length, or [top left, top right, bottom right, bottom left]", shape: Look.SHAPES.join(", "),
               slant: "slant, arrow and chevron: how far the ends lean or point", path: "shape path: an SVG path drawn in a 100 by 100 box",
               shadow: "{color, blur, x, y} or none (not on every cell, only the selected or current one)", padding: "space inside, a length" },
        text: { color: "a color", font: "body, display, mono, or an installed family (fonts lists them)", size: "units", weight: "thin, light, normal, medium, semibold, bold, black or 100-900",
                case: Look.CASES.join(", "), letterSpacing: "units", italic: "true or false" },
        fonts: guide.fonts,
        layout: Look.LAYOUT.map(function(l) {
          return { setting: l.key, about: l.about, takes: l.kind === "bool" ? "true or false" : Array.isArray(l.kind) ? l.kind : l.min + " to " + l.max,
                   retro: l.value, now: guide.layout[l.key] }
        }),
        elements: Look.ELEMENTS.map(function(e) {
          var info = { element: e.key, section: e.section, label: e.label, about: e.about, states: e.states || [],
                       theme: Object.keys(theme).some(function(k) { return k.split(":")[0] === e.key }),
                       yours: Object.keys(yours).some(function(k) { return k.split(":")[0] === e.key }) }
          if (e.follows) info.follows = e.follows   // looks like that part until it's styled
          return info
        })
      })
    }

    function setStyle(element: string, style: string): string {
      var name = String(element).trim()
      var text = String(style).trim()
      if (name === "fonts") return commands.setFonts(text)
      if (name === "layout") return commands.setLayout(text)
      var key = name.split(":")[0]
      var el = Look.BY_KEY[key]
      if (!el) return commands.failReply("no element \"" + name + "\" (elements \"\" lists them)")
      var state = name.split(":")[1]
      if (state !== undefined && (el.states || []).indexOf(state) < 0)
        return commands.failReply(key + (el.states ? " has states " + el.states.join(", ") : " has no states"))
      var all = {}
      for (var k in guide.elementOverrides) all[k] = guide.elementOverrides[k]
      if (text === "theme") {
        delete all[name]
        guide.elementOverrides = all
        guide.saveSettings()
        return commands.okReply({ element: name, yours: null, now: Look.effective(guide.currentTheme.elements, all)[name] })
      }
      if (text.length > 16384) return commands.failReply("that's too big for one element")
      var given
      try { given = JSON.parse(text) } catch (e) { return commands.failReply("not valid JSON: " + e.message) }
      if (!given || typeof given !== "object" || Array.isArray(given)) return commands.failReply("a style is a JSON object, like {\"radius\": 0.4}")
      // null takes one of the user's properties off (the theme's shows again)
      var off = []
      var keep = {}
      for (var p in given) {
        if (given[p] === null) off.push(p)
        else if (p === "text" && given.text && typeof given.text === "object") {
          var t = {}
          for (var tp in given.text) { if (given.text[tp] === null) off.push("text." + tp); else t[tp] = given.text[tp] }
          keep.text = t
        } else keep[p] = given[p]
      }
      var input = {}
      input[name] = keep
      var checked = Look.checkElements(input, guide.colorKeys, guide.installedFonts)
      var mine = Look.merge(all[name] || {}, checked.elements[name] || {})
      for (var o = 0; o < off.length; o++) {
        var path = off[o].split(".")
        if (path.length === 2) { if (mine.text) { delete mine.text[path[1]]; if (!Object.keys(mine.text).length) delete mine.text } }
        else delete mine[path[0]]
      }
      if (Object.keys(mine).length) all[name] = mine
      else delete all[name]
      guide.elementOverrides = all
      guide.saveSettings()
      return commands.okReply({ element: name, yours: all[name] || null, now: Look.effective(guide.currentTheme.elements, all)[name], ignored: checked.ignored })
    }

    function fonts(words: string): string {
      var terms = String(words).toLowerCase().split(/\s+/).filter(function(t) { return t })
      var seen = {}
      var list = guide.installedFonts.filter(function(f) {
        var l = f.toLowerCase()
        if (seen[l]) return false
        seen[l] = true
        return terms.every(function(t) { return l.indexOf(t) >= 0 })
      })
      return commands.okReply({ now: guide.fonts, theme: guide.currentTheme.fonts || {}, yours: guide.fontOverrides,
                                total: list.length, families: list.slice(0, 150), more: list.length > 150 })
    }

    function snapshot(path: string): string {
      var shot = guide.snapshot(path)
      return shot.error ? commands.failReply(shot.error) : commands.okReply({ path: shot.path, width: shot.width, height: shot.height,
                                                                              note: "read it once state's snapshot has this name and says written; refused says why not" })
    }

    function home(): string {
      return commands.okReply({
        on: guide.homeEnabled,
        sections: guide.homeSections.map(function(s) { return { type: s.type, key: s.key || "", on: s.on, title: guide.homeTitle(s), named: !!s.title,
                                                                size: s.size || "medium", shape: s.shape || "auto", limit: s.limit || 0, sort: s.sort || "default" } }),
        rowOptions: { title: "a name (\"\" for its own)", size: guide.homeSizes, shape: ["auto", "poster", "wide"], limit: guide.homeLimits, sort: guide.homeSorts },
        screen: { top: guide.homeTop, clock: guide.layout.homeClock, chips: guide.layout.homeChips,
                  note: "setStyle layout {\"homeTop\": \"selected|clock|channel\", \"homeHero\": true|false, \"homeClock\": \"left|right|none\", \"homeChips\": true|false}" },
        tiles: guide.homeTiles, allTiles: guide.homeTileKinds.map(function(t) { return t.key }),
        background: guide.homeBackground,
        backgroundModes: guide.homeBgModes,
        builtInSections: Object.keys(guide.homeTypes),
        rowsYouCanAdd: { genre: guide.libraryGenres().map(function(g) { return g.genre }),
                         channel: guide.channels.filter(function(c) { return c.kind !== "iptv" }).slice(0, 100).map(function(c) { return { key: c.url, name: c.name } }),
                         category: guide.categories.filter(function(c) { return c }),
                         folder: guide.myVideoFolders(),
                         upcoming: guide.channels.filter(function(c) { return c.kind === "iptv" ? guide.epg.has(c.url) : c.state === "ready" && !c.live }).slice(0, 100).map(function(c) { return { key: c.url, name: c.name } }) }
      })
    }

    function setHome(json: string): string {
      var given
      try { given = JSON.parse(String(json)) } catch (e) { return commands.failReply("not valid JSON: " + e.message) }
      if (!given || typeof given !== "object" || Array.isArray(given)) return commands.failReply("{\"sections\": [...], \"tiles\": [...], \"background\": {...}, \"on\": true}")
      var ignored = []
      var note = ""
      for (var k in given) if (["on", "sections", "tiles", "background"].indexOf(k) < 0) ignored.push(k + " (on, sections, tiles or background)")
      if (given.on !== undefined) { if (typeof given.on === "boolean") guide.homeEnabled = given.on; else ignored.push("on (true or false)") }
      if (given.sections !== undefined) {
        var secs = guide.checkedHomeSections(given.sections)
        if (secs && secs.length) guide.homeSections = secs
        else ignored.push("sections (a list of {type, key, on}: " + Object.keys(guide.homeTypes).join(", ") + ", or genre, channel, category with a key)")
        if (secs && Array.isArray(given.sections) && secs.length < given.sections.length) ignored.push((given.sections.length - secs.length) + " of the sections (unknown, repeated, or missing a key)")
      }
      if (given.tiles !== undefined) {
        var kinds = guide.homeTileKinds.map(function(t) { return t.key })
        if (Array.isArray(given.tiles)) guide.homeTiles = given.tiles.filter(function(t, i, all) { return kinds.indexOf(t) >= 0 && all.indexOf(t) === i })
        else ignored.push("tiles (a list, in order, of " + kinds.join(", ") + ")")
      }
      if (given.background !== undefined) {
        var b = given.background || {}
        var changes = {}
        if (b.mode !== undefined) { if (guide.homeBgModes.indexOf(b.mode) >= 0) changes.mode = b.mode; else ignored.push("background.mode (" + guide.homeBgModes.join(", ") + ")") }
        var picture = ""
        if (b.image !== undefined) { if (typeof b.image === "string" && /^\/.+\.(jpe?g|png|webp)$/i.test(b.image)) picture = b.image; else ignored.push("background.image (a full path to a .jpg, .png or .webp)") }
        if (b.dim !== undefined) { if (typeof b.dim === "number") changes.dim = Math.max(0, Math.min(0.95, b.dim)); else ignored.push("background.dim (0 to 0.95)") }
        if (changes.mode === "image" && !picture && !guide.homeBackground.image) { delete changes.mode; ignored.push("background.mode image needs background.image") }
        // a picture is checked and copied by the helper first, and shown once it's in (mode image with it)
        var pictureMode = picture && changes.mode === "image" ? "image" : ""
        if (pictureMode) delete changes.mode
        guide.setHomeBackground(changes)
        if (picture) { guide.homePicture(picture, pictureMode); note = "the picture is checked and copied first: home shows it once it's in (or says why not)" }
      }
      guide.saveSettings()
      return commands.okReply({ sections: guide.homeSections, tiles: guide.homeTiles, background: guide.homeBackground, on: guide.homeEnabled, ignored: ignored, note: note || undefined })
    }

    function rail(): string {
      return commands.okReply({
        shows: guide.layout.rail,
        items: guide.railSetup.map(function(it) {
          return { key: it.key, label: guide.railKind(it.key).label, on: it.on, partOn: guide.railAvailable(it.key), onRail: guide.railItems.some(function(r) { return r.key === it.key }) }
        }),
        note: "an item whose part is off (Home screen, My Videos, Apps while apps are off, Recordings while they're off and there are none) stays off the rail until the part is turned on"
      })
    }

    function setRail(items: string, shows: string): string {
      var ignored = []
      var text = String(items).trim()
      if (text) {
        var keys = text.split(",").map(function(k) { return k.trim().toLowerCase() }).filter(function(k) { return k })
        var known = keys.filter(function(k) { return guide.railKind(k) })
        keys.filter(function(k) { return !guide.railKind(k) }).forEach(function(k) { ignored.push(k + " (" + guide.railKinds.map(function(r) { return r.key }).join(", ") + ")") })
        if (known.length) {
          var setup = known.map(function(k) { return { key: k, on: true } })
          guide.railKinds.forEach(function(r) { if (known.indexOf(r.key) < 0) setup.push({ key: r.key, on: r.key === "settings" }) })
          guide.railSetup = guide.checkedRailSetup(setup)
        }
      }
      var mode = String(shows).trim()
      if (mode) {
        if (guide.railModes.indexOf(mode) >= 0) guide.setLayoutOverride("rail", mode)
        else ignored.push(mode + " (always, focus or none)")
      }
      guide.saveSettings()
      return commands.okReply({ shows: guide.layout.rail, onRail: guide.railItems.map(function(r) { return r.key }), ignored: ignored })
    }

    function videos(words: string): string {
      var terms = String(words).toLowerCase().split(/\s+/).filter(function(t) { return t })
      var all = guide.myVideos()
      var hits = all.filter(function(v) {
        var hay = (v.title + " " + v.folder + " " + v.path).toLowerCase()
        return terms.every(function(t) { return hay.indexOf(t) >= 0 })
      })
      return commands.okReply({ on: guide.videosOn(), folder: guide.videosFolder, missing: guide.videosMissing, looking: guide.videosScanning, total: hits.length,
                                videos: hits.slice(0, 100).map(function(v) {
                                  return { id: v.id, title: v.title, folder: v.folder, duration: v.duration, added: Qt.formatDateTime(new Date(v.mtime * 1000), "yyyy-MM-dd"),
                                           resumeAt: guide.resumeAt(v.id), inMyList: guide.inMyList(v.id) }
                                }), more: hits.length > 100 })
    }

    function screenSaver(): string {
      var s = guide.screenSaver
      var st = s.settings
      return commands.okReply({ on: st.on, showing: s.showing, after: st.after, pictures: st.pictures, every: st.every, clock: st.clock,
                                folder: s.folder, folderPictures: s.listed ? s.folderPictures.length : null, omarchyPictures: s.listed ? s.omarchyPictures.length : null,
                                note: st.on ? "on: pictures after " + SaverRules.afterLabel(st.after) + " with nothing playing and no key, mouse or phone press"
                                            : "off: only the user can turn it on, in Settings → Screen saver" })
    }

    function setScreenSaver(json: string): string {
      var given
      try { given = JSON.parse(String(json)) } catch (e) { return commands.failReply("the changes as JSON, like {\"after\": 10, \"clock\": \"middle\"}") }
      if (!given || typeof given !== "object" || Array.isArray(given)) return commands.failReply("the changes as a JSON object, like {\"after\": 10}")
      var r = SaverRules.agentChange(guide.screenSaver.settings, given)
      if (r.changed.length) {
        var changes = {}
        r.changed.forEach(function(k) { changes[k] = r.settings[k] })
        guide.setSaver(changes)
      }
      var st = guide.screenSaver.settings
      return commands.okReply({ changed: r.changed, ignored: r.ignored, settings: { on: st.on, after: st.after, pictures: st.pictures, every: st.every, clock: st.clock } })
    }

    function setVideos(on: string, folder: string): string {
      var o = String(on).trim()
      var f = String(folder).trim().replace(/^~(?=\/|$)/, Quickshell.env("HOME")).replace(/\/+$/, "")
      if (o && o !== "on" && o !== "off") return commands.failReply("on, off or \"\"")
      if (f && f.charAt(0) !== "/") return commands.failReply("the folder as a full path, like " + Quickshell.env("HOME") + "/Videos")
      guide.setVideos(o ? o === "on" : guide.videosOn(), f)
      return commands.okReply({ on: guide.videosOn(), folder: guide.videosFolder, note: guide.videosOn() ? "looking for videos there; run videos in a moment" : "My Videos is off: it left the library, Home and the rail" })
    }

    function listings(): string {
      var e = guide.epg
      return commands.okReply({
        sources: e.sources.map(function(x) {
          var r = e.sourceReport(x.url) || {}
          return { url: x.url, from: x.from, ok: r.ok === true, error: r.error || "", listingsChannels: r.channels || 0, matched: r.matched || 0, shows: r.shows || 0 }
        }),
        iptvChannels: guide.iptvCount, withListings: e.matched,
        fetched: e.fetched ? Qt.formatDateTime(new Date(e.fetched * 1000), "yyyy-MM-dd HH:mm") : null,
        fetching: e.busy, status: e.status
      })
    }

    function addListings(source: string): string {
      var res = guide.epg.add(source, "you")
      if (res !== "ok") return commands.failReply(res)
      return commands.okReply({ added: guide.epg.checkSource(source), note: "fetching it now; run listings in a minute to see how many channels it matched" })
    }

    function removeListings(source: string): string {
      var res = guide.epg.remove(guide.epg.checkSource(source) || String(source))
      if (res !== "ok") return commands.failReply(res + " (listings shows them)")
      return commands.okReply({ removed: source, left: guide.epg.sources.length })
    }

    function search(words: string): string {
      if (!String(words).trim()) return commands.failReply("some words to search for")
      var rows = guide.searchRowsFor(words)
      var out = { total: 0 }
      var names = { "s-channels": "channels", "s-now": "onNow", "s-later": "laterToday", "s-movies": "movies", "s-videos": "videos", "s-files": "myVideos" }
      for (var i = 0; i < rows.length; i++) {
        var row = rows[i]
        out.total += row.cards.length
        out[names[row.key]] = row.cards.slice(0, 25).map(function(c) {
          if (c.kind === "channel") {
            var ch = guide.channels[c.r] || {}
            return { number: guide.numbers[c.r], channel: ch.name, title: c.title, live: !!c.live,
                     starts: c.starting ? Qt.formatDateTime(new Date(c.start * 1000), "HH:mm") : null, watch: guide.numbers[c.r] }
          }
          if (c.kind === "series") return { series: c.title, episodes: c.episodes.map(function(e) { return { id: e.id, title: e.title, season: e.season, episode: e.episode } }).slice(0, 50) }
          return { id: c.id, title: c.title, about: c.sub || "" }
        })
        if (row.more || row.cards.length > 25) out[names[row.key] + "More"] = true
      }
      out.note = "watch <number> puts a channel on; play <id> plays a movie, an episode or a video"
      return commands.okReply(out)
    }

    function library(words: string): string {
      var terms = String(words).toLowerCase().split(/\s+/).filter(function(t) { return t })
      var lib = guide.libraryItems()
      var hits = lib.filter(function(it) {
        var hay = (it.title + " " + it.genre + " " + it.series + " " + (it.year || "")).toLowerCase()
        return terms.every(function(t) { return hay.indexOf(t) >= 0 })
      })
      return commands.okReply({ total: hits.length, genres: guide.libraryGenres(),
                                items: hits.slice(0, 100).map(function(it) {
                                  return { id: it.id, title: it.title, genre: it.genre, year: it.year || null, series: it.series || null,
                                           resumeAt: guide.resumeAt(it.id), inMyList: guide.inMyList(it.id) }
                                }), more: hits.length > 100 })
    }

    function play(id: string): string {
      var entry = guide.entryFor(id)
      if (!entry) return commands.failReply("nothing with id \"" + id + "\" (library \"<words>\" finds a movie's id, videos \"<words>\" one of the user's videos; a YouTube video is yt:<its id>)")
      if (entry.videoId && guide.videoLockedBy(entry.videoId, entry.subtitle, entry.owners, entry.ownersMore)) return commands.failReply("that video is from a locked channel: only the user can unlock it, with the passcode, at the screen")
      if (!guide.opened) guide.guidePip()
      commands.pendingPlay = entry
      commands.pendingFrom = undefined
      playSoon.restart()
      return commands.okReply({ playing: entry.title, from: guide.resumeAt(entry.id) })
    }

    // play, from a moment: seconds, or h:mm:ss / mm:ss (a scene, not a burst of skips)
    function playAt(id: string, at: string): string {
      var m = String(at).trim().match(/^(?:(\d{1,2}):)?(?:(\d{1,2}):)?(\d{1,6})$/)
      if (!m) return commands.failReply("a time is seconds, or h:mm:ss or mm:ss")
      var parts = String(at).trim().split(":").map(Number)
      var secs = parts.reduce(function(a, b) { return a * 60 + b }, 0)
      var said = JSON.parse(ipc.play(id))
      if (!said.ok) return JSON.stringify(said)
      commands.pendingFrom = secs
      return commands.okReply({ playing: said.playing, from: secs })
    }

    function channels(words: string): string {
      var terms = String(words).toLowerCase().split(/\s+/).filter(function(t) { return t })
      var out = []
      var total = 0
      for (var i = 0; i < guide.channels.length; i++) {
        var c = guide.channels[i]
        var hay = (c.name + " " + (c.category || "") + " " + guide.numbers[i]).toLowerCase()
        if (!terms.every(function(t) { return hay.indexOf(t) >= 0 })) continue
        total++
        if (out.length < 100) out.push(commands.channelInfo(i))
      }
      return commands.okReply({ total: total, channels: out, more: total > out.length })
    }

    function categories(): string {
      var list = guide.categories.map(function(cat) {
        var mine = guide.channels.filter(function(c) { return (c.category || "") === cat })
        return { category: cat, label: guide.categoryLabel(cat), channels: mine.length,
                 iptv: mine.filter(function(c) { return c.kind === "iptv" }).length,
                 shown: !guide.shownCategories.length || guide.shownCategories.indexOf(cat) >= 0 }
      })
      return commands.okReply({ source: guide.shownSource, categories: list })
    }

    function addChannels(text: string): string {
      var said = guide.addChannel(String(text))
      if (said === "busy") return commands.failReply("still adding the last ones: status says how far along")
      if (guide.addFailed) return commands.failReply(String(said))
      return commands.okReply({ note: String(said), busy: guide.jobTotal > 0 || /…$/.test(guide.addStatus) || said === "fetching" })
    }

    function demoChannels(): string {
      var cats = {}
      var order = []
      guide.demoLineup.channels.forEach(function(c) { var k = c.category || ""; if (!(k in cats)) { cats[k] = 0; order.push(k) } cats[k]++ })
      return commands.okReply({ channels: guide.demoLineup.channels.length, notInGuide: guide.demoToAdd().length,
                                categories: order.map(function(k) { return { name: k || "(none)", channels: cats[k] } }) })
    }

    function loadDemoChannels(): string {
      if (guide.jobTotal) return commands.failReply("still adding channels: status says how far along")
      var r = guide.loadDemoChannels()
      if (r.error) return commands.failReply(r.error)
      return commands.okReply({ added: r.added, note: r.added ? "added; each loads its listings over the next few minutes" : "they're all in the guide already" })
    }

    function status(): string {
      return commands.okReply({ busy: guide.jobTotal > 0 || /…$/.test(guide.addStatus), checking: guide.jobTotal, done: guide.jobDone,
                            message: guide.addStatus, failed: guide.addFailed, channels: guide.channels.length })
    }

    function show(source: string, categories: string): string {
      var src = String(source).trim().toLowerCase()
      if (src && ["both", "youtube", "iptv"].indexOf(src) < 0) return commands.failReply("source: both, youtube or iptv (\"\" keeps it)")
      var cats = String(categories).trim()
      var shown = guide.shownCategories
      if (cats !== "-") {
        shown = []
        var asked = cats ? cats.split(",").map(function(c) { return c.trim() }).filter(function(c) { return c }) : []
        for (var i = 0; i < asked.length; i++) {
          var a = asked[i].toLowerCase()
          var hit = guide.categories.filter(function(c) { return c.toLowerCase() === a || (a === "my channels" && c === "") })
          if (!hit.length) return commands.failReply("no category \"" + asked[i] + "\"; categories lists them")
          if (shown.indexOf(hit[0]) < 0) shown.push(hit[0])
        }
      }
      if (src) guide.shownSource = src
      guide.shownCategories = shown.length === guide.categories.length ? [] : shown
      guide.saveSettings()
      if (guide.visibleRows.indexOf(guide.row) < 0) guide.row = guide.visibleRows[0] || 0
      return commands.okReply({ source: guide.shownSource, shownCategories: guide.shownCategories, shownNow: guide.visibleRows.length })
    }

    function rename(number: string, name: string): string {
      var r = commands.rowsFor(number)[0]
      var clean = String(name).trim()
      if (r === undefined) return commands.failReply("no channel " + number)
      if (!clean) return commands.failReply("give it a name")
      guide.renameChannel(r, clean)
      return commands.okReply({ channel: commands.channelInfo(r) })
    }

    function setCategory(numbers: string, category: string): string {
      var rows = commands.rowsFor(numbers)
      if (!rows.length) return commands.failReply("no channels " + numbers)
      var cat = String(category).trim().slice(0, 40)
      if (cat.toLowerCase() === "my channels") cat = ""
      var urls = rows.map(function(r) { return guide.channels[r].url })
      guide.setCategory(urls, cat)
      // they're renumbered: the category's own hundred
      return commands.okReply({ moved: urls.length, nowNumbered: urls.map(function(u) { return guide.numbers[guide.indexOf(u)] }) })
    }

    function removeChannels(numbers: string): string {
      var rows = commands.rowsFor(numbers)
      if (!rows.length) return commands.failReply("no channels " + numbers)
      var names = rows.map(function(r) { return guide.channels[r].name })
      guide.removeUrls(rows.map(function(r) { return guide.channels[r].url }))
      return commands.okReply({ removed: names })
    }

    function logos(on: string): string {
      var v = commands.onOff(on)
      if (v === null) return commands.failReply("on or off")
      guide.setLogos(v)
      return commands.okReply({ logos: guide.showLogos })
    }

    function keyHints(on: string): string {
      var v = commands.onOff(on)
      if (v === null) return commands.failReply("on or off")
      guide.setKeyHints(v)
      return commands.okReply({ keyHints: guide.showKeyHints })
    }

    function refresh(): string {
      guide.refresh(false)
      return commands.okReply({ note: "fetching the listings again" })
    }

    // Apps: what's there, and turning one off. Nothing here turns apps on,
    // installs or removes them: that's the user's, at the screen. How each
    // was checked, and who withdrew one, in AppAsks.js's words: a signed app
    // file is traced to its pinned developer key, never to Uber TV's catalog.
    function apps(): string {
      var a = guide.apps
      return commands.okReply({
        on: a.on, developer: a.developer, unknownSources: a.unknownSources,
        catalog: a.catalog ? { name: a.catalog.name, apps: (a.catalog.apps || []).length, made: Qt.formatDateTime(new Date((a.catalog.updated || 0) * 1000), "yyyy-MM-dd HH:mm") } : null,
        catalogError: a.catalogError,
        installed: a.installed.map(function(x) {
          var rt = a.runtime(x.id)
          return { id: x.id, name: x.name, version: x.version, author: x.author, kind: x.kind, on: a.on && x.enabled && !x.broken && !x.revoked,
                   onScreen: guide.appUp === x.id || guide.codeApp === x.id, running: rt ? rt.phase : "stopped", from: x.from, source: x.source,
                   checked: !!a.checkedIds[x.id] ? Asks.checkedHow(x.from, x.catalogName, x.keyFingerprint) : "not yet",
                   allowedTo: a.asks(x.permissions, x.settings).map(function(t) { return t.text }),
                   problem: x.revoked ? Asks.pulledBy(x.from) + ": " + x.revoked : x.broken || "", updateWaiting: x.update ? x.update.version : "" }
        }),
        note: a.on ? "only the user turns an app on, installs, updates or removes one (Settings → Apps)" : "apps are off; only the user can turn them on (Settings → Apps)"
      })
    }

    function appScreen(id: string): string {
      var res = guide.appAgent.appScreen(String(id).trim())
      return res.ok ? commands.okReply(res) : commands.failReply(res.error)
    }

    function setAppScreen(id: string, json: string): string {
      var res = guide.appAgent.setAppScreen(String(id).trim(), String(json))
      if (!res.ok) return JSON.stringify({ ok: false, error: res.error, ignored: res.ignored || [] })
      return commands.okReply(res)
    }

    function resetAppScreen(id: string): string {
      var res = guide.appAgent.resetAppScreen(String(id).trim())
      return res.ok ? commands.okReply(res) : commands.failReply(res.error)
    }

    function openApp(id: string, handle: string): string {
      var res = guide.appAgent.openApp(String(id).trim(), String(handle).trim())
      return res.ok ? commands.okReply(res) : commands.failReply(res.error)
    }

    function appSnapshot(view: string): string {
      var res = guide.appAgent.appSnapshot(String(view).trim())
      return res.ok ? commands.okReply(res) : commands.failReply(res.error)
    }

    function appOff(id: string): string {
      var r = guide.apps.record(String(id).trim())
      if (!r) return commands.failReply("no installed app " + id + " (apps lists them)")
      guide.apps.setEnabled(r.id, false)
      return commands.okReply({ id: r.id, on: false, note: "it's off (closed, if it was on the screen) and still installed; the user can turn it back on in Settings → Apps" })
    }
  }

  // play, from the command: once the guide is up
  // playRecording, from the command: once the guide is up, the recording
  // checked again (still there, playable, not locked) before it plays
  property var pendingRecording: null
  Timer {
    id: recordingSoon
    interval: 600
    onTriggered: {
      var p = commands.pendingRecording
      if (!p) return
      if (!guide.opened && p.tries < 8) { p.tries += 1; recordingSoon.restart(); return }   // still opening
      commands.pendingRecording = null
      var rec = guide.recorder.byId[p.id]
      if (!guide.opened || !rec || !DvrRules.playable(rec) || guide.recorder.locked(rec)) return
      guide.playRecording(guide.recordingCard(rec), !!p.fromStart)
    }
  }
  property var pendingPlay: null
  property var pendingFrom: undefined     // startOver: 0; play: where the user stopped
  Timer {
    id: playSoon
    interval: 600
    onTriggered: if (commands.pendingPlay) { guide.playVod(commands.pendingPlay, commands.pendingFrom); commands.pendingPlay = null; commands.pendingFrom = undefined }
  }

  // watch, from the command: once the mini player (or the guide) is up. The
  // channel by its address, found again then: a category set or a channel
  // removed meanwhile moves the rows, and another channel would come on
  property string pendingWatch: ""
  property var pendingMultiview: null
  Timer {
    id: multiviewSoon
    interval: 600
    onTriggered: {
      var p = commands.pendingMultiview
      if (!p) return
      if (!guide.opened && p.tries < 8 && p.request === guide.mvRequest) { p.tries += 1; multiviewSoon.restart(); return }   // still opening
      commands.pendingMultiview = null
      guide.startMultiview(p.urls, p.request)
    }
  }
  Timer {
    id: watchSoon
    interval: 600
    onTriggered: {
      var r = guide.indexOf(commands.pendingWatch)
      commands.pendingWatch = ""
      if (r >= 0) guide.watch(r)
    }
  }
}
