import QtQuick
import QtQuick.Shapes

// A line icon by name, drawn in a 24 by 24 box and scaled to size, in color.
Item {
  id: icon

  property string name: ""
  property color color: "white"
  property real size: 24
  property real stroke: 1.8

  readonly property var paths: ({
    home: "M3 10.5 L12 3 L21 10.5 L21 21 L15 21 L15 14 L9 14 L9 21 L3 21 Z",
    tv: "M3 5 L21 5 L21 17 L3 17 Z M8 21 L16 21 M12 17 L12 21",
    film: "M3 4 L21 4 L21 20 L3 20 Z M7 4 L7 20 M17 4 L17 20 M3 9 L7 9 M3 15 L7 15 M17 9 L21 9 M17 15 L21 15",
    play: "M21 12 A9 9 0 1 1 3 12 A9 9 0 1 1 21 12 Z M10 8.5 L10 15.5 L16 12 Z",
    bookmark: "M6 3.5 L18 3.5 L18 21 L12 16.8 L6 21 Z",
    record: "M21 12 A9 9 0 1 1 3 12 A9 9 0 1 1 21 12 Z M15.5 12 A3.5 3.5 0 1 1 8.5 12 A3.5 3.5 0 1 1 15.5 12 Z",
    folder: "M3 6 L3 19 L21 19 L21 8 L12 8 L10 5.5 L3 5.5 Z M3 10 L21 10",
    up: "M9 9 L4 14 L9 19 M4 14 L14 14 C17.5 14 20 11.5 20 8 L20 4",
    close: "M6 6 L18 18 M18 6 L6 18",
    power: "M12 3 L12 11 M7.2 5.6 A8 8 0 1 0 16.8 5.6",
    window: "M3 7 L17 7 L17 20 L3 20 Z M7 7 L7 4 L21 4 L21 16 L17 16",
    fullscreen: "M3 9 L3 3 L9 3 M15 3 L21 3 L21 9 M21 15 L21 21 L15 21 M9 21 L3 21 L3 15",
    search: "M17.5 11 A6.5 6.5 0 1 1 4.5 11 A6.5 6.5 0 1 1 17.5 11 Z M20 20 L15.8 15.8",
    info: "M21 12 A9 9 0 1 1 3 12 A9 9 0 1 1 21 12 Z M12 11 L12 16.5 M12 7.6 L12 7.7",
    apps: "M4 4 L10 4 L10 10 L4 10 Z M14 4 L20 4 L20 10 L14 10 Z M4 14 L10 14 L10 20 L4 20 Z M14 14 L20 14 L20 20 L14 20 Z",
    globe: "M21 12 A9 9 0 1 1 3 12 A9 9 0 1 1 21 12 Z M3 12 L21 12 M12 3 C8.5 7 8.5 17 12 21 M12 3 C15.5 7 15.5 17 12 21",
    shield: "M12 3 L20 6 L20 12 C20 16.5 16.5 19.5 12 21 C7.5 19.5 4 16.5 4 12 L4 6 Z M8.5 12 L11 14.5 L15.5 9.5",
    plus: "M12 5 L12 19 M5 12 L19 12",
    pencil: "M4 20 L4.8 15.8 L15.5 5.1 A2.1 2.1 0 0 1 18.9 8.5 L8.2 19.2 Z M13.8 6.8 L17.2 10.2",
    lock: "M7.5 11 L7.5 7.5 A4.5 4.5 0 0 1 16.5 7.5 L16.5 11 M5 11 L19 11 L19 21 L5 21 Z M12 15 L12 17.5",
    picture: "M3 5 L21 5 L21 19 L3 19 Z M3 16 L8.5 10.5 L13 15 L16 12 L21 17 M17.5 8.5 A1.5 1.5 0 1 1 14.5 8.5 A1.5 1.5 0 1 1 17.5 8.5 Z",
    link: "M10 14 L14 10 M9.5 7.5 L11.5 5.5 A4 4 0 0 1 18.5 12.5 L16.5 14.5 M14.5 16.5 L12.5 18.5 A4 4 0 0 1 5.5 11.5 L7.5 9.5",
    file: "M6 3 L14 3 L19 8 L19 21 L6 21 Z M14 3 L14 8 L19 8",
    update: "M12 3.5 L12 14.5 M7.5 10 L12 14.5 L16.5 10 M4.5 19.5 L19.5 19.5",
    rewind30: "M4.3 12 A7.7 7.7 0 1 0 6.6 6.5 M6.6 2.6 L6.6 6.5 L10.5 6.5",
    forward30: "M19.7 12 A7.7 7.7 0 1 1 17.4 6.5 M17.4 2.6 L17.4 6.5 L13.5 6.5",
    back: "M15 5 L8 12 L15 19",
    caretUp: "M5 15 L12 8 L19 15",
    caretDown: "M5 9 L12 16 L19 9",
    clock: "M20.5 12 A8.5 8.5 0 1 1 3.5 12 A8.5 8.5 0 1 1 20.5 12 Z M12 7.5 L12 12 L15 14",
    menu: "M4 7 L20 7 M4 12 L20 12 M4 17 L20 17",
    mini: "M3 5 L21 5 L21 19 L3 19 Z M12 12 L18.5 12 L18.5 16.5 L12 16.5 Z",
    gear: "M15 12 A3 3 0 1 1 9 12 A3 3 0 1 1 15 12 Z M12 2 L12 5 M12 19 L12 22 M2 12 L5 12 M19 12 L22 12 M4.9 4.9 L7 7 M17 17 L19.1 19.1 M4.9 19.1 L7 17 M17 7 L19.1 4.9"
  })
  // marks drawn solid, not as lines: X's logo
  readonly property var solids: ({
    pausebars: "M6 4.5 L10.3 4.5 L10.3 19.5 L6 19.5 Z M13.7 4.5 L18 4.5 L18 19.5 L13.7 19.5 Z",
    playsolid: "M8 4.8 L8 19.2 L19.5 12 Z",
    more: "M6.8 12 A1.8 1.8 0 1 1 3.2 12 A1.8 1.8 0 1 1 6.8 12 Z M13.8 12 A1.8 1.8 0 1 1 10.2 12 A1.8 1.8 0 1 1 13.8 12 Z M20.8 12 A1.8 1.8 0 1 1 17.2 12 A1.8 1.8 0 1 1 20.8 12 Z",
    xlogo: "M18.901 1.153h3.68l-8.04 9.19L24 22.846h-7.406l-5.8-7.584-6.638 7.584H.474l8.6-9.83L0 1.154h7.594l5.243 6.932ZM17.61 20.644h2.039L6.486 3.24H4.298Z"
  })

  implicitWidth: size
  implicitHeight: size

  Shape {
    width: 24
    height: 24
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { xScale: icon.size / 24; yScale: icon.size / 24 }
    ShapePath {
      strokeColor: icon.color
      strokeWidth: icon.stroke
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: icon.paths[icon.name] || "" }
    }
    ShapePath {
      strokeColor: "transparent"
      fillColor: icon.color
      fillRule: ShapePath.OddEvenFill
      PathSvg { path: icon.solids[icon.name] || "" }
    }
  }
}
