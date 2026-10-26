import QtQuick

// Tablet mode's keyboard (Guide.qml): up from the bottom while a text field
// has the keys, or Search takes what's typed, in the theme's key colors.
// Letters, then numbers and the signs of web addresses (?123, ABC), Shift for
// one capital, Paste, ⌫, Hide, and Search (in Search) or Done: what Enter does
// in that field (its enterKey(), or its accepted). Plain ASCII; nothing typed
// is kept or logged here.
Item {
  id: kb

  required property var guide
  property Item screen: null          // where a field is measured (the guide's screen)

  // what it types into: the text field with the keys, or Search
  readonly property var field: {
    var f = Window.activeFocusItem
    return f && typeof f.insert === "function" && typeof f.remove === "function" && f.visible ? f : null
  }
  readonly property bool searching: guide.screen === "search" && !guide.searchInResults && !guide.watching && guide.dialog === ""
  readonly property bool wanted: guide.touchMode && (field !== null || searching)
  property bool hidden: false         // Hide: until another field, or the same one tapped again
  property bool numbers: false        // ?123
  property bool shift: false
  readonly property bool up: wanted && !hidden

  onFieldChanged: { hidden = false; numbers = false; shift = false }
  // a finger let go at this point of the screen: on the field it was hidden
  // from, it comes back
  function tappedAt(at) {
    if (!hidden || !field || !screen) return
    var p = field.mapFromItem(screen, at.x, at.y)
    if (p.x >= 0 && p.y >= 0 && p.x <= field.width && p.y <= field.height) hidden = false
  }
  onSearchingChanged: if (searching) hidden = false

  readonly property real f: guide.fingerPx
  readonly property real pad: Math.round(f * 0.22)
  readonly property real gap: Math.round(f * 0.16)
  readonly property real keyH: Math.round(f * 1.05)
  // one key's width: a row is 11.5 keys wide with its gaps (a wide key
  // takes the gaps it spans too)
  readonly property real unit: Math.max(f * 0.5, (width - pad * 2 - gap * 10.5) / 11.5)

  readonly property var face: guide.look.keycap || ({})
  readonly property color faceColor: typeof face.fill === "string" ? face.fill : guide.colors.keyFace
  readonly property color faceInk: face.text && face.text.color ? face.text.color : guide.colors.keyText
  readonly property color edgeColor: face.edge || guide.colors.keyEdge

  visible: up
  height: up ? rows.implicitHeight + pad * 2 : 0

  // ---- typing ----
  function type(ch) {
    var c = shift ? ch.toUpperCase() : ch
    shift = false
    if (field) {
      if (field.readOnly) return
      if (field.selectedText && field.selectedText.length) field.remove(field.selectionStart, field.selectionEnd)
      if (typeof field.maximumLength === "number" && field.length >= field.maximumLength) return
      field.insert(field.cursorPosition, c)
      edited()
    } else if (searching) guide.searchType(c)
  }
  // what the field does when you type in it (its textEdited) runs as for keys
  function edited() { if (field && typeof field.textEdited === "function") field.textEdited() }
  function backspace() {
    if (field) {
      if (field.readOnly) return
      if (field.selectedText && field.selectedText.length) field.remove(field.selectionStart, field.selectionEnd)
      else if (field.cursorPosition > 0) field.remove(field.cursorPosition - 1, field.cursorPosition)
      edited()
    } else if (searching) guide.searchBackspace()
  }
  function paste() {
    if (field) { if (!field.readOnly) { field.paste(); edited() } return }
    if (!searching) return
    sink.text = ""
    sink.paste()
    var t = sink.text
    sink.text = ""
    for (var i = 0; i < t.length && i < 200; i++) {
      var ch = t.charAt(i)
      if (ch >= " " && ch !== "\u007f") guide.searchType(ch)
    }
  }
  function enter() {
    if (field) {
      if (typeof field.enterKey === "function") field.enterKey()
      else if (typeof field.accepted === "function") field.accepted()
      else kb.hidden = true
    } else if (searching) guide.searchEnter()
  }

  // Paste in Search goes through this unseen field (Qt reads the clipboard here)
  TextInput { id: sink; visible: false }

  // the layouts, fixed: a key is [shown, what it does, width in keys]; Enter's
  // words follow Search (both layouts are made once, so changing between
  // them never remakes a key under a finger)
  readonly property var letters: [
    [["q"], ["w"], ["e"], ["r"], ["t"], ["y"], ["u"], ["i"], ["o"], ["p"], ["⌫", "back", 1.5]],
    [["", "space0", 0.5], ["a"], ["s"], ["d"], ["f"], ["g"], ["h"], ["j"], ["k"], ["l"], ["Done", "enter", 2]],
    [["⇧", "shift", 1.5], ["z"], ["x"], ["c"], ["v"], ["b"], ["n"], ["m"], ["."], ["/"], ["-"]],
    [["?123", "numbers", 1.5], ["Paste", "paste", 2], [" ", "space", 6.5], ["Hide", "hide", 1.5]]
  ]
  readonly property var signs: [
    [["1"], ["2"], ["3"], ["4"], ["5"], ["6"], ["7"], ["8"], ["9"], ["0"], ["⌫", "back", 1.5]],
    [["", "space0", 0.5], ["@"], ["#"], ["&"], ["_"], ["-"], ["+"], ["("], [")"], [":"], ["Done", "enter", 2]],
    [["/", "", 1.5], ["."], ["'"], ["\""], [","], [";"], ["!"], ["?"], ["%"], ["="], ["~"]],
    [["ABC", "letters", 1.5], ["Paste", "paste", 2], [" ", "space", 6.5], ["Hide", "hide", 1.5]]
  ]

  function press(k) {
    var what = k[1] || ""
    if (what === "") kb.type(k[0])
    else if (what === "space") kb.type(" ")
    else if (what === "back") kb.backspace()
    else if (what === "enter") kb.enter()
    else if (what === "shift") kb.shift = !kb.shift
    else if (what === "numbers") kb.numbers = true
    else if (what === "letters") kb.numbers = false
    else if (what === "paste") kb.paste()
    else if (what === "hide") kb.hidden = true
  }

  // one key: its face over a lower edge, its words, a tap (or a screen
  // reader's press); a layout's keys are named by it (tests find them)
  component Key: Item {
    id: key
    required property var modelData
    property string layout: "key"
    readonly property string what: modelData[1] || ""
    readonly property bool special: what !== "" && what !== "space"
    readonly property bool blank: what === "space0"
    readonly property bool lit: what === "enter" || (what === "shift" && kb.shift)
    readonly property string shown: what === "enter" ? (kb.searching ? "Search" : "Done")
                                     : what === "" && kb.shift ? modelData[0].toUpperCase() : modelData[0]
    objectName: layout + ":" + (what !== "" ? what : modelData[0])
    width: Math.round(kb.unit * (modelData[2] || 1) + kb.gap * ((modelData[2] || 1) - 1))
    height: kb.keyH
    Accessible.role: blank ? Accessible.NoRole : Accessible.Button
    Accessible.name: what === "back" ? "Backspace" : what === "shift" ? "Shift" : what === "space" ? "Space" : shown
    Accessible.onPressAction: if (!key.blank) kb.press(key.modelData)

    Rectangle {
      visible: !key.blank
      anchors.fill: parent
      anchors.topMargin: Math.round(kb.f * 0.06)
      radius: Math.round(kb.f * 0.18)
      color: key.lit ? Qt.darker(kb.guide.marquee, 1.4) : key.special ? Qt.darker(kb.edgeColor, 1.3) : kb.edgeColor
    }
    Rectangle {
      visible: !key.blank
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: parent.height - Math.round(kb.f * 0.06)
      radius: Math.round(kb.f * 0.18)
      readonly property color fill: key.lit ? kb.guide.marquee : key.special ? kb.edgeColor : kb.faceColor
      color: tap.pressed ? Qt.darker(fill, 1.2) : fill
      Text {
        anchors.centerIn: parent
        text: key.shown
        textFormat: Text.PlainText
        color: key.lit ? kb.guide.inkOn(kb.guide.marquee) : kb.faceInk
        font.family: kb.guide.fonts.body
        font.pixelSize: Math.round(kb.f * (key.special && key.shown.length > 1 ? 0.3 : 0.42))
        font.weight: key.special ? Font.DemiBold : Font.Medium
      }
    }
    TapHandler {
      id: tap
      enabled: !key.blank
      gesturePolicy: TapHandler.ReleaseWithinBounds
      onTapped: kb.press(key.modelData)
    }
  }

  Rectangle {
    anchors.fill: parent
    color: kb.guide.colors.boxBg
    border.color: kb.guide.colors.cellBorder
    border.width: Math.max(1, Math.round(kb.f * 0.02))
  }
  // a tap between keys stays here (nothing under the keyboard gets it)
  MouseArea { anchors.fill: parent }

  // letters, and numbers with the signs (?123): both made once
  Column {
    id: rows
    visible: !kb.numbers
    x: kb.pad
    y: kb.pad
    spacing: kb.gap
    Repeater {
      model: kb.letters
      delegate: Row {
        required property var modelData
        spacing: kb.gap
        Repeater { model: modelData; delegate: Key { layout: "key" } }
      }
    }
  }
  Column {
    visible: kb.numbers
    x: kb.pad
    y: kb.pad
    spacing: kb.gap
    Repeater {
      model: kb.signs
      delegate: Row {
        required property var modelData
        spacing: kb.gap
        Repeater { model: modelData; delegate: Key { layout: "sign" } }
      }
    }
  }
}
