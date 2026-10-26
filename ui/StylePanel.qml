import QtQuick
import "../Look.js" as Look

// The style panel (S): down the right side with no shade, so the guide
// shows each change as you make it. Themes, colors, pictures, the banner
// and the card, saving the look as a theme, and resetting it.
Box {
  id: stylePanel

  required property var guide
  property alias list: styleList
  property alias picker: stylePicker
  property alias namingInput: namingField

  visible: guide.dialog === "style" && !guide.watching
  anchors.right: parent.right
  anchors.top: parent.top
  anchors.bottom: parent.bottom
  anchors.margins: guide.u
  width: Math.min(parent.width * 0.48, guide.u * 44)
  s: guide.look.box
  unit: guide.u
  image: guide.areaImages.box
  readonly property real inner: width - guide.u * 2.4
  // TV-style rows, like Settings (menuRow), a little smaller; in tablet mode
  // a finger tall
  readonly property real rowUnit: guide.u * 0.8
  readonly property real rowH: Math.max(Math.round(Look.px(guide.look.menuRow.height, rowUnit)), guide.touchMode ? guide.fingerPx : 0)

  MouseArea { anchors.fill: parent }

  Column {
    id: styleTop
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: guide.u * 1.2
    spacing: guide.u * 0.4

    Label {
      width: parent.width
      text: guide.styleNaming ? "Save as a theme"
          : guide.styleEditing && guide.slotOf(guide.styleEditing) ? guide.slotOf(guide.styleEditing).label
          : guide.styleView === "element" ? (Look.BY_KEY[guide.styleElement] || {}).label + (guide.styleState ? ": " + guide.styleState : "")
          : guide.styleView === "parts" ? "Parts" : guide.styleView === "layout" ? "Layout" : guide.styleView === "fonts" ? "Fonts" : "Style"
      s: guide.look.boxTitle
      unit: guide.u
      sizeFactor: 1.15
      elide: Text.ElideRight
    }
    Label {
      width: parent.width
      text: guide.styleRefused ? guide.styleRefused.charAt(0).toUpperCase() + guide.styleRefused.slice(1) + "."
            : guide.styleNaming ? "Saves the look you see, every color (yours too), the picture, the banner and the card, as a theme of its own in the Theme list."
            + (guide.currentTheme.builtIn ? "" : " Keep the name to save your changes into " + guide.currentTheme.name + ".")
            : guide.styleEditing ? guide.styleSection.charAt(0) + guide.styleSection.slice(1).toLowerCase() + ". It changes as you pick; Esc puts the old color back."
            : guide.styleView === "element" ? guide.styleAbout + ". Your changes go over the theme's; Del takes one off."
            : guide.styleView === "parts" ? "Every part of the guide: its fill, border, corners, shape, shadow and text. Pick one to style it."
            : guide.styleView === "layout" ? "How the guide is laid out: the grid, a table or a board, where the clock and preview go, and the sizes."
            : guide.styleView === "fonts" ? "The fonts parts use, by role. ← → goes through the fonts on this computer."
            : (guide.styleRows[guide.styleCursor] || {}).type === "theme" && guide.currentTheme.description ? guide.currentTheme.name + ": " + guide.currentTheme.description
            : "Themes, parts, layout and fonts, colors, pictures, the channel banner and the card. Everything changes as you go."
      s: guide.look.boxText
      unit: guide.u
      sizeFactor: 1.05
      wrapMode: Text.Wrap
    }
  }

  ListView {
    id: styleList
    visible: !guide.styleEditing && !guide.styleNaming
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: styleTop.bottom
    anchors.bottom: styleSample.visible ? styleSample.top : styleHintsColumn.top
    anchors.leftMargin: guide.u * 0.7
    anchors.rightMargin: guide.u * 0.7
    anchors.topMargin: guide.u * 0.8
    anchors.bottomMargin: guide.u * 0.8
    clip: true
    spacing: Math.round(guide.u * 0.3)
    boundsBehavior: Flickable.StopAtBounds
    model: guide.styleRows

    delegate: Item {
      id: styleItem
      required property int index
      required property var modelData
      readonly property string type: modelData.type
      readonly property bool current: index === guide.styleCursor
      // what the row shows: a swatch (a color, or "image"), a value, and
      // whether it's the user's own (bright) or the theme's (dim)
      readonly property string swatchColor: guide.styleRowSwatch(modelData)
      readonly property bool isImage: swatchColor === "image"
      readonly property bool hasValue: ["header", "saveTheme", "open", "part", "resetTheme", "resetOriginal", "undoReset", "resetPart"].indexOf(type) < 0
      readonly property bool adjustable: guide.styleRowAdjustable(modelData) || (isImage && guide.areaImages[modelData.key] !== null)
      readonly property bool yours: guide.styleRowYours(modelData)
      readonly property bool danger: ["resetTheme", "resetOriginal", "resetPart"].indexOf(type) >= 0
      readonly property var st: current ? guide.look["menuRow:focused"] : guide.look.menuRow
      readonly property var vst: current ? guide.look["menuValue:focused"] : guide.look.menuValue
      readonly property real ru: stylePanel.rowUnit
      width: styleList.width
      height: type === "header" ? (modelData.label ? guide.u * 2.6 : guide.u * 0.6) : stylePanel.rowH

      Label {
        visible: styleItem.type === "header"
        x: Math.ceil(styleItem.width * 0.03) + guide.u * 0.4
        anchors.bottom: parent.bottom
        anchors.bottomMargin: guide.u * 0.45
        text: styleItem.modelData.label || ""
        s: guide.look.menuHeader
        unit: guide.u
      }

      Box {
        id: face
        visible: styleItem.type !== "header"
        anchors.fill: parent
        // room at the sides to grow into
        anchors.leftMargin: Math.ceil(styleItem.width * 0.03)
        anchors.rightMargin: Math.ceil(styleItem.width * 0.03)
        s: styleItem.st
        unit: styleItem.ru
        scale: 1 + (Number(styleItem.st.grow) || 0)
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        // The color, over a checkerboard so see-through shows (or the picture)
        Item {
          id: swatch
          visible: styleItem.swatchColor !== ""
          anchors.left: parent.left
          anchors.leftMargin: face.padding * 0.7
          anchors.verticalCenter: parent.verticalCenter
          width: visible ? Math.round(styleItem.ru * 3) : 0
          height: Math.round(styleItem.ru * 2)
          clip: true
          Grid {
            columns: 4
            Repeater {
              model: 8
              Rectangle {
                required property int index
                width: swatch.width / 4
                height: swatch.height / 2
                color: (index + Math.floor(index / 4)) % 2 ? "#b8b8b8" : "#ffffff"
              }
            }
          }
          Rectangle {
            anchors.fill: parent
            radius: Math.round(styleItem.ru * 0.25)
            color: styleItem.isImage ? guide.navyDeep : styleItem.swatchColor || "transparent"
            border.color: styleItem.st.text ? styleItem.st.text.color : guide.ink
            border.width: 1
            Image {
              anchors.fill: parent
              anchors.margins: 1
              visible: styleItem.isImage
              source: styleItem.isImage && guide.areaImages[styleItem.modelData.key] ? guide.areaImages[styleItem.modelData.key].url : ""
              sourceSize.width: 128
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
            }
          }
        }

        Label {
          anchors.left: swatch.visible ? swatch.right : parent.left
          anchors.leftMargin: swatch.visible ? styleItem.ru * 0.8 : face.padding
          anchors.right: styleVal.visible ? styleVal.left : parent.right
          anchors.rightMargin: styleVal.visible ? styleItem.ru * 0.8 : face.padding
          anchors.verticalCenter: parent.verticalCenter
          text: guide.styleRowLabel(styleItem.modelData, styleItem.current)
          s: styleItem.st
          unit: styleItem.ru
          color: styleItem.danger && !styleItem.current ? guide.colors.alert : (t.color || "white")
          elide: Text.ElideRight
        }

        Label {
          id: styleVal
          anchors.right: parent.right
          anchors.rightMargin: face.padding
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, face.width * 0.5)
          visible: styleItem.hasValue
          // ‹ › round what ← → change: on the row under the cursor, and in
          // tablet mode on every one (a finger taps them)
          readonly property bool arrows: styleItem.adjustable && (styleItem.current || guide.touchMode)
          text: (arrows ? "‹  " : "") + guide.styleValue(styleItem.modelData) + (arrows ? "  ›" : "")
          s: styleItem.vst
          unit: styleItem.ru
          // what you changed is bright and bold; the theme's is dim
          color: styleItem.yours ? (styleItem.st.text ? styleItem.st.text.color : guide.ink) : (t.color || guide.dimInk)
          font.bold: styleItem.yours
          elide: Text.ElideMiddle
        }
      }

      MouseArea {
        anchors.fill: parent
        enabled: styleItem.type !== "header"
        cursorShape: Qt.PointingHandCursor
        // one click acts, as Enter does (the cursor goes to the row first,
        // so the keys carry on from it); a double-click's second press is
        // ignored, so a row that asks twice (a reset) still needs two clicks.
        // A finger on ‹ or › (a finger's width round each) steps it, as ← →.
        function arrowAt(x) {
          if (!styleVal.arrows || !styleVal.visible) return 0
          var left = styleVal.mapToItem(styleItem, 0, 0).x, right = left + styleVal.width, reach = guide.fingerPx / 2
          return Math.abs(x - left - reach * 0.4) <= reach ? -1 : Math.abs(x - right + reach * 0.4) <= reach ? 1 : 0
        }
        onClicked: function(mouse) {
          if (guide.styleCursor !== styleItem.index) { guide.styleCursor = styleItem.index; guide.styleArmed = "" }
          var step = guide.isFinger(mouse) ? arrowAt(mouse.x) : 0
          if (step) guide.adjustStyle(step)
          else guide.activateStyle()
        }
        onDoubleClicked: {}
      }
    }
  }

  // Naming the look to save
  Column {
    visible: guide.styleNaming
    anchors.top: styleTop.bottom
    anchors.topMargin: guide.u * 0.8
    anchors.left: parent.left
    anchors.leftMargin: guide.u * 1.2
    width: stylePanel.inner
    spacing: guide.u * 0.6

    Box {
      width: parent.width
      height: guide.u * 3.6
      s: namingField.activeFocus ? guide.look["input:focused"] : guide.look.input
      unit: guide.u

      TextInput {
        id: namingField
        anchors.fill: parent
        anchors.leftMargin: guide.u
        anchors.rightMargin: guide.u
        verticalAlignment: TextInput.AlignVCenter
        color: guide.ink
        selectionColor: guide.cellEdge
        font.family: guide.fonts.body
        font.pixelSize: guide.u * 1.35
        maximumLength: 40
        clip: true
        onTextEdited: { guide.namingNote = ""; guide.namingArmed = "" }
        function enterKey() { guide.finishNaming(true) }   // (and the keyboard's Done)
        Keys.onPressed: function(event) {
          if (guide.keyFirst(event)) return
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) enterKey()
          else if (event.key === Qt.Key_Escape) guide.finishNaming(false)
          else return
          event.accepted = true
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      visible: text !== ""
      text: guide.namingNote
      color: guide.namingArmed ? guide.marquee : guide.nowLine
      font.family: guide.fonts.body
      font.pixelSize: guide.u * 1.1
      wrapMode: Text.Wrap
    }
  }

  ColorPicker {
    id: stylePicker
    visible: guide.styleEditing !== ""
    anchors.top: styleTop.bottom
    anchors.topMargin: guide.u * 0.8
    anchors.left: parent.left
    anchors.leftMargin: guide.u * 1.2
    width: stylePanel.inner
    unit: Math.min(guide.u * 1.6, stylePanel.inner / 18.6)
    fontFamily: guide.fontFamily
    ink: guide.ink
    dim: guide.dimInk
    accent: guide.marquee
    edge: guide.cellEdge
    allowAlpha: true
    swatches: guide.pickerSwatches
    onChanged: function(value) { guide.previewColor(value) }
    onKeyed: function(event) { guide.keyFirst(event) }
    onDone: function(keep) { guide.finishPick(keep) }
  }

  // A sample of what the section colors, over a made-up picture
  Rectangle {
    id: styleSample
    readonly property string kind: guide.styleSection === "LOWER THIRD" ? "lt" : guide.styleSection === "CHANNEL CARD" ? "card"
                                 : ["BOXES & KEYS", "BOXES", "KEYS"].indexOf(guide.styleSection) >= 0 ? "boxes" : ""
    readonly property var show: guide.channels.length ? guide.showAt(guide.row, guide.now) : null
    visible: kind !== ""
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: styleHintsColumn.top
    anchors.leftMargin: guide.u * 1.2
    anchors.rightMargin: guide.u * 1.2
    anchors.bottomMargin: guide.u * 0.9
    height: Math.round(width * 9 / 16)
    clip: true
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: "#16324f" }
      GradientStop { position: 0.55; color: "#3f6e8c" }
      GradientStop { position: 1; color: "#d9894a" }
    }

    Text {
      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.margins: guide.u * 0.4
      z: 3
      text: "SAMPLE"
      color: "white"
      opacity: 0.7
      font.family: guide.fonts.body
      font.pixelSize: guide.u * 0.6
      font.bold: true
    }

    LowerThird {
      visible: styleSample.kind === "lt"
      anchors.fill: parent
      look: guide.look
      image: guide.areaImages.lt
      unit: styleSample.width / 34
      logo: guide.logoFor(guide.channels[guide.row])
      number: guide.numbers[guide.row] || "101"
      channel: guide.channels[guide.row] ? guide.channels[guide.row].name : "Channel"
      title: styleSample.show ? styleSample.show.title : "What's on"
      progress: styleSample.show && !styleSample.show.live ? Math.max(0, (guide.now - styleSample.show.start) / (styleSample.show.end - styleSample.show.start)) : 0.4
      clock: guide.clock(guide.now)
      times: !styleSample.show ? "" : styleSample.show.live ? "● LIVE" : guide.clock(styleSample.show.start) + " – " + guide.clock(styleSample.show.end)
    }

    ChannelIdent {
      anchors.fill: parent
      visible: styleSample.kind === "card"
      up: styleSample.kind === "card"
      logo: guide.logoFor(guide.channels[guide.row])
      number: guide.numbers[guide.row] || "101"
      name: guide.channels[guide.row] ? guide.channels[guide.row].name : "Channel"
      status: "tuning"
      unit: styleSample.height / 13
      look: guide.look
      alarm: guide.colors.alert
      image: guide.areaImages.card
    }

    Item {
      anchors.fill: parent
      visible: styleSample.kind === "boxes"

      Box {
        anchors.fill: parent
        s: guide.look.scrim
        unit: guide.u
      }
      Box {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -parent.height * 0.08
        width: sampleBox.implicitWidth + guide.u * 1.6
        height: sampleBox.implicitHeight + guide.u * 1.2
        s: guide.look.box
        unit: guide.u
        image: guide.areaImages.box
        Column {
          id: sampleBox
          anchors.centerIn: parent
          spacing: guide.u * 0.4
          Label {
            text: "A box"
            s: guide.look.boxTitle
            unit: guide.u
            sizeFactor: 0.9 / 1.4
          }
          KeyHints {
            model: [{ keys: ["ENTER"], label: "OK" }, { keys: ["ESC"], label: "Cancel" }]
            size: guide.u * 1.1
            capStyle: guide.look.keycap
            labelStyle: guide.look.keyLabel
          }
        }
      }
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: guide.u * 1.8
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: guide.miniBarColor }
          GradientStop { position: 1; color: Qt.rgba(guide.miniBarColor.r, guide.miniBarColor.g, guide.miniBarColor.b, guide.miniBarColor.a * 0.6) }
        }
        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.leftMargin: guide.u * 0.5
          anchors.verticalCenter: parent.verticalCenter
          text: "MINI PLAYER BAR"
          color: guide.ink
          font.family: guide.fonts.body
          font.pixelSize: guide.u * 0.7
          font.bold: true
        }
      }
    }
  }

  Column {
    id: styleHintsColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: guide.u * 1.2
    spacing: guide.u * 0.5
    Repeater {
      model: guide.dialog === "style" ? guide.styleHintRows : []
      KeyHints {
        required property var modelData
        model: modelData
        touchGuide: stylePanel.guide
        touchWidth: styleHintsColumn.width
        size: guide.u * 1.4
        capStyle: guide.look.keycap
        labelStyle: guide.look.keyLabel
      }
    }
  }
}
