import QtQuick
import "../Look.js" as Look
import "../Dvr.js" as Dvr

// An item's details, over the library or Search (Enter on a movie or a
// series): its poster, what it is, where you stopped, a series' episodes as
// TV-style rows, and Play or Resume; a recording's state, why it stopped,
// and its choices as rows (Play, Start over, Delete…; Watch live, Stop
// recording while it records). Styled by the box, menu, player and
// recording elements.
Box {
  id: details

  required property var guide
  readonly property real u: guide.u

  readonly property var card: guide.libDetail
  readonly property bool series: !!card && card.kind === "series"
  readonly property var episode: series ? card.episodes[guide.libEpisode] : null
  readonly property string playId: !card ? "" : series ? (episode ? episode.id : "") : card.id
  readonly property real resume: playId ? guide.libResumeAt(playId) : 0
  readonly property bool recording: !!card && card.kind === "recording"
  readonly property var rec: guide.libDetailRec
  // a recording as it is now (stopped, done), for its title and lines
  readonly property var shown: recording && guide.libDetailRecCard ? guide.libDetailRecCard : card
  readonly property string recState: rec ? Dvr.stateOf(rec) : ""

  function hms(t) {
    t = Math.max(0, Math.floor(t))
    var h = Math.floor(t / 3600)
    var m = Math.floor((t % 3600) / 60)
    var s = t % 60
    return (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (s < 10 ? "0" : "") + s
  }

  visible: card !== null && !guide.watching && (guide.screen === "library" || guide.screen === "search")
  s: guide.look.scrim
  unit: u
  MouseArea { anchors.fill: parent; onClicked: guide.libDetail = null }

  Box {
    id: panel
    anchors.centerIn: parent
    width: Math.min(parent.width - details.u * 8, details.u * 80)
    height: Math.min(parent.height - details.u * 4, Math.max(poster.height, info.implicitHeight) + panel.padding * 2)
    s: guide.look.box
    unit: details.u
    image: guide.areaImages.box
    MouseArea { anchors.fill: parent }

    Image {
      id: poster
      x: panel.padding
      y: panel.padding
      width: details.u * 18
      height: implicitWidth > 0 ? Math.min(details.u * 28, width * implicitHeight / implicitWidth) : details.u * 10
      source: !details.card ? "" : guide.posterFor(details.card.entry || { poster: details.card.poster, videoId: details.card.videoId, live: details.card.live })
                                   || (details.recording ? details.card.logo || "" : "")
      fillMode: Image.PreserveAspectFit
      verticalAlignment: Image.AlignTop
      asynchronous: true
    }

    Column {
      id: info
      anchors.left: poster.right
      anchors.leftMargin: details.u * 2
      anchors.right: parent.right
      anchors.rightMargin: panel.padding
      y: panel.padding
      spacing: details.u * 0.9

      Label {
        width: parent.width
        text: details.card ? guide.showTitle(details.shown.title) : ""
        s: guide.look.boxTitle
        unit: details.u
        sizeFactor: 1.35
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
      }
      Label {
        width: parent.width
        visible: text !== ""
        text: !details.card ? "" : details.series ? details.card.sub : (details.shown.entry || {}).subtitle || details.shown.sub || ""
        s: guide.look.vodInfo
        unit: details.u
        sizeFactor: 1.15
      }
      Label {
        width: parent.width
        visible: text !== ""
        text: !details.card ? "" : details.series ? (details.episode ? details.episode.description : "") : (details.shown.entry || {}).description || ""
        s: guide.look.boxText
        unit: details.u
        sizeFactor: 1.12
        wrapMode: Text.Wrap
        maximumLineCount: details.series ? 3 : 8
        elide: Text.ElideRight
      }
      // a recording: its state, and why, if it didn't go as planned
      Row {
        visible: details.recording
        spacing: details.u * 0.8
        Box {
          id: stateBox
          readonly property string stateKey: details.recState === "Recording" || details.recState === "Saving" ? ":recording"
                                           : details.recState === "Scheduled" ? ":scheduled" : Dvr.needsYou(details.rec) ? ":attention" : ""
          width: stateText.implicitWidth + stateBox.padding * 2
          height: stateText.implicitHeight + stateBox.padding * 0.6
          s: guide.look["recordingState" + stateKey] || guide.look.recordingState
          unit: details.u
          Label {
            id: stateText
            anchors.centerIn: parent
            text: details.recState + (details.rec && Dvr.active(details.rec) && details.rec.kind !== "youtube-video" ? " until " + guide.clock(details.rec.end)
                                      : details.rec && Dvr.waiting(details.rec) && details.rec.show ? " · " + guide.dayTime(details.rec.show.start) + " – " + guide.clock(details.rec.show.end) : "")
            s: guide.look["recordingState" + stateBox.stateKey] || guide.look.recordingState
            unit: details.u
          }
        }
        Label {
          anchors.verticalCenter: parent.verticalCenter
          width: info.width - stateBox.width - parent.spacing   // wrapped beside the state, inside the box
          wrapMode: Text.Wrap
          visible: text !== ""
          text: !details.rec ? "" : details.recState === "Drive missing" ? "It's on " + (details.rec.placeLabel || "a drive") + ": plug it in to watch."
              : details.rec.state === "failed" || details.rec.state === "incomplete" || details.rec.state === "missed" || details.rec.state === "conflict" ? guide.recReason(details.rec)
              : Dvr.active(details.rec) && details.rec.sleepUnprotected ? "This computer may go to sleep during it: sleep protection is unavailable." : ""
          s: guide.look.boxText
          unit: details.u
        }
      }
      Label {
        visible: details.resume > 0 && !details.recording
        text: "You stopped at " + details.hms(details.resume)
        s: guide.look.vodTime
        unit: details.u
        sizeFactor: 1.15
      }

      // A series' episodes
      ListView {
        id: episodes
        visible: details.series
        readonly property real rowH: Math.round(Look.px(guide.look.menuRow.height, details.u * 0.8))
        width: parent.width
        height: visible ? Math.min(count, 5) * (rowH + spacing) : 0
        clip: true
        spacing: Math.round(details.u * 0.3)
        model: details.series ? details.card.episodes : []
        currentIndex: guide.libEpisode
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: 0
        preferredHighlightEnd: height - rowH
        delegate: MenuRow {
          required property var modelData
          required property int index
          guide: details.guide
          width: episodes.width
          height: implicitHeight
          size: 0.8
          focused: index === guide.libEpisode
          label: "S" + modelData.season + " E" + modelData.episode + "   " + modelData.title
          value: guide.libFinished(modelData.id) ? "✓ Watched" : guide.libProgress(modelData.id) > 0.01 ? Math.round(guide.libProgress(modelData.id) * 100) + "%" : ""
          onActivated: {
            if (guide.libEpisode === index) guide.libPlay(false)
            else guide.libEpisode = index
          }
        }
      }

      // a recording's choices
      Column {
        visible: details.recording
        width: parent.width
        spacing: Math.round(details.u * 0.3)
        Repeater {
          model: details.recording ? guide.recActions : []
          delegate: MenuRow {
            required property var modelData
            required property int index
            guide: details.guide
            width: parent.width
            height: implicitHeight
            size: 0.8
            element: "recordChoice"
            focused: index === guide.libEpisode
            danger: modelData.danger === true
            label: modelData.label
            onActivated: {
              if (guide.libEpisode === index) guide.recAct(index)
              else guide.libEpisode = index
            }
          }
        }
      }

      KeyHints {
        visible: details.recording
        touchGuide: details.guide
        touchWidth: parent.width
        model: [{ keys: ["↑", "↓"], label: "Choose" }, { keys: ["ENTER"], label: "Pick" }, { keys: ["ESC"], label: "Back", touch: { key: Qt.Key_Escape, back: true } }]
        size: details.u * 1.55
        capStyle: guide.look.keycap
        labelStyle: guide.look.keyLabel
      }
      KeyHints {
        visible: !details.recording
        touchGuide: details.guide
        touchWidth: parent.width
        model: [{ keys: ["ENTER"], label: details.resume > 0 ? "Resume" : "Play", touch: { key: Qt.Key_Return, primary: true, icon: "playsolid" } }]
               .concat(details.resume > 0 ? [{ keys: ["R"], label: "Start over", touch: { key: Qt.Key_R } }] : [])
               .concat(details.series ? [{ keys: ["↑", "↓"], label: "Episode" }] : [])
               .concat([{ keys: ["L"], label: details.playId && guide.inLibraryList(details.playId) ? "Take off My List" : "Add to My List", touch: { key: Qt.Key_L, icon: "bookmark" } },
                        { keys: ["ESC"], label: "Back", touch: { key: Qt.Key_Escape, back: true } }])
        size: details.u * 1.55
        capStyle: guide.look.keycap
        labelStyle: guide.look.keyLabel
      }
    }
  }
}
