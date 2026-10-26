import QtQuick

// The strip across the bottom of Home and the guide, just above the key
// hints, asking one thing at a time, each once (guide.stripAsks): update
// notifications, off at first, then Recordings, new. Y (or a click) turns it
// on, N puts it away for good. After Turn on for updates, what the first
// look found, for a few seconds. A message too long for one line goes on to
// the next, the strip growing up. Never over a box, nor while you watch.
Box {
  id: strip

  required property var guide

  readonly property var updates: guide.updates
  readonly property real u: guide.u
  readonly property string asking: guide.stripAsks
  readonly property string message: guide.stripQuestion || updates.strip

  visible: message !== "" && guide.stripPlace
  height: Math.max(Math.round(u * 3), Math.round(said.implicitHeight + u * 1.4), guide.touchMode ? Math.round(guide.fingerPx + u * 0.6) : 0)
  s: guide.look.box
  unit: u

  // a click on the strip stays on it
  MouseArea { anchors.fill: parent }

  Icon {
    id: mark
    anchors.left: parent.left
    anchors.leftMargin: strip.u
    anchors.verticalCenter: parent.verticalCenter
    name: "info"
    size: Math.round(strip.u * 1.3)
    stroke: 2
    color: strip.guide.colors.accent
  }
  Label {
    id: said
    anchors.left: mark.right
    anchors.leftMargin: strip.u * 0.8
    anchors.right: actions.visible ? actions.left : parent.right
    anchors.rightMargin: strip.u
    anchors.verticalCenter: parent.verticalCenter
    text: strip.message
    s: strip.guide.look.menuRow
    unit: strip.u
    sizeFactor: 0.78
    color: strip.guide.ink
    wrapMode: Text.WordWrap
    maximumLineCount: 3
    elide: Text.ElideRight
  }

  Row {
    id: actions
    visible: strip.asking !== ""
    anchors.right: parent.right
    anchors.rightMargin: strip.u
    anchors.verticalCenter: parent.verticalCenter
    spacing: strip.u * 1.2
    Repeater {
      model: [{ keys: ["Y"], label: "Turn on", yes: true }, { keys: ["N"], label: "Dismiss", yes: false }]
      delegate: Item {
        id: action
        required property var modelData
        width: hint.implicitWidth
        height: hint.implicitHeight
        // tablet mode: a button that answers (its own action, not the key)
        KeyHints {
          id: hint
          touchGuide: strip.guide
          model: [{ keys: action.modelData.keys, label: action.modelData.label, touch: { run: function() { strip.guide.stripAnswer(action.modelData.yes) } } }]
          size: strip.u * 1.55
          capStyle: strip.guide.look.keycap
          labelStyle: strip.guide.look.keyLabel
        }
        MouseArea {
          enabled: !hint.touching
          anchors.fill: parent
          anchors.margins: -strip.u * 0.3
          cursorShape: Qt.PointingHandCursor
          onClicked: strip.guide.stripAnswer(action.modelData.yes)
        }
      }
    }
  }
}
