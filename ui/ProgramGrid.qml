import QtQuick
import "../Look.js" as Look

// The grid: the time bar, then a row per channel (in category bands) with
// its shows across the hours shown, and the line marking now.
Item {
  id: gridArea

  required property var guide
  property alias list: rows

  readonly property real laneW: width - guide.chanW
  readonly property real slotW: laneW / guide.slotsShown
  readonly property bool inRow: guide.layout.channelCell === "row"
  // the space after ● LIVE: three spaces of the cell's text
  readonly property real liveGap: spaces.advanceWidth

  TextMetrics {
    id: spaces
    font.family: guide.look.programCell.text.font
    font.pixelSize: Math.max(1, guide.look.programCell.text.size * guide.u)
    text: "   "
  }
  TextMetrics {
    id: numberWidth
    font.family: guide.look.channelNumber.text.font
    font.pixelSize: Math.max(1, guide.look.channelNumber.text.size * guide.u)
    font.weight: guide.look.channelNumber.text.weight
    text: guide.managing ? "□ 0000" : "0000"
  }

  // Time header: the date, then the times. A picture runs across all of it.
  Item {
    id: timeHeader
    width: parent.width
    height: guide.u * guide.layout.timeBarHeight

    Box {
      id: dateCell
      width: guide.chanW - guide.gap
      height: parent.height - guide.gap
      s: guide.look.timeBar
      unit: guide.u
      clip: true
      AreaImage {
        width: timeHeader.width
        height: parent.height
        spec: guide.areaImages.header
      }
      Label {
        anchors.centerIn: parent
        text: Qt.formatDateTime(new Date(guide.windowStart * 1000), "ddd MMM d")
        s: guide.look.timeBar
        unit: guide.u
      }
    }

    Repeater {
      model: guide.slotsShown
      delegate: Box {
        id: timeCell
        required property int index
        x: guide.chanW + index * gridArea.slotW
        width: gridArea.slotW - guide.gap
        height: timeHeader.height - guide.gap
        s: guide.look.timeBar
        unit: guide.u
        clip: true
        AreaImage {
          x: -parent.x
          width: timeHeader.width
          height: parent.height
          spec: guide.areaImages.header
        }
        Label {
          anchors.left: parent.left
          anchors.leftMargin: timeCell.padding
          anchors.verticalCenter: parent.verticalCenter
          text: guide.clock(guide.windowStart + timeCell.index * guide.slot)
          s: guide.look.timeBar
          unit: guide.u
        }
      }
    }
  }

  // Tablet mode: a finger dragged sideways moves through time, a half hour
  // for each half hour's width (up and down, the list scrolls itself). It
  // only watches until the drag is sideways, so taps reach the shows.
  Item {
    anchors.fill: parent
    z: 10
    DragHandler {
      id: timeDrag
      enabled: guide.touchMode
      target: null
      xAxis.enabled: true
      yAxis.enabled: false
      property int from: 0
      onActiveChanged: if (active) from = guide.slotOffset
      onActiveTranslationChanged: if (active) guide.dragTime(from - Math.round(activeTranslation.x / Math.max(1, gridArea.slotW)))
    }
  }

  ListView {
    id: rows
    y: timeHeader.height
    width: parent.width
    height: parent.height - y
    clip: true
    model: guide.visibleRows
    boundsBehavior: Flickable.StopAtBounds

    delegate: Item {
      id: rowItem
      required property int index        // the row in the grid
      required property int modelData    // the channel, by index into guide.channels
      readonly property int r: modelData
      readonly property var channel: guide.channels[r] || ({ name: "", state: "loading", category: "" })
      readonly property var shows: guide.showsFor(r)
      readonly property bool lockedNow: !!guide.channelLock && guide.channelLock.blocks(rowItem.channel)
      readonly property bool recording: guide.recordingOn(rowItem.channel)
      readonly property bool heads: guide.hasCategories
                                    && (index === 0 || (guide.channels[guide.visibleRows[index - 1]].category || "") !== (channel.category || ""))
      readonly property real band: heads ? guide.u * guide.layout.bandHeight : 0
      readonly property bool current: r === guide.row
      readonly property bool marked: !!guide.marked[channel.url]

      width: rows.width
      height: guide.rowH + band

      // A category's band
      Box {
        id: bandBox
        visible: rowItem.heads
        width: parent.width - guide.gap
        height: rowItem.band - guide.gap
        s: guide.look.band
        unit: guide.u
        image: guide.areaImages.band

        Label {
          anchors.left: parent.left
          anchors.leftMargin: bandBox.padding
          anchors.verticalCenter: parent.verticalCenter
          text: guide.categoryName(rowItem.channel.category)
          s: guide.look.band
          unit: guide.u
        }
      }

      Item {
        y: rowItem.band
        width: parent.width
        height: guide.rowH

      Box {
        id: chanBox
        width: guide.chanW - guide.gap
        height: parent.height - guide.gap
        s: rowItem.current && rowItem.marked ? Look.merge(guide.look["channelCell:current"], { border: guide.look["channelCell:marked"].border })
         : rowItem.marked ? guide.look["channelCell:marked"]
         : rowItem.current ? guide.look["channelCell:current"] : guide.look.channelCell
        unit: guide.u
        image: rowItem.current ? null : guide.areaImages.channelCell

        Row {
          anchors.left: parent.left
          anchors.leftMargin: chanBox.padding
          anchors.verticalCenter: parent.verticalCenter
          spacing: guide.u * 0.5

          // In a row: the number first, as wide as four digits
          Label {
            visible: gridArea.inRow
            anchors.verticalCenter: parent.verticalCenter
            width: numberWidth.advanceWidth
            horizontalAlignment: Text.AlignRight
            text: (guide.managing ? (rowItem.marked ? "■ " : "□ ") : "") + (guide.numbers[rowItem.r] || "")
            s: guide.look.channelNumber
            unit: guide.u
          }

          // The channel's logo, or its initial until there is one (always, in a row)
          Box {
            id: logoBox
            visible: guide.showLogos || gridArea.inRow
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? guide.rowH - guide.u : 0
            height: width
            s: guide.look.logoBadge
            unit: guide.u

            Label {
              anchors.centerIn: parent
              visible: logo.status !== Image.Ready && !rowItem.lockedNow
              text: rowItem.channel.name.charAt(0).toUpperCase()
              s: guide.look.logoBadge
              unit: guide.u
            }
            // a locked channel: a lock, not its logo
            Icon {
              anchors.centerIn: parent
              visible: rowItem.lockedNow
              name: "lock"
              size: parent.height * 0.62
              stroke: 1.8
              color: guide.look.logoBadge.text.color
            }
            Image {
              id: logo
              anchors.fill: parent
              anchors.margins: Math.max(1, logoBox.borderWidth)
              source: guide.showLogos ? guide.logoSource(rowItem.channel) : ""
              sourceSize.width: 96
              sourceSize.height: 96
              // YouTube avatars are square; IPTV logos are often wide.
              fillMode: rowItem.channel.kind === "iptv" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
              asynchronous: true
              smooth: true
            }
          }

          Grid {
            anchors.verticalCenter: parent.verticalCenter
            columns: guide.showLogos || gridArea.inRow ? 1 : 2
            columnSpacing: guide.u * 0.6
            verticalItemAlignment: Grid.AlignVCenter

          Label {
            visible: !gridArea.inRow
            text: (guide.managing ? (rowItem.marked ? "■ " : "□ ") : "") + (guide.numbers[rowItem.r] || "")
            s: guide.look.channelNumber
            unit: guide.u
            sizeFactor: guide.showLogos ? 1.1 / 1.6 : guide.managing ? 1.2 / 1.6 : 1
          }
          Label {
            width: (gridArea.inRow ? guide.chanW - chanBox.padding * 2 - numberWidth.advanceWidth - logoBox.width - guide.u * 1.5
                 : guide.showLogos ? guide.chanW - logoBox.width - guide.u * 2.1
                 : guide.chanW - guide.u * (guide.managing ? 6 : 4.5)) - (chanRec.visible ? chanRec.implicitWidth + guide.u * 0.6 : 0)
            text: rowItem.channel.name
            s: guide.look.channelName
            unit: guide.u
            sizeFactor: guide.showLogos ? 0.85 / 0.95 : 1
            elide: Text.ElideRight
          }
          }
        }

        // ● REC while this channel records
        Label {
          id: chanRec
          visible: rowItem.recording
          anchors.right: parent.right
          anchors.rightMargin: chanBox.padding
          anchors.verticalCenter: parent.verticalCenter
          text: "● REC"
          s: guide.look.channelRec
          unit: guide.u
        }

        Rectangle {
          visible: rowItem.r === guide.tunedRow && guide.reception !== "off"
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: guide.gap * 2
          width: guide.u * 0.6
          height: width
          radius: width / 2
          color: guide.nowLine
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            guide.row = rowItem.r
            if (guide.managing) guide.toggleMark(rowItem.r)
            else guide.watch(rowItem.r)
          }
        }
      }

      Item {
        id: lane
        x: guide.chanW
        width: gridArea.laneW
        height: parent.height
        clip: true

        Repeater {
          model: rowItem.shows
          delegate: Box {
            id: cell
            required property var modelData
            readonly property real x0: Math.max(0, (modelData.start - guide.windowStart) / guide.span * lane.width)
            readonly property real x1: Math.min(lane.width, (modelData.end - guide.windowStart) / guide.span * lane.width)
            readonly property bool picked: rowItem.current && guide.selected !== null && guide.selected.start === modelData.start

            x: x0
            width: Math.max(0, x1 - x0 - guide.gap)
            height: lane.height - guide.gap
            s: picked ? guide.look["programCell:selected"] : guide.look.programCell
            unit: guide.u
            image: picked ? null : guide.areaImages.cell

            // ● LIVE, in its own color if the theme gives it one
            Label {
              id: liveTag
              visible: cell.modelData.live === true && parent.width > guide.u * 3
              anchors.left: parent.left
              anchors.leftMargin: cell.padding
              anchors.verticalCenter: parent.verticalCenter
              text: "● Live"
              s: guide.look.liveTag
              unit: guide.u
              color: s.text.color === "inherit" ? cell.s.text.color : s.text.color
            }
            // ● Recording, Scheduled or Conflict: what's happening to the show, in words
            readonly property string rec: guide.recMark(rowItem.channel, modelData)
            Label {
              id: recTag
              visible: cell.rec !== "" && parent.width > guide.u * 3
              anchors.right: parent.right
              anchors.rightMargin: cell.padding
              anchors.verticalCenter: parent.verticalCenter
              text: cell.rec === "recording" ? (parent.width > guide.u * 10 ? "● Recording" : "●") : cell.rec === "conflict" ? "Conflict" : "Scheduled"
              s: cell.rec === "recording" ? guide.look["recordDot:recording"] : guide.look.recordDot
              unit: guide.u
              color: s.text.color === "inherit" ? cell.s.text.color : s.text.color
            }
            Label {
              visible: parent.width > guide.u * 3
              anchors.fill: parent
              anchors.leftMargin: cell.padding + (liveTag.visible ? liveTag.implicitWidth + gridArea.liveGap : 0)
              anchors.rightMargin: cell.padding + (recTag.visible ? recTag.implicitWidth + gridArea.liveGap : 0)
              verticalAlignment: Text.AlignVCenter
              text: cell.modelData.live ? guide.showTitle(cell.modelData.title)
                    : (cell.modelData.start < guide.windowStart ? "◀ " : "") + guide.showTitle(cell.modelData.title)
                      + (cell.modelData.end > guide.windowEnd ? " ▶" : "")
              s: cell.s
              unit: guide.u
              elide: Text.ElideRight
              maximumLineCount: 2
              wrapMode: Text.Wrap
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              // tablet mode: a tap on the show already chosen watches it, and
              // holding a finger on one opens its choices (as Record…)
              readonly property bool chosen: guide.row === rowItem.r && !!guide.selected && guide.selected.start === cell.modelData.start
              onClicked: {
                if (guide.touchMode && chosen) { guide.watch(rowItem.r); return }
                guide.row = rowItem.r
                guide.cursorTime = Math.max(cell.modelData.start, guide.windowStart)
              }
              onDoubleClicked: guide.watch(rowItem.r)
              onPressAndHold: {
                if (!guide.touchMode) return
                guide.row = rowItem.r
                guide.cursorTime = Math.max(cell.modelData.start, guide.windowStart)
                guide.openShowChoices()
              }
            }
          }
        }

        Rectangle {
          visible: rowItem.channel.state !== "ready" && !rowItem.channel.live
          width: lane.width - guide.gap
          height: lane.height - guide.gap
          color: guide.cell
          opacity: 0.6
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: rowItem.channel.state === "error" ? "NO SIGNAL" : "LOADING LISTINGS…"
            color: guide.dimInk
            font.family: guide.fonts.body
            font.pixelSize: guide.u * 0.95
          }
        }
      }
      }
    }
  }

  // Now
  Rectangle {
    visible: guide.look.nowLine.style !== "none" && guide.now >= guide.windowStart && guide.now < guide.windowEnd
    x: guide.chanW + (guide.now - guide.windowStart) / guide.span * gridArea.laneW - width / 2
    y: 0
    width: Math.max(2, Look.px(guide.look.nowLine.width, guide.u))
    height: guide.look.nowLine.style === "tick" ? timeHeader.height - guide.gap : timeHeader.height + Math.min(rows.contentHeight, rows.height)
    color: guide.look.nowLine.color
  }
}
