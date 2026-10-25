import QtQuick
import QtTest
import "../../ui"

// Tablet mode's watcher (ui/TouchWatch.qml), over a button and a list as the
// guide has it over everything: a finger is noticed only once it lets go, and
// it still reaches what's under it (one click, the list scrolls); a finger
// never counts as the mouse, and a real mouse does.
Item {
  id: top
  width: 480; height: 360

  property int clicks: 0
  property int touched: 0
  property int pointed: 0
  property string lastInput: "touch"
  property int escapes: 0

  // a text field as the guide's have them: its Keys.onPressed notes the
  // keyboard without taking the key, its Esc notes it too
  QtObject { id: guideStub; function noteInput(kind) { top.lastInput = kind } }
  TextInput {
    id: field
    x: 20; y: 120; width: 160; height: 30
    Keys.onPressed: function(event) { guideStub.noteInput("keyboard") }
    Keys.onEscapePressed: { guideStub.noteInput("keyboard"); top.escapes++ }
  }

  Rectangle {
    id: button
    x: 20; y: 20; width: 120; height: 60
    MouseArea { anchors.fill: parent; onClicked: top.clicks++ }
  }

  ListView {
    id: list
    x: 200; y: 20; width: 200; height: 300
    model: 60
    delegate: Rectangle { width: 200; height: 40; border.width: 1 }
  }

  TouchWatch {
    id: watcher
    anchors.fill: parent
    z: 1000000
    onTouched: top.touched++
    onPointed: top.pointed++
  }

  TestCase {
    name: "TouchMode"
    when: windowShown

    function init() {
      top.clicks = 0; top.touched = 0; top.pointed = 0
      list.contentY = 0
      watcher.touchAt = 0
    }

    function test_a_tap_reaches_the_button_once_and_counts_on_release() {
      var t = touchEvent(top)
      t.press(0, button, 60, 30).commit()
      compare(top.touched, 0, "nothing while the finger is down")
      t.release(0, button, 60, 30).commit()
      compare(top.touched, 1, "noticed once it lets go")
      tryCompare(top, "clicks", 1)
      wait(50)
      compare(top.clicks, 1, "the button got exactly one click")
    }

    function test_a_drag_still_scrolls_the_list() {
      var t = touchEvent(top)
      t.press(0, list, 100, 250).commit()
      for (var i = 1; i <= 10; i++) { t.move(0, list, 100, 250 - i * 20).commit(); wait(10) }
      t.release(0, list, 100, 50).commit()
      verify(list.contentY > 40, "the list moved: " + list.contentY)
      compare(top.touched, 1)
    }

    function test_a_finger_is_not_the_mouse() {
      var t = touchEvent(top)
      t.press(0, button, 30, 30).commit()
      t.move(0, button, 50, 40).commit()
      t.release(0, button, 50, 40).commit()
      compare(top.pointed, 0, "a finger never counts as the mouse")
      // later, the list moving under where the finger was (Qt sends that
      // spot again) is still not the mouse
      wait(900)
      list.contentY = 200
      wait(100)
      list.contentY = 0
      wait(100)
      compare(top.pointed, 0, "Qt's own repeat of the finger's spot isn't the mouse")
    }

    function test_typing_after_touch_is_the_keyboard_and_still_types() {
      top.lastInput = "touch"; top.escapes = 0
      field.text = ""
      field.forceActiveFocus()
      keyClick(Qt.Key_A); keyClick(Qt.Key_B)
      compare(field.text, "ab", "the field still takes what's typed")
      compare(top.lastInput, "keyboard", "typing in a field is the keyboard")
      top.lastInput = "touch"
      keyClick(Qt.Key_Escape)
      compare(top.escapes, 1, "its Esc still acts")
      compare(top.lastInput, "keyboard", "and notes the keyboard")
    }

    function test_a_real_mouse_is_noticed() {
      mouseMove(top, 300, 200)
      mouseMove(top, 310, 210)
      verify(top.pointed > 0, "the mouse moved over it")
      compare(top.touched, 0)
    }
  }
}
