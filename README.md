# Uber TV

A TV-style media center for [Omarchy](https://omarchy.org): YouTube and IPTV
channels on a real program guide, movies and videos on demand, and apps, in
one screen you drive with the keyboard, the mouse, your phone or a touchscreen.

![Home](docs/screenshots/home.jpg)

## Features

- **Live TV guide.** YouTube channels play their videos on a daily schedule,
  so tuning in joins whatever is "on". Live streams play live. IPTV playlists
  (M3U, M3U8) add live channels, with program listings (XMLTV).
- **A demo lineup.** 163 channels in 30 categories, offered on first start.
- **On demand.** Movies and series from your playlists, your channels'
  videos and your own videos, with resume, My List and Continue watching.
- **Search** across channels, shows, movies and videos as you type.
- **Recordings.** Record what's on with one press, or schedule later shows
  and every episode of a series, even with Uber TV closed. Save to your
  Videos folder, another folder or a USB drive. Pause and rewind live TV.
  Both are off until you turn them on.
- **Multiview.** Up to four channels at once, the sound from the one you
  pick.
- **Make it yours.** Seven built-in themes; change any color, shape, font or
  layout. Arrange Home and the nav rail. Full screen or in a window.
- **Mini player** in a corner while you work, and media keys that change
  channel.
- **Phone remote.** Pair a phone on your network: a d-pad, a number pad and
  the guide. It shows when the channel on is recording, and whether the TV
  is paused or behind live, and answers the strip's questions (TURN ON,
  DISMISS).
- **Tablet mode.** On a touchscreen, finger-sized buttons replace the keys
  along the bottom: tap to choose, drag the guide through time, tap the
  picture for its controls, type on an on-screen keyboard. It turns on when
  you touch the screen, and fits a tablet in portrait.
- **Channel lock.** A passcode for the channels you choose.
- **Apps.** Launchers for services like Netflix and HBO Max, and sandboxed
  apps like Jellyfin and Scores. Third-party apps install from signed files.
- **AI agents, if you want them.** A skill that lets Claude Code, Codex and
  others theme the guide, add channels, record shows or write apps.
- **Backups.** Save your channels and settings to one file, and restore them.

## Screenshots

<table>
<tr>
<td><img src="docs/screenshots/live-tv.jpg" alt="Live TV"><br><sub>Live TV: the guide and its preview</sub></td>
<td><img src="docs/screenshots/mini-player.jpg" alt="Mini player"><br><sub>The mini player over your desktop</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/style.jpg" alt="Style panel"><br><sub>The style panel: themes, colors, parts, layout, fonts</sub></td>
<td><img src="docs/screenshots/search-results.jpg" alt="Search results"><br><sub>Search: channels and videos as you type</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/add-channels.jpg" alt="Add channels"><br><sub>Add channels: YouTube, IPTV or a file</sub></td>
<td><img src="docs/screenshots/phone-remote.jpg" alt="Phone remote"><br><sub>Pair your phone as a remote</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/apps.jpg" alt="Apps"><br><sub>Apps</sub></td>
<td><img src="docs/screenshots/search.jpg" alt="Search"><br><sub>Search</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/settings-general.jpg" alt="Settings: General"><br><sub>Settings</sub></td>
<td><img src="docs/screenshots/settings-live-tv.jpg" alt="Settings: Live TV"><br><sub>Settings → Live TV</sub></td>
</tr>
<tr>
<td><img src="docs/screenshots/settings-apps.jpg" alt="Settings: Apps"><br><sub>Settings → Apps</sub></td>
<td></td>
</tr>
</table>

## Install

```bash
omarchy plugin add https://github.com/marcho78/uber-tv.git --enable
```

Open it with **Super + Alt + T**, or the TV in the top bar. The first start
has five starter channels, and asks once each whether to load the demo
channels, turn on apps, and let AI agents help.

Nothing beyond a standard Omarchy install is needed: `yt-dlp`,
`qt6-multimedia` with FFmpeg, `qrencode`, `bubblewrap` and `ssh-keygen` all
come with it. If `omacut` was removed, run
`omarchy pkg add qt6-multimedia qt6-multimedia-ffmpeg`.

## Update

Turn on **update notifications** (a strip asks the first time, or Settings →
About) to hear about new versions and their release notes. **Update now**
there opens a terminal that shows what changes and asks before updating. Or,
in a terminal:

```bash
omarchy plugin update marcho78.om-pg
omarchy restart shell
```

## Uninstall

1. If you turned them on, turn off the **phone remote** (it offers to remove
   its firewall rule) and the **AI agent skill** (it takes its links out of
   your agents' skill folders), both in Settings → General.
2. Remove the plugin:

   ```bash
   omarchy plugin remove marcho78.om-pg
   ```

3. Your channels, settings, themes and apps stay, so a reinstall picks up
   where you left off. To delete them too:

   ```bash
   rm -rf ~/.config/om-pg ~/.local/share/om-pg ~/.local/state/om-pg ~/.cache/om-pg
   ```

   Recordings stay in their folder (`Uber TV Recordings`, in your Videos
   folder unless you chose another), and backups in
   `~/Documents/Uber TV backups`. The keyboard shortcut was never written
   into your Hyprland config; it's gone at your next login.

## Getting started

- **Add channels:** press **A** in the guide and paste, one per line:
  YouTube channel names, links, `@handles` or playlist links; a link to a
  live stream (its channel is added); an M3U or M3U8 playlist link or a
  stream's link; or the path to a playlist, a text list, a lineup (`.json`)
  or your YouTube subscriptions (`subscriptions.csv`). **Ctrl+O** picks a
  file.
- **YouTube, IPTV or both:** press **F**, then **←** **→** on the top row,
  and **Enter**. The same box picks which categories show.
- **Watch:** **Enter** goes full screen, **P** to the mini player. Uber TV
  remembers your last channel, and goes back to it when it opens.
- **Settings** (**,**) holds everything else. Developer mode is hidden:
  press Enter 7 times on *Uber TV* in Settings → About.

## Keys

The footer shows the keys for where you are, and **?** lists them all.
**Super + Alt + T** opens or closes Uber TV from anywhere (change it in
Settings → General).

**The guide**

| Key | Does | Key | Does |
|---|---|---|---|
| ↑ ↓ | Channel (the preview follows) | E | Manage channels |
| ← → | Program, up to 12 hours ahead | Del | Remove a channel |
| PgUp PgDn | Previous / next category | L | Logos on / off |
| Enter | Full screen | M | Mute |
| I or Space | A show's choices: Watch, and Record when Recordings are on | | |
| V | Library: movies, series, videos, recordings | R | Refresh listings, re-plan lineups |
| / | Search | K | Key hints on / off |
| H | Home | T | Phone remote |
| P | Mini player | S | Style: themes, colors, layout |
| F | Categories, and YouTube / IPTV | W | Window or full screen |
| A | Add channels | , | Settings |
| O | Open a channel list file | ? | Every key |
| Esc | Home (or close, with Home off) | | |

**Watching full screen**

| Key | Does |
|---|---|
| ↑ ↓ | Channel up / down |
| Enter or G | Back to the guide |
| I or Space | The banner's choices: Multiview, Record, Pause… (← → choose, Enter picks) |
| J K L | Pause and rewind: back 30 s, pause or resume, forward 30 s |
| P | Mini player |
| M | Mute |
| Esc | TV off, back |

<details>
<summary><b>More keys:</b> Multiview, Home, the library, movies and videos, the mini player, search, apps, managing channels</summary>

**Multiview** (from a channel's banner: I or Space, then Multiview)

| Key | Does |
|---|---|
| ↑ ↓ ← → | Move the sound to another tile (↑ from the top row: Add channel, Layout, Exit and the background's gear) |
| Enter | That tile full screen (I or Space there: its options) |
| PgUp PgDn | The selected tile's channel |
| Del | Take a tile off |
| L | Layout |
| Esc | Exit: the channel with the sound plays full screen |

**Home**

| Key | Does |
|---|---|
| ↑ ↓ ← → | Move |
| Enter | Open, or play |
| G | The guide |
| V | The library |
| C | Customize Home |
| / | Search |
| ← at the left edge | The nav rail (C on it: customize the rail) |
| Esc | Close |

**Library (V)**

| Key | Does |
|---|---|
| ↑ ↓ ← → | Move |
| Enter | Details (Recordings: its choices) |
| Space | Play, or resume (recording now: watch it live) |
| L | Add to / take off My List |
| Tab, or a number | Next tab, or go to one |
| X | Take off Continue watching |
| / | Search |
| V | The guide |
| H | Home |
| Esc | Back |

**Playing a movie or video**

| Key | Does |
|---|---|
| Space, Enter or K | Pause / play |
| ← → or J L | Back / ahead 10 s (with Shift: 1 min) |
| PgUp PgDn | Ahead / back 10 min |
| I, ↑ or ↓ | The player bar |
| Home | From the start |
| P | Mini player |
| Esc | Stop; it remembers where |

**Mini player** (point at it)

| Key | Does |
|---|---|
| ↑ ↓ | Channel up / down |
| G | Back to the guide |
| Enter | Full screen |
| M | Mute |
| Esc | Close |

Drag it to move it, scroll on it to resize it.

**Search (/)**

| Key | Does |
|---|---|
| Type | Channels, shows, movies, videos |
| ↓ | Into the results |
| Enter | Open, watch or play |
| Del | Clear |
| Esc | Back |

**Apps** (on the nav rail, once apps are on)

| Key | Does |
|---|---|
| Enter | Open one, full screen or in a window, like Uber TV |
| I | What it's allowed, and Remove |
| G | Get apps |
| X | Close the one that's on |
| Super + W | In an app: close it, back to the guide |
| / , R | In an app: search it, its settings, load it again |
| C, S | In an app: customize its screen, the style panel |

**Managing channels (E)**

| Key | Does |
|---|---|
| Space | Mark a channel (Shift: its whole category) |
| Shift + ↑ ↓ | Move it within its category |
| N | Rename |
| C | Set its category |
| L | Lock or unlock (the passcode first) |
| Del | Remove the marked ones (or this one) |
| E or Esc | Done |

</details>

## Privacy and security

- Uber TV reaches the network only for what you add: YouTube, your playlists
  and listings, apps you turn on, and update checks if you turn them on.
- Nothing listens on the network unless you turn on the phone remote.
- Apps that run code have no network of their own, and no access to your
  files: Uber TV fetches for them, only from the sites you approved.
- Your settings and secrets are files only you can read, and so are your
  recordings (except on FAT and exFAT drives, which can't keep files
  private). A channel's address, which can hold your provider's login,
  never goes on a command line or next to a recording.
- It asks for your computer's password only for things you start, such as
  the phone remote's firewall rule or turning on third-party apps.

Everything it touches is listed in [Permissions and security](docs/security.md).
To report a problem, see [SECURITY.md](SECURITY.md).

## Documentation

- [The manual](docs/manual.md): every screen and setting
- [Apps](docs/apps.md), and [publishing an app](docs/sources.md); the SDK is
  in `apps/sdk/`
- [AI agents](docs/agents.md) and their commands
- [How it works](docs/how-it-works.md)
- [Changelog](CHANGELOG.md) and [contributing](CONTRIBUTING.md)

## Contributors

Thank you to everyone who's helped build Uber TV. They're also listed in
Settings → About → Contributors.

- [@calledtoconstruct](https://github.com/calledtoconstruct): phone remote pairing fix, and found the listings limits (0.2.1-beta)

## License

[MIT](LICENSE)
