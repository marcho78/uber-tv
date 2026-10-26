import QtQuick
import QtMultimedia
import "../Look.js" as Look

// What an app plays, full screen: the video (the player only ever has the
// helper's relay address), and over it for a few seconds after a key (or
// while paused) its title, how far in, and the keys. Esc stops it and goes
// back to the app; Space or Enter pauses; ← → skip 10 seconds. Styled by
// the VOD bar's elements (vodProgress, ltTitle and the lower third's).
// Tablet mode: a finger's tap shows the bar (a tap again hides it), the keys
// are buttons, and a finger along the bar goes there when it lets go.
Rectangle {
  id: screen

  required property var guide
  readonly property var pb: guide.appPlayback
  readonly property var s: pb.session
  readonly property real u: guide.u
  property bool barShown: true
  property real dragAt: -1            // tablet mode: where a finger along the bar is, in seconds (-1: none)
  property var dragFor: null          // the video it began on: letting go seeks only that one

  color: "black"

  function clock(sec) {
    if (!(sec > 0)) return "0:00"
    var t = Math.floor(sec)
    var h = Math.floor(t / 3600), m = Math.floor(t % 3600 / 60), x = t % 60
    return (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (x < 10 ? "0" : "") + x
  }

  function poke() { screen.barShown = true; barTimer.restart() }

  VideoOutput {
    id: video
    anchors.fill: parent
    fillMode: VideoOutput.PreserveAspectFit
    Component.onCompleted: screen.pb.videoOutput = video
    Component.onDestruction: if (screen.pb.videoOutput === video) screen.pb.videoOutput = null
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onPositionChanged: screen.poke()
    onClicked: function(mouse) {
      if (guide.isFinger(mouse)) {
        if (screen.barShown && !screen.pb.paused) { screen.barShown = false; barTimer.stop() }
        else screen.poke()
        return
      }
      screen.poke()
      screen.pb.togglePause()
    }
  }

  Connections {
    target: screen.pb
    function onPausedChanged() { screen.poke() }
  }

  Timer {
    id: barTimer
    interval: 4000
    onTriggered: if (!screen.pb.paused) screen.barShown = false
  }
  Component.onCompleted: poke()

  // loading, or why it stopped
  Text {
    anchors.centerIn: parent
    visible: screen.pb.buffering || (screen.pb.error !== "" && !!screen.s)
    textFormat: Text.PlainText
    text: screen.pb.error !== "" ? screen.pb.error : screen.pb.closing ? "Stopping…" : "Loading…"
    color: screen.pb.error !== "" ? guide.colors.alert : "white"
    font.family: guide.fontFamily
    font.pixelSize: Math.round(screen.u * 1.6)
    style: Text.Outline
    styleColor: "#80000000"
  }

  // the bar
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: barCol.implicitHeight + screen.u * 3
    visible: screen.barShown || screen.pb.paused
    gradient: Gradient {
      GradientStop { position: 0; color: "#00000000" }
      GradientStop { position: 0.4; color: "#c0000000" }
      GradientStop { position: 1; color: "#e0000000" }
    }
    Column {
      id: barCol
      x: screen.u * 3
      anchors.bottom: parent.bottom
      anchors.bottomMargin: screen.u * 1.6
      width: parent.width - screen.u * 6
      spacing: screen.u * 0.5
      Row {
        spacing: screen.u * 1
        Text {
          textFormat: Text.PlainText
          text: screen.s ? (screen.s.title || (guide.apps.record(screen.s.app) || {}).name || "") : ""
          color: "white"
          font.family: guide.fontFamily
          font.pixelSize: Math.round(screen.u * 1.8)
          font.bold: true
          elide: Text.ElideRight
          width: Math.min(implicitWidth, barCol.width * 0.7)
        }
        Text {
          anchors.baseline: parent.children[0].baseline
          textFormat: Text.PlainText
          visible: screen.pb.paused
          text: "PAUSED"
          color: guide.marquee
          font.family: guide.fontFamily
          font.pixelSize: Math.round(screen.u * 1.1)
          font.bold: true
        }
      }
      Text {
        visible: text !== ""
        textFormat: Text.PlainText
        text: screen.s ? screen.s.subtitle : ""
        color: "#d0d0d0"
        font.family: guide.fontFamily
        font.pixelSize: Math.round(screen.u * 1.15)
        elide: Text.ElideRight
        width: barCol.width
      }
      Item {
        width: barCol.width
        height: screen.u * 1.6
        visible: !(screen.s && screen.s.live)
        Rectangle {
          id: track
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - times.width - screen.u * 1.5
          height: Math.max(4, screen.u * 0.35)
          radius: height / 2
          color: "#40ffffff"
          Rectangle {
            height: parent.height
            radius: height / 2
            width: screen.pb.duration > 0 ? parent.width * Math.min(1, (screen.dragAt >= 0 ? screen.dragAt : screen.pb.position) / screen.pb.duration) : 0
            color: guide.marquee
          }
          // tablet mode: the mark a finger moves, and a finger's room along it
          Rectangle {
            visible: guide.touchMode && screen.pb.duration > 0
            width: Math.round(guide.fingerPx * 0.5)
            height: width
            radius: width / 2
            x: parent.width * Math.min(1, (screen.dragAt >= 0 ? screen.dragAt : screen.pb.position) / Math.max(1, screen.pb.duration)) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: guide.marquee
          }
          MouseArea {
            anchors.fill: parent
            anchors.topMargin: -Math.max(0, (guide.fingerPx - parent.height) / 2)
            anchors.bottomMargin: -Math.max(0, (guide.fingerPx - parent.height) / 2)
            enabled: guide.touchMode && screen.pb.duration > 0
            preventStealing: true
            function at(x) { return Math.max(0, Math.min(1, x / Math.max(1, track.width))) * screen.pb.duration }
            onPressed: function(mouse) { screen.dragFor = screen.s; screen.dragAt = at(mouse.x); screen.poke() }
            onPositionChanged: function(mouse) { if (pressed) { screen.dragAt = at(mouse.x); screen.poke() } }
            onReleased: function(mouse) { var to = at(mouse.x), was = screen.dragFor; screen.dragAt = -1; screen.dragFor = null; if (was && screen.s === was) screen.pb.seekTo(to) }
            onCanceled: { screen.dragAt = -1; screen.dragFor = null }
          }
        }
        Text {
          id: times
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: screen.clock(screen.dragAt >= 0 ? screen.dragAt : screen.pb.position) + " / " + screen.clock(screen.pb.duration)
          color: "white"
          font.family: guide.fontFamily
          font.pixelSize: Math.round(screen.u * 1.1)
        }
      }
      Text {
        visible: !!screen.s && screen.s.live
        textFormat: Text.PlainText
        text: "● LIVE"
        color: guide.colors.alert
        font.family: guide.fontFamily
        font.pixelSize: Math.round(screen.u * 1.1)
        font.bold: true
      }
      KeyHints {
        visible: guide.showKeyHints || guide.touchMode
        size: screen.u * 1.3
        capStyle: guide.look.keycap
        labelStyle: guide.look.keyLabel
        labelColor: "#d0d0d0"
        touchGuide: screen.guide
        touchWidth: barCol.width
        model: [{ keys: ["SPACE"], label: screen.pb.paused ? "Play" : "Pause", touch: { key: Qt.Key_Space, primary: true, icon: screen.pb.paused ? "playsolid" : "pausebars" } }]
               .concat(screen.s && screen.s.live ? [] : [{ keys: ["←", "→"], label: "10 seconds" }])
               .concat([{ keys: ["M"], label: guide.muted ? "Sound on" : "Mute", touch: { key: Qt.Key_M } }, { keys: ["ESC"], label: "Stop", touch: { key: Qt.Key_Escape, back: true } }])
      }
    }
  }
}
