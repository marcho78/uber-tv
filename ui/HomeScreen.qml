import QtQuick
import QtQuick.Effects
import "../Look.js" as Look

// Home: the time, what's selected told large at the top (Continue watching,
// what's on, a movie), then the sections you chose: the tiles, Continue
// watching, On now, New on your channels, Starting soon, My List and rows you
// added. Over a background you choose. C customizes it, in a panel down the
// right side, live like the style panel. Every card in a row is one height;
// its width is its shape's (posters narrower, wide pictures wider, a square
// picture shown whole), so mixed rows like Continue watching and My List
// draw each card as it is. An app's card, and an app's own row by its name,
// show where the app is from as the Apps screen does (OriginBadge).
Item {
  id: home

  required property var guide

  readonly property real u: guide.u
  readonly property real thumbW: Math.round(u * guide.layout.homeCardWidth)
  readonly property real thumbH: Math.round(thumbW * 9 / 16)
  readonly property real tileH: Math.round(u * guide.layout.homeTileHeight)
  readonly property string topMode: guide.homeTop          // selected, clock, channel or off
  readonly property bool hero: topMode !== "off"
  readonly property string clockSpot: topMode === "clock" ? "none" : guide.layout.homeClock   // a big clock up top: no small one
  readonly property bool chips: guide.layout.homeChips
  // what the big title tells
  readonly property var topInfo: topMode === "channel" ? guide.homeLastChannel
                           : topMode === "clock" ? { kicker: Qt.formatDateTime(new Date(guide.now * 1000), "dddd"), title: guide.clock(guide.now),
                                                     meta: Qt.formatDateTime(new Date(guide.now * 1000), "MMMM d, yyyy"), progress: 0 }
                           : guide.homeHero
  readonly property real heroY: clockSpot === "left" ? u * 9.2 : chips ? u * 6 : u * 3
  // a compact screen: the big title across, and room under it for two lines
  // of title and two of its words, so the sections never cover them
  readonly property bool compact: guide.screenFit === "compact"
  readonly property color shade: guide.look.homeShade.color
  readonly property real titleH: Math.round(u * 2.6)
  readonly property real captionH: Math.round(u * 3.4)
  readonly property var bg: guide.homeBackground
  readonly property var bar: guide.look.vodProgress

  // a row's card size: small, medium or large (its options)
  function cardW(size) { return Math.round(thumbW * (size || 1)) }
  // black or white, whichever reads on an app's color
  function inkOn(c) {
    var m = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(c || "")
    if (!m) return guide.ink
    return (0.299 * parseInt(m[1], 16) + 0.587 * parseInt(m[2], 16) + 0.114 * parseInt(m[3], 16)) / 255 > 0.6 ? "#111111" : "#ffffff"
  }
  function cardH(size) { return Math.round(cardW(size) * 9 / 16) }
  function rowHeight(shape, size) { return titleH + (shape === "tile" ? tileH + u * 1.2 : cardH(size) + captionH) + Math.round(u * 1.4) }

  // ---- the background ----
  Image {
    id: backdrop
    anchors.fill: parent
    source: guide.homeBackdrop
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    visible: status === Image.Ready
    readonly property bool soft: home.bg.mode === "focus" && guide.homeCard !== null && guide.homeCard.kind !== "door"
    layer.enabled: soft
    layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 48; saturation: 0.1 }
  }
  // dark from the left and the bottom, so the words read over any picture
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: Qt.rgba(home.shade.r, home.shade.g, home.shade.b, home.bg.dim + 0.3 * (1 - home.bg.dim)) }
      GradientStop { position: 0.5; color: Qt.rgba(home.shade.r, home.shade.g, home.shade.b, home.bg.dim * 0.7) }
      GradientStop { position: 1; color: Qt.rgba(home.shade.r, home.shade.g, home.shade.b, home.bg.dim * 0.2) }
    }
  }
  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: parent.height * 0.62
    gradient: Gradient {
      GradientStop { position: 0; color: "transparent" }
      GradientStop { position: 0.55; color: Qt.rgba(home.shade.r, home.shade.g, home.shade.b, Math.min(0.97, home.bg.dim + 0.25)) }
    }
  }

  // ---- the time, and how things are ----
  Column {
    id: timeColumn
    visible: home.clockSpot !== "none"
    x: home.clockSpot === "right" ? parent.width - width - home.u * 3 : home.u * 3
    y: home.u * 2.4
    spacing: home.u * 0.2
    Label {
      anchors.right: home.clockSpot === "right" ? parent.right : undefined
      text: Qt.formatDateTime(new Date(guide.now * 1000), "dddd, MMMM d")
      s: guide.look.heroMeta
      unit: home.u
      sizeFactor: 0.85
    }
    Label {
      anchors.right: home.clockSpot === "right" ? parent.right : undefined
      text: guide.clock(guide.now)
      s: guide.look.clock
      unit: home.u
      sizeFactor: 3.2 / Math.max(0.2, guide.look.clock.text.size)
    }
  }
  // the status chips: on the other side from the clock
  Row {
    visible: home.chips
    x: home.clockSpot === "right" ? home.u * 3 : parent.width - width - home.u * 3
    y: home.u * 2.6
    spacing: home.u * 0.8
    Repeater {
      model: [guide.remoteEnabled ? "Phone remote · " + guide.remoteDevices.length + (guide.remoteDevices.length === 1 ? " phone" : " phones") : "",
              guide.fetchedAt ? "Listings · " + (Math.round((guide.now - guide.fetchedAt) / 60) < 60 ? Math.max(0, Math.round((guide.now - guide.fetchedAt) / 60)) + " min ago" : Math.round((guide.now - guide.fetchedAt) / 3600) + " h ago") : ""].filter(function(x) { return x })
      delegate: Box {
        id: chipBox
        required property string modelData
        height: chip.implicitHeight + chipBox.padding
        width: chip.implicitWidth + chipBox.padding * 2
        s: guide.look.statusChip
        unit: home.u
        Label {
          id: chip
          anchors.centerIn: parent
          text: chipBox.modelData
          s: guide.look.statusChip
          unit: home.u
        }
      }
    }
  }

  // ---- what's selected ----
  Column {
    id: hero
    visible: home.hero
    x: home.u * 3
    y: home.heroY
    width: home.compact ? parent.width - home.u * 6 : Math.min(parent.width * 0.58, home.u * 56)
    spacing: home.u * 0.7
    Label {
      text: home.topInfo.kicker
      s: guide.look.heroKicker
      unit: home.u
    }
    Label {
      width: parent.width
      text: guide.showTitle(home.topInfo.title)
      s: guide.look.heroTitle
      unit: home.u
      sizeFactor: home.topMode === "clock" ? 1.7 : 1
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
      lineHeight: 0.95
    }
    Label {
      width: parent.width
      text: home.topInfo.meta
      s: guide.look.heroMeta
      unit: home.u
      wrapMode: Text.Wrap
      maximumLineCount: 2
      elide: Text.ElideRight
    }
    Rectangle {
      visible: home.topInfo.progress > 0.01
      width: home.u * 22
      height: Math.max(3, Look.px(home.bar.height, home.u))
      radius: height / 2
      color: home.bar.track || "transparent"
      Rectangle {
        height: parent.height
        radius: parent.radius
        width: parent.width * home.topInfo.progress
        color: home.bar.fill && typeof home.bar.fill === "object" ? home.bar.fill.from : (home.bar.fill || "transparent")
      }
    }
  }

  // ---- the sections ----
  ListView {
    id: sections
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: home.hero ? home.heroY + home.u * (home.compact ? 16 : 13.3) : home.clockSpot === "left" ? home.u * 9 : home.chips ? home.u * 6 : home.u * 2.5
    anchors.bottom: footer.top
    anchors.bottomMargin: home.u * 0.4
    clip: true
    model: guide.homeView
    currentIndex: guide.homeRow
    highlightRangeMode: ListView.ApplyRange
    preferredHighlightBegin: 0
    preferredHighlightEnd: Math.max(0, height - home.rowHeight("thumb", 1))
    highlightMoveDuration: 220
    boundsBehavior: Flickable.StopAtBounds

    // fixed heights from the start
    delegate: Item {
      id: secItem
      required property var modelData
      required property int index
      readonly property bool currentRow: index === guide.homeRow
      readonly property int col: Math.min(modelData.cards.length - 1, guide.homeCols[modelData.key] || 0)
      readonly property bool tiles: modelData.shape === "tile"
      readonly property real cw: home.cardW(modelData.size)
      readonly property real ch: home.cardH(modelData.size)
      // an app's own row: where that app is from
      readonly property string ownerFrom: {
        if (modelData.type !== "appRow" || tiles) return ""
        var a = guide.apps.record(String(modelData.key).slice("appRow:".length).split("/")[0])
        return a ? a.from || "" : ""
      }
      width: sections.width
      height: home.rowHeight(modelData.shape, modelData.size)

      Label {
        id: rowTitle
        x: home.u * 3
        // beside a badge, cut short if need be: the app's name and its row's
        // label never push where it's from out of the row
        width: rowBadge.visible ? Math.max(0, Math.min(implicitWidth, secItem.width - x - home.u * 3 - rowBadge.anchors.leftMargin - rowBadge.width)) : implicitWidth
        height: home.titleH
        verticalAlignment: Text.AlignVCenter
        elide: rowBadge.visible ? Text.ElideRight : Text.ElideNone
        visible: !secItem.tiles
        text: secItem.modelData.title
        s: guide.look.homeRowTitle
        unit: home.u
      }
      // beside its name, as on the app's card: a link for one of your
      // sources, a page for a file; Uber TV's own, none
      OriginBadge {
        id: rowBadge
        anchors.left: rowTitle.right
        anchors.leftMargin: home.u * 0.6
        anchors.verticalCenter: rowTitle.verticalCenter
        guide: home.guide
        u: home.u
        from: secItem.ownerFrom
      }

      ListView {
        id: cards
        y: secItem.tiles ? home.u * 0.6 : home.titleH
        width: parent.width
        height: parent.height - y
        orientation: ListView.Horizontal
        spacing: home.u * (secItem.tiles ? 1 : 1.2)
        leftMargin: home.u * 3
        rightMargin: home.u * 3
        topMargin: home.u * 0.5
        model: secItem.modelData.cards
        currentIndex: secItem.col
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: home.u * 3
        preferredHighlightEnd: width - home.u * 3 - (secItem.tiles ? home.u * 15 : secItem.cw)
        highlightMoveDuration: 200
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        delegate: Item {
          id: card
          required property var modelData
          required property int index
          readonly property bool current: secItem.currentRow && index === secItem.col
          // its shape at the row's height: a poster 2:3, a square 1:1, else 16:9
          readonly property string shape: modelData.shape === "poster" || modelData.shape === "square" ? modelData.shape : "wide"
          readonly property real picW: shape === "poster" ? Math.round(secItem.ch * 2 / 3) : shape === "square" ? secItem.ch : secItem.cw
          readonly property bool whole: (modelData.kind === "channel" && !modelData.videoId) || modelData.kind === "app" || shape === "square"
          width: secItem.tiles ? Math.max(home.u * 15, (cards.width - home.u * 6 - home.u * 3) / Math.max(1, secItem.modelData.cards.length)) : picW
          height: secItem.tiles ? home.tileH : secItem.ch + home.captionH

          // A tile: where it goes, and how much is there
          Box {
            visible: secItem.tiles
            anchors.fill: parent
            s: card.current ? guide.look["homeTile:current"] : guide.look.homeTile
            unit: home.u
            scale: card.current ? 1.04 : 1
            Behavior on scale { NumberAnimation { duration: 140 } }
            Column {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: parent.padding
              spacing: home.u * 0.15
              Label {
                width: parent.width
                text: guide.showTitle(card.modelData.title)
                s: card.current ? guide.look["homeTile:current"] : guide.look.homeTile
                unit: home.u
                elide: Text.ElideRight
              }
              Label {
                width: parent.width
                text: card.modelData.sub || ""
                s: card.current ? guide.look["homeTile:current"] : guide.look.homeTile
                unit: home.u
                sizeFactor: 0.62
                font.weight: Font.Normal
                opacity: 0.8
                elide: Text.ElideRight
              }
            }
            // an app's tile: where it's from, as on its card
            Loader {
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: home.u * 0.5
              active: secItem.tiles && card.modelData.kind === "app"
              sourceComponent: OriginBadge { guide: home.guide; u: home.u; from: card.modelData.from || "" }
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                guide.homeRow = secItem.index
                var cols = {}
                for (var k in guide.homeCols) cols[k] = guide.homeCols[k]
                cols[secItem.modelData.key] = card.index
                guide.homeCols = cols
                guide.homeOpen()
              }
            }
          }

          // A card: its picture, how far in, and what it is
          Item {
            visible: !secItem.tiles
            anchors.fill: parent
            Box {
              id: frame
              width: parent.width
              height: secItem.ch
              s: card.current ? guide.look["homeCard:current"] : guide.look.homeCard
              unit: home.u
              scale: card.current ? 1.05 : 1
              Behavior on scale { NumberAnimation { duration: 140 } }
              z: card.current ? 2 : 0
              // an app's own color, behind its icon or name
              Rectangle {
                anchors.fill: parent
                anchors.margins: frame.borderWidth
                visible: card.modelData.kind === "app" && !!card.modelData.color
                radius: Math.max(0, frame.corners[0] - frame.borderWidth)
                color: card.modelData.color || "transparent"
              }
              Image {
                id: pic
                anchors.fill: parent
                source: secItem.tiles ? "" : guide.posterFor(card.modelData.entry || { poster: card.modelData.poster, videoId: card.modelData.videoId, live: card.modelData.live })
                sourceSize.width: Math.max(200, Math.min(960, Math.ceil(card.width * (Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1))))
                // a channel's logo, an app's icon and a square picture show
                // whole; pictures fill
                fillMode: card.whole ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                anchors.margins: card.whole && card.shape !== "square" ? home.u * 1.2 : frame.borderWidth
                asynchronous: true
                clip: true
                // an app's picture that came but can't be drawn: fetched
                // again (once, until one draws fine)
                onStatusChanged: {
                  if (secItem.modelData.type !== "appRow" || card.modelData.kind !== "appItem") return
                  var k = String(secItem.modelData.key).slice("appRow:".length)
                  if (status === Image.Error && source != "") guide.appHome.pictureBroken(k, card.modelData)
                  else if (status === Image.Ready) guide.appHome.pictureDrawn(k, card.modelData)
                }
              }
              // a channel's card without its picture (not yet, or none): its logo, whole
              Image {
                id: logoPic
                anchors.fill: parent
                anchors.margins: home.u * 1.2
                visible: pic.status !== Image.Ready
                source: !secItem.tiles && pic.status !== Image.Ready && card.modelData.kind === "channel" ? card.modelData.logo || "" : ""
                sourceSize.width: 192
                fillMode: Image.PreserveAspectFit
                asynchronous: true
              }
              Label {
                anchors.fill: parent
                anchors.margins: home.u * 0.8
                visible: pic.status !== Image.Ready && logoPic.status !== Image.Ready
                text: guide.showTitle(card.modelData.title)
                s: guide.look.homeCardTitle
                unit: home.u
                sizeFactor: card.modelData.kind === "app" ? 1.5 : 1.2
                color: card.modelData.kind === "app" && card.modelData.color ? home.inkOn(card.modelData.color) : (guide.look.homeCardTitle.text ? guide.look.homeCardTitle.text.color : guide.ink)
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
              }
              Box {
                id: liveBadge
                visible: card.modelData.live === true
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: home.u * 0.5
                width: liveText.implicitWidth + liveBadge.padding * 2
                height: liveText.implicitHeight + liveBadge.padding * 0.6
                s: guide.look.liveBadge
                unit: home.u
                Label {
                  id: liveText
                  anchors.centerIn: parent
                  text: "● Live"
                  s: guide.look.liveBadge
                  unit: home.u
                }
              }
              Rectangle {
                visible: (card.modelData.progress || 0) > 0.01
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: frame.borderWidth + home.u * 0.4
                height: Math.max(3, Look.px(home.bar.height, home.u))
                radius: height / 2
                color: home.bar.track || "transparent"
                Rectangle {
                  height: parent.height
                  radius: parent.radius
                  width: parent.width * (card.modelData.progress || 0)
                  color: home.bar.fill && typeof home.bar.fill === "object" ? home.bar.fill.from : (home.bar.fill || "transparent")
                }
              }
              // an app installed from a signed or Developer-mode file,
              // as on the Apps screen's tile: a small badge over its picture,
              // no words; Uber TV's own (bundled, the catalog), none. Made
              // only for an app's card drawn as one, so the rest stay cheap
              Loader {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: home.u * 0.5
                active: !secItem.tiles && card.modelData.kind === "app"
                sourceComponent: OriginBadge { guide: home.guide; u: home.u; from: card.modelData.from || "" }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  guide.homeRow = secItem.index
                  var cols = {}
                  for (var k in guide.homeCols) cols[k] = guide.homeCols[k]
                  cols[secItem.modelData.key] = card.index
                  guide.homeCols = cols
                  // an app opens at once, as on a TV; anything at once with a finger
                  if (card.modelData.kind === "app" || guide.touchMode) guide.homeOpen()
                }
                onDoubleClicked: if (card.modelData.kind !== "app" && !guide.touchMode) guide.homeOpen()
              }
            }
            Column {
              y: secItem.ch + home.u * 0.6
              width: parent.width
              spacing: home.u * 0.15
              Label {
                width: parent.width
                text: guide.showTitle(card.modelData.title)
                s: guide.look.homeCardTitle
                unit: home.u
                elide: Text.ElideRight
              }
              Label {
                width: parent.width
                visible: text !== ""
                text: card.modelData.sub || ""
                s: guide.look.homeCardSub
                unit: home.u
                elide: Text.ElideRight
              }
            }
          }
        }
      }
    }
  }

  // Nothing on Home
  Label {
    anchors.horizontalCenter: sections.horizontalCenter
    y: sections.y + home.u * 3
    visible: guide.homeView.length === 0
    text: "Nothing on Home yet: C chooses what goes here"
    s: guide.look.boxText
    unit: home.u
  }

  // ---- the keys ----
  Box {
    id: footer
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: home.u * 3
    anchors.rightMargin: home.u * 3
    anchors.bottomMargin: home.u * 1.6
    // tablet mode: the buttons, always there, a finger tall (a tap on a card opens it)
    height: guide.touchMode ? guide.fingerPx + home.u * 0.6 : guide.showKeyHints ? home.u * 1.9 : 0
    visible: guide.showKeyHints || guide.touchMode
    s: guide.look.footer
    unit: home.u
    KeyHints {
      id: homeKeys
      anchors.left: parent.left
      anchors.leftMargin: footer.padding
      anchors.verticalCenter: parent.verticalCenter
      transformOrigin: Item.Left
      scale: homeKeys.touching ? 1 : Math.min(1, (footer.width - footer.padding * 2) / Math.max(1, implicitWidth))
      touchGuide: home.guide
      touchWidth: footer.width - footer.padding * 2
      model: guide.homeEditing ? [] : [{ keys: ["↑", "↓", "←", "→"], label: "Move" }]
                                       .concat(guide.railShows === "focus" ? [{ keys: ["←"], label: "Nav rail", touchOnly: true, touch: { run: function() { home.guide.openRail() }, icon: "menu" } }] : [])
                                       .concat([{ keys: ["ENTER"], label: "Open" }, { keys: ["G"], label: "Guide", touch: { key: Qt.Key_G, icon: "tv" } },
                                       { keys: ["V"], label: "Library", touch: { key: Qt.Key_V, icon: "film" } }, { keys: ["/"], label: "Search", touch: { key: Qt.Key_Slash, icon: "search" } },
                                       { keys: ["C"], label: "Customize Home", touch: { key: Qt.Key_C, icon: "pencil" } }, { keys: ["T"], label: "Phone remote", touch: { key: Qt.Key_T } },
                                       { keys: ["W"], label: guide.windowed ? "Full screen" : "Window", touch: { key: Qt.Key_W, icon: guide.windowed ? "fullscreen" : "window" } },
                                       { keys: ["S"], label: "Style", touch: { key: Qt.Key_S } }, { keys: [","], label: "Settings", touch: { key: Qt.Key_Comma, icon: "gear" } }, { keys: ["?"], label: "All keys" },
                                       { keys: ["K"], label: "Hide keys" }, { keys: ["ESC"], label: "Close", touch: { key: Qt.Key_Escape, back: true } }])
      size: home.u * 1.55
      capStyle: guide.look.keycap
      labelStyle: guide.look.keyLabel
    }
  }

  // ---- Customize Home (C): down the right, live ----
  Box {
    id: panel
    visible: guide.homeEditing
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.margins: home.u
    width: Math.min(parent.width * 0.46, home.u * 42)
    s: guide.look.box
    unit: home.u
    image: guide.areaImages.box
    MouseArea { anchors.fill: parent }

    Column {
      id: panelTop
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: panel.padding
      spacing: home.u * 0.4
      Label {
        text: guide.homeAdding ? "Add a row" : guide.homeOptions >= 0 ? "Row options" : "Customize Home"
        s: guide.look.boxTitle
        unit: home.u
        sizeFactor: 1.15
      }
      Label {
        width: parent.width
        text: guide.homeAdding ? "A row of a movie genre, a My Videos folder, a YouTube channel's videos, what's coming up on a channel, or what's on in a category."
            : guide.homeOptions >= 0 ? "Its name, card size, its pictures' shape, how many cards and their order. Changes show as you go."
            : "What's at the top, the rows and tiles in your order, and the picture behind. Space turns one on or off, Enter opens a row's options."
        s: guide.look.boxText
        unit: home.u
        sizeFactor: 1.05
        wrapMode: Text.Wrap
      }
    }

    // A row's name, being typed
    Box {
      id: renameBox
      visible: guide.homeRenaming
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: panelTop.bottom
      anchors.margins: panel.padding
      anchors.topMargin: home.u * 0.8
      height: home.u * 3.4
      s: renameField.activeFocus ? guide.look["input:focused"] : guide.look.input
      unit: home.u
      z: 3
      TextInput {
        id: renameField
        anchors.fill: parent
        anchors.leftMargin: home.u
        anchors.rightMargin: home.u
        verticalAlignment: TextInput.AlignVCenter
        color: guide.ink
        selectionColor: guide.cellEdge
        font.family: guide.fonts.body
        font.pixelSize: home.u * 1.3
        maximumLength: 40
        clip: true
        onAccepted: guide.renameHomeSection(text)
        Keys.onPressed: function(event) { guide.keyFirst(event) }
        Keys.onEscapePressed: { if (guide.keyFirst(event)) return; guide.closeHomePanel() }
      }
      onVisibleChanged: if (visible) { renameField.text = guide.homeRenameStart; renameField.selectAll(); renameField.forceActiveFocus() }
    }

    ListView {
      id: panelList
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: renameBox.visible ? renameBox.bottom : panelTop.bottom
      anchors.bottom: panelHints.top
      anchors.margins: panel.padding * 0.6
      anchors.topMargin: home.u * 0.8
      clip: true
      spacing: home.u * 0.4
      model: guide.homePanelRows
      currentIndex: guide.homeCursor
      highlightRangeMode: ListView.ApplyRange
      preferredHighlightBegin: home.u * 3
      preferredHighlightEnd: height - home.u * 5
      highlightMoveDuration: 160
      boundsBehavior: Flickable.StopAtBounds
      // fixed heights from the start: a heading, or a TV-style row
      delegate: Item {
        id: prow
        required property var modelData
        required property int index
        readonly property string type: modelData.type
        readonly property var sec: type === "section" ? guide.homeSections[modelData.index] : null
        width: panelList.width
        height: type === "header" ? (modelData.label ? home.u * 2.6 : home.u * 0.6) : line.implicitHeight

        Label {
          visible: prow.type === "header"
          x: Math.ceil(panelList.width * 0.03) + home.u * 0.4
          anchors.bottom: parent.bottom
          anchors.bottomMargin: home.u * 0.45
          text: prow.modelData.label || ""
          s: guide.look.menuHeader
          unit: home.u
        }
        MenuRow {
          id: line
          visible: prow.type !== "header"
          guide: home.guide
          width: parent.width
          height: implicitHeight
          size: 0.8
          focused: prow.index === guide.homeCursor
          readonly property var opt: guide.homeOptions >= 0 ? guide.homeSections[guide.homeOptions] : null
          label: { var t = prow.type
                   return t === "screenTop" ? "The top shows" : t === "screenClock" ? "Clock" : t === "screenChips" ? "Status chips"
                        : t === "bgMode" ? "Background" : t === "bgPick" ? "Pick a picture" : t === "bgDim" ? "Darken it"
                        : t === "section" ? guide.homeTitle(prow.sec) : t === "addRow" ? "Add a row" : t === "homeReset" ? "Back to how Home came"
                        : t === "optOn" ? "Shown" : t === "optName" ? "Name" : t === "optSize" ? "Card size" : t === "optShape" ? "Pictures" : t === "optLimit" ? "Cards"
                        : t === "optSort" ? "Order" : t === "optRemove" ? "Take this row off"
                        : prow.modelData.label || "" }
          kind: { var t = prow.type
                  return ["screenTop", "screenClock", "bgMode", "bgDim", "optSize", "optShape", "optLimit", "optSort"].indexOf(t) >= 0 ? "choice"
                       : t === "bgPick" || t === "addRow" || t === "optName" ? "opens"
                       : ["section", "tile", "screenChips", "optOn"].indexOf(t) >= 0 ? "switch"
                       : t === "homeReset" || t === "add" || t === "optRemove" ? "action" : "value" }
          value: { var t = prow.type
                   return t === "screenTop" ? guide.homeTopLabel(guide.homeTop)
                        : t === "screenClock" ? guide.homeClockLabel(guide.layout.homeClock)
                        : t === "bgMode" ? guide.homeBgLabel(home.bg.mode)
                        : t === "bgPick" ? (guide.homePictureNote || (home.bg.image ? (/\/app-pictures\/[0-9a-f]{32}\./.test(home.bg.image) ? "Yours" : home.bg.image.split("/").pop()) : "None yet"))
                        : t === "bgDim" ? Math.round(home.bg.dim * 100) + "%"
                        : t === "optName" && line.opt ? guide.homeTitle(line.opt)
                        : t === "optSize" && line.opt ? guide.homeSizeLabel(line.opt.size || "medium")
                        : t === "optShape" && line.opt ? guide.homeShapeLabel(line.opt.shape || "")
                        : t === "optLimit" && line.opt ? guide.homeLimitLabel(line.opt.limit || 0)
                        : t === "optSort" && line.opt ? guide.homeSortLabel(line.opt.sort || "default")
                        : t === "add" ? "Add" : "" }
          on: prow.type === "section" ? !!(prow.sec && prow.sec.on) : prow.type === "tile" ? guide.homeTiles.indexOf(prow.modelData.key) >= 0
            : prow.type === "screenChips" ? guide.layout.homeChips : prow.type === "optOn" ? !!(line.opt && line.opt.on) : false
          more: prow.type === "section" && !!prow.sec && prow.sec.type !== "doors"
          danger: prow.type === "homeReset" || prow.type === "optRemove"
          onActivated: { guide.homeCursor = prow.index; guide.homePanelAct(1) }
          touchParts: true
          onStepped: function(dir) { guide.homeCursor = prow.index; guide.homePanelAct(dir) }
          onToggled: { guide.homeCursor = prow.index; guide.homePanelToggle() }
        }
      }
    }

    Column {
      id: panelHints
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: panel.padding
      spacing: home.u * 0.5
      // (tablet mode: the name field has the keys while renaming, so its
      // buttons run what the field does)
      KeyHints {
        touchGuide: home.guide
        touchWidth: panelHints.width
        model: guide.homeRenaming ? [{ keys: ["ENTER"], label: "Save the name", touch: { run: function() { home.guide.renameHomeSection(renameField.text) }, primary: true } }, { keys: [], label: "(empty: its own)" },
                                     { keys: ["ESC"], label: "Cancel", touch: { run: function() { home.guide.closeHomePanel() }, back: true } }]
             : guide.homeAdding ? [{ keys: ["ENTER"], label: "Add", touch: { key: Qt.Key_Return, primary: true } }, { keys: ["ESC"], label: "Back", touch: { key: Qt.Key_Escape, back: true } }]
             : guide.homeOptions >= 0 ? [{ keys: ["ENTER"], label: "Change", touch: { key: Qt.Key_Return } }, { keys: ["←", "→"], label: "Change" }, { keys: ["ESC"], label: "Back to the rows", touch: { key: Qt.Key_Escape, back: true } }]
             : [{ keys: ["SPACE"], label: "On / off", touch: { key: Qt.Key_Space } }, { keys: ["ENTER"], label: "Options", touch: { key: Qt.Key_Return } }, { keys: ["SHIFT", "+", "↑", "↓"], label: "Move" },
                { keys: ["DEL"], label: "Remove", touch: { key: Qt.Key_Delete } }]
        size: home.u * 1.4
        capStyle: guide.look.keycap
        labelStyle: guide.look.keyLabel
      }
      KeyHints {
        touchGuide: home.guide
        touchWidth: panelHints.width
        model: guide.homeOptions >= 0 || guide.homeAdding || guide.homeRenaming ? [{ keys: ["↑", "↓"], label: "Move" }]
             : [{ keys: ["↑", "↓"], label: "Move" }, { keys: ["←", "→"], label: "Change" }, { keys: ["C", "/", "ESC"], label: "Done", touch: { key: Qt.Key_Escape, back: true } }]
        size: home.u * 1.4
        capStyle: guide.look.keycap
        labelStyle: guide.look.keyLabel
      }
    }
  }
}
