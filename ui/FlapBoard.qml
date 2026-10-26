import QtQuick
import "../Look.js" as Look

// The board layout (layout.list board): a split-flap departures board, a
// row per channel with what's on and its status, no time grid. The columns
// are the layout's (number, name, now, next, nextAt, left, status,
// category); each gets as many flaps as fit.
Item {
  id: board

  required property var guide
  property alias list: rows

  readonly property var layout: guide.layout
  readonly property var flap: guide.look.flapTile
  readonly property real rowH: Math.round(guide.u * layout.boardRowHeight)
  readonly property real tileH: Math.round(rowH * 0.78)
  // a channel's row: in tablet mode a finger tall, its flaps as they are
  readonly property real lineH: Math.round(guide.fingerRow(rowH))
  readonly property real step: Math.round(tileH * (flap.aspect || 0.66)) + Math.max(1, Math.round(Look.px(flap.gap, guide.u)))
  readonly property real columnGap: guide.u * 1.2
  // with logos on (L), a square logo before the name, in the room of this
  // many of its flaps (the column stays as wide)
  readonly property real flapGap: Math.max(1, Math.round(Look.px(flap.gap, guide.u)))
  readonly property int logoFlaps: Math.ceil((tileH + flapGap) / step)
  // columns that show on a board (bar is the table's)
  readonly property var columns: layout.columns.filter(function(c) { return c !== "bar" })

  // flaps per column: fixed ones, then the rest shared by name, now and next
  readonly property var counts: {
    var fixed = { number: 4, status: 9, nextAt: guide.layout.hours24 ? 5 : 8, left: 5, category: 10 }
    var weight = { name: 1, now: 2, next: 1.5 }
    var total = Math.floor((width - guide.u * 1.6 - columnGap * columns.length) / step)
    var out = {}
    var used = 0
    var shares = 0
    for (var i = 0; i < columns.length; i++) {
      var c = columns[i]
      if (fixed[c] !== undefined) { out[c] = fixed[c]; used += fixed[c] }
      else shares += weight[c] || 1
    }
    for (var j = 0; j < columns.length; j++)
      if (out[columns[j]] === undefined) out[columns[j]] = Math.max(4, Math.floor((total - used) * (weight[columns[j]] || 1) / Math.max(1, shares)))
    return out
  }

  function status(ch, show, recording) {
    if (!ch) return ""
    if (recording) return "● REC"      // this channel records: before Live, On air…
    if (show && show.live) return "Live"
    if (ch.state === "error") return "No signal"
    if (!show) return "Loading"
    if (show.end - guide.now < 300) return "Ending"
    if (show.start > guide.now) return "Next"
    return "On air"
  }

  function cell(c, item) {
    var ch = item.channel
    var show = item.show
    if (c === "number") return String(guide.numbers[item.r] || "")
    if (c === "name") return ch.name
    if (c === "now") return show ? guide.showTitle(show.title) : ""
    if (c === "next") return item.after ? guide.showTitle(item.after.title) : ""
    if (c === "nextAt") return item.after ? guide.clock(item.after.start) : ""
    if (c === "left") return show && !show.live ? Math.max(0, Math.ceil((show.end - guide.now) / 60)) + "m" : ""
    if (c === "status") return board.status(ch, show, item.recording)
    if (c === "category") return guide.categoryName(ch.category)
    return ""
  }

  // The columns' names
  Row {
    id: header
    x: guide.u * 1.6
    height: guide.u * 1.4
    spacing: board.columnGap
    Repeater {
      model: board.columns
      delegate: Item {
        required property string modelData
        width: board.counts[modelData] * board.step - Math.max(1, Math.round(Look.px(board.flap.gap, guide.u)))
        height: header.height
        Label {
          anchors.left: parent.modelData === "number" ? undefined : parent.left
          anchors.right: parent.modelData === "number" ? parent.right : undefined
          anchors.bottom: parent.bottom
          text: { return { number: "Ch", name: "Channel", now: "Now showing", next: "Then", nextAt: "Next", left: "Left", status: "Status", category: "Category" }[parent.modelData] }
          s: guide.look.tableHeader
          unit: guide.u
        }
      }
    }
  }

  ListView {
    id: rows
    y: header.height + guide.u * 0.4
    width: parent.width
    height: parent.height - y
    clip: true
    model: guide.visibleRows
    boundsBehavior: Flickable.StopAtBounds

    // a fixed height from the start, so the list makes only the rows it shows
    delegate: Item {
      id: rowItem
      required property int index
      required property int modelData
      readonly property int r: modelData
      readonly property var channel: guide.channels[r] || ({ name: "", state: "loading", category: "" })
      readonly property bool heads: guide.hasCategories
                                    && (index === 0 || (guide.channels[guide.visibleRows[index - 1]].category || "") !== (channel.category || ""))
      readonly property bool current: r === guide.row
      readonly property bool lockedNow: !!guide.channelLock && guide.channelLock.blocks(rowItem.channel)
      readonly property bool recording: guide.recordingOn(rowItem.channel)
      readonly property var show: current && guide.selected ? guide.selected : guide.showAt(r, guide.now)
      readonly property var after: show ? guide.nextShow(r, show) : null
      readonly property real headH: heads ? Math.round(guide.u * 1.6) : 0
      width: rows.width
      height: headH + board.lineH

      Label {
        visible: rowItem.heads
        x: guide.u * 0.4
        y: rowItem.headH - height - guide.u * 0.15
        text: guide.categoryName(rowItem.channel.category)
        s: guide.look.tableGroup
        unit: guide.u
      }

      Box {
        y: rowItem.headH
        width: parent.width
        height: board.lineH
        s: rowItem.current ? guide.look["tableRow:current"] : guide.look.tableRow
        unit: guide.u

        Row {
          x: guide.u * 1.6
          anchors.verticalCenter: parent.verticalCenter
          spacing: board.columnGap
          Repeater {
            model: board.columns
            delegate: Row {
              id: column
              required property string modelData
              readonly property bool withLogo: modelData === "name" && guide.showLogos
              anchors.verticalCenter: parent.verticalCenter
              spacing: board.flapGap
              Item {
                visible: column.withLogo
                width: board.logoFlaps * board.step - board.flapGap
                height: board.tileH
                ChannelLogo {
                  width: board.tileH
                  height: board.tileH
                  guide: board.guide
                  channel: rowItem.channel
                  locked: rowItem.lockedNow
                }
              }
              FlapText {
                count: board.counts[column.modelData] - (column.withLogo ? board.logoFlaps : 0)
                text: board.cell(column.modelData, rowItem)
                s: column.modelData === "status" ? guide.look["flapTile:status"] : board.flap
                textColor: column.modelData === "status" && text === "● REC" ? guide.look.channelRec.text.color
                         : column.modelData === "status" && (text === "Live" || text === "No signal") && guide.look.liveTag.text.color !== "inherit"
                           ? guide.look.liveTag.text.color : undefined
                alignRight: column.modelData === "number" || column.modelData === "left"
                tileHeight: board.tileH
                unit: guide.u
              }
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          // tablet mode: a tap on the channel already chosen watches it
          onClicked: {
            if (guide.touchMode && !guide.managing && guide.row === rowItem.r) { guide.watch(rowItem.r); return }
            guide.row = rowItem.r
            if (guide.managing) guide.toggleMark(rowItem.r)
          }
          onDoubleClicked: if (!guide.managing) guide.watch(rowItem.r)   // (a quick second tap too)
        }
      }
    }
  }
}
