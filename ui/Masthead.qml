import QtQuick

// Across the top: the title (or your logo), what's shown, what's recording,
// the clock, and while the AI agent skill is off, a strip offering it. A layout without a
// masthead still shows the strip, until you've said yes or no.
Item {
  id: masthead

  required property var guide

  height: Math.max(guide.u * 3, guide.railButtonUp ? guide.fingerPx : 0)

  Row {
    visible: guide.layout.masthead === "title"
    anchors.verticalCenter: parent.verticalCenter
    spacing: guide.u
    // the rail tucked away (a compact screen, or Focus in tablet mode): ☰ opens it
    TouchButton {
      visible: guide.railButtonUp
      anchors.verticalCenter: parent.verticalCenter
      guide: masthead.guide
      icon: "menu"
      accessibleName: "Nav rail"
      onTapped: masthead.guide.openRail()
    }
    Image {
      id: mastLogo
      anchors.verticalCenter: parent.verticalCenter
      visible: guide.areaImages.masthead !== null && status === Image.Ready
      height: guide.u * 3
      width: visible ? Math.min(masthead.width * 0.4, height * sourceSize.width / Math.max(1, sourceSize.height)) : 0
      source: guide.areaImages.masthead ? guide.areaImages.masthead.url : ""
      opacity: guide.areaImages.masthead ? guide.areaImages.masthead.opacity : 1
      fillMode: Image.PreserveAspectFit
      horizontalAlignment: Image.AlignLeft
      asynchronous: true
      smooth: true
      mipmap: true
    }
    Label {
      visible: !mastLogo.visible
      text: "Uber TV" + (guide.layout.titleDate ? " · " + Qt.formatDateTime(new Date(guide.now * 1000), "dddd d") : "")
      s: guide.look.title
      unit: guide.u
    }
    Label {
      anchors.verticalCenter: parent.verticalCenter
      visible: guide.hasCategories || guide.managing || guide.hasIptv
      width: Math.min(implicitWidth, masthead.width * 0.45)
      text: guide.managing ? "Managing channels" + (guide.markedCount ? "  ·  " + guide.markedCount + " marked" : "")
          : guide.hasIptv && guide.shownSource !== "both" && !guide.shownCategories.length ? "Showing  " + guide.sourceName(guide.shownSource)
          : guide.filtered ? "Showing  " + guide.shownCategories.filter(function(c) { return guide.categories.indexOf(c) >= 0 })
                                               .map(guide.categoryName).join(" · ")
                          : "All channels"
      s: guide.managing ? guide.look["showing:managing"] : guide.filtered ? guide.look["showing:filtered"] : guide.look.showing
      unit: guide.u
      elide: Text.ElideRight
    }
  }

  Label {
    id: mastClock
    visible: guide.layout.masthead === "title" && guide.layout.clock === "masthead"
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: guide.clock(guide.now)
    s: guide.look.clock
    unit: guide.u
  }

  // What's recording (● Recording CBS News, ● 2 recording), left of the clock
  Label {
    id: mastRec
    visible: guide.layout.masthead === "title" && guide.recordingNow !== ""
    anchors.right: agentStrip.visible ? agentStrip.left : mastClock.visible ? mastClock.left : parent.right
    anchors.rightMargin: agentStrip.visible || mastClock.visible ? guide.u * 1.5 : 0
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(implicitWidth, masthead.width * 0.3)
    text: guide.recordingNow
    s: guide.look.mastheadRec
    unit: guide.u
    elide: Text.ElideRight
  }

  // While the AI agent skill is off, and you haven't said yes or no
  Rectangle {
    id: agentStrip
    visible: guide.agentStripUp
    anchors.right: mastClock.visible ? mastClock.left : parent.right
    anchors.rightMargin: mastClock.visible ? guide.u * 1.5 : 0
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(stripRow.implicitWidth + guide.u * 1.2, masthead.width * 0.5)
    height: guide.u * 2.1
    radius: height / 2
    color: "transparent"
    border.color: guide.marquee
    border.width: Math.max(1, guide.gap / 2)
    clip: true

    Row {
      id: stripRow
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: guide.u * 0.6
      spacing: guide.u * 0.6

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: "AI AGENTS CAN THEME THE GUIDE AND ADD PLAYLISTS FOR YOU"
        color: guide.ink
        font.family: guide.fonts.body
        font.pixelSize: guide.u * 0.8
        font.bold: true
      }
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: turnOnText.implicitWidth + guide.u
        height: guide.u * 1.5
        radius: height / 2
        color: turnOnMouse.containsMouse ? Qt.lighter(guide.marquee, 1.15) : guide.marquee
        Text {
          id: turnOnText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "TURN ON"
          color: guide.marqueeInk
          font.family: guide.fonts.body
          font.pixelSize: guide.u * 0.75
          font.bold: true
        }
        MouseArea {
          id: turnOnMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: guide.setAgentSkill(true)
        }
      }
      KeyHints {
        anchors.verticalCenter: parent.verticalCenter
        model: [{ keys: [","], label: "Settings" }]
        size: guide.u * 1.1
        capStyle: guide.look.keycap
        labelStyle: guide.look.keyLabel
      }
      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: "✕"
        color: dismissMouse.containsMouse ? guide.ink : guide.dimInk
        font.family: guide.fonts.body
        font.pixelSize: guide.u * 0.95
        font.bold: true
        MouseArea {
          id: dismissMouse
          anchors.fill: parent
          anchors.margins: -guide.u * 0.3
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { guide.agentSettled = true; guide.saveSettings() }
        }
      }
    }
  }
}
