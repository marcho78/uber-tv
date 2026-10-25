import QtQuick

// Full-screen TV: black behind the picture, and the channel banner (the
// lower third). The picture itself (Guide.qml's video) moves in here.
Rectangle {
  id: tvScreen

  required property var guide

  visible: guide.watching
  color: "black"

  // The mouse, as on a TV player: moving it shows the banner (or the player
  // bar), a click pauses (or shows the banner), a double-click goes back.
  // Nothing stays on the picture: still for a moment, the pointer hides too.
  property bool pointerIdle: false
  property real bannerAt: 0

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: tvScreen.pointerIdle ? Qt.BlankCursor : Qt.ArrowCursor
    onPositionChanged: {
      tvScreen.pointerIdle = false
      idle.restart()
      if (Date.now() - tvScreen.bannerAt > 1500) {
        tvScreen.bannerAt = Date.now()
        guide.vod ? guide.showVodBar() : guide.showBanner()
      }
    }
    onClicked: guide.vod ? guide.togglePause() : guide.showBanner()
    onDoubleClicked: guide.vod ? guide.stopVod() : guide.showGuide()
  }

  Timer {
    id: idle
    interval: 2500
    running: tvScreen.visible
    onTriggered: tvScreen.pointerIdle = true
  }

  // On demand: the player bar
  VodBar {
    id: vodBar
    z: 2
    visible: guide.vod !== null && (guide.vodBarShown || guide.vodPaused || guide.reception !== "on" || vodBar.held)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: guide.u * 2
    guide: tvScreen.guide
  }

  // The channel banner (the lower third)
  LowerThird {
    z: 2
    visible: (guide.bannerShown || guide.bannerOptions) && guide.vod === null
    anchors.fill: parent
    look: guide.look
    image: guide.areaImages.lt
    unit: guide.u
    logo: guide.logoFor(guide.channels[guide.tunedRow])
    number: guide.numbers[guide.tunedRow] || ""
    channel: guide.channels[guide.tunedRow] ? guide.channels[guide.tunedRow].name : ""
    title: guide.onAir ? guide.showTitle(guide.onAir.title) : ""
    progress: guide.onAir && (!guide.onAir.live || guide.onAir.epg) ? Math.max(0, (guide.now - guide.onAir.start) / (guide.onAir.end - guide.onAir.start)) : -1
    clock: guide.clock(guide.now)
    times: !guide.onAir ? "" : guide.onAir.live && !guide.onAir.epg ? "● LIVE" : guide.clock(guide.onAir.start) + " – " + guide.clock(guide.onAir.end)
    options: guide.bannerOptions ? guide.bannerActions : []
    recording: guide.recBadge
    timeshift: guide.pauser.chipText
    behindLive: guide.pauser.active && !guide.pauser.atLive
    note: guide.recNote
    optionFocus: guide.bannerAct
    onOptionPicked: function(i) { guide.bannerAct = i; guide.pickBannerAct(i) }
    controls: guide.playerControls && guide.vod === null
    controlsAt: guide.controlsAt
    controlsMark: guide.scrub && !guide.scrub.movie ? guide.scrubFrac : -1
    controlsChip: guide.controlsChip
    controlsPaused: guide.pauser.paused
    onControlsPicked: function(what) { guide.controlsAct(what) }
    onControlsPressed: function(f) { if (guide.scrubStart(0, false)) guide.scrubTo(f) }
    onControlsMoved: function(f) { guide.scrubTo(f) }
    onControlsReleased: guide.scrubEnd()
    onControlsCanceled: guide.cancelScrub()
  }

  // Behind live (pause and rewind), on the picture while the banner's away
  Box {
    id: behindChip
    z: 2
    visible: guide.pauser.active && !guide.pauser.atLive && guide.vod === null && !guide.bannerShown && !guide.bannerOptions && !guide.playerControls
    readonly property var st: guide.look["liveChip:behind"] || guide.look.liveChip || ({})
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: guide.u * 1.5
    width: behindText.implicitWidth + padding * 2
    height: behindText.implicitHeight + padding * 0.6
    s: behindChip.st
    unit: guide.u
    Label {
      id: behindText
      anchors.centerIn: parent
      text: guide.pauser.chipText
      s: behindChip.st
      unit: guide.u
    }
  }

  // Choosing on the banner: its keys, top left
  KeyHints {
    z: 2
    visible: guide.bannerOptions && guide.bannerShown && guide.vod === null
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: guide.u * 1.5
    size: guide.u * 1.55
    capStyle: guide.look.keycap
    labelStyle: guide.look.keyLabel
    model: [{ keys: ["←", "→"], label: "Choose" }].concat(guide.recStopMenu || guide.streamAsk || guide.tsOffMenu || guide.tsCantMenu ? [] : [{ keys: ["↑"], label: "Controls" }])
             .concat([{ keys: ["ENTER"], label: "Pick" }, { keys: ["ESC"], label: guide.recStopMenu ? "Back" : "Hide" }])
  }
  // The player controls: their keys, top left
  KeyHints {
    z: 2
    visible: guide.playerControls && guide.vod === null
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: guide.u * 1.5
    size: guide.u * 1.55
    capStyle: guide.look.keycap
    labelStyle: guide.look.keyLabel
    model: [{ keys: ["←", "→"], label: "30 s" }, { keys: ["ENTER"], label: guide.pauser.paused ? "Play" : "Pause" }, { keys: ["↓"], label: "Back" }, { keys: ["ESC"], label: "Hide" }]
  }
}
