import QtQuick
import QtQuick.Effects
import "../Look.js" as Look

// The table layout (layout.list table), like a terminal app: a pane with
// the channels as a table (in category groups), a pane with the preview,
// and a pane with the lineup of the channel under the cursor. The columns
// are the layout's: number, name, now, next, left, bar, category.
Item {
  id: table

  required property var guide
  property alias list: rows
  property alias videoSlot: previewSlot

  readonly property var layout: guide.layout
  readonly property real rowH: Math.round(guide.u * layout.tableRowHeight)
  readonly property real titleRoom: guide.u * 0.7     // the pane names stick up into the gap above

  // A text style shrunk, if need be, to fit a row
  function fit(s) { return Math.min(1, table.rowH * 0.68 / Math.max(1, (s.text ? s.text.size : 1) * guide.u)) }

  function minutesLeft(show) {
    if (!show || show.live) return ""
    var m = Math.ceil((show.end - guide.now) / 60)
    return m >= 60 ? Math.floor(m / 60) + "h" + (m % 60 ? m % 60 + "m" : "") : Math.max(0, m) + "m"
  }

  // How wide each column is: fixed ones, then name and category a share,
  // now and next what's left
  readonly property var columnWidths: {
    var cols = layout.columns
    var w = channels.width - channels.padding * 2 - guide.u * 1.6
    var fixed = { number: guide.u * 3.4, left: guide.u * 3.4, bar: Look.px(guide.look.rowProgress.width, guide.u) + guide.u * 0.6 }
    var share = { name: 0.3, category: 0.2 }
    var out = {}
    var used = 0
    var flex = 0
    for (var i = 0; i < cols.length; i++) {
      var c = cols[i]
      if (fixed[c] !== undefined) { out[c] = fixed[c]; used += fixed[c] }
      else if (share[c] !== undefined) { out[c] = w * share[c]; used += out[c] }
      else flex++
    }
    for (var j = 0; j < cols.length; j++) if (out[cols[j]] === undefined) out[cols[j]] = Math.max(guide.u * 4, (w - used) / Math.max(1, flex))
    return out
  }

  Pane {
    id: channels
    guide: table.guide
    y: table.titleRoom
    width: Math.round(table.width * table.layout.tableWidth)
    height: table.height - y
    title: "channels"
    note: String(guide.visibleRows.length)

    // The columns' names
    Row {
      id: header
      x: guide.u * 1.6
      height: table.rowH
      Repeater {
        model: table.layout.columns
        delegate: Item {
          required property string modelData
          width: table.columnWidths[modelData]
          height: header.height
          Label {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.modelData === "number" || parent.modelData === "left" ? parent.right : undefined
            anchors.rightMargin: parent.modelData === "number" || parent.modelData === "left" ? guide.u * 0.8 : 0
            text: { return { number: "ch", name: "name", now: "now", next: "next", left: "left", bar: "", category: "category" }[parent.modelData] }
            s: guide.look.tableHeader
            unit: guide.u
          }
        }
      }
    }

    ListView {
      id: rows
      y: header.height
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
        readonly property var show: guide.showAt(r, guide.now)
        readonly property var after: show ? guide.nextShow(r, show) : null
        readonly property real headH: heads ? Math.round(table.rowH * 1.25) : 0
        width: rows.width
        height: headH + table.rowH

        // ▾ news 2
        Item {
          visible: rowItem.heads
          width: parent.width
          height: rowItem.headH
          Row {
            anchors.left: parent.left
            anchors.leftMargin: guide.u * 0.4
            anchors.bottom: parent.bottom
            anchors.bottomMargin: table.rowH * 0.12
            spacing: guide.u * 0.6
            Label {
              text: "▾ " + guide.categoryName(rowItem.channel.category)
              s: guide.look.tableGroup
              unit: guide.u
              sizeFactor: table.fit(guide.look.tableGroup)
            }
            Label {
              text: String(guide.categoryCounts[rowItem.channel.category || ""] || "")
              s: guide.look.tableDim
              unit: guide.u
              sizeFactor: table.fit(guide.look.tableDim)
            }
          }
        }

        Box {
          id: rowBox
          y: rowItem.headH
          width: parent.width
          height: table.rowH
          s: rowItem.current ? guide.look["tableRow:current"] : guide.look.tableRow
          unit: guide.u

          Label {
            visible: rowItem.current
            x: guide.u * 0.4
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            s: guide.look.rowMarker
            unit: guide.u
            sizeFactor: table.fit(guide.look.rowMarker)
          }

          Row {
            x: guide.u * 1.6
            height: parent.height
            Repeater {
              model: table.layout.columns
              delegate: Item {
                id: cellItem
                required property string modelData
                width: table.columnWidths[modelData]
                height: rowBox.height
                readonly property bool live: !!rowItem.show && rowItem.show.live === true

                Label {
                  visible: cellItem.modelData === "number"
                  anchors.right: parent.right
                  anchors.rightMargin: guide.u * 0.8
                  anchors.verticalCenter: parent.verticalCenter
                  text: (guide.managing ? (guide.marked[rowItem.channel.url] ? "■ " : "□ ") : "") + (guide.numbers[rowItem.r] || "")
                  s: guide.look.channelNumber
                  unit: guide.u
                  sizeFactor: table.fit(guide.look.channelNumber)
                }
                // the name, after its logo with logos on (L)
                Row {
                  visible: cellItem.modelData === "name"
                  width: parent.width - guide.u * 0.8
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: guide.u * 0.5
                  ChannelLogo {
                    id: tableLogo
                    visible: guide.showLogos
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? Math.round(table.rowH * 0.8) : 0
                    height: width
                    guide: table.guide
                    channel: rowItem.channel
                    locked: rowItem.lockedNow
                  }
                  Label {
                    width: parent.width - (tableLogo.visible ? tableLogo.width + parent.spacing : 0) - (tableRec.visible ? tableRec.implicitWidth + parent.spacing : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    text: rowItem.channel.name
                    s: guide.look.channelName
                    unit: guide.u
                    sizeFactor: table.fit(s)
                    elide: Text.ElideRight
                  }
                  // ● REC while this channel records
                  Label {
                    id: tableRec
                    visible: rowItem.recording
                    anchors.verticalCenter: parent.verticalCenter
                    text: "● REC"
                    s: guide.look.channelRec
                    unit: guide.u
                    sizeFactor: table.fit(s)
                  }
                }
                Label {
                  visible: cellItem.modelData === "category"
                  width: parent.width - guide.u * 0.8
                  anchors.verticalCenter: parent.verticalCenter
                  text: guide.categoryName(rowItem.channel.category)
                  s: guide.look.tableDim
                  unit: guide.u
                  sizeFactor: table.fit(s)
                  elide: Text.ElideRight
                }
                Row {
                  visible: cellItem.modelData === "now" || cellItem.modelData === "next"
                  width: parent.width - guide.u * 0.8
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: guide.u * 0.5
                  Label {
                    id: liveTag
                    visible: cellItem.modelData === "now" && cellItem.live
                    text: "● Live"
                    s: guide.look.liveTag
                    unit: guide.u
                    sizeFactor: table.fit(guide.look.liveTag)
                    color: s.text.color === "inherit" ? guide.look.tableText.text.color : s.text.color
                  }
                  Label {
                    width: parent.width - (liveTag.visible ? liveTag.width + parent.spacing : 0)
                    text: cellItem.modelData === "now" ? (rowItem.show ? guide.showTitle(rowItem.show.title)
                                                                     : rowItem.channel.state === "error" ? "no signal" : "…")
                                                       : (rowItem.after ? guide.showTitle(rowItem.after.title) : "")
                    s: guide.look.tableText
                    unit: guide.u
                    sizeFactor: table.fit(guide.look.tableText)
                    color: cellItem.modelData === "now" && cellItem.live && guide.look.liveTag.text.color !== "inherit"
                           ? guide.look.liveTag.text.color : guide.look.tableText.text.color
                    elide: Text.ElideRight
                  }
                }
                Label {
                  visible: cellItem.modelData === "left"
                  anchors.right: parent.right
                  anchors.rightMargin: guide.u * 0.8
                  anchors.verticalCenter: parent.verticalCenter
                  text: table.minutesLeft(rowItem.show)
                  s: guide.look.tableDim
                  unit: guide.u
                  sizeFactor: table.fit(guide.look.tableDim)
                }
                // how far in (full, and the live color, for live channels)
                Rectangle {
                  readonly property var bar: cellItem.live ? guide.look["rowProgress:live"] : guide.look.rowProgress
                  visible: cellItem.modelData === "bar" && !!rowItem.show
                  anchors.verticalCenter: parent.verticalCenter
                  width: Look.px(bar.width, guide.u)
                  height: Math.max(2, Look.px(bar.height, guide.u))
                  radius: Math.min(height / 2, Look.px(bar.radius, guide.u))
                  color: bar.track || "transparent"
                  Rectangle {
                    height: parent.height
                    radius: parent.radius
                    color: parent.bar.fill && typeof parent.bar.fill === "object" ? parent.bar.fill.from : (parent.bar.fill || "transparent")
                    width: !rowItem.show ? 0 : cellItem.live ? parent.width
                         : parent.width * Math.max(0, Math.min(1, (guide.now - rowItem.show.start) / Math.max(1, rowItem.show.end - rowItem.show.start)))
                  }
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

  // The preview: 16:9, as wide as the rest
  Pane {
    id: previewPane
    guide: table.guide
    x: channels.width + guide.u
    y: table.titleRoom
    width: table.width - x
    height: Math.round((width - padding * 2) * 9 / 16 + padding * 2 + titleHeight / 2)
    title: "preview"
    note: guide.channels.length ? "ch " + (guide.numbers[guide.tunedRow >= 0 && guide.reception !== "off" ? guide.tunedRow : guide.row] || "") : ""

    Item {
      id: previewSlot
      anchors.fill: parent
      MouseArea {
        anchors.fill: parent
        z: 3
        cursorShape: Qt.PointingHandCursor
        onClicked: if (guide.reception !== "off") guide.watching = true
      }
    }
  }

  // The lineup of the channel under the cursor
  Pane {
    id: lineup
    guide: table.guide
    readonly property var ch: guide.channels[guide.row]
    readonly property var shows: guide.lineupFrom(guide.row, Math.min(guide.now, guide.selected ? guide.selected.start : guide.now), 24)
    x: previewPane.x
    y: previewPane.y + previewPane.height + table.titleRoom + guide.u * 0.4
    width: previewPane.width
    height: table.height - y
    title: "lineup"
    note: ch ? (guide.numbers[guide.row] || "") + " " + ch.name : ""

    Row {
      id: lineupHeader
      x: guide.u * 1.6
      height: table.rowH
      Repeater {
        model: [["start", 5], ["end", 5], ["len", 4], ["title", 0]]
        delegate: Label {
          required property var modelData
          anchors.verticalCenter: parent.verticalCenter
          width: modelData[1] ? guide.u * modelData[1] : implicitWidth
          text: modelData[0]
          s: guide.look.tableHeader
          unit: guide.u
        }
      }
    }

    Column {
      id: lineupRows
      y: lineupHeader.height
      width: parent.width
      Repeater {
        model: lineup.shows.slice(0, Math.max(1, Math.floor((lineup.height - lineup.padding * 2 - lineupHeader.height - lineupNotes.height - table.rowH) / table.rowH)))
        delegate: Box {
          id: showRow
          required property var modelData
          readonly property bool airing: modelData.live || (guide.now >= modelData.start && guide.now < modelData.end)
          readonly property bool picked: guide.selected !== null && guide.selected.start === modelData.start
          width: lineupRows.width
          height: table.rowH
          s: picked ? guide.look["tableRow:current"] : guide.look.tableRow
          unit: guide.u

          Label {
            visible: showRow.airing
            x: guide.u * 0.4
            anchors.verticalCenter: parent.verticalCenter
            text: "▶"
            s: guide.look["rowMarker:playing"]
            unit: guide.u
            sizeFactor: table.fit(guide.look["rowMarker:playing"]) * 0.8
          }
          Row {
            x: guide.u * 1.6
            anchors.verticalCenter: parent.verticalCenter
            Label { width: guide.u * 5; text: showRow.modelData.live ? "live" : guide.clock(showRow.modelData.start); s: guide.look.tableText; unit: guide.u; sizeFactor: table.fit(guide.look.tableText) }
            Label { width: guide.u * 5; text: showRow.modelData.live ? "" : guide.clock(showRow.modelData.end); s: guide.look.tableText; unit: guide.u; sizeFactor: table.fit(guide.look.tableText) }
            Label {
              width: guide.u * 4
              text: showRow.modelData.live ? "" : Math.round((showRow.modelData.end - showRow.modelData.start) / 60) + "m"
              s: guide.look.tableDim
              unit: guide.u
              sizeFactor: table.fit(guide.look.tableDim)
            }
            Label {
              width: lineupRows.width - guide.u * 15.6
              text: guide.showTitle(showRow.modelData.title)
              s: guide.look.tableText
              unit: guide.u
              sizeFactor: table.fit(guide.look.tableText)
              elide: Text.ElideRight
            }
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: guide.cursorTime = Math.max(showRow.modelData.start, guide.now)
          }
        }
      }
    }

    // Where the channel comes from, and how its lineup is planned
    Column {
      id: lineupNotes
      anchors.bottom: parent.bottom
      x: guide.u * 0.4
      width: parent.width - guide.u * 0.8
      spacing: guide.u * 0.15
      Row {
        spacing: guide.u * 0.6
        Label { text: "src"; s: guide.look.tableDim; unit: guide.u }
        Label {
          width: lineupNotes.width - guide.u * 3
          text: !lineup.ch ? "" : (lineup.ch.kind === "iptv" ? "iptv  " : "youtube  ")
                                  + String(lineup.ch.url || "").replace(/^https?:\/\/(www\.)?(youtube\.com\/)?/, "")
          s: guide.look.tableText
          unit: guide.u
          elide: Text.ElideMiddle
        }
      }
      Row {
        spacing: guide.u * 0.6
        Label { text: "plan"; s: guide.look.tableDim; unit: guide.u }
        Label {
          text: !lineup.ch ? "" : lineup.ch.kind === "iptv" && guide.epg.has(lineup.ch.url) ? "live stream, with program listings"
              : lineup.ch.kind === "iptv" || lineup.ch.live ? "live stream"
              : guide.lineupMode === "daily" ? "daily lineup, planned " + guide.clock(guide.tvDayStart(guide.now)) : "replanned with each new listing"
          s: guide.look.tableText
          unit: guide.u
        }
      }
    }
  }
}
