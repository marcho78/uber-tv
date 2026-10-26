import QtQuick
import "../Look.js" as Look

// The channel lock's box (ChannelLock.qml): typing a passcode (dots, never
// the digits), the lock's settings, and the list of channels to lock. TV
// style, like the other boxes: big type, menu rows, the focused one lit. It
// shows over a playing picture too, for a locked channel asked for while
// watching.
Box {
  id: lockBox

  required property var guide
  readonly property var lock: guide.channelLock
  readonly property real u: guide.u
  readonly property real rowSize: 0.85
  readonly property real rowH: Math.round(Look.px(guide.look.menuRow.height, u * rowSize))
  readonly property string view: guide.dialog

  anchors.fill: parent
  visible: lockBox.lock.boxUp
  s: guide.look.scrim
  unit: guide.u

  MouseArea {
    anchors.fill: parent
    onClicked: lockBox.lock.cancel()
  }

  Box {
    id: frame
    anchors.centerIn: parent
    width: Math.min(parent.width - lockBox.u * 4, lockBox.u * (lockBox.view === "lockChannels" ? 66 : 58))
    height: col.implicitHeight + frame.padding * 2
    scale: Math.min(1, (lockBox.height - lockBox.u * 2) / Math.max(1, height))
    s: guide.look.box
    unit: lockBox.u
    image: guide.areaImages.box

    MouseArea { anchors.fill: parent }

    Column {
      id: col
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: frame.padding
      spacing: lockBox.u * 1.1

      Label {
        width: parent.width
        text: lockBox.view === "lockCode" ? lockBox.lock.title : lockBox.view === "lockChannels" ? "Locked channels" : "Channel lock"
        s: guide.look.boxTitle
        unit: lockBox.u
        sizeFactor: 1.3
        wrapMode: Text.Wrap
      }

      Label {
        width: parent.width
        visible: text !== ""
        text: lockBox.view === "lockCode" ? lockBox.lock.prompt
            : lockBox.view === "lockChannels" ? "Type a name or number to find a channel. Enter locks or unlocks it."
            : ""
        s: guide.look.boxText
        unit: lockBox.u
        sizeFactor: 1.15
        wrapMode: Text.Wrap
      }

      // ---- the passcode: a dot for each digit typed ----
      Row {
        visible: lockBox.view === "lockCode" && lockBox.lock.typing
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: lockBox.u * 1.2
        Repeater {
          model: Math.max(4, Math.min(8, lockBox.lock.code.length + (lockBox.lock.code.length >= 4 && lockBox.lock.code.length < 8 ? 1 : 0)))
          delegate: Rectangle {
            required property int index
            width: lockBox.u * 2.2
            height: width
            radius: width / 2
            color: index < lockBox.lock.code.length ? guide.look.boxText.text.color : "transparent"
            border.color: guide.look.boxText.text.color
            border.width: Math.max(2, lockBox.u * 0.18)
            opacity: index < lockBox.lock.code.length ? 1 : 0.55
          }
        }
      }

      Label {
        width: parent.width
        visible: lockBox.view === "lockCode" && text !== ""
        horizontalAlignment: Text.AlignHCenter
        text: lockBox.lock.authBusy ? "Waiting for the computer's password…"
            : lockBox.lock.busy ? "Checking…"
            : lockBox.lock.wait > 0 ? "Too many wrong tries: wait " + lockBox.lock.wait + " s"
            : lockBox.lock.problem
        s: guide.look.boxText
        unit: lockBox.u
        sizeFactor: 1.15
        color: lockBox.lock.busy || lockBox.lock.authBusy ? guide.look.boxText.text.color : guide.colors.alert
        wrapMode: Text.Wrap
      }

      // ---- the settings ----
      Column {
        visible: lockBox.view === "lockSettings"
        width: parent.width
        spacing: lockBox.u * 0.35
        Repeater {
          model: lockBox.lock.rows
          delegate: MenuRow {
            required property int index
            required property var modelData
            guide: lockBox.guide
            width: parent.width
            height: implicitHeight
            size: lockBox.rowSize
            focused: index === lockBox.lock.cursor
            label: modelData.label
            kind: modelData.kind
            on: lockBox.lock.rowOn(modelData.key)
            value: lockBox.lock.rowValue(modelData.key)
            // a click picks first; a finger acts at once
            onActivated: { if (lockBox.lock.cursor !== index) { lockBox.lock.cursor = index; if (!lockBox.guide.touchMode) return } lockBox.lock.act(modelData.key) }
          }
        }
      }
      Label {
        width: parent.width
        visible: lockBox.view === "lockSettings" && text !== ""
        text: lockBox.lock.rowNote
        s: guide.look.boxText
        unit: lockBox.u
        sizeFactor: 1.05
        wrapMode: Text.Wrap
      }

      // ---- the list of channels ----
      Box {
        visible: lockBox.view === "lockChannels"
        width: parent.width
        height: lockBox.u * 3.8
        s: guide.look["input:focused"]
        unit: lockBox.u
        Text {
          anchors.fill: parent
          anchors.leftMargin: lockBox.u
          anchors.rightMargin: lockBox.u
          verticalAlignment: Text.AlignVCenter
          text: lockBox.lock.query || "Search your channels"
          opacity: lockBox.lock.query ? 1 : 0.6
          color: guide.ink
          font.family: guide.fonts.body
          font.pixelSize: lockBox.u * 1.4
          elide: Text.ElideRight
        }
      }
      ListView {
        id: list
        visible: lockBox.view === "lockChannels"
        width: parent.width
        height: Math.min(contentHeight, lockBox.rowH * 7 + spacing * 6)
        clip: true
        spacing: lockBox.u * 0.35
        model: lockBox.lock.listed
        currentIndex: lockBox.lock.listCursor
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        delegate: MenuRow {
          required property int index
          required property var modelData
          guide: lockBox.guide
          width: list.width
          height: lockBox.rowH
          size: lockBox.rowSize
          focused: index === lockBox.lock.listCursor
          label: "CH " + modelData.number + "  " + modelData.name
          kind: "switch"
          on: modelData.locked
          onActivated: { if (lockBox.lock.listCursor !== index) lockBox.lock.listCursor = index; else lockBox.lock.toggleListed() }
        }
      }
      Label {
        width: parent.width
        visible: lockBox.view === "lockChannels" && lockBox.lock.listed.length === 0
        text: "No channel matches."
        s: guide.look.boxText
        unit: lockBox.u
        sizeFactor: 1.05
      }
    }
  }
}
