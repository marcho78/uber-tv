import QtQuick
import QtTest
import "../.."

// RemoteTemplates.qml against a pretend guide and helper: the built-in
// templates and yours read and checked (a file whose JSON isn't a template,
// or that takes a built-in's id, is set aside and said); everything sent to
// the phone remote resolved with the TV's colors, with a new revision each
// time; a phone on a template that's gone follows the default again, but
// never when yours couldn't be read (a failed read keeps the ones read
// before); a phone's choices refused with the remote off, answered by the
// helper, or given up on after a while; removing yours puts the default back
// to Classic if it was it. Run: /usr/lib/qt6/bin/qmltestrunner -input tests/qml
Item {
  id: root

  QtObject {
    id: guide
    property string configDir: "/tmp/nowhere"
    property string pluginDir: "/tmp/nowhere"
    property string remoteTemplate: "classic"
    property var colors: ({ accent: "#82fb9c", bgTop: "#0b0c16" })
    property bool remoteReady: true
    property var remoteDevices: []
    property var sent: []
    property int saves: 0
    property var apps: ({ helper: "/nowhere" })
    function remoteSend(m) { sent = sent.concat([JSON.parse(JSON.stringify(m))]) }
    function saveSettings() { saves += 1 }
  }

  property var listed: ({ ok: true, templates: [] })
  property bool readerFails: false
  property bool readerPartial: false
  property var calls: []
  property var answer: ({})

  RemoteTemplates {
    id: rt
    guide: guide
    order: ["classic", "minimal"]
    reader: function(done) {
      if (root.readerFails) { done(false, ""); return }
      if (root.readerPartial) { done(true, "\x1e/p/remotes/classic.json\n" + JSON.stringify({ id: "classic", name: "Classic", layout: { portrait: [{ row: ["power"], height: 10 }] } }) + "\x1e/p/remotes/minimal.json\n{ broken"); return }
      done(true, "\x1e/p/remotes/classic.json\n" + JSON.stringify({ id: "classic", name: "Classic", layout: { portrait: [{ row: ["power"], height: 10 }] } }) +
           "\x1e/p/remotes/minimal.json\n" + JSON.stringify({ id: "x", name: "Minimal", layout: { portrait: [{ row: ["mute"], height: 10 }] } }) +
           "\x1e/p/remotes/broken.json\n{ not json")
    }
    helper: function(command, request, done) {
      root.calls = root.calls.concat([{ command: command, request: request }])
      if (command === "remote-list") done(root.listed)
      else done(root.answer[command] || { ok: true, outcome: "saved", id: request.id })
    }
  }

  TestCase {
    name: "RemoteTemplates"

    function mine(id, name) { return { id: id, text: JSON.stringify({ id: "ignored", name: name, layout: { portrait: [{ row: ["back"], height: 10 }] } }) } }
    function init() {
      guide.sent = []
      guide.remoteDevices = []
      guide.remoteTemplate = "classic"
      guide.remoteReady = true
      root.calls = []
      root.answer = {}
      root.readerFails = false
      root.readerPartial = false
      root.listed = { ok: true, templates: [mine("sofa", "Sofa"), mine("classic", "Not Classic"), { id: "bad", text: "[]" }] }
    }

    function test_reads_checks_and_sends() {
      rt.load()
      verify(rt.loaded)
      compare(Object.keys(rt.builtIn).sort().join(","), "classic,minimal", "built in, each id its file's name")
      compare(rt.template("minimal").id, "minimal")
      compare(Object.keys(rt.yours).join(","), "sofa", "yours: a built-in's id and a file that isn't a template are set aside")
      compare(rt.template("sofa").id, "sofa", "a file's id is its name")
      var why = rt.problems.map(function(p) { return p.id }).sort().join(",")
      compare(why, "bad,broken,classic", "and said")
      var last = guide.sent[guide.sent.length - 1]
      compare(Object.keys(last.templates).sort().join(","), "classic,minimal,sofa", "every template sent")
      compare(last.default, "classic")
      compare(last.templates.classic.colors.accent, "#82fb9c", "resolved with the TV's colors")
      var rev = last.rev
      guide.colors = { accent: "#ff0000" }
      rt.send()
      compare(guide.sent[guide.sent.length - 1].rev, rev + 1, "a new revision each time")
      compare(guide.sent[guide.sent.length - 1].templates.classic.colors.accent, "#ff0000")
      compare(rt.list.map(function(x) { return x.id }).join(","), "classic,minimal,sofa", "built in first, in their order, then yours")
    }

    function test_tidy_phones_only_when_yours_were_read() {
      guide.remoteDevices = [{ id: "p1", prefs: { template: "gone" } }, { id: "p2", prefs: { template: "sofa" } }, { id: "p3", prefs: { template: null } }]
      rt.load()
      var moved = guide.sent.filter(function(m) { return m.prefs })
      compare(moved.length, 1, "only the phone on a template that's gone")
      compare(moved[0].prefs.id, "p1")
      compare(moved[0].prefs.template, null, "it follows the default")
      // a read that fails keeps yours, and moves no one
      guide.sent = []
      root.listed = { ok: false, error: "it couldn't be read" }
      guide.remoteDevices = [{ id: "p2", prefs: { template: "sofa" } }]
      rt.load()
      verify(rt.has("sofa"), "yours read before stay")
      compare(guide.sent.filter(function(m) { return m.prefs }).length, 0, "and no phone is moved off one")
      verify(rt.problems.some(function(p) { return p.why.indexOf("couldn't be read") >= 0 }), "the problem is said")
    }

    function test_builtin_read_all_or_nothing() {
      rt.load()
      verify(rt.has("minimal"))
      guide.remoteDevices = [{ id: "p1", prefs: { template: "minimal" } }]
      for (var round = 0; round < 2; round++) {
        guide.sent = []
        root.readerFails = round === 0
        root.readerPartial = round === 1
        rt.load()
        verify(rt.has("minimal") && rt.has("classic"), "the built-in ones read before stay (" + (round ? "one unreadable" : "the reader failed") + ")")
        compare(guide.sent.length, 0, "nothing sent: no templates, no phone moved")
        verify(rt.problems.some(function(p) { return p.why.indexOf("built-in templates couldn't all be read") >= 0 }), "said")
        verify(!rt.listOk, "and nothing tidied until a good read")
      }
      root.readerPartial = false
      rt.load()
      verify(rt.listOk, "a good read again")
    }

    function test_phone_choices() {
      rt.load()
      var got = null
      guide.remoteReady = false
      rt.setPrefs("p1", { pad: "off" }, function(r) { got = r })
      compare(got.ok, false)
      compare(got.error, "turn on the phone remote first", "refused with the remote off")
      guide.remoteReady = true
      got = null
      var n = rt.setPrefs("p1", { template: "sofa" }, function(r) { got = r })
      var m = guide.sent[guide.sent.length - 1]
      compare(m.req, n)
      compare(m.prefs.id, "p1")
      compare(m.prefs.template, "sofa")
      compare(got, null, "waits for the helper")
      rt.answered({ done: n + 99, ok: true })
      compare(got, null, "another answer isn't this one's")
      rt.answered({ done: n, ok: false, error: "no such template" })
      compare(got.ok, false)
      compare(got.error, "no such template")
      got = null
      rt.answered({ done: n, ok: true })
      compare(got, null, "answered once")
      // the helper never answers: given up on
      var late = null
      rt.setPrefs("p1", { size: 1 }, function(r) { late = r })
      tryVerify(function() { return late !== null }, 12000)
      compare(late.error, "the phone remote didn't answer")
    }

    function test_default_and_remove() {
      rt.load()
      compare(rt.setDefault("nope").ok, false)
      var saves = guide.saves
      verify(rt.setDefault("sofa").ok)
      compare(guide.remoteTemplate, "sofa")
      compare(guide.saves, saves + 1, "saved at once")
      compare(guide.sent[guide.sent.length - 1].default, "sofa", "and sent")
      var done = null
      rt.remove("classic", function(r) { done = r })
      compare(done.ok, false, "a built-in can't be removed")
      rt.remove("sofa", function(r) { done = r })
      verify(done.ok)
      compare(guide.remoteTemplate, "classic", "the default goes back to Classic")
      compare(root.calls.filter(function(c) { return c.command === "remote-remove" })[0].request.id, "sofa")
      // a save of a built-in's id is refused before the helper
      var calls = root.calls.length
      rt.save({ id: "classic", name: "X" }, "replace", function(r) { done = r })
      compare(done.ok, false)
      compare(root.calls.length, calls, "never asked")
      root.answer = { "remote-save": { ok: false, outcome: "failed", why: "at most 50 of yours" } }
      rt.save({ id: "new", name: "X" }, "replace", function(r) { done = r })
      compare(done.ok, false)
      compare(done.error, "at most 50 of yours", "the helper's reason")
      verify(!rt.busy, "free again after a failure")
    }
  }
}
