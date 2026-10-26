import QtQuick
import "../Look.js" as Look

// The library (V): movies and series from your playlists, your YouTube
// channels' videos, your own (My Videos, while it's on), and My List, as
// rows of posters you move through with
// the arrows (ui/CardRows.qml). Enter opens an item's details (for a series,
// its episodes, in ui/DetailBox.qml); Space plays it, from where you stopped.
// Everything here is styled by the library elements (Look.js) and the theme.
Item {
  id: lib

  required property var guide

  readonly property real u: guide.u
  readonly property var tabs: guide.libraryTabs

  // Tabs, and the time. Tabs that don't fit before the clock (a narrow
  // screen) slide under a finger, the one you're on kept in view. In tablet
  // mode the strip reaches past the tabs' words, so each is a finger tall.
  Flickable {
    id: tabStrip
    readonly property real reach: guide.touchMode ? Math.max(0, (guide.fingerPx - tabRow.height) / 2) : 0
    x: lib.u * 2
    y: lib.u * 1.6 - reach
    width: Math.max(0, Math.min(tabRow.width, clockLabel.x - x - lib.u * 2))
    height: tabRow.height + reach * 2
    contentWidth: tabRow.width
    clip: true
    interactive: contentWidth > width
    boundsBehavior: Flickable.StopAtBounds
    function show(at, w) {
      if (at < contentX) contentX = at
      else if (at + w > contentX + width) contentX = Math.min(contentWidth - width, at + w - width)
    }

    Row {
      id: tabRow
      y: tabStrip.reach
      spacing: lib.u * 2.6
      Repeater {
        model: lib.tabs
        delegate: Item {
          id: tab
          required property var modelData
          readonly property bool on: guide.libraryTab === modelData.key
          width: tabLabel.implicitWidth
          height: tabLabel.implicitHeight + lib.u * 0.7
          onOnChanged: if (on) Qt.callLater(function() { tabStrip.show(tab.x, tab.width) })
          Component.onCompleted: if (on) Qt.callLater(function() { tabStrip.show(tab.x, tab.width) })
          Label {
            id: tabLabel
            text: parent.modelData.label
            s: parent.on ? guide.look["libraryTab:current"] : guide.look.libraryTab
            unit: lib.u
          }
          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Math.max(2, Math.round(lib.u * 0.16))
            visible: parent.on
            color: guide.look["libraryTab:current"].text.color
          }
          MouseArea {
            anchors.fill: parent
            anchors.topMargin: -tabStrip.reach
            anchors.bottomMargin: -tabStrip.reach
            cursorShape: Qt.PointingHandCursor
            onClicked: guide.openLibrary(parent.modelData.key)
          }
        }
      }
    }
  }

  Label {
    id: clockLabel
    anchors.right: parent.right
    anchors.rightMargin: lib.u * 2
    y: lib.u * 1.6
    text: guide.clock(guide.now)
    s: guide.look.clock
    unit: lib.u
    sizeFactor: 1.5 / Math.max(0.2, guide.look.clock.text.size)
  }

  // The rows
  CardRows {
    id: rows
    guide: lib.guide
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: tabStrip.bottom
    anchors.topMargin: lib.u * 1.4 - tabStrip.reach
    anchors.bottom: footer.top
    rows: guide.libraryRows
    rowIndex: guide.libRow
    cols: guide.libCols
    onSelect: function(row, col) {
      guide.libRow = row
      var all = {}
      for (var k in guide.libCols) all[k] = guide.libCols[k]
      all[guide.libraryRows[row].key] = col
      guide.libCols = all
    }
    onOpen: function(row, col) { select(row, col); guide.libEnter() }
  }

  // Nothing here yet
  Column {
    anchors.centerIn: rows
    visible: guide.libraryRows.length === 0
    spacing: lib.u * 0.6
    width: Math.min(parent.width - lib.u * 8, lib.u * 50)
    Label {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: guide.libraryTab === "movies" ? "No movies or series yet" : guide.libraryTab === "ondemand" ? "No YouTube channels yet"
          : guide.libraryTab === "videos" ? (guide.videosScanning ? "Looking for your videos…" : guide.videosMissing ? "That folder isn't there" : "No videos in " + guide.shownPath(guide.videosFolder))
          : guide.libraryTab === "recordings" ? "No recordings yet"
          : "Nothing in My List yet"
      s: guide.look.boxTitle
      unit: lib.u
    }
    Label {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      text: guide.libraryTab === "movies" ? "Add an M3U playlist with movies or series in it (A in the guide): its video files come here, its live channels go in the guide. Or ask an AI agent to."
          : guide.libraryTab === "ondemand" ? "Every video of your YouTube channels shows here, to watch from the start. Add channels with A in the guide."
          : guide.libraryTab === "videos" ? "Video files you put there (and in the folders inside it) show here: screen recordings, downloads, your own. Settings (,) picks another folder."
          : guide.libraryTab === "recordings" ? "Watching a channel full screen, press I or Space (▲ on your phone) and pick Record. Recordings go to " + guide.recordingsPlace + "."
          : "L on a movie or a video adds it here."
      s: guide.look.boxText
      unit: lib.u
    }
  }

  // The keys
  Box {
    id: footer
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: lib.u * 2
    // tablet mode: the buttons, always there, a finger tall (a tap on a card opens it)
    height: guide.touchMode ? guide.fingerPx + lib.u * 0.6 : guide.showKeyHints ? lib.u * 1.9 : 0
    visible: guide.showKeyHints || guide.touchMode
    s: guide.look.footer
    unit: lib.u
    KeyHints {
      id: libKeys
      anchors.left: parent.left
      anchors.leftMargin: footer.padding
      anchors.verticalCenter: parent.verticalCenter
      transformOrigin: Item.Left
      scale: libKeys.touching ? 1 : Math.min(1, (footer.width - footer.padding * 2) / Math.max(1, implicitWidth))
      touchGuide: lib.guide
      touchWidth: footer.width - footer.padding * 2
      model: [{ keys: ["↑", "↓", "←", "→"], label: "Move" }]
              .concat(guide.railShows === "focus" ? [{ keys: ["←"], label: "Nav rail", touchOnly: true, touch: { run: function() { lib.guide.openRail() }, icon: "menu" } }] : [])
              .concat([{ keys: ["ENTER"], label: guide.libraryTab === "recordings" ? "Choices" : "Details" },
              { keys: ["SPACE"], label: ["Starting", "Recording", "Saving"].indexOf((guide.libCard || {}).recState) >= 0 ? "Watch live" : "Play", touch: { key: Qt.Key_Space, icon: "playsolid" } }])
              .concat(guide.libraryTab === "recordings" ? [] : [{ keys: ["L"], label: "My List", touch: { key: Qt.Key_L, icon: "bookmark" } }])
              .concat((guide.libraryRows[guide.libRow] || { key: "" }).key.indexOf("continue") === 0 ? [{ keys: ["X"], label: "Off this row", touch: { key: Qt.Key_X } }] : [])
              .concat([{ keys: ["TAB"], label: lib.tabs.map(function(t) { return t.key === "movies" ? "Movies" : t.label }).join(" · ") }, { keys: ["/"], label: "Search", touch: { key: Qt.Key_Slash, icon: "search" } },
              { keys: ["S"], label: "Style", touch: { key: Qt.Key_S } },
              { keys: ["?"], label: "All keys" }, { keys: ["ESC"], label: "Back", touch: { key: Qt.Key_Escape, back: true } }])
      size: lib.u * 1.55
      capStyle: guide.look.keycap
      labelStyle: guide.look.keyLabel
    }
  }
}
