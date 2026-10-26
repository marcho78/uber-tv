import Quickshell
import Quickshell.Wayland
import QtQuick
import QtMultimedia

// The mini player: on top of everything. It holds the keyboard only while
// the pointer is over it, so ↑↓ change channel there and typing elsewhere
// is left alone. Drag to move, scroll or drag the top-left corner to
// resize, double-click for full screen. Tablet mode: a finger's tap shows
// its bar (a tap again hides it), its buttons and corner a finger big; a
// drag that's cancelled puts it back and saves nothing.
PanelWindow {
  id: pipWindow

  required property var guide
  property alias video: pipVideo
  property alias keys: pipKeys

  visible: guide.pip
  readonly property real screenW: screen ? screen.width : 1920
  readonly property real screenH: screen ? screen.height : 1080
  // tablet mode: never narrower than its bar's six finger-wide buttons need
  readonly property real w: Math.round(Math.max(240, guide.touchMode ? guide.fingerPx * 7 : 0, Math.min(screenW * 0.6, guide.pipW || screenW * 0.25)))
  readonly property real h: Math.round(w * 9 / 16)
  readonly property real k: Math.max(10, h / 14)   // sizes inside, by the window's height
  anchors { right: true; bottom: true }
  margins.right: Math.max(0, Math.min(screenW - w, guide.pipRight))
  margins.bottom: Math.max(0, Math.min(screenH - h, guide.pipBottom))
  implicitWidth: w
  implicitHeight: h
  color: "black"
  WlrLayershell.namespace: "om-pg-mini"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: guide.pipPointerIn && !(guide.nativeSaver && guide.nativeSaver.up) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore

  function clampPlace() {
    guide.pipRight = Math.max(0, Math.min(screenW - w, guide.pipRight))
    guide.pipBottom = Math.max(0, Math.min(screenH - h, guide.pipBottom))
  }

  VideoOutput {
    id: pipVideo
    anchors.fill: parent
    fillMode: VideoOutput.PreserveAspectFit
  }

  Item {
    id: pipKeys
    anchors.fill: parent
    focus: true
    Keys.onPressed: function(event) {
      var k = event.key
      if (guide.keyFirst(event)) return
      // asked first (a 2nd stream from a recording's provider): Enter watches anyway, Esc stays
      if (guide.streamAsk && (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Y)) guide.answerStream(true)
      else if (guide.streamAsk && (k === Qt.Key_Escape || k === Qt.Key_Backspace || k === Qt.Key_N)) guide.answerStream(false)
      else if (k === Qt.Key_Escape) guide.closePip()
      else if (k === Qt.Key_Up || k === Qt.Key_PageUp) guide.pipSurf(1)
      else if (k === Qt.Key_Down || k === Qt.Key_PageDown) guide.pipSurf(-1)
      else if (k === Qt.Key_M) guide.muted = !guide.muted
      else if (k === Qt.Key_G) guide.guidePip()
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_F) guide.expandPip()
      else if (k === Qt.Key_I || k === Qt.Key_Space) guide.showPipBanner()
      else return
      event.accepted = true
    }
  }

  HoverHandler { id: pipHover }

  // Tablet mode: a finger here counts too (the guide's own watcher is hidden
  // while the mini player is up). It only watches, under nothing.
  TouchWatch {
    anchors.fill: parent
    z: 10000
    onTouched: guide.touchReleased()
    onPointed: guide.noteInput("pointer")
  }

  // A yellow outline while it has the keyboard
  Rectangle {
    z: 3
    anchors.fill: parent
    color: "transparent"
    border.color: guide.marquee
    border.width: Math.max(2, pipWindow.k * 0.15)
    visible: guide.pipPointerIn
  }

  // Moving and resizing
  MouseArea {
    anchors.fill: parent
    property real fromX: 0
    property real fromY: 0
    property real startRight: 0
    property real startBottom: 0
    property real travel: 0             // how far the pointer has gone, all told (the window follows it)
    property bool moved: false          // past a drag's start: letting go isn't a tap
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    onPressed: function(mouse) {
      fromX = mouse.x
      fromY = mouse.y
      startRight = guide.pipRight
      startBottom = guide.pipBottom
      travel = 0
      moved = false
      pipKeys.forceActiveFocus()
    }
    onPositionChanged: function(mouse) {
      if (!pressed) return
      // each event's step, before the window catches up (so a slow drag adds up)
      travel += Math.abs(mouse.x - fromX) + Math.abs(mouse.y - fromY)
      if (travel > Qt.styleHints.startDragDistance) moved = true
      guide.pipRight -= mouse.x - fromX
      guide.pipBottom -= mouse.y - fromY
      pipWindow.clampPlace()
    }
    onReleased: guide.saveSettings()
    // cancelled (the window or a gesture took it): back where it was, nothing saved
    onCanceled: { guide.pipRight = startRight; guide.pipBottom = startBottom }
    onClicked: function(mouse) {
      if (moved || !guide.isFinger(mouse)) return
      if (guide.pipBannerShown) guide.pipBannerShown = false
      else guide.showPipBanner()
    }
    onDoubleClicked: function(mouse) { if (!guide.isFinger(mouse)) guide.expandPip() }
    onWheel: function(wheel) {
      guide.pipW = Math.max(240, Math.min(pipWindow.screenW * 0.6, pipWindow.w + (wheel.angleDelta.y > 0 ? 48 : -48)))
      pipWindow.clampPlace()
      guide.saveSettings()
    }
  }

  // What's on, and the controls: on hover, when clicked, or for a moment after a change
  Rectangle {
    id: pipBar
    visible: guide.pipPointerIn || guide.pipBannerShown || guide.reception !== "on" || !!guide.streamAsk
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Math.max(pipWindow.k * 2.6, guide.touchMode ? guide.fingerPx + pipWindow.k * 0.6 : 0)
    gradient: Gradient {
      GradientStop { position: 0; color: guide.miniBarColor }
      GradientStop { position: 1; color: Qt.rgba(guide.miniBarColor.r, guide.miniBarColor.g, guide.miniBarColor.b, guide.miniBarColor.a * 0.6) }
    }

    Column {
      anchors.left: parent.left
      anchors.leftMargin: pipWindow.k * 1.4
      anchors.right: pipButtons.left
      anchors.rightMargin: pipWindow.k * 0.6
      anchors.verticalCenter: parent.verticalCenter
      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: guide.streamAsk ? guide.streamAskLabel : guide.showTitle(guide.nowLabel())
        color: guide.marquee
        font.family: guide.fonts.body
        font.pixelSize: pipWindow.k * 0.95
        font.bold: true
        font.capitalization: Font.AllUppercase
        elide: Text.ElideRight
      }
      Text {
        textFormat: Text.PlainText
        width: parent.width
        visible: pipWindow.w >= 360 || !!guide.streamAsk
        text: guide.streamAsk ? guide.streamAskNote : guide.vod ? guide.vod.subtitle || "" : guide.onAir ? (guide.onAir.live ? "● LIVE  " : "") + guide.showTitle(guide.onAir.title) : ""
        color: guide.ink
        font.family: guide.fonts.body
        font.pixelSize: pipWindow.k * 0.8
        elide: Text.ElideRight
      }
    }

    Row {
      id: pipButtons
      anchors.right: parent.right
      anchors.rightMargin: pipWindow.k * 0.5
      anchors.verticalCenter: parent.verticalCenter
      spacing: pipWindow.k * 0.3

      Repeater {
        model: guide.streamAsk ? [{ label: "WATCH ANYWAY", act: "streamYes" }, { label: "STAY", act: "streamNo" }] : [
          { label: "CH▲", act: "up" }, { label: "CH▼", act: "down" },
          { label: "MUTE", act: "mute" }, { label: "GUIDE", act: "guide" }, { label: "FULL", act: "full" }, { label: "×", act: "close" }
        ]
        delegate: Rectangle {
          required property var modelData
          width: Math.max(pipLabel.implicitWidth + pipWindow.k * 0.8, guide.touchMode ? guide.fingerPx : 0)
          height: Math.max(pipWindow.k * 1.6, guide.touchMode ? guide.fingerPx : 0)
          color: buttonMouse.containsMouse ? guide.cellEdge : Qt.rgba(0, 0, 0, 0.35)
          border.color: modelData.act === "mute" && guide.muted ? guide.marquee : guide.cellEdge
          border.width: 1

          Text {
            id: pipLabel
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: parent.modelData.label
            color: parent.modelData.act === "mute" && guide.muted ? guide.marquee : guide.ink
            font.family: guide.fonts.body
            font.pixelSize: pipWindow.k * 0.8
            font.bold: true
          }

          MouseArea {
            id: buttonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              var act = parent.modelData.act
              if (act === "streamYes" || act === "streamNo") guide.answerStream(act === "streamYes")
              else if (act === "up") guide.pipSurf(1)
              else if (act === "down") guide.pipSurf(-1)
              else if (act === "mute") guide.muted = !guide.muted
              else if (act === "guide") guide.guidePip()
              else if (act === "full") guide.expandPip()
              else guide.closePip()
            }
          }
        }
      }
    }
  }

  ChannelIdent {
    anchors.fill: parent
    up: guide.reception !== "off" && (guide.cardShow ? guide.identUp : guide.reception === "tuning" || guide.reception === "lost") || guide.identStatus === "stalled"
    logo: guide.vod ? guide.posterFor(guide.vod) : guide.logoFor(guide.channels[guide.tunedRow])
    number: guide.vod ? "" : guide.numbers[guide.tunedRow] ? "CH " + guide.numbers[guide.tunedRow] : ""
    name: guide.vod ? guide.vod.title : guide.channels[guide.tunedRow] ? guide.channels[guide.tunedRow].name : ""
    status: guide.identStatus
    unit: pipWindow.k * 0.75
    look: guide.look
    alarm: guide.colors.alert
    image: guide.areaImages.card
  }

  Text {
    textFormat: Text.PlainText
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: pipWindow.k * 0.5
    visible: guide.muted
    text: "MUTE"
    color: guide.marquee
    font.family: guide.fonts.body
    font.pixelSize: pipWindow.k * 0.8
    font.bold: true
  }

  // The resize grip: the corner away from where it's pinned (tablet mode: a
  // finger big; cancelled, the size it was)
  MouseArea {
    anchors.left: parent.left
    anchors.top: parent.top
    width: Math.max(pipWindow.k * 1.2, guide.touchMode ? guide.fingerPx : 0)
    height: width
    cursorShape: Qt.SizeFDiagCursor
    property real fromX: 0
    property real startW: 0
    property real startRight: 0
    property real startBottom: 0
    onPressed: function(mouse) { fromX = mouse.x; startW = guide.pipW; startRight = guide.pipRight; startBottom = guide.pipBottom }
    // (growing near an edge moves it too: all three as they were)
    onCanceled: { guide.pipW = startW; guide.pipRight = startRight; guide.pipBottom = startBottom; pipWindow.clampPlace() }
    onPositionChanged: function(mouse) {
      if (!pressed) return
      guide.pipW = Math.max(240, Math.min(pipWindow.screenW * 0.6, pipWindow.w - (mouse.x - fromX)))
      pipWindow.clampPlace()
    }
    onReleased: guide.saveSettings()

    Canvas {
      anchors.fill: parent
      visible: pipBar.visible
      onPaint: {
        var c = getContext("2d")
        c.reset()
        c.strokeStyle = guide.marquee.toString()
        c.lineWidth = 2
        c.beginPath()
        c.moveTo(3, height - 3); c.lineTo(3, 3); c.lineTo(width - 3, 3)
        c.stroke()
      }
    }
  }
}
