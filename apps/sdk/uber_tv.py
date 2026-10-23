"""The Uber TV toolkit: what an app imports to show screens in Uber TV,
fetch what it needs and play media. It speaks the app protocol
(PROTOCOL.md) for the app, so an app is a few functions:

    from uber_tv import app, get_json, Screen, Row, Item

    @app.home
    def home():
        data = get_json("https://api.example.com/today")
        return Screen("Today", rows=[Row("games", "Games", [
            Item(g["id"], g["name"], subtitle=g["score"]) for g in data["games"]])])

    app.run()

The app runs in a sandbox with no network and nothing to write but /tmp:
fetch(), storage and secret() ask the guide, which does them if app.json
allowed it. Text is plain (no HTML), and long text is cut to fit.

API 3 (app.json "api": 3) adds a row's shape and size, hero rows, an item's
pictures for each shape, its line, text and watched mark, and a details
page's style, title logo, line and chips (PROTOCOL.md). An app running as
API 2 has those left out of what it sends, so it still shows. API 4 adds
the sites it may change things on (app.json's netWrite): fetch() with POST,
PUT, PATCH or DELETE to those; and signing in with a password (flow.how is
"password": flow.credentials() gives what the user typed in the guide's own
box).
"""

import base64
import json as _json
import queue as _queue
import os
import sys
import threading
import time
import traceback

__all__ = ["app", "fetch", "get_json", "storage", "secret", "settings", "server", "locale", "log",
           "Screen", "Row", "Item", "Detail", "Action", "Play", "Message", "Chart", "Column", "Page", "Section", "View",
           "AppError", "FetchError", "Cancelled", "Response"]

settings = {}
server = None
locale = "en-US"
api = 2                  # the API the guide runs this app with (its app.json's), from hello

_out = None
_write = threading.Lock()
_ids = iter(range(1, 2 ** 31))
_ids_lock = threading.Lock()
_waiting = {}            # frame id -> [Event, reply]
_waiting_lock = threading.Lock()
_local = threading.local()
_calls = {}              # call id -> _Call
_flows = {}              # flow id -> Flow
_hello = threading.Event()


class AppError(Exception):
    """Raise it to show the user a plain message: AppError("The server is down.")"""

    code = "app"

    def __init__(self, text, code="app"):
        super().__init__(text)
        self.code = code


class FetchError(Exception):
    """A request the guide couldn't make, or (from get_json) one that didn't
    answer 2xx: .code ("offline", "origin", "timeout", "status"...), .status"""

    def __init__(self, code, text, status=0):
        super().__init__(text)
        self.code, self.status = code, status


class Cancelled(BaseException):
    """The call this work belongs to is over (the user went back, it timed
    out). A BaseException, so `except Exception` doesn't swallow it."""


# ---- text --------------------------------------------------------------------

def text(v, n, lines=False):
    """Plain text that fits: control characters, and halves of a character
    that lost its other half (lone surrogates, which can't be sent), become
    spaces (newlines kept only where lines is true, or a number of lines),
    cut to n characters with an ellipsis"""
    if v is None:
        return ""
    s = str(v)
    out = []
    for c in s:
        o = ord(c)
        if c == "\n" and lines:
            out.append(c)
        elif (o < 0x20 or 0x7F <= o < 0xA0 or o in (0x2028, 0x2029) or 0x202A <= o <= 0x202E or 0x2066 <= o <= 0x2069
              or 0xD800 <= o <= 0xDFFF):
            out.append(" ")
        else:
            out.append(c)
    s = "".join(out)
    if lines:
        s = "\n".join(l.rstrip() for l in s.split("\n")[:60 if lines is True else int(lines)])
    else:
        s = " ".join(s.split())
    return s if len(s) <= n else s[:n - 1].rstrip() + "…"


def _image(v):
    if v is None or v == "":
        return None
    if isinstance(v, dict):
        return v
    v = str(v)
    return {"url": v} if v.startswith(("https://", "http://")) else {"asset": v}


# ---- blocks ------------------------------------------------------------------

PICTURES = ("poster", "wide", "square", "backdrop", "logo")


class Item:
    """One thing on a screen. kind: "open" (browse into it), "play" (play it),
    "info" (its details). progress: 0 to 1 (how much was watched).
    API 3: images, a picture for each shape it has one for ({"poster": url,
    "wide": url, "square": url, "backdrop": url, "logo": url}, any of them;
    image stays the picture for its row's own shape); meta, a short line
    (year, length, rating); text, up to 4 lines; watched, true or false.
    API 4: cells, its values in a table row (one a column, 40 characters
    each); chart, a Chart drawn with it."""

    def __init__(self, id, title, subtitle="", image=None, badge="", progress=None, kind="open",
                 images=None, meta="", watched=None, cells=None, chart=None, **kw):
        body = kw.pop("text", "")
        if kw:
            raise TypeError("Item() got an unexpected argument " + repr(sorted(kw)[0]))
        self.d = {"id": text(id, 200) or "-", "title": text(title, 120) or "Untitled", "kind": kind}
        if subtitle:
            self.d["subtitle"] = text(subtitle, 120)
        if image:
            self.d["image"] = _image(image)
        if badge:
            self.d["badge"] = text(badge, 12)
        if progress is not None:
            self.d["progress"] = min(1.0, max(0.0, float(progress)))
        pics = {k: _image(v) for k, v in (images or {}).items() if k in PICTURES and v}
        if pics:
            self.d["images"] = pics
        if meta:
            self.d["meta"] = text(meta, 80)
        if body:
            self.d["text"] = text(body, 300, lines=4)
        if watched is not None:
            self.d["watched"] = bool(watched)
        if cells is not None:
            self.d["cells"] = [text(c, 40) for c in list(cells)[:8]]
        if chart is not None:
            self.d["chart"] = chart.to_dict() if hasattr(chart, "to_dict") else chart

    def to_dict(self):
        return self.d


class Chart:
    """API 4: a line the guide draws, on an item (in a list or table row) or a
    details page: 2 to 120 numbers, oldest first; low and high, what the
    bottom and top mean ("0", "52 °F"), 24 characters each"""

    def __init__(self, points, low="", high=""):
        pts = [float(p) for p in list(points)[-120:]]
        self.d = {"points": pts}
        if low:
            self.d["low"] = text(low, 24)
        if high:
            self.d["high"] = text(high, 24)

    def to_dict(self):
        return self.d


class Column:
    """API 4: a table row's column: its label (24 characters) and which side
    its values keep to ("start", or "end" for numbers)"""

    def __init__(self, label, align="start"):
        self.d = {"label": text(label, 24), "align": "end" if align == "end" else "start"}

    def to_dict(self):
        return self.d


class Section:
    """API 4: a part of a Page: a heading (80 characters) and its text (4,000,
    its own lines kept)"""

    def __init__(self, heading="", text_="", **kw):
        body = kw.pop("text", text_)
        if kw:
            raise TypeError("Section() got an unexpected argument " + repr(sorted(kw)[0]))
        self.d = {}
        if heading:
            self.d["heading"] = text(heading, 80)
        if body:
            self.d["text"] = text(body, 4000, lines=4001)   # every line its 4,000 characters hold

    def to_dict(self):
        return self.d


class Page:
    """API 4: an article the guide shows whole, the arrows scrolling it: a
    title and up to 30 Sections, 30,000 characters in all. browse, details
    and action may answer with one."""

    def __init__(self, title, sections=()):
        self.d = {"title": text(title, 120) or "Untitled",
                  "sections": [x.to_dict() if hasattr(x, "to_dict") else x for x in list(sections)[:30]]}

    def to_dict(self):
        return self.d


def _items(items, cap):
    out, seen = [], set()
    for it in items or []:
        d = it.to_dict() if hasattr(it, "to_dict") else it
        if d.get("id") in seen:
            continue
        seen.add(d.get("id"))
        out.append(d)
        if len(out) == cap:
            break
    return out


class Row:
    """A row of items. layout: "row" (cards across), "grid" or "list"; left
    out, a row (or, API 3, what app.json says for this row). API 3: "hero"
    (one big item at a time, at most 10); shape: "poster", "wide", "square",
    "logo" or "circle" (left out: the guide works it out from the pictures);
    size: "small", "medium" or "large". An API 3 row's id is lowercase
    letters, digits, - and _, starting with a letter, and stays the same
    across versions. API 4: "table" (columns: up to 8 Columns, each item's
    cells one a column; for standings and schedules) and "ticker" (up to 30
    items of text and badge, moving across slowly)."""

    def __init__(self, id, title, items, layout=None, shape=None, size=None, columns=None):
        cap = 10 if layout == "hero" else 30 if layout == "ticker" else 50
        self.d = {"id": text(id, 64) or "row", "title": text(title, 80), "items": _items(items, cap)}
        if columns is not None:
            self.d["columns"] = [c.to_dict() if hasattr(c, "to_dict") else c for c in list(columns)[:8]]
        if layout:
            self.d["layout"] = layout
        if shape:
            self.d["shape"] = shape
        if size:
            self.d["size"] = size

    def to_dict(self):
        return self.d


def _rows(rows, cap, budget):
    out, seen = [], set()
    for r in rows or []:
        d = r.to_dict() if hasattr(r, "to_dict") else r
        if d.get("id") in seen or len(out) == cap:
            continue
        seen.add(d.get("id"))
        items = d.get("items", [])[:max(0, budget[0])]
        budget[0] -= len(items)
        out.append(dict(d, items=items))
    return out


class Screen:
    """A screen: a title and rows. empty: what to say when there are no rows.
    refresh: seconds (15 to 3600) after which the guide asks again. API 4:
    live=True, it may update its rows while it's on the screen (app.live)."""

    def __init__(self, title, rows=(), empty="", refresh=None, live=False):
        self.d = {"title": text(title, 80), "rows": _rows(rows, 30, [200])}
        if empty:
            self.d["empty"] = text(empty, 200)
        if refresh:
            self.d["refresh"] = min(3600, max(15, refresh))
        if live:
            self.d["live"] = True

    def to_dict(self):
        return self.d


class Action:
    """A button on a details screen. kind: "action" (app.action) or "play"."""

    def __init__(self, id, label, kind="action"):
        self.d = {"id": text(id, 64), "label": text(label, 30), "kind": kind}

    def to_dict(self):
        return self.d


class Detail:
    """A details screen. facts: [(label, value)]. actions: [Action]. rows: up
    to 3 rows (more like this, episodes...); API 3, up to 4. API 3: style,
    "classic" or "cinematic"; logo, the title's own picture; meta, a short
    line; chips, up to 8 short labels (genres, 4K). API 4: chart, a Chart."""

    def __init__(self, title, subtitle="", text_="", image=None, backdrop=None, facts=(), actions=(), rows=(),
                 style=None, logo=None, meta="", chips=(), chart=None, **kw):
        body = kw.pop("text", text_)
        if kw:
            raise TypeError("Detail() got an unexpected argument " + repr(sorted(kw)[0]))
        self.d = {"title": text(title, 120) or "Untitled"}
        if subtitle:
            self.d["subtitle"] = text(subtitle, 200)
        if body:
            self.d["text"] = text(body, 4000, lines=True)
        if image:
            self.d["image"] = _image(image)
        if backdrop:
            self.d["backdrop"] = _image(backdrop)
        fs = []
        for f in list(facts)[:12]:
            label, value = (f["label"], f.get("value", "")) if isinstance(f, dict) else f
            fs.append({"label": text(label, 40) or "-", "value": text(value, 120)})
        if fs:
            self.d["facts"] = fs
        acts = [a.to_dict() if hasattr(a, "to_dict") else a for a in list(actions)[:6]]
        if acts:
            self.d["actions"] = acts
        if rows:
            self.d["rows"] = _rows(rows, 4, [200])
        if style:
            self.d["style"] = style
        if logo:
            self.d["logo"] = _image(logo)
        if meta:
            self.d["meta"] = text(meta, 120)
        cs = [text(c, 24) for c in list(chips)[:8] if text(c, 24)]
        if cs:
            self.d["chips"] = cs
        if chart is not None:
            self.d["chart"] = chart.to_dict() if hasattr(chart, "to_dict") else chart

    def to_dict(self):
        return self.d


# what API 3 added, left out of what an app running as API 2 sends; and
# what API 4 added, left out of what an app running as API 2 or 3 sends
_ITEM3 = ("images", "meta", "text", "watched")
_ROW3 = ("shape", "size")
_DETAIL3 = ("style", "logo", "meta", "chips")
_ITEM4 = ("cells", "chart")
_ROW4 = ("columns",)
_DETAIL4 = ("chart",)


# (a handler may return a plain dictionary: only what's well formed is
# changed here, and the guide checks the rest, rows: null included)
def _api2_item(i):
    return {k: v for k, v in i.items() if k not in _ITEM3} if isinstance(i, dict) else i


def _api2_row(r):
    if not isinstance(r, dict):
        return r
    out = {k: v for k, v in r.items() if k not in _ROW3}
    if out.get("layout") == "hero":
        out["layout"] = "row"
    if isinstance(r.get("items"), list):
        out["items"] = [_api2_item(i) for i in r["items"]]
    return out


def _api3_row(r):
    if not isinstance(r, dict):
        return r
    out = {k: v for k, v in r.items() if k not in _ROW4}
    if out.get("layout") in ("table", "ticker"):
        out["layout"] = "list" if out["layout"] == "table" else "row"
    if isinstance(r.get("items"), list):
        out["items"] = [{k: v for k, v in i.items() if k not in _ITEM4} if isinstance(i, dict) else i for i in r["items"]]
    return out


def _api3(out):
    """What API 4 added, left out of what an app running as API 2 or 3
    sends (a table becomes a list, a ticker a row; a page can't be sent)"""
    if "page" in out:
        raise AppError("a page needs api 4 (app.json)", "invalid")
    if isinstance(out.get("screen"), dict):
        out["screen"] = {k: v for k, v in out["screen"].items() if k != "live"}
        if isinstance(out["screen"].get("rows"), list):
            out["screen"]["rows"] = [_api3_row(r) for r in out["screen"]["rows"]]
    elif isinstance(out.get("detail"), dict):
        d = {k: v for k, v in out["detail"].items() if k not in _DETAIL4}
        if isinstance(d.get("rows"), list):
            d["rows"] = [_api3_row(r) for r in d["rows"]]
        out["detail"] = d
    elif isinstance(out.get("rows"), list):
        out["rows"] = [{k: v for k, v in i.items() if k not in _ITEM4} if isinstance(i, dict) else i for i in out["rows"]]
    return out


def _api2(out):
    if isinstance(out.get("screen"), dict):
        if isinstance(out["screen"].get("rows"), list):
            out["screen"] = dict(out["screen"], rows=[_api2_row(r) for r in out["screen"]["rows"]])
    elif isinstance(out.get("detail"), dict):
        d = {k: v for k, v in out["detail"].items() if k not in _DETAIL3}
        if isinstance(d.get("rows"), list):
            d["rows"] = [_api2_row(r) for r in d["rows"][:3]]
        out["detail"] = d
    elif isinstance(out.get("rows"), list):
        out["rows"] = [_api2_item(i) for i in out["rows"]]
    return out


class Play:
    """Media to play. headers: sent with every request for it (Authorization,
    say); they stay with the guide's helper, as does context, which comes back
    with every playback event. start_at: seconds."""

    def __init__(self, url, headers=None, title="", subtitle="", start_at=0, live=False, context=None):
        self.d = {"url": str(url)}
        if headers:
            self.d["headers"] = dict(headers)
        if title:
            self.d["title"] = text(title, 120)
        if subtitle:
            self.d["subtitle"] = text(subtitle, 200)
        if start_at:
            self.d["startAt"] = max(0.0, float(start_at))
        if live:
            self.d["live"] = True
        if context is not None:
            self.d["context"] = context

    def to_dict(self):
        return self.d


class Message:
    """A plain message shown to the user"""

    def __init__(self, text_):
        self.d = {"text": text(text_, 400) or "Done."}

    def to_dict(self):
        return self.d


# ---- talking to the guide ------------------------------------------------

class _Pace:
    """Under the guide's limit of 30 frames a second"""

    def __init__(self):
        self.tokens, self.at, self.lock = 50.0, time.monotonic(), threading.Lock()

    def take(self):
        while True:
            with self.lock:
                now = time.monotonic()
                self.tokens = min(50.0, self.tokens + (now - self.at) * 25)
                self.at = now
                if self.tokens >= 1:
                    self.tokens -= 1
                    return
                wait = (1 - self.tokens) / 25
            time.sleep(wait)


_pace = _Pace()


def _send(frame):
    line = _json.dumps(frame, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode() + b"\n"
    if len(line) > 1024 * 1024:
        raise AppError("that answer is bigger than 1 MB")
    _pace.take()
    with _write:
        _out.write(line)
        _out.flush()


def _take_stdout():
    """Keep fd 1 for frames; anything else written to stdout goes to the log"""
    global _out
    if _out is None:
        _out = os.fdopen(os.dup(1), "wb", buffering=0)
        os.dup2(2, 1)
        sys.stdout = sys.stderr


def log(*parts):
    """A line in the app's log (print works too)"""
    print(*parts, file=sys.stderr, flush=True)


def _owner():
    o = getattr(_local, "owner", None)
    if o is None:
        raise AppError("fetch, storage and secret work only while the app is answering the guide")
    if o.over:
        raise Cancelled()
    return o


def _ask(frame, owner):
    """A frame that gets a reply, waited for until the owner's time is up"""
    with _ids_lock:
        fid = next(_ids)
    frame["id"] = fid
    frame.update(owner.tag)
    slot = [threading.Event(), None]
    with _waiting_lock:
        _waiting[fid] = slot
    owner.asks.add(fid)
    try:
        _send(frame)
        left = owner.deadline - time.monotonic()
        if not slot[0].wait(max(0.1, left + 1)):
            raise FetchError("timeout", "the guide didn't answer in time")
        if owner.over:
            raise Cancelled()
        return slot[1]
    finally:
        owner.asks.discard(fid)
        with _waiting_lock:
            _waiting.pop(fid, None)


class Response:
    """What fetch() got: .status, .headers (lowercase names), .body (bytes),
    .text, .json(), .ok (2xx)"""

    def __init__(self, status, headers, body):
        self.status, self.headers, self.body = status, headers, body

    @property
    def ok(self):
        return 200 <= self.status < 300

    @property
    def text(self):
        return self.body.decode("utf-8", "replace")

    def json(self):
        return _json.loads(self.body.decode("utf-8"))


def fetch(url, method="GET", headers=None, body=None, json=None):
    """A request, made by the guide if app.json allows it (an exact net host,
    GET or HEAD, plus the methods its netWrite gives that host at api 4; or
    the server the user chose, any method). Raises FetchError if it couldn't
    be made; any HTTP status comes back as a Response (a 307 or 308 sending
    a write to another site comes back as it is: make that request again
    yourself if you mean to)."""
    owner = _owner()
    if json is not None:
        body = _json.dumps(json).encode()
        headers = dict(headers or {})
        headers.setdefault("Content-Type", "application/json")
    if isinstance(body, str):
        body = body.encode()
    frame = {"t": "fetch", "url": str(url), "method": method}
    if headers:
        frame["headers"] = {str(k): str(v) for k, v in headers.items()}
    if body:
        frame["body"] = base64.b64encode(body).decode()
    r = _ask(frame, owner)
    if "error" in r:
        raise FetchError(r["error"].get("code", "failed"), r["error"].get("text", "the request failed"))
    return Response(r["status"], r.get("headers", {}), base64.b64decode(r.get("body", "")))


def get_json(url, headers=None):
    """GET a URL and parse its JSON; FetchError("status") if it isn't 2xx"""
    r = fetch(url, headers=headers)
    if not r.ok:
        raise FetchError("status", "the server answered " + str(r.status), r.status)
    try:
        return r.json()
    except ValueError:
        raise FetchError("json", "the server didn't answer with JSON", r.status)


class _Storage:
    """The app's own storage, kept by the guide (256 keys, 64 KB a value, 4 MB
    in all). server=True on put: forgotten when the user signs out or
    changes the server."""

    def _do(self, frame):
        r = _ask(frame, _owner())
        if "error" in r:
            raise AppError(r["error"].get("text", "storage failed"), r["error"].get("code", "storage"))
        return r

    def get_bytes(self, key):
        v = self._do({"t": "storeGet", "key": str(key)}).get("value")
        return base64.b64decode(v) if v is not None else None

    def get(self, key, default=None):
        v = self.get_bytes(key)
        return v.decode("utf-8", "replace") if v is not None else default

    def get_json(self, key, default=None):
        v = self.get(key)
        try:
            return _json.loads(v) if v is not None else default
        except ValueError:
            return default

    def put(self, key, value, server=False):
        if isinstance(value, str):
            value = value.encode()
        frame = {"t": "storePut", "key": str(key), "value": base64.b64encode(value).decode()}
        if server:
            frame["server"] = True
        self._do(frame)

    def put_json(self, key, value, server=False):
        self.put(key, _json.dumps(value, separators=(",", ":")), server)

    def delete(self, key):
        self._do({"t": "storeDel", "key": str(key)})

    def keys(self):
        return self._do({"t": "storeList"}).get("value", [])


storage = _Storage()


def secret(name):
    """A secret: one the user typed in the app's settings (a "secret"
    setting), or one its sign-in kept. None if there isn't one."""
    r = _ask({"t": "secretGet", "name": str(name)}, _owner())
    if "error" in r:
        raise AppError(r["error"].get("text", "the secret couldn't be read"))
    return r.get("value")


class _Call:
    def __init__(self, cid, deadline_ms):
        self.id = cid
        self.tag = {"parent": cid}
        self.deadline = time.monotonic() + deadline_ms / 1000.0
        self.over = False
        self.asks = set()


class Flow:
    """A sign-in, as app.sign_in gets it. how: "code" or "password" (what the
    user chose, from what app.json offers). With a code: show_code() puts it
    on screen. With a password: credentials() waits for what the user typed
    in the guide's own box, (username, password), or None if they cancelled;
    sign in with it through fetch and let go of it. keep() saves a secret
    (only during a sign-in), done() ends it. sleep() waits between polls
    (False once the user cancelled or it expired)."""

    def __init__(self, fid, how="code"):
        self.id = fid
        self.how = how if how in ("code", "password") else "code"
        self.tag = {"flow": fid}
        self.deadline = time.monotonic() + 600
        self.over = False
        self.asks = set()
        self.kept = False
        self._typed = None
        self._got = threading.Event()
        self._chosen = None
        self._before = None
        self._picked = threading.Event()

    def offer_servers(self, servers):
        """For an app whose app.json says server.fromSignIn: the servers the
        account lists, [{"handle", "label", "urls": [...]}] (up to 10, each
        with up to 8 addresses; the handle is yours, it stands for whatever
        the service gives you for that server: keep that, never send it).
        The user chooses one, and one of its addresses or one they type for
        it; returns {"handle", "url"}, or None if they cancelled. From then
        on the app's server is that address (uber_tv.server)."""
        out = []
        for s in list(servers)[:10]:
            out.append({"handle": str(s["handle"]), "label": text(s.get("label") or s["handle"], 80),
                        "urls": [str(u) for u in list(s.get("urls") or [])[:8]]})
        _send({"t": "signInServers", "flow": self.id, "servers": out})
        while not self._picked.wait(0.25):
            if self.over or time.monotonic() > self.deadline:
                return None
        return self._chosen

    def credentials(self):
        """What the user typed, once: (username, password), or None if the
        sign-in was called off or ran out of time first"""
        while not self._got.wait(0.25):
            if self.over or time.monotonic() > self.deadline:
                return None
        typed, self._typed = self._typed, None
        return typed

    def show_code(self, code, url="", expires=600):
        if self.how != "code":
            raise AppError("the user chose to sign in with a password: use flow.credentials()")
        expires = max(5, min(600, float(expires)))
        self.deadline = min(self.deadline, time.monotonic() + expires)
        _send({"t": "signInCode", "flow": self.id, "code": text(code, 16), "url": str(url or ""), "expires": expires})

    def keep(self, name, value):
        r = _ask({"t": "secretSet", "name": str(name), "value": str(value)}, self)
        if "error" in r:
            raise AppError(r["error"].get("text", "the secret couldn't be kept"))
        self.kept = True

    def done(self, ok=True, message=""):
        global server
        if not ok and self._chosen is not None:
            server = self._before      # not signed in: the helper goes back to the server it had
        if not self.over:
            self.over = True
            _send({"t": "signInDone", "flow": self.id, "ok": bool(ok), "message": text(message, 400)})

    def sleep(self, seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if self.over or time.monotonic() > self.deadline:
                return False
            time.sleep(min(0.25, end - time.monotonic()))
        return not self.over and time.monotonic() <= self.deadline

    @property
    def active(self):
        return not self.over and time.monotonic() <= self.deadline


class View:
    """A live view the guide has on the screen (api 4): a screen that said
    live=True, or one of the app's Home rows. app.live gets one, in a thread
    of its own, while it's shown: method and args say what asked for it
    ("home", {} or "homeRow", {"key": ...}...). fetch, storage and secret
    work in it. update() replaces rows already on the screen (by their ids;
    a Home row: its items), at most once a second (a Home row: every 5 s).
    sleep() waits (False once the view has gone). stream(url) yields the
    lines of a long GET to one of its net hosts, while the view is on."""

    def __init__(self, vid, method, args):
        self.id = vid
        self.method = method
        self.args = args or {}
        self.tag = {"view": vid}
        self.over = False
        self.asks = set()
        self._streams = {}

    @property
    def deadline(self):
        return time.monotonic() + 35   # a request of a view's: 30 s at the guide

    @property
    def active(self):
        return not self.over

    def sleep(self, seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if self.over:
                return False
            time.sleep(min(0.25, end - time.monotonic()))
        return not self.over

    def update(self, rows):
        """Rows replacing those of the same ids (a screen), or a Home row's
        items; nothing if the view has gone"""
        if self.over:
            return
        out = [r.to_dict() if hasattr(r, "to_dict") else r for r in rows]
        _send({"t": "update", "view": self.id, ("items" if self.method == "homeRow" else "rows"): out})

    def stream(self, url):
        """The lines of a long GET (text/event-stream or newline-delimited
        text) to one of its net hosts, as they come, until the stream ends
        (FetchError if it ended with an error) or the view goes"""
        with _ids_lock:
            sid = next(_ids)
        q = _queue.Queue()
        self._streams[sid] = q
        _send({"t": "stream", "id": sid, "view": self.id, "url": str(url)})
        try:
            while True:
                try:
                    kind, v = q.get(timeout=0.25)
                except _queue.Empty:
                    if self.over:
                        return
                    continue
                if kind == "line":
                    yield v
                    continue
                if v:
                    raise FetchError(v.get("code", "stream"), v.get("text", "the stream ended"))
                return
        finally:
            self._streams.pop(sid, None)
            if not self.over:
                _send({"t": "streamClose", "id": sid})


_views = {}             # view id -> View, while it's on the screen


# ---- the app -------------------------------------------------------------

METHODS = {"home": "home", "browse": "browse", "details": "details", "search": "search", "play": "play",
           "action": "action", "homeRow": "home_row", "playback": "playback", "playbackFailed": "playback_failed",
           "signIn": "sign_in", "signOut": "sign_out"}


class App:
    """Register what the app does with the decorators, then app.run():

    @app.home                    home() -> Screen
    @app.browse                  browse(item) -> Screen        (an "open" item)
    @app.details                 details(item) -> Detail       (an "info" item, or I)
    @app.search                  search(query) -> Screen
    @app.play                    play(item) -> Play or a URL   (a "play" item or action)
    @app.action                  action(item, action) -> Message, Screen or Detail
    @app.home_row                home_row(key) -> [Item]       (a row declared in app.json "home")
    @app.playback                playback(event)               (started, progress, paused, resumed, seeked, stopped)
    @app.playback_failed         playback_failed(event) -> Play or Message (one more try)
    @app.sign_in                 sign_in(flow)                 (flow.show_code, flow.keep, flow.done)
    @app.sign_out                sign_out()
    @app.live                    live(view)                    (api 4: while a live screen or a Home row is on the screen)
    """

    def __init__(self):
        self.handlers = {}
        self.running = False

    def _reg(name):
        def deco(self, fn):
            self.handlers[name] = fn
            return fn
        return deco

    home = _reg("home")
    browse = _reg("browse")
    details = _reg("details")
    search = _reg("search")
    play = _reg("play")
    action = _reg("action")
    home_row = _reg("home_row")
    playback = _reg("playback")
    playback_failed = _reg("playback_failed")
    sign_in = _reg("sign_in")
    sign_out = _reg("sign_out")
    live = _reg("live")
    del _reg

    def run(self):
        if self.running:
            return
        self.running = True
        _take_stdout()
        stdin = sys.stdin.buffer
        first = stdin.readline()
        try:
            hello = _json.loads(first)
        except ValueError:
            sys.exit("uber_tv: the guide didn't say hello")
        settings.update(hello.get("settings") or {})
        global server, locale, api
        server = hello.get("server")
        locale = hello.get("locale") or "en-US"
        api = hello.get("api") if hello.get("api") in (2, 3, 4) else 2
        _hello.set()
        _send({"t": "ready"})
        for line in stdin:
            try:
                f = _json.loads(line)
            except ValueError:
                continue
            t = f.get("t")
            if t == "call":
                threading.Thread(target=self._answer, args=(f,), daemon=True).start()
            elif t == "cancel":
                c = _calls.get(f.get("id"))
                if c:
                    c.over = True
                    self._wake(c)
            elif t == "viewOn":
                vid = f.get("view")
                if vid not in _views and self.handlers.get("live"):
                    v = _views[vid] = View(vid, f.get("method", ""), f.get("args"))
                    threading.Thread(target=self._live, args=(v,), daemon=True).start()
            elif t == "viewOff":
                v = _views.pop(f.get("view"), None)
                if v:
                    v.over = True
                    self._wake(v)
            elif t in ("streamData", "streamEnd"):
                for v in list(_views.values()):
                    q = v._streams.get(f.get("id"))
                    if q:
                        q.put(("line", str(f.get("line", ""))) if t == "streamData" else ("end", f.get("error")))
            elif t == "signInCancel":
                fl = _flows.get(f.get("flow"))
                if fl:
                    fl.over = True     # called off by the guide: nothing more of it is sent
                    if fl._chosen is not None:
                        server = fl._before    # the helper went back to the server it had
                    fl._got.set()
                    fl._picked.set()
            elif t == "serverChosen":
                fl = _flows.get(f.get("flow"))
                if fl and not fl._picked.is_set():
                    fl._chosen = {"handle": str(f.get("handle") or ""), "url": str(f.get("url") or "")}
                    fl._before, server = server, fl._chosen["url"]
                    fl._picked.set()
            elif t == "credentials":
                fl = _flows.get(f.get("flow"))
                if fl and not fl._got.is_set():
                    fl._typed = (str(f.get("username") or ""), str(f.get("password") or ""))
                    fl._got.set()
            elif t in ("fetchReply", "storeReply", "secretReply"):
                with _waiting_lock:
                    slot = _waiting.get(f.get("id"))
                if slot:
                    slot[1] = f
                    slot[0].set()
        os._exit(0)   # the guide closed stdin: stop now, whatever is running

    def _wake(self, owner):
        for fid in list(owner.asks):
            with _waiting_lock:
                slot = _waiting.get(fid)
            if slot:
                slot[1] = {"error": {"code": "cancelled", "text": "cancelled"}}
                slot[0].set()

    def _answer(self, f):
        cid, method, args = f["id"], f["method"], f.get("args") or {}
        c = _calls[cid] = _Call(cid, f.get("deadline", 10000))
        _local.owner = c
        try:
            name = METHODS.get(method)
            fn = self.handlers.get(name)
            if method == "signIn":
                flow = _flows[args["flow"]] = Flow(args["flow"], args.get("how", "code"))
                if not fn:
                    raise AppError("this app doesn't sign in", "unsupported")
                threading.Thread(target=self._sign_in, args=(fn, flow), daemon=True).start()
                out = {"ok": True}
            elif not fn:
                if method in ("playback", "signOut"):
                    out = {"ok": True}
                elif method == "playbackFailed":
                    out = {"message": {"text": "It couldn't be played."}}
                else:
                    raise AppError("this app doesn't do that", "unsupported")
            else:
                out = self._shape(method, fn(*self._args(method, args)))
                if api < 4:
                    out = _api3(out)
                if api < 3:
                    out = _api2(out)
        except Cancelled:
            out = {"error": {"code": "cancelled", "text": "cancelled"}}
        except AppError as e:
            out = {"error": {"code": e.code if e.code.isidentifier() and e.code.islower() else "app", "text": text(str(e), 200)}}
        except FetchError as e:
            log("fetch failed:", e.code, str(e))
            out = {"error": {"code": "fetch", "text": text(str(e), 200)}}
        except Exception as e:
            traceback.print_exc()
            out = {"error": {"code": "crash", "text": text(type(e).__name__ + ": " + str(e), 200)}}
        finally:
            _local.owner = None
        _calls.pop(cid, None)
        out["t"] = "result"
        out["id"] = cid
        try:
            _send(out)
        except AppError as e:
            _send({"t": "result", "id": cid, "error": {"code": "toobig", "text": str(e)}})
        except (ValueError, TypeError) as e:
            # something in it can't be sent (half a character, a number JSON
            # doesn't have): the call is still answered, so the app isn't
            # stopped for never answering it
            traceback.print_exc()
            _send({"t": "result", "id": cid, "error": {"code": "crash", "text": "its answer couldn't be sent (" + type(e).__name__ + ")"}})

    def _live(self, view):
        _local.owner = view
        try:
            self.handlers["live"](view)
        except Cancelled:
            pass
        except Exception:
            traceback.print_exc()
        finally:
            _local.owner = None
            if _views.get(view.id) is view and view.over:
                _views.pop(view.id, None)

    def _sign_in(self, fn, flow):
        _local.owner = flow
        try:
            fn(flow)
            if not flow.over:
                # returned without saying: signed in only if it kept something
                # while the code was still good
                expired = not flow.active
                flow.done(flow.kept and not expired, "The code expired." if expired and not flow.kept else "")
        except Cancelled:
            pass
        except Exception as e:
            if not isinstance(e, (AppError, FetchError)):
                traceback.print_exc()
            if not flow.over and time.monotonic() > flow.deadline:
                flow.done(False, "The code expired.")   # its last request was cut off at the same moment
            else:
                flow.done(False, text(str(e), 400) if isinstance(e, (AppError, FetchError)) else "Signing in failed.")
        finally:
            _flows.pop(flow.id, None)

    @staticmethod
    def _args(method, a):
        if method in ("browse", "details", "play"):
            return (a.get("item", ""),)
        if method == "search":
            return (a.get("query", ""),)
        if method == "action":
            return (a.get("item", ""), a.get("action", ""))
        if method == "homeRow":
            return (a.get("key", ""),)
        if method in ("playback", "playbackFailed"):
            return (dict(a),)
        return ()

    @staticmethod
    def _shape(method, v):
        if hasattr(v, "to_dict"):
            kind = {Screen: "screen", Detail: "detail", Play: "play", Message: "message", Page: "page"}.get(type(v))
            return {kind: v.to_dict()}
        if method in ("playback", "signOut"):
            return {"ok": True}
        if method == "homeRow":
            return {"rows": _items(v, 50)}
        if method in ("play", "playbackFailed") and isinstance(v, str):
            return {"play": {"url": v}}
        if method == "playbackFailed" and v is None:
            return {"message": {"text": "It couldn't be played."}}
        if method == "action" and isinstance(v, str):
            return {"message": {"text": text(v, 400)}}
        if isinstance(v, dict):
            kind = {"home": "screen", "browse": "screen", "search": "screen", "details": "detail", "play": "play"}.get(method)
            if kind:
                return {kind: v}
        raise AppError(method + " returned something the guide can't show (" + type(v).__name__ + ")", "invalid")


app = App()
