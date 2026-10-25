import QtQuick
import "../Look.js" as Look

// The bar over a movie or video on demand: its picture, title and details,
// where you are along it, and the keys. Shown for a moment after a key,
// and all the while it's paused or the pointer is on it. Click or drag
// along it to go there: the time follows the drag, the picture jumps when
// you let go.
Box {
  id: bar

  required property var guide

  readonly property real position: guide.playPosition / 1000
  readonly property real duration: guide.playDuration / 1000
  readonly property var progressStyle: guide.look.vodProgress
  property real dragAt: -1            // where a drag along it is, in seconds (-1: none)
  property var dragFor: null          // the video the drag began on: letting go seeks only that one
  // a held ← → scrubs too (Guide.qml): its mark, until it's let go
  readonly property bool keyScrub: !!guide.scrub && guide.scrub.movie === true
  readonly property real shownAt: dragAt >= 0 ? dragAt : keyScrub ? guide.scrub.at : position
  readonly property bool held: scrub.containsMouse || scrub.pressed || keyScrub
  function atX(x) { return Math.max(0, Math.min(1, x / Math.max(1, track.width))) * duration }

  function hms(t) {
    t = Math.max(0, Math.floor(t))
    var h = Math.floor(t / 3600)
    var m = Math.floor((t % 3600) / 60)
    var sec = t % 60
    return (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (sec < 10 ? "0" : "") + sec
  }

  height: content.implicitHeight + bar.padding * 2
  s: guide.look.vodBar
  unit: guide.u

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: bar.padding
    spacing: guide.u * 0.9

    Row {
      width: parent.width
      spacing: guide.u * 1.2

      Image {
        id: poster
        width: status === Image.Ready ? Math.round(height * sourceSize.width / Math.max(1, sourceSize.height)) : 0
        height: guide.u * 4.4
        source: guide.posterFor(guide.vod)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
      }

      Column {
        width: parent.width - poster.width - state.width - guide.u * 2.4
        anchors.verticalCenter: parent.verticalCenter
        spacing: guide.u * 0.3
        Label {
          width: parent.width
          text: guide.vod ? guide.showTitle(guide.vod.title) : ""
          s: guide.look.vodTitle
          unit: guide.u
          elide: Text.ElideRight
        }
        Label {
          width: parent.width
          visible: text !== ""
          text: guide.vod ? guide.vod.subtitle || "" : ""
          s: guide.look.vodInfo
          unit: guide.u
          elide: Text.ElideRight
        }
      }

      Label {
        id: state
        anchors.verticalCenter: parent.verticalCenter
        text: guide.reception === "tuning" ? "Loading…" : guide.reception === "lost" ? "Can't play this" : guide.vodPaused ? "Paused" : ""
        s: guide.look.vodTitle
        unit: guide.u
        sizeFactor: 0.6
        color: guide.reception === "lost" ? guide.colors.alert : s.text.color
      }
    }

    // Where you are
    Item {
      width: parent.width
      height: Math.max(guide.u * 1.4, track.height)
      Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Math.max(2, Look.px(bar.progressStyle.height, guide.u))
        radius: Math.min(height / 2, Look.px(bar.progressStyle.radius, guide.u))
        color: bar.progressStyle.track || "transparent"
        Rectangle {
          height: parent.height
          radius: parent.radius
          width: bar.duration > 0 ? parent.width * Math.min(1, bar.shownAt / bar.duration) : 0
          color: bar.progressStyle.fill && typeof bar.progressStyle.fill === "object" ? bar.progressStyle.fill.from : (bar.progressStyle.fill || "transparent")
        }
      }
      // the mark you drag, while the pointer's on the bar
      Rectangle {
        visible: bar.held && bar.duration > 0
        width: guide.u * 1.1
        height: width
        radius: width / 2
        x: track.width * Math.min(1, bar.shownAt / Math.max(1, bar.duration)) - width / 2
        anchors.verticalCenter: track.verticalCenter
        color: bar.progressStyle.fill && typeof bar.progressStyle.fill === "object" ? bar.progressStyle.fill.from : (bar.progressStyle.fill || guide.ink)
      }
      MouseArea {
        id: scrub
        anchors.fill: parent
        anchors.topMargin: -guide.u * 0.6
        anchors.bottomMargin: -guide.u * 0.6
        enabled: bar.duration > 0
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onEntered: bar.guide.showVodBar()
        onPressed: function(mouse) { bar.dragFor = bar.guide.vod; bar.dragAt = bar.atX(mouse.x); bar.guide.showVodBar() }
        onPositionChanged: function(mouse) { if (pressed) { bar.dragAt = bar.atX(mouse.x); bar.guide.showVodBar() } }
        onReleased: function(mouse) { var to = bar.atX(mouse.x); var was = bar.dragFor; bar.dragAt = -1; bar.dragFor = null; if (was && bar.guide.vod === was) bar.guide.seekVodTo(to) }
        onCanceled: { bar.dragAt = -1; bar.dragFor = null }
      }
    }

    Item {
      width: parent.width
      height: hints.height
      Label {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: bar.hms(bar.shownAt) + (bar.duration > 0 ? " / " + bar.hms(bar.duration) : "")
        s: guide.look.vodTime
        unit: guide.u
      }
      KeyHints {
        id: hints
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        model: [{ keys: ["SPACE"], label: guide.vodPaused ? "Play" : "Pause" }, { keys: ["←", "→"], label: "10 s" },
                { keys: ["SHIFT", "+", "←", "→"], label: "1 min" }, { keys: ["HOME"], label: "Start" },
                { keys: ["P"], label: "Mini player" }, { keys: ["ESC"], label: "Back" }]
        size: guide.u * 1.3
        capStyle: guide.look.keycap
        labelStyle: guide.look.keyLabel
      }
      Label {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: bar.duration > 0 ? "−" + bar.hms(bar.duration - bar.shownAt) : ""
        s: guide.look.vodTime
        unit: guide.u
      }
    }
  }
}
