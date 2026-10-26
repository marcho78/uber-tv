import QtQuick
import QtTest

// Every QML file of the guide's code apps compiles: a property named like
// one Item already has (left, top, state…), a reserved word or a typo stops
// the whole guide from loading, so it fails here first. (Files that import
// Quickshell, AppRuntime.qml, Apps.qml, Commands.qml, Awake.qml and
// NativeSaver.qml, can't load outside the shell: the shell's own log is
// checked for those.)
Item {
  TestCase {
    name: "Compile"

    function test_compiles_data() {
      return ["AppView.qml", "AppPlayback.qml", "AppHome.qml", "AppScreens.qml", "AppPanel.qml", "AppAgent.qml", "Snapshots.qml", "Themes.qml", "RemoteTemplates.qml",
              "ui/AppScreen.qml", "ui/AppCard.qml", "ui/AppPlayer.qml", "ui/AppsScreen.qml", "ui/DialogBox.qml",
              "ui/AppStrip.qml", "ui/AppBackdrop.qml", "ui/AppTop.qml", "ui/AppHero.qml", "ui/AppCustomize.qml", "ui/AppChart.qml", "ui/AppTicker.qml", "ui/AppPage.qml",
              "ui/MultiviewTile.qml", "ui/Multiview.qml", "GuideKeys.qml", "ChannelLock.qml", "ui/LockBox.qml", "Authorize.qml", "DeveloperPresses.qml", "ui/OriginBadge.qml",
              "ui/LowerThird.qml", "ui/CardRows.qml", "ui/DetailBox.qml", "ui/MenuRow.qml", "ui/LibraryScreen.qml", "ui/TvScreen.qml", "ui/Icon.qml", "Timeshift.qml", "ui/ChannelIdent.qml", "ui/AskStrip.qml", "ui/VodBar.qml", "ui/ProgramGrid.qml", "ui/ChannelTable.qml", "ui/TopBar.qml", "ui/Masthead.qml", "ui/FlapBoard.qml", "ui/TouchWatch.qml", "ui/TouchButton.qml", "ui/TouchMore.qml", "ui/KeyHints.qml", "ui/Footer.qml", "ui/HomeScreen.qml", "ui/SettingsScreen.qml", "ui/NavRail.qml", "ui/StylePanel.qml"].filter(function(f) { return /\.qml$/.test(f) }).map(function(f) { return { tag: f, file: f } })
    }

    function test_compiles(data) {
      var c = Qt.createComponent(Qt.resolvedUrl("../../" + data.file))
      tryVerify(function() { return c.status !== Component.Loading }, 5000)
      verify(c.status === Component.Ready, data.file + ": " + c.errorString())
    }
  }
}
