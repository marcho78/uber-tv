# Changelog

Everything notable that's changed, newest first. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[semantic versioning](https://semver.org/).

Until 1.0, minor versions (0.2, 0.3…) bring big new features and may change
how things work, including the app interface and the agent commands; patch
versions (0.2.1…) bring fixes and small additions. 1.0.0 will be the public release, once the plugin's name
and id are final (the rename to Uber TV) and the app interface is declared
stable.

## [Unreleased]

### Added

- **`playAt <id> <time>`** for agents: a library movie from a moment (seconds, `mm:ss` or `h:mm:ss`), to show a scene without skipping there.

### Fixed

- **Holding → (or a remote sending a burst of skips) no longer stalls the shell.** Every 10-second skip asked the player to seek at once; a few hundred in a row on a long HEVC movie stalled the shell until Omarchy restarted it. Skips now add up, the bar shows where they're going, and the player seeks at most every 0.3 seconds. Apps' videos too.
- **The guide no longer closes by itself when apps start working.** The helpers wrote compiled Python into the plugin's folder, which Omarchy watches, so the guide reloaded and closed. They no longer write it.
- **A channel list, library or history that couldn't be read is never saved over.** It was read as empty, and the next change saved that over the whole file. Now, like settings, it's kept as it is until it's fixed or moved away, Settings → Files says so, and an unreadable channel list shows the starter channels meanwhile.
- **The TV day starts at 4 AM on the days the clocks change too,** and the guide's grid starts on the hour or half past in time zones a quarter hour off (like Nepal).
- **Program listings:** a show with an impossible time is skipped instead of failing the whole source.
- **Apps:**
  - half a character (a lone surrogate) in an app's answer no longer leaves the call unanswered and the app stopped;
  - every secret an app may keep can be read back, and a secrets file that can't be read is never written over;
  - rows made ahead no longer pile up or keep a timer running;
  - a play that couldn't start because its app stopped says so.
- **Scores 1.2.1:** a game ESPN sends incomplete is left out instead of breaking the screen and stopping live updates.
- **Agents:** `watch` puts on the channel it asked for, even if channels moved or were removed just before.
- **`tests/appstate.test.py` runs on any clone:** it read old Scores versions from a commit that isn't in the repository's history; they're kept in the test now.

## [0.4.0-beta] - 2026-10-21

### Added

- **Recordings (DVR).** Off to start with: a strip on Home and the guide asks once (Y turns them on, N dismisses), and the switch is in Settings → Recordings.
  - **Record now:** Record on a channel's banner (I or Space while watching, ▲ on the phone) records to the show's end plus a couple of minutes (an hour without listings); a scheduled YouTube channel's video is saved whole. The banner says ● REC until when (only on the channel that's recording), and its choices stop it or change when it stops (up to 12 hours). In the guide, I or Space on a show that's recording offers Stop recording too.
  - **Later shows:** in the guide, I or Space on a show (⋯ on the phone) offers Record for a later show on an IPTV channel with listings, and Record every episode for its series. The guide's cells say Scheduled, ● Recording (in red) or Conflict; a channel that's recording has a red ● REC beside its name, and the top of the guide says what's recording.
  - Recordings run with Uber TV closed while you're logged in, keep the computer from sleeping, and a notification says when one starts and how it went. One that couldn't start on time (logged out, asleep, off) is Missed.
  - **How many at once:** 2 unless you choose 1 to 4. One too many is a Conflict that names the others, and the Record choice says so before you press it.
  - **Two streams from one provider:** going to another channel from a recording's playlist asks first (Watch anyway, or Stay), on the banner, in a box or in the mini player.
  - **The Recordings tab** in the library, and a Home row and nav rail item: what needs you, recording now, Upcoming, then recorded. Enter opens a recording's choices; Space plays it, or watches its channel live while it records.
  - **Settings → Recordings:** where they go (your Videos folder, a folder or a USB drive), the space kept free, YouTube's quality, how many at once, starting early and ending late.
- **Pause and rewind** (Settings → Recordings: off to start with, 5 or 30 minutes): a live channel plays through a rolling buffer on the recordings drive. The banner's choices start with Pause, Back 30 s, Forward 30 s and Live; J K L and the media keys work too. The banner says Live, or how far behind you are.
- **Phone remote:** it shows when the channel on is recording, and whether the TV is paused or behind live, answers the strip's question (TURN ON, DISMISS), and ⋯ while watching opens the banner's choices.
- **Agent commands:** `record`, `recordShow`, `recordSeries`, `recordUntil`, `stopRecording`, `cancelRecording`, `recordings`, `playRecording`, `startOver`, `removeRecording`, `shows` (find a show in the listings ahead), `recordingDrives`, `recordingSettings`, `setRecordingSettings`, `pauseLive`, `seekLive`, `goLive`, `libraryTabs` and `setLibraryTabs`; `state` reports Recordings and pause and rewind. Locked channels are refused. New theme parts for recordings and the Live chip.

### Changed

- **The movie player's bar** can be clicked or dragged to go to a point (the time follows the drag).
- YouTube's red circles (🔴) in video titles show as a · (or not at all at either end), so a red dot in the guide only ever means recording.
- My Videos leaves the recordings folder out.
- Program listings keep each show's episode title and number.
- Home is built only while it's on screen, so the picture no longer stutters while listings load.
- Sound follows the system's default output when you switch outputs. If the sound server itself restarts, restart the shell for sound.

### Fixed

- **The Keys box (?)** shows every line in full: long ones go on to a second line, and keys no longer run over their labels.
- **A theme's Multiview background is kept when the theme is saved.** `addTheme` stored it but also listed `multiview` as ignored, so a follow-up that dropped ignored keys removed it. By [@calledtoconstruct](https://github.com/calledtoconstruct) (#3).

## [0.3.0-beta] - 2026-10-19

### Added

- **Multiview:** up to four channels at once, live, scheduled or IPTV, the sound from the one you pick. From a channel's banner (I or Space while watching, then Multiview): it starts with that channel and the Add a channel list (type a number to jump to it). Side by side, featured (the first channel big), grid or a row; the arrows move the sound, Enter puts a tile full screen (with its own options), PgUp PgDn change a tile's channel, Del takes one off, L switches the layout, Esc exits to the channel with the sound. Each tile asks only for the quality its size needs (720p side by side, 480p in a grid, 1080p and 360p featured), and only the tile with the sound has audio.
- **The channel banner's options** (I or Space while watching): Multiview, Mini player, Guide and Mute.
- **Multiview's background** (the gear in its bar): as it is, a color, the theme's background, or a custom wallpaper (Omarchy's or a picture of your own). Its tiles' frames, labels and badge are parts in the style panel, and themes carry the background too.
- **Agent commands for Multiview:** `multiview "101,501,801"`, `multiviewAdd`, `multiviewRemove`, `multiviewLayout`, `multiviewSound`, `multiviewClose` and `multiviewBackground`; `state` reports Multiview. Locked channels are refused.
- Media keys, the phone remote, keep-awake, the screen saver and the channel lock all work with Multiview; turning the TV off, closing or playing something else stops every tile.

### Changed

- **The phone remote in full screen:** ▲ opens the banner's choices (◀ ▶ choose, OK picks, ▼ or BACK closes them), and ◀ ▶ change the channel; ▲ ▼ no longer change it (CH▲ CH▼ and the number pad still do). A full-screen Multiview tile works the same.

## [0.2.2-beta] - 2026-10-18

### Added

- **Update now** (Settings → About, when an update is out; the update mark on the nav rail goes to it): opens a terminal running Omarchy's own `omarchy plugin update`, which shows what changes and asks first; once it's updated, the shell restarts with the new version.

### Changed

- **Update notifications look every 6 hours** (and when the shell starts), not every 12.

## [0.2.1-beta] - 2026-10-18

### Added

- **Contributors** (Settings → About): everyone who's helped build Uber TV, and what they did. Enter on one opens their GitHub page.
- **Apps in a window:** with Uber TV in a window, website apps (Netflix, HBO Max and the like) open maximized under the Omarchy bar instead of full screen. The hint over an app adds Super + F (full screen), and leaving full screen puts it back maximized. Super + W still closes them and brings Uber TV back.

### Fixed

- **Program listings can't run away with memory or time.** Each show is let go of once read, so memory stays flat however big the file (a 400,000-show file: 46 MB, down from 80); a file stops at 4 GB unpacked; an `.xz` file can't make the reader reserve more than 128 MB (a few bytes could ask for 1.5 GB); and a fetch stops after 15 minutes, keeping the listings you had. Found by [@calledtoconstruct](https://github.com/calledtoconstruct).
- **The phone remote can't be paired from this computer.** A QR link opened here is refused, the same as a button press, and the link stays valid for the phone. A page on this computer can't use a paired phone's token either. By [@calledtoconstruct](https://github.com/calledtoconstruct) (#2).
- **Paired phones are saved under one lock,** so two pairing at once, or a phone dropping off while another is seen, can't lose one. The list is written to its own temporary file and renamed into place, and the pairing QR code is readable by you alone.

## [0.2.0-beta] - 2026-10-18

The first public release.

### Added

- **Save the agent skill** (Settings → General): a copy of the agent skill in your Downloads folder, as one Markdown file, to give to the AI assistant you use.
- **Demo channels:** a ready-made lineup of 163 YouTube channels in 30 categories (news, weather, space, nature, music, city, beach and ski cams, kids and family, and more). A first start offers it, and Settings → Live TV → Load the demo channels adds it any time. Channels you have are skipped and nothing is removed. Agents can load it too (`demoChannels`, `loadDemoChannels`).
- **A first start asks, one at a time:** load the demo channels, turn on apps, then the AI agent skill. Each is asked once; existing installs aren't asked.
- **Uber TV remembers your last channel,** after a restart too: Live TV opens on it with its preview, and if you closed Uber TV while watching a channel full screen, opening it plays that channel again (not a locked one: that waits for your passcode).
- **Settings → About says how to reach Developer mode:** a Developer mode line, always showing, says to press Enter on Uber TV 7 times (and, once it's there, where it is).

### Changed

- **Channel logos are on by default** for a new install or a Reset. Your own setting stays as it is.
- **Premiere is the default theme:** a new install or a Reset starts with it, and Reset to the original look gives it. A theme you've chosen stays on, and settings from before themes keep Retro.

### Fixed

- **Apps install again on btrfs.** Every install stopped with "it couldn't be made ready to put in place": on btrfs, a folder that was read once doesn't show files added after that until it's read again from the start, so a new app's folder still looked empty once its files were in. Folders are read from the start each time now.
- **An install or update that fails in a way that can pass** (a full disk, a file that didn't read back) says "Couldn't install" or "Couldn't update" with the app's name, and "Try again." The details go to the shell's log.
- **A link to a YouTube live stream adds its channel.** It was refused as a single video. When YouTube says the stream is live now, its channel goes in and plays that stream while it's live, and the channel's videos when it isn't; with several streams live at once, it plays the one you pasted. A channel that only streams goes in too: Live while it's on, NO SIGNAL when it's off. A regular video's link still says it's a single video.
- **L shows channel logos in every layout:** the channel table (Terminal) and the split-flap board now draw them, as the grid does. Before, L switched logos in those themes with nothing changing on screen.
- **Live channels' cards show a picture** (On now, Search): the live stream's own, refreshed about every 15 minutes, and the channel's logo until a card's picture has loaded, or when there's none. Before, a live channel's card had no picture.
- **Add channels says what can go in it, IPTV included:** YouTube, IPTV (M3U or M3U8 playlist links, or a stream's link) and files, each on a line of its own, with an M3U playlist among the examples. The file picker names playlists (.m3u, .m3u8) too. Before, neither mentioned IPTV.
- **What's live is known as soon as Uber TV opens:** if it hasn't been checked in the last 15 minutes, every channel is checked then. After a restart, live channels used to show as not live for up to 15 minutes, or until the guide had been open that long.
- **Live updates to an app's screen count their pictures again** (Scores updating a game, say). Since Qt 6.12 the updated rows arrived as something that isn't an array, so their pictures weren't counted against the 4,000-picture limit.

### Removed

- The design plans and build reports that were in `docs/`, and two performance benchmarks in `tests/`: they were for building Uber TV, not for using it.

### Documentation

- A new README: what Uber TV does, screenshots, install, update and uninstall (with what it leaves behind), getting started, and every key.
- The manual, the AI agents page and How it works brought up to date.

## [0.1.0-beta] - 2026-10-17

The first beta: everything built between October 10 and 17, 2026. Not
published yet.

### Its name

- **Uber TV is the app's name everywhere you see it:**
  - the window and the top bar;
  - Settings → About;
  - the guide's title and the phone remote's page;
  - the media player name in the bar, and the shortcut's name in Omarchy's keybindings;
  - messages, the docs, the SDK and the agent skill's text.
- **"The guide" or Live TV** is the name of its TV grid screen.
- **Internal names keep "om-pg" until the full rename before 1.0:** the plugin's id `marcho78.om-pg`, its `omarchy-shell om-pg` commands, its settings folder `~/.config/om-pg`, and the agent skill's folder `program-guide`.

### The guide and live TV

- **A full-screen program grid of YouTube channels.** Each channel loops its videos on a daily schedule, so tuning in joins whatever is "on now", partway through, like broadcast TV.
  - Video plays inside the shell: in a preview box, full screen, or a mini player that stays on top while you work.
- **Adding channels:**
  - by link, `@handle`, name, pasted list, or file (CSV, a lineup, a Google Takeout subscriptions export);
  - a built-in file picker that can also browse a folder at a time.
- **Categories:**
  - cable-style numbering (each category its own hundred);
  - a filter for the categories and sources shown;
  - live channels.
- **Manage mode:** mark, move, rename, recategorize and remove channels.
- **Channel logos** (optional, cached and throttled), and a channel card with the logo, number and name when you change channel.
- **Saved listings and daily lineups.** Keycap key hints in the footer, and a full key list on **?**.

### IPTV and program listings

- **M3U/M3U8 playlists** (pasted, linked, GitHub file pages included, or opened from a file) add live channels that play their streams directly.
  - streams at the best size up to 1080p, with one retry when a stream drops;
  - `group-title` becomes the category and `tvg-logo` the logo;
  - YouTube links in a playlist become YouTube channels;
  - sources in the filter: YouTube and IPTV, YouTube only, IPTV only.
- **Program listings (XMLTV) for IPTV channels:**
  - matched by `tvg-id`, then by name within a country;
  - a playlist's `url-tvg` is picked up when it's added.

### Media keys and the phone remote

- **Media keys:** while the TV is on, the guide is a media player on the session bus. Next and Previous change channel, Play/Pause pauses, and the bar's media widget shows the channel, show and logo.
- **The phone remote (T), off until you turn it on.** It's a remote control page for phones on your local network: a d-pad, a channel rocker, a number pad and a guide tab, in portrait and landscape.
  - turning it on first shows what it opens and asks;
  - when the firewall is on, the one rule it needs is added through the system's password prompt, and offered for removal when you turn the remote off;
  - phones pair with a short-lived, single-use code or QR code;
  - pairing and unpairing from Settings.

### Home, the library and the TV-style shell

- **Home:** the first screen, arranged by you. Sections, tiles, rows (a genre, a YouTube channel's videos, what's on in a category, a folder, recent searches), the top of the screen, the clock and its background.
- **The library (V):**
  - movies and series from your playlists, with details;
  - On Demand: every video of your YouTube channels;
  - My List, watch history, and resume.
- **On demand playback:** from the start, with pause, seeking and resume.
- **My Videos:** a folder of your own videos, scanned with thumbnails.
- **Search (/):** across channels, shows, movies, videos and My Videos, with recent searches.
- **The nav rail:** down the left of every screen; what's on it, and its order, are yours.
- **Settings:** a TV-style screen in parts (General, Live TV, Library, Apps, About), with big rows and switches.
- **Display mode:** full screen, or a maximized window under the Omarchy bar.

### Style and themes

- **A style engine:** every part of the guide (program cells, the time bar, category bands, the info panel, the channel banner, boxes, keycaps, menus) styled by its colors, shapes, shadows, sizes, spacing and fonts.
- **Layouts:** the time grid, a terminal-style channel table, a split-flap departures board, and where the clock and preview go.
- **Seven built-in themes:** Retro, Aperture, Nightshift, OLED, Premiere, Split-Flap and Terminal. Your own themes, kept as files.
- **The style panel (S):**
  - colors (the theme's, with your own picks on top);
  - pictures in the guide's areas and behind it;
  - the banner and card settings;
  - every part, the layout and the fonts.
- **Save the look on screen as a theme,** reset to the original or to the theme, and undo the reset.

### Opening the guide

- **A TV in the top bar** opens and closes the guide, so a standard install works with no setup. It can be hidden in Settings.
- **Super + Alt + T** opens and closes it from anywhere. It's registered with Hyprland while the guide runs, again after config reloads, and taken out when the guide is turned off. The Hyprland config is never edited, and a key another binding uses is left alone.
- **Window or full screen, and Turn off,** at the foot of the nav rail.
- **A splash screen as Uber TV turns on:** an old TV warming up, then the Uber TV logo, about 9 seconds (any key, click or phone press skips it). Coming back while it's on doesn't show it; Settings → General → Splash screen turns it off. Its fonts, Orbitron and DM Mono, come with Uber TV under the SIL Open Font License (`fonts/`).
- **Credits at the foot of the nav rail,** while it's open: X's logo and @devsec_ai, then the website devsecai.sh, each a link, and Disable, which goes to their switch (Settings → About → Credits on the nav rail).
- **One click does it in Settings and the theme panel:** the row acts at once, the cursor lands on it, and the list stays where it is under the pointer. A double-click acts once; rows that clear something still ask twice.
- **A channel lock, like a TV's parental lock** (Settings → Live TV → Channel lock): a passcode you set once (4 to 8 digits), and the channels it protects. Watching one asks for it, on the screen or by typing it on the phone remote; until it's unlocked, it shows a lock, its shows say Locked everywhere (titles optional), its videos are left out of On Demand, Search and Home (even when they're on another channel too, or the channel is renamed or removed), and channel up and down skip it; **L** locks or unlocks channels where you manage them. An unlock lasts until the TV is turned off (or 1 or 4 hours, and a channel playing stops when it runs out). The passcode is kept only as a salted scrypt hash in a file only you can read, checked by the helper; wrong tries slow down. Forgot it? A reset asks for the computer's password. Until the lock has been read, no channel plays. Agents see that a channel is locked and can't watch, lock or unlock one.
- **A screen saver, like a TV's** (Settings → Screen saver, off until you turn it on): after a few minutes with nothing playing and no key, mouse or phone press, Omarchy's backgrounds and the pictures in your `~/Pictures/Screen Saver` folder fill every screen, crossfading with a slow pan and zoom, with the clock. Any press brings you straight back, with no password: while it's on, Uber TV keeps the computer from locking while it's on screen. Every picture from your folder is checked before it's shown. Agents can change how it looks and when it starts, but not turn it on or choose the folder.
- **A press on the phone remote counts as you being there:** Omarchy's screen saver and lock don't come while you're using the phone.
- **Keep the screen awake** (Settings → General): while a video plays (the default), while Uber TV is on screen, or off. Omarchy's screen saver and lock wait meanwhile, held off the way video players do it, and Omarchy's own settings aren't changed.
- **Playing full screen:** moving the mouse shows the banner or player bar, and an idle pointer hides. Nothing stays over the picture.

### Apps

- **Apps, off until you turn them on, each with its own switch:**
  - from the Uber TV catalog: signed, and checked against `apps/catalog-signers`;
  - or, in Developer mode, an unsigned app from a file.
- **Before anything is installed,** you see who made it and what it asks for. The package's SHA-256 and the catalog's signature are checked, it's unpacked safely, and its `app.json` is validated.
- **Launchers** open a website in the browser's app window, full screen, and the guide makes way until it's closed.
- **The catalog keeps an offline spare key,** so a lost key needs no guide update. Apps signed by a key taken out of trust are installed again from the trusted catalog.

### Apps with code (Code apps v1)

- **Python apps run in a sandbox** (bubblewrap, in a systemd user scope of their own), with no network of their own and limits on memory, CPU and tasks.
  - the guide fetches for them, only from the sites you approved and your own server;
  - every request is checked against private addresses, redirects and certificates.
- **The app screen:** the guide draws everything, from blocks the app sends: screens, rows, details pages, buttons and its settings page.
- **Playback** of direct media and HLS streams, through a local relay that checks every stream's structure and fails closed.
- **Signing in** with a code, a server setting with a base path, certificate pinning, and sign-out done in order.
- **Jellyfin,** bundled: your movies and series from your Jellyfin server. **Scores,** bundled.
- **Home rows from apps.**
- **The SDK and tools for writing apps:** `om-pg-apps check`, `try` (offline by default) and `pack`.

### Code apps v2

- **API 4: apps can change things on sites they name.** `netWrite` in `app.json` lists, for each of its sites, the methods it may use there (POST, PUT, PATCH, DELETE).
  - the helper allows exactly those, nothing else changes for the site;
  - an update adding a site or a method waits for you.
- **Redirects, tightened for every app:**
  - a 301, 302 or 303 becomes a GET without its body;
  - a write is never carried to another site (that redirect is the app's answer);
  - every header an app set is dropped when the site changes, not only `Authorization`.
- **The consent screen, laid out for the couch:**
  - who made it and where it's from, then one line on what it can do;
  - a row for each kind of thing with its icon, changing things first;
  - long lists and Can't fold, Enter opens them;
  - an update shows only what's new;
  - the cursor starts on Cancel for anyone else's app, a replace, or an update adding a way to change things.
- **Activity in an app's details:** the sites it contacted in the last 90 days, and the ones it was refused, kept as daily totals per site, never addresses. The first refusal while it's on screen says so, once a session.
- **The showcase example is API 4**, and the toolkit, `PROTOCOL.md` and the agent skill cover `netWrite`.
- **Signing in with your username and password** (API 4), in the guide's own box: keyboard only, the password as dots, handed to the app once and kept by nothing; kept out of the app's log for its whole run. After 5 wrong passwords in a row, 30 seconds' wait. **Jellyfin** offers it for servers with Quick Connect off (Jellyfin 1.2.0).
- **Choosing your server while signing in** (API 4, `server.fromSignIn`), for accounts that list your servers: the server first, then one of its addresses or one you type for it; only that server's key kept, and the server kept with the sign-in in one write; another server asks "Switch?" first. A new example app, `apps/sdk/examples/accounts`, does it offline.
- **Richer screens** (API 4): a table row (standings, schedules), a ticker row (moving across, still while selected, the screen saver is up or a video plays), a chart on an item or a details page, and an article page the arrows scroll; styled through new APPS parts (Table, Ticker, Chart, Page), drawn the same in all five looks. The showcase has each.
- **Live screens** (API 4): a screen that says live updates its rows while it's shown (a game's score), and Home rows the same while Home is (every 5 seconds at most); an app can also follow a stream of lines from one of its sites. Pictures are held per row, so a row replaced every second never piles them up. **Scores 1.2.0 is live**.
- **Third-party apps** (Settings → Apps, off): install apps other developers
  sign and give out as a `.tvapp` file you downloaded yourself. Uber TV never
  fetches apps from a link.
  - turning it on asks for the computer's password; **Install a third-party
    app** picks a `.tvapp` from your home folder;
  - the review shows who signed it and everything it asks for; Install asks
    for the password and contacts nothing;
  - the same app signed by another developer installs as a new app with none
    of the old one's data, and the review says so;
  - while it's on, only each app's small signed update note is checked, about
    twice a day. **Update available** shows exactly what will be fetched
    (address, version, size, key, new asks highlighted), and nothing is
    downloaded until you agree;
  - a version its developer withdraws turns off and says why; turning
    Third-party apps off stops those apps and every check.
- **Publishing an app file:** `om-pg-apps app-key`, `app-file` and
  `app-revoke` keep one locked publisher workspace, make signed `.tvapp`
  releases in new exclusive folders and carry withdrawals forward. Nothing
  is uploaded for the developer (docs/sources.md).
- **Where an app is from is a small icon, not NOT CHECKED:** a page for an
  app installed from a file and none for Uber TV's own, on its tile, Home
  card and rows, and band; always solid, its icon picked to read. The signed
  developer and key are in its details and review.
- **Developer mode is for testing apps you're building,** unsigned, with no
  updates. It has its own **Developer** part in Settings, shown after you
  press OK 7 times on the version in Settings → About, and gone again once
  Developer mode is switched off. **Install an unsigned app** is there.
  Turning it on asks for the computer's password.
- **Check for updates** with an update waiting opens that app's details,
  where its Update is.

### How app screens look (App screens v2)

- **Fixes:**
  - details pages show their poster and backdrop;
  - cards show whole pictures in the right shape;
  - list rows;
  - big grids stay fast;
  - the selection ring reads on any theme.
- **Layouts and picture shapes (API 3):**
  - rows of posters, wide pictures, squares, logos and round cast photos;
  - grids, lists, and a featured (hero) row;
  - two details-page styles, Classic and Cinematic;
  - an app can describe its own layout in `app.json`.
- **Five looks:** Classic, Posters, Cinematic, Wall and Compact. They set card shapes, sizes, titles, the top panel and the background (a blurred backdrop of what's selected, among others), plus the app's name band at the top.
- **Customizing:**
  - **C** on an app's screen opens Customize: the look rows, a picture of your own, how dark, and each row (show, rename, pictures, size, layout, order);
  - Settings → Apps → How apps look does the same for every app;
  - themes carry these choices, and the resets and undo cover them.
- **For app writers:**
  - an offline example app that uses every block (`apps/sdk/examples/showcase`);
  - `try` prints each row and card as the guide will draw them in the look the app suggests.

### Updates, backups and reset

- **Update notifications,** off until you turn them on (Settings → About, or the strip at the bottom of Home and the guide the first time): Uber TV asks the git address it was installed from for a newer version tag when the shell starts and every 12 hours, and says so on the nav rail and in Settings → About. **Check for updates** looks now, on or off; **Release notes** shows what's new in the update, or what's in your version. Updating stays `omarchy plugin update marcho78.om-pg`.
- **Back up channels and settings** (Settings → About): your channels, settings, My List, Continue watching, themes and program listings, in one file in `~/Documents/Uber TV backups` readable only by you. Paired phones, the channel lock and app sign-ins are never in it. **Restore a backup** asks first, checks the file, and puts back what it swapped if a step fails; the phone remote stays as it is.
- **Reset Uber TV** (Settings → Developer): back to how it was when first installed, channels, settings, apps and every consent included. It asks first, asks for the computer's password when a channel lock or the phone remote's firewall rule needs it, and saves a backup before anything goes.

### AI agents

- **An agent skill, off until you turn it on:** a link to the plugin's `skills/program-guide` in each agent skill folder. The first time the guide opens, it asks. Until you answer, the masthead says so.
- **Commands for agents** (`omarchy-shell om-pg …`): themes and style, Home, the nav rail, channels and categories, the library and playback, listings, apps (list, turn off), and how app screens look (`appScreen`, `setAppScreen`, `resetAppScreen`, `openApp`, `appSnapshot`).
- **Snapshots,** so an agent can look at what it made. They're refused while anything sensitive is on screen (the phone remote's code, an app's sign-in or settings, a text field).

### Security

- **Only you can do what matters:** installing, turning on and removing apps, Developer mode, signing in, secrets, the phone remote and the firewall. Agents and scripts can't.
- **Consent boxes** move only on your keys, mouse or paired phone, and take a yes only when they're on screen.
- **Private files:** the guide's own (settings, your choices for app screens, themes) are read with a size limit, written whole, checked and then swapped in, and readable only by you. So are the channel list (IPTV links can carry logins), apps' secrets, and pictures you pick.
- **Pictures you pick** are checked (a real PNG, JPEG or WebP, of sane size) and copied. Only the copy is ever shown.
- **Themes are saved as one confirmed transaction.** Their clean-up only ever deletes files the guide wrote.
- **Apps:**
  - a version the catalog pulls is never offered or installed;
  - installs re-check the catalog's signature and install exactly the reviewed files;
  - at every start, each app is traced back to its proof;
  - an app from the catalog or a signed app file is never installed without its proof, and an install that stops partway (an error, a full disk, Ctrl-C) puts back what was there and checks it, saying if anything may be left to look at.

### Fixed

- **Omarchy locks again while Uber TV is open full screen.** Omarchy's screen saver opened under Uber TV without focus and quit at once, and Omarchy took that as you dismissing it: it called off the lock and didn't arm it again until you touched something. Now Uber TV steps aside when Omarchy's screen saver opens (its layer hidden, the keyboard let go, the saver window focused), and comes back when you close it with a key.
- A movie or channel no longer gets Omarchy's screen saver after a couple of minutes and the lock after five: a playing video keeps the screen awake.
- Single-file fMP4 HLS streams (as FFmpeg writes them) are played: segments may start with their index box.
- Removing an app removes its empty folders too.
- Settings are saved only once they've been read, and never over a file that couldn't be.

### Documentation

- A short README, with the full manual, apps, AI agents, security and how-it-works pages in `docs/`.
- The designs and reports for code apps and app screens, in `docs/`.
- This changelog, CONTRIBUTING, SECURITY and the MIT license.
