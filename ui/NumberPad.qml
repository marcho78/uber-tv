import QtQuick

// Tablet mode's number pad (123, Guide.qml numberPad): a channel by its
// number. The digits as typed, then Watch, dim until they're a channel's
// number (it watches as Enter does: the lock and a 2nd stream ask first). A
// tap on the shade, or any key, closes it.
Item {
  id: pad

  required property var guide

  readonly property real f: guide.fingerPx
  property string typed: ""
  readonly property int row: typed !== "" ? guide.numbers.indexOf(Number(typed)) : -1

  visible: guide.touchMode && guide.numberPad
  onVisibleChanged: typed = ""

  function press(k) {
    if (k === "back") pad.typed = pad.typed.slice(0, -1)
    else if (k === "watch") { if (pad.row >= 0) pad.guide.numberWatch(pad.row) }
    else if (pad.typed.length < 5) pad.typed += k
  }

  MouseArea {
    anchors.fill: parent
    onClicked: pad.guide.closeNumberPad()
    Rectangle { anchors.fill: parent; color: pad.guide.colors.scrim }
  }

  Rectangle {
    anchors.centerIn: parent
    width: grid.width + pad.f * 0.8
    height: shown.height + grid.height + pad.f * 1.0
    radius: pad.f * 0.3
    color: pad.guide.colors.boxBg
    border.color: pad.guide.colors.boxBorder
    border.width: Math.max(1, Math.round(pad.f * 0.03))

    // a tap on the panel itself, between keys, doesn't close it
    MouseArea { anchors.fill: parent }

    Text {
      id: shown
      anchors.horizontalCenter: parent.horizontalCenter
      y: pad.f * 0.3
      height: Math.round(pad.f * 1.3)
      verticalAlignment: Text.AlignVCenter
      text: pad.typed
      textFormat: Text.PlainText
      color: pad.guide.marquee
      font.family: pad.guide.fonts.body
      font.pixelSize: Math.round(pad.f * 0.8)
      font.weight: Font.DemiBold
    }

    Grid {
      id: grid
      anchors.horizontalCenter: parent.horizontalCenter
      y: shown.y + shown.height + pad.f * 0.2
      columns: 3
      spacing: Math.round(pad.f * 0.2)
      Repeater {
        model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "back", "0", "watch"]
        delegate: TouchButton {
          required property string modelData
          guide: pad.guide
          width: Math.round(pad.f * 1.7)
          label: modelData === "back" ? "⌫" : modelData === "watch" ? "Watch" : modelData
          accessibleName: modelData === "back" ? "Backspace" : label
          primary: modelData === "watch"
          opacity: modelData === "watch" && pad.row < 0 ? 0.4 : 1
          onTapped: pad.press(modelData)
        }
      }
    }
  }
}
