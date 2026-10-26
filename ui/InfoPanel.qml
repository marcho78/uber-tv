import QtQuick
import QtQuick.Effects
import "../Look.js" as Look

// The preview box (the TV, small) and what's under the cursor: the channel,
// the show, its times and what's on next. The layout (Look.js) puts the
// preview on either side or leaves it out, and can add a tag to it, a
// progress bar, an Up next list and the clock with the date.
Box {
  id: area

  required property var guide
  // where the TV goes while the guide is up
  property alias videoSlot: previewSlot

  readonly property var layout: guide.layout

  // a compact screen: the preview no wider than half, beside the words (the
  // area no taller than that preview)
  height: guide.screenFit === "compact" && layout.preview !== "none"
          ? Math.max(0, Math.min(guide.u * layout.infoHeight, Math.round((width - area.padding * 2 - guide.u) / 2 * 9 / 16 + area.padding * 2)))
          : guide.u * layout.infoHeight
  s: guide.look.infoArea
  unit: guide.u

  Row {
    id: topRow
    anchors.fill: parent
    anchors.margins: area.padding
    spacing: guide.u
    layoutDirection: area.layout.preview === "right" ? Qt.RightToLeft : Qt.LeftToRight

    Box {
      id: preview
      visible: area.layout.preview !== "none"
      height: topRow.height
      width: Math.round(height * 16 / 9)
      s: guide.look.preview
      unit: guide.u

      // The TV goes in here; cut to the box's corners when they're rounded
      Item {
        id: previewSlot
        anchors.fill: parent
        anchors.margins: preview.borderWidth
        layer.enabled: preview.rounded || preview.curved
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: previewMask
          maskThresholdMin: 0.5
          maskSpreadAtMin: 1
        }
      }
      Rectangle {
        id: previewMask
        anchors.fill: previewSlot
        visible: false
        layer.enabled: true
        color: "white"
        topLeftRadius: Math.max(0, preview.corners[0] - preview.borderWidth)
        topRightRadius: Math.max(0, preview.corners[1] - preview.borderWidth)
        bottomRightRadius: Math.max(0, preview.corners[2] - preview.borderWidth)
        bottomLeftRadius: Math.max(0, preview.corners[3] - preview.borderWidth)
      }

      // LIVE PREVIEW · CH 1
      Box {
        id: tag
        visible: area.layout.previewTag && guide.channels.length > 0
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Math.max(guide.u * 0.5, preview.corners[3] * 0.4)
        width: tagLabel.implicitWidth + tag.padding * 2
        height: tagLabel.implicitHeight + tag.padding * 2
        s: guide.look.previewTag
        unit: guide.u
        Label {
          id: tagLabel
          anchors.centerIn: parent
          text: "Live preview · CH " + (guide.numbers[guide.tunedRow >= 0 && guide.reception !== "off" ? guide.tunedRow : guide.row] || "")
          s: guide.look.previewTag
          unit: guide.u
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (guide.reception !== "off") guide.watching = true
      }
    }

    Box {
      id: panel
      width: topRow.width - (preview.visible ? preview.width + topRow.spacing : 0)
      height: topRow.height
      s: guide.look.infoPanel
      unit: guide.u
      image: guide.areaImages.infoPanel
      clip: true

      // The clock and the date, when the layout puts it here
      Label {
        id: infoClock
        visible: area.layout.clock === "info"
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: panel.padding
        text: Qt.formatDateTime(new Date(guide.now * 1000), "ddd MMM d") + "   " + guide.clock(guide.now)
        s: guide.look.clock
        unit: guide.u
      }

      Column {
        id: info
        anchors.fill: parent
        anchors.margins: panel.padding
        spacing: guide.u * 0.5

        readonly property var ch: guide.channels[guide.row]
        readonly property var after: guide.selected ? guide.nextShow(guide.row, guide.selected) : null
        // what's after it, as many as the layout lists
        readonly property var later: {
          var out = []
          var show = guide.selected
          for (var i = 0; show && i < area.layout.upNext; i++) {
            show = guide.nextShow(guide.row, show)
            if (show) out.push(show)
          }
          return out
        }

        Label {
          width: parent.width - (infoClock.visible ? infoClock.width + guide.u : 0)
          text: !info.ch ? "No channels — press A to add one"
                : guide.channelLabel(guide.row) + (info.ch.category ? "   ·   " + info.ch.category : "")
          s: guide.look.infoChannel
          unit: guide.u
          elide: Text.ElideRight
        }
        Label {
          width: parent.width
          text: guide.selected ? guide.showTitle(guide.selected.title)
                : !info.ch ? ""
                : info.ch.state === "error" ? "No signal — nothing on this channel can air"
                : "Loading listings…"
          s: guide.look.infoTitle
          unit: guide.u
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Label {
          width: parent.width
          text: guide.selected ? guide.airTime(guide.selected) : ""
          s: guide.look.infoTime
          unit: guide.u
          elide: Text.ElideRight
        }
        // what it's about (program listings)
        Label {
          width: parent.width
          visible: text !== ""
          text: guide.selected && guide.selected.desc ? guide.selected.desc : ""
          s: guide.look.infoDesc
          unit: guide.u
          wrapMode: Text.Wrap
          maximumLineCount: area.layout.upNext >= 2 ? 1 : 2
          elide: Text.ElideRight
        }

        // How far in it is
        Rectangle {
          readonly property var bar: guide.look.infoProgress
          readonly property var show: guide.selected
          visible: area.layout.infoProgress && show !== null && !show.live && guide.now >= show.start && guide.now < show.end
          width: typeof bar.width === "number" ? parent.width * bar.width : parent.width
          height: Look.px(bar.height, guide.u)
          radius: Math.min(height / 2, Look.px(bar.radius, guide.u))
          color: bar.track || "transparent"
          Rectangle {
            height: parent.height
            width: !parent.show ? 0 : parent.width * Math.max(0, Math.min(1, (guide.now - parent.show.start) / Math.max(1, parent.show.end - parent.show.start)))
            radius: parent.radius
            color: parent.bar.fill && typeof parent.bar.fill === "object" ? parent.bar.fill.from : (parent.bar.fill || "transparent")
          }
        }

        // What's next: a line, or a list under a heading
        Label {
          width: parent.width
          visible: area.layout.upNext === 1 && info.after !== null
          text: info.after ? "NEXT  " + guide.clock(info.after.start) + "  " + guide.showTitle(info.after.title) : ""
          s: guide.look.infoNext
          unit: guide.u
          elide: Text.ElideRight
        }
        Label {
          visible: area.layout.upNext >= 2 && info.later.length > 0
          topPadding: guide.u * 0.4
          text: "Up next"
          s: guide.look.upNextLabel
          unit: guide.u
        }
        Repeater {
          model: area.layout.upNext >= 2 ? info.later : []
          delegate: Label {
            required property var modelData
            required property int index
            width: info.width
            text: guide.clock(modelData.start) + "  " + guide.showTitle(modelData.title)
            s: index === 0 ? guide.look.infoNext : guide.look["infoNext:later"]
            unit: guide.u
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
