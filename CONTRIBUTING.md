# Contributing

Thanks for wanting to help. This guide says where changes belong, the rules
every change follows, and how to test and send one.

Contributions are welcome. Open an issue first, as described below.

## Talk first

- **Bugs:** open an issue with the steps to reproduce, what happened, and what you expected. A snapshot or screenshot helps.
- **Features:** open an issue to agree on the idea before writing code.
- **Big features** start with a written plan in the issue, agreed before any code.
- **Security problems:** never in an issue. See [SECURITY.md](SECURITY.md).

## Where a change belongs: apps first

- **A new feature for everyone should be an app when it can be.** Apps run sandboxed, show the user what they ask for before they're installed, and are drawn by the guide in its own style. Start from the SDK in `apps/sdk/` and the example in `apps/sdk/examples/showcase`.
- **Changes to the guide itself** (its screens, menus and parts) start with an issue.
- **Only the maintainer adds first-party apps** to the catalog. Share your own as a signed app file: make a key with `om-pg-apps app-key`, then `om-pg-apps app-file` (see [publishing an app](docs/sources.md)). People install it as a **third-party app**. **Developer mode** is only for testing an unsigned app while you build it.

## Rules every change follows

- **No new dependencies** beyond Omarchy's base packages: no new QML modules, and no Python beyond the standard library.
- **No manual setup steps.** Installing the plugin is the only step.
- **Network features are off** until the user turns them on.
- **Programs are started by their full path** (`/usr/bin/…`), never found through `PATH`.
- **Every read and every program's output is bounded,** and every wait has a deadline.
- **No `rm -rf`.** Delete only what the guide wrote, by name. The exceptions: Reset Uber TV deletes Uber TV's own three folders after moving them aside (never through a link), and a helper deletes its own private temporary folder.
- **Private files are readable only by the user** (0600, folders 0700), and are written whole: a new file, checked, then swapped in.
- **The plugin never fetches code on its own.** Third-party apps come only from files the user picks, and an update is downloaded only after the user agrees to exactly what will be fetched.

## Security

- **What only the user may do stays that way:** installing, turning on and removing apps, Developer mode, signing in and secrets, the phone remote and the firewall. These need the user's own keys, mouse or paired phone, and are never opened to agents, commands or scripts.
- **Apps stay sandboxed.** All their network goes through the guide's checks, and the guide draws everything they show.
- **No secrets in command lines, logs or answers to agents.**
- **A security fix comes with a test that fails without it.**

### Secure coding checklist

Go through it for every function you change, before asking for review:

1. **Failure paths:** every step that can fail, cleanup and undo included, and the state each leaves. Catch `BaseException` where a cleanup must run (Ctrl-C too), and re-raise.
2. **Check-then-act:** never check a file and then act on its name. Use an atomic step instead: `rename_at` with `RENAME_NOREPLACE` or `RENAME_EXCHANGE`, `O_EXCL`, `os.link`, or a lock held across both.
3. **Concurrent writers:** a second helper run, the guide doing two things at once, a record removed and added again. Installs and removals take the apps folder's lock.
4. **Links:** open with `O_NOFOLLOW` and work through folder descriptors; never chmod, unlink or remove through a path that could have been swapped.
5. **Bounded input:** sizes, counts, decompression, depth and time all have limits.
6. **Half-changed state:** a file saved but its record not, or the reverse; nothing left behind.
7. **True messages:** "nothing changed" and every recovery instruction must match what's really on disk.

Fix the whole class: when you find one instance, look for the others.

## The TV rules

The guide is used from a couch:

- **Everything works with the keyboard and the phone remote.** The mouse is a bonus.
- **New keys show** in the footer if they matter on that screen, and in the **?** list always.
- **Every part can be arranged by the user,** and hides when its feature is off.
- **It stays readable on every theme.** The guide's floors (focus ring, text contrast) aren't for themes to override.
- **Plain words in the interface:** say what something does, not how it's built.

## Code

- **Match the code around you:** its naming, its comment density, and its idioms.
- **Keep changes focused:** one feature or fix per pull request.
- **Commit messages:** a short summary of what changed for the user, then why if it isn't obvious.

## Tests

Every change comes with tests:

- **A regression test for each fix** that fails without it. Prove it: break the code and watch the test fail.
- **No timing guesses:** patch the function the code really calls, and join threads with a deadline.
- **Test the real path.** A stand-in for the function you changed proves only the stand-in: run the guide's own function, as `tests/look.test.mjs` does with Guide.qml's, or the helper itself.
- **Run suites one at a time,** with a private temp folder (`TMPDIR=…`) and `nice -n 19`; running many at once slows the computer to a crawl.
- **Mutating the Python helpers?** Set `PYTHONDONTWRITEBYTECODE=1` and clear `bin/__pycache__` and `lib/__pycache__`, or a stale compiled copy runs instead.

All of these pass before a pull request:

```bash
node tests/schedule.test.mjs
node tests/look.test.mjs      # element styles, layout and fonts: checks, layering, the APPS parts following their twins, and where the picture behind came from
node tests/appnav.test.mjs    # an app's screens: the arrows, grids of their own width, your place kept
node tests/applooks.test.mjs  # how an app's screen is laid out: the looks and who decides what, the shape a row learns, ring, title and strip contrast, the floors
node tests/appbudget.test.mjs # which running app makes room for another
node tests/appasks.test.mjs   # app origin, consent and withdrawal wording; command output stays read-only
node tests/shortcut.test.mjs  # the guide's own shortcut never counts as taken
node tests/awake.test.mjs     # when the screen is kept awake: off, while a video plays, while Uber TV is on; Omarchy's own screen saver given room
node tests/saver.test.mjs     # the screen saver: its settings, its pictures, when it may come, what an agent may change
node tests/channellock.test.mjs   # the channel lock: which channels (by address, then name), blocked or not, typing a passcode
node tests/multiview.test.mjs     # Multiview and the guide: the media player while it's up, a saved theme keeping its background, the agent commands
node tests/playback.test.mjs      # every player's sound follows the system's output; Home is made only while it's on screen
node tests/dvr.test.mjs           # Recordings, the guide's side: what Record records, the stop times, the banner's and a recording's choices, the lock, the agent commands
node tests/timeshift.test.mjs     # pause and rewind, the guide's side: what the buffer takes, each move a new open, the clock, falling back only once the writer's gone, the words, the agents
node tests/remotepage.test.mjs    # the phone remote's page: a number on GO or OK, the passcode as dots, sent as text
node tests/files.test.mjs     # a channel list that couldn't be read is never saved over, and the guide says so
node tests/clock.test.mjs     # the TV day and the grid in local time: clock changes, quarter-hour time zones
node tests/seek.test.mjs      # a burst of skips makes one seek a gap (a flood stalled the shell); playAt plays from a moment
python3 tests/apps.test.py    # installing apps: good ones, and ones that try to get past the checks
python3 tests/appfiles.test.py   # signed app files, updates, withdrawals, transactions and publisher workspaces
python3 tests/apptransactions.test.py   # install transactions, package caps, no-replace renames and cleanup races
python3 tests/apprun.test.py  # the app helper: misbehaving apps, escaping requests, the sandbox, try's output
python3 tests/appstate.test.py   # Apps.qml in a shell of its own, against the real helper
python3 tests/library.test.py    # Library.qml in a shell of its own: a library or history that couldn't be read is never saved over
python3 tests/bytecode.test.py   # the helpers write no .pyc into the plugin's folder (run it without PYTHONDONTWRITEBYTECODE)
python3 tests/themes.test.py  # themes saved as one confirmed transaction, and pictures you pick
python3 tests/update.test.py  # Uber TV's own updates: version tags, release notes, git's output bounded
python3 tests/backup.test.py  # backups, restore and reset, in a throwaway home: what a backup holds, bad ones refused, a failed restore put back
python3 tests/snapshots.test.py   # snapshot files put in place whole, and the guard's text fields
python3 tests/saver.test.py   # the screen saver's pictures: links, fakes, sizes, depth, the cap, Omarchy's folders, your folder made only at home
python3 tests/lock.test.py    # the channel lock's passcode: only a hash, changing it, wrong tries slowing down, a sound file
python3 tests/streamer.test.py   # the streamer's playlists: the height asked for, the cache keeping each quality apart, ?h= checked
python3 tests/dvr.test.py     # the recorder: places checked, drives found again, the relay against hostile playlists (with real ffmpeg), the state under its lock, a recording end to end
python3 tests/dvrbuffer.test.py   # pause and rewind's buffer: the published playlist and what's deleted, the server, the helper, and end to end with real ffmpeg (a new address, a swapped folder, too little space, the lease)
python3 tests/epg.test.py     # program listings: plain, gzip and xz; the .xz memory cap, the unpacked cap, flat memory, the run's time limit
python3 tests/remote.test.py  # the phone remote's commands: the passcode as text, 4 to 8 digits, only from a paired phone; pairing only from a phone, and the device list saved under one lock
python3 tests/jellyfin.test.py tests/appmedia.test.py tests/appplayback.test.py   # Jellyfin, media checks, playback
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/qml   # the guide's side
```

- **Checks that need real drawing** (corners cut under a radius, a circle, a slant or a path) skip in Qt's software renderer. Run `QT_QPA_PLATFORM=wayland /usr/lib/qt6/bin/qmltestrunner -input tests/qml/tst_appscreen.qml` in your session to see them pass. It opens a window for a few seconds.
- **Then try it on the real guide:** restart the shell (`omarchy restart shell`), and check the shell log has no errors from the guide.

## Docs

When behavior changes, the docs change with it:

- [the manual](docs/manual.md), or the right page in `docs/`, and the README if it's a headline feature;
- the agent skill (`skills/program-guide/SKILL.md`), whose command table must match the real commands;
- [the changelog](CHANGELOG.md), under the version being worked on.

## AI-assisted contributions

Welcome, as long as you stand behind them:

- **Understand it:** know what the change does, why, and how it behaves, and have been involved in it.
- **Try it:** run it on the guide, and run the tests.
- **Answer for it:** be able to answer questions about it in review.
- **Say so:** mention in the pull request that AI tools were used.

An agent working on the guide follows the agent skill and these rules.

## Pull requests

Send pull requests to the `dev` branch; `main` only gets releases.

Before you send one:

- [ ] the issue it closes, or the plan it follows
- [ ] all the tests pass, and new behavior has tests
- [ ] tried on the real guide
- [ ] the docs, the skill and the changelog updated
- [ ] AI tools mentioned, if any were used

## License

By contributing, you agree that your contribution is licensed under the
project's [MIT license](LICENSE).
