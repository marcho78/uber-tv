import QtQuick
import Quickshell
import Quickshell.Wayland
import "Saver.js" as SaverRules
import "ui"

// The screen saver (Saver.js): when it's on, Uber TV is
// on screen, nothing plays, and there's been no key, mouse or phone press for
// the chosen minutes, pictures fill every screen with the clock. The first
// key, mouse move, click, scroll or phone press only wakes it, and keys wait
// a moment after (settling) so that press doesn't act in the guide too. A
// video starting, Uber TV leaving the screen or Omarchy's own screen saver
// coming hide it as well. While it's on (or showing), Awake keeps the screen
// awake while Uber TV shows, so Omarchy's saver and lock wait and waking
// needs no password. The pictures (Omarchy's backgrounds, your folder) are
// listed by the helper (bin/om-pg-apps saver-pictures), and each is copied
// into the guide's cache just before it's shown (saver-take: opened without
// following a link and checked through that open file), so what's shown is
// what was checked, whatever happens to its name after.
Item {
  id: saver

  required property var guide
  property string helper: ""          // bin/om-pg-apps
  property var settings: SaverRules.defaults()
  property bool eligible: false       // the guide's: on, on screen, nothing playing (Saver.js eligible)
  property bool omarchySaverUp: false // Omarchy's own screen saver is up: this one goes
  property bool showing: false
  property bool settling: false

  property var omarchyPictures: []
  property var folderPictures: []
  property bool folderMissing: false
  property bool listed: false
  property bool listAgain: false
  property string folderRoot: ""     // the folder as the helper read it (links on the way resolved)
  property var ids: ({})              // each picture's identity when it was checked (saver-take holds it to it)
  property int run: 0                 // which showing (a late copy for an earlier one is dropped)
  property var order: []
  readonly property string folder: SaverRules.folderOf(saver.settings, Quickshell.env("HOME"))

  // The paired phone (Hyprland's idle timers were started over for it): it
  // wakes the pictures, or starts the wait over
  function activity() {
    if (saver.showing) saver.wake()
    else if (saver.eligible) countdown.restart()
  }

  function show() {
    if (saver.showing) return
    saver.order = SaverRules.shuffled(SaverRules.playlist(saver.settings.pictures, saver.omarchyPictures, saver.folderPictures), Math.random)
    saver.run += 1
    saver.showing = true
  }

  function wake() {
    if (!saver.showing) return
    saver.showing = false
    saver.settling = true
    settle.restart()
    if (saver.eligible) countdown.restart()
    saver.clearCopies()
    saver.list()   // pictures dropped in your folder meanwhile join next time
  }

  // It comes once it may (eligible), the chosen minutes have passed since it
  // could (a video ending starts the wait over), and Hyprland has seen no
  // key, mouse or touch for that long (a steady stream of input counts all
  // the way, not just its first press)
  function check() {
    if (SaverRules.shouldShow({ eligible: saver.eligible, quiet: quiet.isIdle, waited: !countdown.running, showing: saver.showing })) saver.show()
  }

  // when the wait begins, your folder is read again, so pictures dropped in
  // since are there when it comes
  onEligibleChanged: {
    if (saver.eligible) { countdown.restart(); saver.list() }
    else { countdown.stop(); if (saver.showing) saver.wake() }
  }
  // Omarchy's own screen saver came (a preview while it's off, say): this one
  // goes, so Omarchy's can have the keyboard and keep its lock
  onOmarchySaverUpChanged: if (saver.omarchySaverUp && saver.showing) saver.wake()
  onSettingsChanged: {
    countdown.interval = saver.settings.after * 60000
    if (saver.eligible) countdown.restart()
  }

  Timer {
    id: countdown
    interval: 5 * 60000
    onTriggered: saver.check()
  }
  Timer {
    id: settle
    interval: 400
    onTriggered: saver.settling = false
  }

  // No key, mouse or touch on this computer for the chosen minutes, measured
  // by Hyprland (ignoring holds: Uber TV's own keeps Omarchy's from counting)
  IdleMonitor {
    id: quiet
    timeout: saver.settings.after * 60
    respectInhibitors: false
    enabled: saver.settings.on
    onIsIdleChanged: { if (isIdle) saver.check(); else if (saver.showing) saver.wake() }
  }
  // While it shows: any key, mouse move or touch after a second's quiet wakes
  // it (a preview comes just after a press, before the long watch is idle)
  IdleMonitor {
    timeout: 1
    respectInhibitors: false
    enabled: saver.showing
    onIsIdleChanged: if (!isIdle) saver.wake()
  }

  // ---- the pictures ----
  property var lister: null
  property string listedFolder: ""
  function list() {
    if (saver.lister) { saver.listAgain = true; return }
    var r = listRun.createObject(saver)
    saver.lister = r
    var asked = saver.folder
    r.finished.connect(function(ok, output) {
      var res
      try { res = JSON.parse(String(output).trim().split("\n").pop()) } catch (e) { res = {} }
      if (res.ok) {
        saver.omarchyPictures = Array.isArray(res.omarchy) ? res.omarchy.filter(function(p) { return typeof p === "string" }) : []
        saver.folderPictures = Array.isArray(res.folder) ? res.folder.filter(function(p) { return typeof p === "string" }) : []
        saver.folderMissing = res.folderMissing === true
        saver.folderRoot = typeof res.folderRoot === "string" ? res.folderRoot : ""
        saver.ids = res.ids && typeof res.ids === "object" ? res.ids : ({})
        saver.listedFolder = asked
        saver.listed = true
      }
      saver.lister = null
      Qt.callLater(function() { r.destroy() })
      // asked again meanwhile (another folder, say): once more
      if (saver.listAgain || asked !== saver.folder) { saver.listAgain = false; Qt.callLater(saver.list) }
    })
    // Omarchy's are always listed (an empty folder falls back to them), and
    // your folder too (Settings says how many it has)
    r.start(["/usr/bin/python3", saver.helper, "saver-pictures"], JSON.stringify({ omarchy: true, folder: saver.folder }))
  }
  Component { id: listRun; Run { timeoutMs: 60000; maxBytes: 512 * 1024; okCodes: [0, 1]; splitMarker: "\n" } }

  // A picture ready to show: copied into the guide's cache by the helper,
  // from the file it opened and checked, through the folder it was listed
  // from (yours, or Omarchy's backgrounds folder it's in), and only if it's
  // the very file that was listed (its identity). done(path of the copy, or
  // "" if it can't be shown), only for the showing that asked.
  readonly property string copies: saver.guide.cacheDir + "/saver"
  function take(path, done) {
    var p = String(path)
    var root = saver.folderRoot && p.indexOf(saver.folderRoot + "/") === 0 ? saver.folderRoot : p.slice(0, p.lastIndexOf("/"))
    var r = listRun.createObject(saver)
    var run = saver.run
    r.finished.connect(function(ok, output) {
      var res
      try { res = JSON.parse(String(output).trim().split("\n").pop()) } catch (e) { res = {} }
      if (run === saver.run && saver.showing) done(res.ok && typeof res.path === "string" ? res.path : "")
      Qt.callLater(function() { r.destroy() })
    })
    r.start(["/usr/bin/python3", saver.helper, "saver-take"], JSON.stringify({ root: root, from: p.slice(root.length + 1), id: String(saver.ids[p] || ""), into: saver.copies }))
  }
  // The copies go once it's closed (its layers, and the pictures in them, gone)
  function clearCopies() {
    var r = listRun.createObject(saver)
    r.finished.connect(function() { Qt.callLater(function() { r.destroy() }) })
    r.start(["/usr/bin/python3", saver.helper, "saver-take"], JSON.stringify({ clear: true, into: saver.copies }))
  }

  // Your folder, made if it isn't there yet, then opened in your file manager
  function openFolder(done) {
    var r = listRun.createObject(saver)
    r.finished.connect(function(ok, output) {
      var res
      try { res = JSON.parse(String(output).trim().split("\n").pop()) } catch (e) { res = {} }
      if (res.ok && typeof res.folder === "string") Quickshell.execDetached(["/usr/bin/xdg-open", res.folder])
      done(res.ok ? "" : (typeof res.error === "string" && res.error ? res.error : "it couldn't be opened"))
      saver.list()
      Qt.callLater(function() { r.destroy() })
    })
    r.start(["/usr/bin/python3", saver.helper, "saver-folder"], JSON.stringify({ folder: saver.folder }))
  }

  // ---- a layer on every screen ----
  function placeOf(screen) {
    var all = Quickshell.screens
    for (var i = 0; i < all.length; i++) if (all[i] === screen) return i
    return 0
  }
  Variants {
    model: saver.showing ? Quickshell.screens : []
    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      color: "black"
      WlrLayershell.namespace: "om-pg-saver"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      exclusionMode: ExclusionMode.Ignore

      SaverScreen {
        anchors.fill: parent
        guide: saver.guide
        order: saver.order
        place: saver.placeOf(win.modelData)
        screens: Quickshell.screens.length
        every: saver.settings.every
        clockAt: saver.settings.clock
        take: saver.take
        dpr: win.devicePixelRatio || 1
      }

      // the first press only wakes it
      Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) { guide.keyFirst(event); event.accepted = true; saver.wake() }
      }
      MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.BlankCursor
        // a layer appearing under the pointer can be told it moved: for a
        // moment, that isn't you; after it, any move is
        property bool armed: false
        Timer { interval: 700; running: true; onTriggered: pointer.armed = true }
        onPositionChanged: if (armed) saver.wake()
        onPressed: function(mouse) { mouse.accepted = true; saver.wake() }
        onWheel: function(wheel) { wheel.accepted = true; saver.wake() }
      }
    }
  }
}
