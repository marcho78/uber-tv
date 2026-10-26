import QtQuick

// The guide's keys: what each does depends on the box that's open, then on
// managing, watching full screen or the grid. Every key is in the help box (?).
Item {
  id: keys

  required property var guide

  anchors.fill: parent
  focus: true
  // a held ← → (J, L) let go: a tap, or the end of a scrub (Guide.qml scrubKeyUp)
  Keys.onReleased: function(event) {
    var k = event.key
    if (event.isAutoRepeat || !guide.keyHold) return
    if (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_J || k === Qt.Key_L) { guide.scrubKeyUp(); event.accepted = true }
  }
  Keys.onPressed: function(event) {
    if (guide.keyFirst(event)) return   // the keyboard; tablet mode's ⋯ panel goes
    keys.press(event)
  }
  // A key in the box that's open, then the screen: what it does there. A real
  // key comes in above; a touch button runs it with its hint's own key
  // (Guide.qml touchPress: never ← → J L, the arrows or Page Up and Down).
  function press(event) {
    var k = event.key
    // Omarchy's screen saver is up, or the key that closed it is still coming
    // (or the one that woke Uber TV's screen saver)
    if ((guide.nativeSaver && (guide.nativeSaver.up || guide.nativeSaver.settling)) || (guide.screenSaver && guide.screenSaver.settling)) { event.accepted = true; return }
    // the splash as Uber TV turns on: any key skips it
    if (guide.splash && guide.splash.running) { guide.splash.skip(); event.accepted = true; return }
    // the channel lock's box takes every key while it's up
    if (guide.channelLock && guide.channelLock.boxUp) { guide.channelLock.key(event); event.accepted = true; return }
    if (guide.sources && guide.sources.boxUp) { guide.sources.key(event); event.accepted = true; return }
    // Multiview takes every key while it's up (ui/Multiview.qml)
    if (guide.multiview && guide.multiview.active && !guide.dialog) { guide.multiview.key(event); event.accepted = true; return }
    // any key you press ends an agent's open of an app (AppView.agentOpen)
    if (guide.appView && guide.appView.agentOpen) guide.appView.userActs()
    // an app's coming up: Esc stops waiting for it
    if (guide.appOpening) {
      if (k === Qt.Key_Escape) guide.cancelAppOpen()
      event.accepted = true
      return
    }
    // an app's media, full screen: its own keys
    if (guide.appPlaying) {
      var pbk = guide.appPlayback
      if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) pbk.togglePause()
      else if (k === Qt.Key_Left) pbk.seek(-10)
      else if (k === Qt.Key_Right) pbk.seek(10)
      else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) pbk.close("user", null)
      else if (k === Qt.Key_M) guide.muted = !guide.muted
      else if (k === Qt.Key_K) guide.setKeyHints(!guide.showKeyHints)
      event.accepted = true
      return
    }
    // the Customize panel for an app's screen (or every app's): its rows
    // while it's open (typing a row's name is the name field's)
    if (guide.appPanel && guide.appPanel.open && !guide.watching && !guide.dialog) {
      var ap = guide.appPanel
      if (ap.renaming) { event.accepted = true; return }
      if (k === Qt.Key_Escape || k === Qt.Key_Backspace || (k === Qt.Key_C && ap.rowOpen === "")) ap.close()
      else if (k === Qt.Key_Up) ap.move(-1)
      else if (k === Qt.Key_Down) ap.move(1)
      else if (k === Qt.Key_Left) ap.act(-1)
      else if (k === Qt.Key_Right) ap.act(1)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) ap.act(0)
      else return
      event.accepted = true
      return
    }
    // a box hidden by the TV playing full screen was never yours (you can't
    // open one there): it goes, and the key does what it does on the TV
    if (guide.dialog && guide.dialog !== "style" && !guide.boxShown()) guide.closeDialog()
    if (guide.dialog === "remote") {
      if (guide.remoteStep === "firewall") { event.accepted = true; return }
      if (guide.remoteStep === "") {
        if (k === Qt.Key_Return || k === Qt.Key_Enter) guide.remoteAsk(guide.byUser)
        else if (k === Qt.Key_Escape || k === Qt.Key_T) guide.closeDialog()
      } else if (guide.remoteStep === "confirm") {
        if (k === Qt.Key_Return || k === Qt.Key_Enter) guide.remoteAgree(guide.byUser)
        else if (k === Qt.Key_Escape) guide.remoteStep = ""
      } else if (guide.remoteStep === "off") {
        if (k === Qt.Key_Return || k === Qt.Key_Enter) guide.turnRemoteOff(true, guide.byUser)
        else if (k === Qt.Key_N) guide.turnRemoteOff(false, guide.byUser)
        else if (k === Qt.Key_Escape) guide.remoteStep = "on"
      } else {
        if (k === Qt.Key_Up) guide.movePhones(-1)
        else if (k === Qt.Key_Down) guide.movePhones(1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Delete || k === Qt.Key_X) guide.unpairAct()
        else if (k === Qt.Key_A && !guide.remoteAllowedHere) guide.firewall("allow", guide.byUser)
        else if (k === Qt.Key_T) guide.remoteStep = "off"
        else if (k === Qt.Key_Escape) guide.closeDialog()
      }
      event.accepted = true
      return
    }
    if (guide.dialog === "help") {
      if (k === Qt.Key_Escape || k === Qt.Key_Question || k === Qt.Key_H || k === Qt.Key_Return || k === Qt.Key_Enter) guide.closeDialog()
      event.accepted = true
      return
    }
    // Reset Uber TV: Enter resets (after the password, when one's needed,
    // and a backup), Esc cancels
    if (guide.dialog === "reset") {
      if (k === Qt.Key_Return || k === Qt.Key_Enter) guide.backups.reset(guide.byUser)
      else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) guide.backups.resetEscape()
      event.accepted = true
      return
    }
    // Restore a backup: ↑↓ pick one, Enter asks first then restores, Esc goes back
    if (guide.dialog === "restore") {
      if (k === Qt.Key_Up) guide.backups.move(-1)
      else if (k === Qt.Key_Down) guide.backups.move(1)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) guide.backups.restoreAct(guide.byUser)
      else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) guide.backups.restoreEscape()
      event.accepted = true
      return
    }
    // Contributors: ↑↓ pick one, Enter opens their GitHub page
    if (guide.dialog === "contributors") {
      if (k === Qt.Key_Escape || k === Qt.Key_Backspace) guide.closeDialog()
      else if (k === Qt.Key_Up) guide.contributorPick = Math.max(0, guide.contributorPick - 1)
      else if (k === Qt.Key_Down) guide.contributorPick = Math.max(0, Math.min(guide.contributors.length - 1, guide.contributorPick + 1))
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) guide.openContributor(guide.contributorPick)
      event.accepted = true
      return
    }
    // Release notes: ↑↓ (a page with Page Up and Down) scroll them
    if (guide.dialog === "notes") {
      if (k === Qt.Key_Escape || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Backspace) guide.closeDialog()
      else if (k === Qt.Key_Up) guide.scrollNotes(-guide.u * 3)
      else if (k === Qt.Key_Down) guide.scrollNotes(guide.u * 3)
      else if (k === Qt.Key_PageUp) guide.scrollNotes(-guide.u * 24)
      else if (k === Qt.Key_PageDown) guide.scrollNotes(guide.u * 24)
      event.accepted = true
      return
    }
    if (guide.dialog === "showChoices") {
      if (k === Qt.Key_Up) guide.moveShowChoice(-1)
      else if (k === Qt.Key_Down) guide.moveShowChoice(1)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) guide.showChoiceAct()
      else if (k === Qt.Key_Escape || k === Qt.Key_Backspace || k === Qt.Key_I) guide.closeShowChoices()
      event.accepted = true
      return
    }
    if (guide.dialog === "recStream") {
      if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Y) guide.answerStream(true)
      else if (k === Qt.Key_Escape || k === Qt.Key_N || k === Qt.Key_Backspace) guide.answerStream(false)
      event.accepted = true
      return
    }
    if (guide.dialog === "demo") {
      if (k === Qt.Key_Y || k === Qt.Key_Return || k === Qt.Key_Enter) guide.answerDemo(true)
      else if (k === Qt.Key_N || k === Qt.Key_Escape) guide.answerDemo(false)
      event.accepted = true
      return
    }
    if (guide.dialog === "agent") {
      if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Y) guide.answerAgents("yes")
      else if (k === Qt.Key_N) guide.answerAgents("no")
      else if (k === Qt.Key_Escape) guide.answerAgents("later")
      event.accepted = true
      return
    }
    // The apps boxes: asking first, Get apps, the review, an app's details
    if (["appsOn", "devOn", "appCatalog", "appReview", "appInfo"].indexOf(guide.dialog) >= 0) {
      if (guide.appsBusy()) { event.accepted = true; return }
      if (k === Qt.Key_Up) guide.moveApps(-1, guide.byUser)
      else if (k === Qt.Key_Down) guide.moveApps(1, guide.byUser)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) guide.appsAct(guide.byUser)
      else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) guide.appsEscape()
      event.accepted = true
      return
    }
    if (guide.dialog === "style") {
      var styleType = (guide.styleRows[guide.styleCursor] || {}).type
      if (k === Qt.Key_Up) guide.moveStyle(-1)
      else if (k === Qt.Key_Down) guide.moveStyle(1)
      else if (k === Qt.Key_PageUp) guide.moveStyle(-8)
      else if (k === Qt.Key_PageDown) guide.moveStyle(8)
      else if (k === Qt.Key_Left) guide.adjustStyle(-1)
      else if (k === Qt.Key_Right) guide.adjustStyle(1)
      else if (k === Qt.Key_BracketLeft) guide.fadeImage(-1)
      else if (k === Qt.Key_BracketRight) guide.fadeImage(1)
      else if (k === Qt.Key_Space && ["lt", "card", "prop", "layout"].indexOf(styleType) >= 0) guide.toggleStyle()
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) guide.activateStyle()
      else if (k === Qt.Key_Delete || k === Qt.Key_Backspace || k === Qt.Key_X) guide.resetStyleRow()
      else if (k === Qt.Key_Escape) guide.styleBack()
      else if (k === Qt.Key_S) guide.closeDialog()
      event.accepted = true
      return
    }
    if (!guide.watching && guide.screen === "guide" && k === Qt.Key_H && !guide.managing && guide.homeEnabled) {
      guide.openHome()
      event.accepted = true
      return
    }
    if (!guide.watching && guide.screen !== "search" && (k === Qt.Key_Question || (k === Qt.Key_H && !guide.managing))) {
      guide.openHelp()
      event.accepted = true
      return
    }
    // W: the guide in a window, or full screen (not while typing in Search, or in a box)
    if (k === Qt.Key_W && !guide.dialog && guide.screen !== "search" && !guide.managing && !guide.railEditing && !guide.homeEditing) {
      guide.toggleDisplay()
      event.accepted = true
      return
    }
    if (guide.dialog === "filter") {
      var rowsInBox = guide.categories.length + 1 + guide.sourceRow
      var onSource = guide.sourceRow && guide.filterCursor === 0
      if (k === Qt.Key_Up) guide.filterCursor = (guide.filterCursor + rowsInBox - 1) % rowsInBox
      else if (k === Qt.Key_Down) guide.filterCursor = (guide.filterCursor + 1) % rowsInBox
      else if (onSource && (k === Qt.Key_Space || k === Qt.Key_Right)) guide.cycleSource(1)
      else if (onSource && k === Qt.Key_Left) guide.cycleSource(-1)
      else if (k === Qt.Key_Space) guide.toggleFilter(guide.filterCursor - guide.sourceRow)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) guide.applyFilter()
      else if (k === Qt.Key_Escape || k === Qt.Key_F) guide.closeDialog()
      event.accepted = true
      return
    }
    // Program listings (typing a link: its field has the keys)
    if (guide.dialog === "listings") {
      if (k === Qt.Key_Up) guide.moveListings(-1)
      else if (k === Qt.Key_Down) guide.moveListings(1)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) guide.listingsAct()
      else if (k === Qt.Key_Delete || k === Qt.Key_X) { if ((guide.listingRows[guide.listingsCursor] || {}).type === "source") guide.listingsAct() }
      else if (k === Qt.Key_Escape) guide.closeDialog()
      event.accepted = true
      return
    }
    if (guide.dialog === "remove") {
      if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Y) guide.removeUrls(guide.removeTargets)
      else if (k === Qt.Key_Escape || k === Qt.Key_N) guide.closeDialog()
      event.accepted = true
      return
    }
    // Customizing the nav rail
    if (!guide.watching && guide.railEditing) {
      var shiftRail = event.modifiers & Qt.ShiftModifier
      if (k === Qt.Key_Escape || k === Qt.Key_C) guide.closeRailPanel()
      else if (k === Qt.Key_Up && shiftRail) guide.moveRailItem(-1)
      else if (k === Qt.Key_Down && shiftRail) guide.moveRailItem(1)
      else if (k === Qt.Key_Up) guide.moveRailPanel(-1)
      else if (k === Qt.Key_Down) guide.moveRailPanel(1)
      else if (k === Qt.Key_Left) guide.railPanelAct(-1)
      else if (k === Qt.Key_Right || k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) guide.railPanelAct(1)
      event.accepted = true
      return
    }
    // The nav rail, while it's open
    if (!guide.watching && guide.railOpen) {
      if (k === Qt.Key_Up) guide.moveRail(-1)
      else if (k === Qt.Key_Down) guide.moveRail(1)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space || k === Qt.Key_Right) guide.railGo()
      else if (k === Qt.Key_C) guide.openRailPanel("rail")
      else if (k === Qt.Key_Escape || k === Qt.Key_Left) guide.closeRail()
      event.accepted = true
      return
    }
    // The strip's question, the first time (Home or the guide): update
    // notifications, then Recordings. Y turns it on, N puts it away (a held
    // key once)
    if (!guide.watching && guide.stripAsks !== "" && (guide.screen === "home" || guide.screen === "guide")
        && !guide.managing && !guide.homeEditing && (k === Qt.Key_Y || k === Qt.Key_N)) {
      if (!event.isAutoRepeat) guide.stripAnswer(k === Qt.Key_Y)
      event.accepted = true
      return
    }
    // An item's details, over the library or Search
    if (!guide.watching && guide.libDetail && (guide.screen === "library" || guide.screen === "search")) {
      if (k === Qt.Key_Escape || k === Qt.Key_Backspace) guide.libDetail = null
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) guide.libDetailOk()
      else if (k === Qt.Key_R) guide.libPlay(true)
      else if (k === Qt.Key_L) guide.libToggleList()
      else if (k === Qt.Key_Up) guide.libEpisodeMove(-1)
      else if (k === Qt.Key_Down) guide.libEpisodeMove(1)
      else if (k === Qt.Key_M) guide.muted = !guide.muted
      else return
      event.accepted = true
      return
    }
    // Search: what you type goes in the query; the arrows go into the results
    if (!guide.watching && guide.screen === "search") {
      var mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
      var typed = event.text || ""
      if (k === Qt.Key_Escape) { if (guide.searchInResults) guide.searchInResults = false; else guide.leaveSearch() }
      else if (k === Qt.Key_Down) guide.moveSearch(1, 0)
      else if (k === Qt.Key_Up) guide.moveSearch(-1, 0)
      else if (k === Qt.Key_Left) { if (guide.searchAtLeft()) guide.openRail(); else guide.moveSearch(0, -1) }
      else if (k === Qt.Key_Right) guide.moveSearch(0, 1)
      else if (k === Qt.Key_PageUp) guide.moveSearch(0, -6)
      else if (k === Qt.Key_PageDown) guide.moveSearch(0, 6)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) guide.searchEnter()
      else if (k === Qt.Key_Space && guide.searchInResults) guide.searchPlay()
      else if (k === Qt.Key_Backspace) guide.searchBackspace()
      else if (k === Qt.Key_Delete) guide.searchClear()
      else if (!mods && typed.length === 1 && typed.charCodeAt(0) >= 32 && typed.charCodeAt(0) !== 127) guide.searchType(typed)
      else return
      event.accepted = true
      return
    }
    // The Settings screen: its parts, then a part's rows
    if (!guide.watching && guide.screen === "settings" && !guide.settingsInRows) {
      if (k === Qt.Key_Up) guide.moveSettingsPart(-1)
      else if (k === Qt.Key_Down) guide.moveSettingsPart(1)
      else if (k === Qt.Key_Left) guide.openRail()
      else if (k === Qt.Key_Space || k === Qt.Key_Right || k === Qt.Key_Return || k === Qt.Key_Enter) guide.settingsInto()
      else if (k === Qt.Key_Escape || k === Qt.Key_Comma) guide.leaveSettings()
      else if (k === Qt.Key_S) guide.openStyle()
      else if (k === Qt.Key_M) guide.muted = !guide.muted
      else if (k === Qt.Key_K) guide.setKeyHints(!guide.showKeyHints)
      else return
      event.accepted = true
      return
    }
    if (!guide.watching && guide.screen === "settings") {
      if (k === Qt.Key_Up) guide.moveSettings(-1)
      else if (k === Qt.Key_Down) guide.moveSettings(1)
      else if (k === Qt.Key_Left || k === Qt.Key_Escape || k === Qt.Key_Backspace) guide.settingsOut()
      else if (k === Qt.Key_Space) guide.changeSetting(1, guide.byUser, true)
      else if (k === Qt.Key_Right || k === Qt.Key_Return || k === Qt.Key_Enter) guide.changeSetting(1, guide.byUser)
      else if (k === Qt.Key_Comma) guide.leaveSettings()
      else if (k === Qt.Key_S) guide.openStyle()
      else if (k === Qt.Key_M) guide.muted = !guide.muted
      else if (k === Qt.Key_K) guide.setKeyHints(!guide.showKeyHints)
      else return
      event.accepted = true
      return
    }
    // An app with code: its screens (the app never sees a key)
    if (!guide.watching && guide.screen === "app") {
      var av = guide.appView
      if (av.signIn) {
        // choosing its server: up and down, Enter, Esc a step back
        if (k === Qt.Key_Escape || k === Qt.Key_Backspace) av.signInBack()
        else if (k === Qt.Key_Up) av.signInMove(-1)
        else if (k === Qt.Key_Down) av.signInMove(1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) av.signInAct(guide.byUser)
        event.accepted = true
        return
      }
      if (av.settingsOpen) {
        if (k === Qt.Key_Up) av.moveSettings(-1)
        else if (k === Qt.Key_Down) av.moveSettings(1)
        else if (k === Qt.Key_Left) av.settingsAct(-1, guide.byUser)
        else if (k === Qt.Key_Right) av.settingsAct(1, guide.byUser)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) av.settingsAct(0, guide.byUser)
        else if (k === Qt.Key_Escape || k === Qt.Key_Backspace || k === Qt.Key_Comma) av.back()
        else return
        event.accepted = true
        return
      }
      if (k === Qt.Key_Escape || k === Qt.Key_Backspace) av.back()
      else if (k === Qt.Key_Up) av.move("up")
      else if (k === Qt.Key_Down) av.move("down")
      else if (k === Qt.Key_Left) { if (!av.move("left")) guide.openRail() }
      else if (k === Qt.Key_Right) av.move("right")
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) av.enter(guide.byUser)
      else if (k === Qt.Key_I) av.details(guide.byUser)
      else if (k === Qt.Key_Slash) av.startSearch(guide.byUser)
      else if (k === Qt.Key_Comma) av.openSettings(guide.byUser)
      else if (k === Qt.Key_R) av.reload(guide.byUser)
      else if (k === Qt.Key_C) guide.appPanel.openFor(av.appId, guide.byUser)
      else if (k === Qt.Key_S) guide.openStyle()
      else if (k === Qt.Key_M) guide.muted = !guide.muted
      else if (k === Qt.Key_K) guide.setKeyHints(!guide.showKeyHints)
      else return
      event.accepted = true
      return
    }
    // The Apps screen: your apps, and Get apps
    if (!guide.watching && guide.screen === "apps") {
      if (k === Qt.Key_Escape) guide.leaveApps()
      else if (k === Qt.Key_Up) guide.moveAppsTile(0, -1)
      else if (k === Qt.Key_Down) guide.moveAppsTile(0, 1)
      else if (k === Qt.Key_Left) { if (guide.appsTile % guide.appsCols !== 0 || !guide.openRail()) guide.moveAppsTile(-1, 0) }
      else if (k === Qt.Key_Right) guide.moveAppsTile(1, 0)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) guide.appsTileAct(false, guide.byUser)
      else if (k === Qt.Key_I) guide.appsTileAct(true, guide.byUser)
      else if (k === Qt.Key_X) { if ((guide.appsTiles[guide.appsTile] || {}).id === guide.appUp) guide.closeApp() }
      else if (k === Qt.Key_G) guide.openCatalog(guide.byUser)
      else if (k === Qt.Key_Slash) guide.openSearch()
      else if (k === Qt.Key_Comma) guide.openSettings("apps")
      else if (k === Qt.Key_S) guide.openStyle()
      else if (k === Qt.Key_M) guide.muted = !guide.muted
      else if (k === Qt.Key_K) guide.setKeyHints(!guide.showKeyHints)
      else return
      event.accepted = true
      return
    }
    if (!guide.watching && guide.screen === "home") {
      var shiftHome = event.modifiers & Qt.ShiftModifier
      if (guide.homeEditing) {
        if (k === Qt.Key_Escape || (k === Qt.Key_C && !guide.homeAdding)) guide.closeHomePanel()
        else if (k === Qt.Key_Up && shiftHome) guide.moveHomeSection(-1)
        else if (k === Qt.Key_Down && shiftHome) guide.moveHomeSection(1)
        else if (k === Qt.Key_Up) guide.moveHomePanel(-1)
        else if (k === Qt.Key_Down) guide.moveHomePanel(1)
        else if (k === Qt.Key_Left) guide.homePanelAct(-1)
        else if (k === Qt.Key_Space) guide.homePanelToggle()
        else if (k === Qt.Key_Right || k === Qt.Key_Return || k === Qt.Key_Enter) guide.homePanelAct(1)
        else if (k === Qt.Key_Delete || k === Qt.Key_Backspace || k === Qt.Key_X) guide.removeHomeSection()
        else return
      } else {
        if (k === Qt.Key_Escape) guide.dismiss()
        else if (k === Qt.Key_Up) guide.moveHome(-1, 0)
        else if (k === Qt.Key_Down) guide.moveHome(1, 0)
        else if (k === Qt.Key_Left) { if (!guide.homeAtLeft() || !guide.openRail()) guide.moveHome(0, -1) }
        else if (k === Qt.Key_Right) guide.moveHome(0, 1)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) guide.homeOpen()
        else if (k === Qt.Key_G) guide.closeLibrary()
        else if (k === Qt.Key_V) guide.openLibrary()
        else if (k === Qt.Key_C) guide.openHomePanel()
        else if (k === Qt.Key_Slash) guide.openSearch()
        else if (k === Qt.Key_S) guide.openStyle()
        else if (k === Qt.Key_Comma) guide.openSettings()
        else if (k === Qt.Key_T) guide.openRemote(guide.byUser)
        else if (k === Qt.Key_A) { guide.closeLibrary(); guide.openAdd() }
        else if (k === Qt.Key_M) guide.muted = !guide.muted
        else if (k === Qt.Key_K) guide.setKeyHints(!guide.showKeyHints)
        else return
      }
      event.accepted = true
      return
    }
    if (!guide.watching && guide.screen === "library") {
      var shiftLib = event.modifiers & Qt.ShiftModifier
      {
        if (k === Qt.Key_Escape) guide.leaveLibrary()
        else if (k === Qt.Key_V) guide.closeLibrary()
        else if (k === Qt.Key_H && guide.homeEnabled) guide.openHome()
        else if (k === Qt.Key_Up) guide.moveLib(-1, 0)
        else if (k === Qt.Key_Down) guide.moveLib(1, 0)
        else if (k === Qt.Key_Left) { if (!guide.libAtLeft() || !guide.openRail()) guide.moveLib(0, -1) }
        else if (k === Qt.Key_Right) guide.moveLib(0, 1)
        else if (k === Qt.Key_PageUp) guide.moveLib(0, -6)
        else if (k === Qt.Key_PageDown) guide.moveLib(0, 6)
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) guide.libEnter()
        else if (k === Qt.Key_Space) guide.libPlay(false)
        else if (k === Qt.Key_L) guide.libToggleList()
        else if (k === Qt.Key_X || k === Qt.Key_Delete) guide.libForget()
        else if (k === Qt.Key_Slash) guide.openSearch()
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) guide.libTab(k === Qt.Key_Backtab || shiftLib ? -1 : 1)
        else if (k >= Qt.Key_1 && k <= Qt.Key_9 && guide.libraryTabs[k - Qt.Key_1]) { guide.openLibrary(guide.libraryTabs[k - Qt.Key_1].key); guide.libRow = 0 }
        else if (k === Qt.Key_S) guide.openStyle()
        else if (k === Qt.Key_Comma) guide.openSettings()
        else if (k === Qt.Key_M) guide.muted = !guide.muted
        else if (k === Qt.Key_K) guide.setKeyHints(!guide.showKeyHints)
        else return
      }
      event.accepted = true
      return
    }
    if (guide.managing && !guide.watching) {
      var shift = event.modifiers & Qt.ShiftModifier
      if (k === Qt.Key_Escape || k === Qt.Key_E) guide.setManaging(false)
      else if (k === Qt.Key_Up && shift) guide.moveChannel(-1)
      else if (k === Qt.Key_Down && shift) guide.moveChannel(1)
      else if (k === Qt.Key_Up) guide.moveRow(-1)
      else if (k === Qt.Key_Down) guide.moveRow(1)
      else if (k === Qt.Key_PageUp) guide.jumpCategory(-1)
      else if (k === Qt.Key_PageDown) guide.jumpCategory(1)
      else if (k === Qt.Key_Space && shift) guide.toggleCategoryMark(guide.row)
      else if (k === Qt.Key_Space) guide.toggleMark(guide.row)
      else if (k === Qt.Key_N) guide.openRename()
      else if (k === Qt.Key_C) guide.openCategory()
      else if (k === Qt.Key_L) guide.lockTargets(guide.byUser)
      else if (k === Qt.Key_Delete || k === Qt.Key_X) guide.askRemove(guide.targets())
      else if (k === Qt.Key_M) guide.muted = !guide.muted
      else return
      event.accepted = true
      return
    }
    if (k === Qt.Key_M) guide.muted = !guide.muted
    else if (guide.watching && guide.vod) {
      // On demand: pause, seek, back to where you came from. ← → (J, L): a
      // tap 10 s, a hold scrubs the bar (let go: it goes there); Shift 1 min
      var big = event.modifiers & Qt.ShiftModifier
      var seekKey = k === Qt.Key_Left || k === Qt.Key_J || k === Qt.Key_Right || k === Qt.Key_L
      if (k === Qt.Key_Escape || k === Qt.Key_Backspace) guide.stopVod()
      else if (k === Qt.Key_Space || k === Qt.Key_K || k === Qt.Key_Return || k === Qt.Key_Enter) guide.togglePause()
      else if (seekKey && big) guide.seekVod((k === Qt.Key_Left || k === Qt.Key_J) ? -60 : 60)
      else if (seekKey) { if (!event.isAutoRepeat) guide.scrubKeyDown((k === Qt.Key_Left || k === Qt.Key_J) ? -1 : 1, k === Qt.Key_J || k === Qt.Key_L) }
      else if (k === Qt.Key_PageUp) guide.seekVod(600)
      else if (k === Qt.Key_PageDown) guide.seekVod(-600)
      else if (k === Qt.Key_Home) guide.seekVodTo(0)
      else if (k === Qt.Key_I || k === Qt.Key_Up || k === Qt.Key_Down) guide.showVodBar()
      else if (k === Qt.Key_P) guide.goPip()
      else return
    } else if (guide.watching && guide.playerControls) {
      // the player controls (↑ again): ← → (J, L) a tap 30 s, a hold scrubs;
      // Enter, K or Space pauses; ↓ back to the choices; Esc hides; ↑ nothing
      var dirKey = k === Qt.Key_Left || k === Qt.Key_J ? -1 : k === Qt.Key_Right || k === Qt.Key_L ? 1 : 0
      if (dirKey) { if (!event.isAutoRepeat) guide.scrubKeyDown(dirKey, k === Qt.Key_J || k === Qt.Key_L) }
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_K || k === Qt.Key_Space) guide.controlsAct("pause")
      else if (k === Qt.Key_Down) guide.bannerBack()
      else if (k === Qt.Key_Escape || k === Qt.Key_Backspace || k === Qt.Key_I) guide.hideBanner()
      else if (k === Qt.Key_Up) {}
      else if (k === Qt.Key_PageUp) { guide.hideBanner(); guide.surf(1) }
      else if (k === Qt.Key_PageDown) { guide.hideBanner(); guide.surf(-1) }
      else if (k === Qt.Key_P) { guide.hideBanner(); guide.goPip() }
      else return
    } else if (guide.watching && guide.bannerOptions) {
      // the banner's choices (I or Space): ← → choose, Enter picks, ↑ the
      // player controls, Esc or ↓ hides
      if (k === Qt.Key_Left) guide.moveBannerAct(-1)
      else if (k === Qt.Key_Right) guide.moveBannerAct(1)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) guide.pickBannerAct()
      else if (k === Qt.Key_Escape || k === Qt.Key_Backspace || k === Qt.Key_Down) guide.bannerBack()
      else if (k === Qt.Key_I || k === Qt.Key_Space) guide.hideBanner()
      else if (k === Qt.Key_Up) { if (!guide.recStopMenu && !guide.streamAsk && !guide.tsOffMenu && !guide.tsCantMenu) guide.openPlayerControls(true) }
      else if (k === Qt.Key_PageUp) { guide.hideBanner(); guide.surf(1) }
      else if (k === Qt.Key_PageDown) { guide.hideBanner(); guide.surf(-1) }
      else if (k === Qt.Key_P) { guide.hideBanner(); guide.goPip() }
      else if (k === Qt.Key_J) guide.tsKey("back")
      else if (k === Qt.Key_K) guide.tsKey("pause")
      else if (k === Qt.Key_L) guide.tsKey("forward")
      else return
    } else if (guide.watching) {
      if (k === Qt.Key_Escape && guide.homeEnabled) guide.turnOff()   // back to Home or the guide, the TV off
      else if (k === Qt.Key_Escape) guide.dismiss()
      else if (k === Qt.Key_Up || k === Qt.Key_PageUp) guide.surf(1)
      else if (k === Qt.Key_Down || k === Qt.Key_PageDown) guide.surf(-1)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_G) guide.showGuide()
      else if (k === Qt.Key_I || k === Qt.Key_Space) guide.openBannerOptions()
      else if (k === Qt.Key_P) guide.goPip()
      // pause and rewind: J, L (a tap 30 s) and ← → (a hold scrubs; a tap does nothing here), K pauses
      else if (k === Qt.Key_J || k === Qt.Key_L || k === Qt.Key_Left || k === Qt.Key_Right) {
        if (!event.isAutoRepeat) guide.scrubKeyDown(k === Qt.Key_J || k === Qt.Key_Left ? -1 : 1, k === Qt.Key_J || k === Qt.Key_L)
      }
      else if (k === Qt.Key_K) guide.tsKey("pause")
      else return
    } else {
      if (k === Qt.Key_Escape) guide.homeEnabled ? guide.openHome() : guide.dismiss()
      else if (k === Qt.Key_Up) guide.moveRow(-1)
      else if (k === Qt.Key_Down) guide.moveRow(1)
      else if (k === Qt.Key_Left) { if (!guide.guideAtLeft() || !guide.openRail()) guide.moveTime(-1) }
      else if (k === Qt.Key_Right) guide.moveTime(1)
      else if (k === Qt.Key_Return || k === Qt.Key_Enter) guide.watch(guide.row)
      else if (k === Qt.Key_I || k === Qt.Key_Space) guide.openShowChoices()
      else if (k === Qt.Key_V) guide.openLibrary()
      else if (k === Qt.Key_Slash) guide.openSearch()
      else if (k === Qt.Key_R) guide.refresh(true)
      else if (k === Qt.Key_A) guide.openAdd()
      else if (k === Qt.Key_O) guide.openPicker()
      else if (k === Qt.Key_L) guide.setLogos(!guide.showLogos)
      else if (k === Qt.Key_K) guide.setKeyHints(!guide.showKeyHints)
      else if (k === Qt.Key_T) guide.openRemote(guide.byUser)
      else if (k === Qt.Key_S) guide.openStyle()
      else if (k === Qt.Key_Comma) guide.openSettings()
      else if (k === Qt.Key_P) guide.goPip()
      else if (k === Qt.Key_F) guide.openFilter()
      else if (k === Qt.Key_PageUp) guide.jumpCategory(-1)
      else if (k === Qt.Key_PageDown) guide.jumpCategory(1)
      else if ((k === Qt.Key_Delete || k === Qt.Key_X) && guide.channels.length) guide.askRemove([guide.channels[guide.row].url])
      else if (k === Qt.Key_E) guide.setManaging(true)
      else return
    }
    event.accepted = true
  }
}
