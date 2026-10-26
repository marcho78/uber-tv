import QtQuick
import "../Look.js" as Look

// The nav rail: down the left of every screen, an icon for each part of the
// guide (Home, Live TV, the library's tabs, Settings), the one you're in lit,
// and at its foot a window (or full screen) and Turn off.
// Open (← at a screen's left edge, or the pointer over it) it widens with
// their names, over a shade. The layout says whether it shows always, only
// when you go to it, or never. What's on it is yours: C on the open rail (or
// Settings) customizes it, in a panel beside it, the rail changing as you go.
Item {
  id: rail

  required property var guide

  readonly property real u: guide.u
  readonly property real thinW: Math.round(u * guide.layout.railWidth)
  readonly property real openW: Math.round(u * guide.layout.railOpenWidth)
  readonly property bool wide: guide.railOpen || guide.railEditing || hover.hovered
  // the credits' room at its foot, kept whether it's wide or thin
  readonly property real creditRoom: guide.railCredits ? handle.implicitHeight + credit.spacing + site.implicitHeight + u : 0

  visible: guide.railEditing || (guide.railShows !== "none" && (guide.railShows === "always" || guide.railOpen) && !guide.watching)

  // The shade over the screen while it's open; a click closes it
  Rectangle {
    anchors.fill: parent
    visible: guide.railOpen || guide.railEditing
    color: Qt.rgba(0, 0, 0, 0.4)
    MouseArea { anchors.fill: parent; onClicked: guide.railEditing ? guide.closeRailPanel() : guide.closeRail() }
  }

  Box {
    id: strip
    width: rail.wide ? rail.openW : rail.thinW
    height: parent.height
    s: rail.wide ? guide.look["rail:open"] : guide.look.rail
    unit: rail.u
    clip: true
    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    HoverHandler { id: hover }

    Column {
      y: rail.u * 2.4
      x: strip.padding
      width: strip.width - strip.padding * 2
      spacing: rail.u * 0.5

      Repeater {
        model: guide.railItems
        delegate: Box {
          id: item
          required property var modelData
          required property int index
          readonly property bool current: modelData.key === guide.railCurrent
          readonly property bool focused: guide.railOpen && index === guide.railCursor
          readonly property var st: focused ? guide.look["railItem:focused"] : current ? guide.look["railItem:current"] : guide.look.railItem
          width: parent.width
          height: Math.round(rail.u * 3)
          s: st
          unit: rail.u

          Icon {
            id: icon
            // centered in the thin rail, so the icons don't move as it widens
            x: Math.round((rail.thinW - strip.padding * 2 - width) / 2)
            anchors.verticalCenter: parent.verticalCenter
            name: item.modelData.icon
            size: Math.round(rail.u * 1.45)
            color: item.st.text ? item.st.text.color : "white"
          }
          Label {
            anchors.left: icon.right
            anchors.leftMargin: rail.u * 0.9
            anchors.verticalCenter: parent.verticalCenter
            opacity: rail.wide ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            text: item.modelData.label
            s: item.st
            unit: rail.u
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            enabled: !guide.railEditing
            onClicked: guide.railGo(item.index)
          }
        }
      }
    }

    // At its foot: a window or full screen, and Turn off (guide.railSystem),
    // after the parts for the cursor, drawn the same way
    Column {
      id: foot
      x: strip.padding
      width: strip.width - strip.padding * 2
      anchors.bottom: parent.bottom
      anchors.bottomMargin: rail.u * 1.6 + rail.creditRoom + (guide.railOpen && guide.showKeyHints ? rail.u * 3 : 0)
      spacing: rail.u * 0.5
      visible: !guide.railEditing

      Repeater {
        model: guide.railSystem
        delegate: Box {
          id: sys
          required property var modelData
          required property int index
          readonly property bool focused: guide.railOpen && guide.railCursor === guide.railItems.length + index
          readonly property var st: focused ? guide.look["railItem:focused"] : guide.look.railItem
          width: parent.width
          height: Math.round(rail.u * 3)
          s: st
          unit: rail.u

          Icon {
            id: sysIcon
            x: Math.round((rail.thinW - strip.padding * 2 - width) / 2)
            anchors.verticalCenter: parent.verticalCenter
            name: sys.modelData.icon
            size: Math.round(rail.u * 1.45)
            color: sys.st.text ? sys.st.text.color : "white"
          }
          // an update to tell you about: a dot on its icon
          Rectangle {
            visible: sys.modelData.key === "update"
            width: Math.round(rail.u * 0.55)
            height: width
            radius: width / 2
            x: sysIcon.x + sysIcon.width - width * 0.6
            y: sysIcon.y - height * 0.2
            color: guide.colors.accent
          }
          Label {
            anchors.left: sysIcon.right
            anchors.leftMargin: rail.u * 0.9
            anchors.verticalCenter: parent.verticalCenter
            opacity: rail.wide ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            text: sys.modelData.label
            s: sys.st
            unit: rail.u
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: guide.railGo(guide.railItems.length + sys.index)
          }
        }
      }
    }

    // How to customize it, while it's open
    KeyHints {
      visible: guide.railOpen && (guide.showKeyHints || guide.touchMode)
      x: strip.padding + rail.u * 0.4
      anchors.bottom: parent.bottom
      anchors.bottomMargin: rail.u * 2 + rail.creditRoom
      touchGuide: rail.guide
      model: [{ keys: ["C"], label: "Customize", touch: { key: Qt.Key_C, icon: "pencil" } }]
      size: rail.u * 1.4
      capStyle: guide.look.keycap
      labelStyle: guide.look.keyLabel
    }

    // The credits at its very foot, while it's wide (Settings → About turns
    // them off): X's logo and the handle, then the website, each a link.
    // In the splash's mono, marks in the icons' column a step quieter than
    // the words in the names'. Their room stays while it's thin, so nothing
    // moves as it widens.
    FontLoader { id: creditFont; source: Qt.resolvedUrl("../fonts/DMMono-Medium.ttf") }
    Column {
      id: credit
      readonly property real markX: (rail.thinW - strip.padding * 2) / 2
      readonly property real textX: Math.round((rail.thinW - strip.padding * 2 - Math.round(rail.u * 1.45)) / 2) + Math.round(rail.u * 1.45) + rail.u * 0.9
      readonly property int textSize: Math.round(rail.u * 0.82)
      visible: guide.railCredits && !guide.railEditing
      opacity: rail.wide ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 120 } }
      x: strip.padding
      width: strip.width - strip.padding * 2
      anchors.bottom: parent.bottom
      anchors.bottomMargin: rail.u * 1.6
      spacing: rail.u * 0.35

      Item {
        width: parent.width
        height: handle.implicitHeight
        Icon {
          x: Math.round(credit.markX - width / 2)
          anchors.verticalCenter: parent.verticalCenter
          name: "xlogo"
          size: credit.textSize
          color: handle.color
          opacity: 0.68
        }
        Label {
          id: handle
          x: credit.textX
          text: "@devsec_ai"
          s: guide.look.railItem
          unit: rail.u
          font.family: creditFont.font.family
          font.pixelSize: credit.textSize
          font.weight: Font.Medium
          font.letterSpacing: rail.u * 0.02
          MouseArea {
            anchors.fill: parent
            enabled: rail.wide
            cursorShape: Qt.PointingHandCursor
            onClicked: guide.openCredit("x")
          }
        }
        // at the row's far end, as quiet as the marks: to their switch in
        // Settings (placed for the open width, so it doesn't slide in)
        Label {
          x: rail.openW - strip.padding * 2 - rail.u * 0.7 - width
          text: "Disable"
          s: guide.look.railItem
          unit: rail.u
          font.family: creditFont.font.family
          font.pixelSize: credit.textSize
          font.weight: Font.Medium
          font.letterSpacing: rail.u * 0.02
          opacity: 0.68
          MouseArea {
            anchors.fill: parent
            enabled: rail.wide
            cursorShape: Qt.PointingHandCursor
            onClicked: guide.openCreditSetting()
          }
        }
      }
      Item {
        width: parent.width
        height: site.implicitHeight
        Label {
          x: Math.round(credit.markX - width / 2)
          text: "W:"
          s: guide.look.railItem
          unit: rail.u
          font.family: creditFont.font.family
          font.pixelSize: credit.textSize
          font.weight: Font.Medium
          opacity: 0.68
        }
        Label {
          id: site
          x: credit.textX
          text: "devsecai.sh"
          s: guide.look.railItem
          unit: rail.u
          font.family: creditFont.font.family
          font.pixelSize: credit.textSize
          font.weight: Font.Medium
          font.letterSpacing: rail.u * 0.02
          MouseArea {
            anchors.fill: parent
            enabled: rail.wide
            cursorShape: Qt.PointingHandCursor
            onClicked: guide.openCredit("web")
          }
        }
      }
    }
  }

  // ---- Customize the rail: beside it, live ----
  Box {
    id: panel
    visible: guide.railEditing
    x: strip.width + rail.u
    y: rail.u
    width: Math.min(rail.width - x - rail.u, rail.u * 42)
    // as tall as its rows (worked out from them, not measured from the list)
    readonly property real rowsH: {
      var rowH = Math.round(Look.px(guide.look.menuRow.height, rail.u * 0.8))
      var gap = Math.round(rail.u * 0.4)
      return guide.railPanelRows.reduce(function(h, r) {
        return h + gap + (r.type === "header" ? (r.label ? rail.u * 2.6 : rail.u * 0.6) : rowH)
      }, 0)
    }
    height: Math.min(rail.height - rail.u * 2, panelTop.implicitHeight + rowsH + panelHints.implicitHeight + panel.padding * 3 + rail.u * 0.8)
    s: guide.look.box
    unit: rail.u
    image: guide.areaImages.box
    MouseArea { anchors.fill: parent }

    Column {
      id: panelTop
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: panel.padding
      spacing: rail.u * 0.4
      Label {
        text: "Customize the nav rail"
        s: guide.look.boxTitle
        unit: rail.u
        sizeFactor: 1.15
      }
      Label {
        width: parent.width
        text: "Which parts are on it, in what order, and when it shows. A part that's turned off in Settings stays off the rail until it's back on."
        s: guide.look.boxText
        unit: rail.u
        sizeFactor: 1.05
        wrapMode: Text.Wrap
      }
    }

    ListView {
      id: panelList
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: panelTop.bottom
      anchors.bottom: panelHints.top
      anchors.margins: panel.padding * 0.6
      anchors.topMargin: rail.u * 0.8
      clip: true
      spacing: rail.u * 0.4
      model: guide.railPanelRows
      currentIndex: guide.railEditCursor
      highlightRangeMode: ListView.ApplyRange
      preferredHighlightBegin: rail.u * 3
      preferredHighlightEnd: height - rail.u * 5
      boundsBehavior: Flickable.StopAtBounds
      // fixed heights from the start: a heading, or a TV-style row
      delegate: Item {
        id: prow
        required property var modelData
        required property int index
        readonly property string type: modelData.type
        readonly property var it: type === "railItem" ? guide.railSetup[modelData.index] : null
        readonly property var kind: it ? guide.railKind(it.key) : null
        readonly property bool available: !it || guide.railAvailable(it.key)
        width: panelList.width
        height: type === "header" ? (modelData.label ? rail.u * 2.6 : rail.u * 0.6) : line.implicitHeight

        Label {
          visible: prow.type === "header"
          x: Math.ceil(panelList.width * 0.03) + rail.u * 0.4
          anchors.bottom: parent.bottom
          anchors.bottomMargin: rail.u * 0.45
          text: prow.modelData.label || ""
          s: guide.look.menuHeader
          unit: rail.u
        }
        MenuRow {
          id: line
          visible: prow.type !== "header"
          guide: rail.guide
          width: parent.width
          height: implicitHeight
          size: 0.8
          focused: prow.index === guide.railEditCursor
          icon: prow.kind ? prow.kind.icon : ""
          label: prow.type === "railMode" ? "Show it" : prow.type === "railReset" ? "Back to how the rail came" : prow.kind ? prow.kind.label : ""
          kind: prow.type === "railMode" ? "choice" : prow.type === "railReset" ? "action" : prow.it && prow.it.key !== "settings" ? "switch" : "value"
          value: prow.type === "railMode" ? guide.railModeLabel(guide.layout.rail)
               : prow.it && prow.it.key === "settings" ? "Always"
               : prow.it && prow.it.on && !prow.available ? guide.railOffBecause(prow.it.key) : ""
          on: !!(prow.it && prow.it.on)
          dim: !prow.available
          danger: prow.type === "railReset"
          onActivated: { guide.railEditCursor = prow.index; guide.railPanelAct(1) }
          touchParts: true
          onStepped: function(dir) { guide.railEditCursor = prow.index; guide.railPanelAct(dir) }
        }
      }
    }

    Column {
      id: panelHints
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: panel.padding
      spacing: rail.u * 0.5
      KeyHints {
        touchGuide: rail.guide
        touchWidth: panelHints.width
        model: [{ keys: ["SPACE"], label: "On / off", touch: { key: Qt.Key_Space } }, { keys: ["SHIFT", "+", "↑", "↓"], label: "Move" }, { keys: ["←", "→"], label: "Change" }]
        size: rail.u * 1.4
        capStyle: guide.look.keycap
        labelStyle: guide.look.keyLabel
      }
      KeyHints {
        touchGuide: rail.guide
        touchWidth: panelHints.width
        model: [{ keys: ["↑", "↓"], label: "Move" }, { keys: ["C", "/", "ESC"], label: "Done", touch: { key: Qt.Key_Escape, back: true } }]
        size: rail.u * 1.4
        capStyle: guide.look.keycap
        labelStyle: guide.look.keyLabel
      }
    }
  }
}
