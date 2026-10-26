.pragma library

// The guide's look, part by part. A theme (or you, or an AI agent through
// setStyle) can style each part of the guide, an "element": a box gets a
// fill, a border, corners and a shape, a shadow and padding; its text gets
// a color, a font, a size, weight, case and letter spacing. Whatever a theme
// leaves out comes from Retro, the guide's own look, written out below.
//
// Lengths are in units, a 60th of the screen's height, so a theme looks the
// same on any screen; a string like "2px" is pixels. Keycaps and their labels
// go by the key's height instead (0.2 is a fifth of it). Colors are #rrggbb or
// #aarrggbb, a color slot's name ("accent": the theme's colors, with yours on
// top), a color of your Omarchy theme ("omarchy.blue", from its colors.toml,
// so it follows when you change themes), or "none".

var BOX = ["fill", "border", "radius", "shape", "slant", "path", "shadow", "padding"]
var TEXT = ["color", "font", "size", "weight", "case", "letterSpacing", "italic"]
var SHAPES = ["rect", "pill", "slant", "arrow", "chevron", "path"]
var WEIGHTS = { thin: 100, light: 300, normal: 400, medium: 500, semibold: 600, bold: 700, black: 900 }
var CASES = ["upper", "lower", "title", "none"]
var FONT_ROLES = ["body", "display", "mono"]

// Every element: what it is, which properties it takes (box ones, text ones
// under "text", and its own), its states, and Retro's style for it.
var ELEMENTS = [
  { key: "background", section: "GUIDE", label: "Background", about: "behind everything in the guide (a picture, if you set one, goes over it)",
    box: ["fill"], style: { fill: { from: "bgTop", to: "bgBottom", direction: "down" } } },
  { key: "title", section: "GUIDE", label: "Title", about: "UBER TV, top left (a logo picture replaces it)",
    text: true, style: { text: { color: "accent", font: "display", size: 2, weight: "bold", case: "upper", letterSpacing: 0.15 } } },
  { key: "showing", section: "GUIDE", label: "What's shown", about: "beside the title: ALL CHANNELS, or the source and categories shown",
    text: true, states: ["filtered", "managing"],
    style: { text: { color: "textDim", size: 0.95, weight: "normal", case: "upper" } },
    stateStyle: { filtered: { text: { color: "accent", weight: "bold" } }, managing: { text: { color: "alert", weight: "bold" } } } },
  { key: "clock", section: "GUIDE", label: "Clock", about: "the time, top right",
    text: true, style: { text: { color: "text", font: "display", size: 2, weight: "bold", case: "none" } } },
  { key: "preview", section: "GUIDE", label: "Preview box", about: "the small TV beside the info panel",
    box: ["fill", "border", "radius", "shape", "slant", "path", "shadow"],
    style: { fill: "preview", border: { width: 0.09, color: "cellBorder" } } },
  { key: "infoPanel", section: "GUIDE", label: "Info panel", about: "the panel about the program under the cursor",
    box: BOX, style: { fill: "infoPanel", border: { width: 0.09, color: "cellBorder" }, padding: 1 } },
  { key: "infoChannel", section: "GUIDE", label: "Info: channel", about: "the info panel's first line: channel number, name and category",
    text: true, style: { text: { color: "textDim", size: 1.1, weight: "normal", case: "upper" } } },
  { key: "infoTitle", section: "GUIDE", label: "Info: title", about: "the program's title in the info panel (up to two lines)",
    text: true, style: { text: { color: "text", size: 1.9, weight: "bold", case: "none" } } },
  { key: "infoTime", section: "GUIDE", label: "Info: times", about: "when it's on, and how long is left",
    text: true, style: { text: { color: "accent", size: 1.1, weight: "normal", case: "upper" } } },
  { key: "infoNext", section: "GUIDE", label: "Info: next", about: "what's on next; later is the ones after it, when layout.upNext lists more than one",
    text: true, states: ["later"], style: { text: { color: "textDim", size: 1, weight: "normal", case: "none" } },
    stateStyle: { later: { text: { color: "textDim" } } } },
  { key: "infoDesc", section: "GUIDE", label: "Description", about: "what a show is about, under its times in the info panel (from program listings)",
    text: true, style: { text: { color: "textDim", size: 0.95, weight: "normal", case: "none" } } },
  { key: "upNextLabel", section: "GUIDE", label: "Info: Up next", about: "the heading over the list of what's next (layout.upNext 2 or more)",
    text: true, style: { text: { color: "textDim", size: 0.8, weight: "normal", case: "none", letterSpacing: 0.1 } } },
  { key: "infoProgress", section: "GUIDE", label: "Info: progress", about: "how far into the program, under its times (layout.infoProgress)",
    box: ["fill", "radius"], own: { track: "color", height: "length", width: "width" },
    style: { fill: "accent", track: "cellBorder", height: 0.35, radius: 0, width: 0.6 } },
  { key: "infoArea", section: "GUIDE", label: "Info area", about: "the whole strip holding the preview and the info panel (none by default)",
    box: BOX, style: { fill: "none" } },
  { key: "divider", section: "GUIDE", label: "Divider", about: "the thin lines between the info area, the grid and the key hints (layout.dividers)",
    own: { color: "color", height: "length" }, style: { color: "cellBorder", height: "1px" } },
  { key: "previewTag", section: "GUIDE", label: "Preview tag", about: "the label on the preview box saying what it shows (layout.previewTag)",
    box: ["fill", "border", "radius", "padding"], text: true,
    style: { fill: "#cc000000", padding: 0.4, text: { color: "textDim", font: "mono", size: 0.7, weight: "normal", case: "upper", letterSpacing: 0.12 } } },

  { key: "timeBar", section: "GRID", label: "Time bar", about: "the date and the times across the top of the grid",
    box: BOX, text: true, style: { fill: "header", padding: 0.6, text: { color: "headerText", size: 1, weight: "bold", case: "upper" } } },
  { key: "band", section: "GRID", label: "Category band", about: "the band naming each category, between its channels",
    box: BOX, text: true,
    style: { fill: "band", border: { width: "1px", color: "bandText" }, padding: 0.6,
             text: { color: "bandText", size: 0.95, weight: "bold", case: "upper", letterSpacing: 0.1 } } },
  { key: "channelCell", section: "GRID", label: "Channel cell", about: "each channel's cell, left of its programs",
    box: BOX, states: ["current", "marked"],
    style: { fill: "channelCell", border: { width: 0.17, color: "none" }, padding: 0.6 },
    stateStyle: { current: { fill: "cellBorder" }, marked: { border: { color: "accent" } } } },
  { key: "channelNumber", section: "GRID", label: "Channel number", about: "the number in the channel cell (smaller with logos on)",
    text: true, style: { text: { color: "accent", size: 1.6, weight: "bold", case: "none" } } },
  { key: "channelName", section: "GRID", label: "Channel name", about: "the name in the channel cell",
    text: true, style: { text: { color: "text", size: 0.95, weight: "bold", case: "upper" } } },
  { key: "logoBadge", section: "GRID", label: "Logo badge", about: "the box holding a channel's logo (or its initial) with logos on",
    box: ["fill", "border", "radius", "shape"], text: true,
    style: { fill: "bgBottom", border: { width: "1px", color: "cellBorder" }, text: { color: "textDim", size: 1.2, weight: "bold" } } },
  { key: "programCell", section: "GRID", label: "Program cell", about: "each program in the grid; selected is the one under the cursor",
    box: BOX, text: true, states: ["selected"],
    style: { fill: "cell", border: { width: "1px", color: "cellBorder" }, padding: 0.6,
             text: { color: "text", size: 0.95, weight: "normal", case: "none" } },
    stateStyle: { selected: { fill: "selected", border: { color: "selected" }, text: { color: "selectedText", weight: "bold" } } } },
  { key: "liveTag", section: "GRID", label: "Live tag", about: "● LIVE in a live channel's program cell; its color goes with the cell's text unless set",
    text: true, style: { text: { color: "inherit", size: 0.95, weight: "normal", case: "upper" } } },
  { key: "nowLine", section: "GRID", label: "Now line", about: "the line marking now: down the grid, a tick in the time bar, or none",
    own: { color: "color", width: "length", style: ["line", "tick", "none"] }, style: { color: "timeline", width: 0.17, style: "line" } },

  { key: "topBar", section: "BARS", label: "Top bar", about: "the status line across the top (layout.masthead bar)",
    box: BOX, style: { fill: "none", padding: 0 } },
  { key: "barBadge", section: "BARS", label: "Bar badge", about: "the badge at the start of the top bar",
    box: ["fill", "border", "radius", "padding"], text: true,
    style: { fill: "accent", padding: 0.35, text: { color: "selectedText", size: 0.85, weight: "bold", case: "none" } } },
  { key: "barLabel", section: "BARS", label: "Bar label", about: "quiet words in the bars: labels, separators, counts",
    text: true, style: { text: { color: "textDim", size: 0.85, weight: "normal", case: "none" } } },
  { key: "barValue", section: "BARS", label: "Bar value", about: "what a bar label is set to (all, youtube + iptv…)",
    text: true, style: { text: { color: "accent", size: 0.85, weight: "normal", case: "none" } } },
  { key: "modeBadge", section: "BARS", label: "Mode badge", about: "GUIDE, MANAGE or WATCHING at the start of the status line (layout.footer status)",
    box: ["fill", "border", "radius", "padding"], text: true,
    style: { fill: "accent", padding: 0.35, text: { color: "selectedText", size: 0.85, weight: "bold", case: "upper" } } },

  { key: "pane", section: "TABLE", label: "Pane", about: "the boxes of the table layout: channels, preview, lineup",
    box: BOX, style: { fill: "none", border: { width: "1px", color: "cellBorder" }, padding: 0.8 } },
  { key: "paneTitle", section: "TABLE", label: "Pane title", about: "a pane's name, set into its top border; its fill cuts the border behind it",
    box: ["fill", "border", "radius", "padding"], text: true,
    style: { fill: "bgTop", padding: 0.3, text: { color: "accent", size: 0.85, weight: "normal", case: "none" } } },
  { key: "tableHeader", section: "TABLE", label: "Column names", about: "the names over a table's columns",
    text: true, style: { text: { color: "textDim", size: 0.8, weight: "normal", case: "none" } } },
  { key: "tableGroup", section: "TABLE", label: "Group", about: "a category's heading in the channel table",
    text: true, style: { text: { color: "bandText", size: 0.85, weight: "bold", case: "none" } } },
  { key: "tableRow", section: "TABLE", label: "Table row", about: "a row in a table; current is the one under the cursor",
    box: ["fill", "border", "radius", "padding"], states: ["current"],
    style: { fill: "none", padding: 0.5 }, stateStyle: { current: { fill: "cellBorder" } } },
  { key: "rowMarker", section: "TABLE", label: "Row marker", about: "› by the current row; ▶ by what's playing in the lineup",
    text: true, states: ["playing"], style: { text: { color: "accent", size: 0.85, weight: "bold" } },
    stateStyle: { playing: { text: { color: "accent" } } } },
  { key: "tableText", section: "TABLE", label: "Table text", about: "what's on, and titles in the lineup",
    text: true, style: { text: { color: "text", size: 0.85, weight: "normal", case: "none" } } },
  { key: "tableDim", section: "TABLE", label: "Table detail", about: "times, lengths and time left in the tables, and the lineup's notes",
    text: true, style: { text: { color: "textDim", size: 0.8, weight: "normal", case: "none" } } },
  { key: "rowProgress", section: "TABLE", label: "Row progress", about: "the little bar of how far in a program is; live fills it",
    box: ["fill", "radius"], states: ["live"], own: { track: "color", height: "length", width: "length" },
    style: { fill: "textDim", track: "cellBorder", height: 0.3, width: 2.6, radius: 0 }, stateStyle: { live: { fill: "alert" } } },

  { key: "flapTile", section: "BOARD", label: "Flap", about: "each letter's flap on the board; status is the status column's; seam is the split across it, aspect its width to its height, gap the space between flaps",
    box: ["fill", "border", "radius"], text: true, states: ["status"], own: { seam: "color", aspect: "fraction", gap: "length" },
    style: { fill: "channelCell", radius: 0.12, seam: "bgBottom", aspect: 0.66, gap: 0.08,
             text: { color: "text", font: "mono", size: 1.2, weight: "bold", case: "upper" } },
    stateStyle: { status: { text: { color: "accent" } } } },

  { key: "footer", section: "KEYS", label: "Footer", about: "the strip along the bottom holding the key hints (none by default)",
    box: BOX, style: { fill: "none" } },
  { key: "keycap", section: "KEYS", label: "Keycap", about: "each key drawn in the key hints; radius, depth and text size go by the key's height",
    box: ["fill", "border"], text: true, own: { edge: "color", depth: "fraction", radius: "fraction" },
    style: { fill: "keyFace", border: { width: "1px", color: "auto" }, edge: "keyEdge", depth: 0.12, radius: 0.2,
             text: { color: "keyText", size: 0.62, weight: "bold", case: "none" } } },
  { key: "keyLabel", section: "KEYS", label: "Key label", about: "what each key does, beside it; size goes by the key's height",
    text: true, style: { text: { color: "textDim", size: 0.58, weight: "bold", case: "upper" } } },

  // tablet mode's buttons (ui/TouchButton.qml): a finger sizes them (a theme
  // can't make one smaller); corners, border and text size are fractions of it
  { key: "touchButton", section: "TABLET MODE", label: "Touch button", about: "tablet mode's buttons; primary is a screen's main one (Watch, OK)",
    box: ["fill", "border"], text: true, own: { radius: "fraction" }, states: ["primary"],
    style: { fill: "boxBg", border: { width: 0.025, color: "cellBorder" }, radius: 0.22, text: { color: "text", font: "body", size: 0.3, weight: "medium", case: "none" } },
    stateStyle: { primary: { fill: "accent", border: { color: "accent" } } } },

  { key: "scrim", section: "BOXES", label: "Shade", about: "the shade over the guide behind a box",
    box: ["fill"], style: { fill: "scrim" } },
  { key: "box", section: "BOXES", label: "Box", about: "dialog boxes (add channels, settings…) and the style panel",
    box: BOX, style: { fill: "boxBg", border: { width: 0.17, color: "boxBorder" }, padding: 1.2 } },
  { key: "boxTitle", section: "BOXES", label: "Box title", about: "a box's title",
    text: true, style: { text: { color: "accent", size: 1.4, weight: "bold", case: "upper" } } },
  { key: "boxText", section: "BOXES", label: "Box text", about: "what a box says under its title",
    text: true, style: { text: { color: "text", size: 1, weight: "normal", case: "none" } } },
  { key: "panelHeader", section: "BOXES", label: "Panel heading", about: "the section names in the style panel and Home's panel: THEME, BACKGROUND…",
    text: true, style: { text: { color: "accent", size: 0.85, weight: "bold", case: "upper", letterSpacing: 0.12 } } },
  { key: "listRow", section: "BOXES", label: "List row", about: "rows in a box's list; current is the one under the cursor",
    box: ["fill", "border", "radius"], states: ["current"], style: { fill: "none" }, stateStyle: { current: { fill: "cellBorder" } } },
  { key: "input", section: "BOXES", label: "Text field", about: "where you type in a box; focused while you're typing in it",
    box: ["fill", "border", "radius"], states: ["focused"],
    style: { fill: "bgBottom", border: { width: "1px", color: "cellBorder" } }, stateStyle: { focused: { border: { color: "accent" } } } },

  { key: "searchField", section: "MENUS", label: "Search field", about: "where you type in Search, big, with its icon and a blinking caret; focused while you're typing (not in the results); caret is the caret's color",
    box: BOX, text: true, states: ["focused"], own: { caret: "color" },
    style: { fill: "#d9101118", border: { width: 0.1, color: "#33ffffff" }, radius: 0.9, padding: 1.4, caret: "accent",
             text: { color: "text", size: 2, weight: "semibold", case: "none" } },
    stateStyle: { focused: { border: { color: "accent" }, shadow: { color: "#80000000", blur: 1.5, x: 0, y: 0.3 } } } },
  { key: "menuCategory", section: "MENUS", label: "Menu part", about: "the parts down the left of Settings (General, Live TV, Library, About); current is the one open, focused the one under the cursor",
    box: BOX, text: true, states: ["current", "focused"],
    style: { fill: "none", radius: 0.8, padding: 1.1, text: { color: "textDim", font: "display", size: 1.6, weight: "bold", case: "none" } },
    stateStyle: { current: { fill: "#d9101118", text: { color: "text" } },
                  focused: { fill: "text", shadow: { color: "#80000000", blur: 1.5, x: 0, y: 0.3 }, text: { color: "bgBottom" } } } },
  { key: "menuRow", section: "MENUS", label: "Menu row", about: "each row in Settings, the Customize panels, the boxes and the style panel, big enough to read across the room; height is a row's, grow how much the focused one grows (0.03: 3%)",
    box: BOX, text: true, states: ["focused"], own: { height: "length", grow: "fraction" },
    style: { fill: "#d9101118", border: { width: "1px", color: "#1fffffff" }, radius: 0.7, padding: 1.2, height: 3.8, grow: 0,
             text: { color: "text", size: 1.45, weight: "semibold", case: "none" } },
    stateStyle: { focused: { fill: "text", border: { color: "text" }, grow: 0.03, shadow: { color: "#80000000", blur: 1.5, x: 0, y: 0.3 }, text: { color: "bgBottom" } } } },
  { key: "menuValue", section: "MENUS", label: "Menu value", about: "a setting's value, at the right of its row (‹ › round it when ← → change it); focused when its row is",
    text: true, states: ["focused"], style: { text: { color: "textDim", size: 1.3, weight: "medium", case: "none" } },
    stateStyle: { focused: { text: { color: "bgBottom" } } } },
  { key: "menuHeader", section: "MENUS", label: "Menu heading", about: "the headings between groups of rows in the Customize panels: BACKGROUND, SECTIONS…",
    text: true, style: { text: { color: "accent", size: 1, weight: "bold", case: "upper", letterSpacing: 0.12 } } },
  { key: "menuNote", section: "MENUS", label: "Menu note", about: "what the focused setting does, under the rows",
    text: true, style: { text: { color: "textDim", size: 1.2, weight: "normal", case: "none" } } },
  { key: "toggle", section: "MENUS", label: "Switch", about: "a setting's on/off switch; on is how it looks on; knob is the round part's color, width and height the switch's size",
    box: ["fill", "border", "shape", "radius"], states: ["on"], own: { knob: "color", width: "length", height: "length" },
    style: { fill: "cellBorder", shape: "pill", knob: "textDim", width: 3.4, height: 1.8 },
    stateStyle: { on: { fill: "accent", knob: "text" } } },

  { key: "lowerThird", section: "LOWER THIRD", label: "Lower third", about: "the channel banner over the TV; height, margin and width set where it sits",
    box: BOX, own: { height: "length", margin: "length", width: "width", align: ["left", "center", "right"] },
    style: { fill: "ltBg", border: { width: 0.08, color: "ltBorder" }, padding: 1.2, height: 7, margin: 2, width: "full", align: "center" } },
  { key: "ltNumber", section: "LOWER THIRD", label: "Number", about: "the big channel number",
    text: true, style: { text: { color: "ltNumber", font: "display", size: 4, weight: "bold", case: "none" } } },
  { key: "ltChannel", section: "LOWER THIRD", label: "Channel name", about: "the channel's name, over the title",
    text: true, style: { text: { color: "ltChannel", size: 1, weight: "normal", case: "upper" } } },
  { key: "ltTitle", section: "LOWER THIRD", label: "Title", about: "what's on",
    text: true, style: { text: { color: "ltTitle", size: 1.5, weight: "bold", case: "none" } } },
  { key: "ltProgress", section: "LOWER THIRD", label: "Progress", about: "how far into the show (fill), over its track",
    box: ["fill", "radius"], own: { track: "color", height: "length" },
    style: { fill: "ltProgress", track: "ltTrack", height: 0.5, radius: 0 } },
  { key: "ltClock", section: "LOWER THIRD", label: "Clock", about: "the time, right",
    text: true, style: { text: { color: "ltClock", font: "display", size: 1.5, weight: "bold", case: "none" } } },
  { key: "ltTime", section: "LOWER THIRD", label: "Show times", about: "the show's start and end, under the clock",
    text: true, style: { text: { color: "ltTime", size: 0.9, weight: "normal", case: "none" } } },

  { key: "rail", section: "RAIL", label: "Nav rail", about: "the strip down the left with a way to every part (Home, Live TV, the library, Settings); open is how it looks widened, with its labels",
    box: BOX, states: ["open"], style: { fill: "bgBottom", border: { width: "1px", color: "cellBorder", sides: ["right"] }, padding: 0.7 },
    stateStyle: { open: { shadow: { color: "#99000000", blur: 2, x: 0.3, y: 0 } } } },
  { key: "railItem", section: "RAIL", label: "Rail item", about: "each way in the rail, its icon and name; current is where you are, focused the one under the cursor while it's open",
    box: ["fill", "border", "radius", "padding"], text: true, states: ["current", "focused"],
    style: { fill: "none", radius: 0.6, padding: 0.7, text: { color: "textDim", size: 1.05, weight: "bold", case: "none" } },
    stateStyle: { current: { text: { color: "accent" } }, focused: { fill: "cellBorder", text: { color: "text" } } } },
  { key: "homeTile", section: "HOME", label: "Tile", about: "the tiles on Home (Live TV, Movies, On Demand, My List); current is the one selected",
    box: BOX, text: true, states: ["current"],
    style: { fill: "#a6101118", border: { width: "1px", color: "#24ffffff" }, radius: 1.1, padding: 1.1,
             text: { color: "text", font: "display", size: 1.2, weight: "bold", case: "none" } },
    stateStyle: { current: { fill: "text", text: { color: "bgBottom" } } } },
  { key: "homeCard", section: "HOME", label: "Card", about: "each card in Home's rows (a show, a video, a movie, a channel); current is the one selected",
    box: BOX, states: ["current"], style: { fill: "cell", border: { width: 0.12, color: "none" }, radius: 0.5 },
    stateStyle: { current: { border: { color: "text" } } } },
  { key: "homeCardTitle", section: "HOME", label: "Card title", about: "the title under a card on Home",
    text: true, style: { text: { color: "text", size: 0.9, weight: "bold", case: "none" } } },
  { key: "homeCardSub", section: "HOME", label: "Card details", about: "the channel, time or length under a card's title on Home",
    text: true, style: { text: { color: "textDim", size: 0.8, weight: "normal", case: "none" } } },
  { key: "homeRowTitle", section: "HOME", label: "Row title", about: "the name over each row on Home: Continue watching, On now…",
    text: true, style: { text: { color: "text", size: 1.15, weight: "bold", case: "none" } } },
  { key: "statusChip", section: "HOME", label: "Status chip", about: "the little chips top right on Home: the phone remote, how old the listings are",
    box: BOX, text: true, style: { fill: "#a60e0f16", border: { width: "1px", color: "#24ffffff" }, radius: 1, padding: 0.8,
                                   text: { color: "textDim", size: 0.85, weight: "medium", case: "none" } } },
  { key: "homeShade", section: "HOME", label: "Shade", about: "the dark coming in from the left and the bottom over Home's background, so the words read (how dark: the background's darken setting)",
    own: { color: "color" }, style: { color: "bgBottom" } },
  { key: "heroKicker", section: "HOME", label: "Kicker", about: "the small line over the title at the top of Home: Continue watching, On now…",
    text: true, style: { text: { color: "accent", font: "mono", size: 0.8, weight: "bold", case: "upper", letterSpacing: 0.18 } } },
  { key: "heroTitle", section: "HOME", label: "Title", about: "the big title at the top of Home, of what's selected",
    text: true, style: { text: { color: "text", font: "display", size: 3.6, weight: "black", case: "none" } } },
  { key: "heroMeta", section: "HOME", label: "Details", about: "what's selected, in a line or two, under the title",
    text: true, style: { text: { color: "textDim", size: 1.2, weight: "normal", case: "none" } } },

  { key: "libraryTab", section: "LIBRARY", label: "Tab", about: "Movies & Series, On Demand and My List across the top of the library; current is the one open",
    text: true, states: ["current"], style: { text: { color: "textDim", font: "display", size: 1.5, weight: "bold", case: "none" } },
    stateStyle: { current: { text: { color: "accent" } } } },
  { key: "rowTitle", section: "LIBRARY", label: "Row title", about: "the name over each row of the library: a genre, a channel, Continue watching",
    text: true, style: { text: { color: "text", size: 1.15, weight: "bold", case: "none" } } },
  { key: "posterCard", section: "LIBRARY", label: "Poster", about: "each movie's poster or video's picture in the library; current is the one under the cursor",
    box: BOX, states: ["current"], style: { fill: "cell", border: { width: 0.12, color: "none" } },
    stateStyle: { current: { border: { color: "accent" } } } },
  { key: "liveBadge", section: "LIBRARY", label: "Live badge", about: "● LIVE on a live channel's card, on Home",
    box: ["fill", "border", "radius", "padding"], text: true,
    style: { fill: "alert", radius: 1, padding: 0.4, text: { color: "#ffffff", font: "mono", size: 0.62, weight: "bold", case: "upper" } } },
  { key: "cardBadge", section: "LIBRARY", label: "Card badge", about: "✓ Watched and My List on a poster",
    box: ["fill", "border", "radius", "padding"], text: true,
    style: { fill: "#cc000000", radius: 1, padding: 0.4, text: { color: "#ffffff", size: 0.7, weight: "bold", case: "none" } } },
  { key: "posterTitle", section: "LIBRARY", label: "Poster title", about: "the title under a poster",
    text: true, style: { text: { color: "text", size: 0.9, weight: "bold", case: "none" } } },
  { key: "posterSub", section: "LIBRARY", label: "Poster details", about: "the year, the channel or how long, under the title",
    text: true, style: { text: { color: "textDim", size: 0.8, weight: "normal", case: "none" } } },

  { key: "vodBar", section: "PLAYER", label: "Player bar", about: "the bar over a movie or video on demand, with its title, where you are and the keys",
    box: BOX, style: { fill: "ltBg", border: { width: 0.08, color: "ltBorder" }, padding: 1.4 } },
  { key: "vodTitle", section: "PLAYER", label: "Title", about: "the movie's or video's title",
    text: true, style: { text: { color: "ltTitle", font: "display", size: 1.8, weight: "bold", case: "none" } } },
  { key: "vodInfo", section: "PLAYER", label: "Details", about: "what it is: the genre and year, or the channel",
    text: true, style: { text: { color: "ltChannel", size: 1, weight: "normal", case: "none" } } },
  { key: "vodTime", section: "PLAYER", label: "Times", about: "how far in, and how long it is",
    text: true, style: { text: { color: "ltTime", font: "mono", size: 1, weight: "normal", case: "none" } } },
  { key: "vodProgress", section: "PLAYER", label: "Progress", about: "where you are (fill) along the whole of it (track)",
    box: ["fill", "radius"], own: { track: "color", height: "length" }, style: { fill: "ltProgress", track: "ltTrack", height: 0.4, radius: 0 } },

  { key: "card", section: "CHANNEL CARD", label: "Backdrop", about: "behind the card shown while changing channel, over the TV",
    box: ["fill"], style: { fill: "cardBackdrop" } },
  { key: "cardName", section: "CHANNEL CARD", label: "Number and name", about: "the channel's number and name on the card",
    text: true, style: { text: { color: "cardName", font: "display", size: 1.25, weight: "bold", case: "upper" } } },
  { key: "cardStatus", section: "CHANNEL CARD", label: "Status", about: "TUNING… or NO SIGNAL (that one is in the alert color)",
    text: true, style: { text: { color: "cardStatus", size: 0.85, weight: "bold", case: "upper" } } },
  { key: "cardFrame", section: "CHANNEL CARD", label: "Logo frame", about: "the frame holding a channel's initial when it has no logo",
    box: ["fill", "border", "radius", "shape", "slant", "path", "shadow"], text: true,
    style: { fill: "none", border: { width: 0.08, color: "cardFrame" }, text: { color: "cardStatus", size: 2.4, weight: "bold" } } },

  // An app's screen. Each part follows the guide's part it's like (follows),
  // state by state, until a theme or you style it: the library's cards and
  // titles, Home's big title, the menus' rows.
  { key: "appCard", section: "APPS", label: "Card", follows: "posterCard",
    about: "each card on an app's screen; current is the one selected (the guide's focus ring goes around it whatever its style); grow is how much the selected one grows (0.05: 5%)",
    box: BOX, states: ["current"], own: { grow: "fraction" }, style: { grow: 0 }, stateStyle: { current: { grow: 0.05 } } },
  { key: "appCardTitle", section: "APPS", label: "Card title", follows: "posterTitle", about: "the title under a card on an app's screen",
    text: true, style: {} },
  { key: "appCardSub", section: "APPS", label: "Card details", follows: "posterSub", about: "the line under a card's title on an app's screen",
    text: true, style: {} },
  { key: "appRowTitle", section: "APPS", label: "Row title", follows: "rowTitle", about: "the name over each row on an app's screen",
    text: true, style: {} },
  { key: "appBadge", section: "APPS", label: "Badge", follows: "cardBadge", about: "a card's badge (NEW, 4K, ✓ for watched) on an app's screen",
    box: ["fill", "border", "radius", "padding"], text: true, style: {} },
  { key: "appProgress", section: "APPS", label: "Progress", follows: "vodProgress", about: "how far into it (fill) along a card's bottom (track) on an app's screen",
    box: ["fill", "radius"], own: { track: "color", height: "length" }, style: {} },
  { key: "appTopKicker", section: "APPS", label: "Top: kicker", follows: "heroKicker", about: "the row's name over the title at the top of an app's screen (when its top shows what's selected)",
    text: true, style: {} },
  { key: "appTopTitle", section: "APPS", label: "Top: title", follows: "heroTitle", about: "the title of what's selected at the top of an app's screen, and a featured (hero) row's",
    text: true, style: {} },
  { key: "appTopMeta", section: "APPS", label: "Top: details", follows: "heroMeta", about: "what's selected, in a line, under the title at the top of an app's screen",
    text: true, style: {} },
  { key: "appTopText", section: "APPS", label: "Top: text", follows: "infoDesc", about: "two lines about what's selected, at the top of an app's screen and in a featured row",
    text: true, style: {} },
  { key: "appDetailTitle", section: "APPS", label: "Details: title", follows: "heroTitle", about: "the title on an item's details page (Cinematic draws it full size, Classic smaller)",
    text: true, style: {} },
  { key: "appDetailMeta", section: "APPS", label: "Details: line", follows: "heroMeta", about: "the line under the title on a details page: year, length, rating",
    text: true, style: {} },
  { key: "appDetailText", section: "APPS", label: "Details: text", follows: "boxText", about: "what it's about, on a details page",
    text: true, style: {} },
  { key: "appFactLabel", section: "APPS", label: "Details: fact name", follows: "posterSub", about: "a fact's name on a details page (Director, Runtime)",
    text: true, style: {} },
  { key: "appFactValue", section: "APPS", label: "Details: fact", follows: "posterTitle", about: "a fact on a details page",
    text: true, style: {} },
  { key: "appChip", section: "APPS", label: "Details: chip", follows: "statusChip", about: "the small labels on a details page (Drama, 4K)",
    box: BOX, text: true, style: {} },
  { key: "appButton", section: "APPS", label: "Button", follows: "menuRow", about: "a details page's buttons (Play, Resume, Watched); focused is the one selected; grow is how much it grows",
    box: BOX, text: true, states: ["focused"], own: { height: "length", grow: "fraction" }, style: {} },
  { key: "appShade", section: "APPS", label: "Shade", follows: "homeShade", about: "the dark over a picture behind an app's screen, a featured row and a Cinematic details page, so the words read (never under 30% over an app's picture)",
    own: { color: "color" }, style: {} },
  // api 4's richer blocks
  { key: "appTableHead", section: "APPS", label: "Table: column names", follows: "posterSub", about: "the names over a table's columns on an app's screen (standings, a schedule)",
    text: true, style: {} },
  { key: "appTable", section: "APPS", label: "Table: line", follows: "menuRow", about: "each line of a table on an app's screen, its values in their columns; focused is the one selected",
    box: BOX, text: true, states: ["focused"], own: { height: "length", grow: "fraction" }, style: {} },
  { key: "appTicker", section: "APPS", label: "Ticker", follows: "statusChip", about: "a row of short news or scores moving across an app's screen; it stops while it's selected",
    box: BOX, text: true, style: {} },
  { key: "appChart", section: "APPS", label: "Chart", about: "the line a chart draws on an app's screen, in a list or table line and on a details page",
    own: { color: "color", width: "length" }, style: { color: "accent", width: 0.15 } },
  { key: "appOrigin", section: "APPS", label: "Where it's from", about: "the small page badge on an app's tile, its card and rows on Home, and its band when it was installed from a signed app file or an unsigned Developer-mode file; always drawn solid, its icon black or white, whichever reads",
    own: { color: "color", edge: "color", size: "length" }, style: { color: "boxBg", edge: "boxBorder", size: 1.7 } },
  { key: "appPageTitle", section: "APPS", label: "Page: title", follows: "heroTitle", about: "an article page's title on an app's screen",
    text: true, style: {} },
  { key: "appPageHeading", section: "APPS", label: "Page: heading", follows: "rowTitle", about: "a heading in an article page on an app's screen",
    text: true, style: {} },
  { key: "appPageText", section: "APPS", label: "Page: text", follows: "boxText", about: "an article page's text on an app's screen",
    text: true, style: {} },
  // Multiview (two to four channels at once)
  { key: "mvBackground", section: "MULTIVIEW", label: "Background", follows: "background", about: "behind Multiview's tiles (a picture, if you set one for Multiview, goes over it)",
    box: ["fill"], style: {} },
  { key: "mvTile", section: "MULTIVIEW", label: "Tile", about: "each channel's frame in Multiview, round its picture; current is the one with the sound",
    box: BOX, states: ["current"], style: { fill: "preview", border: { width: 0.08, color: "cellBorder" }, radius: 0.35 },
    stateStyle: { current: { border: { width: 0.2, color: "accent" } } } },
  { key: "mvStrip", section: "MULTIVIEW", label: "Name strip", about: "the band along a tile's bottom with its channel and what's on",
    box: ["fill", "border", "radius", "padding"], style: { fill: "scrim" } },
  { key: "mvName", section: "MULTIVIEW", label: "Channel name", follows: "posterTitle", about: "a tile's channel number and name",
    text: true, style: {} },
  { key: "mvShow", section: "MULTIVIEW", label: "What's on", follows: "posterSub", about: "what's on a tile's channel",
    text: true, style: {} },
  { key: "mvSound", section: "MULTIVIEW", label: "Sound badge", follows: "cardBadge", about: "SOUND on the tile you hear",
    box: ["fill", "border", "radius", "padding"], text: true, style: {} },
  // Recordings (the DVR)
  { key: "recordBadge", section: "RECORDINGS", label: "REC badge", follows: "liveBadge", about: "● REC with its stop time, on the channel banner and on a card that's recording",
    box: ["fill", "border", "radius", "padding"], text: true, style: {} },
  { key: "recordChoice", section: "RECORDINGS", label: "Record choice", follows: "menuRow", about: "Record, Save video, Stop recording and the stop times among the banner's choices; Record, Record every episode, Cancel recording and Stop recording this series among a show's choices in the guide; a recording's choices in its details; focused is the one picked (one that can't start now is dimmed, its reason under it)",
    box: BOX, text: true, states: ["focused"], own: { height: "length", grow: "fraction" }, style: {} },
  { key: "recordNote", section: "RECORDINGS", label: "Record note", follows: "posterSub", about: "the line under a Record choice: a second stream from the provider, too many recordings right now, too little space, the drive missing",
    text: true, style: {} },
  { key: "recordWarning", section: "RECORDINGS", label: "Two-stream warning", follows: "cardBadge", about: "the word above the banner while you watch one channel and record another from the same IPTV provider (two streams)",
    box: ["fill", "border", "radius", "padding"], text: true, style: {} },
  { key: "recordingCard", section: "RECORDINGS", label: "Card", follows: "posterCard", about: "a recording's card in Recordings and on Home; current is the one under the cursor",
    box: BOX, states: ["current"], style: {} },
  { key: "upcomingRecording", section: "RECORDINGS", label: "Upcoming card", follows: "posterCard", about: "a show scheduled to record, its card in Recordings (Upcoming, and a conflict); current is the one under the cursor",
    box: BOX, states: ["current"], style: {} },
  { key: "recordingState", section: "RECORDINGS", label: "State", about: "the word on a recording's card: Recording and Saving (recording), Scheduled (scheduled), Failed, Missed, Incomplete, Conflict and Drive missing (attention), Done",
    box: ["fill", "border", "radius", "padding"], text: true, states: ["recording", "scheduled", "attention"],
    style: { fill: "#cc000000", radius: 1, padding: 0.4, text: { color: "#ffffff", size: 0.7, weight: "bold", case: "none" } },
    stateStyle: { recording: { fill: "alert", text: { color: "#ffffff" } }, scheduled: { text: { color: "accent" } }, attention: { text: { color: "alert" } } } },
  { key: "recordDot", section: "RECORDINGS", label: "Cell mark", about: "● Recording, Scheduled or Conflict in a program cell whose show is recording or scheduled to; its color goes with the cell's text unless set, and recording is red",
    text: true, states: ["recording"], style: { text: { color: "inherit", size: 0.95, weight: "normal", case: "upper" } },
    stateStyle: { recording: { text: { color: "alert", weight: "bold" } } } },
  { key: "channelRec", section: "RECORDINGS", label: "Channel REC", about: "● REC beside a channel's name in the guide's channel column while it records",
    text: true, style: { text: { color: "alert", size: 0.8, weight: "bold", case: "upper" } } },
  { key: "mastheadRec", section: "RECORDINGS", label: "Masthead recording", about: "what's recording (● Recording CBS News, ● 2 recording) at the top of the guide, beside the clock",
    text: true, style: { text: { color: "alert", size: 0.95, weight: "bold", case: "none" } } },
  { key: "recordingProgress", section: "RECORDINGS", label: "Progress", follows: "vodProgress", about: "how far a recording is to its stop time, along its card's bottom",
    box: ["fill", "radius"], own: { track: "color", height: "length" }, style: { fill: "alert" } },
  { key: "liveChip", section: "RECORDINGS", label: "Pause and rewind chip", about: "Live, or how far behind live (2:15 behind live), on the channel banner while pause and rewind is on, and on the picture while it's behind; behind is that state",
    box: ["fill", "border", "radius", "padding"], text: true, states: ["behind"],
    style: { fill: "alert", radius: 1, padding: 0.4, text: { color: "#ffffff", font: "mono", size: 0.7, weight: "bold", case: "none" } },
    stateStyle: { behind: { fill: "#cc000000", text: { color: "#ffffff" } } } }
]

// How the guide is laid out. Lengths are in units.
var LAYOUT = [
  { key: "masthead", label: "Top of the guide", kind: ["title", "bar", "none"], value: "title", about: "across the top: the title, what's shown and the clock; bar: a thin status line (a badge, the filter, the sources, when the listings came, the clock); none" },
  { key: "list", label: "Channels as", kind: ["grid", "table", "board"], value: "grid", about: "grid: the time grid under the info area; table: a table of channels with a preview pane and the lineup of the channel under the cursor; board: a split-flap departures board, what's on and its status per channel" },
  { key: "titleDate", label: "Day after the title", kind: "bool", value: false, about: "the day after the title: UBER TV · SATURDAY 10" },
  { key: "footer", label: "Key hints as", kind: ["keys", "status"], value: "keys", about: "keys: the key hints along the bottom; status: a status line with a mode badge, the keys and the channel count" },
  { key: "info", label: "Info area", kind: "bool", value: true, about: "the info area: the preview box and the panel about the program under the cursor" },
  { key: "dividers", label: "Divider lines", kind: "bool", value: false, about: "thin lines between the info area, the grid and the key hints" },
  { key: "clock", label: "Clock", kind: ["masthead", "info", "none"], value: "masthead", about: "where the clock goes: the masthead, the info panel's top right (with the date), or nowhere" },
  { key: "hours24", label: "24-hour clock", kind: "bool", value: false, about: "clocks in 24 hours (20:13) instead of 8:13 PM" },
  { key: "preview", label: "Preview box", kind: ["left", "right", "none"], value: "left", about: "which side of the info panel the preview box is on, or none" },
  { key: "previewTag", label: "Preview tag", kind: "bool", value: false, about: "a label on the preview box: LIVE PREVIEW · CH 1" },
  { key: "infoHeight", label: "Info area height", step: 0.5, kind: "number", min: 6, max: 20, value: 12, about: "the info area's height" },
  { key: "infoProgress", label: "Progress bar", kind: "bool", value: false, about: "a bar under the program's times showing how far in it is" },
  { key: "upNext", label: "Up next", step: 1, kind: "number", min: 0, max: 4, step: 1, value: 1, about: "how many programs after it to list: 1 is a NEXT line, 2 or more a list under an Up next heading" },
  { key: "hours", label: "Hours across", kind: [1, 1.5, 2, 2.5, 3], value: 1.5, about: "how many hours the grid shows across" },
  { key: "rowHeight", label: "Row height", step: 0.1, kind: "number", min: 2, max: 8, value: 3.4, about: "each channel's row" },
  { key: "gap", label: "Gap between cells", step: 0.05, kind: "number", min: 0, max: 1.5, value: 0.17, about: "the space between cells" },
  { key: "channelWidth", label: "Channel column", step: 0.5, kind: "number", min: 6, max: 24, value: 11, about: "the channel column" },
  { key: "channelCell", label: "Channel cell", kind: ["stacked", "row"], value: "stacked", about: "stacked: the number over the name with logos on, beside it without; row: number, logo badge and name in a row" },
  { key: "timeBarHeight", label: "Time bar height", step: 0.1, kind: "number", min: 1.2, max: 4, value: 2.2, about: "the time bar" },
  { key: "bandHeight", label: "Band height", step: 0.1, kind: "number", min: 1, max: 4, value: 1.9, about: "a category's band" },
  { key: "tableWidth", label: "Table width", step: 0.02, kind: "number", min: 0.35, max: 0.75, value: 0.52, about: "table: the channel table's share of the width" },
  { key: "tableRowHeight", label: "Table rows", step: 0.05, kind: "number", min: 1.2, max: 4, value: 1.6, about: "table: each row" },
  { key: "columns", label: "Columns", kind: "columns", value: ["number", "name", "now", "left", "bar"], about: "table and board: the columns, in order: number, name, now, next (its title), nextAt (when it starts), left (time left), bar (how far in, table only), status (on air, live, ending, no signal), category" },
  { key: "boardRowHeight", label: "Board rows", step: 0.1, kind: "number", min: 1.6, max: 5, value: 2.4, about: "board: each row of flaps" },
  { key: "rail", label: "Nav rail", kind: ["always", "focus", "none"], value: "always", about: "the strip down the left with a way to every part: always (thin, with icons; ← at a screen's left edge widens it), focus (only when you go to it), none (the keys only)" },
  { key: "railWidth", label: "Nav rail width", step: 0.2, kind: "number", min: 3, max: 8, value: 4.4, about: "the thin rail's width" },
  { key: "railOpenWidth", label: "Nav rail, open", step: 0.5, kind: "number", min: 10, max: 30, value: 17, about: "the rail's width when it's open, with its labels" },
  { key: "homeHero", label: "Home: the big title", kind: "bool", value: true, about: "Home: the big title of what's selected, and the time, at the top" },
  { key: "homeTop", label: "Home: the top shows", kind: ["selected", "clock", "channel"], value: "selected", about: "Home: what the big title at the top tells: what's selected, a big clock, or what's on the channel you watched last (with homeHero on)" },
  { key: "homeClock", label: "Home: clock", kind: ["left", "right", "none"], value: "left", about: "Home: where the date and time go, top left or top right, or nowhere" },
  { key: "homeChips", label: "Home: status chips", kind: "bool", value: true, about: "Home: the little chips top right (the phone remote, how old the listings are)" },
  { key: "homeCardWidth", label: "Home: card width", step: 0.5, kind: "number", min: 8, max: 26, value: 14, about: "Home: each card's width (they're 16:9)" },
  { key: "homeTileHeight", label: "Home: tile height", step: 0.2, kind: "number", min: 4, max: 14, value: 7.6, about: "Home: the tiles' height" },
  { key: "libraryPosterWidth", label: "Library: poster width", step: 0.2, kind: "number", min: 5, max: 16, value: 8.6, about: "the library: each poster's width (they're 2:3)" },
  { key: "libraryThumbWidth", label: "Library: picture width", step: 0.5, kind: "number", min: 9, max: 26, value: 15.5, about: "the library: each video's picture width (16:9)" },
  { key: "librarySquareWidth", label: "Library: square width", step: 0.2, kind: "number", min: 5, max: 16, value: 10, about: "apps' square, logo and round pictures (albums, teams, people): each card's width" }
]

var LAYOUT_BY_KEY = {}
for (var lk = 0; lk < LAYOUT.length; lk++) LAYOUT_BY_KEY[LAYOUT[lk].key] = LAYOUT[lk]

function checkLayout(given) {
  var out = {}
  var ignored = []
  if (given === undefined) return { layout: out, ignored: ignored }
  if (given === null || typeof given !== "object" || Array.isArray(given)) return { layout: out, ignored: ["layout (an object)"] }
  for (var k in given) {
    var spec = LAYOUT_BY_KEY[k]
    var v = given[k]
    if (!spec) { ignored.push("layout." + k + " (no such setting)"); continue }
    if (spec.kind === "bool") { if (typeof v === "boolean") out[k] = v; else ignored.push("layout." + k + " (true or false)") }
    else if (spec.kind === "columns") {
      var known = ["number", "name", "now", "next", "nextAt", "left", "bar", "status", "category"]
      var cols = Array.isArray(v) ? v.filter(function(c, i) { return known.indexOf(c) >= 0 && v.indexOf(c) === i }) : []
      if (cols.length) out[k] = cols
      if (!Array.isArray(v) || cols.length !== v.length) ignored.push("layout." + k + " (a list of: " + known.join(", ") + ")")
    }
    else if (Array.isArray(spec.kind)) { if (spec.kind.indexOf(v) >= 0) out[k] = v; else ignored.push("layout." + k + " (" + spec.kind.join(", ") + ")") }
    else if (typeof v === "number" && isFinite(v)) {
      var n = Math.max(spec.min, Math.min(spec.max, v))
      out[k] = k === "upNext" ? Math.round(n) : Math.round(n * 1000) / 1000
    } else ignored.push("layout." + k + " (" + spec.min + " to " + spec.max + ")")
  }
  return { layout: out, ignored: ignored }
}

// Retro's layout, then the theme's, then yours
function effectiveLayout(themeLayout, yourLayout) {
  var out = {}
  for (var i = 0; i < LAYOUT.length; i++) {
    var k = LAYOUT[i].key
    out[k] = yourLayout && yourLayout[k] !== undefined ? yourLayout[k] : themeLayout && themeLayout[k] !== undefined ? themeLayout[k] : LAYOUT[i].value
  }
  return out
}

var BY_KEY = {}
for (var e = 0; e < ELEMENTS.length; e++) BY_KEY[ELEMENTS[e].key] = ELEMENTS[e]

// Elements whose box would be drawn hundreds of times: no shadows there,
// except in a state only one of them is in at a time.
var NO_SHADOW = { channelCell: true, programCell: true, band: true, timeBar: true, listRow: true, appCard: true, recordingCard: true, upcomingRecording: true }
var ONE_AT_A_TIME = ["selected", "current", "focused"]

function isObject(v) { return v !== null && typeof v === "object" && !Array.isArray(v) }

function copy(v) { return v === undefined ? undefined : JSON.parse(JSON.stringify(v)) }

// b over a, objects merged a level at a time (fill gradients and radius
// lists are replaced whole)
function merge(a, b) {
  if (!isObject(b)) return b === undefined ? copy(a) : copy(b)
  if (!isObject(a)) return copy(b)
  var out = copy(a)
  for (var k in b) {
    if (k === "fill" || k === "radius") out[k] = copy(b[k])
    else out[k] = isObject(b[k]) && isObject(out[k]) ? merge(out[k], b[k]) : copy(b[k])
  }
  return out
}

// ---- checking ------------------------------------------------------------

function isHex(v) { return typeof v === "string" && /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(v) }

function isOmarchy(v) { return typeof v === "string" && /^omarchy\.[a-z][a-z0-9_]{0,40}$/.test(v) }

function checkColor(v, slots) {
  if (typeof v !== "string") return undefined
  var t = v.trim()
  if (isHex(t)) return t.toLowerCase()
  if (isOmarchy(t)) return t
  if (t === "none" || t === "transparent") return "none"
  if (slots.indexOf(t) >= 0) return t
  return undefined
}

function checkLength(v, lo, hi) {
  if (typeof v === "number" && isFinite(v)) return Math.round(Math.max(lo, Math.min(hi, v)) * 1000) / 1000
  if (typeof v === "string") {
    var m = v.trim().match(/^(-?\d+(\.\d+)?)px$/)
    if (m) return Math.max(lo * 20, Math.min(hi * 20, Number(m[1]))) + "px"
  }
  return undefined
}

function checkFill(v, slots) {
  if (isObject(v)) {
    var from = checkColor(v.from, slots)
    var to = checkColor(v.to, slots)
    if (from === undefined || to === undefined) return undefined
    var dir = ["down", "up", "right", "left"].indexOf(v.direction) >= 0 ? v.direction : "down"
    return { from: from, to: to, direction: dir }
  }
  return checkColor(v, slots)
}

// A role, a family, or a list of families: the first one installed
function checkFont(v, families) {
  if (Array.isArray(v)) {
    for (var c = 0; c < v.length && c < 8; c++) {
      var f = checkFont(v[c], families)
      if (f !== undefined && FONT_ROLES.indexOf(f) < 0) return f
    }
    return undefined
  }
  if (typeof v !== "string" || !v.trim()) return undefined
  var t = v.trim()
  if (FONT_ROLES.indexOf(t) >= 0) return t
  if (!families) return t.slice(0, 80)
  var lower = t.toLowerCase()
  if (["monospace", "sans-serif", "sans", "serif"].indexOf(lower) >= 0) return t
  for (var i = 0; i < families.length; i++) if (families[i].toLowerCase() === lower) return families[i]
  return undefined
}

function checkPath(v) {
  if (typeof v !== "string") return undefined
  var t = v.trim()
  return t.length > 0 && t.length <= 4000 && /^[MmLlHhVvCcSsQqTtAaZz0-9eE.,\s+-]+$/.test(t) && /^[Mm]/.test(t) ? t : undefined
}

// One property of a box: { value } or { error }
function checkBoxProp(name, v, slots, elementKey, state) {
  switch (name) {
  case "fill":
    var f = checkFill(v, slots)
    return f === undefined ? { error: "a color (#rrggbb, #aarrggbb, a slot name or none) or {from, to, direction}" } : { value: f }
  case "border":
    if (v === "none") return { value: { width: 0 } }
    if (!isObject(v)) return { error: "{width, color, sides} or none" }
    var b = {}
    var bad = []
    for (var bk in v) {
      if (bk === "width") { var w = checkLength(v.width, 0, 2); if (w === undefined) bad.push("width"); else b.width = w }
      else if (bk === "color") { var c = checkColor(v.color, slots); if (c === undefined) bad.push("color"); else b.color = c }
      else if (bk === "sides") {
        var sides = typeof v.sides === "string" ? [v.sides] : v.sides
        if (Array.isArray(sides) && sides.length && sides.every(function(s) { return ["all", "top", "bottom", "left", "right"].indexOf(s) >= 0 })) b.sides = sides.indexOf("all") >= 0 ? "all" : sides
        else bad.push("sides (all, or some of top, bottom, left, right)")
      } else bad.push(bk)
    }
    return bad.length ? { value: b, error: "border." + bad.join(", border.") } : { value: b }
  case "radius":
    if (Array.isArray(v) && v.length === 4) {
      var corners = v.map(function(x) { return checkLength(x, 0, 30) })
      return corners.some(function(x) { return x === undefined }) ? { error: "a length, or four: [top left, top right, bottom right, bottom left]" } : { value: corners }
    }
    var r = checkLength(v, 0, 30)
    return r === undefined ? { error: "a length, or four: [top left, top right, bottom right, bottom left]" } : { value: r }
  case "shape":
    return SHAPES.indexOf(v) >= 0 ? { value: v } : { error: SHAPES.join(", ") }
  case "slant":
    var sl = checkLength(v, -10, 10)
    return sl === undefined ? { error: "a length: how far the ends lean (or the point sticks out), -10 to 10" } : { value: sl }
  case "path":
    var p = checkPath(v)
    return p === undefined ? { error: "an SVG path (M, L, C, Q, A, Z…) drawn in a 100 by 100 box" } : { value: p }
  case "shadow":
    if (v === "none") return { value: "none" }
    if (NO_SHADOW[elementKey] && ONE_AT_A_TIME.indexOf(state) < 0)
      return { error: "not on every " + elementKey + ": it's drawn too many times (the selected or current one can have one)" }
    if (!isObject(v)) return { error: "{color, blur, x, y} or none" }
    var sh = { color: checkColor(v.color, slots) || "#99000000", blur: checkLength(v.blur, 0, 6), x: checkLength(v.x, -6, 6), y: checkLength(v.y, -6, 6) }
    if (sh.blur === undefined) sh.blur = 1
    if (sh.x === undefined) sh.x = 0
    if (sh.y === undefined) sh.y = 0.3
    return { value: sh }
  case "padding":
    var pd = checkLength(v, 0, 10)
    return pd === undefined ? { error: "a length, 0 to 10" } : { value: pd }
  }
  return { error: "unknown" }
}

function checkTextProp(name, v, slots, families) {
  switch (name) {
  case "color":
    var c = checkColor(v, slots)
    return c === undefined ? { error: "#rrggbb, #aarrggbb, a slot name or none" } : { value: c }
  case "font":
    var f = checkFont(v, families)
    return f === undefined ? { error: "body, display, mono, an installed font family (fonts lists them), or a list of families (the first installed is used)" } : { value: f }
  case "size":
    var s = checkLength(v, 0.2, 12)
    return s === undefined || typeof s !== "number" ? { error: "a size in units, 0.2 to 12" } : { value: s }
  case "weight":
    if (typeof v === "number" && v >= 100 && v <= 900) return { value: Math.round(v / 100) * 100 }
    return WEIGHTS[v] ? { value: v } : { error: Object.keys(WEIGHTS).join(", ") + ", or 100 to 900" }
  case "case":
    return CASES.indexOf(v) >= 0 ? { value: v } : { error: CASES.join(", ") }
  case "letterSpacing":
    var ls = checkLength(v, -0.5, 2)
    return ls === undefined || typeof ls !== "number" ? { error: "units, -0.5 to 2" } : { value: ls }
  case "italic":
    return typeof v === "boolean" ? { value: v } : { error: "true or false" }
  }
  return { error: "unknown" }
}

function checkOwnProp(kind, v, slots) {
  if (Array.isArray(kind)) return kind.indexOf(v) >= 0 ? { value: v } : { error: kind.join(", ") }
  if (kind === "color") { var c = checkColor(v, slots); return c === undefined ? { error: "a color" } : { value: c } }
  if (kind === "length") { var l = checkLength(v, 0, 40); return l === undefined ? { error: "a length" } : { value: l } }
  if (kind === "fraction") return typeof v === "number" && v >= 0 && v <= 1 ? { value: Math.round(v * 1000) / 1000 } : { error: "0 to 1" }
  if (kind === "width") return v === "full" ? { value: v } : typeof v === "number" && v >= 0.2 && v <= 1 ? { value: v } : { error: "full, or a share of the screen's width, 0.2 to 1" }
  return { error: "unknown" }
}

// One element's style as given, checked. Text properties may come under
// "text" or, for a text-only element, on their own. Returns { style, ignored }.
function checkStyle(key, given, slots, families, state) {
  var el = BY_KEY[key]
  var ignored = []
  var style = {}
  if (!el) return { style: style, ignored: [key + " (no such element)"] }
  if (!isObject(given)) return { style: style, ignored: [key + " (an object of properties)"] }
  var boxProps = el.box || []
  var own = el.own || {}
  var text = isObject(given.text) ? copy(given.text) : {}
  for (var name in given) {
    var v = given[name]
    if (name === "text") continue
    if (el.text && !el.box && TEXT.indexOf(name) >= 0 && !own[name]) { text[name] = v; continue }
    var res = own[name] ? checkOwnProp(own[name], v, slots)
            : boxProps.indexOf(name) >= 0 ? checkBoxProp(name, v, slots, key, state)
            : { error: TEXT.indexOf(name) >= 0 && el.text ? "goes under text" : "not a property of " + key }
    if (res.value !== undefined) style[name] = res.value
    if (res.error) ignored.push(key + "." + name + " (" + res.error + ")")
  }
  if (Object.keys(text).length) {
    if (!el.text) ignored.push(key + ".text (" + key + " has no text)")
    else {
      var t = {}
      for (var tn in text) {
        var tr = TEXT.indexOf(tn) >= 0 ? checkTextProp(tn, text[tn], slots, families) : { error: "not a text property" }
        if (tr.value !== undefined) t[tn] = tr.value
        if (tr.error) ignored.push(key + ".text." + tn + " (" + tr.error + ")")
      }
      if (Object.keys(t).length) style.text = t
    }
  }
  return { style: style, ignored: ignored }
}

// A theme's (or your) elements: { "programCell": {...}, "programCell:selected": {...} }
function checkElements(given, slots, families) {
  var out = {}
  var ignored = []
  if (!isObject(given)) return { elements: out, ignored: given === undefined ? [] : ["elements (an object: element name to its style)"] }
  for (var name in given) {
    var parts = name.split(":")
    var el = BY_KEY[parts[0]]
    if (!el) { ignored.push("elements." + name + " (no such element; elements lists them)"); continue }
    if (parts.length > 1 && (parts.length > 2 || (el.states || []).indexOf(parts[1]) < 0)) {
      ignored.push("elements." + name + " (" + (el.states ? "states: " + el.states.join(", ") : "no states") + ")")
      continue
    }
    var res = checkStyle(parts[0], given[name], slots, families, parts[1])
    for (var i = 0; i < res.ignored.length; i++) ignored.push("elements." + res.ignored[i].replace(parts[0], name))
    if (Object.keys(res.style).length) out[name] = res.style
  }
  return { elements: out, ignored: ignored }
}

function checkFonts(given, families) {
  var out = {}
  var ignored = []
  if (!isObject(given)) return { fonts: out, ignored: given === undefined ? [] : ["fonts ({body, display, mono})"] }
  for (var role in given) {
    if (FONT_ROLES.indexOf(role) < 0) { ignored.push("fonts." + role + " (body, display or mono)"); continue }
    var f = checkFont(given[role], families)
    if (f === undefined || FONT_ROLES.indexOf(f) >= 0) ignored.push("fonts." + role + " (\"" + given[role] + "\" isn't installed; fonts lists what is)")
    else out[role] = f
  }
  return { fonts: out, ignored: ignored }
}

// A theme (checked) with something in it to use: colors, elements, fonts,
// layout, or the look it gives every app's screen
function themeUsable(theme) {
  var some = function(o) { return isObject(o) && Object.keys(o).length > 0 }
  return !!theme && (some(theme.colors) || some(theme.elements) || some(theme.fonts) || some(theme.layout) || some(theme.apps))
}

// ---- a theme's pictures ----------------------------------------------------
// A picture a theme names: read from its folder on disk, only a plain name
// there (no path, nothing hidden); given to be saved, also a picture's full
// path (the helper checks it and copies it in under a new name). "" if it's
// neither.
function themePicture(v, fromDisk) {
  if (typeof v !== "string") return ""
  if (/^[^\/\\.][^\/\\]*\.(jpe?g|png|webp)$/i.test(v)) return v
  return !fromDisk && /^\/.+\.(jpe?g|png|webp)$/i.test(v) ? v : ""
}

// ---- the picture behind the guide, and where it came from ------------------

// Where it came from: "theme" (put on with a theme, or a reset to it),
// "user" (picked in the style panel, or given to the background command),
// or "" (not known: kept before this was). Anything else is "".
function bgProvenance(v) { return v === "theme" || v === "user" ? v : "" }
// An app's screen keeps the guide's picture under the 30% shade floor unless
// it's surely yours: one of unknown origin gets the floor until it's picked
// again (your wallpaper isn't an "image", and goes as you set it)
function bgFloored(mode, image, from) { return mode === "image" && !!image && from !== "user" }
// The background a theme gives when it's put on or put back (a reset of the
// look, or of the Background row alone): its mode, and its own picture
// (resolved in its folder) as the theme's. With no picture of its own, the
// one there now stays as it was (yours, if it was), and "image" with no
// picture at all is "none". current: { image, from }.
function themeBackground(theme, current) {
  var bg = theme && isObject(theme.background) ? theme.background : {}
  var mode = bg.mode !== undefined ? bg.mode : "none"
  var out = { mode: mode, image: current.image || "", from: bgProvenance(current.from) }
  if (mode === "image" && typeof bg.image === "string" && bg.image !== "") {
    out.image = bg.image.charAt(0) === "/" ? bg.image : theme.dir + "/" + bg.image
    out.from = "theme"
  }
  if (out.mode === "image" && !out.image) out.mode = "none"
  return out
}

// ---- resolving -----------------------------------------------------------

// The style of every element and state, from Retro's, the theme's and
// yours: { "programCell": {...}, "programCell:selected": {...} }, unresolved.
// An element that follows another (its twin, one hop: a twin never follows)
// starts from it, state by state: its base is its twin's, with its own
// (Retro's, the theme's, yours) on top; each state is its twin's state of
// that name (or its twin's base), then its own base, then its own state.
// Twins are worked out first. The safety rules come after: an element
// drawn many times (NO_SHADOW) loses a shadow its base inherited, while a
// state only one is in at a time keeps one.
function effective(themeElements, yourElements) {
  var t = themeElements || {}
  var y = yourElements || {}
  var out = {}
  var order = ELEMENTS.filter(function(el) { return !el.follows }).concat(ELEMENTS.filter(function(el) { return !!el.follows }))
  for (var i = 0; i < order.length; i++) {
    var el = order[i]
    var own = merge(merge(el.style, t[el.key]), y[el.key])
    var twin = el.follows && BY_KEY[el.follows] && !BY_KEY[el.follows].follows ? el.follows : ""
    var base = twin ? merge(out[twin], own) : own
    if (NO_SHADOW[el.key] && isObject(base) && base.shadow !== undefined) delete base.shadow
    out[el.key] = base
    var states = el.states || []
    for (var s = 0; s < states.length; s++) {
      var name = el.key + ":" + states[s]
      var mine = merge(merge((el.stateStyle || {})[states[s]], t[name]), y[name])
      out[name] = twin ? merge(merge(out[twin + ":" + states[s]] !== undefined ? out[twin + ":" + states[s]] : out[twin], own), mine)
                       : merge(base, mine)
    }
  }
  return out
}

// The Omarchy theme's colors.toml, as { name: "#hex" }
function parseOmarchy(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([a-z][a-z0-9_]*)\s*=\s*"(#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?)"/)
    if (m) out[m[1]] = m[2].toLowerCase()
  }
  return out
}

function colorOf(v, colors, omarchy) {
  if (v === "none" || v === undefined || v === null) return "transparent"
  if (v === "auto" || v === "inherit") return v
  if (v.charAt(0) === "#") return v
  if (isOmarchy(v)) return (omarchy || {})[v.slice(8)] || "transparent"
  return String(colors[v] || "transparent")
}

// Colors as colors and fonts as families, ready to draw: one entry per
// element and state.
function resolve(themeElements, yourElements, colors, fonts, omarchy) {
  var eff = effective(themeElements, yourElements)
  var out = {}
  for (var name in eff) {
    var s = eff[name]
    var r = copy(s)
    if (s.fill !== undefined) {
      r.fill = isObject(s.fill) ? { from: colorOf(s.fill.from, colors, omarchy), to: colorOf(s.fill.to, colors, omarchy), direction: s.fill.direction }
                                : colorOf(s.fill, colors, omarchy)
    }
    if (s.border) {
      r.border = { width: s.border.width === undefined ? 0 : s.border.width, color: colorOf(s.border.color, colors, omarchy), sides: s.border.sides || "all" }
      if (r.border.color === "transparent") r.border.width = 0
    }
    if (isObject(s.shadow)) r.shadow = { color: colorOf(s.shadow.color, colors, omarchy), blur: s.shadow.blur, x: s.shadow.x, y: s.shadow.y }
    else delete r.shadow
    var own = (BY_KEY[name.split(":")[0]] || {}).own || {}
    for (var o in own) if (own[o] === "color" && s[o] !== undefined) r[o] = colorOf(s[o], colors, omarchy)
    if (s.text) {
      r.text.color = colorOf(s.text.color, colors, omarchy)
      var role = s.text.font || "body"
      r.text.font = FONT_ROLES.indexOf(role) >= 0 ? fonts[role] : role
      r.text.weight = typeof s.text.weight === "number" ? s.text.weight : WEIGHTS[s.text.weight || "normal"]
      r.text.case = s.text.case || "none"
      r.text.letterSpacing = s.text.letterSpacing || 0
      r.text.italic = s.text.italic === true
    }
    out[name] = r
  }
  return out
}

// A length in pixels: units times unit, or "Npx" as is
function px(v, unit) {
  if (typeof v === "number") return v * unit
  if (typeof v === "string") return parseFloat(v) || 0
  return 0
}

// ---- the style panel -------------------------------------------------------

var OWN_LABELS = { height: "Height", margin: "Margin", width: "Width", align: "Side", track: "Track", edge: "Edge",
                   depth: "Depth", radius: "Corners", seam: "Seam", aspect: "Flap width", gap: "Gap", style: "Style", color: "Color" }

// What the style panel can change on an element (or a state of it), in
// order: { path, kind, label, step, min, max, options }
function propList(key, state) {
  var el = BY_KEY[key]
  if (!el) return []
  var box = el.box || []
  var own = el.own || {}
  var out = []
  var has = function(p) { return box.indexOf(p) >= 0 }
  if (has("fill")) out.push({ path: "fill", kind: "color", label: "Fill" })
  if (has("border")) {
    out.push({ path: "border.width", kind: "length", label: "Border", step: 0.02, min: 0, max: 2 })
    out.push({ path: "border.color", kind: "color", label: "Border color" })
  }
  if (has("radius") && !own.radius) out.push({ path: "radius", kind: "length", label: "Corners", step: 0.05, min: 0, max: 30 })
  if (has("shape")) out.push({ path: "shape", kind: "enum", label: "Shape", options: ["rect", "pill", "slant", "arrow", "chevron"] })
  if (has("slant")) out.push({ path: "slant", kind: "length", label: "Slant or point", step: 0.1, min: -10, max: 10 })
  if (has("shadow") && (!NO_SHADOW[key] || ONE_AT_A_TIME.indexOf(state) >= 0)) {
    out.push({ path: "shadow", kind: "shadow", label: "Shadow" })
    out.push({ path: "shadow.blur", kind: "length", label: "Shadow blur", step: 0.1, min: 0, max: 6 })
    out.push({ path: "shadow.y", kind: "length", label: "Shadow drop", step: 0.05, min: -6, max: 6 })
    out.push({ path: "shadow.color", kind: "color", label: "Shadow color" })
  }
  if (has("padding")) out.push({ path: "padding", kind: "length", label: "Padding", step: 0.1, min: 0, max: 10 })
  for (var o in own) {
    var k = own[o]
    var row = { path: o, label: OWN_LABELS[o] || o }
    if (Array.isArray(k)) { row.kind = "enum"; row.options = k }
    else if (k === "color") row.kind = "color"
    else if (k === "length") { row.kind = "length"; row.step = 0.1; row.min = 0; row.max = 40 }
    else if (k === "fraction") { row.kind = "fraction"; row.step = 0.02 }
    else row.kind = k
    out.push(row)
  }
  if (el.text) {
    out.push({ path: "text.color", kind: "color", label: "Text color" })
    out.push({ path: "text.font", kind: "font", label: "Font" })
    out.push({ path: "text.size", kind: "length", label: "Text size", step: 0.05, min: 0.2, max: 12 })
    out.push({ path: "text.weight", kind: "enum", label: "Weight", options: Object.keys(WEIGHTS) })
    out.push({ path: "text.case", kind: "enum", label: "Capitals", options: CASES })
    out.push({ path: "text.letterSpacing", kind: "length", label: "Letter spacing", step: 0.02, min: -0.5, max: 2 })
    out.push({ path: "text.italic", kind: "bool", label: "Italic" })
  }
  return out
}

function getPath(obj, path) {
  var parts = path.split(".")
  var v = obj
  for (var i = 0; i < parts.length; i++) {
    if (!isObject(v)) return undefined
    v = v[parts[i]]
  }
  return v
}

// A copy of obj with path set (value undefined: taken out, and empty
// objects it leaves with it)
function withPath(obj, path, value) {
  var out = copy(obj) || {}
  var parts = path.split(".")
  var at = out
  for (var i = 0; i < parts.length - 1; i++) {
    if (!isObject(at[parts[i]])) {
      if (value === undefined) return out
      at[parts[i]] = {}
    }
    at = at[parts[i]]
  }
  if (value === undefined) delete at[parts[parts.length - 1]]
  else at[parts[parts.length - 1]] = value
  if (value === undefined && parts.length > 1 && isObject(out[parts[0]]) && !Object.keys(out[parts[0]]).length) delete out[parts[0]]
  return out
}

// Installed families worth offering: one per family, without symbol,
// emoji and per-script fonts
function usableFonts(families) {
  var seen = {}
  var out = []
  for (var i = 0; i < families.length; i++) {
    var f = families[i]
    var l = f.toLowerCase()
    if (seen[l]) continue
    seen[l] = true
    if (/emoji|awesome|symbol|dingbat|cursor|d050000l|fangsong|^noto (sans|serif|kufi|naskh|nastaliq|rashi|music)\b(?! mono$)./i.test(f)
        && !/^noto (sans|serif)( mono)?$/i.test(f)) continue
    out.push(f)
  }
  return out.sort(function(a, b) { return a.toLowerCase() < b.toLowerCase() ? -1 : 1 })
}

// For the elements command: everything about one element
function describe(key, themeElements, yourElements) {
  var el = BY_KEY[key]
  if (!el) return null
  var names = [key].concat((el.states || []).map(function(s) { return key + ":" + s }))
  var eff = effective(themeElements, yourElements)
  var props = (el.box || []).slice()
  for (var o in (el.own || {})) props.push(o)
  if (el.text) props.push("text: {" + TEXT.join(", ") + "}")
  var out = { element: key, section: el.section, label: el.label, about: el.about, properties: props, states: el.states || [],
              retro: {}, theme: {}, yours: {}, now: {} }
  if (el.follows) out.follows = el.follows
  for (var i = 0; i < names.length; i++) {
    var n = names[i]
    var retro = i === 0 ? el.style : (el.stateStyle || {})[n.split(":")[1]]
    if (retro) out.retro[n] = retro
    if ((themeElements || {})[n]) out.theme[n] = themeElements[n]
    if ((yourElements || {})[n]) out.yours[n] = yourElements[n]
    out.now[n] = eff[n]
  }
  return out
}
