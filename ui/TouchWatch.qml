import QtQuick

// Tablet mode's watcher (Guide.qml): over everything, it notices a finger (or
// a real mouse) without taking it from what's under it. Pointer handlers only
// watch here, so a tap still reaches the button under it and a drag still
// scrolls the list.
Item {
  id: watch

  signal touched(point at)   // a finger let go of the screen, there (in the scene)
  signal pointed()      // a real mouse or touchpad moved over it

  property real touchAt: 0                    // when a finger was last on the screen
  property point lastPos: Qt.point(-1, -1)    // where the mouse was last seen
  property point fingerAt: Qt.point(-1, -1)   // where the finger last was

  PointHandler {
    id: finger
    acceptedDevices: PointerDevice.TouchScreen
    // no buttons: the mouse events Qt makes from a finger would otherwise
    // let go of it for a moment, as if the finger had lifted (Qt's advice)
    acceptedButtons: Qt.NoButton
    onActiveChanged: {
      watch.touchAt = Date.now()
      if (active) watch.fingerAt = point.scenePosition
      else watch.touched(watch.fingerAt)
    }
    onPointChanged: {
      watch.touchAt = Date.now()
      if (active) watch.fingerAt = point.scenePosition
    }
  }

  HoverHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    // A finger moves Qt's own mouse too, and Qt sends that spot again as
    // things move under it: only a real move, away from a finger, counts
    onPointChanged: {
      var p = point.scenePosition
      var moved = Math.abs(p.x - watch.lastPos.x) + Math.abs(p.y - watch.lastPos.y) >= 2
      watch.lastPos = p
      if (moved && !finger.active && Date.now() - watch.touchAt > 800) watch.pointed()
    }
  }
}
