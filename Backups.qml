import QtQuick
import Quickshell
import "ui"

// Backups of your channels and settings (Settings → About), putting one
// back, and resetting Uber TV to how it was when first installed (Settings →
// Developer), through bin/om-pg-backup. From a restore's or a reset's start
// nothing of Uber TV writes its files (guide.wiping), and once it's done the
// shell reloads, so everything is read again: the backup's, or nothing, as
// when first installed.
Item {
  id: backups

  required property var guide

  readonly property string helper: guide.pluginDir + "/bin/om-pg-backup"
  readonly property string version: (guide.manifest && guide.manifest.version) || ""
  property string folder: ""          // where backups go (the helper says)

  // Back up channels and settings
  property string saving: ""          // busy, done or failed
  property string saveSaid: ""        // the file it saved, or why it couldn't
  // Restore a backup
  property var list: []               // [{ file, made, size }], newest first
  property bool listed: false
  property int pick: 0
  property bool armed: false          // asking first: Enter again restores
  property string restoreStep: ""     // busy or failed
  property string restoreSaid: ""
  // Reset Uber TV
  property string resetStep: ""       // password, backup, stopping, wiping or failed
  property string resetSaid: ""

  readonly property string shownFolder: backups.folder ? guide.shownPath(backups.folder) : "~/Documents/Uber TV backups"

  function when(seconds) { return Qt.formatDateTime(new Date(seconds * 1000), "MMM d, yyyy, h:mm AP") }
  function bytes(n) { return n >= 1048576 ? (n / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(n / 1024)) + " KB" }

  function parse(ok, output) {
    var r = null
    if (ok) { try { r = JSON.parse(output) } catch (e) { r = null } }
    if (!r || typeof r !== "object") return { ok: false, error: "it didn't answer" }
    if (r.ok !== true) return { ok: false, error: typeof r.error === "string" && r.error ? r.error : "it couldn't be done" }
    return r
  }

  // ---- Back up channels and settings ----
  function save(by) {
    if (by !== guide.byUser || backups.saving === "busy" || guide.wiping) return
    backups.saving = "busy"
    backups.saveSaid = ""
    guide.flushAll()        // what's waiting to be written goes in first
    saveDelay.restart()
  }

  // ---- Restore a backup ----
  function openRestore() {
    backups.pick = 0
    backups.armed = false
    backups.restoreStep = ""
    backups.restoreSaid = ""
    backups.listed = false
    guide.dialog = "restore"
    listRun.start(["/usr/bin/python3", backups.helper, "list"])
  }
  function move(d) {
    if (backups.restoreStep === "busy" || !backups.list.length) return
    backups.pick = Math.max(0, Math.min(backups.list.length - 1, backups.pick + d))
    backups.armed = false
  }
  function choose(i) {
    if (backups.restoreStep === "busy") return
    if (backups.pick !== i) { backups.pick = i; backups.armed = false }
    backups.restoreAct(guide.byUser)
  }
  // Enter: asks first, then restores
  function restoreAct(by) {
    if (by !== guide.byUser || backups.restoreStep === "busy" || !backups.list[backups.pick]) return
    if (!backups.armed) { backups.armed = true; backups.restoreStep = ""; backups.restoreSaid = ""; return }
    backups.restoreStep = "busy"
    backups.restoreSaid = ""
    guide.wiping = true
    restoreRun.start(["/usr/bin/python3", backups.helper, "restore", backups.list[backups.pick].file])
  }
  // Esc: back from asking, or the box closes (not while it's restoring)
  function restoreEscape() {
    if (backups.restoreStep === "busy") return
    if (backups.armed) backups.armed = false
    else guide.closeDialog()
  }

  // ---- Reset Uber TV ----
  function openReset() {
    backups.resetStep = ""
    backups.resetSaid = ""
    guide.dialog = "reset"
  }
  function resetBusy() { return ["password", "backup", "stopping", "wiping"].indexOf(backups.resetStep) >= 0 }
  function failReset(why) { backups.resetStep = "failed"; backups.resetSaid = why }
  function resetEscape() { if (!backups.resetBusy()) guide.closeDialog() }

  // Enter in the box: the computer's password when something needs it, a
  // backup, then everything of Uber TV goes and it starts as new
  function reset(by) {
    if (by !== guide.byUser || backups.resetBusy() || guide.wiping) return
    if (guide.appsBusy() || guide.firewallBusy || Object.keys(guide.apps.changing).length) {
      backups.failReset("Something is being changed just now (an app, the firewall or a password prompt). Try again in a moment.")
      return
    }
    backups.resetSaid = ""
    var rules = guide.remoteRules.slice()
    if (rules.length) {
      // taking the phone remote's firewall rules out asks for the password itself
      backups.resetStep = "password"
      backups.removeRules(rules)
    } else if (guide.channelLock && guide.channelLock.set) {
      backups.resetStep = "password"
      guide.authorize("resetAll", null, function(given, why) {
        if (given) backups.backupFirst()
        else backups.failReset(guide.authSaid(why) || "Nothing was reset.")
      }, function() { return guide.dialog === "reset" })
    } else {
      backups.backupFirst()
    }
  }

  function removeRules(rules) {
    if (!rules.length) { backups.backupFirst(); return }
    guide.firewallThen = function(removed) {
      if (removed) backups.removeRules(rules.slice(1))
      else backups.failReset("The firewall wasn't changed, so nothing was reset.")
    }
    if (guide.firewall("remove", guide.byUser, rules[0]) !== true) {
      guide.firewallThen = null
      backups.failReset("The phone remote's firewall rule couldn't be taken out, so nothing was reset.")
    }
  }

  function backupFirst() {
    backups.resetStep = "backup"
    guide.flushAll()
    resetDelay.restart()
  }

  // Everything that runs stops first (the TV, the phone remote, apps, the
  // agent skill's links), so nothing writes into what's being reset
  function wipe() {
    backups.resetStep = "stopping"
    guide.wiping = true
    guide.turnOff()
    if (guide.remoteEnabled) guide.turnRemoteOff(false, guide.byUser)
    guide.apps.stopAll()
    stopWait.ticks = 0
    stopWait.restart()
  }

  function wipeNow() {
    backups.resetStep = "wiping"
    if (guide.agentSkill) unlinkRun.start(["/usr/bin/bash", guide.pluginDir + "/bin/om-pg-skill", "unlink", guide.skillDir])
    else wipeRun.start(["/usr/bin/python3", backups.helper, "reset"])
  }

  // What the boxes and the rows say
  function title(dialog) { return dialog === "reset" ? "Reset Uber TV?" : "Restore a backup" }
  function text(dialog) {
    if (dialog === "reset") {
      return backups.resetStep === "password" ? "Waiting for the computer's password…"
           : backups.resetStep === "backup" ? "Saving a backup first…"
           : backups.resetStep === "stopping" || backups.resetStep === "wiping" ? "Resetting…"
           : backups.resetStep === "failed" ? backups.resetSaid
           : "This resets all your channels and settings, including update notifications and everything else you agreed to. Uber TV will be as it was when you first installed it.\n\n"
             + "A backup of your channels and settings is saved first, in " + backups.shownFolder + "."
    }
    if (backups.restoreStep === "busy") return "Restoring…"
    if (backups.restoreSaid) return backups.restoreSaid
    if (!backups.listed) return "Looking for backups…"
    if (!backups.list.length) return "There are no backups yet. Back up channels and settings, in Settings → About, makes one in " + backups.shownFolder + "."
    var b = backups.list[backups.pick]
    return backups.armed && b ? "Restore the backup from " + backups.when(b.made) + "? Your channels and settings now are replaced by it." : "Pick a backup to restore."
  }
  function hints(dialog) {
    if (dialog === "reset")
      return backups.resetBusy() ? [{ keys: [], label: "One moment…" }]
             : [{ keys: ["ENTER"], label: "Reset everything", touch: { key: Qt.Key_Return } }, { keys: ["ESC"], label: "Cancel", touch: { key: Qt.Key_Escape, back: true } }]
    if (backups.restoreStep === "busy") return [{ keys: [], label: "One moment…" }]
    if (!backups.list.length) return [{ keys: ["ESC"], label: "Close", touch: { key: Qt.Key_Escape, back: true } }]
    return backups.armed ? [{ keys: ["ENTER"], label: "Restore", touch: { key: Qt.Key_Return } }, { keys: ["ESC"], label: "Back", touch: { key: Qt.Key_Escape, back: true } }]
                         : [{ keys: ["↑", "↓"], label: "Pick" }, { keys: ["ENTER"], label: "Restore", touch: { key: Qt.Key_Return } }, { keys: ["ESC"], label: "Cancel", touch: { key: Qt.Key_Escape, back: true } }]
  }
  function value(key) {
    if (key === "backupSave") return backups.saving === "busy" ? "Saving…" : backups.saving === "done" ? "Saved" : backups.saving === "failed" ? "Couldn't save" : ""
    return ""
  }
  function note(key) {
    if (key === "backupSave")
      return "Saves your channels, settings, My List, Continue watching, your themes and program listings to " + backups.shownFolder + ". Paired phones, the channel lock and app sign-ins aren't saved."
             + (backups.saving === "done" ? " Saved as " + backups.saveSaid + "." : backups.saving === "failed" ? " Couldn't save it: " + backups.saveSaid + "." : "")
    if (key === "backupRestore") return "Puts a backup's channels and settings in place of yours. It asks first."
    if (key === "resetAll") return "Back to how Uber TV was when you first installed it: your channels, settings and apps go, and everything you agreed to. It asks first, and saves a backup before anything goes."
    return ""
  }

  // where backups go, for the rows' notes (read once, from the helper)
  Component.onCompleted: folderRun.start(["/usr/bin/python3", backups.helper, "list"])

  Run {
    id: folderRun
    timeoutMs: 20000
    maxBytes: 256 * 1024
    onFinished: function(ok, output) {
      var r = backups.parse(ok, output)
      if (r.ok && typeof r.folder === "string") backups.folder = r.folder
    }
  }

  Timer {
    id: saveDelay
    interval: 600
    onTriggered: saveRun.start(["/usr/bin/python3", backups.helper, "backup", backups.version])
  }
  Run {
    id: saveRun
    timeoutMs: 120000
    maxBytes: 16 * 1024
    onFinished: function(ok, output) {
      var r = backups.parse(ok, output)
      backups.saving = r.ok ? "done" : "failed"
      backups.saveSaid = r.ok ? String(r.file || "").split("/").pop() : r.error
    }
  }

  Run {
    id: listRun
    timeoutMs: 20000
    maxBytes: 256 * 1024
    onFinished: function(ok, output) {
      var r = backups.parse(ok, output)
      backups.list = r.ok && Array.isArray(r.backups)
        ? r.backups.filter(function(b) { return b && /^uber-tv-backup-[0-9-]+\.tar\.gz$/.test(b.file) && b.made > 0 }) : []
      if (r.ok && typeof r.folder === "string") backups.folder = r.folder
      backups.listed = true
      if (!r.ok) backups.restoreSaid = "Couldn't read the backups: " + r.error + "."
    }
  }
  Run {
    id: restoreRun
    timeoutMs: 300000
    maxBytes: 16 * 1024
    onFinished: function(ok, output) {
      var r = backups.parse(ok, output)
      if (r.ok) { Quickshell.reload(true); return }
      guide.wiping = false
      backups.restoreStep = "failed"
      backups.armed = false
      backups.restoreSaid = "Couldn't restore it: " + r.error + "."
    }
  }

  Timer {
    id: resetDelay
    interval: 600
    onTriggered: resetBackupRun.start(["/usr/bin/python3", backups.helper, "backup", backups.version])
  }
  Run {
    id: resetBackupRun
    timeoutMs: 120000
    maxBytes: 16 * 1024
    onFinished: function(ok, output) {
      var r = backups.parse(ok, output)
      // nothing to back up (a fresh start already): nothing to lose either
      if (r.ok || r.error === "there's nothing to back up yet") backups.wipe()
      else backups.failReset("Couldn't save a backup, so nothing was reset: " + r.error + ".")
    }
  }
  // the apps' runtimes stopping (up to ten seconds), then the reset
  Timer {
    id: stopWait
    property int ticks: 0
    interval: 250
    repeat: true
    onTriggered: {
      if (guide.apps.live() > 0 && ++ticks < 40) return
      stop()
      backups.wipeNow()
    }
  }
  Run {
    id: unlinkRun
    timeoutMs: 15000
    maxBytes: 64 * 1024
    onFinished: wipeRun.start(["/usr/bin/python3", backups.helper, "reset"])
  }
  Run {
    id: wipeRun
    timeoutMs: 300000
    maxBytes: 64 * 1024
    onFinished: function(ok, output) {
      var r = backups.parse(ok, output)
      if (r.ok) { Quickshell.reload(true); return }
      guide.wiping = false
      backups.failReset("Couldn't reset: " + r.error + ". Nothing was deleted. Your backup is in " + backups.shownFolder + ".")
    }
  }
}
