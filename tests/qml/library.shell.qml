import QtQuick
import Quickshell
import Quickshell.Io

// Library.qml in a Quickshell of its own, with a pretend guide, over the
// files tests/library.test.py put in a scratch folder ($T): one it can
// read, and ones it can't. Something played, a movie added to My List, then
// flushed: what's saved, and what's kept as it was.
ShellRoot {
  id: root
  property string tmp: Quickshell.env("T")
  QtObject {
    id: fake
    property string configDir: root.tmp
    property bool wiping: false
    function isStreamUrl(u) { return /^https?:\/\//.test(u || "") }
    function videoOwners(id, owners) { return owners || [] }
  }
  property var lib: null
  property int fails: 0
  function check(c, s) { if (!c) root.fails++; console.log((c ? "H PASS " : "H FAIL ") + s) }
  function waitFor(cond, then, label) {
    var n = 0
    var t = poll.createObject(root)
    t.triggered.connect(function() { if (cond()) { t.destroy(); then() } else if (++n > 500) { t.destroy(); root.check(false, "timed out: " + label); Qt.quit() } })
    t.start()
  }
  Component { id: poll; Timer { interval: 20; repeat: true } }
  Component.onCompleted: {
    var c = Qt.createComponent("file://" + Quickshell.env("OM_PG_ROOT") + "/Library.qml")
    if (c.status !== Component.Ready) { console.log("H ERR " + c.errorString()); Qt.quit(); return }
    root.lib = c.createObject(root, { guide: fake })
    waitFor(function() { return root.lib.loaded && root.lib.historyLoaded }, function() {
      var want = Quickshell.env("WANT")   // "library", "history", "both" or "none": the ones it can't read
      root.check(root.lib.libraryUnread === (want === "library" || want === "both"), "library.json read as expected (" + want + ")")
      root.check(root.lib.historyUnread === (want === "history" || want === "both"), "history.json read as expected (" + want + ")")
      root.check((root.lib.problem !== "") === (want !== "none"), "the problem is said when a file wasn't read: " + root.lib.problem)
      root.lib.record({ id: "v0123abcd", title: "Played", kind: "movie", url: "https://example.com/a.mp4" }, 120, 3600)
      root.lib.items = root.lib.items.concat([{ id: "v0123abcd", title: "Played", url: "https://example.com/a.mp4" }])
      root.lib.save()
      root.lib.flush()
      tick.start()   // the savers' timers too, as if the guide stayed open
    }, "load")
  }
  Timer { id: tick; interval: 2600; onTriggered: { console.log("H DONE " + root.fails); Qt.quit() } }
}
