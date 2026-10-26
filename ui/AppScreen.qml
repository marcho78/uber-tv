import QtQuick
import "../Look.js" as Look
import "../AppNav.js" as Nav
import "../AppLooks.js" as Looks

// An app with code, full screen in the guide: who it is (the guide's own
// identity strip, always on top), the screen's title, what's selected at
// the top when the look shows it, then the screen it sent (rows of cards,
// featured rows, grids, lists) or an item's details (Classic: its picture,
// title, line, chips, facts and text; Cinematic: its backdrop across the
// screen, its title logo or title, line, chips and text), then buttons and
// more rows. All drawn by the guide from what the helper checked, as plain
// text, laid out by the presentation model (AppLooks.js, as view.model):
// the look in force and what it sets, and each line's picture shape, card
// size, titles and columns. The app never draws anything and never sees a
// key: the arrows move, Enter does what the item says (opens it, plays it,
// shows its details), I shows details, / searches the app, , opens its
// settings, Esc goes back. Pictures come from the app's package or,
// fetched and checked by the helper, as local files, decoded no bigger than
// their box. Styled by the APPS parts (appCard, appRowTitle, appTopTitle,
// appDetailTitle, appChip, appButton, appShade…), which follow the
// library's, Home's and the menus' until styled; the guide's own focus ring,
// the selected title's contrast and the floors go on top of any theme.
Item {
  id: page

  required property var guide

  readonly property var view: guide.appView
  readonly property real u: guide.u
  readonly property var app: view.record
  readonly property var cur: view.topView
  readonly property var model: view.model
  readonly property var ls: model.lines
  readonly property var geo: model.geometry
  readonly property var screen: model.screen
  readonly property bool detail: !!page.cur && page.cur.kind === "detail" && !!page.cur.value
  readonly property bool cinematic: page.detail && model.detailStyle === "cinematic"
  readonly property var sel: Nav.locate(page.ls, view.sel)     // where the selection is: { line, col }
  // a click or a tap on an item: the cursor there; a second click (a tap in
  // tablet mode) opens it, as Enter
  function tap(line, col) {
    var was = page.sel && page.sel.line === line && page.sel.col === col
    if (!view.pick(line, col)) return
    if (was || guide.touchMode) view.enter(guide.byUser)
  }
  readonly property real titleH: geo.titleH
  readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  // what's around a card, and directly behind its title: the page's fill
  // all along it, and whatever picture the background puts behind it under
  // its shade (AppBackdrop.behind). The ring and the selected title read
  // against every color that can be there.
  readonly property var pageFill: guide.look.background ? guide.look.background.fill : ""
  readonly property var around: Looks.behindColors(backdrop.behind)
  readonly property string pageColor: Looks.behindColors({ fill: page.pageFill, base: String(guide.colors.bgBottom) })[0]
  readonly property string ringColor: Looks.ringColor(String(guide.colors.accent), String(guide.ink), page.pageColor, page.around)
  readonly property var selectedTitle: Looks.titleColor(String(guide.look.appCardTitle && guide.look.appCardTitle.text ? guide.look.appCardTitle.text.color : ""),
                                                        String(guide.ink), page.pageColor, page.around)
  readonly property string ringHalo: Looks.ringHalo(page.ringColor, page.around)
  readonly property real ringW: Math.max(2, Math.ceil(u * 0.15))

  // the selected card (or list row, or button) kept on the screen, from the
  // model's own geometry: a grid or a list taller than the screen scrolls
  // within itself
  function keepInView(instant) {
    var line = page.ls[page.sel.line]
    if (!line) { lines.contentY = 0; return }
    var r = Looks.cellRect(line, page.sel.col, page.geo)
    var inner = line.layout === "grid" || line.layout === "list" || line.layout === "table"
    var y0 = line.y + (inner ? r.y : 0)
    var y1 = inner ? line.y + r.y + r.h + page.u * 1.2 : line.y + line.height
    if (line.layout === "grid" && page.sel.col < line.cols) y0 = line.y
    if ((line.layout === "list" || line.layout === "table") && page.sel.col === 0) y0 = line.y
    var maxY = Math.max(0, page.model.height - lines.height)
    var to = lines.contentY
    if (y0 < to) to = Math.max(0, y0 - page.u * 0.5)
    else if (y1 > to + lines.height) to = Math.min(maxY, y1 - lines.height + page.u * 0.5)
    to = Math.max(0, Math.min(maxY, to))
    if (instant) { scroll.enabled = false; lines.contentY = to; scroll.enabled = true }
    else lines.contentY = to
  }
  // work put off to after the frame, dropped once the screen has gone (it's
  // made and destroyed as the guide goes to it and away)
  readonly property var life: ({ on: true })
  function soon(f) { var life = page.life; Qt.callLater(function() { if (life.on) f() }) }
  onSelChanged: page.soon(function() { page.keepInView(false) })
  onCurChanged: {
    page.soon(function() {
      if (!page.cur || !page.cur.sel || (page.sel.line === 0 && page.sel.col === 0)) { scroll.enabled = false; lines.contentY = 0; scroll.enabled = true }
      page.keepInView(true)
    })
    page.askPictures()
  }
  // the model made again (a resize, a row learning its shape): the same place
  onLsChanged: page.soon(function() { page.keepInView(true) })

  // a details page asks for the pictures it draws, first of all (the
  // focus): Classic its picture and backdrop, Cinematic its backdrop and
  // title logo; another view (or style) lets go of them
  property var asked: []
  function askPictures() {
    page.asked.forEach(function(img) { view.unwant(img, "focus") })
    var v = page.cur && page.cur.kind === "detail" ? page.cur.value : null
    var now = !v ? [] : page.cinematic ? [v.backdrop, v.logo] : [v.image, v.backdrop]
    now = now.filter(function(x) { return !!x })
    now.forEach(function(img) { view.want(img, "focus") })
    page.asked = now
  }
  onCinematicChanged: page.askPictures()
  Component.onCompleted: askPictures()
  Component.onDestruction: {
    page.life.on = false
    page.asked.forEach(function(img) { view.unwant(img, "focus") })
  }

  // ---- behind it all: the background, as the model says ----
  AppBackdrop {
    id: backdrop
    objectName: "appBackdrop"
    // the whole screen, the rail's strip too (the rail is drawn over it), so a
    // picture behind sits as the guide's own does
    x: -(guide.railSpace || 0)
    width: parent.width + (guide.railSpace || 0)
    height: parent.height
    guide: page.guide
    view: page.view
    host: page
  }

  // ---- who it is: the guide's own, over everything the app or a theme draws ----
  AppStrip {
    id: strip
    z: 50
    width: parent.width
    guide: page.guide
    app: page.app
  }

  // ---- where you are in it: the screen's title (the app's own words) ----
  Label {
    id: heading
    objectName: "screenTitle"
    x: page.u * 3
    y: strip.height + page.u * 0.8
    width: Math.min(implicitWidth, page.width - page.u * 6)
    height: page.u * 2.2
    verticalAlignment: Text.AlignVCenter
    text: !page.cur || page.detail || page.cur.kind === "page" ? "" : (page.cur.value.title || "")
    s: guide.look.appCardSub
    unit: page.u
    sizeFactor: 1.5
    elide: Text.ElideRight
  }

  // ---- what's selected, at the top, when the look (or you) shows it ----
  AppTop {
    id: top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: heading.bottom
    anchors.topMargin: page.u * 0.6
    height: page.screen.topShown ? Math.round(page.u * 11.5) : 0
    guide: page.guide
    view: page.view
    host: page
    visible: page.screen.topShown && !!thing
  }

  // ---- the body ----
  Item {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: page.screen.topShown ? top.bottom : heading.bottom
    anchors.topMargin: page.u * 0.8
    anchors.bottom: hintsRow.top
    anchors.bottomMargin: page.u * 0.8
    clip: true

    // a details page's top.
    // Classic: its picture, its space kept at a poster's shape while it
    // comes, then the picture's own shape once it's in (a poster stands
    // tall, a still lies wide), closed if it can't come (the text takes the
    // width); its title, line, chips, facts and text.
    // Cinematic: over its backdrop across the screen (AppBackdrop), its
    // title logo (at most 40% of the width and 8 units high; one that fails
    // gives way to the title) or its title, its line and chips, and up to
    // four lines of text.
    Item {
      id: detailHead
      objectName: "detailHead"
      readonly property bool shown: page.detail
      readonly property bool cine: page.cinematic
      readonly property var v: shown ? page.cur.value : null
      readonly property var img: v && !cine ? v.image : null
      readonly property real p: Math.round(page.u * guide.layout.libraryPosterWidth * 1.15)
      readonly property bool closed: !img || view.imageFailed(img) || poster.status === Image.Error
      readonly property bool ready: poster.status === Image.Ready && poster.implicitHeight > 0
      // its shape: from its size as soon as that's known (its header's, so
      // before it's drawn), else as it's drawn, else a poster's while it comes
      readonly property real known: view.imageRatio(img)
      readonly property bool shaped: known > 0 || ready
      readonly property real ratio: known > 0 ? known : ready ? poster.implicitWidth / poster.implicitHeight : 2 / 3
      readonly property real picW: closed ? 0 : shaped ? Math.round(Math.min(2 * p, 1.5 * p * ratio)) : p
      readonly property real picH: closed ? 0 : shaped ? Math.round(picW / ratio) : Math.round(1.5 * p)
      readonly property var chips: v && Array.isArray(v.chips) ? v.chips : []
      readonly property string meta: v && typeof v.meta === "string" ? v.meta : ""
      readonly property var logo: v && cine ? v.logo || null : null
      readonly property string logoUrl: view.imageUrl(logo)
      visible: shown
      x: page.u * 3
      width: parent.width - page.u * 6
      height: !shown ? 0 : cine ? cineCol.implicitHeight + page.u * 1.2 : Math.max(picH, detailText.implicitHeight) + page.u * 1.2

      // ---- Classic ----
      Item {
        id: posterBox
        objectName: "detailPicture"
        visible: !detailHead.cine && width > 0
        width: detailHead.cine ? 0 : detailHead.picW
        height: detailHead.picH
        Image {
          id: poster
          anchors.fill: parent
          source: detailHead.shown && !detailHead.cine ? view.imageUrl(detailHead.img) : ""
          sourceSize: Qt.size(Math.min(960, Math.ceil(2 * detailHead.p * page.dpr)), Math.min(960, Math.ceil(1.5 * detailHead.p * page.dpr)))
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          // a file that came but can't be drawn: fetched again, once
          onStatusChanged: {
            if (status === Image.Error && source != "") view.brokenPicture(detailHead.img, "focus")
            else if (status === Image.Ready) view.pictureDrawn(detailHead.img)
          }
        }
      }
      Column {
        id: detailText
        visible: !detailHead.cine
        x: posterBox.visible ? posterBox.width + page.u * 2 : 0
        width: detailHead.width - x
        spacing: page.u * 0.5
        Label {
          objectName: "detailTitle"
          width: parent.width
          text: detailHead.v ? detailHead.v.title : ""
          s: guide.look.appDetailTitle
          unit: page.u
          sizeFactor: 0.6
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Label {
          width: parent.width
          visible: text !== ""
          text: detailHead.v ? detailHead.v.subtitle || "" : ""
          s: guide.look.appDetailMeta
          unit: page.u
          wrapMode: Text.Wrap
        }
        Label {
          objectName: "detailMeta"
          width: parent.width
          visible: text !== ""
          text: detailHead.meta
          s: guide.look.appDetailMeta
          unit: page.u
          elide: Text.ElideRight
          maximumLineCount: 1
        }
        Flow {
          width: parent.width
          visible: detailHead.chips.length > 0
          spacing: page.u * 0.5
          Repeater {
            model: detailHead.cine ? [] : detailHead.chips
            delegate: chip
          }
        }
        Column {
          spacing: page.u * 0.25
          visible: !!detailHead.v && detailHead.v.facts.length > 0
          Repeater {
            model: detailHead.v ? detailHead.v.facts : []
            delegate: Row {
              required property var modelData
              spacing: page.u * 1.2
              Label {
                width: detailText.width * 0.36
                text: parent.modelData.label
                s: guide.look.appFactLabel
                unit: page.u
                sizeFactor: 1.15
                elide: Text.ElideRight
              }
              Label {
                width: detailText.width * 0.6
                text: parent.modelData.value
                s: guide.look.appFactValue
                unit: page.u
                sizeFactor: 1.15
                elide: Text.ElideRight
              }
            }
          }
        }
        AppChart {
          objectName: "detailChart"
          guide: page.guide
          width: Math.min(parent.width, page.u * 34)
          height: visible ? page.u * 5 : 0
          data: !detailHead.cine && detailHead.v && detailHead.v.chart ? detailHead.v.chart : null
        }
        Label {
          objectName: "detailText"
          width: parent.width
          visible: text !== ""
          topPadding: page.u * 0.4
          text: detailHead.v ? detailHead.v.text : ""
          s: guide.look.appDetailText
          unit: page.u
          sizeFactor: 1.1
          wrapMode: Text.Wrap
          maximumLineCount: 9
          elide: Text.ElideRight
        }
      }

      // ---- Cinematic ----
      Column {
        id: cineCol
        objectName: "cinematicHead"
        visible: detailHead.cine
        width: Math.min(detailHead.width, Math.max(page.u * 40, detailHead.width * 0.6))
        spacing: page.u * 0.6
        Image {
          id: titleLogo
          objectName: "detailLogo"
          width: Math.min(page.width * 0.4, cineCol.width)
          height: page.u * 8
          visible: detailHead.logoUrl !== "" && status === Image.Ready
          source: detailHead.logoUrl
          sourceSize: Qt.size(Math.min(960, Math.ceil(width * page.dpr)), Math.min(960, Math.ceil(height * page.dpr)))
          fillMode: Image.PreserveAspectFit
          horizontalAlignment: Image.AlignLeft
          asynchronous: true
          onStatusChanged: {
            if (status === Image.Ready) view.pictureDrawn(detailHead.logo)
            else if (status === Image.Error && source != "") view.brokenPicture(detailHead.logo, "focus")
          }
        }
        Label {
          objectName: "cinematicTitle"
          width: parent.width
          visible: !titleLogo.visible
          text: detailHead.v ? detailHead.v.title : ""
          s: guide.look.appDetailTitle
          unit: page.u
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
        Flow {
          width: parent.width
          spacing: page.u * 0.7
          visible: detailHead.meta !== "" || detailHead.chips.length > 0 || (!!detailHead.v && !!detailHead.v.subtitle)
          Label {
            visible: text !== ""
            text: detailHead.meta || (detailHead.v ? detailHead.v.subtitle || "" : "")
            s: guide.look.appDetailMeta
            unit: page.u
            height: Math.max(implicitHeight, page.u * 2)
            verticalAlignment: Text.AlignVCenter
          }
          Repeater {
            model: detailHead.cine ? detailHead.chips : []
            delegate: chip
          }
        }
        AppChart {
          guide: page.guide
          width: Math.min(parent.width, page.u * 34)
          height: visible ? page.u * 5 : 0
          data: detailHead.cine && detailHead.v && detailHead.v.chart ? detailHead.v.chart : null
        }
        Label {
          width: parent.width
          visible: text !== ""
          text: detailHead.v ? detailHead.v.text : ""
          s: guide.look.appDetailText
          unit: page.u
          sizeFactor: 1.1
          wrapMode: Text.Wrap
          maximumLineCount: 4
          elide: Text.ElideRight
        }
      }
    }

    // a chip: a few words about it (Drama, 4K), plain text
    Component {
      id: chip
      Box {
        id: chipBox
        required property var modelData
        objectName: "detailChip"
        height: chipLabel.implicitHeight + chipBox.padding
        width: chipLabel.implicitWidth + chipBox.padding * 2
        s: guide.look.appChip
        unit: page.u
        Label {
          id: chipLabel
          anchors.centerIn: parent
          text: String(chipBox.modelData)
          s: guide.look.appChip
          unit: page.u
        }
      }
    }

    // an article page (api 4): drawn whole, the arrows scrolling it
    AppPage {
      objectName: "appPage"
      anchors.fill: parent
      visible: !!page.cur && page.cur.kind === "page"
      guide: page.guide
      view: page.view
      value: visible ? page.cur.value : null
    }

    // the lines: a screen's rows, or a details screen's buttons and rows,
    // each as the model lays it out
    ListView {
      id: lines
      objectName: "appLines"
      visible: !page.cur || page.cur.kind !== "page"
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: detailHead.bottom
      anchors.bottom: parent.bottom
      model: page.ls
      boundsBehavior: Flickable.StopAtBounds
      Behavior on contentY { id: scroll; enabled: !guide.touchMode; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      interactive: guide.touchMode          // a finger scrolls it (the keys move the cursor)
      clip: true
      // the lines just off the screen are made ahead, between frames, so a
      // line scrolling in doesn't make all its cards in one frame
      cacheBuffer: Math.max(0, Math.round(height))
      onWidthChanged: view.screenWidth = width
      // the room it has changed (the top of the screen came or went, a
      // details page's top took its size): the selection stays in view
      onHeightChanged: page.soon(function() { page.keepInView(true) })
      Component.onCompleted: view.screenWidth = width

      delegate: Item {
        id: lineItem
        required property var modelData
        required property int index
        readonly property var line: modelData
        readonly property bool currentLine: index === page.sel.line
        readonly property int col: currentLine ? page.sel.col : -1
        // inside the list's viewport (a line made ahead, off it, isn't): by
        // its place in the model, never where it is for a moment as it's made
        readonly property bool lineOnScreen: line.y + line.height > lines.contentY && line.y < lines.contentY + lines.height
        // a featured row shows the item the cursor is on, or the one it was on last
        readonly property int heroCol: {
          if (currentLine) return page.sel.col
          var cols = view.sel && view.sel.cols ? view.sel.cols : null
          var k = "r:" + line.id
          return cols && Object.prototype.hasOwnProperty.call(cols, k) ? cols[k] : 0
        }
        width: lines.width
        height: line.height
        // a row still working out its shape starts its 2 s once it's on the
        // screen (one made ahead, off it, starts its clock when it scrolls
        // in; if its first three pictures all settle before that, they decide it)
        function shown() { if (lineOnScreen && line.kind === "row" && line.from === "auto") view.rowShown(line.id, line.items.length) }
        onLineOnScreenChanged: shown()
        Component.onCompleted: shown()

        // its title (a row's)
        Label {
          x: page.geo.margin
          height: page.titleH
          visible: lineItem.line.kind === "row"
          verticalAlignment: Text.AlignVCenter
          text: lineItem.line.title || ""
          s: guide.look.appRowTitle
          unit: page.u
        }

        // a featured row: one big item at a time
        Loader {
          active: lineItem.line.layout === "hero"
          x: page.geo.margin
          y: page.titleH
          width: lineItem.line.cardW || 0
          height: lineItem.line.cardH || 0
          sourceComponent: AppHero {
            guide: page.guide
            view: page.view
            host: page
            line: lineItem.line
            col: lineItem.heroCol
            current: lineItem.currentLine
            onScreen: lineItem.lineOnScreen
            ringColor: page.ringColor
            ringHalo: page.ringHalo
          }
        }

        // buttons (a details screen's actions)
        Row {
          visible: lineItem.line.layout === "actions"
          x: page.u * 3
          y: page.u * 0.4
          spacing: page.u * 1
          Repeater {
            model: lineItem.line.layout === "actions" ? lineItem.line.items : []
            delegate: Box {
              id: button
              required property var modelData
              required property int index
              readonly property bool current: lineItem.col === index
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.tap(lineItem.index, button.index) }
              width: actionLabel.implicitWidth + page.u * 3
              height: page.u * 3.2
              s: current ? guide.look["appButton:focused"] : guide.look.appButton
              unit: page.u
              scale: current ? 1 + Looks.growOf(s) : 1                  // only the selected one grows (at most 15%)
              z: current ? 2 : 0                                        // over its neighbours, ring and all
              Behavior on scale { NumberAnimation { duration: 120 } }
              Row {
                anchors.centerIn: parent
                spacing: page.u * 0.5
                Icon {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: button.modelData.kind === "play"
                  name: "play"
                  size: Math.round(page.u * 1.3)
                  stroke: 2
                  color: actionLabel.color
                }
                Label {
                  id: actionLabel
                  anchors.verticalCenter: parent.verticalCenter
                  text: button.modelData.label
                  s: button.current ? guide.look["appButton:focused"] : guide.look.appButton
                  unit: page.u
                }
              }
              // the guide's focus ring (with its halo where its color doesn't read)
              Rectangle {
                visible: button.current && page.ringHalo !== ""
                anchors.fill: parent
                anchors.margins: -page.ringW * 2
                color: "transparent"
                border.width: page.ringW
                border.color: page.ringHalo || "transparent"
                radius: button.rounded ? button.corners[0] + page.ringW * 2 : 0
                z: 10
              }
              Rectangle {
                objectName: "focusRing"
                visible: button.current
                anchors.fill: parent
                anchors.margins: -page.ringW
                color: "transparent"
                border.width: page.ringW
                border.color: page.ringColor
                radius: button.rounded ? button.corners[0] + page.ringW : 0
                z: 10
              }
            }
          }
        }

        // a list: one item a line, its picture in the row's shape
        Column {
          visible: lineItem.line.layout === "list"
          x: page.geo.margin
          y: page.titleH
          width: lines.width - 2 * page.geo.margin
          spacing: lineItem.line.rowGap || 0
          Repeater {
            model: lineItem.line.layout === "list" ? lineItem.line.items : []
            delegate: Box {
              id: listRow
              required property var modelData
              required property int index
              readonly property bool current: lineItem.col === index
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.tap(lineItem.index, listRow.index) }
              // its picture for the row's shape, wanted first when it's
              // selected, then while its line is on the screen
              readonly property var img: Looks.cardImage(modelData, lineItem.line)
              readonly property string prio: current ? "focus" : lineItem.lineOnScreen ? "visible" : "rest"
              readonly property string url: view.imageUrl(img)
              width: parent.width
              height: lineItem.line.rowH
              s: current ? guide.look["menuRow:focused"] : guide.look.menuRow
              unit: page.u
              z: current ? 2 : 0
              property var wantedImg: null
              property string wantedPrio: ""
              function rewant() {
                if (listRow.img === listRow.wantedImg && listRow.prio === listRow.wantedPrio) return
                if (listRow.wantedImg) view.unwant(listRow.wantedImg, listRow.wantedPrio)
                listRow.wantedImg = listRow.img
                listRow.wantedPrio = listRow.prio
                if (listRow.img) view.want(listRow.img, listRow.prio)
              }
              onImgChanged: rewant()
              onPrioChanged: rewant()
              property bool reported: false
              property string owner: ""
              property int ownerEpoch: -1
              function own() { if (listRow.ownerEpoch < 0) { listRow.owner = view.shapeKey; listRow.ownerEpoch = view.epoch } }
              // how its picture came out, for a row still working out its shape
              function report(ratio) {
                if (listRow.reported || lineItem.line.from !== "auto") return
                listRow.reported = true
                listRow.own()
                view.pictureSettled(lineItem.line.id, listRow.index, ratio, lineItem.line.items.length, listRow.owner, listRow.ownerEpoch)
              }
              Component.onCompleted: {
                listRow.own()
                listRow.rewant()
                if (!listRow.img || view.imageFailed(listRow.img)) report(0)
                else if (view.imageRatio(listRow.img) > 0 && view.imageUrl(listRow.img) !== "") report(view.imageRatio(listRow.img))
              }
              Component.onDestruction: if (listRow.wantedImg) view.unwant(listRow.wantedImg, listRow.wantedPrio)
              // a picture the helper couldn't get, after it was made; or one
              // whose size came with it (known before it's drawn)
              Connections {
                target: view
                function onImagePathsChanged() {
                  if (!listRow.img) return
                  if (view.imageFailed(listRow.img)) listRow.report(0)
                  else if (view.imageRatio(listRow.img) > 0 && view.imageUrl(listRow.img) !== "") listRow.report(view.imageRatio(listRow.img))
                }
              }
              Box {
                id: listPic
                x: page.u * 0.6
                anchors.verticalCenter: parent.verticalCenter
                width: listRow.url !== "" && imageStatus !== Image.Error ? lineItem.line.picW : 0
                height: lineItem.line.picH
                unit: page.u
                image: listRow.url !== "" && lineItem.line.picW > 0
                       ? { url: listRow.url, fit: lineItem.line.fit, opacity: 1,
                           decodeW: Math.min(960, Math.ceil(lineItem.line.picW * page.dpr)), decodeH: Math.min(960, Math.ceil(lineItem.line.picH * page.dpr)) }
                       : null
                onImageStatusChanged: {
                  if (imageStatus === Image.Ready) { listRow.report(imageRatio); view.pictureDrawn(listRow.img) }
                  else if (imageStatus === Image.Error) { listRow.report(0); view.brokenPicture(listRow.img, listRow.prio) }
                }
              }
              Label {
                id: listTitle
                anchors.left: listPic.right
                anchors.leftMargin: listPic.width > 0 ? page.u * 1 : 0
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.5
                text: listRow.modelData.title
                s: listRow.current ? guide.look["menuRow:focused"] : guide.look.menuRow
                unit: page.u
                elide: Text.ElideRight
              }
              // its chart (api 4), small, before its badge
              AppChart {
                id: listChart
                guide: page.guide
                anchors.right: listBadge.left
                anchors.rightMargin: visible ? page.u * 1 : 0
                anchors.verticalCenter: parent.verticalCenter
                width: visible ? page.u * 9 : 0
                height: lineItem.line.rowH * 0.6
                data: listRow.modelData.chart || null
                labels: false
              }
              Label {
                anchors.left: listTitle.right
                anchors.right: listChart.left
                anchors.margins: page.u * 1
                anchors.verticalCenter: parent.verticalCenter
                text: listRow.modelData.meta || listRow.modelData.subtitle || ""
                s: listRow.current ? guide.look["menuValue:focused"] : guide.look.menuValue
                unit: page.u
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
              }
              Label {
                id: listBadge
                anchors.right: parent.right
                anchors.rightMargin: page.u * 1
                anchors.verticalCenter: parent.verticalCenter
                text: listRow.modelData.badge || (listRow.modelData.watched === true ? "✓" : "")
                s: Looks.floored(guide.look.appBadge, Looks.CARD_TEXT, page.u, 1)
                unit: page.u
              }
              // the guide's focus ring (with its halo where its color doesn't read)
              Rectangle {
                visible: listRow.current && page.ringHalo !== ""
                anchors.fill: parent
                anchors.margins: -page.ringW * 2
                color: "transparent"
                border.width: page.ringW
                border.color: page.ringHalo || "transparent"
                radius: listRow.rounded ? listRow.corners[0] + page.ringW * 2 : 0
                z: 10
              }
              Rectangle {
                objectName: "focusRing"
                visible: listRow.current
                anchors.fill: parent
                anchors.margins: -page.ringW
                color: "transparent"
                border.width: page.ringW
                border.color: page.ringColor
                radius: listRow.rounded ? listRow.corners[0] + page.ringW : 0
                z: 10
              }
            }
          }
        }

        // a table (api 4): its columns' names, then a line each item, its
        // cells in their columns (each its share of the width; "end" ones
        // to the right), its chart at the end if it has one
        Column {
          id: table
          visible: lineItem.line.layout === "table"
          x: page.geo.margin
          y: page.titleH
          width: lines.width - 2 * page.geo.margin
          spacing: lineItem.line.rowGap || 0
          readonly property var cols: lineItem.line.columns || []
          readonly property bool charts: (lineItem.line.items || []).some(function(it) { return !!it.chart })
          readonly property real chartW: charts ? page.u * 9 : 0
          readonly property real colW: cols.length ? (width - page.u * 2 - chartW) / cols.length : 0
          Item {
            width: parent.width
            height: lineItem.line.headH || 0
            Repeater {
              model: lineItem.line.layout === "table" ? table.cols : []
              delegate: Label {
                required property var modelData
                required property int index
                x: page.u + index * table.colW
                width: table.colW - page.u * 0.6
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                horizontalAlignment: modelData.align === "end" ? Text.AlignRight : Text.AlignLeft
                s: guide.look.appTableHead
                unit: page.u
                elide: Text.ElideRight
              }
            }
          }
          Repeater {
            model: lineItem.line.layout === "table" ? lineItem.line.items : []
            delegate: Box {
              id: tableRow
              objectName: "tableRow"
              required property var modelData
              required property int index
              readonly property bool current: lineItem.col === index
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.tap(lineItem.index, tableRow.index) }
              width: table.width
              height: lineItem.line.rowH
              s: current ? guide.look["appTable:focused"] : guide.look.appTable
              unit: page.u
              z: current ? 2 : 0
              Repeater {
                model: table.cols
                delegate: Label {
                  required property var modelData
                  required property int index
                  x: page.u + index * table.colW
                  width: table.colW - page.u * 0.6
                  anchors.verticalCenter: parent.verticalCenter
                  text: (tableRow.modelData.cells || [])[index] || ""
                  horizontalAlignment: modelData.align === "end" ? Text.AlignRight : Text.AlignLeft
                  s: tableRow.current ? guide.look["appTable:focused"] : guide.look.appTable
                  unit: page.u
                  elide: Text.ElideRight
                }
              }
              AppChart {
                guide: page.guide
                anchors.right: parent.right
                anchors.rightMargin: page.u
                anchors.verticalCenter: parent.verticalCenter
                width: table.chartW - page.u
                height: lineItem.line.rowH * 0.6
                data: tableRow.modelData.chart || null
                labels: false
              }
              Rectangle {
                visible: tableRow.current && page.ringHalo !== ""
                anchors.fill: parent
                anchors.margins: -page.ringW * 2
                color: "transparent"
                border.width: page.ringW
                border.color: page.ringHalo || "transparent"
                radius: tableRow.rounded ? tableRow.corners[0] + page.ringW * 2 : 0
                z: 10
              }
              Rectangle {
                objectName: "focusRing"
                visible: tableRow.current
                anchors.fill: parent
                anchors.margins: -page.ringW
                color: "transparent"
                border.width: page.ringW
                border.color: page.ringColor
                radius: tableRow.rounded ? tableRow.corners[0] + page.ringW : 0
                z: 10
              }
            }
          }
        }

        // a ticker (api 4): one line moving across; it stops while it's
        // selected, while the screen saver is up and while a video plays
        AppTicker {
          id: tickerLine
          objectName: "ticker"
          visible: lineItem.line.layout === "ticker"
          x: page.geo.margin
          y: page.titleH
          width: lines.width - 2 * page.geo.margin
          height: lineItem.line.rowH || 0
          guide: page.guide
          line: visible ? lineItem.line : null
          moving: !lineItem.currentLine && !guide.appPlaying && !(guide.screenSaver && guide.screenSaver.showing) && lineItem.lineOnScreen
          Rectangle {
            objectName: "focusRing"
            visible: lineItem.currentLine
            anchors.fill: parent
            anchors.margins: -page.ringW
            color: "transparent"
            border.width: page.ringW
            border.color: page.ringColor
            z: 10
          }
        }

        // a row of cards
        ListView {
          id: rowCards
          objectName: "rowCards"
          // room above and below its cards for the selected one to grow (at
          // most 15%) with the guide's ring and halo round it, inside what
          // the row clips (as it scrolls across): nothing hides the ring
          readonly property real pad: Math.ceil((lineItem.line.cardH || 0) * Looks.MAX_GROW / 2 + page.ringW * 3)
          visible: lineItem.line.layout === "row"
          y: page.titleH - pad
          width: parent.width
          height: lineItem.line.layout === "row" ? lineItem.line.cardH + lineItem.line.captionH + page.u + 2 * pad : 0
          orientation: ListView.Horizontal
          spacing: lineItem.line.gap || 0
          leftMargin: page.geo.margin
          rightMargin: page.geo.margin
          model: lineItem.line.layout === "row" ? lineItem.line.items : []
          // a few cards past each end made ahead, between frames
          cacheBuffer: (lineItem.line.cellW || 0) * 3
          currentIndex: Math.max(0, lineItem.col)
          highlightRangeMode: ListView.ApplyRange
          preferredHighlightBegin: page.geo.margin
          preferredHighlightEnd: width - page.geo.margin - (lineItem.line.cardW || 0)
          highlightMoveDuration: 200
          boundsBehavior: Flickable.StopAtBounds
          interactive: guide.touchMode          // a finger slides the row
          clip: true
          delegate: AppCard {
            id: rowCard
            // drawn below the room kept for growing (the list places it at
            // its top, so it's moved by a transform the list doesn't touch)
            transform: Translate { y: rowCards.pad }
            guide: page.guide
            view: page.view
            line: lineItem.line
            current: lineItem.col === index
            onScreen: lineItem.lineOnScreen && x + width > rowCards.contentX && x < rowCards.contentX + rowCards.width
            ringColor: page.ringColor
            ringHalo: page.ringHalo
            selectedTitle: page.selectedTitle
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.tap(lineItem.index, rowCard.index) }
          }
        }

        // a grid of cards, virtualized: a GridView over only the part of the
        // grid inside the list's viewport, moving and scrolling with it, so
        // only the cards on the screen (and a line more) exist
        Item {
          id: gridArea
          visible: lineItem.line.layout === "grid"
          x: page.geo.margin
          y: page.titleH + Math.round(page.u * 0.5)
          width: lineItem.line.layout === "grid" ? lineItem.line.cols * lineItem.line.cellW : 0
          height: lineItem.line.layout === "grid" ? Math.ceil(lineItem.line.items.length / lineItem.line.cols) * lineItem.line.cellH : 0
          // how far the viewport's top is into the grid, and how much of it shows
          readonly property real into: Math.max(0, Math.min(height, lines.contentY - (lineItem.y + y)))
          readonly property real shows: Math.max(0, Math.min(height, lines.contentY + lines.height - (lineItem.y + y)) - into)
          onIntoChanged: grid.contentY = gridArea.into
          GridView {
            id: grid
            objectName: "appGrid"
            y: gridArea.into
            width: parent.width
            height: Math.max(1, gridArea.shows)
            interactive: false
            cellWidth: lineItem.line.cellW || 1
            cellHeight: lineItem.line.cellH || 1
            cacheBuffer: lineItem.line.cellH || 0
            model: lineItem.line.layout === "grid" ? lineItem.line.items : []
            onCountChanged: contentY = gridArea.into
            Component.onCompleted: contentY = gridArea.into
            delegate: AppCard {
              id: gridCard
              guide: page.guide
              view: page.view
              line: lineItem.line
              current: lineItem.col === index
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.tap(lineItem.index, gridCard.index) }
              onScreen: y + height > grid.contentY && y < grid.contentY + grid.height
              ringColor: page.ringColor
              ringHalo: page.ringHalo
              selectedTitle: page.selectedTitle
            }
          }
        }
      }
    }

    // nothing on it (or every row of it hidden: the app's own message isn't yours)
    Label {
      objectName: "emptyNote"
      anchors.centerIn: parent
      visible: !!page.cur && page.cur.kind === "screen" && page.ls.length === 0 && !view.loading && !view.failed
      width: Math.min(parent.width - page.u * 6, page.u * 60)
      horizontalAlignment: Text.AlignHCenter
      text: page.model.allHidden ? "Every row is hidden. Customize (C, or Options on the phone) brings them back."
          : page.cur && page.cur.value.empty ? page.cur.value.empty : "Nothing here yet."
      s: guide.look.boxText
      unit: page.u
      sizeFactor: 1.4
      color: guide.dimInk
      wrapMode: Text.Wrap
    }

    // it couldn't come: why, and Enter tries again
    Column {
      anchors.centerIn: parent
      visible: view.failed !== ""
      spacing: page.u * 1
      width: Math.min(parent.width - page.u * 6, page.u * 60)
      Label {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: view.failed
        s: guide.look.boxText
        unit: page.u
        sizeFactor: 1.4
        color: guide.colors.alert
        wrapMode: Text.Wrap
      }
      Label {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "Enter tries again. Esc goes back to Apps."
        s: guide.look.menuNote
        unit: page.u
        sizeFactor: 1.15
      }
    }
  }

  // loading: over what's there, after a moment (no flicker for quick ones)
  Rectangle {
    id: loadingBox
    z: 60
    anchors.centerIn: body
    visible: view.loading && loadingDelay.passed && !view.failed
    width: loadingText.implicitWidth + page.u * 4
    height: page.u * 3.6
    radius: page.u * 0.6
    color: guide.colors.boxBg
    border.color: guide.colors.boxBorder
    border.width: 2
    Label {
      id: loadingText
      anchors.centerIn: parent
      text: page.cur ? "Loading…  (Esc stops it)" : "Starting " + (page.app ? page.app.name : "the app") + "…"
      s: guide.look.boxText
      unit: page.u
      sizeFactor: 1.3
      color: guide.ink
    }
    Timer {
      id: loadingDelay
      property bool passed: false
      interval: 350
      running: view.loading
      onRunningChanged: if (!running) passed = false
      onTriggered: passed = true
    }
  }

  // the app's message, or what went wrong
  Rectangle {
    z: 60
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: hintsRow.top
    anchors.bottomMargin: page.u * 1.6
    visible: view.message !== ""
    width: Math.min(page.width - page.u * 8, messageText.implicitWidth + page.u * 4)
    height: messageText.implicitHeight + page.u * 1.6
    radius: page.u * 0.6
    color: guide.colors.boxBg
    border.color: view.messageBad ? guide.colors.alert : guide.colors.boxBorder
    border.width: 2
    Label {
      id: messageText
      anchors.centerIn: parent
      width: Math.min(implicitWidth, page.width - page.u * 12)
      text: view.message
      s: guide.look.boxText
      unit: page.u
      sizeFactor: 1.2
      color: view.messageBad ? guide.colors.alert : guide.ink
      wrapMode: Text.Wrap
      horizontalAlignment: Text.AlignHCenter
    }
  }

  // ---- its settings (the guide's own boxes go over everything, the strip too) ----
  Rectangle {
    z: 60
    anchors.fill: parent
    visible: view.settingsOpen
    color: guide.colors.scrim
    MouseArea { anchors.fill: parent; onClicked: view.back() }
  }
  Rectangle {
    id: settingsPanel
    z: 60
    visible: view.settingsOpen
    anchors.centerIn: parent
    width: Math.min(page.width - page.u * 8, page.u * 64)
    height: settingsCol.implicitHeight + page.u * 4
    radius: page.u * 0.8
    color: guide.colors.boxBg
    border.color: guide.colors.boxBorder
    border.width: 2
    Column {
      id: settingsCol
      x: page.u * 2
      y: page.u * 2
      width: parent.width - page.u * 4
      spacing: page.u * 0.5
      Label {
        text: (page.app ? page.app.name : "") + " settings"
        s: guide.look.menuHeader
        unit: page.u
        sizeFactor: 1.4
      }
      Label {
        width: parent.width
        visible: view.settingsRows.length === 0
        text: "It has no settings."
        s: guide.look.menuNote
        unit: page.u
      }
      Repeater {
        model: view.settingsOpen ? view.settingsRows : []
        delegate: MenuRow {
          required property var modelData
          required property int index
          guide: page.guide
          width: settingsCol.width
          height: implicitHeight
          size: 0.85
          focused: index === view.settingsCursor
          label: modelData.label
          kind: modelData.type === "switch" ? "switch" : modelData.type === "choice" ? "choice" : modelData.type === "clear" || modelData.type === "signIn" ? "action" : "value"
          on: modelData.type === "switch" && modelData.value === true
          danger: modelData.type === "clear"
          value: modelData.type === "clear" && view.armed === modelData.key ? "Enter again to clear"
                 : modelData.type === "switch" ? "" : String(modelData.value)
          // a click picks first; a finger acts at once (a clearing still asks twice)
          onActivated: {
            if (view.settingsCursor !== index) { view.settingsCursor = index; if (!guide.touchMode) return }
            view.settingsAct(0, guide.byUser)
          }
          // tablet mode: ‹ › as ← → (the keys' own steps)
          touchParts: true
          onStepped: function(dir) { view.settingsCursor = index; view.settingsAct(dir, guide.byUser) }
        }
      }
      Label {
        width: parent.width
        visible: text !== ""
        text: view.settingsNote
        s: guide.look.boxText
        unit: page.u
        color: guide.marquee
        wrapMode: Text.Wrap
      }
      Label {
        width: parent.width
        text: "A change starts the app again, from its first screen. Secrets you type here are kept for this app only, readable by nobody else."
        s: guide.look.menuNote
        unit: page.u
        wrapMode: Text.Wrap
      }
    }
  }

  // ---- signing in: the code, big, and a QR code for the page; or the
  // guide's own box for a username and password (keyboard only) ----
  Rectangle {
    z: 60
    anchors.fill: parent
    visible: view.signIn !== null
    color: guide.colors.scrim
    MouseArea { anchors.fill: parent }
  }
  Rectangle {
    id: signInBox
    z: 60
    visible: view.signIn !== null
    anchors.centerIn: parent
    width: Math.min(page.width - page.u * 8, page.u * 70)
    height: signInCol.implicitHeight + page.u * 4
    radius: page.u * 0.8
    color: guide.colors.boxBg
    border.color: guide.marquee
    border.width: 2
    property real secondsLeft: 0
    readonly property bool typing: !!view.signIn && view.signIn.how === "password" && view.signIn.stage === "typing"
    // what you typed lives only in these two fields, cleared the moment it's
    // sent, or the box goes
    onTypingChanged: {
      userField.text = ""
      passField.text = ""
      if (typing) userField.forceActiveFocus()
      else guide.focusKeys()   // signing in, or the box gone: the guide's keys again (Esc)
    }
    onVisibleChanged: if (!visible) { userField.text = ""; passField.text = "" }
    function send() {
      if (!userField.text) { userField.forceActiveFocus(); return }
      if (!passField.text) { passField.forceActiveFocus(); return }
      if (view.sendPassword(userField.text, passField.text, guide.byUser)) { userField.text = ""; passField.text = "" }
    }
    Timer {
      interval: 1000
      repeat: true
      running: signInBox.visible
      triggeredOnStart: true
      onTriggered: signInBox.secondsLeft = view.signIn && view.signIn.expires ? Math.max(0, Math.round((view.signIn.expires - Date.now()) / 1000)) : 0
    }
    Row {
      id: signInCol
      x: page.u * 2
      y: page.u * 2
      spacing: page.u * 2
      Column {
        width: signInBox.width - page.u * 4 - (qr.visible ? qr.width + page.u * 2 : 0)
        spacing: page.u * 0.8
        Label {
          text: "Sign in to " + (page.app ? page.app.name : "it")
          s: guide.look.menuHeader
          unit: page.u
          sizeFactor: 1.4
        }
        Label {
          width: parent.width
          visible: !!view.signIn && (view.signIn.stage === "checking" || signInBox.typing)
          text: !view.signIn ? "" : view.signIn.stage === "checking" ? (view.signIn.note || "Signing in…")
                : "Your username and password for " + (page.app && page.app.server ? page.app.server.replace(/^https?:\/\//, "") : "its server")
                  + ". They go to " + (page.app ? page.app.name : "the app") + " once, to sign in; Uber TV keeps only what the service gives back."
          s: guide.look.boxText
          unit: page.u
          sizeFactor: 1.15
          color: guide.ink
          wrapMode: Text.Wrap
        }
        Column {
          visible: signInBox.typing
          width: parent.width
          spacing: page.u * 0.3
          Label {
            text: "Username"
            s: guide.look.menuNote
            unit: page.u
          }
          Rectangle {
            width: parent.width
            height: page.u * 3
            radius: page.u * 0.4
            color: Qt.darker(guide.colors.boxBg, 1.3)
            border.color: userField.activeFocus ? guide.marquee : guide.colors.boxBorder
            border.width: userField.activeFocus ? 2 : 1
            TextInput {
              id: userField
              anchors.fill: parent
              anchors.margins: page.u * 0.6
              verticalAlignment: TextInput.AlignVCenter
              color: guide.ink
              font.family: guide.fontFamily
              font.pixelSize: Math.round(page.u * 1.3)
              maximumLength: 256
              clip: true
              KeyNavigation.tab: passField
              Keys.onPressed: function(event) { guide.keyFirst(event) }
              Keys.onDownPressed: { if (guide.keyFirst(event)) return; passField.forceActiveFocus() }
              Keys.onReturnPressed: { if (guide.keyFirst(event)) return; signInBox.send() }
              Keys.onEnterPressed: { if (guide.keyFirst(event)) return; signInBox.send() }
              Keys.onEscapePressed: { if (guide.keyFirst(event)) return; view.back() }
              function enterKey() { signInBox.send() }   // tablet mode's keyboard's Done
            }
          }
        }
        Column {
          visible: signInBox.typing
          width: parent.width
          spacing: page.u * 0.3
          Label {
            text: "Password"
            s: guide.look.menuNote
            unit: page.u
          }
          Rectangle {
            width: parent.width
            height: page.u * 3
            radius: page.u * 0.4
            color: Qt.darker(guide.colors.boxBg, 1.3)
            border.color: passField.activeFocus ? guide.marquee : guide.colors.boxBorder
            border.width: passField.activeFocus ? 2 : 1
            TextInput {
              id: passField
              anchors.fill: parent
              anchors.margins: page.u * 0.6
              verticalAlignment: TextInput.AlignVCenter
              color: guide.ink
              font.family: guide.fontFamily
              font.pixelSize: Math.round(page.u * 1.3)
              echoMode: TextInput.Password
              maximumLength: 1024
              clip: true
              KeyNavigation.backtab: userField
              Keys.onPressed: function(event) { guide.keyFirst(event) }
              Keys.onUpPressed: { if (guide.keyFirst(event)) return; userField.forceActiveFocus() }
              function enterKey() { signInBox.send() }   // tablet mode's keyboard's Done
              Keys.onReturnPressed: { if (guide.keyFirst(event)) return; signInBox.send() }
              Keys.onEnterPressed: { if (guide.keyFirst(event)) return; signInBox.send() }
              Keys.onEscapePressed: { if (guide.keyFirst(event)) return; view.back() }
            }
          }
        }
        // choosing its server: the server, then how to reach it (or switch to it?)
        Label {
          width: parent.width
          visible: text !== ""
          text: !view.signIn ? "" : view.signIn.stage === "servers" ? "Choose your server. Your account lists these:"
                : view.signIn.stage === "addresses" && view.signIn.server ? "How to reach " + view.signIn.server.label + ":"
                : view.signIn.stage === "address" && view.signIn.server ? "An address for " + view.signIn.server.label + ", like https://media.example.com or http://192.168.1.20:32400:"
                : view.signIn.stage === "switch" ? "Switch " + (page.app ? page.app.name : "it") + " to " + view.signIn.target + "? What it kept from "
                  + (page.app && page.app.server ? page.app.server : "the server it has") + " is cleared, and you sign in again."
                : ""
          s: guide.look.boxText
          unit: page.u
          sizeFactor: 1.15
          color: guide.ink
          wrapMode: Text.Wrap
        }
        Repeater {
          model: view.signInRows
          delegate: MenuRow {
            required property int index
            required property var modelData
            guide: page.guide
            width: parent.width
            height: implicitHeight
            size: 0.85
            focused: !!view.signIn && index === view.signIn.pick
            label: modelData.label
            value: modelData.value
            kind: modelData.type === "server" || modelData.type === "type" ? "opens" : "action"
            danger: modelData.type === "switch"
            onActivated: { if (view.signIn.pick !== index) view.signIn = guide.apps.withKey(view.signIn, "pick", index); else view.signInAct(guide.byUser) }
          }
        }
        Rectangle {
          visible: !!view.signIn && view.signIn.stage === "address"
          width: parent.width
          height: page.u * 3
          radius: page.u * 0.4
          color: Qt.darker(guide.colors.boxBg, 1.3)
          border.color: guide.marquee
          border.width: 2
          onVisibleChanged: { addressField.text = ""; if (visible) addressField.forceActiveFocus(); else if (view.signIn) guide.focusKeys() }
          TextInput {
            id: addressField
            anchors.fill: parent
            anchors.margins: page.u * 0.6
            verticalAlignment: TextInput.AlignVCenter
            color: guide.ink
            font.family: guide.fontFamily
            font.pixelSize: Math.round(page.u * 1.3)
            maximumLength: 500
            clip: true
            Keys.onPressed: function(event) { guide.keyFirst(event) }
            function enterKey() { view.typedAddress(text, guide.byUser) }   // tablet mode's keyboard's Done
            Keys.onReturnPressed: { if (guide.keyFirst(event)) return; view.typedAddress(text, guide.byUser) }
            Keys.onEnterPressed: { if (guide.keyFirst(event)) return; view.typedAddress(text, guide.byUser) }
            Keys.onEscapePressed: { if (guide.keyFirst(event)) return; view.signInBack() }
          }
        }
        Label {
          width: parent.width
          visible: !!view.signIn && view.signIn.note !== "" && view.signIn.stage !== "checking"
          text: view.signIn ? view.signIn.note : ""
          s: guide.look.boxText
          unit: page.u
          color: guide.colors.alert
          wrapMode: Text.Wrap
        }
        Label {
          visible: signInBox.typing
          text: "Enter signs in, Tab moves between them, Esc cancels."
          s: guide.look.menuNote
          unit: page.u
        }
        Label {
          width: parent.width
          visible: !!view.signIn && view.signIn.how !== "password" && view.signIn.stage === "" && view.signIn.code === ""
          text: "Asking " + (page.app && page.app.server ? page.app.server.replace(/^https?:\/\//, "") : "the server") + " for a code…"
          s: guide.look.boxText
          unit: page.u
          sizeFactor: 1.2
          color: guide.ink
          wrapMode: Text.Wrap
        }
        Label {
          visible: !!view.signIn && view.signIn.stage === "" && view.signIn.code !== ""
          text: view.signIn ? view.signIn.code.split("").join(" ") : ""
          s: guide.look.libraryTab
          unit: page.u
          sizeFactor: 4 / Math.max(0.2, guide.look.libraryTab.text.size)
          color: guide.marquee
          font.letterSpacing: page.u * 0.3
        }
        Label {
          width: parent.width
          visible: !!view.signIn && view.signIn.stage === "" && view.signIn.code !== ""
          text: view.signIn && view.signIn.url ? "Enter it at " + view.signIn.url + (qr.visible ? ", or scan the code with your phone." : ".")
                : "Enter it where your account's app asks for a Quick Connect code (on your phone, say)."
          s: guide.look.boxText
          unit: page.u
          sizeFactor: 1.15
          color: guide.ink
          wrapMode: Text.Wrap
        }
        Label {
          visible: !!view.signIn && view.signIn.stage === "" && view.signIn.code !== "" && signInBox.secondsLeft > 0
          text: "It expires in " + Math.floor(signInBox.secondsLeft / 60) + ":" + ("0" + signInBox.secondsLeft % 60).slice(-2) + ". Esc cancels."
          s: guide.look.menuNote
          unit: page.u
        }
      }
      Image {
        id: qr
        visible: !!view.signIn && view.signIn.how !== "password" && view.signIn.stage === "" && view.signIn.qr !== "" && status === Image.Ready
        width: page.u * 12
        height: width
        source: view.signIn && view.signIn.qr ? guide.fileUrl(view.signIn.qr) : ""
        sourceSize.width: 400
        fillMode: Image.PreserveAspectFit
        smooth: false
        cache: false            // the two QR files are reused
      }
    }
  }

  // ---- typing: a search, or a setting ----
  Rectangle {
    id: editBox
    z: 60
    visible: view.editing !== null
    anchors.horizontalCenter: parent.horizontalCenter
    y: page.height * 0.3
    width: Math.min(page.width - page.u * 8, page.u * 60)
    height: editCol.implicitHeight + page.u * 3
    radius: page.u * 0.8
    color: guide.colors.boxBg
    border.color: guide.marquee
    border.width: 2
    onVisibleChanged: if (visible) { field.text = view.editing ? view.editing.text : ""; field.forceActiveFocus() }
    Column {
      id: editCol
      x: page.u * 1.5
      y: page.u * 1.5
      width: parent.width - page.u * 3
      spacing: page.u * 0.6
      Label {
        text: view.editing ? view.editing.label : ""
        s: guide.look.menuHeader
        unit: page.u
        sizeFactor: 1.2
      }
      Rectangle {
        width: parent.width
        height: page.u * 3
        radius: page.u * 0.4
        color: Qt.darker(guide.colors.boxBg, 1.3)
        border.color: guide.colors.boxBorder
        TextInput {
          id: field
          anchors.fill: parent
          anchors.margins: page.u * 0.6
          verticalAlignment: TextInput.AlignVCenter
          color: guide.ink
          font.family: guide.fontFamily
          font.pixelSize: Math.round(page.u * 1.3)
          echoMode: view.editing && view.editing.type === "secret" ? TextInput.Password : TextInput.Normal
          maximumLength: view.editing && view.editing.type === "secret" ? 4096 : 500
          clip: true
          Keys.onPressed: function(event) { guide.keyFirst(event) }
          function enterKey() { view.editDone(text, guide.byUser) }   // tablet mode's keyboard's Done
          Keys.onReturnPressed: { if (guide.keyFirst(event)) return; view.editDone(text, guide.byUser) }
          Keys.onEnterPressed: { if (guide.keyFirst(event)) return; view.editDone(text, guide.byUser) }
          Keys.onEscapePressed: { if (guide.keyFirst(event)) return; view.back() }
        }
      }
      Label {
        width: parent.width
        text: !view.editing ? "" : view.editing.type === "server" ? "Its address, like http://192.168.1.20:8096 or https://media.example.com/jellyfin. Enter keeps it, Esc cancels."
              : view.editing.type === "secret" ? "It's kept for this app only (0600, in your config). Enter keeps it (empty clears it), Esc cancels."
              : "Enter " + (view.editing.type === "search" ? "searches" : "keeps it") + ", Esc cancels."
        s: guide.look.menuNote
        unit: page.u
        wrapMode: Text.Wrap
      }
    }
  }

  // ---- the keys ----
  // its keys; in tablet mode its buttons, always there (where a field has
  // the keys, the buttons run what the field does)
  KeyHints {
    id: hintsRow
    visible: guide.showKeyHints || guide.touchMode
    x: page.u * 3
    anchors.bottom: parent.bottom
    anchors.bottomMargin: page.u * 1.2
    size: guide.u * 1.5
    capStyle: guide.look.keycap
    labelStyle: guide.look.keyLabel
    touchGuide: page.guide
    touchWidth: page.width - page.u * 6
    model: view.signIn ? (signInBox.typing ? [{ keys: ["ENTER"], label: "Sign in", touch: { run: function() { signInBox.send() }, primary: true } }, { keys: ["TAB"], label: "Next field" },
                                              { keys: ["ESC"], label: "Cancel", touch: { run: function() { view.back() }, back: true } }]
                          : view.signIn.stage === "address" ? [{ keys: ["ENTER"], label: "Use it", touch: { run: function() { view.typedAddress(addressField.text, guide.byUser) }, primary: true } },
                                                               { keys: ["ESC"], label: "Back", touch: { run: function() { view.signInBack() }, back: true } }]
                          : view.signInRows.length ? [{ keys: ["↑", "↓"], label: "Choose" }, { keys: ["ENTER"], label: "OK", touch: { key: Qt.Key_Return, primary: true } },
                                                      { keys: ["ESC"], label: view.signIn.stage === "servers" ? "Cancel" : "Back", touch: { key: Qt.Key_Escape, back: true } }]
                          : [{ keys: ["ESC"], label: "Cancel", touch: { key: Qt.Key_Escape, back: true } }])
           : view.editing ? [{ keys: ["ENTER"], label: view.editing.type === "search" ? "Search" : "Keep", touch: { run: function() { view.editDone(field.text, guide.byUser) }, primary: true } },
                             { keys: ["ESC"], label: "Cancel", touch: { run: function() { view.back() }, back: true } }]
           : view.settingsOpen ? [{ keys: ["↑", "↓"], label: "Move" }, { keys: ["←", "→"], label: "Change" }, { keys: ["ENTER"], label: "Set" }, { keys: ["ESC"], label: "Done", touch: { key: Qt.Key_Escape, back: true } }]
           : view.failed ? [{ keys: ["ENTER"], label: "Try again", touch: { key: Qt.Key_Return, primary: true } }, { keys: [","], label: "Settings", touch: { key: Qt.Key_Comma, icon: "gear" } },
                            { keys: ["ESC"], label: "Apps", touch: { key: Qt.Key_Escape, back: true } }]
           : page.cur && page.cur.kind === "page" ? [{ keys: ["↑", "↓"], label: "Scroll" }, { keys: [","], label: "Settings", touch: { key: Qt.Key_Comma, icon: "gear" } },
                                                    { keys: ["ESC"], label: "Back", touch: { key: Qt.Key_Escape, back: true } }]
           : [{ keys: ["↑", "↓", "←", "→"], label: "Move" }, { keys: ["ENTER"], label: "Open" }, { keys: ["I"], label: "Details", touch: { key: Qt.Key_I, icon: "info" } },
              { keys: ["/"], label: "Search", touch: { key: Qt.Key_Slash, icon: "search" } }, { keys: ["C"], label: "Customize", touch: { key: Qt.Key_C, icon: "pencil" } },
              { keys: [","], label: "Settings", touch: { key: Qt.Key_Comma, icon: "gear" } },
              { keys: ["ESC"], label: view.stack.length > 1 || view.pending ? "Back" : "Apps", touch: { key: Qt.Key_Escape, back: true } }]
  }
}
