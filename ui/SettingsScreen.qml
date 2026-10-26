import QtQuick
import "../Look.js" as Look

// Settings (,), TV style: its parts down the left (General, Live TV,
// Library, Apps, About), the rows of the one you're on at the right, big enough
// to read across the room, and under them what the focused one does. ↑↓
// pick a part, → goes into its rows, ← or Esc back out. In a row, Enter
// flips a switch, opens a box, or does something (twice, for one that
// removes or clears). Styled by the menu elements (Look.js) and the theme.
Item {
  id: page

  required property var guide

  readonly property real u: guide.u
  readonly property var row: guide.settingsRows[guide.settingsCursor] || ({})

  Label {
    id: title
    x: page.u * 3
    y: page.u * 2
    text: "Settings"
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

  // ---- the parts ----
  Column {
    id: parts
    x: page.u * 3
    anchors.top: title.bottom
    anchors.topMargin: page.u * 2.4
    width: Math.min(page.u * 26, page.width * 0.28)
    spacing: page.u * 0.6

    Repeater {
      model: guide.settingsParts
      delegate: Box {
        id: part
        required property var modelData
        required property int index
        readonly property bool focused: !guide.settingsInRows && index === guide.settingsPart
        readonly property bool current: guide.settingsInRows && index === guide.settingsPart
        readonly property var st: focused ? guide.look["menuCategory:focused"] : current ? guide.look["menuCategory:current"] : guide.look.menuCategory
        width: parts.width
        height: Math.round(page.u * 4.6)
        s: st
        unit: page.u
        scale: focused ? 1.03 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Icon {
          id: partIcon
          x: part.padding
          anchors.verticalCenter: parent.verticalCenter
          name: part.modelData.icon
          size: Math.round(page.u * 1.8)
          stroke: 2
          color: part.st.text ? part.st.text.color : "white"
        }
        Label {
          anchors.left: partIcon.right
          anchors.leftMargin: page.u * 1.1
          anchors.right: parent.right
          anchors.rightMargin: part.padding
          anchors.verticalCenter: parent.verticalCenter
          text: part.modelData.label
          s: part.st
          unit: page.u
          elide: Text.ElideRight
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { guide.settingsPart = part.index; guide.settingsCursor = 0; guide.settingsInRows = false; guide.settingsArmed = "" }
        }
      }
    }
  }

  // ---- the rows of the part you're on ----
  ListView {
    id: rows
    anchors.left: parts.right
    anchors.leftMargin: page.u * 2.4
    anchors.top: parts.top
    // as tall as its rows (worked out from them, not measured), the note right under them
    readonly property real rowsH: guide.settingsRows.length * (Math.max(Math.round(Look.px(guide.look.menuRow.height, page.u)), guide.touchMode ? guide.fingerPx : 0) + spacing)
    height: Math.max(0, Math.min(rowsH, footer.y - y - note.implicitHeight - page.u * 4))
    width: Math.min(page.width - x - page.u * 3, page.u * 72)
    clip: true
    spacing: page.u * 0.6
    model: guide.settingsRows
    currentIndex: guide.settingsCursor
    // the cursor kept clear of the edges as the keys move it (the next rows
    // in view); put on a row by a click, the list stays where it is
    property int mouseIndex: -1
    onCurrentIndexChanged: if (currentIndex !== mouseIndex) mouseIndex = -1
    highlightRangeMode: ListView.ApplyRange
    preferredHighlightBegin: mouseIndex >= 0 ? 0 : page.u * 2
    preferredHighlightEnd: mouseIndex >= 0 ? height : height - page.u * 6
    highlightMoveDuration: 160
    boundsBehavior: Flickable.StopAtBounds

    // fixed heights from the start
    delegate: MenuRow {
      required property var modelData
      required property int index
      guide: page.guide
      width: rows.width
      height: implicitHeight
      label: modelData.label || ""
      icon: modelData.icon || ""
      kind: modelData.kind || "value"
      value: guide.settingValue(modelData.key, modelData)
      on: modelData.kind === "switch" && guide.settingOn(modelData.key, modelData)
      more: modelData.more === true
      focused: guide.settingsInRows && index === guide.settingsCursor
      danger: modelData.danger === true
      dim: modelData.kind === "info"
      // one click acts, as Enter does (the version's presses are counted
      // however fast they come)
      oneClick: modelData.key !== "about"
      // the cursor goes to the row first, so the keys carry on from it,
      // without the list scrolling under the pointer
      function pick() { if (!focused) { rows.mouseIndex = index; guide.settingsInRows = true; guide.settingsCursor = index; guide.settingsArmed = "" } }
      onActivated: { pick(); guide.changeSetting(1, guide.byUser) }
      // tablet mode: ‹ › step a choice; a switch that also opens flips (as Space)
      onStepped: function(dir) { pick(); guide.changeSetting(dir, guide.byUser) }
      onToggled: { pick(); guide.changeSetting(1, guide.byUser, true) }
    }
  }

  // What the focused row (or part) is about
  Label {
    id: note
    anchors.left: rows.left
    anchors.leftMargin: Math.ceil(rows.width * 0.03)
    anchors.top: rows.bottom
    anchors.topMargin: page.u * 1.6
    width: rows.width * 0.94
    text: guide.settingsNote
    s: guide.look.menuNote
    unit: page.u
    wrapMode: Text.Wrap
    maximumLineCount: 5
    elide: Text.ElideRight
  }

  Box {
    id: footer
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: page.u * 3
    anchors.rightMargin: page.u * 3
    anchors.bottomMargin: page.u * 1.6
    // tablet mode: the buttons (Back), always there, a finger tall; a tap on a
    // part or a row does the rest
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
      model: guide.channelLock && guide.channelLock.boxUp ? guide.channelLock.hints
             : !guide.settingsInRows
             ? [{ keys: ["↑", "↓"], label: "Pick" }, { keys: ["→", "/", "ENTER"], label: "Open" }, { keys: ["←"], label: "Nav rail", touch: guide.layout.rail === "focus" ? { run: function() { page.guide.openRail() }, icon: "menu" } : undefined },
                { keys: ["?"], label: "All keys" }, { keys: ["ESC"], label: "Back", touch: { key: Qt.Key_Escape, back: true } }]
             : [{ keys: ["↑", "↓"], label: "Move" }].concat(page.row.key === "app" ? [{ keys: ["SPACE"], label: "On / off" }] : []).concat([
                page.row.key === "app" ? { keys: ["ENTER"], label: "Details" }
                : page.row.kind === "opens" ? { keys: ["ENTER"], label: "Open" }
                : page.row.kind === "action" ? { keys: ["ENTER"], label: guide.settingsArmed ? "Again to do it" : "Do it" }
                : page.row.kind === "info" ? { keys: [], label: "" }
                : page.row.kind === "choice" ? { keys: ["ENTER"], label: "Change" } : { keys: ["ENTER"], label: "On / off" },
                { keys: ["←", "/", "ESC"], label: "Back", touch: { key: Qt.Key_Escape, back: true } },
                { keys: ["?"], label: "All keys" }])
      size: page.u * 1.55
      capStyle: guide.look.keycap
      labelStyle: guide.look.keyLabel
    }
  }
}
