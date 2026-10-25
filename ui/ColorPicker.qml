import QtQuick

// A color picker: a saturation/brightness square, a hue strip, a
// transparency strip (when the slot allows it), a hex field and swatches.
// Every change is reported with `changed`, so whatever it colors updates as
// you go; `done(true)` keeps it, `done(false)` puts the old color back.
//
// Keys: arrows move in the square (Shift: faster), PgUp/PgDn change the
// hue, [ and ] the transparency, Tab goes to the hex field, Enter keeps,
// Esc cancels.
FocusScope {
  id: picker

  property color original: "white"
  property bool allowAlpha: false
  property string fontFamily: ""
  property real unit: 16
  property color ink: "white"
  property color dim: "#9fb0f0"
  property color accent: "#ffd23f"
  property color edge: "#3b5bd1"
  property var swatches: []

  property real hue: 0
  property real sat: 0
  property real val: 1
  property real alpha: 1
  readonly property color current: Qt.hsva(hue, sat, val, allowAlpha ? alpha : 1)

  signal changed(color value)
  signal keyed()          // a key was pressed in it (tablet mode notes the keyboard)
  signal done(bool keep)

  implicitWidth: unit * 22
  implicitHeight: column.implicitHeight

  function start(value) {
    picker.original = value
    picker.setColor(value)
    hexField.text = picker.hex(value)
    keyCatcher.forceActiveFocus()
  }

  function setColor(c) {
    var col = Qt.color(c)
    if (col.hsvSaturation > 0 && col.hsvValue > 0) picker.hue = Math.max(0, col.hsvHue)
    picker.sat = col.hsvSaturation
    picker.val = col.hsvValue
    picker.alpha = col.a
  }

  // "#rrggbb", or "#aarrggbb" when it's see-through
  function hex(c) {
    var col = Qt.color(c)
    var two = function(x) { var h = Math.round(x * 255).toString(16); return h.length < 2 ? "0" + h : h }
    return "#" + (picker.allowAlpha && col.a < 0.999 ? two(col.a) : "") + two(col.r) + two(col.g) + two(col.b)
  }

  function report() {
    hexField.text = picker.hex(picker.current)
    picker.changed(picker.current)
  }

  function nudge(dx, dy, big) {
    var step = big ? 0.1 : 0.02
    picker.sat = Math.max(0, Math.min(1, picker.sat + dx * step))
    picker.val = Math.max(0, Math.min(1, picker.val - dy * step))
    picker.report()
  }

  Item {
    id: keyCatcher
    focus: true
    Keys.onPressed: function(event) {
      picker.keyed()
      var big = event.modifiers & Qt.ShiftModifier
      var k = event.key
      if (k === Qt.Key_Left) picker.nudge(-1, 0, big)
      else if (k === Qt.Key_Right) picker.nudge(1, 0, big)
      else if (k === Qt.Key_Up) picker.nudge(0, -1, big)
      else if (k === Qt.Key_Down) picker.nudge(0, 1, big)
      else if (k === Qt.Key_PageUp || k === Qt.Key_PageDown) {
        picker.hue = (picker.hue + (k === Qt.Key_PageUp ? -1 : 1) * (big ? 0.05 : 0.01) + 1) % 1
        picker.report()
      }
      else if (picker.allowAlpha && (k === Qt.Key_BracketLeft || k === Qt.Key_BracketRight)) {
        picker.alpha = Math.max(0, Math.min(1, picker.alpha + (k === Qt.Key_BracketRight ? 0.05 : -0.05)))
        picker.report()
      }
      else if (k === Qt.Key_Tab) hexField.forceActiveFocus()
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) picker.done(true)
      else if (k === Qt.Key_Escape) picker.done(false)
      else return
      event.accepted = true
    }
  }

  Column {
    id: column
    width: parent.width
    spacing: picker.unit * 0.7

    Row {
      spacing: picker.unit * 0.6
      height: picker.unit * 12

      // Saturation across, brightness down, for the current hue
      Item {
        id: square
        width: picker.unit * 14
        height: parent.height
        Rectangle { anchors.fill: parent; color: Qt.hsva(picker.hue, 1, 1, 1) }
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "white" }
            GradientStop { position: 1; color: "#00ffffff" }
          }
        }
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0; color: "#00000000" }
            GradientStop { position: 1; color: "black" }
          }
        }
        Rectangle {
          x: picker.sat * square.width - width / 2
          y: (1 - picker.val) * square.height - height / 2
          width: picker.unit * 0.9
          height: width
          radius: width / 2
          color: "transparent"
          border.color: picker.val > 0.5 ? "black" : "white"
          border.width: 2
        }
        MouseArea {
          anchors.fill: parent
          function pick(m) {
            picker.sat = Math.max(0, Math.min(1, m.x / width))
            picker.val = Math.max(0, Math.min(1, 1 - m.y / height))
            picker.report()
            keyCatcher.forceActiveFocus()
          }
          onPressed: function(m) { pick(m) }
          onPositionChanged: function(m) { if (pressed) pick(m) }
        }
      }

      // Hue
      Item {
        id: hueStrip
        width: picker.unit * 1.6
        height: parent.height
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0.0; color: "#ff0000" }
            GradientStop { position: 0.17; color: "#ffff00" }
            GradientStop { position: 0.33; color: "#00ff00" }
            GradientStop { position: 0.5; color: "#00ffff" }
            GradientStop { position: 0.67; color: "#0000ff" }
            GradientStop { position: 0.83; color: "#ff00ff" }
            GradientStop { position: 1.0; color: "#ff0000" }
          }
        }
        Rectangle {
          y: picker.hue * hueStrip.height - height / 2
          width: parent.width
          height: 4
          color: "white"
          border.color: "black"
          border.width: 1
        }
        MouseArea {
          anchors.fill: parent
          function pick(m) { picker.hue = Math.max(0, Math.min(0.999, m.y / height)); picker.report(); keyCatcher.forceActiveFocus() }
          onPressed: function(m) { pick(m) }
          onPositionChanged: function(m) { if (pressed) pick(m) }
        }
      }

      // Transparency, over a checkerboard
      Item {
        id: alphaStrip
        visible: picker.allowAlpha
        width: picker.unit * 1.6
        height: parent.height
        clip: true
        Grid {
          columns: 2
          Repeater {
            model: alphaStrip.width > 0 ? Math.ceil(alphaStrip.height / (alphaStrip.width / 2)) * 2 : 0
            Rectangle { width: alphaStrip.width / 2; height: width; color: (Math.floor(index / 2) + index) % 2 ? "#cccccc" : "#ffffff" }
          }
        }
        Rectangle {
          anchors.fill: parent
          gradient: Gradient {
            GradientStop { position: 0; color: Qt.hsva(picker.hue, picker.sat, picker.val, 1) }
            GradientStop { position: 1; color: Qt.hsva(picker.hue, picker.sat, picker.val, 0) }
          }
        }
        Rectangle {
          y: (1 - picker.alpha) * alphaStrip.height - height / 2
          width: parent.width
          height: 4
          color: "white"
          border.color: "black"
          border.width: 1
        }
        MouseArea {
          anchors.fill: parent
          function pick(m) { picker.alpha = Math.max(0, Math.min(1, 1 - m.y / height)); picker.report(); keyCatcher.forceActiveFocus() }
          onPressed: function(m) { pick(m) }
          onPositionChanged: function(m) { if (pressed) pick(m) }
        }
      }
    }

    // Old and new, and the hex value
    Row {
      spacing: picker.unit * 0.6
      Rectangle {
        width: picker.unit * 3
        height: picker.unit * 1.8
        color: picker.original
        border.color: picker.edge
        border.width: 1
        Text { anchors.centerIn: parent; text: "OLD"; textFormat: Text.PlainText; font.family: picker.fontFamily; font.pixelSize: picker.unit * 0.55; color: picker.val > 0.6 && picker.sat < 0.5 ? "black" : "white" }
      }
      Rectangle {
        width: picker.unit * 3
        height: picker.unit * 1.8
        color: picker.current
        border.color: picker.edge
        border.width: 1
        Text { anchors.centerIn: parent; text: "NEW"; textFormat: Text.PlainText; font.family: picker.fontFamily; font.pixelSize: picker.unit * 0.55; color: picker.val > 0.6 && picker.sat < 0.5 ? "black" : "white" }
      }
      Rectangle {
        width: picker.unit * 8
        height: picker.unit * 1.8
        color: "transparent"
        border.color: hexField.activeFocus ? picker.accent : picker.edge
        border.width: 1
        TextInput {
          id: hexField
          anchors.fill: parent
          anchors.leftMargin: picker.unit * 0.4
          verticalAlignment: TextInput.AlignVCenter
          color: picker.ink
          font.family: picker.fontFamily
          font.pixelSize: picker.unit * 0.85
          maximumLength: 9
          selectByMouse: true
          onTextEdited: {
            if (/^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(text)) {
              picker.setColor(text)
              picker.changed(picker.current)
            }
          }
          Keys.onPressed: function(event) {
            picker.keyed()
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { picker.done(true); event.accepted = true }
            else if (event.key === Qt.Key_Escape) { picker.done(false); event.accepted = true }
            else if (event.key === Qt.Key_Tab) { keyCatcher.forceActiveFocus(); event.accepted = true }
          }
        }
      }
    }

    // Quick picks
    Flow {
      width: parent.width
      spacing: picker.unit * 0.3
      Repeater {
        model: picker.swatches
        delegate: Rectangle {
          required property string modelData
          width: picker.unit * 1.4
          height: width
          color: modelData
          border.color: picker.edge
          border.width: 1
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { picker.setColor(parent.modelData); picker.report(); keyCatcher.forceActiveFocus() }
          }
        }
      }
    }
  }
}
