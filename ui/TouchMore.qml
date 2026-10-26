import QtQuick

// Tablet mode's ⋯ panel (Guide.qml touchMore): the buttons that didn't fit
// in a row, in a grid above the bottom, over a shade. A tap on one runs it
// (and closes the panel); a tap on the shade, Back or any key closes it.
Item {
  id: more

  required property var guide

  readonly property real f: guide.fingerPx
  readonly property var list: guide.touchMore || []
  readonly property real cell: Math.round(f * 3.3)
  readonly property int cols: Math.max(1, Math.min(4, list.length, Math.floor((width - f) / (cell + f * 0.2))))

  visible: guide.touchMode && list.length > 0

  MouseArea {
    anchors.fill: parent
    onClicked: more.guide.closeTouchMore()
    Rectangle { anchors.fill: parent; color: more.guide.colors.scrim }
  }

  Rectangle {
    id: panel
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: more.f * 1.6
    width: grid.width + more.f * 0.8
    height: grid.height + more.f * 0.8
    radius: more.f * 0.3
    color: more.guide.colors.boxBg
    border.color: more.guide.colors.boxBorder
    border.width: Math.max(1, Math.round(more.f * 0.03))

    // a tap on the panel itself, between buttons, doesn't close it
    MouseArea { anchors.fill: parent }

    Grid {
      id: grid
      anchors.centerIn: parent
      columns: more.cols
      spacing: Math.round(more.f * 0.2)
      Repeater {
        model: more.list
        delegate: TouchButton {
          required property var modelData
          guide: more.guide
          width: more.cell
          label: modelData.touch.moreLabel || modelData.label   // (123: Channel number)
          icon: modelData.touch.icon || ""
          onTapped: more.guide.touchPress(modelData.touch)
        }
      }
    }
  }
}
