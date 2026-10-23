---
name: program-guide
description: >
  Customize Uber TV (the Program Guide), the TV and media center for YouTube
  channels and IPTV in the Omarchy shell. Make and put on themes of any style: colors, fonts,
  shapes (rounded, pill, slanted, arrow, your own SVG outline), shadows, sizes and
  spacing for every part (program cells, the time bar, category bands, the info
  panel, the channel banner or lower third, the channel-change card, boxes,
  keycaps), and layouts (the time grid, a terminal-style channel table, a
  split-flap departures board, where the clock and preview go). Follow the
  user's Omarchy theme colors, put pictures in its areas, take a snapshot to
  see the result, save the look on screen as a theme, reset it to the original
  or to its theme (and undo that). Customize its Home screen (which sections
  and tiles show, in what order, rows of a genre or a channel, its background
  picture), arrange its nav rail (which parts show, in what order), see its
  apps and turn one off, change how apps' screens look (Jellyfin, Scores: a
  look, posters or wide pictures, rows hidden or reordered, and a snapshot of
  the result), write apps for it (websites, or Python apps it runs
  in a sandbox: check, try and pack them for the user to install),
  find and play movies, series, YouTube videos and the user's own videos (My
  Videos) on demand, add
  M3U/M3U8 IPTV playlists (their movies go to the library), YouTube channels or
  channel lists, sort channels into categories, rename or remove channels,
  choose what the guide shows, and open it on a channel. Record channels and
  shows (DVR): what's on now, later shows and every episode of a series; pause
  and rewind live TV. Triggers: program guide, TV guide, EPG, om-pg, IPTV, m3u,
  m3u8, playlist, VOD, movies, record, recording, DVR, "record channel",
  "record every episode", "pause the TV", "rewind", "make a
  theme for the guide", "make the guide look like…", "round the cells", "change
  the guide's font", "change the guide's colors", "use this picture for the
  lower third", "put this picture behind Home", "add a row to Home", "save this
  as a theme", "put the guide back to how it was", "make Jellyfin look like
  Netflix", "posters for my movies", "add this playlist", "play that movie",
  "put on channel".
---

# Uber TV

Uber TV runs inside the Omarchy shell. Work with it only through
`omarchy-shell om-pg <command>`. The guide checks what you give it, saves it and
shows it at once. Don't edit its files (`~/.config/om-pg/`) or its code.

Every command prints JSON: `{"ok": true, ...}`, or `{"ok": false, "error": "..."}`
saying what was wrong. Commands take a fixed number of arguments, so pass `""`
for one you leave as it is. `omarchy-shell is not running` means the Omarchy
shell is off: ask the user to start it. `Target not found.` means the guide
isn't loaded: the shell is still starting (wait a few seconds and try again),
or the Uber TV plugin isn't installed or is turned off.

| Command | What it does |
|---|---|
| `omarchy-shell om-pg help` | these commands |
| `omarchy-shell om-pg state` | the guide at a glance: open or not, the channel on, how many channels, the theme, what's shown, settings, `recordings` (`{on, recording, scheduled, series}`: on or not, how many recording now, how many waiting (Scheduled or Conflict), how many series), `pauseAndRewind` (`{on, running, paused, behindSeconds}`), and `multiview` (its channels in order, which has the sound, the layout) while it's on |
| `omarchy-shell om-pg open` | opens the guide (full screen, over everything), on Home when Home is on |
| `omarchy-shell om-pg display <full\|window\|"">` | how the guide shows: `full` (over everything, the Omarchy bar too) or `window` (an ordinary window, maximized under the bar, on its own desktop); `""` says which |
| `omarchy-shell om-pg close` | closes it, and turns the TV off |
| `omarchy-shell om-pg watch <number>` | a channel full screen |
| `omarchy-shell om-pg multiview "<numbers>"` | Multiview: up to 4 channels at once (`"101,501,801"`), the first with the sound (see Multiview) |
| `omarchy-shell om-pg multiviewAdd <number>` | adds a channel to Multiview (up to 4) |
| `omarchy-shell om-pg multiviewRemove <number>` | takes one off; with one left, Multiview closes and that one plays full screen |
| `omarchy-shell om-pg multiviewLayout <side\|featured\|grid\|row>` | Multiview's layout, one for how many channels it has |
| `omarchy-shell om-pg multiviewSound <number>` | which of Multiview's channels has the sound |
| `omarchy-shell om-pg multiviewClose` | closes Multiview: the channel with the sound plays full screen |
| `omarchy-shell om-pg record <number> "<length>"` | records a channel from now (see Recordings): `""` to its show's end plus the end-late minutes with listings (an hour without), or minutes (`90`) or hours (`2h`), 12 hours at most; a scheduled YouTube channel's show is its video, saved whole. Not a locked channel. As many at once as Settings → Recordings allows (2 unless the user chose otherwise) |
| `omarchy-shell om-pg recordShow <number> <HH:MM\|"YYYY-MM-DD HH:MM"\|next>` | records a later show (an IPTV channel with listings; 5 minutes or longer): the one on at that time today (tomorrow, if it's gone by), on that day at that time (`shows` gives each one's `when`), at a show's `start` (seconds, from `shows`: use it for the hour that repeats when the clocks go back), or the next one. Scheduled, or a Conflict when it'd be one too many (Recordings at once; `recordings` names the others). Not a locked channel |
| `omarchy-shell om-pg recordSeries <number> <HH:MM\|"YYYY-MM-DD HH:MM"\|now\|next>` | Record every episode of the show on at that time (or on that day at that time): this one too if it's on, then each episode the listings have (about a day and a half ahead, fetched twice a day), never one recorded already. Not a locked channel |
| `omarchy-shell om-pg cancelRecording <id>` | cancels a scheduled recording (an episode of a series isn't scheduled again), or a series by its id (its rule and its shows not started; what it recorded stays). Only when the user asks |
| `omarchy-shell om-pg recordUntil <id> <minutes\|HH:MM>` | a new stop time for a recording: minutes from now, or a clock time, within 12 hours of its start |
| `omarchy-shell om-pg stopRecording <id>` | stops a recording; what's recorded is kept |
| `omarchy-shell om-pg recordings` | the recordings (the first 300): `{id, state, kind, locked, title, channel, started, until, show, records, series, seconds, bytes, why, file}` (state Scheduled, Conflict, Starting, Recording, Saving (a YouTube video), Done, Missed, Incomplete, Failed or Drive missing), the series (`{id, title, channel}`), plus the settings. A locked channel's say only `Locked recording` |
| `omarchy-shell om-pg playRecording <id>` | plays a recording full screen, from where the user stopped (not a locked channel's) |
| `omarchy-shell om-pg startOver <id>` | plays a recording, a library item or one of the user's videos full screen from the start (`playRecording` and `play` resume); not a locked channel's |
| `omarchy-shell om-pg removeRecording <id>` | deletes a recording: its file, details and picture (one on an unplugged drive comes off the list, its file stays). Only when the user asks |
| `omarchy-shell om-pg recordingDrives` | the USB drives plugged in, mounted or not |
| `omarchy-shell om-pg recordingSettings` | Settings → Recordings: on, where recordings go (and its free space), space kept free (`keepFree`, and `keepFreeNow` in GB), YouTube quality (`quality`, and `qualityNow`), padding, how many at once (`atOnce`), pause and rewind (`pauseAndRewind`: minutes kept, 0 off), and the USB drives (`drives`) |
| `omarchy-shell om-pg setRecordingSettings '<json>'` | changes them: `{"on", "place": "videos" \| "/a/folder" \| "drive:<device>", "keepFree": "auto" \| 2 \| 5 \| 8 \| 10 \| 20, "quality": "auto" \| 1080 \| 720 \| 480, "padding": 0 \| 1 \| 2, "atOnce": 1 \| 2 \| 3 \| 4, "pauseAndRewind": 0 \| 5 \| 30}` (`on` only when the user asks; atOnce only when the user asks: each is another stream and ~3 GB an hour; pauseAndRewind only when the user asks: it writes to the recordings drive the whole time they watch); off while one records or is scheduled needs `"stopAndCancel": true`, once the user says so |
| `omarchy-shell om-pg pauseLive` | pauses the live channel on the TV, or resumes it (pause and rewind on, its buffer ready): `{paused, live, behindSeconds}` |
| `omarchy-shell om-pg seekLive <seconds>` | back (negative) or forward by that many seconds, as far as pause and rewind's buffer goes; past live is live |
| `omarchy-shell om-pg goLive` | back to live |
| `omarchy-shell om-pg libraryTabs` | the library's tabs in order, and which show |
| `omarchy-shell om-pg setLibraryTabs "<keys>"` | their order, with commas (`movies`, `ondemand`, `videos`, `recordings`, `mylist`); the rest follow in theirs |
| `omarchy-shell om-pg home` | Home: its sections in order (on or off), its tiles, its background, and the rows that can be added |
| `omarchy-shell om-pg setHome '<json>'` | changes Home: `{"sections": [...], "tiles": [...], "background": {...}, "on": true}`, any part left out stays (see Home) |
| `omarchy-shell om-pg rail` | the nav rail: when it shows (`always`, `focus`, `none`) and its items in order, each on or off, and whether each one's part is turned on |
| `omarchy-shell om-pg setRail "<items>" <always\|focus\|none>` | the rail's items in order, with commas (`search`, `home`, `tv`, `movies`, `ondemand`, `videos`, `recordings`, `mylist`, `apps`, `settings`): the ones named are on, the rest off (`settings` always stays). `""` keeps either |
| `omarchy-shell om-pg listings` | program listings (XMLTV) for IPTV channels: the sources, how many channels each matched, errors, when fetched, and how many IPTV channels have listings |
| `omarchy-shell om-pg addListings "<link or path>"` | adds a source of program listings: a link to an XMLTV file (`.xml`, `.xml.gz`, `.xml.xz`) or a full path to one. Fetched at once; run `listings` a minute later |
| `omarchy-shell om-pg removeListings "<link or path>"` | takes a source of listings off. Only when the user asks |
| `omarchy-shell om-pg search "<words>"` | what matches, as the guide's Search shows it: `channels` (with `watch` numbers), `onNow`, `laterToday`, `movies` (series with their episodes' ids), `videos`, `myVideos` (with `play` ids). Channels and shows follow what the guide shows |
| `omarchy-shell om-pg shows <number> "<words>"` | the shows ahead in the listings (IPTV channels with listings, about a day and a half): a channel's (`""` for every channel), the ones whose title or episode has the words (`""` for all); the first 100, soonest first: `{total, more, shows: [{number, channel, title, episode, episodeNumber, start, end, when, onNow, recording}]}` (`recording`: recording, scheduled or conflict). Not a locked channel's |
| `omarchy-shell om-pg library "<words>"` | movies and series in the library matching the words (`""`: the first 100), with their ids, genres, and where the user stopped |
| `omarchy-shell om-pg videos "<words>"` | My Videos: on or not, its folder, and the user's videos in it matching the words (`""`: the newest 100), with their ids, folders and lengths |
| `omarchy-shell om-pg setVideos <on\|off> "<folder>"` | My Videos on or off, and the folder it shows (a full path). `""` keeps either |
| `omarchy-shell om-pg screenSaver` | the screen saver: on or not, showing now, the minutes before it starts, the pictures, how often they change, the clock, and the user's folder with how many pictures it has |
| `omarchy-shell om-pg setScreenSaver '<json>'` | changes the screen saver: `{"after": 10, "pictures": "both", "every": 20, "clock": "middle"}` (after 1, 2, 5, 10, 15 or 30 minutes; pictures `both`, `omarchy` or `folder`; every 10, 20, 30 or 60 seconds; clock `bottomRight`, `bottomLeft`, `topRight`, `topLeft`, `middle` or `off`). Turning it on (it keeps the computer from locking while Uber TV is on screen) and choosing its folder stay the user's |
| `omarchy-shell om-pg play <id>` | plays a library item or one of the user's videos (its id from `library` or `videos`), or a YouTube video (`yt:<video id>`), full screen from where the user stopped |
| `omarchy-shell om-pg playAt <id> <time>` | the same, from a moment: seconds, `mm:ss` or `h:mm:ss` (a scene to show). Never skip there with hundreds of key presses |
| `omarchy-shell om-pg snapshot ""` | a PNG of the guide as it is on screen: the guide must be open, with no sensitive screen up (the phone remote's box, an app's sign-in or settings, a certificate to pin, a text field). Answers its file's `path`; read it once `state`'s `snapshot` has that name and says `written` (see Looking at your work) |
| `omarchy-shell om-pg themes` | the themes: `[{id, name, description, builtIn, current, …}]` |
| `omarchy-shell om-pg theme <id>` | puts a theme on |
| `omarchy-shell om-pg addTheme "<json>"` | saves a theme (the JSON itself, not a path) and puts it on once it's saved; the same name again replaces it. Answers a `saving` token (see Saving a look as a theme) |
| `omarchy-shell om-pg saveTheme "<name>" "<description>"` | saves the look on screen as a theme: the theme on with the user's own colors, styles, fonts, layout and pictures over it, the banner and card, and how every app's screen looks. The name of the theme that's on saves the changes into it; another taken name is refused (`""` description: kept, or made). Put on once it's saved; answers a `saving` token |
| `omarchy-shell om-pg removeTheme <id>` | deletes one of the user's themes (`state`'s `saving` says when it's gone). Only when the user asks |
| `omarchy-shell om-pg elements ""` | every part of the guide you can style, the property formats, the layout settings and fonts on now |
| `omarchy-shell om-pg elements <name>` | one part: what it is, what it takes, its states, and Retro's, the theme's, the user's and the style now |
| `omarchy-shell om-pg setStyle <element> '<json>'` | styles one part (or `part:state`) over the theme, as the user's: `setStyle programCell '{"radius": 0.4}'`; `null` takes one property off, `theme` (instead of JSON) takes all of it off |
| `omarchy-shell om-pg setStyle fonts '<json>'` | fonts by role: `{"body": "Adwaita Sans"}` (`null` or `theme` takes one off) |
| `omarchy-shell om-pg setStyle layout '<json>'` | layout settings: `{"masthead": "none", "upNext": 2}` (`null` takes one off, `theme` all) |
| `omarchy-shell om-pg fonts "<words>"` | installed font families matching the words (`""`: all), and the fonts on now |
| `omarchy-shell om-pg slots` | every color slot: `[{key, section, label, theme, yours, now}]` |
| `omarchy-shell om-pg style` | the theme on, and the user's own colors, pictures, styles, fonts and layout over it, the banner and card settings |
| `omarchy-shell om-pg setColor <key> <#hex>` | one slot's color, over the theme (`""` goes back to the theme's) |
| `omarchy-shell om-pg resetColors` | takes the user's own colors off, back to the theme's. Only when the user asks, or agrees |
| `omarchy-shell om-pg reset theme` | all the user's own changes off (colors, pictures, styles, fonts, layout, and their choices for every app's screen); the theme's picture, banner and card settings back. The theme stays on |
| `omarchy-shell om-pg reset original` | back to the guide's original look: Premiere, with no changes (every app's screen as the theme has it too). Themes stay saved; channels and settings aren't touched |
| `omarchy-shell om-pg reset undo` | the look from before the last reset, all of it (the choices for every app's screen too) |
| `omarchy-shell om-pg images` | every picture area, and the picture in it: `[{area, name, picture, fit, opacity, from}]` (`from`: `yours`, `theme`, or `""` for none) |
| `omarchy-shell om-pg setImage <area> <picture> <fit> <opacity>` | an area's picture: a picture's full path, `none`, `theme` (back to the theme's) or `""` (keep it); fit and opacity as below (`""` keeps either) |
| `omarchy-shell om-pg background <none\|wallpaper\|/path/picture.jpg> <dim>` | the picture behind the guide: none, the user's Omarchy wallpaper, or a picture's full path; dim `0` to `0.95` darkens it (`""` keeps either) |
| `omarchy-shell om-pg multiviewBackground <none\|#rrggbb\|theme\|wallpaper\|/path/picture.jpg> <dim>` | what's behind Multiview's tiles: `none` as it is (the theme's colors), a color (`#rrggbb`), `theme` the theme's background, the Omarchy wallpaper, or a picture's full path (checked and copied first); dim `0` to `0.95` darkens a picture (`""` keeps either). The user picks the same four in Multiview's gear; how dark a picture is, and the tiles' look (the Multiview parts below), are yours to set when asked |
| `omarchy-shell om-pg lowerThird <on\|off> <seconds>` | the channel banner in full screen, and how long it stays (1 to 15) |
| `omarchy-shell om-pg card <on\|off> <seconds>` | the card shown when changing channel, and how long it stays once the picture is on (0.6 to 5) |
| `omarchy-shell om-pg channels "<words>"` | channels whose name, category or number has all the words (`""`: the first 100): `{total, channels: [{number, name, kind, category, live, shown}], more}` |
| `omarchy-shell om-pg categories` | each category with how many channels (and IPTV ones), and whether it's shown |
| `omarchy-shell om-pg addChannels "<text>"` | adds an M3U/M3U8 playlist (its URL, or a file's full path), a channel list file, or YouTube links, `@handles` and channel names, one a line |
| `omarchy-shell om-pg status` | how the last `addChannels` is going: `{busy, checking, done, message, failed}` |
| `omarchy-shell om-pg demoChannels` | the demo lineup that comes with Uber TV: how many channels, its categories, and how many aren't in the guide yet |
| `omarchy-shell om-pg loadDemoChannels` | adds the demo lineup's channels the guide doesn't have, in their categories; nothing is removed. Only when the user asks, or agrees |
| `omarchy-shell om-pg show <both\|youtube\|iptv> "<categories>"` | what the guide shows: a source (`""` keeps it) and categories with commas (`""`: all, `-` keeps them) |
| `omarchy-shell om-pg rename <number> "<name>"` | renames a channel |
| `omarchy-shell om-pg setCategory <numbers> "<category>"` | files channels under a category, new or not (`""` for none); numbers like `101`, `101,105` or `101-110` |
| `omarchy-shell om-pg removeChannels <numbers>` | removes channels. Only when the user asks, and check the numbers with `channels` first |
| `omarchy-shell om-pg logos <on\|off>` | channel logos in the guide |
| `omarchy-shell om-pg keyHints <on\|off>` | the keys along the bottom |
| `omarchy-shell om-pg refresh` | fetches the listings again |
| `omarchy-shell om-pg apps` | apps: on or not, Developer mode, Third-party apps, the catalog, and the installed apps (id, name, version, on or off, on the screen now, where from, developer key for a signed app file, whether it's been checked, what each is allowed to do, any problem, an update waiting) |
| `omarchy-shell om-pg appOff <id>` | turns one installed app off; it stays installed |
| `omarchy-shell om-pg appScreen <app id\|all>` | how an app's screen looks and what's on it, by handle (see App screens): its choices and what they give, its rows in screen order, and while it's on the screen its items; also `onScreen`, `state`, `picturesPending`, `covered` and `view`. `all`: the choices for every app's screen |
| `omarchy-shell om-pg setAppScreen <app id\|all> '<json>'` | changes the user's choices for an app's screen, or every app's (`all`): `look`, `top`, `background`, `details`, `titles`, `size` (`null` takes one off), and for one app `rows` by handle and `order` (a list of handles). Answers what it will save, what it `ignored` and why, and a `saving` token |
| `omarchy-shell om-pg resetAppScreen <app id\|all>` | an app's screen follows the choices for every app again (`all`: the theme's). Only when the user asks |
| `omarchy-shell om-pg openApp <app id> "<handle or empty>"` | opens an app that comes with the guide at its first screen, or (with a live item handle from `appScreen`) at that item. Answers the `view` it asked for |
| `omarchy-shell om-pg appSnapshot <view>` | a PNG of an app's screen, only while that view is on the screen with nothing of the guide's over it. Answers its file's `name`; `state`'s `snapshot` says when it's written |

There's no command for the phone remote or the firewall, to keep the screen
awake (it can keep the computer from locking), for the channel lock (setting
its passcode, locking, unlocking or watching a locked channel: `watch` and
`play` refuse a locked channel and its videos, `channels` says `locked`, and
`search` shows a locked channel's shows as Locked and leaves out its videos), or to turn apps on, turn an app
on, or install, update or remove one: those stay the user's. Don't work
around that: not through `omarchy-shell shell call`, not by editing
`~/.config/om-pg/settings.json`, `apps.json` or the guide's apps folders, and
not by pairing as a phone. `state` says which it is (`awake`) and whether it's
held now (`keptAwake`), and whether Omarchy's own screen saver is up
(`omarchySaver`: the guide is out of its way then, and snapshots wait).

## Themes

A theme can set five things, all optional except a name: **colors** (one per
slot), **fonts**, **layout**, **elements** (the style of each part: fills,
borders, corners, shapes, shadows, padding, and its text's font, size, weight,
case and spacing), and **pictures** (`images` and `background`), plus the
banner and card settings. Whatever a theme leaves out comes from Retro.

Built in: **Premiere** (ink and mint, a screening room: the look a new
install starts with, and the original look), **Retro** (navy and marquee
yellow, the old cable guide), **Aperture** (a cinematic broadcast package in
graphite, ivory and amber), **Nightshift** (late-night graphite, amber and a
teal now line), **OLED** (modern near-black, rounded cells, an Up next list),
**Terminal** (tmux-style panes in the user's Omarchy colors) and
**Split-Flap** (a departures board).
Read one for a worked example: they're in the plugin's `themes/` folder
(`~/.config/omarchy/plugins/marcho78.om-pg/themes/<id>/theme.json`). Themes
you add are kept as folders in `~/.config/om-pg/themes/` (`<id>/theme.json`,
with their pictures copied in beside it, so a theme can be shared whole) and
show in the guide's style panel (S), where the user can switch between them.

The user's own changes (from the style panel, `setColor`, `setStyle`,
`setImage`) stay on top of whichever theme is on. If `addTheme` or `theme`
answers with a non-empty `yourColorsOnTop` or `yourStylesOnTop`, those won't
show the theme's: tell the user and offer `reset theme`.

```json
{
  "name": "Midnight Neon",
  "description": "Deep violet with hot pink and cyan, rounded and glowing.",
  "fonts": { "body": ["Adwaita Sans", "Noto Sans", "sans-serif"], "display": ["Adwaita Sans", "sans-serif"] },
  "colors": {
    "text": "#f5f0ff", "textDim": "#a99bd6", "accent": "#ff4fd8", "timeline": "#34e1ff",
    "cell": "#2a1854", "cellBorder": "#5a3aa8", "channelCell": "#1f1240",
    "selected": "#ff4fd8", "selectedText": "#15082e",
    "header": "#34e1ff", "headerText": "#0b0420", "band": "#120a2a", "bandText": "#34e1ff",
    "infoPanel": "#40000000", "preview": "#000000", "alert": "#ff5a5a",
    "bgTop": "#1a0d3d", "bgBottom": "#090418",
    "ltBg": "#e6140a33", "ltBorder": "#ff4fd8", "ltNumber": "#34e1ff", "ltChannel": "#a99bd6",
    "ltTitle": "#f5f0ff", "ltProgress": "#ff4fd8", "ltTrack": "#2a1854", "ltClock": "#f5f0ff", "ltTime": "#34e1ff",
    "cardBackdrop": "#d9090418", "cardName": "#ff4fd8", "cardStatus": "#a99bd6", "cardFrame": "#5a3aa8",
    "boxBg": "#1a0d3d", "boxBorder": "#ff4fd8", "scrim": "#bf090418",
    "keyFace": "#efe8ff", "keyText": "#1f1240", "keyEdge": "#6b55b0", "miniBar": "#eb090418"
  },
  "layout": { "gap": 0.3 },
  "elements": {
    "programCell": { "radius": 0.5, "border": "none" },
    "programCell:selected": { "shadow": { "color": "#aaff4fd8", "blur": 1, "y": 0 } },
    "timeBar": { "radius": 0.5 },
    "band": { "radius": 0.5, "border": "none", "text": { "case": "none", "letterSpacing": 0.15 } },
    "lowerThird": { "shape": "pill", "width": 0.7, "align": "left", "shadow": { "blur": 2, "y": 0.4 } }
  },
  "background": { "mode": "none" },
  "lowerThird": { "show": true, "seconds": 4 },
  "card": { "show": true, "seconds": 1.4 }
}
```

- **Colors** are `#rrggbb`, `#aarrggbb` (see-through: `aa` `00` clear to `ff`
  solid), or `omarchy.<name>` (below). Give every slot: one left out falls back
  to Retro's navy or yellow. `addTheme` answers with `slotsLeftAtRetro` and
  anything it `ignored` (with why): read `ignored` and fix what you meant.
- **background** is optional: `mode` `none`, `wallpaper` (the user's Omarchy
  wallpaper, following it when it changes) or `image` with `image` (a picture's
  full path), and `dim` (0 to 0.95). Leave `background` out to keep the user's.
- **lowerThird** and **card** are optional, with `show` (true or false) and
  `seconds`. Leave them out to keep the user's.
- **images** is optional: a picture for each area you want one in (see
  Pictures). Give each `src` as a picture's full path on this computer:
  `addTheme` copies it into the theme's folder.
- **apps** is optional: how every app's screen looks (an app with code, like
  Jellyfin or Scores), under any choice the user makes there. Each key is
  optional; one left out follows the look:
  - `look`: `app` (as each app suggests), `classic`, `posters`, `cinematic`,
    `wall` or `compact` (below);
  - `top`: `selected` (what's selected, told large at the top) or `off`;
  - `details`: a details page `classic`, `cinematic`, or `app` (as the app says);
  - `titles`: titles under cards: `below` (every card), `selected` (only the
    selected one) or `off` (only with `top` showing it);
  - `size`: cards `small`, `medium` or `large`;
  - `background`: `{"mode": "focus"|"details"|"guide"|"wallpaper"|"image"|"none", "dim": 0 to 0.95}`,
    with `"image"` a picture's full path for `image` (copied into the theme's
    folder). `focus` is the selected item's picture, blurred and darkened;
    `details` a details page's backdrop. A picture an app or a theme sent is never
    under 30% dark (only a picture the user picked, or their wallpaper,
    goes lighter).

  The five looks: `classic` (as the app says, titles under cards, a details
  page's backdrop behind it), `posters` (posters wherever a row has them),
  `cinematic` (wide pictures, large cards, what's selected at the top, the
  selected picture behind, cinematic details), `wall` (posters, small, no
  titles, what's selected at the top, the selected picture behind) and
  `compact` (small cards, the theme's colors behind, classic details). A
  look never hides, reorders or re-lays-out an app's rows.

| Slot | What it colors | Readable against |
|---|---|---|
| `text` | titles, channel names, the clock | `cell`, `channelCell`, `bgTop` |
| `textDim` | secondary text: times, next up, hints | `cell`, `bgTop` |
| `accent` | the title, channel numbers, box titles, highlights | `bgTop`, `channelCell` |
| `timeline` | the line marking now | `cell` and `header`: it must stand out from both |
| `cell` | program cells | |
| `cellBorder` | cell edges, the cursor row in lists, panel borders | `cell` (a step lighter or brighter) |
| `channelCell` | the channel column | |
| `selected` | the program under the cursor | `cell` (clearly different) |
| `selectedText` | its text | `selected` |
| `header` | the time bar | |
| `headerText` | its date and times | `header` |
| `band` | category bands between channel groups | |
| `bandText` | category names and band border | `band` |
| `infoPanel` | the panel about the program under the cursor (usually see-through) | `text` reads on it |
| `preview` | the preview box behind the video (usually black) | |
| `alert` | NO SIGNAL, the tuned dot, warnings | `cell`, and unlike `accent` |
| `bgTop`, `bgBottom` | the background gradient; `bgBottom` also darkens a background picture | |
| `ltBg` | the lower third's background (over video: keep `aa` at `cc` or more) | |
| `ltBorder` | its border | |
| `ltNumber` | the big channel number | `ltBg` |
| `ltChannel` | channel name | `ltBg` |
| `ltTitle` | the show's title | `ltBg` |
| `ltProgress`, `ltTrack` | how far into the show, and the bar under it | each other |
| `ltClock`, `ltTime` | the clock, and the show's times | `ltBg` |
| `cardBackdrop` | behind the channel-change card, over video (keep `aa` at `b0` or more) | |
| `cardName` | channel number and name on the card | `cardBackdrop` |
| `cardStatus` | TUNING… | `cardBackdrop` |
| `cardFrame` | the box around a channel's initial when it has no logo | |
| `boxBg`, `boxBorder` | dialog boxes and the style panel | `text` on `boxBg` |
| `scrim` | the shade behind dialog boxes (see-through) | |
| `keyFace`, `keyText`, `keyEdge` | the keycaps in the key hints | `keyText` on `keyFace` |
| `miniBar` | the bar across the mini player (see-through) | `text` on it |

**Following the user's Omarchy theme.** A color written `omarchy.<name>` is
taken from the user's current Omarchy theme
(`~/.local/state/omarchy/current/theme/colors.toml`) and changes when they
switch themes. Every Omarchy theme has: `background`, `dark_background`,
`darker_background`, `lighter_background`, `foreground`, `dark_foreground`,
`light_foreground`, `bright_foreground`, `accent`, `selection`, `muted`, `red`,
`green`, `yellow`, `blue`, `magenta`, `cyan`, and `bright_` versions of the six
colors (not every theme has `orange`). Use them in `colors` and anywhere in
`elements`. Roughly: `bgTop` from `background`, `bgBottom` from
`darker_background`, `cell` from `lighter_background`, `text` from
`foreground`, `textDim` from `dark_foreground`, `accent`, `selected` and
`header` from `accent`, `timeline` and `alert` from `red`. The Terminal theme
does this. The theme's wallpaper is `"background": {"mode": "wallpaper"}`.

**Putting it on.** Write the JSON to a file, then give it to `addTheme`. Open
the guide, take a snapshot and look at it (see Looking at your work), fix what
needs it, then show the user and ask what to change. To adjust it, change the
file and `addTheme` it again under the same name.

```bash
f=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/om-pg-theme-XXXXXX.json")
cat > "$f" <<'EOF'
{ "name": "Midnight Neon", "description": "...", "colors": { ... }, "elements": { ... } }
EOF
omarchy-shell om-pg addTheme "$(cat "$f")"
omarchy-shell om-pg open
```

To change one thing the user names without making a theme, set it over the
theme, as theirs: "make the timeline green" is `setColor timeline #22c55e`;
"round the cells" is `setStyle programCell '{"radius": 0.4}'`; "use Adwaita"
is `setStyle fonts '{"body": "Adwaita Sans"}'`.

**Home's background** can come with a theme too: `"home": {"background":
{"mode": "focus"|"guide"|"wallpaper"|"image"|"none", "image": "/full/path.jpg",
"dim": 0.6}}` (leave it out to keep the user's). `focus` shows the picture of
what's selected, blurred; `guide` the guide's background picture; `none` the
theme's colors only.

**Multiview's background** comes the same way: `"multiview": {"background":
{"mode": "none"|"color"|"theme"|"wallpaper"|"image", "color": "#rrggbb",
"image": "/full/path.jpg", "dim": 0.6}}`. `none` is the theme's colors
(`mvBackground`), `color` the color given, `theme` the theme's own picture.

## Elements

Every part of the guide is an element. `elements ""` lists them all (with what
each is, its states, and whether the theme or the user styles it); `elements
<name>` shows one in full. The main ones:

| Section | Elements |
|---|---|
| Guide | `background`, `title`, `showing`, `clock`, `infoArea`, `preview`, `previewTag`, `infoPanel`, `infoChannel`, `infoTitle`, `infoTime`, `infoDesc`, `infoProgress`, `infoNext` (`:later`), `upNextLabel`, `divider` |
| Grid | `timeBar`, `band`, `channelCell` (`:current`, `:marked`), `channelNumber`, `channelName`, `logoBadge`, `programCell` (`:selected`), `liveTag`, `nowLine` |
| Bars | `topBar`, `barBadge`, `barLabel`, `barValue`, `modeBadge` |
| Table | `pane`, `paneTitle`, `tableHeader`, `tableGroup`, `tableRow` (`:current`), `rowMarker` (`:playing`), `tableText`, `tableDim`, `rowProgress` (`:live`) |
| Board | `flapTile` (`:status`) |
| Home | `homeTile` (`:current`), `homeCard` (`:current`), `homeCardTitle`, `homeCardSub`, `homeRowTitle`, `heroKicker`, `heroTitle`, `heroMeta`, `statusChip`, `homeShade` |
| Library | `libraryTab` (`:current`), `rowTitle`, `posterCard` (`:current`), `posterTitle`, `posterSub`, `liveBadge`, `cardBadge` |
| Recordings | `recordBadge` (follows `liveBadge`: ● REC and its stop time on the banner), `recordChoice` (follows `menuRow`, `:focused`: Record, Save video, Stop recording and the stop times among the banner's choices; Record, Record every episode, Cancel recording and Stop recording this series among a show's choices in the guide; a recording's choices in its details), `recordNote` (follows `posterSub`: the line under a Record choice), `recordWarning` (follows `cardBadge`: the word above the banner while watching one channel and recording another from the same provider), `recordDot` (`:recording`, red: ● Recording, Scheduled or Conflict in a program cell), `channelRec` (● REC beside a recording channel's name in the channel column), `mastheadRec` (what's recording, at the top of the guide), `recordingCard` (follows `posterCard`, `:current`), `upcomingRecording` (follows `posterCard`, `:current`: a scheduled one's card), `recordingState` (`:recording`, `:scheduled`, `:attention`: the word on a card: Recording, Saving; Scheduled; Failed, Missed, Incomplete, Conflict, Drive missing; none for Done), `recordingProgress` (follows `vodProgress`: how far a recording is to its stop), `liveChip` (`:behind`: Live, or how far behind live, on the banner while pause and rewind is on, and on the picture while it's behind). "A red REC badge with white text" is `setStyle recordBadge '{"fill": "alert", "text": {"color": "#ffffff"}}'` |
| Multiview | `mvBackground` (follows `background`), `mvTile` (`:current`, the tile with the sound: every tile is framed by a thin border, the current one thicker), `mvStrip` (the band with the channel and what's on), `mvName` (follows `posterTitle`), `mvShow` (follows `posterSub`), `mvSound` (follows `cardBadge`): Multiview's screen, up to four channels at once. "Thicker borders between the tiles" is `setStyle mvTile '{"border": {"width": 0.15}}'` |
| Apps | `appCard` (`:current`, its `grow`), `appCardTitle`, `appCardSub`, `appRowTitle`, `appBadge`, `appProgress`, `appTopKicker`, `appTopTitle`, `appTopMeta`, `appTopText`, `appDetailTitle`, `appDetailMeta`, `appDetailText`, `appFactLabel`, `appFactValue`, `appChip`, `appButton` (`:focused`), `appShade`, `appTableHead`, `appTable` (`:focused`), `appTicker`, `appChart`, `appOrigin`, `appPageTitle`, `appPageHeading`, `appPageText`: an app's screen. Each follows the guide part it's like (`elements <name>` says which: `appCard` follows `posterCard`, `appButton` follows `menuRow`…), state by state, until styled. Whatever the style, the guide keeps its own focus ring round the selected card, keeps the selected title readable and its text no smaller than its floor, and keeps the strip naming the app on top |
| Player | `vodBar`, `vodTitle`, `vodInfo`, `vodTime`, `vodProgress` (on demand: the bar over a movie or video) |
| Rail | `rail` (`:open`), `railItem` (`:current`, `:focused`) |
| Menus | `searchField` (`:focused`), `menuCategory` (`:current`, `:focused`), `menuRow` (`:focused`), `menuValue` (`:focused`), `menuHeader`, `menuNote`, `toggle` (`:on`): Settings, the Customize panels, the boxes and the style panel, TV style (big rows, the focused one lit and grown a little, on/off switches) |
| Keys | `footer`, `keycap`, `keyLabel` |
| Boxes | `scrim`, `box`, `boxTitle`, `boxText`, `panelHeader`, `listRow` (`:current`), `input` (`:focused`) |
| Lower third | `lowerThird`, `ltNumber`, `ltChannel`, `ltTitle`, `ltProgress`, `ltClock`, `ltTime` |
| Channel card | `card`, `cardName`, `cardStatus`, `cardFrame` |

A state (`programCell:selected`) takes the element's style and changes what it
sets: give it only what differs. Its own defaults (the selected cell's fill
and text color) win over the element's, so a theme's `programCell` text color
doesn't spill onto the selected cell.

**Box properties** (on elements with a box):

- `fill`: a color, `none`, or a gradient `{"from": c, "to": c, "direction": "down"|"up"|"right"|"left"}`
- `border`: `{"width": length, "color": c, "sides": "all" or ["top", "bottom", "left", "right"]}`, or `none`. Sides need square corners
- `radius`: a length, or four `[top left, top right, bottom right, bottom left]`
- `shape`: `rect` (with `radius`), `pill` (round ends), `slant` (a parallelogram; `slant` is how far the ends lean, negative leans the other way), `arrow` (pointed right end; `slant` is the point's length, negative points left), `chevron` (notched left, pointed right), or `path` with `path`, an SVG path drawn in a 100 by 100 box and stretched to the element (`"M0,20 Q0,0 20,0 L100,0 L100,100 L0,100 Z"`)
- `shadow`: `{"color": c, "blur": length, "x": length, "y": length}` or `none`. Not on every cell or row (they're drawn hundreds of times): the selected or current one can have one
- `padding`: a length, the space inside

**Text properties** go under `"text"` (`"programCell": {"fill": …, "text": {"size": 1.1}}`); on a text-only element (`title`, `clock`, `infoTitle`…) they can go on their own:

- `color`, `font` (`body`, `display`, `mono`, an installed family, or a list of families: the first installed is used), `size` (units), `weight` (`thin`, `light`, `normal`, `medium`, `semibold`, `bold`, `black`, or 100 to 900), `case` (`upper`, `lower`, `title`, `none`), `letterSpacing` (units), `italic`

**Lengths** are units, a 60th of the screen's height (so 1 is about 17 px on a
1000-px-tall screen, and a theme looks the same on any screen), or `"2px"` for
pixels (good for thin borders). Keycap `radius`, `depth` and text sizes, and
the key label's size, go by the key's height instead (0.2 is a fifth of it).

Some elements have their own properties, shown by `elements <name>`: the lower
third's `height`, `margin`, `width` (`full` or a share, 0.2 to 1) and `align`
(where it sits: a floating pill on the left is `{"shape": "pill", "width":
0.6, "align": "left"}`); the progress bars' `track`, `height`, `width`; the
now line's `color`, `width` and `style` (`line`, `tick` in the time bar only,
`none`); the keycap's `edge` color and `depth`; the flap's `seam`, `aspect` and
`gap`; the divider's `color` and `height`.

**Fonts** are set by role in `fonts`: `body` (most text), `display` (the title,
clocks, big numbers) and `mono` (tags and the like). Use only installed
families (`fonts "<words>"` finds them), or give a list so the theme works on
other computers too: `["Adwaita Sans", "Noto Sans", "sans-serif"]`. Omarchy
installs `JetBrainsMono Nerd Font` (the terminal font), `Noto Sans`, `Noto
Serif` and the `iA Writer` fonts; usually there too are `Adwaita Sans` (like
Inter), `Adwaita Mono`, `Liberation Sans` and `Nimbus Sans Narrow`
(condensed), so end a list of those with one of the first.

## Layout

`layout` in a theme (or `setStyle layout`) arranges the guide. `elements ""`
lists every setting with its range, Retro's value and what's on now.

| Setting | Takes | What it does |
|---|---|---|
| `list` | `grid`, `table`, `board` | the channels as the time grid, a terminal-style table (with preview and lineup panes), or a split-flap board |
| `masthead` | `title`, `bar`, `none` | the title row, a thin status bar, or nothing |
| `titleDate` | true, false | the day after the title |
| `clock` | `masthead`, `info`, `none` | where the clock goes (`info`: top right of the info panel, with the date) |
| `hours24` | true, false | 20:13 instead of 8:13 PM |
| `info` | true, false | the info area (preview and program details) |
| `infoHeight` | 6 to 20 | its height |
| `preview` | `left`, `right`, `none` | the preview box's side |
| `previewTag` | true, false | LIVE PREVIEW · CH 1 on the preview |
| `infoProgress` | true, false | a bar showing how far into the program |
| `upNext` | 0 to 4 | what's next: 1 a NEXT line, 2 or more a list under Up next |
| `dividers` | true, false | thin lines between the info area, the list and the keys |
| `hours` | 1, 1.5, 2, 2.5, 3 | hours across the grid |
| `rowHeight`, `gap`, `channelWidth`, `timeBarHeight`, `bandHeight` | units | the grid's sizes |
| `channelCell` | `stacked`, `row` | the channel cell: number over name, or number, badge and name in a row |
| `tableWidth`, `tableRowHeight` | | the table's share of the width, its rows |
| `columns` | a list | the table's or board's columns, in order: `number`, `name`, `now`, `next`, `nextAt`, `left`, `bar`, `status`, `category` |
| `boardRowHeight` | units | the board's rows |
| `footer` | `keys`, `status` | key hints, or a status line with a mode badge and counts |
| `rail` | `always`, `focus`, `none` | the nav rail down the left: always (thin, icons), only when the user goes to it, or never |
| `railWidth`, `railOpenWidth` | units | the rail, thin and open |
| `homeHero` | true, false | Home: the big title of what's selected, and the time |
| `homeCardWidth`, `homeTileHeight` | units | Home's cards (16:9) and tiles |
| `libraryPosterWidth`, `libraryThumbWidth`, `librarySquareWidth` | units | the library's posters (2:3) and video pictures (16:9), and apps' square, logo and round pictures |

The user's key hints setting decides whether the keys show: a theme can
restyle them, or make them a status line, but not hide them.

## Home

With Home on (Settings), the guide opens on it: the time, what's selected
told large at the top, then the user's sections. `home` shows them.

- **Sections**, in order, each on or off: `doors` (the tiles), `continue`
  (Continue watching), `onNow`, `latest` (the newest video of each YouTube
  channel), `soon` (Starting soon), `mylist`. Rows the user adds: `{"type":
  "genre", "key": "<a library genre>"}`, `{"type": "channel", "key": "<a YouTube
  channel's url>"}` (its videos), `{"type": "category", "key": "<a category>"}`
  (what's on in it), `{"type": "folder", "key": "<a My Videos folder, . for
  itself>"}`, `{"type": "upcoming", "key": "<a channel's url>"}` (what's coming
  up on it). `home` lists what can be added. Built in too: `searches` (the
  user's recent searches), `recordings` (recording now, then the latest
  recorded; while Recordings is on or there are some).
- **A row's options:** `title` (a name of the user's; leave it out for its
  own), `size` (`small`, `medium`, `large`), `limit` (0 for all, 6, 12, 24),
  `sort` (`default`, `newest`, `oldest`, `az`).
  `videos` (New in My Videos) shows while My Videos is on.
- **Tiles**: `tv`, `movies`, `ondemand`, `videos`, `mylist`, in the order given,
  any left out (`videos` shows while My Videos is on).
- **The screen** is layout (`setStyle layout`): `homeHero` (the big title on
  or off), `homeTop` (`selected`, `clock`, `channel`: what it tells),
  `homeClock` (`left`, `right`, `none`), `homeChips` (true or false).
- **Background**: `{"mode": "focus"|"guide"|"wallpaper"|"image"|"none", "image":
  "/full/path.jpg", "dim": 0 to 0.95}`. Only pictures already on the computer.

`setHome` replaces what it's given and keeps the rest: "put my Sci-Fi movies
on Home, after On now" is `home` (to see the order), then `setHome` with the
sections in the new order. "Use this picture behind Home" is `setHome
'{"background": {"mode": "image", "image": "/home/you/Pictures/x.jpg"}}'`. The
user can do the same with C on Home.

## Movies, series and videos on demand

A playlist entry that's a video file (`.mp4`, `.mkv`…, or an IPTV provider's
`/movie/` or `/series/` link) goes to the library, not the guide: its
`tvg-logo` is the poster, `tvg-description` (or `#EXTDESC`) the synopsis,
`group-title` the genre, and names like `Show S01E02` group into series.
`addChannels` says how many went where. The library also has every video of
the user's YouTube channels (On Demand) and My List.

**My Videos** (on unless the user turns it off) is the video files in the
user's Videos folder and the folders in it, each folder a row, each video with
its length and a picture from it. `setVideos on "/full/path"` shows another
folder. Nothing is copied or uploaded.

`search "<words>"` finds anything (a channel's number, a movie's or a video's
id); `library "<words>"` finds a movie's id and `videos "<words>"` one of the
user's videos; `play <id>` plays it full screen, from where the user stopped (a
YouTube video is `yt:<its 11-character id>`). The user pauses with Space, seeks
with ← →, and Esc stops it, remembering where.

## Multiview

Multiview shows up to four channels at once (live, scheduled or IPTV), the
sound from one. "Put 101, 501 and 801 on" is `multiview "101,501,801"`; the
first one has the sound and is the big tile in Featured. Look numbers up with
`channels "<words>"` first. A locked channel is refused (only the user unlocks
it, at the screen), and so is one with nothing to show yet.

| Channels | Layouts (the first is what it opens with) |
|---|---|
| 2 | `side` (side by side), `featured` |
| 3 | `featured` (the first big, two beside it), `grid`, `row` |
| 4 | `grid`, `featured` |

`multiviewAdd` makes the layout its new count's first; `multiviewLayout`
changes it after. One channel alone opens with the Add a channel list, for the
user to pick the rest. `state`'s `multiview` says what's on (`null` when it's
off). The user does all of this from a channel's banner (I or Space while
watching) and Multiview's own keys; its background is `multiviewBackground`.

## Recordings

Recordings start off. Until the user turns them on (a strip asks them once,
or Settings → Recordings), `record`, `recordShow` and `recordSeries` answer
that Recordings are off. Turn them on (`setRecordingSettings '{"on": true}'`)
only when the user asks.

The user records what's on from the channel banner (I or Space while
watching, then Record) or from a show in the guide (I or Space on it), and
finds recordings in the library's Recordings tab.
"Record channel 132 for two hours" is `record 132 "2h"`; `""` records to the
end of the show (with listings, plus the late padding), or an hour without
listings. On a scheduled YouTube channel it saves the video that's on, whole.
A recording goes on with the guide closed, while the user is logged in.
`record` answers at once; `recordings` says a moment later whether it's
`Recording`, or why it couldn't start (`why`).

A later show: "record Bake Off at nine on 107" is `recordShow 107 21:00`
(`next` for the next show). Without a channel or a time ("record the next
Bake Off"), `shows "" "bake off"` finds it: give `recordShow` its number and
`when` ("2026-10-21 21:00"). "Record every episode" is `recordSeries 107 now`
(or a time). They need an IPTV channel with listings. A scheduled one starts
on time with the guide closed, while the user is logged in; one that couldn't
(logged out, asleep, off) is `Missed`. As many record at once as the user's
setting says (2 unless they chose 1 to 4: `recordingSettings`' `atOnce`): a
show that would be one too many is a `Conflict` (`why` names the others) and
records only if one of them is cancelled. `cancelRecording` cancels a scheduled one, or a
series by its id from `recordings`' `series`, only when the user asks. A
locked channel is refused (only the user unlocks it, at the screen), and its
recordings say nothing about themselves to you. While an IPTV channel
records, `watch`, `multiview` and `multiviewAdd` refuse another channel from
the same provider (a second stream may stop the recording): ask the user;
the guide asks them when they go to it.

Pause and rewind: "pause the TV" is `pauseLive`, "go back a minute" is
`seekLive -60`, "back to live" is `goLive`. They work only while the user's
setting is on (`recordingSettings`' `pauseAndRewind`: 5 or 30 minutes) and a
live channel is on the TV; otherwise they say why. Don't turn it on unless
the user asks.

`recordingSettings` says where recordings go. `setRecordingSettings` changes
it when the user asks: `"place": "videos"` (an Uber TV Recordings folder in
their Videos folder), a folder's full path, or `"drive:<device>"` for a USB
drive that's already opened (`recordingDrives`; the user opens one in
Settings → Recordings). The guide checks a place before using it: hidden,
system, temporary and Uber TV's own folders are refused. Delete recordings
(`removeRecording`) only when the user asks.

## Program listings

IPTV channels show their shows (not one LIVE block) when there are program
listings for them. A provider often gives a listings link (XMLTV); free ones
by country are listed at `https://epgshare01.online/epgshare01/` (files like
`epg_ripper_US2.xml.gz`; the `.txt` beside each lists its channels).
`addListings` adds one, and `listings` then says how many channels it matched.
Matching is by `tvg-id`, then name within a country; a feed-specific channel
(Pacific, one station of a network) only takes its own feed's listings. Add
sources only when the user asks; big ones (tens of MB) are fetched twice a day.

## The nav rail

Down the left of every screen, a way to each part. `rail` shows its items;
`setRail` sets which are on and their order, and when it shows. An item whose
part is turned off (Home, when the Home screen is off; My Videos, when it's
off; Apps, while apps are off; Recordings, while it's off and there are none) stays off the rail until the part is on again, without changing the
user's choice. The user does the same with C on the open rail, or in Settings.

## Apps

Apps (Netflix, Hulu and others, each a website the guide opens full screen) come from
the signed Uber TV catalog, and only the user turns them on and installs
them, in Settings → Apps, after seeing what each asks for. `apps` says what's
there; when the user asks for an app, tell them where to get it (Settings →
Apps → Get apps, or Apps on the nav rail). `appOff` turns one off when the
user asks, or when something about it worries you (say why).

Never install, update or turn on an app by editing files: not
`~/.config/om-pg/apps.json`, not the guide's apps folders
(`~/.local/share/om-pg/apps/`), not its secrets (`~/.config/om-pg/app-secrets/`)
or storage, not its cache. Even when the user asks you to install one, tell
them where to do it instead. You may write an app for them, check it, try it
and pack it (below); they install it themselves, from Settings → Developer →
Install an unsigned app, with Developer mode on, after seeing what it asks for. Never
type a secret or sign in for them: they do that in the app's settings.
Third-party apps and Developer mode are the user's alone: each asks for the
computer's password. Third-party apps lets the user pick a signed `.tvapp`
they downloaded; Install asks for the password too. Never turn either mode
on, pick, install, update or approve an app for them, and never edit
`~/.config/om-pg/apps.json` or the installed-app folders. If they ask to
install one, tell them where: Settings → Apps → Third-party apps, then
**Install a third-party app**. `apps` shows installed origins and a signed app's
developer key, read only.

**Third-party apps or Developer mode: what to tell the user**
- **Third-party apps** is for apps other developers make. The developer gives
  out a `.tvapp` file: one file holding the app, the developer's key, and a
  signed note of the app's name, version and what it may do. The user
  installs it from Settings → Apps → Install a third-party app. They see who made
  it, it gets updates only from that developer and only after the user
  agrees, and the developer can withdraw a bad version, which then turns off.
- **Developer mode** is for testing an app the user is making. It installs
  straight from the app's folder or a `.tar.gz`, unsigned, with no updates,
  and the app opens only while Developer mode is on. It's hidden until the
  user presses OK 7 times on the version in Settings → About.
- If they downloaded the app, it's Third-party apps. If they're building it,
  it's Developer mode.

## App screens

An app with code (Jellyfin, Scores, an app the user wrote) gets its screens
drawn by the guide, so how they look is the user's to choose, and yours to
change when they ask. Change only what they asked for.

**Who decides what.** For each of `look`, `top`, `background`, `details`,
`titles` and `size`, the first that's set wins: the user's choice for this
app, then their choice for every app (`all`), then the theme's (`apps`, see
Themes), then (the look only) the app's own suggestion, then Classic. `look`
as a value hands it to the look; `app` as a look hands it to the app. A row's
pictures, size, layout and titles: the user's choice for that row, then the
look's, then what the app says. The five looks:

```json
{
  "classic":   {"picture": "app",    "size": "app",   "titles": "below",    "top": "off",      "background": "details", "details": "app"},
  "posters":   {"picture": "poster", "size": "app",   "titles": "below",    "top": "off",      "background": "details", "details": "app"},
  "cinematic": {"picture": "wide",   "size": "large", "titles": "selected", "top": "selected", "background": "focus",   "details": "cinematic"},
  "wall":      {"picture": "poster", "size": "small", "titles": "off",      "top": "selected", "background": "focus",   "details": "app"},
  "compact":   {"picture": "app",    "size": "small", "titles": "below",    "top": "off",      "background": "none",    "details": "classic"}
}
```

**Handles, never the app's own ids or words.** `appScreen` names rows by
handles (`r-` and 12 hex digits) and, while the app is on the screen, its open
and info items by handles (`i-` and 16), with their positions. No answer holds
anything the app wrote: an app that comes with the guide gives its rows'
labels from its own reviewed `app.json`, and otherwise rows and items are
known by their position. Tell them apart by looking at an `appSnapshot`, as
the user would. Pass handles back; anything else (an app's own row id
included) is ignored like a made-up key. A row handle lasts while the app
stays installed (a reinstall makes new ones); an item handle only for the view
it came from. A `view` id (`v-` and a number) names the screen on show, and a
new one comes with every screen, Back included.

**Changing a screen, then looking at it:**
1. `setAppScreen` (or `setStyle` for the APPS parts). Then poll `state` for at
   most 10 s. On each poll, first check that its `saving.run` is the one in
   your token (`w-<run>-<number>`): if it isn't, the guide restarted, so stop.
   Go ahead once your token says `saved`, and poll on while it's `pending`.
   Stop and say so if it's `failed` or `unconfirmed`, if its number falls
   below `saving.since`, or if 10 s pass; never assume it saved.
2. `openApp <app id> ""`, keeping the `view` it answers. (It's refused while a
   box is open, while something plays, or when the app has stopped working:
   say why. It never plays anything or presses an app's buttons.)
3. Poll `appScreen <app id>` until its `view` is that one, its `state` is
   `ready`, `covered` is false and `picturesPending` is 0, or 10 s pass. A
   different `view` means the user moved or the app started again, and
   `covered` that the user is doing something: stop and say so.
4. `appSnapshot <view>`.
5. Poll `state` until its `snapshot.name` is that file and its `outcome`
   isn't `pending`. Read the file if it's `written`; if it's `refused`, stop
   and say why.

**Examples:**
- "Make Jellyfin look like Netflix": `setAppScreen tv.uber.jellyfin
  '{"look": "cinematic"}'`, then steps 1 to 5 to show it.
- "Posters for my movies, hide Recently added": `appScreen tv.uber.jellyfin`,
  find the rows (by label where there is one, else by position and a
  snapshot), then `setAppScreen tv.uber.jellyfin '{"rows": {"r-…": {"shape":
  "poster"}, "r-…": {"show": false}}}'`. A row's choices: `show`, `name` (the
  user's name for it), `shape` (`poster`, `wide`, `square`, `logo`,
  `circle`), `size`, `layout` (`row`, `grid`, `list`, or `hero` where the app
  made one) and `titles`; `order` lists handles, first to last. To open a
  library inside Jellyfin, `openApp tv.uber.jellyfin "i-…"` with its handle.
- "Round every app's cards": `setStyle appCard '{"radius": 0.8}'` (the APPS
  parts are every app's; see Elements).
- "The same look for every app": take an app's choices from `appScreen`
  (`choices`: look, top, background, details, titles, size) and give them to
  `setAppScreen all '<json>'`. Each app's own choices still win; ask before
  `resetAppScreen <app id>`, which makes it follow everyone's.
- "Save this as a theme": `saveTheme "<name>" ""` keeps the look for every
  app (not one app's own choices).

## Making an app

Two kinds. A *launcher* is a website opened full screen (`"kind": "launcher"`,
`"api": 1`, `launch.web` and `permissions.web`: see the catalog's README). An
*app with code* (`"kind": "app"`, `"api": 4`; 3 if it changes nothing on any site, 2 for the older blocks) runs
Python in the guide's sandbox and sends what to show; the guide draws it. The
plugin's folder is `~/.config/omarchy/plugins/marcho78.om-pg` (`bin/`,
`apps/sdk/`, `apps/first-party/` for two complete apps: Scores, Jellyfin, and
`apps/sdk/examples/showcase`, an offline app using every block: start from
it). Everything an app may say is in `apps/sdk/PROTOCOL.md`.

**What it may use:** Python's standard library, the toolkit (`uber_tv`), and its
own `.py` files. No packages, no network of its own, nothing writable but
`/tmp` (16 MB). Files: `.py`, `app.json`, `.json` data, PNG/JPEG/WebP pictures
(4096 px at most), `.md`, `.txt`, `LICENSE`; all text UTF-8.

**`app.json`:**

```json
{
  "id": "com.example.weather", "name": "Weather", "version": "1.0.0", "api": 4, "kind": "app",
  "author": "You", "description": "Today and the week ahead.", "color": "#2b6cb0",
  "icon": "icon.png", "main": "main.py",
  "permissions": { "net": ["api.open-meteo.com"] },
  "settings": [ { "key": "city", "type": "text", "label": "City" } ],
  "home": [ { "key": "today", "label": "Weather today", "shape": "wide" } ],
  "layout": { "look": "classic", "rows": [ { "id": "week", "label": "This week", "shape": "square", "size": "small" } ] }
}
```

`layout` (API 3 and 4) is the look the app suggests (`classic`, `posters`,
`cinematic`, `wall` or `compact`; the user and a theme can choose another)
and its rows' defaults by row id: a `label` the user sees in Customize, and a
`shape`, `size` and `layout`, at most 40 rows. A Home row's `shape` is
`poster` or `wide`.

Permissions, each shown to the user in plain words before it installs:
`net` (exact hosts, no wildcards or subdomains; https; GET and HEAD),
`netWrite` (API 4: `{"api.example.com": ["POST"]}`, the `net` hosts it may also
change things on, with the methods: POST, PUT, PATCH, DELETE; the user sees
each under "Can change things on", so ask only for what it does),
`server` (`{"label", "defaultPort", "fromSignIn"}`: a server the user chooses; GET, HEAD,
POST, PUT, PATCH or DELETE, under its path; for things like Jellyfin), `play` (play media from those),
`signIn` (needs `server`): `"code"` (a code the user enters elsewhere), or at
API 4 `"password"` or `["code", "password"]` (the guide's own box takes the
username and password and hands them to `sign_in` once: `flow.how ==
"password"`, then `flow.credentials()` gives `(username, password)` or None if
cancelled; sign in with `fetch`, `flow.keep()` only what the service gives
back, never the password), `storage` (4 MB of its own). For an account that
lists the user's servers (like Plex), API 4's `"server": {"label": "…",
"fromSignIn": true}` starts the sign-in with no server: signed in to the
account, `flow.offer_servers([{"handle", "label", "urls"}])` lets the user
choose one (and how to reach it) and returns `{"handle", "url"}` or None;
keep only that server's credential (the handle is your own name for it:
never a token). `apps/sdk/examples/accounts` does this offline with
fixtures.
Settings: `text`, `choice` (with `choices`), `switch`, `secret` (asked of the
user, kept apart; read it with `secret(key)`). Ask for as little as it needs.

**`main.py`:**

```python
from uber_tv import app, get_json, settings, storage, Screen, Row, Item, Detail, AppError

@app.home
def home():
    city = settings.get("city") or "Lisbon"
    data = get_json("https://api.open-meteo.com/v1/forecast?latitude=38.7&longitude=-9.1&daily=temperature_2m_max&timezone=auto")
    days = data["daily"]
    items = [Item(d, d, subtitle="%.0f°" % t, kind="info") for d, t in zip(days["time"], days["temperature_2m_max"])]
    return Screen("Weather in " + city, rows=[Row("week", "This week", items)], empty="No forecast.")

@app.details
def details(day):
    return Detail(day, subtitle="Max temperature", facts=[("Day", day)])

@app.home_row
def home_row(key):
    return home().to_dict()["rows"][0]["items"][:3]

app.run()
```

**What a screen can hold (API 3).** A `Row(id, title, items, layout=,
shape=, size=)`: `layout` `row`, `grid`, `list` or `hero` (one big item at a
time, at most 10); `shape` `poster`, `wide`, `square`, `logo` or `circle`
(left out, the guide works it out from the row's first three pictures:
under 0.8 wide to high is a poster, to 1.25 a square, above that wide; a tie
or none, wide); `size` `small`, `medium` or `large`. A row's id is lowercase
letters, digits, `-` and `_`, starting with a letter, and keeps meaning the
same row in every version: the user's choices for it (hidden, renamed,
moved, its pictures) follow the id. An `Item(id, title, subtitle=,
image=, images=, meta=, text=, watched=, badge=, progress=, kind=)`:
`images` holds a picture for each shape it has one for (`poster`, `wide`,
`square`, `backdrop`, `logo`), and a card shows the one for its row's
shape, else `image`; `meta` a short line (80 characters: year, length,
rating), `text` up to 4 lines (300), `watched` true or false. A hero item
shows its `backdrop` (else `wide`) behind it and its `logo` (else its
title). A `Detail(title, ..., style=, logo=, meta=, chips=, rows=)`: `style`
`classic` or `cinematic` (the backdrop across the page, the logo for the
title), `meta` (120), `chips` (up to 8 of 24), and up to 4 rows. Give
pictures in their own shape: the guide never crops a logo or a person.
API 4 adds a table row (`Row(..., layout="table", columns=[Column("Team"),
Column("W", "end")])`, each `Item(..., cells=["Gulls", "18"])`: standings,
schedules), a ticker row (`layout="ticker"`, up to 30 items of title and
badge, moving across), a `Chart(points, low=, high=)` on an item (drawn in a
list or table line) or a `Detail`, and a `Page(title, sections=[Section(heading,
text)])` that `browse`, `details` or `action` may return (an article the
arrows scroll). The showcase has each. A screen can be live
(`Screen(..., live=True)`): while it's shown, `@app.live` gets a `view`
(`view.method`, `view.args`; every Home row of an API 4 app is one too) in
its own thread; `view.sleep(15)` (False once it's gone), then
`view.update([Row(...)])` replacing rows by their ids (a Home row:
`view.update([Item(...)])`), at most once a second (Home: every 5 s);
`fetch` works in it, and `view.stream(url)` yields the lines of a long GET
to one of its net hosts. Send every row the screen may need in its first
answer (empty ones are fine): an update never adds a row. Scores is live.

The handlers: `home()`, `browse(item)` (an `open` item), `details(item)` (an
`info` item, or I), `search(query)`, `play(item)` (returns `Play(url, headers,
title, start_at, context)`), `action(item, action)` (a detail's button),
`home_row(key)`, `playback(event)`, `playback_failed(event)`, `sign_in(flow)`
(`flow.how`, `flow.show_code(code, url, expires)`, `flow.credentials()`,
`flow.offer_servers(servers)`, `flow.sleep(5)`, `flow.keep(name, value)`,
`flow.done(ok, message)`), `sign_out()`. To try a password sign-in, put
`"@username"` and `"@password"` in the `--secrets` file and `--call
'signIn:{"how":"password"}'`; for a server chosen while signing in, add
`"server": "<handle>"` and `"url"` or `"typed"` to that call (else try takes the
first one's first address). `fetch(url, method, headers,
json)` returns `.status`, `.json()`, `.text`; `get_json(url)` raises unless
2xx. `storage.get/put/get_json/put_json/delete/keys` (`server=True` on put:
forgotten on sign-out). `raise AppError("A plain message.")` shows the user a
message. Every call has 10 seconds (play 30). Item ids are yours (up to 200
characters): encode what you need (`"lib:42:48"`), and page long lists (a row
holds 50 items, a screen 200: end a page with a `More…` item that opens the
next). Text is plain, cut to fit; pictures are `"icon.png"` (in the app) or a
link on a host it may reach.

**Check it, try it, pack it** (try runs it in the same sandbox, offline unless
`--live`; offline, requests are answered only from `--fixtures`). For each
row, on a screen or a details page, try prints its layout, shape and size and where each came from (the
row, app.json, the look, or auto: the shape it learns from the first
pictures), and for each card the picture it shows and why ("images.poster",
or "image (no images.poster: its image instead)"). It's the screen as the
guide draws it in the look your app.json suggests (Classic if none), before
the user's own choices or a theme's, which can change shapes and sizes.
A look with a picture rule (Posters and Wall: posters; Cinematic: wide)
takes that shape for every row whose items all have that picture:

```bash
P=~/.config/omarchy/plugins/marcho78.om-pg
python3 $P/bin/om-pg-apps check ~/weather
python3 $P/bin/om-pg-apps try ~/weather --live --call home --call 'details:{"item":"2026-10-12"}' --call 'homeRow:{"key":"today"}'
python3 $P/bin/om-pg-apps pack ~/weather ~/weather.tar.gz
```

An app with a server: `--server http://192.168.1.20:8096` (and `--pin <sha256>`
for a pinned certificate); live, only GET and HEAD reach it, or a `netWrite`
host, unless you add `--allow-write`. Fixtures (`--fixtures f.json`): `{"requests": [{"method": "GET", "url":
"https://…", "status": 200, "json": {…}}]}` (or `"body"`, `"bodyFile"`).
`--play` plays a `play` result through the relay as the guide would. Fix what
`check` and `try` say before handing it over. Then tell the user what it does,
what it asks for, and how to install it (Developer mode, Install an unsigned app,
its folder's `app.json` or the `.tar.gz`); its tile shows a small page,
because nobody but you two has read it. Developer mode is hidden until they
press OK 7 times on the version in Settings → About, and turning it on asks
for their computer's password: tell them so; never do it for them.

## Publishing your app

To share an app, its developer makes a signed **app file** (`.tvapp`). The
file carries the app package, its signed release note and the developer's
public key. An optional HTTPS update folder holds `release.json`, its
signature and `package.tar.gz`. `docs/sources.md` says it all. You may run
these for the developer:

```bash
P=~/.config/omarchy/plugins/marcho78.om-pg
python3 $P/bin/om-pg-apps app-key ~/my-publisher
python3 $P/bin/om-pg-apps app-file ~/weather ~/my-publisher
python3 $P/bin/om-pg-apps app-file ~/weather ~/my-publisher https://you.github.io/weather/
python3 $P/bin/om-pg-apps app-revoke ~/my-publisher tv.alex.weather 1.2.0 "unsafe release"
```

`app-key` initializes one permanent publisher workspace and makes an Ed25519
key under `~/.ssh/`. `ssh-keygen` asks for a passphrase, which is the
developer's to type: run it where they can type it, never pass or store one
yourself. Keep the whole workspace; its private history prevents an old
release or a missing withdrawal becoming current.

`app-file` checks and packs the app, advances the signed release, and makes a
new exclusive `<id>-<version>-<updated>` folder. Without an update address,
give the user its `.tvapp`. With one, upload that folder's `release.json`,
`release.json.sig` and `package.tar.gz` to the exact HTTPS folder and give the
user its `.tvapp`. The command uploads nothing. A changed app needs a newer
version in `app.json`; never edit a release by hand or move only exported
release folders as publisher state.

`app-revoke` makes a newer signed note withdrawing one version, or `*` for
all, and carries every earlier withdrawal forward. There is deliberately no
unrevoke command. Upload the new note and signature. An installed copy turns
off once its guide checks that note while the Third-party apps switch is on. Never turn
on Third-party apps, pick an app file, install, update or approve anything
yourself; those are the user's actions at the screen.

## Looking at your work

With the guide open, `snapshot ""` writes a PNG of it (1600 px wide at most)
and answers its file's `path`. The file is written a moment later: poll
`state` until its `snapshot` has that `name` and its `outcome` isn't
`pending`. Read the file if it's `written`; if it's `refused`, say why (`why`)
and don't look for the file. A snapshot is refused while a sensitive screen
is up (the phone remote's box, an app's sign-in or settings, a certificate to
pin, a text field), also when one comes up while it's taken; one at a time.
Then check that text reads against what's behind it, that nothing is cut off
or overlapping, and that the selected cell, the now line and the accent stand
apart. Fix and `addTheme` again until it's right, then show the user.

The snapshot shows what's on screen. `open` shows Home (with Home on); for the
lower third and the card, `watch` a channel and take it within the first
seconds (the card shows while it tunes, the banner for the seconds set); for
the player bar, `play` something. Close the guide when you're done
looking (`close`) unless the user wants it open.

## Pictures

Each of these areas can have a picture over its color, under its text:

| Area | Where | Starts as |
|---|---|---|
| `masthead` | a logo in place of the "UBER TV" title (shown whole, 3 rows tall) | fit, 100% |
| `infoPanel` | behind the details of the program under the cursor | fill, 60% |
| `header` | the time bar, one picture across it | fill, 80% |
| `band` | each category band | fill, 80% |
| `channelCell` | the channel column (not the cursor's row) | tile, 35% |
| `cell` | program cells (not the selected one) | tile, 35% |
| `lt` | the lower third, the channel banner over the video | fill, 90% |
| `card` | the channel-change card's backdrop | fill, 100% |
| `box` | dialog boxes and the style panel | fill, 50% |

The whole-screen picture behind the guide is `background` (above). A picture
is cut to its element's corners and shape.

- **fit:** `fill` (covers the area, cropped), `fit` (whole, with space
  around), `stretch`, `tile` (repeated at its own size, for textures),
  `center` (its own size, in the middle), or `frame` (its edges keep their
  size and only the middle stretches, for borders and banner graphics with
  rounded or ornate ends).
- **opacity:** `0.1` to `1`. The area's color shows through what's faint, so
  the color still sets the mood.
- Text sits on top of the pictures, so keep it readable. For cells and the
  channel column, use subtle textures at low opacity (0.2 to 0.4), not photos.
  For the lower third and the card, a darker picture, or a lower opacity over
  a dark `ltBg` or `cardBackdrop`, keeps text clear. A PNG with transparency
  lies over the color as it is.
- Only pictures already on this computer (`.jpg`, `.png`, `.webp`): the user's,
  or ones they point you to. Don't download pictures unless the user gives you
  the file.

In a theme:

```json
"images": {
  "masthead": { "src": "/home/you/Pictures/logo.png", "fit": "fit", "opacity": 1 },
  "lt": { "src": "/home/you/Pictures/banner.png", "fit": "frame", "opacity": 0.95 },
  "cell": { "src": "/home/you/Pictures/grain.png", "fit": "tile", "opacity": 0.25 }
}
```

To put one in without a theme: `setImage lt /home/you/Pictures/banner.png frame 0.95`.
`setImage lt none "" ""` shows none (over the theme's), and `setImage lt theme "" ""`
brings back the theme's.

## Saving a look as a theme

The user can tune the look piece by piece (in the style panel, or by asking
you to `setColor`, `setStyle` and `setImage`) and then keep the result as a
theme. "Save this as a theme called Sunday" becomes `saveTheme "Sunday" ""`.
Everything as it is now goes in: every slot's color, the elements, fonts and
layout (the theme's with the user's over them), every picture (copied into the
theme's folder), and the banner and card settings. The new theme is then the
one on, and the user's changes are part of it, so `yourColorsOnTop` and
`yourStylesOnTop` empty. "Save my changes into Nightshift" (when it's on) is
`saveTheme "Nightshift" ""`. A name another theme already has is refused: ask
the user whether to replace that theme (`removeTheme` it, then save) or pick
another name. Built-in themes can't be saved over.

How every app's screen looks goes in too: the theme's, with the user's
choices for all apps over it (each app's own choices stay out).

A save is written whole and confirmed by the disk before the theme is put on.
`addTheme`, `saveTheme` and `removeTheme` answer a `saving` token: poll
`state` until its `saving` lists that token as `saved` (then it's on, or gone),
`unconfirmed` (it's on disk, but the disk hasn't confirmed it: it isn't put
on yet; tell the user) or `failed` (nothing changed; say `why`). Theme changes
go one at a time: while one is being saved or removed, `theme`, `addTheme`,
`saveTheme`, `removeTheme` and `reset` answer "a theme change is still being
made: try again in a moment". Wait for its outcome, then try again.

## Going back

- "Put it back how it was", "the original", "the default look", "undo all
  the customizing": `reset original`, which gives Premiere with no changes.
- "Keep this theme but undo my changes": `reset theme`.
- One color back to the theme's: `setColor <key> ""`. One part:
  `setStyle <element> theme`. One property of it: `setStyle <element>
  '{"radius": null}'`. Fonts or layout: `setStyle fonts theme`, `setStyle
  layout theme`.
- Changed your mind about a reset: `reset undo`. It brings back the look from
  before the last reset, theme and all. Tell the user that's there after you
  reset.
- A theme you made that they don't like: `theme retro` (or the one they had),
  then `removeTheme <id>` only if they want it gone.

A reset is about the look only. Channels you added stay, and you take them
out with `removeChannels`, when the user asks. Settings like logos stay too.

## Playlists and channels

**Adding an M3U/M3U8 playlist.** Give `addChannels` its URL (a GitHub page for
the file works too) or a file's full path. Its channels come in at once (the
first 3,000), each `#EXTINF`'s `group-title` as its category, `tvg-logo` as its
logo. Its movies and episodes go to the library instead (see Movies, series
and videos on demand). The answer's `note` says how many were added. YouTube channels (links,
`@handles`, names to look up, or a list file: `.txt`, `.csv`, `.json`, a YouTube
subscriptions export) are checked a few at a time: run `status` until `busy` is
false, and its `message` says how it went. Only one `addChannels` runs at a time.

To build a playlist for the user (say, streams they gave you), write an M3U
file and add it by path:

```
#EXTM3U
#EXTINF:-1 tvg-logo="https://example.com/logo.png" group-title="News",Example News
https://example.com/live/news.m3u8
```

**The demo lineup.** Uber TV comes with a ready-made lineup of 163 YouTube
channels in 30 categories (news, weather, space, nature, music, city, beach
and ski cams, kids and family, and more). A first start offers it; the user
can also load it in Settings → Live TV. `demoChannels` says what's in it and
how many aren't in the guide yet; `loadDemoChannels` adds those, in their
categories, and removes nothing. Offer it when the guide has few channels or
the user asks for something to watch, and load it only when they say yes.
The channels come in at once and load their listings over the next few
minutes (`channels` shows them).

**Numbers.** Channels with no category are numbered 1 to 99, then each
category gets its own hundred (101…, 201…) in the guide's order, so filing a
channel under another category renumbers it. `setCategory` answers with the
new numbers. Look numbers up with `channels "<words>"` before you act on them.

**What the guide shows.** `show iptv ""` shows only IPTV channels, all
categories. `show "" "News, Sports"` shows two categories. `show both ""` shows
everything again.

## Rules

- Change only what the user asked for. Ask before removing channels or themes
  (`removeChannels`, `removeTheme`), listings (`removeListings`) or recordings (`removeRecording`), and before `resetColors` or `reset`
  unless the user asked for it. After a reset, say `reset undo` brings it back.
- `open`, `watch` and `multiview` put the guide over the user's whole screen. Use them when
  the user wants to look, or briefly to take a snapshot, and say how to close
  it (Esc, or Turn off at the foot of the nav rail). The user opens and closes it with
  Super + Alt + T (unless changed in Settings) or the TV in the top bar.
- Work only through these commands: no edits to `~/.config/om-pg/`, the
  plugin's files (its apps folders included), or other apps' settings.
