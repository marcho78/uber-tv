import QtQuick
import "../Look.js" as Look

// A setting, TV style (Settings and the Customize panels): a big row with
// its name, maybe an icon, and at its right a switch, its value (‹ › round
// it when ← → change it), or › when it opens something. The focused one
// lights up and grows a little. Styled by menuRow, menuValue and toggle.
Item {
  id: row

  required property var guide
  property real u: guide.u
  property real size: 1               // the panels' rows are a little smaller
  property string label: ""
  property string icon: ""
  property string value: ""
  property string kind: "value"       // switch, choice, opens, action, info, value
  property bool on: false
  property bool focused: false
  property bool danger: false         // removes or clears something
  property bool dim: false            // can't be used just now
  property bool more: false           // a switch that also opens something (›)
  property bool oneClick: false       // a click acts at once: a double-click's second press is ignored
  signal activated()
  // tablet mode: ‹ (-1) or › (+1) tapped on a choice, and the switch tapped
  // on a row that also opens (more); everywhere else a tap is activated
  signal stepped(int dir)
  signal toggled()
  readonly property bool touching: !!guide && guide.touchMode === true

  readonly property real unit: u * size
  property string element: "menuRow"  // or a part that follows it (recordChoice)
  readonly property var st: focused ? guide.look[element + ":focused"] || guide.look["menuRow:focused"] : guide.look[element] || guide.look.menuRow
  readonly property var vst: focused ? guide.look["menuValue:focused"] : guide.look.menuValue
  readonly property var sw: on ? guide.look["toggle:on"] : guide.look.toggle
  readonly property color ink: dim && !focused ? guide.dimInk : (st.text ? st.text.color : "white")
  readonly property color valueInk: danger && !focused ? guide.colors.alert : (vst.text ? vst.text.color : "white")

  // at least a finger tall in tablet mode (the whole row is a target)
  implicitHeight: Math.max(Math.round(Look.px(guide.look.menuRow.height, unit)), touching ? guide.fingerPx : 0)

  // a tap a finger's width round a part of the row (and the part shown)
  function near(part, x) {
    if (!part.visible) return false
    var c = part.mapToItem(face, part.width / 2, 0).x
    return Math.abs(x - c) <= Math.max(guide.fingerPx, part.width) / 2
  }
  function tapAt(x) {
    if (row.touching && row.kind === "choice") {
      if (row.near(leftArrow, x)) { row.stepped(-1); return }
      if (row.near(rightArrow, x)) { row.stepped(1); return }
    }
    if (row.touching && row.more && row.kind === "switch" && row.near(toggle, x)) { row.toggled(); return }
    row.activated()
  }

  Box {
    id: face
    anchors.fill: parent
    // room at the sides to grow into
    anchors.leftMargin: Math.ceil(row.width * 0.03)
    anchors.rightMargin: Math.ceil(row.width * 0.03)
    s: row.st
    unit: row.unit
    scale: 1 + (Number(row.st.grow) || 0)
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Icon {
      id: picture
      visible: row.icon !== ""
      x: face.padding
      anchors.verticalCenter: parent.verticalCenter
      name: row.icon
      size: Math.round(row.unit * 1.5)
      stroke: 2
      color: row.ink
    }
    Label {
      id: name
      anchors.left: picture.visible ? picture.right : parent.left
      anchors.leftMargin: picture.visible ? row.unit * 0.9 : face.padding
      anchors.right: right.left
      anchors.rightMargin: row.unit
      anchors.verticalCenter: parent.verticalCenter
      text: row.label
      s: row.st
      unit: row.unit
      color: row.ink
      elide: Text.ElideRight
    }

    Row {
      id: right
      anchors.right: parent.right
      anchors.rightMargin: face.padding
      anchors.verticalCenter: parent.verticalCenter
      spacing: row.unit * 0.6
      Label {
        id: leftArrow
        anchors.verticalCenter: parent.verticalCenter
        visible: row.kind === "choice" && (row.focused || row.touching)
        text: "‹"
        s: row.vst
        unit: row.unit
        sizeFactor: 1.3
        color: row.valueInk
      }
      Label {
        anchors.verticalCenter: parent.verticalCenter
        visible: text !== ""
        // half the row; a recording choice's note all the room its short name leaves
        width: Math.min(implicitWidth, row.element !== "recordChoice" ? face.width * 0.5
                        : Math.max(face.width * 0.5, face.width - face.padding * 2 - row.unit * 2 - name.implicitWidth
                                                     - (picture.visible ? picture.width + row.unit * 0.9 : 0)))
        text: row.value
        s: row.vst
        unit: row.unit
        color: row.valueInk
        // a recording choice's note read from its start; a value (a folder's path) keeps both ends
        elide: row.element === "recordChoice" ? Text.ElideRight : Text.ElideMiddle
      }
      Label {
        id: rightArrow
        anchors.verticalCenter: parent.verticalCenter
        visible: row.kind === "opens" || (row.kind === "choice" && (row.focused || row.touching))
        text: "›"
        s: row.vst
        unit: row.unit
        sizeFactor: 1.3
        color: row.valueInk
      }
      // the switch
      Box {
        id: toggle
        anchors.verticalCenter: parent.verticalCenter
        visible: row.kind === "switch"
        width: Math.round(Look.px(row.sw.width, row.unit))
        height: Math.round(Look.px(row.sw.height, row.unit))
        s: row.sw
        unit: row.unit
        Rectangle {
          readonly property real gap: Math.max(2, Math.round(toggle.height * 0.14))
          width: toggle.height - gap * 2
          height: width
          radius: width / 2
          y: gap
          x: row.on ? toggle.width - width - gap : gap
          color: row.sw.knob || "white"
          Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
      }
      Label {
        anchors.verticalCenter: parent.verticalCenter
        visible: row.more
        text: "›"
        s: row.vst
        unit: row.unit
        sizeFactor: 1.3
        color: row.valueInk
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) { row.tapAt(mouse.x) }
      // the second press of a double-click is a second click, except where
      // one click acts (so a switch doesn't flip back, and a row that asks
      // twice isn't answered by a double-click), a tap's too
      onDoubleClicked: function(mouse) { if (!row.oneClick) row.tapAt(mouse.x) }
    }
  }
}
