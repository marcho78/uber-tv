import QtQuick
import "../Look.js" as Look

// A tablet mode button (ui/KeyHints.qml, the ⋯ panel): at least a finger
// tall and wide, its words and maybe an icon. A tap that lets go over it says
// tapped; a drag that starts on it doesn't. Styled by the touch button
// element (Look.js: its colors, border and corners; a finger sizes it).
Item {
  id: btn

  required property var guide
  property string label: ""
  property string icon: ""
  property bool primary: false        // the screen's main action (Watch)
  property bool lit: false            // ⋯ while its panel is open
  property string accessibleName: label   // what a screen reader says (⋯: More)
  signal tapped()

  readonly property real h: guide.fingerPx
  readonly property var st: (guide.look && guide.look[primary ? "touchButton:primary" : "touchButton"]) || ({})
  readonly property var grad: st.fill && typeof st.fill === "object" ? st.fill : null   // a gradient fill
  readonly property color fill: st.fill ? (grad ? grad.from : st.fill) : primary ? guide.marquee : guide.colors.boxBg
  // its words: the element's color, made to read on its fill (Guide.qml textOn)
  readonly property color ink: {
    var c = st.text && st.text.color && st.text.color !== "inherit" ? st.text.color : primary ? guide.inkOn(fill) : guide.ink
    return typeof guide.textOn === "function" ? guide.textOn(fill, c) : c
  }
  readonly property color edge: st.border && st.border.color && st.border.color !== "auto" ? st.border.color : primary ? fill : guide.colors.cellBorder
  // the border's width: a fraction of the finger (or "Npx"), in whole pixels; 0 for none
  readonly property real edgeW: {
    var w = st.border ? st.border.width : 0.025
    var px = w ? Look.px(w, h) : 0
    return px > 0 ? Math.max(1, Math.round(px)) : 0
  }

  implicitHeight: h
  implicitWidth: Math.max(h, content.implicitWidth + h * (label !== "" ? 0.6 : 0.3))

  // a screen reader finds it by its name and presses it as a tap does
  Accessible.role: Accessible.Button
  Accessible.name: accessibleName
  Accessible.onPressAction: btn.tapped()

  Rectangle {
    anchors.fill: parent
    radius: btn.h * (btn.st.radius !== undefined ? btn.st.radius : 0.22)
    color: tap.pressed ? Qt.darker(btn.fill, 1.3) : btn.fill
    gradient: btn.grad && !tap.pressed ? faceGradient : null
    border.width: btn.edgeW
    border.color: btn.lit ? btn.guide.marquee : btn.edge

    // a gradient fill, drawn as Box draws one
    Gradient {
      id: faceGradient
      orientation: btn.grad && (btn.grad.direction === "right" || btn.grad.direction === "left") ? Gradient.Horizontal : Gradient.Vertical
      GradientStop { position: 0; color: !btn.grad ? "transparent" : btn.grad.direction === "up" || btn.grad.direction === "left" ? btn.grad.to : btn.grad.from }
      GradientStop { position: 1; color: !btn.grad ? "transparent" : btn.grad.direction === "up" || btn.grad.direction === "left" ? btn.grad.from : btn.grad.to }
    }
  }

  Row {
    id: content
    anchors.centerIn: parent
    spacing: btn.h * 0.16

    Icon {
      visible: btn.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      name: btn.icon
      size: Math.round(btn.h * 0.4)
      stroke: 2
      color: btn.primary ? btn.ink : btn.guide.marquee
    }
    // the element's font, weight and case; its size a fraction of the finger
    Label {
      visible: btn.label !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: btn.label
      s: btn.st.text ? btn.st : ({ text: { size: 0.3, weight: Font.Medium } })
      unit: btn.h
      fallbackFont: btn.guide.fonts.body
      color: btn.ink
    }
  }

  // takes the press (nothing under the button gets it), says tapped if the
  // finger lets go still over it
  TapHandler {
    id: tap
    gesturePolicy: TapHandler.ReleaseWithinBounds
    onTapped: btn.tapped()
  }
}
