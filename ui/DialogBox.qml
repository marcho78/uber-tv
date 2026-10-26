import QtQuick
import "../Look.js" as Look

// The boxes over the guide, one at a time (guide.dialog): adding channels,
// removing them, the filter, the file picker, renaming, categories, the
// phone remote, the AI agent question, the key list, and the apps boxes
// (turning apps on, Get apps, what an app asks for, an app's details). TV style, like
// Settings: big type, tall fields, lists of menu rows (menuRow) with the
// focused one lit, switches for what's on or off, scrolling when long.
Box {
  id: dialogBox

  required property var guide
  property alias renameInput: renameField
  property alias categoryInput: catField
  property alias pickInput: pickField
  property alias pickView: pickList
  property alias addInput: addField
  property alias listingsInput: listingsField

  readonly property real u: guide.u
  readonly property real rowSize: 0.85
  readonly property real rowH: Math.round(Look.px(guide.look.menuRow.height, u * rowSize))
  readonly property real rowGap: Math.round(u * 0.35)
  readonly property real fieldText: u * 1.4
  // what a list can take of the screen, under the title and over the keys
  readonly property real listRoom: Math.max(rowH * 3, height - u * 26)
  readonly property bool appBox: ["appCatalog", "appReview", "appInfo"].indexOf(guide.dialog) >= 0
  readonly property var review: guide.apps.review
  readonly property var app: guide.dialog === "appInfo" ? guide.apps.record(guide.appInfoId) : null
  function day(t) { return t ? Qt.formatDateTime(new Date(t * 1000), "MMM d, yyyy") : "" }

  anchors.fill: parent
  visible: guide.dialog !== "" && guide.dialog !== "style" && !guide.watching && !(guide.channelLock && guide.channelLock.boxUp)
  s: guide.look.scrim
  unit: guide.u

  MouseArea {
    anchors.fill: parent
    onClicked: guide.closeDialog()
  }

  Box {
    id: frame
    anchors.centerIn: parent
    // above tablet mode's keyboard while it's up
    anchors.verticalCenterOffset: -(guide.touchKeyboardHeight || 0) / 2
    width: Math.min(parent.width - dialogBox.u * 4,
                    dialogBox.u * (guide.dialog === "help" ? 100 : guide.dialog === "pick" || guide.dialog === "notes" ? 76 : guide.dialog === "remote" || guide.dialog === "contributors" || dialogBox.appBox ? 68 : 60))
    height: box.implicitHeight + frame.padding * 2
    // a box taller than the screen shrinks to fit
    scale: Math.min(1, (dialogBox.height - (guide.touchKeyboardHeight || 0) - dialogBox.u * 2) / Math.max(1, height))
    s: guide.look.box
    unit: dialogBox.u
    image: guide.areaImages.box

    MouseArea { anchors.fill: parent }

    Column {
      id: box
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: frame.padding
      spacing: dialogBox.u * 1.1

      Label {
        width: parent.width
        text: guide.dialog === "remove" ? (guide.removeTargets.length > 1 ? "Remove channels" : "Remove a channel")
              : guide.dialog === "remote" ? (guide.remoteStep === "confirm" ? "Turn on the phone remote?"
                                          : guide.remoteStep === "off" ? "Turn off the phone remote?" : "Phone remote")
              : guide.dialog === "help" ? "Keys"
              : guide.dialog === "notes" ? "Release notes"
              : guide.dialog === "contributors" ? "Contributors"
              : guide.dialog === "reset" || guide.dialog === "restore" ? guide.backups.title(guide.dialog)
              : guide.dialog === "agent" ? "Let AI agents help?"
              : guide.dialog === "demo" ? "Load the demo channels?"
              : guide.dialog === "recStream" ? "Watch it while recording?"
              : guide.dialog === "showChoices" ? (guide.showChoice && guide.showChoice.show ? guide.showChoice.show.title || "" : "")
              : guide.dialog === "appsOn" ? "Turn on apps?"
              : guide.dialog === "unknownOn" ? "Turn on third-party apps?"
              : guide.dialog === "devOn" ? "Turn on Developer mode?"
              : guide.dialog === "appCatalog" ? "Get apps"
              : guide.dialog === "appReview" ? (!dialogBox.review ? "" : (dialogBox.review.updateConsent ? "Get update for " : dialogBox.review.have && !dialogBox.review.replaces ? "Update " : "Install ") + dialogBox.review.manifest.name + "?")
              : guide.dialog === "appInfo" ? (dialogBox.app ? dialogBox.app.name : "")
              : guide.dialog === "rename" ? "Rename channel"
              : guide.dialog === "category" ? "Set category"
              : guide.dialog === "filter" ? "Show categories"
              : guide.dialog === "listings" ? (guide.listingsAdding ? "Add program listings" : "Program listings")
              : guide.dialog === "pick" ? (guide.pickSignedApps ? "Pick an app file to install" : guide.pickApps ? "Pick an app to install" : guide.pickFolders ? "Pick a folder for My Videos" : guide.pickImages ? "Pick a picture" + (guide.pickArea ? ": " + guide.imageAreaName(guide.pickArea) : " for the background")
                                                            : "Open a channel list") : "Add channels"
        s: guide.look.boxTitle
        unit: dialogBox.u
        sizeFactor: 1.3
        wrapMode: Text.Wrap
      }

      Label {
        width: parent.width
        text: guide.dialog === "remove"
              ? guide.removePrompt()
              : guide.dialog === "remote" ? guide.remotePrompt()
              : guide.dialog === "help"
              ? "Everything the guide does from the keyboard."
              : guide.dialog === "reset" || guide.dialog === "restore"
              ? guide.backups.text(guide.dialog)
              : guide.dialog === "contributors"
              ? (guide.contributors.length ? "Everyone who's helped build Uber TV, newest first. Thank you." : "No one yet.")
              : guide.dialog === "notes"
              ? (guide.updates.notesStatus === "loading" ? "Getting the release notes…"
                 : guide.updates.notesStatus === "failed" ? "Couldn't get the release notes."
                 : guide.updates.notes === "" ? "There are no release notes for version " + guide.updates.notesFor + "."
                 : guide.updates.notesFor !== guide.updates.installed ? "What's new in " + guide.updates.notesFor + "."
                 : "What's in version " + guide.updates.notesFor + ".")
              : guide.dialog === "recStream"
              ? guide.streamAskText()
              : guide.dialog === "showChoices"
              ? guide.showChoiceText()
              : guide.dialog === "demo"
              ? guide.demoLineup.channels.length + " YouTube channels to start with, in " + guide.demoLineup.categories + " categories: news, weather, space, live cams, music and more. "
                + "Remove any you don't want, or add your own with A."
              : guide.dialog === "agent"
              ? "Turn on the guide's skill and AI agents like Claude Code and Codex can make themes, change colors, add M3U playlists and sort your channels into categories, when you ask them to. "
                + "It links the skill into the folders agents read skills from (" + guide.agentFolders.join(", ") + "); turning it off, in Settings (,), takes those links out. "
                + "Agents can't turn on the phone remote, and remove channels only when you ask."
              : guide.dialog === "appsOn"
              ? "Apps bring services like Netflix and Hulu into the guide, each opening full screen, as on a TV. They come from the Uber TV catalog, checked and signed with its key, or with the guide itself, and before one is installed you see what it asks for. "
                + "Most are launchers: a website the guide opens full screen in your browser's app window, with nothing run on this computer. A few, like Scores, run in a sandbox and the guide draws their screens. Each app has its own switch, and turning apps off stops them all. AI agents can't turn apps on or install them."
              : guide.dialog === "unknownOn"
              ? "Install signed apps from other developers. You see who made each one before installing it, and it gets updates only from that developer. Turning it on asks for your computer's password."
                + (guide.authBusy ? "\n\nWaiting for the computer's password…" : "")
              : guide.dialog === "devOn"
              ? "For testing apps you're building. Unsigned apps get no updates and open only while Developer mode is on. Turning it on asks for your computer's password."
                + (guide.authBusy ? "\n\nWaiting for the computer's password…" : "")
              : guide.dialog === "appCatalog"
              ? (guide.apps.bundled.length ? "Apps that come with the guide, then " : "") + (guide.apps.catalog ? (guide.apps.bundled.length ? guide.catalogName(guide.apps.catalog.name) : guide.apps.catalog.name) + ": apps checked and signed with its key. Pick one to see who made it and what it asks for." : guide.apps.fetching ? "Getting the catalog…" : "")
                + (guide.apps.catalogError ? " " + guide.apps.catalogError.charAt(0).toUpperCase() + guide.apps.catalogError.slice(1) + "." : "")
              : guide.dialog === "appReview"
              ? (!dialogBox.review ? "" : "By " + dialogBox.review.manifest.author + "  ·  version " + dialogBox.review.manifest.version
                 + (dialogBox.review.have ? " (you have " + dialogBox.review.have.version + ")" : "") + (dialogBox.review.manifest.description ? "\n" + dialogBox.review.manifest.description : ""))
              : guide.dialog === "appInfo"
              ? (!dialogBox.app ? "" : (dialogBox.app.description ? dialogBox.app.description + "\n" : "") + "By " + dialogBox.app.author + "  ·  version " + dialogBox.app.version
                 + "  ·  installed " + dialogBox.day(dialogBox.app.installed) + (dialogBox.app.used ? "  ·  opened " + dialogBox.day(dialogBox.app.used) : ""))
              : guide.dialog === "rename"
              ? "New name for " + guide.channelLabel(guide.row) + "."
              : guide.dialog === "category"
              ? (guide.markedCount ? guide.markedCount + " marked channels" : guide.channelLabel(guide.row))
                + ": pick a category, or type a new one."
              : guide.dialog === "listings" && guide.listingsAdding
              ? "A link to an XMLTV file (.xml, .xml.gz or .xml.xz), or a full path to one on this computer. Your provider may give you one; free ones are listed by country at epgshare01.online."
              : guide.dialog === "listings"
              ? "Show by show, what's on your IPTV channels: XMLTV files, matched to your channels by their ids and names. "
                + (guide.epg.sources.length ? guide.epg.matched + " of your " + guide.iptvCount + " IPTV channels have listings." : "Add a link or a file to start.")
              : guide.dialog === "filter"
              ? (guide.hasIptv ? "Pick YouTube, IPTV or both, and the categories to show. " : "Pick the categories to show. ") + "Channel numbers stay the same."
              : guide.dialog === "pick" && guide.pickSignedApps
              ? "Signed app files (.tvapp) in your home folder, newest first. Type to search by name or folder, or Tab to browse inside your home folder. Picking one contacts nothing; nothing is installed until you've seen its developer key and what it asks for."
              : guide.dialog === "pick" && guide.pickApps
              ? "App packages (.tar.gz) and apps' folders (pick its app.json) in your home folder, newest first. Type to search by name or folder, or Tab to browse your folders. Nothing is installed until you've seen what it asks for."
              : guide.dialog === "pick" && guide.pickFolders
              ? "The folders in your home folder, the ones you changed last first. Type to search by name, or Tab to browse. My Videos shows the videos in it, and in the folders inside it."
              : guide.dialog === "pick" && guide.pickImages
              ? "Pictures in your home folder and your Omarchy backgrounds (.jpg, .png, .webp), newest first. Type to search by name or folder, or Tab to browse your folders."
              : guide.dialog === "pick"
              ? "Playlists (.m3u, .m3u8) and lists (.txt, .csv, .tsv, .json), newest first. Type to search, or Tab to browse."
              : "One per line, as many as you like."
        s: guide.look.boxText
        unit: dialogBox.u
        sizeFactor: 1.15
        wrapMode: Text.Wrap
      }

      // ---- adding channels: what can go in the box ----
      Column {
        visible: guide.dialog === "add"
        width: parent.width
        spacing: dialogBox.u * 0.45
        Repeater {
          model: guide.dialog === "add" ? [["YouTube", "channel names, links, @handles, playlist links"],
                                           ["IPTV", "M3U or M3U8 playlist links, or a stream's link"],
                                           ["Files", "the path to an M3U playlist, a text list, a lineup (.json) or your YouTube subscriptions (subscriptions.csv)"]] : []
          delegate: Row {
            required property var modelData
            width: parent.width
            spacing: dialogBox.u * 1.4
            Label {
              width: dialogBox.u * 6.5
              anchors.baseline: addWhat.baseline
              text: modelData[0]
              s: guide.look.menuHeader
              unit: dialogBox.u
            }
            Label {
              id: addWhat
              width: parent.width - dialogBox.u * 6.5 - parent.spacing
              text: modelData[1]
              s: guide.look.boxText
              unit: dialogBox.u
              sizeFactor: 1.15
              wrapMode: Text.Wrap
            }
          }
        }
      }

      // ---- the key list, in three columns (the guide; Home to watching;
      // the rest). Each section's keys are as wide as its widest; a long
      // line goes on to the next rather than being cut ----
      Row {
        visible: guide.dialog === "help"
        width: parent.width
        spacing: dialogBox.u * 2.4

        Repeater {
          model: guide.dialog === "help" ? [guide.helpSections.slice(0, 1), guide.helpSections.slice(1, 5), guide.helpSections.slice(5)] : []
          delegate: Column {
            id: helpColumn
            required property var modelData
            width: (parent.width - dialogBox.u * 4.8) / 3
            spacing: dialogBox.u * 0.9

            Repeater {
              model: helpColumn.modelData
              delegate: Column {
                id: helpSection
                required property var modelData
                width: helpColumn.width
                spacing: dialogBox.u * 0.2
                property real keysWidth: dialogBox.u * 8.6   // grows to the section's widest keys

                Label {
                  text: helpSection.modelData.title
                  s: guide.look.menuHeader
                  unit: dialogBox.u
                  sizeFactor: 1.1
                }
                Repeater {
                  model: helpSection.modelData.keys
                  delegate: Row {
                    id: helpRow
                    required property var modelData
                    spacing: dialogBox.u * 0.6
                    Item {
                      width: helpSection.keysWidth
                      height: Math.max(dialogBox.u * 1.75, helpText.implicitHeight)
                      KeyHints {
                        id: helpKeys
                        anchors.verticalCenter: parent.verticalCenter
                        model: [{ keys: helpRow.modelData[0], label: "" }]
                        size: dialogBox.u * 1.4
                        capStyle: guide.look.keycap
                        labelStyle: guide.look.keyLabel
                        labelColor: guide.ink
                        onImplicitWidthChanged: if (implicitWidth + dialogBox.u * 0.4 > helpSection.keysWidth) helpSection.keysWidth = implicitWidth + dialogBox.u * 0.4
                      }
                    }
                    Label {
                      id: helpText
                      anchors.verticalCenter: parent.verticalCenter
                      width: helpSection.width - helpSection.keysWidth - helpRow.spacing
                      text: helpRow.modelData[1]
                      s: guide.look.boxText
                      unit: dialogBox.u
                      sizeFactor: 1.08
                      color: helpRow.modelData[0].length ? guide.ink : guide.dimInk
                      wrapMode: Text.WordWrap
                    }
                  }
                }
              }
            }
          }
        }
      }

      // ---- an app's review, for the couch: who and
      // where from, one line on what it can do, then a row a group with its
      // icon (changing things first), Can't as one line; long lists, Can't
      // and an update's old asks fold, and OK opens them ----
      Column {
        id: reviewBox
        visible: guide.dialog === "appReview" && dialogBox.review !== null
        width: parent.width
        spacing: dialogBox.u * 0.7
        readonly property bool update: !!dialogBox.review && !!dialogBox.review.have && !dialogBox.review.replaces
        readonly property bool hasNew: update && dialogBox.review.newAsks.length > 0
        readonly property bool code: !!dialogBox.review && dialogBox.review.manifest.kind === "app"
        readonly property bool ours: !!dialogBox.review && (dialogBox.review.from === "bundled" || dialogBox.review.from === "catalog")
        readonly property var groups: !dialogBox.review ? []
            : guide.apps.groupsOf(hasNew ? dialogBox.review.newAsks : dialogBox.review.asks, dialogBox.review.manifest.permissions,
                                  hasNew ? [] : dialogBox.review.manifest.home)
        readonly property var cursorRow: guide.appsBoxRows[guide.appsCursor] || {}
        function opened(key) { return !!guide.reviewOpen[key] }
        function focusedOn(key) { return guide.dialog === "appReview" && reviewBox.cursorRow.type === "fold" && reviewBox.cursorRow.key === key }
        function foldIndex(key) {
          var rows = guide.appsBoxRows
          for (var i = 0; i < rows.length; i++) if (rows[i].type === "fold" && rows[i].key === key) return i
          return -1
        }

        // who, and where it's from
        Row {
          spacing: dialogBox.u * 0.9
          Item {
            width: Math.round(dialogBox.u * 3.6)
            height: width
            anchors.verticalCenter: parent.verticalCenter
            Image {
              id: reviewIcon
              anchors.fill: parent
              source: dialogBox.review && dialogBox.review.manifest.icon ? "file://" + dialogBox.review.staging + "/" + dialogBox.review.manifest.icon : ""
              sourceSize.width: width * 2
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              cache: false
            }
            Icon {
              visible: reviewIcon.status !== Image.Ready
              anchors.centerIn: parent
              name: "apps"
              size: parent.width * 0.8
              stroke: 2
              color: guide.ink
            }
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            width: box.width - dialogBox.u * 4.5
            spacing: dialogBox.u * 0.2
            Label {
              width: parent.width
              text: !dialogBox.review ? "" : dialogBox.review.manifest.name + "  ·  " + dialogBox.review.manifest.author + "  ·  version " + dialogBox.review.manifest.version
                    + (reviewBox.code ? "  ·  an app with code" : "  ·  a website")
              s: guide.look.boxText
              unit: dialogBox.u
              sizeFactor: 1.1
              font.bold: true
              elide: Text.ElideRight
            }
            Label {
              width: parent.width
              text: !dialogBox.review ? "" : guide.apps.originLine(dialogBox.review.from, guide.catalogName(dialogBox.review.file), dialogBox.review.fingerprint)
                    + (dialogBox.review.from === "file" ? " (" + guide.shownPath(dialogBox.review.file) + ")" : "")
              s: guide.look.boxText
              unit: dialogBox.u
              color: reviewBox.ours ? guide.marquee : guide.colors.alert
              wrapMode: Text.Wrap
            }
            Label {
              width: parent.width
              visible: reviewBox.code && !reviewBox.ours
              text: "It runs in its sandbox with only what's listed below."
              s: guide.look.menuNote
              unit: dialogBox.u
              wrapMode: Text.Wrap
            }
          }
        }
        Label {
          visible: text !== ""
          width: parent.width
          text: !dialogBox.review || !dialogBox.review.have ? ""
                : dialogBox.review.replaces && dialogBox.review.from === "appFile" && dialogBox.review.have.from === "appFile"
                ? "This file has the same app id but a different developer key. It installs as a new app: none of the old app's saved data, settings, sign-in, server, pictures or Activity is kept."
                : dialogBox.review.replaces ? "It takes the place of the " + dialogBox.review.have.name + " you installed "
                  + (dialogBox.review.replaces === "file" ? "from a file" : dialogBox.review.replaces === "bundled" ? "with the guide" : dialogBox.review.replaces === "appFile" ? "from a signed app file" : "from the catalog")
                  + (dialogBox.review.manifest.kind === "app" || dialogBox.review.have.kind === "app" ? ": none of that app's saved data, settings or sign-in is kept." : ".")
                : dialogBox.review.from === "file" && dialogBox.review.manifest.kind === "app" ? "This replaces the app from a file you installed before, and gets its saved data, settings and sign-in."
                : ""
          s: guide.look.menuNote
          unit: dialogBox.u
          wrapMode: Text.Wrap
        }
        Column {
          visible: !!dialogBox.review && dialogBox.review.updateConsent === true
          width: parent.width
          spacing: dialogBox.u * 0.15
          Label {
            text: "WHAT AGREE WILL FETCH"
            s: guide.look.menuHeader
            unit: dialogBox.u
            color: guide.marquee
          }
          Label {
            width: parent.width
            text: !dialogBox.review ? "" : "Address: " + dialogBox.review.fetchAddress
                  + "\nVersion: " + dialogBox.review.manifest.version
                  + "  ·  Size: " + guide.apps.sizeWords(dialogBox.review.fetchSize)
                  + "\nDeveloper key: " + dialogBox.review.fingerprint
            s: guide.look.boxText
            unit: dialogBox.u
            wrapMode: Text.Wrap
          }
          Label {
            width: parent.width
            text: "Only Agree downloads this package. It still has to match this signed release exactly."
            s: guide.look.menuNote
            unit: dialogBox.u
            wrapMode: Text.Wrap
          }
        }
        // what it can do, in a line
        Label {
          width: parent.width
          topPadding: dialogBox.u * 0.2
          text: !dialogBox.review ? "" : guide.apps.summary(dialogBox.review.manifest.permissions, dialogBox.review.manifest.kind)
          s: guide.look.boxText
          unit: dialogBox.u
          sizeFactor: 1.2
          font.bold: true
          wrapMode: Text.Wrap
        }
        // an update shows what's new in it, then what it had before, folded
        Label {
          visible: reviewBox.hasNew
          text: "NEW IN VERSION " + (dialogBox.review ? dialogBox.review.manifest.version : "")
          s: guide.look.menuHeader
          unit: dialogBox.u
          sizeFactor: 1.1
          color: guide.marquee
        }
        // a row a group
        Repeater {
          model: reviewBox.groups
          delegate: Row {
            required property var modelData
            readonly property bool long: modelData.lines.length > 3
            readonly property bool open: long && reviewBox.opened(modelData.key)
            spacing: dialogBox.u * 0.8
            Icon {
              name: modelData.icon
              size: Math.round(dialogBox.u * 1.5)
              stroke: 2
              color: modelData.strong ? guide.marquee : guide.ink
            }
            Column {
              width: box.width - dialogBox.u * 2.3
              spacing: dialogBox.u * 0.15
              Label {
                text: modelData.title.toUpperCase()
                s: guide.look.menuHeader
                unit: dialogBox.u
                color: reviewBox.hasNew || modelData.strong ? guide.marquee : t.color
              }
              Label {
                width: parent.width
                text: (open || !long ? modelData.lines : modelData.lines.slice(0, 3)).join(", ")
                s: guide.look.boxText
                unit: dialogBox.u
                sizeFactor: 1.15
                color: reviewBox.hasNew || modelData.strong ? guide.marquee : guide.ink
                font.bold: reviewBox.hasNew || modelData.strong
                wrapMode: Text.Wrap
              }
              MenuRow {
                visible: long
                guide: dialogBox.guide
                width: parent.width
                height: visible ? implicitHeight : 0
                size: dialogBox.rowSize * 0.85
                focused: reviewBox.focusedOn(modelData.key)
                label: open ? "Fewer" : "And " + (modelData.lines.length - 3) + " more"
                kind: "opens"
                onActivated: { var i = reviewBox.foldIndex(modelData.key); if (guide.appsCursor !== i && !byFinger) guide.appsCursor = i; else { guide.appsCursor = i; guide.appsAct(guide.byUser) } }
              }
              Label {
                width: parent.width
                visible: text !== ""
                text: modelData.note
                s: guide.look.menuNote
                unit: dialogBox.u
                wrapMode: Text.Wrap
              }
            }
          }
        }
        // an update: what it had before, folded
        MenuRow {
          visible: reviewBox.update && reviewBox.foldIndex("before") >= 0
          guide: dialogBox.guide
          width: parent.width
          height: visible ? implicitHeight : 0
          size: dialogBox.rowSize * 0.85
          focused: reviewBox.focusedOn("before")
          label: "And what it had before"
          kind: "opens"
          onActivated: { var i = reviewBox.foldIndex("before"); if (guide.appsCursor !== i && !byFinger) guide.appsCursor = i; else { guide.appsCursor = i; guide.appsAct(guide.byUser) } }
        }
        Label {
          width: parent.width
          visible: reviewBox.update && reviewBox.opened("before")
          text: !visible ? "" : guide.apps.groupsOf(guide.apps.hadBefore(dialogBox.review), dialogBox.review.manifest.permissions, dialogBox.review.manifest.home)
                                 .map(function(g) { return g.title + ": " + g.lines.join(", ") }).join("\n")
          s: guide.look.boxText
          unit: dialogBox.u
          wrapMode: Text.Wrap
        }
        // Can't, one calm line that opens
        MenuRow {
          visible: reviewBox.code
          guide: dialogBox.guide
          width: parent.width
          height: visible ? implicitHeight : 0
          size: dialogBox.rowSize * 0.85
          focused: reviewBox.focusedOn("cant")
          icon: "shield"
          label: "Can't reach your files, channels, other apps or sites it didn't list"
          kind: "opens"
          onActivated: { var i = reviewBox.foldIndex("cant"); if (guide.appsCursor !== i && !byFinger) guide.appsCursor = i; else { guide.appsCursor = i; guide.appsAct(guide.byUser) } }
        }
        Label {
          width: parent.width
          visible: reviewBox.code && reviewBox.opened("cant")
          text: "It can't see your files, your channels, your watch history or your other apps; reach sites it didn't list, or your home network beyond the server you choose; run programs or change Uber TV; or use more than its share of memory and processor. The guide draws its screens and plays what it plays."
          s: guide.look.menuNote
          unit: dialogBox.u
          wrapMode: Text.Wrap
        }
        Label {
          width: parent.width
          visible: !reviewBox.code
          text: "It runs no code on this computer: it's a website, opened full screen in your browser's app window. You sign in on the website itself, never in the guide."
          s: guide.look.menuNote
          unit: dialogBox.u
          wrapMode: Text.Wrap
        }
      }

      // ---- an installed app: where it's from, what it's allowed ----
      Column {
        visible: guide.dialog === "appInfo" && dialogBox.app !== null
        width: parent.width
        spacing: dialogBox.u * 0.6

        Label {
          width: parent.width
          visible: text !== ""
          text: !dialogBox.app ? "" : dialogBox.app.revoked ? "Turned off: " + (dialogBox.app.from === "appFile" ? "its developer withdrew this version. " : "the catalog pulled it. ") + dialogBox.app.revoked
                : dialogBox.app.broken ? "Turned off: " + dialogBox.app.broken.charAt(0).toLowerCase() + dialogBox.app.broken.slice(1) + ". Remove it, and install it again."
                : dialogBox.app.update ? "Update available: version " + dialogBox.app.update.version + ". " + (!dialogBox.app.update.asks.length ? "It asks for nothing new."
                                         : "it also asks to " + dialogBox.app.update.asks.map(function(x) { return x.charAt(0).toLowerCase() + x.slice(1) }).join(", ") + ".")
                : ""
          s: guide.look.boxText
          unit: dialogBox.u
          sizeFactor: 1.1
          font.bold: true
          color: dialogBox.app && dialogBox.app.update && !dialogBox.app.revoked && !dialogBox.app.broken ? guide.marquee : guide.colors.alert
          wrapMode: Text.Wrap
        }
        Label {
          width: parent.width
          text: !dialogBox.app ? "" : guide.apps.originLine(dialogBox.app.from, guide.catalogName(dialogBox.app.catalogName),
                                                            dialogBox.app.from === "appFile" ? dialogBox.app.keyFingerprint || "" : "")
                + (dialogBox.app.from === "file" ? " (" + guide.shownPath(dialogBox.app.file) + ")" : "")
          s: guide.look.menuNote
          unit: dialogBox.u
          wrapMode: Text.Wrap
        }
        Label {
          width: parent.width
          visible: !!dialogBox.app
          text: dialogBox.app ? guide.apps.summary(dialogBox.app.permissions, dialogBox.app.kind) : ""
          s: guide.look.boxText
          unit: dialogBox.u
          sizeFactor: 1.1
          font.bold: true
          wrapMode: Text.Wrap
        }
        // what it's allowed, a line a group (the review's rows, all shown)
        Repeater {
          model: dialogBox.app ? guide.apps.groupsOf(guide.apps.asks(dialogBox.app.permissions, dialogBox.app.settings), dialogBox.app.permissions, dialogBox.app.home) : []
          delegate: Row {
            required property var modelData
            spacing: dialogBox.u * 0.8
            Icon {
              name: modelData.icon
              size: Math.round(dialogBox.u * 1.3)
              stroke: 2
              color: modelData.strong ? guide.marquee : guide.ink
            }
            Label {
              width: box.width - dialogBox.u * 2.1
              text: modelData.title + ": " + modelData.lines.join(", ")
              s: guide.look.boxText
              unit: dialogBox.u
              sizeFactor: 1.05
              color: modelData.strong ? guide.marquee : guide.ink
              wrapMode: Text.Wrap
            }
          }
        }
        // Activity: the sites it contacted and the ones it was refused
        // (lib/appactivity.py); past the first few, a row that Enter opens
        Column {
          id: activityBox
          visible: !!dialogBox.app && dialogBox.app.kind === "app"
          width: parent.width
          spacing: dialogBox.u * 0.2
          readonly property var act: guide.appActivity
          readonly property var shown: guide.apps.activityShown
          readonly property bool allSites: !!guide.reviewOpen["sites"]
          readonly property bool allRefused: !!guide.reviewOpen["refused"]
          readonly property var sites: !act || act.failed ? [] : allSites ? act.sites : act.sites.slice(0, shown.sites)
          readonly property var refused: !act || act.failed ? [] : allRefused ? act.refused : act.refused.slice(0, shown.refused)
          function focusedOn(key) { var r = guide.appsBoxRows[guide.appsCursor] || {}; return guide.dialog === "appInfo" && r.type === "fold" && r.key === key }
          function act_(key) {
            var rows = guide.appsBoxRows
            for (var i = 0; i < rows.length; i++) if (rows[i].type === "fold" && rows[i].key === key) {
              if (guide.appsCursor !== i) guide.appsCursor = i; else guide.appsAct(guide.byUser)
              return
            }
          }
          Label {
            text: "ACTIVITY, THE LAST 90 DAYS"
            s: guide.look.menuHeader
            unit: dialogBox.u
            topPadding: dialogBox.u * 0.3
          }
          Label {
            width: parent.width
            visible: text !== ""
            text: !activityBox.act ? "Reading…" : activityBox.act.failed ? "Its Activity couldn't be read just now."
                  : !activityBox.act.sites.length && !activityBox.act.refused.length && !activityBox.act.refusedMore ? "It hasn't contacted any site yet." : ""
            s: guide.look.menuNote
            unit: dialogBox.u
          }
          Repeater {
            model: activityBox.sites
            delegate: Label {
              required property var modelData
              width: box.width
              text: (modelData.server ? "Your server (" + modelData.site + ")" : modelData.site) + ": "
                    + (modelData.reads ? "got things " + guide.apps.times(modelData.reads) : "")
                    + (modelData.reads && modelData.writes ? ", " : "")
                    + (modelData.writes ? "changed things " + guide.apps.times(modelData.writes) : "")
                    + " · " + guide.apps.sizeWords(modelData.sent + modelData.received) + " · " + guide.agoLabel(modelData.last)
              s: guide.look.boxText
              unit: dialogBox.u
              color: modelData.writes ? guide.marquee : guide.ink
              wrapMode: Text.Wrap
            }
          }
          MenuRow {
            readonly property int more: activityBox.act && !activityBox.act.failed ? activityBox.act.sites.length - activityBox.shown.sites : 0
            visible: more > 0
            guide: dialogBox.guide
            width: parent.width
            height: visible ? implicitHeight : 0
            size: dialogBox.rowSize * 0.85
            focused: activityBox.focusedOn("sites")
            label: activityBox.allSites ? "Fewer" : "And " + more + " more " + (more === 1 ? "site" : "sites")
            kind: "opens"
            onActivated: activityBox.act_("sites")
          }
          Repeater {
            model: activityBox.refused
            delegate: Label {
              required property var modelData
              width: box.width
              text: (modelData.change ? "Tried to change things on " : "Tried to reach ") + modelData.site + ": refused, " + guide.apps.times(modelData.count)
              s: guide.look.boxText
              unit: dialogBox.u
              color: guide.colors.alert
              wrapMode: Text.Wrap
            }
          }
          MenuRow {
            readonly property int more: activityBox.act && !activityBox.act.failed ? activityBox.act.refused.length - activityBox.shown.refused : 0
            visible: more > 0
            guide: dialogBox.guide
            width: parent.width
            height: visible ? implicitHeight : 0
            size: dialogBox.rowSize * 0.85
            focused: activityBox.focusedOn("refused")
            label: activityBox.allRefused ? "Fewer" : "And " + more + " more refused " + (more === 1 ? "site" : "sites")
            kind: "opens"
            onActivated: activityBox.act_("refused")
          }
          Label {
            width: parent.width
            readonly property int more: activityBox.act && !activityBox.act.failed ? activityBox.act.refusedMore : 0
            visible: more > 0
            text: "And " + more + " more refused " + (more === 1 ? "attempt" : "attempts") + " whose sites weren't kept"
            s: guide.look.menuNote
            unit: dialogBox.u
            wrapMode: Text.Wrap
          }
        }
        Item { width: 1; height: dialogBox.u * 0.3 }
      }

      // ---- the apps boxes' rows: Not now / Turn on, the catalog, Install / Cancel, an app's ----
      ListView {
        id: appRows
        visible: ["appsOn", "unknownOn", "devOn", "appCatalog", "appReview", "appInfo"].indexOf(guide.dialog) >= 0
        width: parent.width
        height: visible ? Math.min(dialogBox.listRoom, count * (dialogBox.rowH + dialogBox.rowGap) - dialogBox.rowGap) : 0
        clip: true
        spacing: dialogBox.rowGap
        // the review's and the details' folded rows are drawn in them (above): here, their buttons
        readonly property int offset: guide.dialog === "appReview" || guide.dialog === "appInfo" ? guide.appsBoxRows.filter(function(r) { return r.type === "fold" }).length : 0
        model: visible ? guide.appsBoxRows.slice(offset) : []
        currentIndex: guide.appsCursor - offset
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: dialogBox.rowH
        preferredHighlightEnd: height - dialogBox.rowH * 2
        highlightMoveDuration: 120
        boundsBehavior: Flickable.StopAtBounds

        delegate: MenuRow {
          required property int index
          required property var modelData
          readonly property var have: modelData.type === "app" ? guide.apps.rowRecord(modelData) : null   // installed from this row's origin only
          guide: dialogBox.guide
          width: appRows.width
          height: implicitHeight
          size: dialogBox.rowSize
          focused: index + appRows.offset === guide.appsCursor
          icon: modelData.type === "app" ? "apps" : ""
          label: modelData.label
          kind: modelData.type === "toggle" ? "switch" : ["app", "update"].indexOf(modelData.type) >= 0 ? "opens" : "action"
          on: modelData.type === "toggle" && !!dialogBox.app && dialogBox.app.enabled && !dialogBox.app.broken && !dialogBox.app.revoked
          danger: modelData.type === "remove" || (modelData.type === "yes" && (guide.dialog === "devOn" || guide.dialog === "unknownOn"))
          value: modelData.type === "app"
                 ? (guide.apps.inspecting && focused ? "Checking…"
                    : !have ? "By " + modelData.entry.author
                    : guide.apps.newer(modelData.entry.version, have.version) ? "Update to " + modelData.entry.version : "Installed")
                 : modelData.type === "remove" && guide.appsArmed ? "Enter again to remove"
                 : modelData.type === "install" && guide.apps.preparing ? "Getting it ready…"
                 : modelData.type === "install" && guide.apps.installing ? "Installing…"
                 : ""
          onActivated: {
            if (guide.appsBusy()) return
            // a finger acts at once (a removal still asks again); a click picks first
            if (guide.appsCursor !== index + appRows.offset) { guide.appsCursor = index + appRows.offset; guide.appsArmed = ""; if (!byFinger) return }
            guide.appsAct(guide.byUser)
          }
        }
      }

      Label {
        width: parent.width
        visible: (dialogBox.appBox || guide.dialog === "devOn" || guide.dialog === "unknownOn") && text !== ""
        text: guide.apps.status
        s: guide.look.boxText
        unit: dialogBox.u
        sizeFactor: 1.1
        color: /^(Not installed|Couldn't)/.test(guide.apps.status) ? guide.colors.alert : guide.marquee
        wrapMode: Text.Wrap
      }

      // ---- the phone remote, while on: QR code, code, address, paired phones ----
      Column {
        visible: guide.dialog === "remote" && guide.remoteStep === "on" && guide.remoteReady
        width: parent.width
        spacing: dialogBox.u * 1.1

        Row {
          spacing: dialogBox.u * 2
          Rectangle {
            width: dialogBox.u * 15
            height: width
            radius: dialogBox.u * 0.4
            color: "white"
            Image {
              anchors.fill: parent
              anchors.margins: dialogBox.u * 0.5
              source: guide.dialog === "remote" && guide.remoteStep === "on" && guide.remotePairing && guide.remotePairing.qr ? "file://" + guide.remotePairing.qr : ""
              fillMode: Image.PreserveAspectFit
              smooth: false
              cache: false
            }
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: dialogBox.u * 0.6
            Label {
              text: "Pairing code"
              s: guide.look.menuHeader
              unit: dialogBox.u
              sizeFactor: 1.1
            }
            Label {
              text: guide.remotePairing ? guide.remotePairing.code.slice(0, 3) + " " + guide.remotePairing.code.slice(3) : "…"
              s: guide.look.boxTitle
              unit: dialogBox.u
              sizeFactor: 4.2 / Math.max(0.2, guide.look.boxTitle.text.size)
              font.letterSpacing: dialogBox.u * 0.25
              color: guide.marquee
            }
            Label {
              text: guide.remotePairing ? "A new code in " + Math.max(0, Math.round(guide.remotePairing.expires - guide.remoteClock)) + " s" : ""
              s: guide.look.menuNote
              unit: dialogBox.u
            }
            Label {
              text: guide.remoteNet ? "http://" + guide.remoteNet.address + ":" + guide.remotePort : ""
              s: guide.look.boxText
              unit: dialogBox.u
              sizeFactor: 1.3
              font.bold: true
            }
            Label {
              text: guide.remoteNet ? "or http://" + guide.remoteNet.hostname + ":" + guide.remotePort : ""
              s: guide.look.menuNote
              unit: dialogBox.u
            }
          }
        }

        Label {
          text: guide.remoteDevices.length ? "Paired phones" : "No phones paired yet"
          s: guide.look.menuHeader
          unit: dialogBox.u
          sizeFactor: 1.1
        }
        Repeater {
          model: guide.remoteDevices
          delegate: MenuRow {
            required property int index
            required property var modelData
            guide: dialogBox.guide
            width: parent.width
            height: implicitHeight
            size: dialogBox.rowSize
            focused: index === guide.remoteCursor
            label: modelData.name
            kind: "action"
            danger: guide.remoteArmed === modelData.id
            value: guide.remoteArmed === modelData.id ? "Enter again to unpair"
                 : "Paired " + Qt.formatDateTime(new Date(modelData.added * 1000), "MMM d") + " · used " + Qt.formatDateTime(new Date(modelData.seen * 1000), "MMM d")
                   + (index === guide.remoteCursor ? " · Unpair" : "")
            onActivated: { if (guide.remoteCursor !== index) { guide.remoteCursor = index; guide.remoteArmed = ""; if (!byFinger) return } guide.unpairAct() }
          }
        }
      }

      // ---- renaming ----
      Box {
        visible: guide.dialog === "rename"
        width: parent.width
        height: dialogBox.u * 3.8
        s: renameField.activeFocus ? guide.look["input:focused"] : guide.look.input
        unit: dialogBox.u

        TextInput {
          id: renameField
          anchors.fill: parent
          anchors.leftMargin: dialogBox.u
          anchors.rightMargin: dialogBox.u
          verticalAlignment: TextInput.AlignVCenter
          color: guide.ink
          selectionColor: guide.cellEdge
          font.family: guide.fonts.body
          font.pixelSize: dialogBox.fieldText
          clip: true
          maximumLength: 60
          onAccepted: guide.renameChannel(guide.row, text)
          Keys.onPressed: function(event) { guide.keyFirst(event) }
          Keys.onEscapePressed: { if (guide.keyFirst(event)) return; guide.closeDialog() }
        }
      }

      // ---- setting a category: type to filter, or name a new one ----
      Column {
        visible: guide.dialog === "category"
        width: parent.width
        spacing: dialogBox.rowGap

        Box {
          width: parent.width
          height: dialogBox.u * 3.8
          s: catField.activeFocus ? guide.look["input:focused"] : guide.look.input
          unit: dialogBox.u

          TextInput {
            id: catField
            anchors.fill: parent
            anchors.leftMargin: dialogBox.u
            anchors.rightMargin: dialogBox.u
            verticalAlignment: TextInput.AlignVCenter
            color: guide.ink
            selectionColor: guide.cellEdge
            font.family: guide.fonts.body
            font.pixelSize: dialogBox.fieldText
            clip: true
            maximumLength: 40
            onTextChanged: {
              guide.catQuery = text
              guide.catCursor = 0
            }
            // Enter, here and as tablet mode's keyboard's Done
            function enterKey() { if (guide.catOptions[guide.catCursor]) guide.setCategory(guide.targets(), guide.catOptions[guide.catCursor].value) }
            Keys.onPressed: function(event) {
              if (guide.keyFirst(event)) return
              if (event.key === Qt.Key_Escape) guide.closeDialog()
              else if (event.key === Qt.Key_Up) guide.moveCat(-1)
              else if (event.key === Qt.Key_Down) guide.moveCat(1)
              else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && guide.catOptions[guide.catCursor]) catField.enterKey()
              else return
              event.accepted = true
            }
          }
        }

        Item { width: 1; height: dialogBox.u * 0.3 }

        Repeater {
          model: guide.dialog === "category" ? guide.catOptions.slice(0, 8) : []
          delegate: MenuRow {
            required property int index
            required property var modelData
            guide: dialogBox.guide
            width: parent.width
            height: implicitHeight
            size: dialogBox.rowSize
            focused: index === guide.catCursor
            label: modelData.label
            value: modelData.isNew ? "New category" : ""
            onActivated: guide.setCategory(guide.targets(), modelData.value)
          }
        }
      }

      // ---- the file picker: a search line (or, browsing, a filter for the
      // folder you're in), then the files ----
      Column {
        visible: guide.dialog === "pick"
        width: parent.width
        spacing: dialogBox.u * 0.7

        Box {
          width: parent.width
          height: dialogBox.u * 3.8
          s: pickField.activeFocus ? guide.look["input:focused"] : guide.look.input
          unit: dialogBox.u

          TextInput {
            id: pickField
            anchors.fill: parent
            anchors.leftMargin: dialogBox.u
            anchors.rightMargin: modes.width + dialogBox.u * 2
            verticalAlignment: TextInput.AlignVCenter
            color: guide.ink
            selectionColor: guide.cellEdge
            font.family: guide.fonts.body
            font.pixelSize: dialogBox.fieldText
            clip: true
            function enterKey() { guide.choosePick(guide.byUser) }   // (and the keyboard's Done)
            onTextChanged: {
              guide.pickQuery = text
              guide.pickCursor = 0
              pickList.positionViewAtBeginning()
            }
            Keys.onPressed: function(event) {
              if (guide.keyFirst(event)) return
              if (event.key === Qt.Key_Escape) guide.pickEscape()
              else if (event.key === Qt.Key_Up) guide.movePick(-1)
              else if (event.key === Qt.Key_Down) guide.movePick(1)
              else if (event.key === Qt.Key_PageUp) guide.movePick(-6)
              else if (event.key === Qt.Key_PageDown) guide.movePick(6)
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) pickField.enterKey()
              else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) guide.pickToggleBrowse()
              else if (event.key === Qt.Key_Backspace && guide.pickBrowse && pickField.text === "") guide.browseUp()
              else return
              event.accepted = true
            }
          }

          // Search or Browse (Tab), a click too
          Row {
            id: modes
            anchors.right: parent.right
            anchors.rightMargin: dialogBox.u * 0.6
            anchors.verticalCenter: parent.verticalCenter
            spacing: dialogBox.u * 0.3
            Repeater {
              model: [{ browse: false, label: "Search" }, { browse: true, label: "Browse" }]
              delegate: Rectangle {
                required property var modelData
                readonly property bool on: guide.pickBrowse === modelData.browse
                width: modeLabel.implicitWidth + dialogBox.u * 1.2
                height: modeLabel.implicitHeight + dialogBox.u * 0.5
                radius: height / 2
                color: on ? guide.marquee : "transparent"
                border.width: 1
                border.color: on ? guide.marquee : guide.dimInk
                Text {
                  id: modeLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: parent.modelData.label
                  color: parent.on ? guide.inkOn(String(guide.marquee)) : guide.dimInk
                  font.family: guide.fonts.body
                  font.pixelSize: Math.round(dialogBox.fieldText * 0.7)
                  font.bold: parent.on
                }
                MouseArea {
                  anchors.fill: parent
                  // tablet mode: a finger tall, past the pill
                  anchors.topMargin: guide.touchMode ? -Math.max(0, (guide.fingerPx - parent.height) / 2) : 0
                  anchors.bottomMargin: guide.touchMode ? -Math.max(0, (guide.fingerPx - parent.height) / 2) : 0
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { if (!parent.on) guide.pickToggleBrowse(); pickField.forceActiveFocus() }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            anchors.fill: pickField
            verticalAlignment: Text.AlignVCenter
            visible: pickField.text === ""
            text: guide.pickBrowse ? guide.shownPath(guide.pickDir) + "  ·  type to filter"
                  : guide.pickApps ? "myapp.tar.gz  ·  app.json" : guide.pickFolders ? "videos  ·  movies  ·  recordings" : guide.pickImages ? "wallpapers  ·  pictures  ·  png" : "subscriptions  ·  downloads csv  ·  channels"
            elide: Text.ElideMiddle
            color: guide.dimInk
            opacity: 0.6
            font.family: guide.fonts.body
            font.pixelSize: dialogBox.fieldText
          }
        }

        ListView {
          id: pickList
          width: parent.width
          height: Math.min(dialogBox.listRoom, (dialogBox.rowH + dialogBox.rowGap) * 6)
          clip: true
          spacing: dialogBox.rowGap
          model: guide.dialog === "pick" ? guide.pickMatches : []
          currentIndex: guide.pickCursor
          highlightRangeMode: ListView.ApplyRange
          preferredHighlightBegin: dialogBox.rowH
          preferredHighlightEnd: height - dialogBox.rowH
          highlightMoveDuration: 120
          boundsBehavior: Flickable.StopAtBounds

          // a TV-style row: the picture (for pictures), the name, its folder, when
          delegate: Item {
            id: pickRow
            required property int index
            required property var modelData
            readonly property bool focused: index === guide.pickCursor
            readonly property var st: focused ? guide.look["menuRow:focused"] : guide.look.menuRow
            readonly property var vst: focused ? guide.look["menuValue:focused"] : guide.look.menuValue
            readonly property real unitHere: dialogBox.u * dialogBox.rowSize
            width: pickList.width
            height: dialogBox.rowH

            Box {
              id: pickFace
              anchors.fill: parent
              anchors.leftMargin: Math.ceil(pickRow.width * 0.02)
              anchors.rightMargin: Math.ceil(pickRow.width * 0.02)
              s: pickRow.st
              unit: pickRow.unitHere
              scale: 1 + (Number(pickRow.st.grow) || 0) * 0.66
              Behavior on scale { NumberAnimation { duration: 120 } }

              Image {
                id: pickThumb
                anchors.left: parent.left
                anchors.leftMargin: pickFace.padding * 0.6
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool picture: guide.pickImages && !pickRow.modelData.dir && !pickRow.modelData.up && !pickRow.modelData.here
                visible: picture
                width: picture ? height * 16 / 9 : 0
                height: parent.height - dialogBox.u * 0.7
                source: picture ? "file://" + pickRow.modelData.path : ""
                sourceSize.width: 240
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }
              Icon {
                id: pickIcon
                visible: !pickThumb.picture
                anchors.left: parent.left
                anchors.leftMargin: pickFace.padding
                anchors.verticalCenter: parent.verticalCenter
                name: pickRow.modelData.up ? "up" : pickRow.modelData.dir || pickRow.modelData.here ? "folder" : guide.pickApps ? "apps" : guide.pickFolders ? "folder" : "bookmark"
                size: Math.round(pickRow.unitHere * 1.4)
                stroke: 2
                color: pickRow.st.text ? pickRow.st.text.color : "white"
              }
              Label {
                id: pickName
                anchors.left: pickThumb.picture ? pickThumb.right : pickIcon.right
                anchors.leftMargin: pickRow.unitHere * 0.9
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, pickFace.width * 0.42)
                text: pickRow.modelData.name !== undefined ? pickRow.modelData.name : pickRow.modelData.shown.split("/").pop()
                s: pickRow.st
                unit: pickRow.unitHere
                elide: Text.ElideRight
              }
              Label {
                anchors.left: pickName.right
                anchors.leftMargin: pickRow.unitHere
                anchors.right: pickWhen.left
                anchors.rightMargin: pickRow.unitHere
                anchors.verticalCenter: parent.verticalCenter
                text: pickRow.modelData.where !== undefined ? pickRow.modelData.where : pickRow.modelData.shown.replace(/\/[^\/]*$/, "")
                s: pickRow.vst
                unit: pickRow.unitHere
                sizeFactor: 0.85
                elide: Text.ElideLeft
              }
              Label {
                id: pickWhen
                anchors.right: parent.right
                anchors.rightMargin: pickFace.padding
                anchors.verticalCenter: parent.verticalCenter
                text: pickRow.modelData.mtime ? Qt.formatDateTime(new Date(pickRow.modelData.mtime * 1000), "MMM d") : ""
                s: pickRow.vst
                unit: pickRow.unitHere
                sizeFactor: 0.85
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) { guide.pickCursor = pickRow.index; if (guide.isFinger(mouse)) guide.choosePick(guide.byUser) }
                onDoubleClicked: { guide.pickCursor = pickRow.index; guide.choosePick(guide.byUser) }
              }
            }
          }

          Label {
            anchors.centerIn: parent
            visible: pickList.count === 0
            text: guide.pickSearching ? (guide.pickBrowse ? "Opening…" : "Searching…")
                  : guide.pickBrowse ? (guide.pickQuery ? "No matches in this folder" : "Nothing to pick here")
                  : guide.pickFiles.length ? "No matches"
                  : guide.pickApps ? "No app packages or app.json files in your home folder" : guide.pickFolders ? "No folders found" : guide.pickImages ? "No pictures found in your home folder" : "No channel lists found in your home folder"
            s: guide.look.menuNote
            unit: dialogBox.u
          }
        }

        Label {
          visible: !guide.pickSearching
          text: guide.pickApps && guide.apps.inspecting ? "Checking it…" : guide.pickApps && guide.apps.status ? guide.apps.status
              : guide.pickBrowse ? guide.shownPath(guide.pickDir)
              : guide.pickMatches.length + (guide.pickFolders ? (guide.pickMatches.length === 1 ? " folder" : " folders")
                                            : guide.pickImages ? (guide.pickMatches.length === 1 ? " picture" : " pictures")
                                            : (guide.pickMatches.length === 1 ? " file" : " files"))
                + (guide.pickMatches.length >= 300 ? " (the first 300)" : "")
          s: guide.look.menuNote
          unit: dialogBox.u
        }
      }

      // ---- the filter: YouTube, IPTV or both, and the categories ----
      ListView {
        id: filterList
        visible: guide.dialog === "filter"
        width: parent.width
        // [the sources (with IPTV channels)], all channels, then each category
        readonly property var rows: guide.dialog !== "filter" ? []
          : (guide.hasIptv ? [{ type: "source" }] : []).concat([{ type: "all" }])
            .concat(guide.categories.map(function(c) { return { type: "cat", cat: c } }))
        height: visible ? Math.min(dialogBox.listRoom, rows.length * (dialogBox.rowH + dialogBox.rowGap) - dialogBox.rowGap) : 0
        clip: true
        spacing: dialogBox.rowGap
        model: rows
        currentIndex: guide.filterCursor
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: dialogBox.rowH
        preferredHighlightEnd: height - dialogBox.rowH * 2
        highlightMoveDuration: 120
        boundsBehavior: Flickable.StopAtBounds

        delegate: MenuRow {
          required property int index
          required property var modelData
          guide: dialogBox.guide
          width: filterList.width
          height: implicitHeight
          size: dialogBox.rowSize
          focused: index === guide.filterCursor
          label: modelData.type === "source" ? "Sources" : modelData.type === "all" ? "All channels" : guide.categoryName(modelData.cat)
          kind: modelData.type === "source" ? "choice" : "switch"
          value: modelData.type === "source" ? guide.sourceName(guide.sourceDraft) : ""
          on: modelData.type === "all" ? !guide.filterDraft.length : modelData.type === "cat" && guide.filterChecked(modelData.cat)
          onActivated: {
            guide.filterCursor = index
            if (modelData.type === "source") guide.cycleSource(1)
            else guide.toggleFilter(index - guide.sourceRow)
          }
          touchParts: true
          onStepped: function(dir) { guide.filterCursor = index; guide.cycleSource(dir) }
        }
      }

      // ---- a show's choices (I or Space in the guide): Watch, Record or Save video ----
      Column {
        visible: guide.dialog === "showChoices"
        width: parent.width
        spacing: dialogBox.rowGap
        Repeater {
          model: guide.dialog === "showChoices" ? guide.showChoices : []
          delegate: MenuRow {
            required property int index
            required property var modelData
            guide: dialogBox.guide
            width: parent.width
            height: implicitHeight
            size: dialogBox.rowSize
            // the recording ones (Record, Record every episode, Cancel, Stop…) as the record choice element
            element: modelData.key === "watch" ? "menuRow" : "recordChoice"
            focused: index === guide.showCursor
            icon: modelData.key === "watch" ? "tv" : ["record", "schedule", "series"].indexOf(modelData.key) >= 0 ? "record" : ""
            label: modelData.label
            value: modelData.note || ""
            dim: modelData.unavailable === true
            onActivated: { if (guide.showCursor === index || byFinger) { guide.showCursor = index; guide.showChoiceAct(index) } else guide.showCursor = index }
          }
        }
      }

      // ---- program listings: the sources, adding one, fetching ----
      Column {
        visible: guide.dialog === "listings" && !guide.listingsAdding
        width: parent.width
        spacing: dialogBox.rowGap

        Repeater {
          model: guide.dialog === "listings" ? guide.listingRows : []
          delegate: MenuRow {
            required property int index
            required property var modelData
            readonly property var result: modelData.type === "source" ? guide.epg.sourceReport(modelData.url) : null
            guide: dialogBox.guide
            width: parent.width
            height: implicitHeight
            size: dialogBox.rowSize
            focused: index === guide.listingsCursor
            icon: modelData.type === "add" ? "" : modelData.type === "fetch" ? "" : "tv"
            label: modelData.type === "source" ? guide.listingName(modelData.url) + (modelData.from === "playlist" ? "  (from a playlist)" : "")
                 : modelData.type === "add" ? "Add a link or a file" : "Get the listings now"
            kind: modelData.type === "add" ? "opens" : "action"
            danger: modelData.type === "source" && guide.listingsArmed === modelData.url
            value: modelData.type === "source"
                   ? (guide.listingsArmed === modelData.url ? "Enter again to remove"
                      : !result ? (guide.epg.busy ? "Fetching…" : "Not fetched yet")
                      : result.ok ? result.matched + (result.matched === 1 ? " channel" : " channels") : result.error || "Failed")
                 : modelData.type === "fetch" ? (guide.epg.busy ? guide.epg.status || "Fetching…" : guide.epg.fetched ? "Last " + guide.agoLabel(guide.epg.fetched) : "")
                 : ""
            onActivated: { guide.listingsCursor = index; guide.listingsAct() }
          }
        }
      }

      Box {
        visible: guide.dialog === "listings" && guide.listingsAdding
        width: parent.width
        height: dialogBox.u * 3.8
        s: listingsField.activeFocus ? guide.look["input:focused"] : guide.look.input
        unit: dialogBox.u

        TextInput {
          id: listingsField
          anchors.fill: parent
          anchors.leftMargin: dialogBox.u
          anchors.rightMargin: dialogBox.u
          verticalAlignment: TextInput.AlignVCenter
          color: guide.ink
          selectionColor: guide.cellEdge
          font.family: guide.fonts.body
          font.pixelSize: dialogBox.fieldText
          clip: true
          maximumLength: 2000
          onAccepted: guide.addListingsFrom(text)
          Keys.onPressed: function(event) { guide.keyFirst(event) }
          Keys.onEscapePressed: { if (guide.keyFirst(event)) return; guide.listingsBack() }
        }
        Text {
          textFormat: Text.PlainText
          anchors.fill: listingsField
          verticalAlignment: Text.AlignVCenter
          visible: listingsField.text === ""
          text: "https://…/guide.xml.gz   or   ~/Downloads/guide.xml"
          color: guide.dimInk
          opacity: 0.6
          font.family: guide.fonts.body
          font.pixelSize: dialogBox.fieldText
        }
      }

      Label {
        width: parent.width
        visible: guide.dialog === "listings" && text !== ""
        text: guide.listingsNote
        s: guide.look.boxText
        unit: dialogBox.u
        sizeFactor: 1.1
        color: guide.colors.alert
        wrapMode: Text.Wrap
      }

      // ---- the backups, to restore one: ↑↓ and Enter, or a click ----
      ListView {
        id: backupList
        visible: guide.dialog === "restore" && guide.backups.list.length > 0 && guide.backups.restoreStep !== "busy"
        width: parent.width
        height: visible ? Math.min(guide.backups.list.length, 6) * (Math.round(Look.px(guide.look.menuRow.height, dialogBox.u * dialogBox.rowSize)) + spacing) : 0
        clip: true
        spacing: Math.round(dialogBox.u * 0.4)
        model: guide.dialog === "restore" ? guide.backups.list : []
        currentIndex: guide.backups.pick
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: 0
        preferredHighlightEnd: height
        boundsBehavior: Flickable.StopAtBounds
        delegate: MenuRow {
          required property int index
          required property var modelData
          guide: dialogBox.guide
          width: backupList.width
          height: implicitHeight
          size: dialogBox.rowSize
          oneClick: true
          focused: index === guide.backups.pick
          label: guide.backups.when(modelData.made)
          value: guide.backups.bytes(modelData.size)
          onActivated: guide.backups.choose(index)
        }
      }

      // ---- contributors: ↑↓, and Enter (or a click) opens their GitHub page ----
      ListView {
        id: contributorList
        visible: guide.dialog === "contributors" && guide.contributors.length > 0
        width: parent.width
        height: visible ? Math.min(guide.contributors.length, 8) * (Math.round(Look.px(guide.look.menuRow.height, dialogBox.u * dialogBox.rowSize)) + spacing) : 0
        clip: true
        spacing: Math.round(dialogBox.u * 0.4)
        model: guide.dialog === "contributors" ? guide.contributors : []
        currentIndex: guide.contributorPick
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: 0
        preferredHighlightEnd: height
        boundsBehavior: Flickable.StopAtBounds
        delegate: MenuRow {
          required property int index
          required property var modelData
          guide: dialogBox.guide
          width: contributorList.width
          height: implicitHeight
          size: dialogBox.rowSize
          oneClick: true
          kind: "opens"
          focused: index === guide.contributorPick
          label: "@" + modelData.handle
          value: modelData.did + (modelData.version ? "  ·  " + modelData.version : "")
          onActivated: { guide.contributorPick = index; guide.openContributor(index) }
        }
      }

      // ---- release notes, scrolled with ↑↓ or the wheel ----
      Flickable {
        id: notesScroll
        visible: guide.dialog === "notes" && guide.updates.notesShown !== ""
        width: parent.width
        height: visible ? Math.min(dialogBox.u * 34, dialogBox.height * 0.55) : 0
        contentWidth: width
        contentHeight: notesText.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onVisibleChanged: if (visible) contentY = 0
        Text {
          id: notesText
          width: notesScroll.width
          textFormat: Text.StyledText
          wrapMode: Text.Wrap
          text: guide.dialog === "notes" ? guide.updates.notesShown : ""
          color: guide.ink
          font.family: guide.fonts.body
          font.pixelSize: Math.round(dialogBox.u * 1.15)
          lineHeight: 1.15
        }
        Connections {
          target: guide
          function onScrollNotes(by) {
            notesScroll.contentY = Math.max(0, Math.min(notesScroll.contentHeight - notesScroll.height, notesScroll.contentY + by))
          }
        }
      }

      // ---- adding channels ----
      Box {
        visible: guide.dialog === "add"
        width: parent.width
        height: dialogBox.u * 11
        s: addField.activeFocus ? guide.look["input:focused"] : guide.look.input
        unit: dialogBox.u

        Flickable {
          id: addScroll
          anchors.fill: parent
          anchors.margins: dialogBox.u
          contentWidth: width
          contentHeight: addField.contentHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          function follow(r) {
            if (contentY >= r.y) contentY = r.y
            else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
          }

          // Plain text: rich text pasted from a web page stays text.
          TextEdit {
            id: addField
            width: addScroll.width
            height: Math.max(addScroll.height, contentHeight)
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.Wrap
            color: guide.ink
            selectionColor: guide.cellEdge
            font.family: guide.fonts.body
            font.pixelSize: dialogBox.u * 1.3
            selectByMouse: true
            readOnly: guide.jobTotal > 0
            onCursorRectangleChanged: addScroll.follow(cursorRectangle)
            function enterKey() { guide.addChannel(text) }   // (and the keyboard's Done)
            Keys.onPressed: function(event) {
              if (guide.keyFirst(event)) return
              if (event.key === Qt.Key_Escape) {
                guide.closeDialog()
                event.accepted = true
              } else if (event.key === Qt.Key_O && (event.modifiers & Qt.ControlModifier)) {
                guide.openPicker()
                event.accepted = true
              } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                addField.enterKey()
                event.accepted = true
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.fill: addScroll
          visible: addField.text === ""
          text: "Veritasium\nhttps://www.youtube.com/@kurzgesagt\nhttps://example.com/channels.m3u\n~/Downloads/subscriptions.csv"
          color: guide.dimInk
          opacity: 0.6
          font.family: guide.fonts.body
          font.pixelSize: dialogBox.u * 1.3
        }
      }

      Label {
        width: parent.width
        visible: text !== ""
        text: guide.dialog !== "add" ? ""
              : guide.jobTotal === 1 ? "Checking…"
              : guide.jobTotal > 1 ? "Checking " + Math.min(guide.jobDone + 1, guide.jobTotal) + " of " + guide.jobTotal + "…  " + guide.inFlight + " at a time"
              : guide.addStatus
        s: guide.look.boxText
        unit: dialogBox.u
        sizeFactor: 1.15
        font.bold: true
        color: guide.addFailed ? guide.nowLine : guide.marquee
        wrapMode: Text.Wrap
      }

      // its keys; in tablet mode, its buttons (a finger tall, never shrunk)
      Item {
        width: parent.width
        height: guide.touchMode ? guide.fingerPx + dialogBox.u * 0.6 : dialogBox.u * 2.2
        KeyHints {
          id: boxKeys
          anchors.verticalCenter: parent.verticalCenter
          transformOrigin: Item.Left
          scale: boxKeys.touching ? 1 : Math.min(1, parent.width / Math.max(1, implicitWidth))
          model: guide.dialogHints
          size: dialogBox.u * 1.55
          capStyle: guide.look.keycap
          labelStyle: guide.look.keyLabel
          touchGuide: dialogBox.guide
          touchWidth: parent.width
        }
      }
    }
  }
}
