#!/usr/bin/python3
"""The phone remote's commands (bin/om-pg-remote), through its real request
handler with the request stood in: /usr/bin/python3 tests/remote.test.py

The channel lock's passcode, typed on the phone, comes as "code" with its
digits as text (a leading 0 counts), 4 to 8 of them, only from a paired
phone; anything else is refused before it reaches the guide."""

import importlib.machinery
import importlib.util
import io
import json
import os
import pathlib
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_loader = importlib.machinery.SourceFileLoader("om_pg_remote", os.path.join(ROOT, "bin", "om-pg-remote"))
_spec = importlib.util.spec_from_loader("om_pg_remote", _loader)
remote = importlib.util.module_from_spec(_spec)
_loader.exec_module(remote)

# The import read the user's remotes.json. Point at a temp folder before
# anything saves, and don't touch that file.
_dir = pathlib.Path(tempfile.mkdtemp())
remote.CONFIG = _dir
remote.CACHE = _dir
remote.DEVICES = _dir / "remotes.json"
remote.devices = []
remote.pairing = {"on": False, "code": "", "link": "", "expires": 0, "tries": 0, "qr": ""}

failures = 0


def check(name, cond, detail=""):
    global failures
    if not cond:
        failures += 1
    print(("ok   " if cond else "FAIL ") + name + ("" if cond or detail == "" else "  " + str(detail)[:300]))


def post(body, paired=True):
    """One POST /api/cmd from a phone on the network: what it answered, and
    what reached the guide"""
    said, answered = [], []
    remote.say = said.append
    h = remote.Handler.__new__(remote.Handler)
    h.path = "/api/cmd"
    h.client_address = ("192.168.1.20", 50000)
    h.private = lambda: True
    h.from_here = lambda: False
    h.same_origin = lambda: True
    h.body = lambda: body
    h.device = lambda: {"id": "phone"} if paired else None
    h.json = lambda code, data, headers=None: answered.append((code, data))
    h.send = lambda code, *a, **k: answered.append((code, None))
    h.do_POST()
    return answered, said


answered, said = post({"cmd": "code", "digits": "0123"})
check("a paired phone's passcode reaches the guide as text, a leading 0 and all", said == [{"command": {"cmd": "code", "digits": "0123"}}] and answered == [(204, None)], (answered, said))
for bad in ["123", "123456789", "12a4", "", None, 1234, ["1234"], "１２３４"]:
    answered, said = post({"cmd": "code", "digits": bad})
    check("refused: %r" % (bad,), not said and answered and answered[0][0] == 400, (answered, said))
answered, said = post({"cmd": "code", "digits": "2468"}, paired=False)
check("an unpaired phone's passcode never reaches the guide", not said and answered and answered[0][0] == 401, (answered, said))
answered, said = post({"cmd": "tune", "number": 101})
check("the other commands are as they were (tune)", said == [{"command": {"cmd": "tune", "number": 101}}], said)

HERE = "Pair and press buttons from your phone, not from this computer."


def get(path, here=False, headers=None):
    """One GET, with private, from_here and the answer stood in"""
    answered = []
    h = remote.Handler.__new__(remote.Handler)
    h.path = path
    h.client_address = ("192.168.1.20", 50000)
    h.private = lambda: True
    h.from_here = lambda: here
    h.headers = headers or {}
    h.json = lambda code, data, headers=None: answered.append((code, data))
    h.send = lambda code, *a, **k: answered.append((code, None))
    h.do_GET()
    return answered


remote.say = lambda message: None
link = "phone-link"
remote.devices = []
remote.pairing.update(on=True, code="111111", link=link, expires=time.time() + 120, tries=0, qr="")
answered = get("/?pair=" + link, here=True)
check("a QR link opened on this computer is refused, and the link stays valid",
      answered == [(403, {"error": HERE})] and remote.devices == [] and remote.pairing["link"] == link,
      (answered, remote.pairing["link"], remote.devices))

remote.devices = []
remote.pairing.update(on=True, code="222222", link=link, expires=time.time() + 120, tries=0, qr="")
answered = get("/?pair=" + link, here=False)
check("a QR link opened on a phone pairs it, and the link is used once",
      answered == [(303, None)] and len(remote.devices) == 1 and remote.pairing["link"] != link,
      (answered, len(remote.devices)))

token = "stolen-token"
seen = 1
remote.devices = [{"id": "abcd1234", "hash": remote.digest(token), "name": "Phone", "added": 1, "seen": seen}]
answered = get("/api/state", here=True, headers={"Cookie": "omt=" + token})
check("a page on this computer can't use a paired phone's token",
      answered == [(403, {"error": HERE})] and remote.devices[0]["seen"] == seen,
      (answered, remote.devices[0]["seen"]))

answered = get("/", here=True)
check("the remote page still opens on this computer", answered == [(200, None)], answered)

saves = []
real_save = remote.save_devices


def wrapped_save():
    assert remote.lock._is_owned() is True
    saves.append(True)
    real_save()


remote.save_devices = wrapped_save
remote.add_device("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit Safari")
check("add_device saves the list while it holds the lock", saves == [True], saves)

saves.clear()
remote.devices = [{"id": "abcd1234", "hash": remote.digest("tok"), "name": "Phone", "added": 1, "seen": 0}]
h = remote.Handler.__new__(remote.Handler)
h.headers = {"Cookie": "omt=tok"}
h.device()
check("a phone seen again is saved while the lock is held", saves == [True] and remote.devices[0]["seen"] != 0, saves)

mode = os.stat(remote.DEVICES).st_mode & 0o777
parts = [n for n in os.listdir(remote.CONFIG) if n.endswith(".part")]
check("remotes.json is readable by you alone and no partial file remains",
      mode == 0o600 and parts == [], (oct(mode), parts))

remote.network = {}
remote.pairing["on"] = True
remote.new_code()
qr = remote.pairing["qr"]
qr_mode = os.stat(qr).st_mode & 0o777 if qr else 0
check("the pairing QR code is readable by you alone",
      bool(qr) and os.path.dirname(qr) == str(remote.CACHE) and qr_mode == 0o600,
      (qr, oct(qr_mode) if qr else None))

# ---- remote templates and each phone's choices -------------------------------

remote.save_devices = real_save
said = []
remote.say = said.append


def guide_sends(message):
    """What the guide sends over stdin, as listen() takes it"""
    if isinstance(message.get("templates"), dict):
        remote.take_templates(message)
    if isinstance(message.get("prefs"), dict):
        remote.guide_prefs(message["prefs"], message.get("req"))


TPL = {"classic": {"id": "classic", "name": "Classic", "pad": "on"},
       "minimal": {"id": "minimal", "name": "Minimal", "pad": "off"},
       "player": {"id": "player", "name": "Player", "pad": "off"}}
LIST = [{"id": "classic", "name": "Classic", "description": "Today's remote"},
        {"id": "minimal", "name": "Minimal", "description": "Round keys"},
        {"id": "player", "name": "Player", "description": "Card first"}]

rev0, ver0 = remote.templates["rev"], remote.state["version"]
guide_sends({"templates": dict(TPL, **{"Bad ID": {"id": "x"}, "nodict": 5, "../x": {}}),
             "list": LIST + [{"id": "gone", "name": "Gone"}, {"id": "player", "name": "Twice"}, "junk", {"id": "minimal", "name": 7}],
             "default": "minimal", "rev": 3})
check("templates from the guide: kept, malformed ids and entries dropped",
      sorted(remote.templates["templates"]) == ["classic", "minimal", "player"], sorted(remote.templates["templates"]))
check("the list keeps only rows for templates sent, once each, in the guide's order",
      [r["id"] for r in remote.templates["list"]] == ["classic", "minimal", "player"] and remote.templates["list"][2]["name"] == "Player",
      remote.templates["list"])
check("a new set bumps remoteRev and wakes the event stream",
      remote.templates["rev"] == rev0 + 1 and remote.state["version"] == ver0 + 1, (remote.templates["rev"], remote.state["version"]))
check("the default the guide named", remote.templates["default"] == "minimal")
guide_sends({"templates": dict(TPL), "default": "No Good"})
check("a bad default falls back to classic; no list: each one's own name",
      remote.templates["default"] == "classic" and [r["name"] for r in remote.templates["list"]] == ["Classic", "Minimal", "Player"],
      (remote.templates["default"], remote.templates["list"]))
guide_sends({"templates": dict(TPL), "list": LIST, "default": "classic", "rev": 4})

check("an older phone entry has no prefs yet: the default, the template's pad, size 0",
      remote.prefs_of({"id": "x"}) == {"template": None, "pad": None, "size": 0}
      and remote.prefs_of({"prefs": {"template": "../x", "pad": "maybe", "size": True}}) == {"template": None, "pad": None, "size": 0})

TOK = "phone-token"
remote.devices = [{"id": "p1", "hash": remote.digest(TOK), "name": "Phone", "added": 1, "seen": int(time.time())},
                  {"id": "p2", "hash": remote.digest("other"), "name": "Other", "added": 1, "seen": int(time.time()),
                   "prefs": {"template": "player", "pad": "on", "size": -1}}]
rows = remote.device_rows()
check("the devices the guide hears carry each phone's prefs",
      rows[0]["prefs"] == {"template": None, "pad": None, "size": 0} and rows[1]["prefs"] == {"template": "player", "pad": "on", "size": -1}, rows)


def get_full(path, here=False, token=TOK):
    """One GET from a paired phone: (code, body, kind, headers) of each answer"""
    answered = []
    h = remote.Handler.__new__(remote.Handler)
    h.path = path
    h.client_address = ("192.168.1.20", 50000)
    h.private = lambda: True
    h.from_here = lambda: here
    h.headers = {"Cookie": "omt=" + token} if token else {}
    h.json = lambda code, data, headers=None: answered.append((code, data, "application/json", headers))
    h.send = lambda code, body=b"", kind="application/json", headers=None: answered.append((code, body, kind, headers))
    h.do_GET()
    return answered


def post_remote(body, path="/api/remote", token=TOK):
    """One POST from a paired phone, the real device check: what it answered, what the guide heard"""
    said.clear()
    answered = []
    h = remote.Handler.__new__(remote.Handler)
    h.path = path
    h.client_address = ("192.168.1.20", 50000)
    h.private = lambda: True
    h.from_here = lambda: False
    h.same_origin = lambda: True
    h.headers = {"Cookie": "omt=" + token} if token else {}
    h.body = lambda: body
    h.json = lambda code, data, headers=None: answered.append((code, data))
    h.send = lambda code, *a, **k: answered.append((code, None))
    h.do_POST()
    return answered, list(said)


a = get_full("/api/remote")
check("GET /api/remote: a phone following the default gets it, with its prefs and the list",
      a[0][0] == 200 and a[0][1]["id"] == "classic" and a[0][1]["template"] == TPL["classic"] and a[0][1]["prefs"]["template"] is None
      and [r["id"] for r in a[0][1]["list"]] == ["classic", "minimal", "player"] and a[0][1]["rev"] == remote.templates["rev"], a)
a = get_full("/api/remote", token="other")
check("a phone's own choice wins", a[0][1]["id"] == "player" and a[0][1]["template"]["name"] == "Player", a)
remote.devices[1]["prefs"]["template"] = "gone"
a = get_full("/api/remote", token="other")
check("its choice gone: the default", a[0][1]["id"] == "classic", a)
remote.templates["default"] = "removed"
a = get_full("/api/remote", token="other")
check("the default gone too: classic", a[0][1]["id"] == "classic", a)
saved_templates = remote.templates["templates"]
remote.templates["templates"] = {"minimal": TPL["minimal"]}
a = get_full("/api/remote", token="other")
check("classic not sent either: none (the page draws its own)", a[0][1]["id"] is None and a[0][1]["template"] is None, a)
remote.templates["templates"] = saved_templates
remote.templates["default"] = "classic"
remote.devices[1]["prefs"]["template"] = "player"
check("unpaired: refused", get_full("/api/remote", token="nobody")[0][0] == 401)
check("from this computer: refused", get_full("/api/remote", here=True)[0][0] == 403)
a = get_full("/api/state")
check("/api/state carries remoteRev", a[0][0] == 200 and a[0][1].get("remoteRev") == remote.templates["rev"], a)

# a phone picks its own
saves = []


def locked_save():
    saves.append(remote.lock._is_owned())
    real_save()


remote.save_devices = locked_save
rev = remote.templates["rev"]
a, s = post_remote({"template": "minimal"})
check("a phone picks a template: saved under the lock, its number pad setting comes along",
      a == [(200, {"ok": True, "prefs": {"template": "minimal", "pad": "off", "size": 0}})] and saves == [True], (a, saves))
check("the guide hears the devices, and remoteRev moves",
      any("devices" in m and m["devices"][0]["prefs"]["template"] == "minimal" for m in s) and remote.templates["rev"] == rev + 1, (s, remote.templates["rev"]))
on_disk = json.load(open(remote.DEVICES))["devices"][0].get("prefs")
check("and it's in remotes.json", on_disk == {"template": "minimal", "pad": "off", "size": 0}, on_disk)
a, s = post_remote({"pad": "on", "size": 2})
check("then the pad and the size", a[0][1]["prefs"] == {"template": "minimal", "pad": "on", "size": 2}, a)
a, s = post_remote({"template": "minimal"})
check("picking the same template again keeps its pad", a[0][1]["prefs"]["pad"] == "on", a)
a, s = post_remote({"template": "player", "pad": "on"})
check("a new template with a pad given: the pad given", a[0][1]["prefs"] == {"template": "player", "pad": "on", "size": 2}, a)
a, s = post_remote({"template": "classic"})
check("a new template without one: its own", a[0][1]["prefs"]["pad"] == "on", a)
rev = remote.templates["rev"]
saves.clear()
for bad, why in [({"template": "gone"}, "a template not sent"), ({"template": None}, "no template"), ({"template": 5}, "a number"),
                 ({"pad": "maybe"}, "pad maybe"), ({"pad": None}, "pad null"), ({"size": 3}, "size 3"), ({"size": -3}, "size -3"),
                 ({"size": True}, "size true"), ({"size": "1"}, "size as text"), ({"size": 1.5}, "size 1.5"), ({}, "nothing"),
                 ({"name": "x"}, "only unknown keys")]:
    a, s = post_remote(bad)
    check("refused: " + why, a and a[0][0] == 400 and not s, (a, s))
check("nothing refused was saved, and remoteRev stayed", saves == [] and remote.templates["rev"] == rev, (saves, remote.templates["rev"]))
a, s = post_remote({"template": "minimal"}, token="nobody")
check("an unpaired phone can't", a and a[0][0] == 401 and not s, a)

# unpaired between the check and the save: nothing is saved for it
d1 = remote.devices[0]
remote.devices.remove(d1)
p, why = remote.change_prefs(d1, {"size": 1})
check("a phone unpaired meanwhile: refused", p is None and why == "that phone isn't paired" and saves == [], (p, why))
remote.devices.insert(0, d1)

# a save that fails changes nothing


def failing_save():
    raise OSError("disk full")


remote.save_devices = failing_save
before = dict(d1["prefs"])
rev = remote.templates["rev"]
a, s = post_remote({"size": -2})
check("a save that fails: refused, the prefs as they were, remoteRev unmoved",
      a and a[0][0] == 400 and d1["prefs"] == before and remote.templates["rev"] == rev and not s, (a, d1["prefs"]))
remote.save_devices = locked_save

# the TV or an agent sets a phone's prefs
said.clear()
saves.clear()
rev = remote.templates["rev"]
guide_sends({"prefs": {"id": "p2", "template": "minimal"}, "req": 7})
check("from the guide: answered once saved (under the lock), then the devices, then remoteRev",
      said[0] == {"done": 7, "ok": True, "prefs": {"template": "minimal", "pad": "off", "size": -1}} and "devices" in said[1]
      and saves == [True] and remote.templates["rev"] == rev + 1, (said, saves))
said.clear()
guide_sends({"prefs": {"id": "p2", "template": "classic", "keepPad": True}, "req": 8})
check("a move onto another template (keepPad) leaves the pad and size", said[0]["prefs"] == {"template": "classic", "pad": "off", "size": -1}, said)
said.clear()
guide_sends({"prefs": {"id": "p2", "template": None, "pad": None}, "req": 9})
check("template and pad null: back to the default and its pad", said[0]["ok"] and said[0]["prefs"]["template"] is None and said[0]["prefs"]["pad"] is None, said)
for msg, why in [({"id": "nope", "size": 1}, "an unknown phone"), ({"id": "p2", "template": "gone"}, "a template not sent"),
                 ({"id": "p2", "size": 9}, "a bad size"), ({"id": "p2", "pad": "sideways"}, "a bad pad"), ({"id": 5, "size": 1}, "an id not text"),
                 ({"id": "p2"}, "nothing to change")]:
    said.clear()
    guide_sends({"prefs": msg, "req": 11})
    check("from the guide, refused with why: " + why, len(said) == 1 and said[0]["done"] == 11 and said[0]["ok"] is False and said[0]["error"], said)
said.clear()
guide_sends({"prefs": {"id": "p2", "size": 1}, "req": "x"})
check("a request number that isn't one: answered with done null", said[0]["done"] is None and said[0]["ok"], said)

# the event stream carries remoteRev, and a bump wakes it at once
import threading

writes, stop = [], threading.Event()


class Wire:
    def write(self, b):
        writes.append(b)

    def flush(self):
        pass


h = remote.Handler.__new__(remote.Handler)
h.wfile = Wire()
h.send_response = lambda *a: None
h.send_header = lambda *a: None
h.end_headers = lambda: None
h.device = lambda: None if stop.is_set() else {"id": "p1"}
th = threading.Thread(target=h.events, daemon=True)
started = time.time()
th.start()
for _ in range(100):
    if writes:
        break
    time.sleep(0.02)
stop_after = len(writes)
remote.bump_rev()
for _ in range(100):
    if len(writes) > stop_after:
        break
    time.sleep(0.02)
stop.set()
remote.bump_rev()
th.join(3)
payloads = [json.loads(w[6:].decode()) for w in writes if w.startswith(b"data: ")]
check("each event carries remoteRev, and a bump reaches an open stream at once",
      len(payloads) >= 2 and payloads[1]["remoteRev"] == payloads[0]["remoteRev"] + 1 and time.time() - started < 5,
      ([p.get("remoteRev") for p in payloads], time.time() - started))

# fonts: a fixed table, nothing from the address reaches a path
fonts = pathlib.Path(tempfile.mkdtemp())
remote.FONT_DIR = fonts
(fonts / "DMMono-Regular.ttf").write_bytes(b"\x00\x01\x00\x00font")
(fonts / "secret.txt").write_bytes(b"not for phones")
os.symlink(fonts / "secret.txt", fonts / "Orbitron.ttf")
with open(fonts / "DMMono-Medium.ttf", "wb") as f:
    f.truncate(remote.MAX_FONT + 1)
a = get_full("/api/font/dm-mono")
check("a font Uber TV ships: served as font/ttf, cached", a == [(200, b"\x00\x01\x00\x00font", "font/ttf", {"Cache-Control": "max-age=86400"})], a)
for path, why in [("/api/font/comic-sans", "an id not in the table"), ("/api/font/../secret.txt", "../"),
                  ("/api/font/%2e%2e%2fsecret.txt", "encoded separators"), ("/api/font/dm-mono%2f..%2fsecret", "an encoded slash"),
                  ("/api/font/secret.txt", "a file's name"), ("/api/font/orbitron", "a link in the fonts folder"),
                  ("/api/font/dm-mono-medium", "a font bigger than 1 MB"), ("/api/font/", "no id")]:
    a = get_full(path)
    check("font refused: " + why, a and a[0][0] == 404, a)
check("font: unpaired refused", get_full("/api/font/dm-mono", token="nobody")[0][0] == 401)
check("font: from this computer refused", get_full("/api/font/dm-mono", here=True)[0][0] == 403)

# the phone's new commands, and seek's checks
remote.say = said.append
for cmd in ("playpause", "rewind", "forward", "live", "window", "home", "full", "mini"):
    answered, s = post({"cmd": cmd})
    check("the command reaches the guide: " + cmd, s == [{"command": {"cmd": cmd}}] and answered == [(204, None)], (answered, s))
for at, play, want in [(0.5, 3, 0.5), (0, 0, 0.0), (1, 12, 1.0), (0.25, 2 ** 53 - 1, 0.25)]:
    answered, s = post({"cmd": "seek", "at": at, "play": play})
    check("seek at %r play %r" % (at, play), s == [{"command": {"cmd": "seek", "at": want, "play": play}}] and answered == [(204, None)], (answered, s))
for at, play, why in [(-0.1, 1, "at below 0"), (1.5, 1, "at past 1"), (True, 1, "at true"), ("0.5", 1, "at as text"), (None, 1, "no at"),
                      (float("nan"), 1, "at NaN"), (float("inf"), 1, "at infinite"), (0.5, -1, "play below 0"), (0.5, 1.5, "play not whole"),
                      (0.5, True, "play true"), (0.5, "3", "play as text"), (0.5, None, "no play"), (0.5, 2 ** 53, "play too big")]:
    answered, s = post({"cmd": "seek", "at": at, "play": play})
    check("seek refused: " + why, not s and answered and answered[0][0] == 400, (answered, s))
h = remote.Handler.__new__(remote.Handler)
for raw, why in [(b'["not", "an", "object"]', "a list"), (b'"text"', "a string"), (b"[" * 5000, "nested too deep"), (b"{nope", "not JSON")]:
    h.headers = {"Content-Length": str(len(raw))}
    h.rfile = io.BytesIO(raw)
    check("a body that isn't an object reads as an empty one: " + why, h.body() == {})

print("\n" + ("remote: all good" if not failures else str(failures) + " failed"))
sys.exit(1 if failures else 0)
