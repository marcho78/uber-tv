import QtQuick

// Apps (on the rail, while apps are on): your apps as tiles in their own
// colors, then Get apps. Enter (or a click) opens one full screen, the guide
// making way until it's closed; the one that's on says so, and X closes it.
// I shows what it's allowed, G the catalog. Under the tiles, what the
// selected one is. Styled by the homeTile element (each app's color over
// its fill) and the menu elements.
Item {
  id: page

  required property var guide

  readonly property real u: guide.u
  readonly property var tile: guide.appsTiles[guide.appsTile] || null
  readonly property var app: tile && tile.kind === "app" ? guide.apps.record(tile.id) : null
  readonly property bool appOn: !!app && guide.appUp === app.id

  // black or white, whichever reads on the app's color
  function inkOn(c) {
    var m = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(c || "")
    if (!m) return guide.ink
    var l = (0.299 * parseInt(m[1], 16) + 0.587 * parseInt(m[2], 16) + 0.114 * parseInt(m[3], 16)) / 255
    return l > 0.6 ? "#111111" : "#ffffff"
  }

  function styled(base, color) {
    var o = {}
    for (var k in base) o[k] = base[k]
    if (color) o.fill = color
    return o
  }

  Label {
    id: title
    x: page.u * 3
    y: page.u * 2
    text: "Apps"
    s: guide.look.libraryTab
    unit: page.u
    sizeFactor: 2.4 / Math.max(0.2, guide.look.libraryTab.text.size)
    color: guide.look["libraryTab:current"].text.color
  }
  Label {
    anchors.right: parent.right
    anchors.rightMargin: page.u * 3
    y: title.y + page.u * 0.4
    text: guide.clock(guide.now)
    s: guide.look.clock
    unit: page.u
    sizeFactor: 1.5 / Math.max(0.2, guide.look.clock.text.size)
  }

  GridView {
    id: grid
    x: page.u * 3 - page.u * 0.6
    anchors.top: title.bottom
    anchors.topMargin: page.u * 2.4
    width: page.width - page.u * 4.8
    height: Math.min(Math.ceil(count / guide.appsCols) * cellHeight, footer.y - y - note.implicitHeight - page.u * 5)
    cellWidth: Math.floor(width / guide.appsCols)
    cellHeight: Math.round((cellWidth - page.u * 1.2) * 9 / 16 + page.u * 1.6)
    clip: true
    interactive: false
    model: guide.appsTiles
    currentIndex: guide.appsTile
    highlightRangeMode: GridView.ApplyRange
    preferredHighlightBegin: 0
    preferredHighlightEnd: height - cellHeight

    delegate: Item {
      id: cell
      required property var modelData
      required property int index
      readonly property bool current: index === guide.appsTile
      readonly property bool get: modelData.kind === "get"
      readonly property var st: page.styled(current ? guide.look["homeTile:current"] : guide.look.homeTile, get ? "" : modelData.color)
      width: grid.cellWidth
      height: grid.cellHeight

      Box {
        id: face
        x: page.u * 0.6
        y: page.u * 0.6
        width: parent.width - page.u * 1.2
        height: parent.height - page.u * 1.6
        s: cell.st
        unit: page.u
        scale: cell.current ? 1.06 : 1
        z: cell.current ? 2 : 0
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Image {
          id: icon
          anchors.centerIn: parent
          width: parent.width * 0.42
          height: parent.height * 0.5
          visible: !cell.get && status === Image.Ready
          source: !cell.get && cell.modelData.icon ? guide.fileUrl(cell.modelData.icon) : ""
          sourceSize.width: 256
          fillMode: Image.PreserveAspectFit
          asynchronous: true
        }
        Icon {
          visible: cell.get
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -page.u * 0.8
          name: "plus"
          size: Math.round(page.u * 2.6)
          stroke: 2.2
          color: cell.st.text ? cell.st.text.color : guide.ink
        }
        Label {
          visible: !icon.visible
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: face.padding
          anchors.verticalCenter: parent.verticalCenter
          anchors.verticalCenterOffset: cell.get ? page.u * 1.6 : 0
          horizontalAlignment: Text.AlignHCenter
          text: cell.modelData.title
          s: cell.st
          unit: page.u
          sizeFactor: cell.get ? 1 : 1.35
          color: cell.get ? (cell.st.text ? cell.st.text.color : guide.ink) : page.inkOn(cell.modelData.color)
          elide: Text.ElideRight
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { guide.appsTile = cell.index; guide.appsTileAct(false, guide.byUser) }
        }
        // from a signed or Developer-mode file: a small page badge, no words
        OriginBadge {
          anchors.right: parent.right
          anchors.rightMargin: page.u * 0.5
          y: page.u * 0.5
          guide: page.guide
          u: page.u
          from: cell.get ? "" : cell.modelData.from || ""
        }
        // the one that's on, under the guide
        Rectangle {
          visible: !cell.get && guide.appUp === cell.modelData.id
          x: page.u * 0.5
          y: page.u * 0.5
          width: onNow.implicitWidth + page.u * 1.2
          height: onNow.implicitHeight + page.u * 0.4
          radius: height / 2
          color: guide.marquee
          Text {
            id: onNow
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "ON NOW"
            color: page.inkOn(String(guide.marquee))
            font.family: guide.fontFamily
            font.pixelSize: Math.round(page.u * 0.85)
            font.bold: true
          }
        }
      }
      // the selected one's ring: an app's color would hide the theme's highlight
      Rectangle {
        visible: cell.current
        x: face.x - ring
        y: face.y - ring
        width: face.width + ring * 2
        height: face.height + ring * 2
        scale: face.scale
        z: 3
        readonly property real ring: Math.round(page.u * 0.45)
        radius: (face.corners[0] || 0) + ring
        color: "transparent"
        border.width: Math.max(2, Math.round(page.u * 0.25))
        border.color: guide.marquee
      }
    }
  }

  // What the selected one is
  Label {
    id: note
    x: page.u * 3
    anchors.top: grid.bottom
    anchors.topMargin: page.u * 1.6
    width: Math.min(page.width - page.u * 6, page.u * 90)
    text: !page.tile ? ""
          : page.tile.kind === "get" ? "The Uber TV catalog: apps checked and signed with its key. You see who made each one and what it asks for before it's installed."
            + (guide.apps.ready.length ? "" : " Your apps show here once they're installed.")
          : page.appOn ? page.app.name + " is on, under the guide. Enter goes back to it; X closes it."
          : page.app ? page.app.name + "  ·  by " + page.app.author + (page.app.from === "file" ? "  ·  unsigned, from a file" : "")
            + (page.app.description ? "\n" + page.app.description : "")
            + (page.app.kind === "app" ? "\nIt opens here, in the guide. In it, , is its settings and Esc comes back."
               : "\nSuper + W closes it and brings you back here.")
          : ""
    s: guide.look.menuNote
    unit: page.u
    sizeFactor: 1.15
    wrapMode: Text.Wrap
    maximumLineCount: 4
    elide: Text.ElideRight
  }
  Label {
    x: page.u * 3
    anchors.top: note.bottom
    anchors.topMargin: page.u * 0.8
    width: note.width
    visible: text !== ""
    text: guide.apps.status
    s: guide.look.boxText
    unit: page.u
    sizeFactor: 1.05
    color: /^(Not installed|Couldn't)/.test(guide.apps.status) || / was turned off/.test(guide.apps.status) ? guide.colors.alert : guide.marquee
    wrapMode: Text.Wrap
  }

  Box {
    id: footer
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: page.u * 3
    anchors.rightMargin: page.u * 3
    anchors.bottomMargin: page.u * 1.6
    // tablet mode: the buttons, always there, a finger tall (a tap on a card opens it)
    height: guide.touchMode ? guide.fingerPx + page.u * 0.6 : guide.showKeyHints ? page.u * 1.9 : 0
    visible: guide.showKeyHints || guide.touchMode
    s: guide.look.footer
    unit: page.u
    KeyHints {
      anchors.left: parent.left
      anchors.leftMargin: footer.padding
      anchors.verticalCenter: parent.verticalCenter
      touchGuide: page.guide
      touchWidth: footer.width - footer.padding * 2
      model: [{ keys: ["↑", "↓", "←", "→"], label: "Move" },
              { keys: ["ENTER"], label: page.tile && page.tile.kind === "get" ? "Get apps" : page.appOn ? "Back to it" : "Open" }]
             .concat(page.appOn ? [{ keys: ["X"], label: "Close it", touch: { key: Qt.Key_X, icon: "close" } }] : [])
             .concat(page.app ? [{ keys: ["I"], label: "Details", touch: { key: Qt.Key_I, icon: "info" } }] : [])
             .concat(page.tile && page.tile.kind === "get" ? [] : [{ keys: ["G"], label: "Get apps", touch: { key: Qt.Key_G, icon: "plus" } }])
             .concat([{ keys: [","], label: "Settings", touch: { key: Qt.Key_Comma, icon: "gear" } },
                      { keys: ["←"], label: "Nav rail", touch: guide.layout.rail === "focus" ? { run: function() { page.guide.openRail() }, icon: "menu" } : undefined },
                      { keys: ["ESC"], label: "Back", touch: { key: Qt.Key_Escape, back: true } }])
      size: page.u * 1.55
      capStyle: guide.look.keycap
      labelStyle: guide.look.keyLabel
    }
  }
}
