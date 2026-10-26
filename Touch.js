.pragma library

// Tablet mode's rules (Guide.qml): whether the touch controls are on, how big
// a finger is on this screen, and how much room the screen gives. The setting
// is "auto" (on once a finger touches the screen, until Uber TV closes), "on"
// or "off". What was used last ("keyboard", "pointer", "touch" or "remote")
// only changes focus and hints: the touch controls stay put.

var SETTINGS = ["auto", "on", "off"]
var INPUTS = ["keyboard", "pointer", "touch", "remote"]
var FINGER_MM = 9               // a touch target, measured on the screen
var MIN_PX = 44                 // whatever the screen says about its size,
var MAX_PX = 72                 // a target stays between these

function setting(v) { return SETTINGS.indexOf(v) >= 0 ? v : "auto" }

function on(setting, latched) { return setting === "on" || (setting === "auto" && latched === true) }

// A finger in the guide's pixels: 9 mm from the screen's physical pixels per
// mm and its scale. A screen that doesn't say gets 3.2 units; either way it
// stays inside 44 to 72 px (a TV or a projector can report a silly size).
function fingerPx(density, dpr, u) {
  var d = Number(density)
  var r = Number(dpr) > 0 ? Number(dpr) : 1
  var px = d > 0 && isFinite(d) ? FINGER_MM * d / r : 3.2 * (Number(u) || 0)
  return Math.round(Math.min(MAX_PX, Math.max(MIN_PX, px)))
}

// How much room there is, in units across: compact (a portrait screen, a
// narrow window), medium (4:3) or expanded (3:2, 16:10, 16:9 and wider)
function fit(width, u) {
  var across = Number(u) > 0 ? Number(width) / Number(u) : 0
  return across < 62 ? "compact" : across < 88 ? "medium" : "expanded"
}

// The guide's unit: a 60th of its height, and on a narrow screen (a tablet
// in portrait, a narrow window) small enough for 50 units across, so a
// layout made for a wide screen still fits; never under 10 px. Landscape
// screens get a 60th of their height, as always.
var ACROSS = 50
function unit(width, height) {
  var h = Number(height) > 0 ? Number(height) : 0
  var w = Number(width) > 0 ? Number(width) : Infinity
  return Math.max(10, Math.round(Math.min(h / 60, w / ACROSS)))
}

// A compact screen draws the theme's layout stepped down (what was chosen
// stays as it is): the nav rail tucked away (☰ opens it), an hour across
function railShows(rail, fit) { return rail === "always" && fit === "compact" ? "focus" : rail }
function hoursAcross(hours, fit) { return fit === "compact" ? Math.min(hours, 1) : hours }

// A row a finger taps: in tablet mode never shorter than a finger
function rowPx(px, touch, finger) { return touch ? Math.max(px, finger) : px }

// A click a finger (or a pen) made: Qt makes a mouse click of a touch and
// says so (MouseEvent.source 2, or 1 where the system made it); a mouse's
// or a touchpad's own click is 0. Tablet mode being on says what the screen
// shows, never what made a click: a mouse still picks with a click and
// opens with a double click.
function byFinger(mouse) { return !!mouse && (mouse.source === 2 || mouse.source === 1) }

// Qt's own key codes (tests/qml/tst_touchmode.qml checks they match)
var KEY = { left: 0x01000012, up: 0x01000013, right: 0x01000014, down: 0x01000015,
            pageUp: 0x01000016, pageDown: 0x01000017, j: 0x4a, l: 0x4c }
var SHIFT = 0x02000000

// A touch button's own key, as its hint gives it ({ key, mods }): never the
// arrows or Page Up and Down (a finger does that), never ← → J L while
// watching (they hold to scrub; touch has its own buttons), no modifier but
// Shift. What a hint shows is never read for this.
function pressable(t, watching) {
  if (!t || typeof t.key !== "number" || t.key <= 0) return false
  if ([KEY.left, KEY.right, KEY.up, KEY.down, KEY.pageUp, KEY.pageDown].indexOf(t.key) >= 0) return false
  if (watching && (t.key === KEY.j || t.key === KEY.l)) return false
  var mods = t.mods === undefined ? 0 : t.mods
  return mods === 0 || mods === SHIFT
}

// A hint list for the touch controls: Back (the hint whose touch is back),
// the buttons (hints with their own touch key, or a text field's action), and
// the words with no key at all ("Checking it…"). The rest a finger does.
function split(hints) {
  var out = { back: null, buttons: [], notes: [] }
  var list = Array.isArray(hints) ? hints : []
  for (var i = 0; i < list.length; i++) {
    var h = list[i]
    if (!h || typeof h.label !== "string") continue
    var t = h.touch
    if (t && t.back === true && !out.back) out.back = h
    else if (t && (typeof t.run === "function" || typeof t.key === "number")) out.buttons.push(h)
    else if (!t && (!Array.isArray(h.keys) || h.keys.length === 0) && h.label) out.notes.push(h)
  }
  return out
}

// How many of the buttons fit in the room, given their widths and the gap,
// leaving space for ⋯ when not all of them do (room 0: no limit)
function fitCount(widths, gap, room, moreWidth) {
  var n = widths.length
  if (!(room > 0)) return n
  var total = 0
  for (var i = 0; i < n; i++) total += widths[i] + (i ? gap : 0)
  if (total <= room) return n
  var used = moreWidth
  for (var k = 0; k < n; k++) {
    var next = used + gap + widths[k]
    if (next > room) return k
    used = next
  }
  return n
}
