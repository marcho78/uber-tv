import QtQuick
import "../Touch.js" as Touch

// A row of hints: keycaps, then what they do. Each hint is
// { keys: ["SHIFT", "+", "SPACE"], label: "Mark category" }; "+" (together)
// and "/" (either) are drawn as plain text between keys. The keycap and key
// label elements (Look.js) style them; labelColor, where given, colors the
// labels instead (the managing footer, say).
//
// Tablet mode: given the guide (touchGuide), while its touch controls are on, the same
// hints are buttons (Touch.js split): Back first (the hint whose touch is
// back), then those with their own touch key or action, the ones past
// touchWidth under ⋯, then any words with no key ("Checking it…"). A hint
// with neither is something a finger does itself (scrolling, moving).
Row {
  id: hints

  property var model: []
  property real size: 24
  property var capStyle: ({})
  property var labelStyle: ({})
  property var labelColor: undefined
  property var touchGuide: null     // the guide, for tablet mode (not named guide: it would hide yours)
  property real touchWidth: 0        // the room for the buttons (0: no limit)

  readonly property bool touching: !!touchGuide && touchGuide.touchMode === true
  readonly property var touchSplit: Touch.split(touching ? model : [])
  readonly property real touchGap: touching ? Math.round(touchGuide.fingerPx * 0.2) : 0
  // how many buttons fit (measured unseen, below), after Back and the words,
  // with room left for ⋯ when not all do
  readonly property int touchFits: {
    if (!touching) return 0
    var widths = []
    for (var i = 0; i < measure.count; i++) {
      var it = measure.itemAt(i)
      widths.push(it ? it.implicitWidth : 0)
    }
    var room = touchWidth > 0 ? touchWidth - (backLoader.item ? backLoader.item.implicitWidth + touchGap : 0)
                                          - (notesRow.implicitWidth > 0 ? notesRow.implicitWidth + touchGap : 0) : 0
    return Touch.fitCount(widths, touchGap, room, touchGuide.fingerPx)
  }
  readonly property var touchRest: touchSplit.buttons.slice(touchFits)

  readonly property color textColor: labelColor !== undefined ? labelColor : (labelStyle.text ? labelStyle.text.color : "#9fb0f0")

  spacing: touching ? touchGap : size * 0.9

  // (a hint for touch only, like Nav rail's button, isn't a key)
  Repeater {
    model: hints.touching ? [] : (hints.model || []).filter(function(h) { return !h || h.touchOnly !== true })
    delegate: Row {
      id: hint
      required property var modelData
      spacing: hints.size * 0.25

      Repeater {
        model: modelData.keys
        delegate: Loader {
          required property string modelData
          anchors.verticalCenter: parent.verticalCenter
          // "+" and "/" between keys join them; on its own, "/" is the slash key
          sourceComponent: (modelData === "+" || modelData === "/") && hint.modelData.keys.length > 1 ? joiner : keycap
          property string key: modelData
        }
      }

      Label {
        anchors.verticalCenter: parent.verticalCenter
        leftPadding: modelData.keys.length ? hints.size * 0.15 : 0
        text: modelData.label
        s: hints.labelStyle
        unit: hints.size
        color: hints.textColor
      }
    }
  }

  Component {
    id: keycap
    Keycap {
      label: parent ? parent.key : ""
      size: hints.size
      s: hints.capStyle
    }
  }

  Component {
    id: joiner
    Label {
      text: parent ? parent.key : ""
      s: hints.labelStyle
      unit: hints.size
      sizeFactor: 0.55 / 0.58
      color: hints.textColor
    }
  }

  // ---- tablet mode ----
  Loader {
    id: backLoader
    active: hints.touching && !!hints.touchSplit.back
    visible: active
    anchors.verticalCenter: parent.verticalCenter
    sourceComponent: TouchButton {
      guide: hints.touchGuide
      label: hints.touchSplit.back ? hints.touchSplit.back.label : ""
      icon: "back"
      onTapped: hints.touchGuide.touchPress(hints.touchSplit.back.touch)
    }
  }

  Repeater {
    model: hints.touching ? hints.touchSplit.buttons.slice(0, hints.touchFits) : []
    delegate: TouchButton {
      required property var modelData
      anchors.verticalCenter: parent.verticalCenter
      guide: hints.touchGuide
      label: modelData.label
      icon: modelData.touch.icon || ""
      primary: modelData.touch.primary === true
      onTapped: hints.touchGuide.touchPress(modelData.touch)
    }
  }

  Loader {
    id: moreLoader
    active: hints.touching && hints.touchRest.length > 0
    visible: active
    anchors.verticalCenter: parent.verticalCenter
    sourceComponent: TouchButton {
      guide: hints.touchGuide
      icon: "more"
      lit: hints.touchGuide.touchMore !== null
      onTapped: hints.touchGuide.openTouchMore(hints.touchRest)
    }
  }

  Row {
    id: notesRow
    visible: hints.touching && hints.touchSplit.notes.length > 0
    anchors.verticalCenter: parent.verticalCenter
    spacing: hints.touchGap
    Repeater {
      model: hints.touching ? hints.touchSplit.notes : []
      // the same size as the buttons' words
      delegate: Text {
        required property var modelData
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.label
        textFormat: Text.PlainText
        color: hints.textColor
        font.family: hints.touchGuide ? hints.touchGuide.fonts.body : ""
        font.pixelSize: hints.touchGuide ? Math.round(hints.touchGuide.fingerPx * 0.3) : hints.size * 0.6
      }
    }
  }

  // the buttons measured, unseen (how many fit)
  Item {
    visible: false
    Repeater {
      id: measure
      model: hints.touching ? hints.touchSplit.buttons : []
      delegate: TouchButton {
        required property var modelData
        guide: hints.touchGuide
        label: modelData.label
        icon: modelData.touch.icon || ""
      }
    }
  }
}
