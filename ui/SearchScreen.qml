import QtQuick

// Search (/): a big field at the top that takes what you type, and under it
// what matches, in rows of cards (ui/CardRows.qml): channels, what's on now
// and later today, movies and series, your YouTube channels' videos, and My
// Videos. With nothing typed, your recent searches. ↓ goes into the results,
// ↑ from the first row back to the field. Styled by the searchField, menu
// and library elements (Look.js).
Item {
  id: page

  required property var guide

  readonly property real u: guide.u
  readonly property bool typing: !guide.searchInResults
  readonly property var fieldStyle: typing ? guide.look["searchField:focused"] : guide.look.searchField
  readonly property var card: guide.searchCard

  // ---- the field ----
  Box {
    id: field
    x: page.u * 3
    y: page.u * 2.2
    width: Math.min(page.width - x - clock.width - page.u * 6, page.u * 90)
    height: Math.round(page.u * 5.2)
    s: page.fieldStyle
    unit: page.u

    Icon {
      id: glass
      x: field.padding
      anchors.verticalCenter: parent.verticalCenter
      name: "search"
      size: Math.round(page.u * 2.2)
      stroke: 2.2
      color: page.fieldStyle.text ? page.fieldStyle.text.color : "white"
    }
    Label {
      id: query
      anchors.left: glass.right
      anchors.leftMargin: page.u * 1.2
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, field.width - glass.width - field.padding * 2 - page.u * 2)
      text: guide.searchQuery
      s: page.fieldStyle
      unit: page.u
      elide: Text.ElideLeft
    }
    Label {
      anchors.left: glass.right
      anchors.leftMargin: page.u * 1.2
      anchors.right: parent.right
      anchors.rightMargin: field.padding
      anchors.verticalCenter: parent.verticalCenter
      visible: guide.searchQuery === ""
      text: "Search channels, shows, movies and videos"
      s: page.fieldStyle
      unit: page.u
      color: guide.dimInk
      font.weight: Font.Normal
      elide: Text.ElideRight
    }
    // the caret, blinking while you type
    Rectangle {
      id: caret
      visible: page.typing
      x: query.x + (guide.searchQuery === "" ? 0 : query.width + page.u * 0.15)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(2, Math.round(page.u * 0.14))
      height: Math.round(field.height * 0.5)
      color: page.fieldStyle.caret || guide.marquee
      SequentialAnimation on opacity {
        running: caret.visible
        loops: Animation.Infinite
        NumberAnimation { to: 0; duration: 500; easing.type: Easing.InOutQuad }
        NumberAnimation { to: 1; duration: 500; easing.type: Easing.InOutQuad }
      }
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.IBeamCursor
      // back to typing, and tablet mode's keyboard back up if it was hidden
      onClicked: { guide.searchInResults = false; guide.showTouchKeyboard() }
    }
  }

  Label {
    id: clock
    anchors.right: parent.right
    anchors.rightMargin: page.u * 3
    anchors.verticalCenter: field.verticalCenter
    text: guide.clock(guide.now)
    s: guide.look.clock
    unit: page.u
    sizeFactor: 1.5 / Math.max(0.2, guide.look.clock.text.size)
  }

  // How it went
  Label {
    id: status
    x: field.x + page.u * 0.4
    anchors.top: field.bottom
    anchors.topMargin: page.u * 1.2
    width: field.width
    text: !guide.searchTerms ? (guide.searchQuery.trim() ? "Searching…" : "")
        : guide.searchCount ? guide.searchCount + (guide.searchCount === 1 ? " match" : " matches") + " for “" + guide.searchTerms + "”"
        : "Nothing matches “" + guide.searchTerms + "”. Try fewer or other words."
    s: guide.look.menuNote
    unit: page.u
    elide: Text.ElideRight
  }

  // ---- what matches ----
  CardRows {
    id: results
    guide: page.guide
    visible: guide.searchTerms !== ""
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: page.u
    anchors.top: status.bottom
    anchors.topMargin: page.u
    anchors.bottom: footer.top
    rows: guide.searchRows
    rowIndex: guide.searchRow
    cols: guide.searchCols
    active: guide.searchInResults
    onSelect: function(row, col) {
      guide.searchInResults = true
      guide.searchRow = row
      var all = {}
      for (var k in guide.searchCols) all[k] = guide.searchCols[k]
      all[guide.searchRows[row].key] = col
      guide.searchCols = all
    }
    onOpen: function(row, col) { select(row, col); guide.searchEnter() }
  }

  // ---- nothing typed: your recent searches ----
  Column {
    visible: guide.searchTerms === "" && guide.searchQuery.trim() === ""
    x: field.x
    anchors.top: field.bottom
    anchors.topMargin: page.u * 2.4
    width: Math.min(field.width, page.u * 64)
    spacing: Math.round(page.u * 0.4)

    Label {
      visible: guide.recentSearches.length > 0
      x: Math.ceil(parent.width * 0.03) + page.u * 0.4
      text: "Recent searches"
      s: guide.look.menuHeader
      unit: page.u
      bottomPadding: page.u * 0.4
    }
    Repeater {
      model: guide.recentSearches
      delegate: MenuRow {
        required property var modelData
        required property int index
        guide: page.guide
        width: parent.width
        height: implicitHeight
        size: 0.9
        icon: "search"
        label: modelData
        focused: guide.searchInResults && index === guide.searchRow
        onActivated: { guide.searchInResults = true; guide.searchRow = index; guide.searchEnter() }
      }
    }
    Label {
      width: parent.width
      x: page.u * 0.4
      topPadding: guide.recentSearches.length ? page.u * 1.4 : 0
      text: "Type a channel's name or number, a show, a movie, a video, or one of your own videos. Everything that matches shows here as you type."
      s: guide.look.menuNote
      unit: page.u
      wrapMode: Text.Wrap
    }
  }

  // ---- the keys ----
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
      id: searchKeys
      anchors.left: parent.left
      anchors.leftMargin: footer.padding
      anchors.verticalCenter: parent.verticalCenter
      transformOrigin: Item.Left
      scale: searchKeys.touching ? 1 : Math.min(1, (footer.width - footer.padding * 2) / Math.max(1, implicitWidth))
      touchGuide: page.guide
      touchWidth: footer.width - footer.padding * 2
      // (tablet mode: a tap on a result opens it; "or type" and "Type to
      // search again" are the keyboard's, so no words there)
      model: page.typing
             ? [{ keys: [], label: "Type to search", touch: {} }].concat(guide.searchRows.length || (!guide.searchTerms && guide.recentSearches.length) ? [{ keys: ["↓"], label: guide.searchTerms ? "Results" : "Recent searches" }] : [])
               .concat([{ keys: ["DEL"], label: "Clear", touch: { key: Qt.Key_Delete } },
                        { keys: ["←"], label: "Nav rail", touch: guide.railShows === "focus" ? { run: function() { page.guide.openRail() }, icon: "menu" } : undefined },
                        { keys: ["ESC"], label: "Back", touch: { key: Qt.Key_Escape, back: true } }])
             : !guide.searchTerms
             ? [{ keys: ["↑", "↓"], label: "Move" }, { keys: ["ENTER"], label: "Search it" }, { keys: [], label: "or type", touch: {} }, { keys: ["ESC"], label: "Back to typing", touch: { key: Qt.Key_Escape, back: true } }]
             : [{ keys: ["↑", "↓", "←", "→"], label: "Move" },
                { keys: ["ENTER"], label: !page.card ? "Open" : page.card.kind === "channel" ? (page.card.starting ? "See it in the guide" : "Watch")
                                        : page.card.kind === "movie" || page.card.kind === "series" ? "Details" : "Play" },
                { keys: ["SPACE"], label: "Play", touch: { key: Qt.Key_Space, icon: "playsolid" } }, { keys: [], label: "Type to search again", touch: {} },
                { keys: ["ESC"], label: "Back to typing", touch: { key: Qt.Key_Escape, back: true } }]
      size: page.u * 1.55
      capStyle: guide.look.keycap
      labelStyle: guide.look.keyLabel
    }
  }
}
