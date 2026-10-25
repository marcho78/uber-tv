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
