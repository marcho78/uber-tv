import QtQuick
import "../AppLooks.js" as Looks

// A featured (hero) row on an app's screen (§4.2): one big item at a time,
// across the screen: its backdrop (or its wide picture) under a shade that
// never goes below the floor, its title logo (at most 40% of the width and
// 8 units high) or its title, a line about it, and up to three lines of
// text; dots say which of its items it is. ← and → change items. With no
// backdrop and no logo, its title on the card's color. The guide's focus
// ring goes round it when it's selected, and its title reads against
// what's behind it. Plain text. A click or a tap on it is on the item it
// shows (tapped: the app screen picks it, and opens it at a finger's first
// tap or a click's second); in tablet mode the dots are spaced a finger
// apart, and a tap on one shows its item (chose).
Item {
  id: hero

  required property var guide
  required property var view
  required property var host           // the app screen it's on
  property var line: ({})
  property int col: 0                     // the item it shows
  property bool current: false            // the cursor is on it
  property bool onScreen: true
  property string ringColor: "#ffffff"
  property string ringHalo: ""
  signal tapped(int col, bool finger)
  signal chose(int col)

  readonly property real u: guide.u
  readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1
  readonly property real ringW: Math.max(2, Math.ceil(u * 0.15))
  readonly property var items: line.items || []
  readonly property var item: items.length ? items[Math.max(0, Math.min(items.length - 1, col))] : null
  readonly property var pic: Looks.backdropOf(item)
  readonly property var logo: Looks.logoOf(item)
  readonly property string prio: current ? "focus" : onScreen ? "visible" : "rest"
  readonly property string picUrl: view.imageUrl(pic)
  readonly property string logoUrl: view.imageUrl(logo)
  readonly property var style: current ? guide.look["appCard:current"] : guide.look.appCard
  readonly property color shadeColor: guide.look.appShade && guide.look.appShade.color ? guide.look.appShade.color : guide.colors.bgBottom
  // what's behind its words: the picture under the shade's left side, or the card's color
  readonly property var behind: frame.imageStatus === Image.Ready
                                ? Looks.behindColors({ fill: style.fill, base: host.pageColor, picture: true, dim: 0.75, dimColor: String(shadeColor) })
                                : Looks.behindColors({ fill: style.fill, base: host.pageColor })
  readonly property var titleStyle: Looks.floored(guide.look.appTopTitle, Looks.TOP_TITLE, u, 0.8)
  readonly property var titleColor: Looks.titleColor(String(titleStyle.text ? titleStyle.text.color : ""), String(guide.ink), host.pageColor, behind)

  objectName: "appHero"

  // what it wants of the view: its picture and its logo, at its priority
  property var wantedPic: null
  property var wantedLogo: null
  property string wantedPrio: ""
  function rewant() {
    if (hero.pic === hero.wantedPic && hero.logo === hero.wantedLogo && hero.prio === hero.wantedPrio) return
    if (hero.wantedPic) view.unwant(hero.wantedPic, hero.wantedPrio)
    if (hero.wantedLogo) view.unwant(hero.wantedLogo, hero.wantedPrio)
    hero.wantedPic = hero.pic
    hero.wantedLogo = hero.logo
    hero.wantedPrio = hero.prio
    if (hero.pic) view.want(hero.pic, hero.prio)
    if (hero.logo) view.want(hero.logo, hero.prio)
  }
  onPicChanged: rewant()
  onLogoChanged: rewant()
  onPrioChanged: rewant()
  Component.onCompleted: rewant()
  Component.onDestruction: {
    if (hero.wantedPic) view.unwant(hero.wantedPic, hero.wantedPrio)
    if (hero.wantedLogo) view.unwant(hero.wantedLogo, hero.wantedPrio)
  }

  Box {
    id: frame
    anchors.fill: parent
    s: hero.style
    unit: hero.u
    image: hero.picUrl !== "" && hero.width > 0 && hero.height > 0
           ? { url: hero.picUrl, fit: "fill", opacity: 1,
               decodeW: Math.min(960, Math.ceil(hero.width * hero.dpr)), decodeH: Math.min(960, Math.ceil(hero.height * hero.dpr)),
               shade: { color: String(hero.shadeColor), stops: [[0, 0.9], [0.55, 0.75], [1, Looks.SHADE_FLOOR]] } }
           : null
    onImageStatusChanged: {
      if (imageStatus === Image.Ready) hero.view.pictureDrawn(hero.pic)
      else if (imageStatus === Image.Error) hero.view.brokenPicture(hero.pic, hero.prio)
    }

    Column {
      x: hero.u * 2.4
      width: Math.min(parent.width * 0.5, hero.u * 50)
      anchors.verticalCenter: parent.verticalCenter
      spacing: hero.u * 0.5
      // its title logo, whole, in a box at most 40% of the width and 8 units high
      Image {
        id: logoPic
        objectName: "heroLogo"
        width: Math.min(hero.width * 0.4, parent.width)
        height: hero.u * 8
        visible: hero.logoUrl !== "" && status === Image.Ready
        source: hero.logoUrl
        sourceSize: Qt.size(Math.min(960, Math.ceil(width * hero.dpr)), Math.min(960, Math.ceil(height * hero.dpr)))
        fillMode: Image.PreserveAspectFit
        horizontalAlignment: Image.AlignLeft
        asynchronous: true
        onStatusChanged: {
          if (status === Image.Ready) hero.view.pictureDrawn(hero.logo)
          else if (status === Image.Error && source != "") hero.view.brokenPicture(hero.logo, hero.prio)
        }
      }
      // else its title (a logo that fails gives way to it)
      Item {
        width: parent.width
        height: heroTitle.implicitHeight
        visible: !logoPic.visible
        Rectangle {
          visible: hero.titleColor.plate !== ""
          x: -hero.u * 0.3
          y: -hero.u * 0.1
          width: Math.min(parent.width, heroTitle.implicitWidth) + hero.u * 0.6
          height: heroTitle.implicitHeight + hero.u * 0.2
          radius: hero.u * 0.25
          color: hero.titleColor.plate || "transparent"
        }
        Label {
          id: heroTitle
          objectName: "heroTitle"
          width: parent.width
          text: hero.item ? hero.item.title : ""
          s: hero.titleStyle
          unit: hero.u
          sizeFactor: 0.8
          color: hero.titleColor.color
          opacity: 1
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
      }
      Label {
        objectName: "heroMeta"
        width: parent.width
        visible: text !== ""
        text: hero.item ? (hero.item.meta || hero.item.subtitle || "") : ""
        s: hero.guide.look.appTopMeta
        unit: hero.u
        elide: Text.ElideRight
        maximumLineCount: 1
      }
      Label {
        objectName: "heroText"
        width: parent.width
        visible: text !== ""
        text: hero.item ? (hero.item.text || "") : ""
        s: hero.guide.look.appTopText
        unit: hero.u
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
      }
    }

    // on the item it shows (under the dots, which take their own taps)
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) { hero.tapped(hero.col, hero.guide.isFinger(mouse)) }
    }

    // which of its items this is
    Row {
      objectName: "heroDots"
      visible: hero.items.length > 1
      readonly property real dot: Math.round(hero.u * 0.7)
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: hero.u * 1.2
      spacing: hero.guide.touchMode ? Math.max(hero.u * 0.5, hero.guide.fingerPx - dot) : hero.u * 0.5
      Repeater {
        model: hero.items.length
        delegate: Rectangle {
          required property int index
          width: parent.dot
          height: width
          radius: width / 2
          color: index === hero.col ? hero.ringColor : "transparent"
          border.width: Math.max(1, Math.round(hero.u * 0.1))
          border.color: hero.ringColor
          // a finger's width round it, in tablet mode
          MouseArea {
            enabled: hero.guide.touchMode
            anchors.centerIn: parent
            width: Math.max(parent.width, hero.guide.fingerPx)
            height: width
            onClicked: hero.chose(parent.index)
          }
        }
      }
    }

    // the guide's focus ring: always round it when it's selected
    Rectangle {
      objectName: "focusHalo"
      visible: hero.current && hero.ringHalo !== ""
      anchors.fill: parent
      anchors.margins: -hero.ringW * 2
      color: "transparent"
      border.width: hero.ringW
      border.color: hero.ringHalo || "transparent"
      radius: frame.rounded ? frame.corners[0] + hero.ringW * 2 : 0
      z: 10
    }
    Rectangle {
      objectName: "focusRing"
      visible: hero.current
      anchors.fill: parent
      anchors.margins: -hero.ringW
      color: "transparent"
      border.width: hero.ringW
      border.color: hero.ringColor
      radius: frame.rounded ? frame.corners[0] + hero.ringW : 0
      z: 10
    }
  }
}
