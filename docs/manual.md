# Using Uber TV

Everything the guide does, screen by screen. The [README](../README.md) has the short version.

## First start

The first time Uber TV opens (and after Reset Uber TV), it's in the Premiere
theme with five starter channels, and it asks, one question at a time and
each only once:

1. **Load the demo channels?** 163 YouTube channels in 30 categories: news,
   weather, space, live cams, music and more. **Y** loads them, **N** keeps
   the five. Settings → Live TV → *Load the demo channels* adds them any time,
   skipping the ones you have and removing nothing.
2. **Turn on apps?** See [Apps](apps.md).
3. **Let AI agents help?** See [AI agents](agents.md).

After that, Uber TV remembers the channel you were on: Live TV opens on it,
after a restart too, and if you closed Uber TV while watching a channel full
screen, it opens playing that channel again (a locked one waits for the
passcode).

## Use

It opens on Home (see [Home](#home)), or on the guide with Home turned off in
Settings. In the guide, the preview box plays whichever channel the cursor is
on. The footer shows the essential keys (**K** hides it for a cleaner guide,
and is remembered); **?** lists every key:

| Key       | Does                                   |
|-----------|----------------------------------------|
| ↑ ↓       | Channel (the preview follows)          |
| ← →       | Program (scrolls ahead up to 12 hours) |
| PgUp PgDn | Previous / next category               |
| Enter     | Full screen                            |
| I / Space | A show's choices: Watch, and Record while Recordings are on |
| V         | The library: movies, series, videos, recordings |
| /         | Search                                 |
| W         | In a window, or full screen            |
| H         | Home                                   |
| P         | Mini player (the highlighted channel)  |
| F         | Choose which categories to show        |
| A         | Add channels                           |
| O         | Open a channel list file (with search) |
| E         | Manage channels (see below)            |
| L         | Show or hide channel logos             |
| Del       | Remove the highlighted channel         |
| M         | Mute                                   |
| R         | Refresh listings and re-plan lineups   |
| K         | Hide or show the key hints             |
| T         | Phone remote                           |
| S         | Style: themes, colors, parts, layout, fonts |
| ,         | Settings (and the AI agent skill)      |
| ?         | Every key, in one list                 |
| Esc       | Home (with Home off: turn off and close) |

Watching full screen:

| Key         | Does                      |
|-------------|---------------------------|
| ↑ ↓         | Channel up, channel down  |
| Enter / G   | Guide (the TV keeps playing in the preview box) |
| I / Space   | Channel banner, with its options: [Multiview](#multiview), Record (while Recordings are on), Mini player, Guide, Mute (← → choose, Enter picks; it hides after 10 seconds). ↑ there: the player controls |
| J K L       | [Pause and rewind](#recordings): back 30 s, pause or resume, forward 30 s (off, they offer Turn on); hold J or L, or ← →, to scrub |
| P           | Mini player               |
| M           | Mute                      |
| Esc         | TV off, back to Home or the guide (with Home off: close) |

Clicking a channel watches it; double-clicking a program does too.

Changing channel shows the channel's card for a moment: its logo, number
and name (whether or not logos are on in the grid), in full screen, the
preview box and the mini player, and the full-screen banner carries the logo
too.

## Home

Home is the first screen: the time, what's selected told large at the top,
then rows you move through with the arrows (or the phone remote's):

- **Tiles:** Live TV (the guide), Movies & Series, On Demand, My Videos and My List.
- **Continue watching:** movies and videos you stopped partway through.
- **On now:** the channels you watched last first, with what's on and how far in.
- **New on your channels:** the newest video of each YouTube channel.
- **New in My Videos:** your newest videos.
- **Starting soon:** shows starting in the next hour.
- **My List**, and rows you add: a movie genre, a YouTube channel's videos, or
  what's on in a category.

**Enter** opens what's selected: a tile goes there, a channel plays live, a
movie or video plays from where you stopped. **G** is the guide, **V** the
library, **T** the phone remote, **Esc** closes.

**C** customizes Home, in a panel down the right while Home changes behind it:

- **Screen:** what the big title at the top tells (what's selected, a big
  clock, what's on the channel you watched last, or nothing), where the clock
  goes (left, right or off), and the status chips on or off.
- **Background:** what's selected (its picture, blurred), the guide's picture,
  your Omarchy wallpaper, a picture you pick (*Pick a picture* searches your
  home folder and Omarchy backgrounds), or none. *Darken it* keeps the words
  readable.
- **Rows:** Space turns one on or off, Shift+↑↓ moves it, Enter opens its
  options: its name (yours, or its own), card size (small, medium, large),
  how many cards (all, 6, 12, 24), and their order (as they come, newest or
  oldest first, A to Z). *Add a row* adds a movie genre, a My Videos folder, a
  YouTube channel's videos, what's coming up on a channel (its lineup, or its
  program listings), what's on in a category, your recordings, or your recent searches. Del
  takes off a row you added.
- **Tiles:** which show, and in what order (Shift+↑↓).
- *Back to how Home came* puts it all back.

Home is themed like the rest: its tiles, cards, titles, chips and badges are
parts a theme styles, and a theme can bring Home's background too. Home can be
turned off in Settings (**,**): the guide then opens on the program guide, as
before.

## Full screen or a window

The guide opens full screen, over everything, the Omarchy bar too. **W**
(or Settings → General → *Display mode*) puts it in a window instead:
nearly full screen, maximized under the Omarchy bar, an ordinary window on
its desktop. Go to another desktop to work (SUPER+2, say) and the guide stays
where it was, playing; come back and it's there. Its key on another desktop
brings it to you rather than closing it. **W** again goes back to full screen.
Website apps you open follow it: in a window, maximized under the bar.

**Window** (or **Full screen**) and **Turn off** are at the foot of the nav
rail, under Settings, drawn like its other parts: click one, or go past
Settings with ↓ and press Enter. Nothing sits over the picture: playing full
screen, moving the mouse shows the channel banner (or the player bar), a click
pauses (or shows the banner), a double-click goes back, and the pointer hides
when it's still.

## Keeping the screen awake

Settings → General → *Keep the screen awake* decides when Omarchy's screen
saver and lock wait. Enter picks the next choice:

- **While a video plays** (the first time): a movie, a channel or an app's
  video, in the guide or the mini player. Paused, Omarchy's screen saver and
  lock come as usual.
- **While Uber TV is on:** whenever it's on your screen, playing or not. In a
  window, only while it's on the desktop you're on. Leaving it open keeps
  your computer unlocked.
- **Off:** Omarchy's screen saver and lock come as usual, even during a movie.

It works the way video players do: Uber TV asks Hyprland to hold off idle
while it shows, which Omarchy respects, and that ends when it closes. Your
Omarchy settings (its idle times and its stay-awake switch) are never
changed. Agents can't change this setting.

When Omarchy's own screen saver starts (Uber TV kept nothing awake), Uber TV
steps aside: full screen, it hides until you close the screen saver with a
key, so Omarchy's screen saver and lock work as they do everywhere else. A
phone press doesn't close it yet.

## Screen saver

Like a TV: when nothing's playing and nobody's touched anything for a while,
pictures fill every screen, crossfading with a slow pan and zoom, with the
clock. The first key, mouse move, click, scroll or phone press brings you
straight back to where you were, and does nothing else.

Settings → **Screen saver** (off until you turn it on):

- **Screen saver:** on or off. While it's on, Uber TV keeps your computer
  from locking while it's on screen, so you come back to the TV with no
  password. Close Uber TV, move it to another desktop, or have it go away, and
  Omarchy's screen saver and lock are back. Only you can turn it on.
- **Starts after:** 1, 2, 5, 10, 15 or 30 minutes (5 to begin with) with
  nothing playing (a paused video is nothing) and no key, mouse or phone press.
- **Pictures:** Omarchy's backgrounds (the ones its themes come with, your
  own themes' and any you've added, but not its logo wallpaper), the pictures
  in your folder, or both.
- **Your folder:** `~/Pictures/Screen Saver`. Drop pictures in it (PNG, JPEG
  or WebP, and folders of them, two levels down). Enter opens it in your file
  manager, made the first time. Each picture is checked before it's shown: a
  plain file, never a link, a real picture by its first bytes, at most 40 MB
  and 8192 pixels a side; up to 500. An empty folder shows Omarchy's. Pictures you
  drop in show from the next time it comes on.
- **Use another folder** picks a different one.
- **Change every:** 10, 20, 30 or 60 seconds.
- **Clock:** a corner, the middle, or off. It moves a little now and then, so
  nothing burns in.
- **Show it now** shows it straight away.

Agents can change the wait, the pictures, the timing and the clock
(`setScreenSaver`), but not turn it on or choose the folder.

## Search

**/** (on Home, in the guide or the library), or Search at the top of the
nav rail, opens Search: a big field that takes what you type, and under it
what matches, in rows of cards, as you type:

- **Channels**, by name, number or category, with what's on.
- **On now** and **Later today**: shows on your channels' lineups, by title.
- **Movies & series** from the library (a series once, with its episodes).
- **Videos** from your YouTube channels, and **My Videos**.

Channels and shows follow what the guide shows (its categories and
sources); the library's movies and videos are all searched. **↓** goes into
the results, **↑** from the first row back to the field. **Enter** puts a
channel on, opens a show later today in the guide at its time, opens a movie's
or a series' details, or plays a video; **Space** plays straight away.
Typing again goes back to the field, **Del** clears it, **Esc** goes back.
With nothing typed, your last few searches are there to pick again (Settings
clears them). The phone remote's d-pad moves through the results.

## Library and on demand

**V** opens the library, in tabs (**Tab** switches, a number key goes straight to one):

- **Movies & Series:** what your playlists carry that isn't live TV. When you
  add an M3U playlist, its video files (`.mp4`, `.mkv`…, or an IPTV provider's
  movie and series links) come here, by genre, with their posters and
  descriptions, and episodes named like *Show S01E02* grouped into a series.
  Its live channels go in the guide as before. (Movies added before the
  library had come in as channels; they moved here, and your old channel list
  was kept as `channels.json.before-library`.)
- **On Demand:** every video of your YouTube channels, a row per channel.
- **My Videos:** the video files in your Videos folder (screen recordings,
  downloads, your own) and the folders in it, a row per folder, newest first,
  each with its length and a picture from it. Settings turns it off or picks
  another folder; off, it leaves the library, Home and the nav rail. Nothing
  is copied or uploaded.
- **Recordings:** what you've recorded and what's coming (see
  [Recordings](#recordings)); there while Recordings are on, or there are some.
- **My List:** what you saved (**L** on anything).

Each tab starts with Continue watching (**X** takes something off it).
**Enter** opens an item's details (its poster, description, where you
stopped); **Space** or **Enter** plays it, **R** starts it over (Recordings: see
[Recordings](#recordings)). **H** goes to
Home.

Playing a movie or video:

| Key            | Does                                     |
|----------------|------------------------------------------|
| Space / Enter / K | Pause, play                           |
| ← → or J L     | Back, ahead 10 seconds (Shift: a minute) |
| PgUp PgDn      | Ahead, back 10 minutes                   |
| Home           | From the start                           |
| I / ↑ / ↓      | Show the player bar                      |
| P              | Mini player                              |
| Esc            | Stop, back to the library (it remembers where you were) |

With the mouse, click or drag along the player bar to go there: the time
follows the drag, and the picture jumps when you let go.

Where you stopped is saved every few seconds and when you stop, so it picks
up there next time (also after a restart). The media keys and the phone
remote pause and seek too.

## Style

**S** opens the style panel down the right side of the guide. There's no
shade over the guide, so every change shows as you make it. Every color has
its own slot, and each slot's default comes from the theme. Whatever you pick
is kept on top of the theme, so it carries over when you change themes.

- **Theme:** ← → switch themes. Seven are built in:
  - **Premiere** (the one Uber TV starts with): ink and mint, a screening room. The banner and the channel-change screen fade out instead of sitting in a box.
  - **Retro:** navy blue and marquee yellow, the old cable guide.
  - **Aperture:** a cinematic broadcast package in graphite, warm ivory and amber.
  - **Nightshift:** late-night graphite with warm amber and a teal now line.
  - **OLED:** modern and quiet on near-black, with rounded cells, an Up next list and a red now tick.
  - **Terminal:** tmux-style panes (a channel table, the preview, the lineup of the channel under the cursor) in your Omarchy theme's colors, so it changes when you switch Omarchy themes.
  - **Split-Flap:** a departures board, what's on and its status per channel on flaps that flip when they change.

  Other themes are folders in `~/.config/om-pg/themes/` (a `theme.json`, and
  the pictures it uses): ones an AI agent made for you (see
  [AI agents](agents.md)), ones you saved, or ones you were given (copy the
  folder in). The Theme row shows `+3` when three of your own colors are on
  top of it.
- **Save this look as a theme:** keeps what you see, every color (yours
  included), the picture, the banner and the card, as a theme of its own.
  Name it, then Enter. It's added to the Theme list and put on. Keep the
  name of a theme of yours to save your changes into it. Another taken name
  asks before replacing it, and a built-in theme can't be saved over. Its folder goes in
  `~/.config/om-pg/themes/`, with your pictures copied in, ready to share.

- **Parts: shapes, sizes, text ›** lists every part of the guide, by
  section. Open one to style it:
  - its fill, border and border color, corners, shape (rect, pill, slant,
    arrow, chevron) and slant, shadow (on, blur, drop, color) and padding
  - its text color, font, size, weight, capitals, letter spacing and italic
  - parts with states (the selected program, the current channel, a focused
    field) have an *Editing* row: ← → switches between the part as it is and
    each state.

  ← → change a value, Enter picks a color, Del puts the theme's back, and
  *This part back to the theme's* takes all your changes to it off.
- **Layout ›:** the grid, a channel table or a flap board; the top as the
  title, a thin bar or nothing; where the clock and the preview go; the
  preview tag, a progress bar and the Up next list; divider lines; the key
  hints as a status line; and the grid's and table's sizes.
- **Fonts ›:** the body, display and mono fonts. ← → go through the fonts on
  your computer.
- **Guide:** text, secondary text, accent, the timeline (the now line),
  program cells and their border, channel cells, the selected program, the
  time bar, category bands, the info panel, the preview box and alerts.
- **Background:** the top and bottom of the gradient, and a picture behind
  the guide. The picture can be none, your Omarchy wallpaper (it follows the
  wallpaper when that changes), or one you pick. **Enter** on *Picture* opens
  a search of the pictures in your home folder and your Omarchy theme's
  backgrounds. *Darken the picture* keeps the guide readable over it.
- **Lower third:** the channel banner at the bottom of the full-screen TV.
  You can turn it on or off and set how long it stays up, and change every
  color on it: background, border, number, channel name, show title,
  progress bar and track, clock and show times.
- **Channel card:** the logo card shown when changing channel. You can turn
  it on or off and set how long it stays once the picture is on, and change
  its backdrop, number and name, tuning text and logo frame. With it off, it
  still shows while tuning and for NO SIGNAL.
- **Pictures:** a picture over the color of any of these areas, under its
  text: a logo in place of the title, the info panel, the time bar, category
  bands, the channel column and program cells (subtle textures work best
  there). The lower third, the channel card and boxes have a *Picture* row in
  their own sections. Enter picks one, ← → changes the fit, `[` `]` fade it,
  Del takes it off (first yours, then the theme's). Fits: *fill* (covers,
  cropped), *fit* (whole), *stretch*, *tile* (repeated, for textures),
  *center*, and *frame*, where the edges keep their size and only the middle
  stretches, for borders and banner graphics.
- **Boxes and keys:** dialog boxes and their border, the shade behind them,
  the keycaps (face, letter, edge) and the mini player's bar.

The lower third, card and boxes sections show a sample under the list.

**What a theme can change.** Beyond colors and pictures, a theme styles every
part of the guide on its own, and lays it out:
- **Parts:** program cells, the time bar, category bands, channel cells, the
  info panel, the preview, the lower third, the card, boxes, keycaps and more.
- **Boxes:** a fill (a color or a gradient), a border (all round or on some
  sides), rounded corners, a shape (pill, slanted, arrow, chevron, or any
  outline), a shadow and padding.
- **Text:** its font, size, weight, capitals and letter spacing.
- **Layout:** the time grid, a channel table or a flap board; where the clock
  and the preview go; an Up next list; the grid's sizes; the key hints as a
  status line.

Colors can follow your Omarchy theme. AI agents set all of this for you (see
[AI agents](agents.md)).

| Key in the panel | Does                                                  |
|------------------|-------------------------------------------------------|
| ↑ ↓ PgUp PgDn    | Move                                                  |
| Enter            | Open (Parts, Layout, Fonts, a part), or pick a color (or a picture, on *Picture*) |
| ← →              | Change a value (theme, picture, sizes, shapes, fonts, layout) |
| Space            | Switch on / off (banner, card, shadow, italic, layout switches) |
| Del              | Back to the theme's color or setting                  |
| Esc              | Back to the list before; on the first list, close     |
| S                | Close                                                 |

The color picker has a shade square, a hue strip, a see-through strip, a hex
field and quick swatches. You can use the mouse, or the keys:

| Key in the picker | Does                                          |
|-------------------|-----------------------------------------------|
| ← → ↑ ↓           | Shade (Shift: bigger steps)                   |
| PgUp PgDn         | Hue                                           |
| [ ]               | More / less see-through                       |
| Tab               | Type a hex value (`#rrggbb` or `#aarrggbb`)   |
| Enter             | Keep                                          |
| Esc               | Undo: puts the old color back                 |

Any color can be see-through, for example program cells over a background
picture.

**Going back.** At the bottom of the list (↑ from the top gets there), each
reset needs Enter twice:

- *Reset to <theme>: your changes off* takes your own colors off and puts
  back the theme's picture, banner and card settings, keeping the theme. It
  shows when the theme isn't Premiere.
- *Back to the original look (Premiere)* puts the guide back as it comes:
  Premiere, with its picture, banner and card, and none of your changes.
- *Undo the last reset* brings back the look from before, theme and all.

Del on a single row puts just that back (Del on *Theme*: Premiere). A reset is
about the look only: your themes stay saved, and channels and settings aren't
touched. Your choices are kept in
`~/.config/om-pg/settings.json` (`theme`, `colors`, `images`, `elements`,
`fonts`, `layout`, `background`, `lowerThird`, `card`). A color can also be
set from outside:

```bash
omarchy-shell om-pg setColor timeline "#00ff00"
omarchy-shell om-pg setColor timeline ""        # back to the theme's
```

## Nav rail

Down the left of every screen, an icon for each part: Search, Home, Live TV,
Movies & Series, On Demand, My Videos, Recordings, My List, Apps and Settings, the one you're in lit. Press **←** at
a screen's left edge (the first card on Home or in the library, the current
time in the guide, or on the Settings screen) and it widens with their names;
↑↓ pick, **Enter** goes, **Esc** closes it. Pointing at it widens it too, and
clicking an icon goes there. The phone remote's d-pad works the same. The
shortcut keys (H, G, V, **,**) still work.

What's on it is yours: **C** on the open rail (or *Nav rail* in Settings)
customizes it in a panel beside it, the rail changing as you go. Space turns
an item on or off, Shift+↑↓ moves it, and *Show it* picks always (thin), only
when you go to it, or never. A part that's turned off (Home, when the Home
screen is off; My Videos, when it's off; Recordings, while they're off and there are none; Apps, until apps are on) leaves the rail until it's back on,
and your choice for it stays. Settings is always there.

It's themed like the rest (the rail and its items are parts).

## Settings

**,** (or Settings in the nav rail) opens the Settings screen, laid out like a
TV's: its parts down the left, the settings of the one you're on at the right
in big rows, with switches for what's on or off, and under them what the
focused one does.

- **General:** Home screen on or off, display mode (full screen or a window),
  keeping the screen awake, the shortcut (Super + Alt + T, Super + Alt + V, Alt + G, or none), the TV in
  the top bar on or off, the nav rail, key hints, the splash screen as Uber
  TV turns on (about 9 seconds, any key skips it), the phone remote (pair a
  phone), the AI agent skill, saving a copy of that skill for any AI
  assistant (see [AI agents](agents.md)), Style and themes, and clearing your
  recent searches.
- **Live TV:** channel logos, lineups (daily or latest), program listings,
  the [channel lock](#channel-lock), categories and sources, refreshing the
  listings now, and loading the [demo channels](#demo-channels).
- **Library:** My Videos on or off, its folder, looking for new videos; how
  much is in the library; the movies each playlist brought in, to take out;
  clearing Continue watching; emptying My List. Those last ones need Enter
  twice.
- **Recordings:** on or off, where recordings go, the space kept free,
  YouTube quality, how many at once, starting early and ending late, and
  pause and rewind. See [Recordings](#recordings).
- **Apps:** apps on or off (off until you turn them on, which asks first),
  Get apps, each installed app with its own switch (Space) and details
  (Enter), Check for updates, and Third-party apps with Install a
  third-party app. See [Apps](apps.md).
- **Screen saver:** see [Screen saver](#screen-saver).
- **About:** the version; update notifications (off until you turn them on),
  Check for updates, Update now (when one is out: a terminal that shows what
  changes and asks first) and the release notes; where your settings and lists are
  kept, backing them up (to `~/Documents/Uber TV backups`) and restoring a
  backup; how to reach Developer mode; Contributors, everyone who's helped
  build Uber TV (Enter on one opens their GitHub page); and the credits on the
  nav rail, on or off.
- **Developer:** shown after you press Enter (or click) 7 times on the Uber TV
  row in About,
  and gone again once Developer mode is off: Developer mode and Install an
  unsigned app, for testing an app you're building, and Reset Uber TV, back to
  how it was when first installed (it asks first, and saves a backup).

↑↓ pick a part, **→** or **Enter** goes into it; there ↑↓ move, **Enter**
flips a switch, opens a box or does something, and **←** or **Esc** comes back
out. The rows, switches and parts are themed like the rest (the menu parts in
[Style](#style)); the Customize panels for Home and the rail, the boxes
(categories, the file and folder picker, the phone remote, the key list) and
the style panel use them too.

## Multiview

Up to four channels at once, the picture from each and the sound from one.
Any channel works: live, scheduled (a YouTube channel's videos on its
schedule, joined where the show is now) or IPTV.

**Getting there.** While watching a channel full screen, press **I** or
**Space**: the banner shows its options. **Multiview** is the first; **Enter**
starts it with the channel that's on, and the *Add a channel* list opens
beside it: ↑↓ choose (or type a channel's number to jump to it), **Enter**
adds, **Esc** when you have enough. Esc with nothing added goes back to that
channel.

**Layouts.** Two channels: side by side, or featured. Three: featured (the
first channel big, two beside it), grid, or a row. Four: grid, or featured.
Adding or taking off a channel puts its count's first layout on; **L** (or
*Layout* in the bar) switches.

| Key | Does |
|-----|------|
| ↑ ↓ ← → | Move the sound to the next tile that way (it has the thicker frame and a *Sound* badge) |
| ↑ from the top row | The bar: *+ Add channel*, *Layout*, *Exit Multiview* and the gear (← → choose, Enter picks, ↓ back) |
| Enter | That tile full screen |
| PgUp PgDn | The selected tile's channel (skipping ones on other tiles) |
| Del | Take the tile off (with one left, Multiview closes and it plays full screen) |
| L | The next layout |
| M | Mute |
| K | Hide or show the key hints |
| Esc | Exit: the channel with the sound plays full screen |

**A tile full screen.** ↑↓ change its channel, **I** or **Space** shows its
banner with *Back to Multiview*, *Change channel*, *Take off Multiview* and
*Guide* (that channel in the guide), and **Esc** goes back to the tiles. The
others keep playing.

**The background.** The gear at the end of the bar holds what's behind the
tiles: *As it is* (the theme's), *A color* (the color picker: arrows,
PgUp PgDn for the hue, Enter keeps, Esc leaves it as it was), *The theme's
background* (its picture), or *A custom wallpaper* (your Omarchy wallpaper,
or a picture of your own). The tiles' frames and labels are parts in the
style panel (**S** → *Parts* → MULTIVIEW), and themes and
[AI agents](agents.md) can set all of it.

**Quality.** Each tile asks only for what its size needs: 720p side by side,
480p in a grid or row, 1080p for the big featured tile and 360p for the small
ones, 1080p full screen.

**Media keys and the phone.** Play/Pause pauses and resumes every tile,
Next/Previous change the selected tile's channel, and Stop turns the TV off.
On the phone remote the d-pad, OK and BACK work as the keys (on a
full-screen tile, ▲ opens its banner's choices, ▼ closes them and ◀ ▶ change
its channel), CH▲ CH▼ as PgUp PgDn, ⋯ as I, a number puts that channel on
the selected tile (in the *Add a channel* list it jumps there), GUIDE goes to
the guide, and POWER turns the TV off.

A locked channel asks for the passcode before it goes on a tile, and a tile
whose channel gets locked stops. Turning the TV off, closing Uber TV, or
playing something else stops every tile.

## Recordings

Record what's on to watch later, on this computer.

Recordings are off to start with. A strip at the bottom of Home and the
guide asks once, after the question about update notifications: Y turns
them on, N puts it away (the switch stays in Settings → Recordings).

**Recording.** While watching a channel full screen, press **I** or
**Space** (▲ on the phone remote): **Record** is among the banner's
choices. One press records:

- a channel with listings: to the end of the show, plus the end-late minutes
  (2, unless you change Start early, end late);
- one without (most live channels): for an hour;
- a scheduled YouTube channel: the choice says **Save video**, and the video
  that's on is saved whole, now.

The banner then says **● REC until 9:00**, and its choices become **Stop
recording** and **Until 9:00 ›**: Enter on that one offers the end of the
show, 30 minutes more, an hour, two hours, or **Until I stop — 12 h
maximum** (Esc goes back). Changing channel keeps recording; the guide
shows what's recording (a red **● REC** beside the channel, and the top
line).

Anything worth knowing is written on the Record choice before you press it:
*Uses a 2nd stream from this provider* (some IPTV plans allow one stream at a
time, so watching and recording at once may stop one), and, when it can't
start, why: too many are recording already (Recordings at once), the drive
isn't there, or there isn't enough space.

**Two streams from one provider.** While an IPTV channel records, watching
another channel from the same playlist (or the one recording) takes a second
stream from that provider. The first time, Uber TV asks: on the banner when
you're watching full screen, in a box elsewhere. **Watch anyway**, and it
doesn't ask again while that provider's recordings run; **Stay** keeps what
you had. The guide's preview doesn't play those channels meanwhile (it says
so; Enter asks), and Multiview's *Add a channel* list marks them *2nd
stream*.

**From the guide.** On a show in the guide, **I** or **Space** (⋯ on the
phone) opens its choices. **Enter** still watches.

- **Record:** what's on now, to its end plus the end-late minutes (or an hour without listings); a later show on an
  IPTV channel with listings (5 minutes or longer), scheduled; on a scheduled YouTube channel the
  choice says **Save video**, and the show you picked (its video) is saved now.
- **Record every episode:** that show's series, on that channel (an IPTV
  channel with listings): this
  episode if it's on, then each one the listings have (they reach about a
  day and a half ahead, and come twice a day), never one already recorded
  (by its episode number, else its episode's title).
- On a show already scheduled: **Cancel recording** (an episode of a series
  isn't scheduled again), and **Stop recording this series**; on one
  recording: **Stop recording**.

The cells say what's happening: **Scheduled**, **● Recording** (in red), or
**Conflict**. A channel that's recording has a red **● REC** beside its name
(in the Split-Flap board, in its status column),
and the top of the guide says what's recording (*● Recording Sky News*, or
*● 2 recording*). Two shows back to back on one channel become one recording
(its card names both); a show that would take it past its 12 hours goes on
in a new recording from there. If a playlist changes a channel's link while
it records, the recording follows the new one, in the same file.

**How many at once.** Two record at the same time unless you choose 1, 3
or 4 (Settings → Recordings → *Recordings at once*: each is another stream
and about 3 GB an hour). A show that would be one too many is scheduled as
a **Conflict**, naming the others, and isn't recorded unless one of them is
cancelled (then it's Scheduled again); the Record choice says so before you
press it. The ones scheduled first keep their place.

**Watching recordings.** Library (**V**) → **Recordings**: what needs you
first (Failed, Missed, Incomplete, Conflict, Drive missing), then what's
recording now, then what's coming (**Upcoming**, soonest first), then what's
recorded, newest first. **Enter** (OK on the phone) opens a recording's
choices:

- recorded, or Incomplete: **Play** (**Resume** and **Start over** once you've watched
  some) and **Delete recording…** (Enter twice);
- recording: **Watch live** and **Stop recording** (a YouTube video: **Stop
  saving**);
- still to come: **Cancel recording** and **Watch** its channel now;
- of a series: **Stop recording this series** too;
- Failed, or Incomplete with nothing saved: **Delete…**; Missed: **Take it off the list…**; Drive missing:
  **Take it off the list…** (the file stays on the drive).

**Space** plays it at once; on one still recording, it watches that channel
live. Each card that didn't go as planned says why. Recordings are a row on
Home and an item on the nav rail too (C on Home, or the rail's Customize,
moves or hides them).

**With Uber TV closed.** A recording goes on: it's its own service on this
computer, and the computer doesn't go to sleep while it runs (closing a
laptop's lid still does). A scheduled one starts on time with the guide
closed too (Uber TV checks every 30 seconds while you're logged in), and
joins a show already under way if the computer was asleep when it began.
Recordings run while you're logged in; not at the login screen, after you
log out, or while the computer is asleep or off: one whose show ended
meanwhile is **Missed**. An Omarchy
notification says when one starts and finishes, or why it stopped early,
didn't start or was missed (never what it is: the card in Recordings says).
If the computer can't be kept awake, the banner and the recording's details
say so while it records.

**Where they go.** Settings → **Recordings**: your Videos folder (an *Uber
TV Recordings* folder in it), a folder you choose, or a USB drive (one not
opened yet is opened from here). A drive that isn't plugged in is never
swapped for the computer's own disk: the recording doesn't start, and you're
told why. Recordings on a drive that's unplugged stay listed as *Drive
missing*, and play again when it's back. My Videos leaves the recordings
folder out.

| Setting | Does |
|---|---|
| Recordings | on or off (off takes Record away, and asks first with recordings running or scheduled: they stop or are cancelled; recordings stay, and so does the tab while there are some; a series schedules again once it's back on) |
| Save recordings to | where, with its free space |
| Keep free | a recording stops before the drive gets fuller than this (what's recorded is kept); Auto: 8 GB on a small system disk (your home folder's, under 64 GB), 5 GB anywhere else |
| YouTube quality | 1080p, 720p or 480p (IPTV records as it comes); Auto: 720p on a small system disk, 1080p anywhere else |
| Recordings at once | 1 to 4 (2 to start with): each is another stream (4 to 8 Mbps at 1080p) and about 3 GB an hour; lowering it doesn't stop one recording |
| Start early, end late | none, 1 and 2 minutes (to start with), or 2 and 5 (with listings) |
| Pause and rewind | Off (to start with), 5 min or 30 min: how much of the live channel you watch is kept to pause and go back in (below) |

Recordings are copied as they come, never converted, so they take little of
the computer's power: about 3 GB an hour at 1080p, 1 to 2 at 720p. They're
MPEG-TS files (a saved video is .mkv), playable in any player, and readable
by you alone (except on FAT and exFAT drives, which can't keep files
private). Each has a details file next to it with what its card shows.

**Pause and rewind.** With Settings → Recordings → *Pause and rewind* on (5
or 30 minutes), a live channel you watch (IPTV, or a YouTube channel's live
stream) plays through a rolling buffer on the recordings drive, which keeps
the last 5 or 30 minutes. **J**, **K** and **L** go back 30 s, pause or
resume, and go forward 30 s, and the media keys pause and resume. The
banner says **Live**, or how far behind it you are (*2:15 behind live*),
which also stays on the picture while you're behind.

The **player controls**: full screen, **I** or **Space** (▲ on the phone
remote) shows the banner's choices, and **↑** again (▲ again) the player
controls, like a streaming app's: the bar of what's kept, with a mark where
you are and how far behind live over it, and back 30 s, pause / play and
forward 30 s under it. **Enter** pauses or plays, a tap of **←** or **→**
goes back or forward 30 s, **↓** goes back to the choices, **Esc** hides
them (so do 10 seconds without a key). To go further, **hold ←** or **→**
(or J, L), from the controls or with nothing open: the mark moves, faster
the longer you hold (10 s steps, then 30 s, then a minute), and the picture
jumps there when you let go. Or click or drag along the bar with the mouse.
Change channel during a scrub and it's dropped. A movie's own player bar
works the same: a tap of ← → is 10 s, a hold moves its mark. On the phone,
drag the card's bar (Player, Premium, Dock… show it) and let go. Paused longer
than the buffer holds, it resumes at the oldest part kept; forward past live
is live. Tuning takes a moment longer while it's on (*Starting pause and
rewind…*): the provider still sees one stream, the buffer's. If the stream
stops for a while (*Waiting for the channel…*), it goes back to live when
the stream does. When it can't run (the drive isn't plugged in, can't be
saved to, or is short of space), the channel plays as usual and Pause says
why (*Can't pause: the drive isn't plugged in*). The buffer stays while that
channel is on (full screen or in a window, in the guide's preview, in the
mini player) and
is deleted when you change channel, turn the TV off, or open Multiview, a
video or an app; if Uber TV stops, it's deleted within seconds. It writes to
the drive the whole time you watch (4 to 8 Mbps at 1080p; 30 minutes is
about 1 to 2 GB), and stops before the drive gets fuller than you keep. With
it off, **J**, **K** and **L** (and ↑ on the banner's choices) show *Pause and
rewind is off*, with **Turn on** (5 minutes); ↓ goes back.

**Locked channels.** Recording or scheduling a locked channel asks for the
passcode, as watching does (a show scheduled while it's unlocked still
records later). Its recordings play only once it's unlocked, show no picture
or description while it's locked, and say only *Locked recording* while the
lock hides titles. The files themselves aren't encrypted: the lock is Uber
TV's. A recording stays locked when its channel is removed or renamed, as
the lock itself does.

## Mini player

Press **P** in the guide (for the highlighted channel) or while watching full
screen, and the TV shrinks to a small window that stays on top of everything
while you work, like picture-in-picture on a phone.

- **Drag** it anywhere; **scroll** over it, or drag its top-left corner, to
  resize. Where it sits and how big it is are remembered.
- **Point at it** and it takes the keyboard (a yellow outline shows it has
  it): ↑↓ change channel, M mute, G back to the guide, Enter full screen, Esc
  close. Move the pointer off it and the keyboard goes back to what you were
  doing.
- **Buttons** (shown while you point at it): CH▲, CH▼, MUTE, GUIDE, FULL, ×.
- **GUIDE** (or G) goes back to the program guide with the channel still
  playing in the preview box; **double-click** (or FULL) goes back to full
  screen. The picture keeps playing through either switch.
- **A 2nd stream:** a channel from the same provider as a recording asks
  first, in its bar: **WATCH ANYWAY** (Enter, OK on the phone) or **STAY**
  (Esc, BACK on the phone).

## Media keys

While the TV is on, the guide is a media player like any other (MPRIS), so
your keyboard's media keys and the bar's media widget work with it:
**Next / Previous** change channel (playing a movie or video, ahead 30 seconds and back 10), **Play/Pause** pauses and resumes, and the
widget shows the channel, the show and the channel's logo (or the video's
thumbnail). When the TV is off it steps aside, and the keys go back to your
other players. If another player is also playing, the shell decides which one
the keys control, as with any two players.

## Tablet mode

On a touchscreen, Uber TV works with your fingers. Settings → General →
**Tablet mode**: **Auto** turns it on when you touch the screen, until Uber
TV closes; **On** and **Off** keep it that way. The keyboard, a mouse and the
phone remote work as always: with a mouse, a click still picks and a double
click opens.

- **Buttons** take the key hints' place along the bottom: **Back** first (what
  Esc does), then what fits; **⋯** holds the rest.
- **Tap** to choose, tap again to watch; cards and an app's items open at the
  first tap. **Hold** a show in the grid for its choices. **Drag** the grid
  sideways to move through time; **Now** comes back. **123** types a channel
  number.
- **Watching:** tap the picture for its controls: **Guide**, **CH** ▲ ▼,
  **123**, the banner's choices, and, with pause and rewind on, the bar (drag
  it or tap a spot) with back 30 s, pause and forward 30 s. Tap again, or
  wait, and they go. Movies, app videos, the mini player and Multiview work
  the same way.
- **Typing:** a keyboard comes up from the bottom for any field: letters,
  numbers and the signs of web addresses, **Paste** and **Hide**. The channel
  lock's passcode has its own pad.
- **A tablet in portrait, or a narrow window** (tablet mode or not): the nav
  rail tucks away (☰ opens it), the preview sits beside its details, and the
  grid shows an hour.
- Everything you tap is at least about 9 mm, whatever the screen. Its buttons'
  colors are the theme's (**S** → *Parts* → TABLET MODE).

## Phone remote

Control the guide from any phone's web browser on your network: a remote
with POWER, MUTE, a d-pad, BACK, GUIDE, HOME, one full screen / mini player
button, pause / play, back and forward 30 s, LIVE, channel up and down,
and a number pad (type 101, and you're on channel 101: it goes after a moment, or on GO or OK), plus the
channel list with what each is airing; tap one to watch it. No app. How it's
laid out and how it looks is a template (see below).

On Home and in the library the d-pad moves and OK opens; playing a movie,
← → seek and OK pauses. In the guide, ⋯ opens a show's choices (Watch,
and Record while Recordings are on); on Home, it customizes Home. Watching a channel full screen, ↑
opens the banner's choices (Multiview, Record while Recordings are on, Mini
player, Guide, Mute; ← → choose, OK picks, ↓ or BACK closes
them) and ↑ again the player controls (◀ ▶ 30 s, OK pauses, ↓ back); ← → change the channel, and OK shows the banner. ⋯ does what **I**
does: full screen, the banner's choices (a movie, its player bar); in the
mini player, its bar.

Under what's on, the phone says what the banner does about recording (*● REC
until 9:30 PM*, on the channel that's recording) and pause and rewind
(*Paused*, or how far behind live). The strip's question on Home and the
guide (update notifications, Recordings) shows on the phone too: **TURN ON**
or **DISMISS** answer it.

It is **off** until you turn it on. Press **T** (on Home or in the guide), or
open Settings (**,**) and choose *Phone remote*:

1. **Enter** shows what turning it on means: it opens a network port
   (24750) on this computer for phones on your local network, a paired phone
   works like the TV's keys (channels, playback and the guide's boxes, apps'
   too) and can't reach your files, and, because Omarchy's
   firewall blocks incoming connections, it adds one rule allowing that port
   from your local network.
2. **Enter** again agrees. The system asks for your password for the
   firewall rule (the guide never sees it). Cancel, and nothing changes.
3. Scan the QR code with the phone's camera, or open the address shown and
   type the 6-digit code. Codes last two minutes, work once, and change after
   five wrong tries. The phone stays paired. Only another device pairs or
   presses buttons, never this computer (where any program could read the
   code off the screen), and while the code is showing the guide takes no
   snapshots.

On the same screen (or Settings → General → *Paired phones*), each paired
phone is a row with when it was paired and last used: pick one with ↑↓ and
press **Enter** twice to unpair it (**Del** too, or OK twice on a phone remote).
It needs a new code to pair again. A phone can also unpair itself (⚙ on its
remote page, then **UNPAIR**). **T** turns the remote off: **Enter** also removes the firewall
rule (password again), **N** keeps it. If you move to a network the rule
doesn't cover, the screen says so and **A** allows it.

To add or remove the rule yourself instead:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 24750 proto tcp comment 'om-pg phone remote'
sudo ufw delete allow from 192.168.1.0/24 to any port 24750 proto tcp
```

(with your own network in place of `192.168.1.0/24`). The port can be changed
with `"remote": { "port": … }` in `~/.config/om-pg/settings.json`.

### Remote templates

The whole phone page is a template: which buttons, where, how big, how they
look, and what the card about what's on and the channel list show. Twelve
come with Uber TV:

| Template | |
|---|---|
| Classic | the remote as it was: d-pad, number pad and channel buttons, with play controls |
| Minimal | round keys and the d-pad first; the number pad behind 123 |
| Player | what's on first, with its bar; big pause, rewind and forward |
| Surfer | a big number pad and a tall channel rocker, the guide tab beside the remote |
| Big buttons | few keys, large and high contrast |
| Premium | dark glass and a round d-pad, few soft buttons |
| Techie | monospace, neon lines on cut corners, a status strip and a key grid |
| Pebble | a big round d-pad, back and pause; the rest slides up |
| Swipe | the screen is a touch pad: swipe to move, tap for OK |
| Dock | what's on in large type, with a dock that grows into the full remote |
| Glance | the channel list fills the phone, the remote slides up over it |
| Tiles | four big tiles, like a phone's control center |

Pebble, Swipe, Dock, Glance and Tiles start minimized: the four squares key
shows everything else, the ⌄ key folds it away again. Most templates take
their colors from the TV's theme, so a theme recolors them; Minimal, Premium,
Techie, Pebble and Tiles bring their own.

On the phone, ⚙ (top right) picks this phone's template, shows or hides the
number pad, and makes everything smaller or larger; each phone keeps its own.
**UNPAIR** is there too. On the TV, Settings → General → *Remote template* is
the default, for phones that haven't picked one. While the TV asks for a
channel's passcode, the phone shows a number pad for it, whatever its
template.

Your own templates (an AI agent can make them with the skill) are kept in
`~/.config/om-pg/remotes/`, apart from the TV's themes.

## Managing channels

Press **E** in the guide to manage channels; **E** or **Esc** again when done.

| Key         | Does                                                       |
|-------------|------------------------------------------------------------|
| Space       | Mark or unmark the channel under the cursor (or click it)  |
| Shift+Space | Mark or unmark its whole category                          |
| Shift+↑ ↓   | Move the channel up or down within its category            |
| N           | Rename the channel                                         |
| C           | Set the category of the marked channels (or this one): pick one, or type a new name |
| L           | Lock the marked channels (or this one), or unlock them if they all are, after the passcode ([Channel lock](#channel-lock)) |
| Del         | Remove the marked channels (or this one), after asking     |

Outside manage mode, **Del** removes the channel under the cursor. Everything
is saved to `~/.config/om-pg/channels.json` as you go, which you can also edit
by hand.

## Channel lock

A passcode you set once, and the channels it protects, like a TV's parental
lock. Settings → Live TV → **Channel lock** (the first time, it asks you to
set a passcode: 4 to 8 digits, typed twice):

- **Channel lock:** on or off. Off, nothing is locked; the passcode and the
  list stay.
- **Change the passcode:** the one now, then the new one twice.
- **Locked channels:** your channels, with a search (type a name or a
  number). Enter locks or unlocks one. **L** does the same in the guide, where
  you manage channels (**E**).
- **Unlocks last:** until the TV is turned off (Uber TV closed, or the mini
  player closed), 1 hour or 4 hours.
- **Show titles of locked channels:** off to begin with.

Opening these settings asks for the passcode. Watching a locked channel asks
for it too: Enter on it, its number on the phone, the mini player. Until it's
unlocked, a locked channel shows a lock instead of its logo and preview, its
shows say Locked (in every layout, the info panel, Home and Search; with
**Show titles** on, the titles show but not their pictures or descriptions),
channel up and down skip it, and its videos (On Demand) are left out of the
library, Search and Home; playing one asks for the passcode too. A video
that's also on a channel you left open (a playlist, say) is locked all the
same, and what you watched or saved from a locked channel stays locked after
you rename or remove that channel, until you take it off the lock. One unlock
covers the channel, live and on demand. (Live, a channel you left open still
plays its own lineup: lock it too, to stop that.)

On the phone remote, while the passcode is asked for, the number pad says
PASSCODE: type it there (dots, not digits) and press GO or OK. Like the remote's
other presses, it crosses your local network in plain HTTP. A wrong passcode five times in a row means a minute's wait, longer with
each miss after. When an unlock of 1 or 4 hours runs out, a locked channel
that's playing stops.

**Forgot the passcode?** Press **F** where it's asked for. Resetting forgets
the passcode and the locked channels, and turns the lock off, after this
computer's password (the system's usual prompt), so a child can't do it. If
the lock's file can't be read, no channel plays until it can, and the same
reset is offered.

The passcode itself is never kept: only a scrambled form of it (a salted,
deliberately slow hash), in `~/.config/om-pg/lock.json`, which only you can
read. It's a lock on the TV, not encryption: anyone with your login and a
terminal could delete that file. Agents can see that a channel is locked, and
can't watch, lock or unlock one.

## IPTV

Alongside YouTube, the guide plays IPTV channels from M3U playlists: your
provider's, tvheadend, Jellyfin or Plex live TV, an HDHomeRun, or a free list
like [Free-TV](https://github.com/Free-TV/IPTV). None come with the guide.

Press **A** and paste a playlist's link (a GitHub page for the file works
too), paste the playlist itself, or press **O** to open a `.m3u` / `.m3u8`
file. A link to a single stream adds that one channel. Each channel's
`group-title` becomes its category, its `tvg-logo` its logo; YouTube links in
a playlist become YouTube channels. Up to 3,000 channels per playlist.

IPTV channels are live, and tuning plays the stream directly, at its best
size up to 1080p. With [program listings](#program-listings-epg), a channel's
row shows its shows; without, it's one **● LIVE** block. A stream that drops is retried once; a dead one shows NO
SIGNAL. In the filter box (**F**), **SOURCES** shows YouTube + IPTV, YouTube
only, or IPTV only.

Streams play from wherever the playlist points (http and https only). Because
IPTV links can carry logins, your channel list
(`~/.config/om-pg/channels.json`) is kept readable by you alone.

## Program listings (EPG)

What's on your IPTV channels, show by show, from program listings in
XMLTV, the format nearly every IPTV provider and listings site uses. Add
them in Settings (**,** → Live TV → *Program listings*): a link to an XMLTV
file (`.xml`, `.xml.gz` or `.xml.xz`) or a full path to one. Your provider
may give you one; free ones, by country, are at
[epgshare01.online](https://epgshare01.online/epgshare01/). A playlist that
names its own listings (`url-tvg` at its top) brings them when you add it.

Listings are matched to your channels by their `tvg-id`, then by name within
the same country. A channel of one feed (a Pacific or West one, or a single
station of a network) only takes listings of that feed, so no times are
off; a channel without listings stays a LIVE block. The box shows how many
channels each source matched. They're fetched about twice a day and with
**R**, and kept for today and tomorrow. A fetch that runs out of time (15
minutes) keeps the listings you had, and tries again about twelve hours on.

With listings, an IPTV channel's row has its shows at their times; the info
panel has the show, its times and what it's about; the channel banner has
its times and how far in; Home's *On now* and *Starting soon* and Search's
*On now* and *Later today* include them.

## Categories

A lineup can be plain channels, or channels in categories. With categories,
the grid has a band for each (NEWS, SPORTS, …) and channels get cable-style
numbers: uncategorized channels ("MY CHANNELS") are 1–99, the first category
101 and up, the next 201 and up. **F** picks the categories to show (ALL, or
any set of them); numbers stay the same whatever is showing, and the choice is
remembered in `~/.config/om-pg/settings.json`.

Categories come with the channels you add (see below): a heading line above a
group of links, a `category` column in a CSV, or a `category` field in a
lineup. A channel already in your guide without a category is filed under the
one an import gives it. To move, rename or recategorize, use manage mode (**E**).

## Channel logos

On unless you turn them off: **L** in the guide, or Settings → Live TV
(remembered in `~/.config/om-pg/settings.json`). They show in every layout:
the grid, the channel table and the split-flap board. Each channel's logo is its YouTube avatar,
which comes with the channel listing the guide already loads, so turning
logos on adds no YouTube requests. The image itself (96 px, about 6 KB) is
downloaded once, only when the channel scrolls into view, two at a time and
spaced out, and kept in `~/.cache/om-pg/logos/` for a month. A download that
fails isn't tried again for six hours. Playlists have no logo and show their
initial instead.

## Live channels

When a channel is streaming live (a 24/7 news stream, Lofi Girl, a marathon),
its row is one **● LIVE** block, its card on Home and in Search shows the
stream's picture (fetched again about every 15 minutes), and tuning in plays
the live stream, from the live edge. When the stream ends, the channel goes
back to airing its videos. The guide looks for live streams when it opens
(unless it looked in the last 15 minutes), when listings load, and every 15
minutes while it's open.

**Adding a live stream by its link.** Paste a link to a stream that's live
now (`youtube.com/watch?v=…`, `youtu.be/…` or `youtube.com/live/…`) and its
channel is added, playing that stream while it's live and its videos when it
isn't. With several streams live at once, it plays the one you pasted. A
channel that only streams is added too, and shows NO SIGNAL when it's off
air. A link to a regular video isn't a channel and is refused.

## Channels

In the guide, press **A** and paste any of these (Enter adds, Shift+Enter
starts a new line):

- a list of channel names, one per line, copied from anywhere. Bullets and
  numbering ("1.", "-", "•") are ignored, and commas split names on one line.
  Each name is looked up on YouTube and its first channel result is added, so
  check the summary: it names every channel added
- one or more YouTube links: channels, `@handles` or playlists, one per line
  or separated by spaces. `Name — link` lines name the channel
- a link to a live stream: its channel (see [Live channels](#live-channels))
- an M3U or M3U8 playlist link, or a stream's link (see [IPTV](#iptv))
- either of those in categories: a short heading line on its own above each
  group (or `## News`, `News:`)

```text
News

Sky News — https://www.youtube.com/@SkyNews
DW News — https://www.youtube.com/@dwnews

Food & Cooking

Binging with Babish — https://www.youtube.com/@bingingwithbabish
```

- the path to a list (`~/…` works, quoting and spaces are fine), or press
  **O** in the guide (**Ctrl+O** in the add box) to pick the file instead:
  it lists playlists (`.m3u`, `.m3u8`) and lists (`.txt`, `.csv`, `.tsv`,
  `.json`), newest first, and you type to search by name or folder (or **Tab** to browse a folder at
  a time: **Enter** goes into one, **Backspace** goes back up, all the way to
  `/`, a USB stick too):
  - a text file with links in it
  - a guide lineup, `channels.json` from someone else's guide
  - your YouTube subscriptions: `subscriptions.csv` from
    [Google Takeout](https://takeout.google.com) (choose YouTube, then
    subscriptions), found under `YouTube and YouTube Music/subscriptions/`

A channel list file can be as simple as one link or name per line. As a
CSV, use a name column, a link column and, if you like, a category column
(the header row is optional and skipped; commas, semicolons or tabs all
work):

```csv
name,url,category
My Science,https://www.youtube.com/@veritasium,Science
Maths,@numberphile,Science
Tom Scott,,Education
"Physics, mostly",https://www.youtube.com/@minutephysics,Science
```

The name is what the guide calls the channel (leave it out to use YouTube's).
A row with a name but no link is looked up on YouTube by that name. Quote a
name that has a comma in it.

Each channel is checked first (it needs at least one public video between 5
minutes and 4 hours), four at a time, then added to the bottom of the grid
with its name. Channels already in your guide are skipped, including the
same channel by `@handle` and by channel id. **Del** removes the highlighted
channel.

Your list is kept in `~/.config/om-pg/channels.json`, a list of
`{ "name", "url" }` you can also edit by hand (to rename or reorder) or share;
the guide picks up changes on save. Until you add or remove a channel, the
guide uses the lineup bundled in the plugin's own `channels.json`.

### Demo channels

Uber TV comes with a ready-made lineup: 163 YouTube channels in 30
categories (news, weather, space, nature, music, city, beach and ski cams,
kids and family, and more). The first start offers it; Settings → Live TV →
*Load the demo channels* adds it any time. Channels you already have are
skipped and nothing is removed; each new one comes in loading its listings,
so the whole lineup fills in over a few minutes.

From a script (see [AI agents](agents.md) for every command):

```bash
omarchy-shell om-pg addChannels @veritasium
omarchy-shell om-pg addChannels ~/Downloads/subscriptions.csv
omarchy-shell om-pg channels "news"                 # find channels and their numbers
omarchy-shell om-pg removeChannels 101              # by channel number
```
