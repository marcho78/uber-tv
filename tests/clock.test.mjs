// The guide's clock, by the time zone it's in: the TV day starts at 4 AM by
// the clock, on the days the clocks change too (not 3 or 5 AM), and the
// grid starts on the hour or half past, where the zone is a quarter hour
// off too (UTC+5:45). Guide.qml loads only in the shell, so its own
// functions are cut out and run over a stand-in guide, in each zone:
// node tests/clock.test.mjs
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
const pad = n => String(n).padStart(2, "0")
const Qt = { formatDateTime: (d, f) => { assert.equal(f, "yyyy-MM-dd"); return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) } }
const root = { dayStartsAt: Number(guideSrc.match(/readonly property int dayStartsAt: (\d+) \* 3600/)[1]) * 3600, slot: Number(guideSrc.match(/readonly property int slot: (\d+)/)[1]) }
root.tvDayStart = new Function("root", "t", block(guideSrc, "function tvDayStart(t) {")).bind(null, root)
root.tvDay = new Function("root", "Qt", "t", block(guideSrc, "function tvDay(t) {")).bind(null, root, Qt)
// the grid's first half hour: windowStart, as Guide.qml binds it
const windowStart = guideSrc.match(/readonly property real windowStart: (.*)\n/)[1]
const gridStart = (now, slotOffset) => new Function("root", "now", "slot", "slotOffset", "slotStart",
  "return " + windowStart)(root, now, root.slot, slotOffset, t => new Function("root", "t", block(guideSrc, "function slotStart(t) {"))(root, t))

const at = iso => Date.parse(iso) / 1000           // an instant, written with its UTC offset
const local = t => { const d = new Date(t * 1000); return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + " " + pad(d.getHours()) + ":" + pad(d.getMinutes()) }

const zones = {
  "America/New_York": () => {
    // clocks forward on Sunday 8 March 2026 at 2 AM
    assert.equal(local(root.tvDayStart(at("2026-03-08T12:00:00-04:00"))), "2026-03-08 04:00", "the day the clocks go forward starts at 4 AM, not 5")
    assert.equal(root.tvDay(at("2026-03-08T04:30:00-04:00")), "2026-03-08", "4:30 that morning is the new day")
    assert.equal(root.tvDay(at("2026-03-08T03:30:00-04:00")), "2026-03-07", "3:30 is still the day before")
    // clocks back on Sunday 1 November 2026 at 2 AM
    assert.equal(local(root.tvDayStart(at("2026-11-01T12:00:00-05:00"))), "2026-11-01 04:00", "the day the clocks go back starts at 4 AM, not 3")
    assert.equal(root.tvDay(at("2026-11-01T03:30:00-05:00")), "2026-10-31", "3:30 that morning is still the day before")
    assert.equal(root.tvDay(at("2026-11-01T04:00:00-05:00")), "2026-11-01")
    // the day after: 4 AM too
    assert.equal(local(root.tvDayStart(at("2026-11-02T01:00:00-05:00"))), "2026-11-01 04:00", "1 AM belongs to the day that started at 4 AM before")
    assert.equal(local(gridStart(at("2026-03-08T10:20:00-04:00"), 0)), "2026-03-08 10:00")
  },
  "Asia/Kathmandu": () => {
    // UTC+5:45: the grid starts on the hour or half past here, not at :15 or :45
    assert.equal(local(gridStart(at("2026-06-10T10:20:00+05:45"), 0)), "2026-06-10 10:00")
    assert.equal(local(gridStart(at("2026-06-10T10:50:00+05:45"), 0)), "2026-06-10 10:30")
    assert.equal(local(gridStart(at("2026-06-10T10:50:00+05:45"), 2)), "2026-06-10 11:30", "moved on by half hours")
    assert.equal(local(root.tvDayStart(at("2026-06-10T10:20:00+05:45"))), "2026-06-10 04:00")
    assert.equal(root.tvDay(at("2026-06-10T03:59:00+05:45")), "2026-06-09")
  },
  "Asia/Kolkata": () => {
    assert.equal(local(gridStart(at("2026-06-10T10:20:00+05:30"), 0)), "2026-06-10 10:00")
    assert.equal(local(root.tvDayStart(at("2026-06-10T04:00:00+05:30"))), "2026-06-10 04:00")
  },
  "UTC": () => {
    assert.equal(local(gridStart(at("2026-06-10T10:44:00Z"), 0)), "2026-06-10 10:30")
    assert.equal(root.tvDay(at("2026-06-10T03:00:00Z")), "2026-06-09")
  },
}
const was = process.env.TZ
try {
  for (const [zone, check] of Object.entries(zones)) {
    process.env.TZ = zone
    assert.equal(new Date(at("2026-06-10T00:00:00Z") * 1000).getTimezoneOffset(),
                 { "America/New_York": 240, "Asia/Kathmandu": -345, "Asia/Kolkata": -330, UTC: 0 }[zone], "node in " + zone)
    check()
  }
} finally {
  if (was === undefined) delete process.env.TZ
  else process.env.TZ = was
}
console.log("clock: all good")
