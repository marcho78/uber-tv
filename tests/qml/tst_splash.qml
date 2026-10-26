import QtQuick
import QtTest
import "../../ui"

// The splash as Uber TV turns on (ui/SplashScreen.qml): it plays for its 9
// seconds, a skip ends it at once and says so, and it shows only while it
// plays. A tap skips it, and is its own: nothing under it gets that tap.
Item {
  width: 480; height: 270

  property int under: 0
  MouseArea { anchors.fill: parent; onPressed: parent.under++; onClicked: parent.under++ }
  SplashScreen { id: splash; anchors.fill: parent }

  SignalSpy { id: ended; target: splash; signalName: "finished" }

  TestCase {
    name: "Splash"
    when: windowShown

    function init() { ended.clear(); splash.skip(); ended.clear() }

    function test_plays_then_skips() {
      verify(!splash.running && !splash.visible, "nothing until it starts")
      splash.start()
      verify(splash.running && splash.visible, "playing")
      compare(splash.total, 9.0)
      tryVerify(function() { return splash.t > 0.2 }, 2000, "its clock runs")
      splash.skip()
      verify(!splash.running && !splash.visible, "a skip ends it")
      compare(ended.count, 1, "and says it's done")
    }

    function test_a_tap_skips_it_and_is_its_own() {
      splash.start()
      verify(splash.running)
      var t = touchEvent(splash)
      t.press(0, splash, 100, 100).commit()
      t.release(0, splash, 100, 100).commit()
      verify(!splash.running, "a tap skips it")
      compare(ended.count, 1)
      compare(parent.under, 0, "nothing under it got the tap")
    }

    function test_a_skip_when_not_playing_does_nothing() {
      splash.skip()
      compare(ended.count, 0)
    }

    function test_it_ends_by_itself() {
      var clock = findChild(splash, "splashClock")
      verify(clock !== null)
      splash.start()
      clock.complete()   // (its last frame at once)
      tryCompare(ended, "count", 1)
      verify(!splash.running && !splash.visible)
    }
  }
}
