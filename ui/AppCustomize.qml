import QtQuick
import "../Look.js" as Look

// The Customize panel for an app's screen (C, or Options on the phone), and
// for every app's (Settings → Apps → How apps look): down the right, live
// over the screen it changes, TV-style rows like Customize Home. Its rows,
// values and changes are AppPanel's; this draws them. A row's name typed
// here (the keyboard only) is plain text, at most 40 characters.
Box {
  id: box

  required property var guide
  readonly property var panel: guide.appPanel
  readonly property real u: guide.u

  objectName: "appCustomize"
  visible: panel.open
  width: Math.min(parent.width * 0.46, u * 44)
  s: guide.look.box
  unit: u
  image: guide.areaImages ? guide.areaImages.box : null
  MouseArea { anchors.fill: parent }

  Column {
    id: top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: box.padding
    spacing: box.u * 0.4
    Label {
      objectName: "customizeTitle"
      width: parent.width
      text: box.panel.rowOpen !== "" ? "Row options"
          : box.panel.mode === "all" ? "How apps look"
          : "Customize " + (box.panel.app ? box.panel.app.name : "")
      s: guide.look.boxTitle
      unit: box.u
      sizeFactor: 1.15
      elide: Text.ElideRight
    }
    Label {
      width: parent.width
      text: box.panel.rowOpen !== "" ? "Whether it shows, your name for it, its pictures, size, layout and titles, and where it goes. Changes show as you go."
          : box.panel.mode === "all" ? "The look of every app's screen, under what you choose for one app. Left to the theme, it shows what the theme gives."
          : "Its look, and its rows. Each change is saved as you make it; the screen behind changes at once."
      s: guide.look.boxText
      unit: box.u
      sizeFactor: 1.05
      wrapMode: Text.Wrap
    }
  }

  // a row's name, being typed
  Box {
    id: renameBox
    visible: box.panel.renaming
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: top.bottom
    anchors.margins: box.padding
    anchors.topMargin: box.u * 0.8
    height: box.u * 3.4
    s: renameField.activeFocus ? guide.look["input:focused"] : guide.look.input
    unit: box.u
    z: 3
    TextInput {
      id: renameField
      objectName: "customizeName"
      anchors.fill: parent
      anchors.leftMargin: box.u
      anchors.rightMargin: box.u
      verticalAlignment: TextInput.AlignVCenter
      color: guide.ink
      font.family: guide.fonts.body
      font.pixelSize: box.u * 1.3
      maximumLength: 40
      clip: true
      onAccepted: { box.panel.rename(text); guide.focusKeys() }
      Keys.onPressed: function(event) { guide.keyFirst(event) }
      Keys.onEscapePressed: { if (guide.keyFirst(event)) return; box.panel.close(); guide.focusKeys() }
    }
    onVisibleChanged: {
      if (!visible) return
      var c = box.panel.rowChoice(box.panel.rowOpen)
      renameField.text = c.name || ""
      renameField.selectAll()
      renameField.forceActiveFocus()
    }
  }

  ListView {
    id: list
    objectName: "customizeRows"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: renameBox.visible ? renameBox.bottom : top.bottom
    anchors.bottom: foot.top
    anchors.margins: box.padding * 0.6
    anchors.topMargin: box.u * 0.8
    clip: true
    spacing: box.u * 0.4
    model: box.panel.rows
    currentIndex: box.panel.cursor
    highlightRangeMode: ListView.ApplyRange
    preferredHighlightBegin: box.u * 3
    preferredHighlightEnd: height - box.u * 5
    highlightMoveDuration: 160
    boundsBehavior: Flickable.StopAtBounds
    delegate: Item {
      id: prow
      required property var modelData
      required property int index
      readonly property string type: modelData.type
      width: list.width
      height: type === "header" ? (modelData.label ? box.u * 2.6 : box.u * 0.6) : line.implicitHeight
      Label {
        visible: prow.type === "header"
        x: Math.ceil(list.width * 0.03) + box.u * 0.4
        anchors.bottom: parent.bottom
        anchors.bottomMargin: box.u * 0.45
        text: prow.modelData.label || ""
        s: guide.look.menuHeader
        unit: box.u
      }
      MenuRow {
        id: line
        visible: prow.type !== "header"
        guide: box.guide
        width: parent.width
        height: implicitHeight
        size: 0.8
        focused: prow.index === box.panel.cursor
        readonly property var c: box.panel.rowOpen !== "" ? box.panel.rowChoice(box.panel.rowOpen) : ({})
        label: { var t = prow.type
                 return t === "look" ? "Look" : t === "top" ? "Top of the screen" : t === "background" ? "Background" : t === "bgPick" ? "Pick a picture" : t === "dim" ? "Darken"
                      : t === "details" ? "Details page" : t === "titles" ? "Titles under cards" : t === "size" ? "Card size"
                      : t === "follow" ? (box.panel.mode === "all" ? "Follow the theme" : "Follow all apps' settings")
                      : t === "row" ? prow.modelData.label
                      : t === "rowShow" ? "Show it" : t === "rowName" ? "Name" : t === "rowShape" ? "Pictures" : t === "rowSize" ? "Size"
                      : t === "rowLayout" ? "Layout" : t === "rowTitles" ? "Titles" : t === "rowUp" ? "Move up" : t === "rowDown" ? "Move down" : "" }
        kind: { var t = prow.type
                return ["look", "top", "background", "dim", "details", "titles", "size", "rowShape", "rowSize", "rowLayout", "rowTitles"].indexOf(t) >= 0 ? "choice"
                     : t === "rowShow" ? "switch" : t === "row" || t === "rowName" || t === "bgPick" ? "opens" : "action" }
        value: { var t = prow.type
                 if (["look", "top", "details", "titles", "size", "background"].indexOf(t) >= 0) return box.panel.shown(t)
                 if (t === "dim") return Math.round(box.panel.dimNow() * 100) + "%"
                 if (t === "bgPick") { var bp = box.panel.mine.background; return bp && bp.image ? "Yours" : "None yet" }
                 if (t === "row") return box.panel.rowSummary(prow.modelData.id)
                 if (t === "rowName") return line.c.name || "Its own"
                 if (t === "rowShape") return { "": "Auto", poster: "Posters", wide: "Wide", square: "Square", logo: "Logos", circle: "Round" }[line.c.shape || ""]
                 if (t === "rowSize") return line.c.size ? box.panel.label("size", line.c.size) : "As the screen"
                 if (t === "rowLayout") return line.c.layout ? { row: "Row", grid: "Grid", list: "List", hero: "Hero" }[line.c.layout] : "As the app says"
                 if (t === "rowTitles") return line.c.titles ? box.panel.label("titles", line.c.titles) : "As the screen"
                 return "" }
        on: prow.type === "rowShow" && line.c.show !== false
        onActivated: { box.panel.cursor = prow.index; box.panel.act(0) }
        // tablet mode: ‹ › as ← → (the keys' own steps)
        touchParts: true
        onStepped: function(dir) { box.panel.cursor = prow.index; box.panel.act(dir) }
      }
    }
  }

  Column {
    id: foot
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: box.padding
    spacing: box.u * 0.5
    Label {
      objectName: "customizeNote"
      width: parent.width
      visible: text !== ""
      text: box.panel.note
      s: guide.look.boxText
      unit: box.u
      color: box.panel.note.indexOf("Not saved") === 0 ? guide.colors.alert : guide.ink
      wrapMode: Text.Wrap
    }
    KeyHints {
      model: box.panel.renaming ? [{ keys: ["ENTER"], label: "Keep the name" }, { keys: [], label: "(empty: its own)" }, { keys: ["ESC"], label: "Cancel" }]
           : box.panel.rowOpen !== "" ? [{ keys: ["←", "→"], label: "Change" }, { keys: ["ENTER"], label: "Change" }, { keys: ["ESC"], label: "Back to the rows" }]
           : [{ keys: ["↑", "↓"], label: "Move" }, { keys: ["←", "→"], label: "Change" }, { keys: ["ENTER"], label: "Options" }, { keys: ["ESC"], label: "Done" }]
      size: box.u * 1.4
      capStyle: guide.look.keycap
      labelStyle: guide.look.keyLabel
    }
  }
}
