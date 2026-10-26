import QtQuick
import "../Look.js" as Look

// Rows of cards you move through with the arrows: posters (movies) or 16:9
// pictures (videos, channels), each with its title, how far in you are,
// Live, Watched and My List. The library and Search show their results in
// them. Styled by the library elements (rowTitle, posterCard, posterTitle,
// posterSub, liveBadge, cardBadge, vodProgress); a recording's card by the
// recording ones (recordingCard, recordingState, recordingProgress).
ListView {
  id: rowsView

  required property var guide
  property real u: guide.u
  property var rows: []               // [{ key, title, shape: "poster"|"thumb", cards }]
  property int rowIndex: 0
  property var cols: ({})             // row key -> the card the cursor is on in it
  property bool active: true          // the cursor shows (false while you type, say)
  signal select(int row, int col)     // a click
  signal open(int row, int col)       // a double click

  readonly property real posterW: Math.round(u * guide.layout.libraryPosterWidth)
  readonly property real posterH: Math.round(posterW * 1.5)
  readonly property real thumbW: Math.round(u * guide.layout.libraryThumbWidth)
  readonly property real thumbH: Math.round(thumbW * 9 / 16)
  readonly property real titleH: Math.round(u * 2.6)
  readonly property real captionH: Math.round(u * 3.4)
  readonly property var bar: guide.look.vodProgress

  function imageH(shape) { return shape === "poster" ? posterH : thumbH }
  function cardW(shape) { return shape === "poster" ? posterW : thumbW }
  function rowHeight(shape) { return titleH + imageH(shape) + captionH + Math.round(u * 1.6) }

  clip: true
  model: rows
  currentIndex: rowIndex
  highlightRangeMode: ListView.ApplyRange
  preferredHighlightBegin: 0
  preferredHighlightEnd: Math.max(0, height - rowHeight("poster"))
  highlightMoveDuration: 220
  boundsBehavior: Flickable.StopAtBounds

  // fixed heights from the start, so only the rows on screen are made
  delegate: Item {
    id: rowItem
    required property var modelData
    required property int index
    readonly property bool currentRow: rowsView.active && index === rowsView.rowIndex
    readonly property int col: Math.min(modelData.cards.length - 1, rowsView.cols[modelData.key] || 0)
    readonly property string shape: modelData.shape
    width: rowsView.width
    height: rowsView.rowHeight(shape)

    Row {
      x: rowsView.u * 2
      height: rowsView.titleH
      spacing: rowsView.u * 0.8
      Label {
        anchors.verticalCenter: parent.verticalCenter
        text: rowItem.modelData.title
        s: guide.look.rowTitle
        unit: rowsView.u
      }
      Label {
        anchors.verticalCenter: parent.verticalCenter
        text: String(rowItem.modelData.cards.length) + (rowItem.modelData.more ? "+" : "")
        s: guide.look.posterSub
        unit: rowsView.u
      }
    }

    ListView {
      id: cards
      y: rowsView.titleH
      width: parent.width
      height: parent.height - rowsView.titleH
      orientation: ListView.Horizontal
      spacing: rowsView.u * 1.2
      leftMargin: rowsView.u * 2
      rightMargin: rowsView.u * 2
      topMargin: rowsView.u * 0.5
      model: rowItem.modelData.cards
      currentIndex: rowItem.col
      highlightRangeMode: ListView.ApplyRange
      preferredHighlightBegin: rowsView.u * 2
      preferredHighlightEnd: width - rowsView.u * 2 - rowsView.cardW(rowItem.shape)
      highlightMoveDuration: 200
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      delegate: Item {
        id: card
        required property var modelData
        required property int index
        readonly property bool current: rowItem.currentRow && index === rowItem.col
        readonly property bool isChannel: modelData.kind === "channel"
        readonly property bool isRec: modelData.kind === "recording"
        // recording now: how far to its stop time
        readonly property real recProgress: isRec ? (modelData.recProgress || 0) : 0
        // a channel's card: how far into the show; anything else: how far you watched
        readonly property real progress: isChannel ? (modelData.progress || 0) : guide.libProgress(modelData.id)
        readonly property bool finished: !isChannel && guide.libFinished(modelData.id)
        readonly property bool listed: !isChannel && guide.inLibraryList(modelData.id)
        width: rowsView.cardW(rowItem.shape)
        height: rowsView.imageH(rowItem.shape) + rowsView.captionH

        Box {
          id: frame
          width: parent.width
          height: rowsView.imageH(rowItem.shape)
          readonly property string recKind: card.isRec && (card.modelData.recState === "Scheduled" || card.modelData.recState === "Conflict") ? "upcomingRecording" : "recordingCard"
          s: card.isRec ? (card.current ? guide.look[recKind + ":current"] : guide.look[recKind])
                        : card.current ? guide.look["posterCard:current"] : guide.look.posterCard
          unit: rowsView.u
          scale: card.current ? 1.05 : 1
          Behavior on scale { NumberAnimation { duration: 140 } }
          z: card.current ? 2 : 0

          Image {
            id: picture
            anchors.fill: parent
            // a channel's logo shows whole; pictures fill
            anchors.margins: card.isChannel && !card.modelData.videoId ? rowsView.u * 1.2 : frame.borderWidth
            source: guide.posterFor(card.modelData.entry || { poster: card.modelData.poster, videoId: card.modelData.videoId, live: card.modelData.live })
            sourceSize.width: 360
            fillMode: card.isChannel && !card.modelData.videoId ? Image.PreserveAspectFit : Image.PreserveAspectCrop
            asynchronous: true
            clip: true
          }
          // a channel's card without its picture (not yet, or none): its logo, whole
          Image {
            id: logoPicture
            anchors.fill: parent
            anchors.margins: rowsView.u * 1.2
            visible: picture.status !== Image.Ready
            source: picture.status !== Image.Ready && (card.isChannel || card.isRec) ? card.modelData.logo || "" : ""
            sourceSize.width: 192
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }
          // no picture: the title, large
          Label {
            anchors.fill: parent
            anchors.margins: rowsView.u * 0.8
            visible: picture.status !== Image.Ready && logoPicture.status !== Image.Ready
            text: guide.showTitle(card.modelData.title)
            s: guide.look.posterTitle
            unit: rowsView.u
            sizeFactor: 1.3
            wrapMode: Text.Wrap
            maximumLineCount: 5
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
          }
          // a recording's state (Recording, Failed…), and how far it is to its stop time
          Box {
            id: recState
            readonly property string word: card.isRec ? card.modelData.recState || "" : ""
            readonly property string sk: word === "Recording" || word === "Saving" ? ":recording" : word === "Scheduled" ? ":scheduled"
                                       : word === "Failed" || word === "Missed" || word === "Incomplete" || word === "Conflict" || word === "Drive missing" ? ":attention" : ""
            visible: word !== "" && word !== "Done"
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: rowsView.u * 0.4
            width: recWord.implicitWidth + recState.padding * 2
            height: recWord.implicitHeight + recState.padding * 0.6
            s: guide.look["recordingState" + sk] || guide.look.recordingState
            unit: rowsView.u
            Label {
              id: recWord
              anchors.centerIn: parent
              text: (recState.sk === ":recording" ? "● " : "") + recState.word
              s: guide.look["recordingState" + recState.sk] || guide.look.recordingState
              unit: rowsView.u
            }
          }
          Rectangle {
            readonly property var rb: guide.look.recordingProgress || ({})
            visible: card.recProgress > 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: frame.borderWidth
            height: Math.max(3, Look.px(rb.height, rowsView.u))
            color: rb.track || "transparent"
            Rectangle {
              height: parent.height
              width: parent.width * card.recProgress
              color: parent.rb.fill && typeof parent.rb.fill === "object" ? parent.rb.fill.from : (parent.rb.fill || "transparent")
            }
          }
          // how far in
          Rectangle {
            visible: card.progress > 0.01 && !card.finished && card.recProgress <= 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: frame.borderWidth
            height: Math.max(3, Look.px(rowsView.bar.height, rowsView.u))
            color: rowsView.bar.track || "transparent"
            Rectangle {
              height: parent.height
              width: parent.width * card.progress
              color: rowsView.bar.fill && typeof rowsView.bar.fill === "object" ? rowsView.bar.fill.from : (rowsView.bar.fill || "transparent")
            }
          }
          // live
          Box {
            id: liveBadge
            visible: card.modelData.live === true
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: rowsView.u * 0.5
            width: liveText.implicitWidth + liveBadge.padding * 2
            height: liveText.implicitHeight + liveBadge.padding * 0.6
            s: guide.look.liveBadge
            unit: rowsView.u
            Label {
              id: liveText
              anchors.centerIn: parent
              text: "● Live"
              s: guide.look.liveBadge
              unit: rowsView.u
            }
          }
          // watched, and in My List
          Box {
            id: badge
            visible: !liveBadge.visible && (card.finished || card.listed)
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: rowsView.u * 0.4
            width: mark.implicitWidth + badge.padding * 2
            height: mark.implicitHeight + badge.padding * 0.6
            s: guide.look.cardBadge
            unit: rowsView.u
            Label {
              id: mark
              anchors.centerIn: parent
              text: (card.finished ? "✓ Watched" : "") + (card.finished && card.listed ? "  ·  " : "") + (card.listed ? "My List" : "")
              s: guide.look.cardBadge
              unit: rowsView.u
            }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // a click picks, a double click opens; a finger opens at once
            onClicked: function(mouse) { rowsView.select(rowItem.index, card.index); if (rowsView.guide.isFinger(mouse)) rowsView.open(rowItem.index, card.index) }
            onDoubleClicked: function(mouse) { if (!rowsView.guide.isFinger(mouse)) rowsView.open(rowItem.index, card.index) }
          }
        }

        Column {
          y: rowsView.imageH(rowItem.shape) + rowsView.u * 0.6
          width: parent.width
          spacing: rowsView.u * 0.15
          Label {
            width: parent.width
            text: guide.showTitle(card.modelData.title)
            s: guide.look.posterTitle
            unit: rowsView.u
            elide: Text.ElideRight
          }
          Label {
            width: parent.width
            visible: text !== ""
            text: card.modelData.sub || ""
            s: guide.look.posterSub
            unit: rowsView.u
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
