import QtQuick

// A tablet mode button (ui/KeyHints.qml, the ⋯ panel): at least a finger
// tall and wide, its words and maybe an icon. A tap that lets go over it says
// tapped; a drag that starts on it doesn't.
Item {
  id: btn

  required property var guide
  property string label: ""
  property string icon: ""
  property bool primary: false        // the screen's main action (Watch)
  property bool lit: false            // ⋯ while its panel is open
  signal tapped()

  readonly property real h: guide.fingerPx
  readonly property color fill: primary ? guide.marquee : guide.colors.boxBg
  readonly property color ink: primary ? guide.inkOn(guide.marquee) : guide.ink

  implicitHeight: h
  implicitWidth: Math.max(h, content.implicitWidth + h * (label !== "" ? 0.6 : 0.3))

  Accessible.role: Accessible.Button
  Accessible.name: label

  Rectangle {
    anchors.fill: parent
    radius: btn.h * 0.22
    color: tap.pressed ? Qt.darker(btn.fill, 1.3) : btn.fill
    border.width: Math.max(1, Math.round(btn.h * 0.025))
    border.color: btn.primary ? btn.fill : btn.lit ? btn.guide.marquee : btn.guide.colors.cellBorder
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: btn.h * 0.16

    Icon {
      visible: btn.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      name: btn.icon
      size: Math.round(btn.h * 0.4)
      stroke: 2
      color: btn.primary ? btn.ink : btn.guide.marquee
    }
    Text {
      visible: btn.label !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: btn.label
      textFormat: Text.PlainText
      color: btn.ink
      font.family: btn.guide.fonts.body
      font.pixelSize: Math.round(btn.h * 0.3)
      font.weight: Font.Medium
    }
  }

  // takes the press (nothing under the button gets it), says tapped if the
  // finger lets go still over it
  TapHandler {
    id: tap
    gesturePolicy: TapHandler.ReleaseWithinBounds
    onTapped: btn.tapped()
  }
}
