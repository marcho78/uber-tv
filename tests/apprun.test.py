#!/usr/bin/python3
"""The app helper (bin/om-pg-apprun) against apps that misbehave, requests
that try to escape, and the sandbox's scope being killed:
/usr/bin/python3 tests/apprun.test.py"""

import asyncio
import base64
import hashlib
import importlib.util
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from importlib.machinery import SourceFileLoader

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name, rel):
    path = os.path.join(ROOT, rel)
    loader = SourceFileLoader(name, path)
    spec = importlib.util.spec_from_file_location(name, path, loader=loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


apprun = load("apprun", "bin/om-pg-apprun")
net, blocks, apps = apprun.net, apprun.blocks, apprun.apps
WORK = tempfile.mkdtemp(prefix="om-pg-apprun-test-")


def make_app(name, main, perms=None, settings=None, extra=None, api=2):
    folder = os.path.join(WORK, name)
    if os.path.exists(folder):
        shutil.rmtree(folder)
    os.makedirs(folder)
    m = {"id": "tv.example." + name.replace("_", "-"), "name": name[:40], "version": "1.0.0", "api": api, "kind": "app",
         "author": "Test", "main": "main.py", "permissions": perms or {}, "settings": settings or []}
    with open(os.path.join(folder, "app.json"), "w") as f:
        json.dump(m, f)
    with open(os.path.join(folder, "main.py"), "w") as f:
        f.write(main)
    for k, v in (extra or {}).items():
        with open(os.path.join(folder, k), "wb") as f:
            f.write(v)
    return folder


RAW = """import sys, json, time, uber_tv
out = uber_tv._out
def send(b): out.write(b if isinstance(b, bytes) else (json.dumps(b) + "\\n").encode()); out.flush()
hello = sys.stdin.buffer.readline()
"""


class Harness:
    """One runtime in this process, its frames to the guide collected"""

    def __init__(self, folder, **cfg):
        self.frames = []
        self.n = 0
        base = tempfile.mkdtemp(prefix="state-" + os.path.basename(folder) + "-", dir=WORK)
        self.cfg = {"appDir": folder, "gen": 1, "locale": "en-US", "settings": {}, "server": None, "pin": "",
                    "storePath": os.path.join(base, "store.json"), "secretsPath": os.path.join(base, "secrets.json"),
                    "logPath": os.path.join(base, "log"), "imageDir": os.path.join(base, "img"), "online": True}
        self.cfg.update(cfg)

    async def start(self):
        self.rt = apprun.Runtime(self.cfg, self.frames.append)
        return await self.rt.start()

    async def call(self, method, args=None, wait=20):
        self.n += 1
        n = self.n
        await self.rt.from_guide({"t": "call", "id": n, "method": method, "args": args or {}})
        end = time.monotonic() + wait
        while time.monotonic() < end:
            for f in self.frames:
                if f.get("t") == "result" and f.get("id") == n:
                    return f
            if self.rt.done.is_set():
                break
            await asyncio.sleep(0.02)
        return None

    async def stop(self):
        await self.rt.stop("normal")

    def log(self):
        try:
            return open(self.cfg["logPath"], encoding="utf-8").read()
        except OSError:
            return ""


class LocalServer:
    """A plain HTTP server on 127.0.0.1 that records exactly what reaches it"""

    def __init__(self, handler=None):
        self.requests = []
        self.connections = 0
        self.handler = handler or (lambda line, headers: (200, {"Content-Type": "application/json"}, b'{"ok":true}'))

    async def start(self):
        self.server = await asyncio.start_server(self.serve, "127.0.0.1", 0)
        self.port = self.server.sockets[0].getsockname()[1]
        return self

    async def serve(self, r, w):
        self.connections += 1
        try:
            head = await asyncio.wait_for(r.readuntil(b"\r\n\r\n"), 5)
        except Exception:
            w.close()
            return
        lines = head.decode("latin-1").split("\r\n")
        headers = dict((l.split(":", 1)[0].lower(), l.split(":", 1)[1].strip()) for l in lines[1:] if ":" in l)
        n = int(headers.get("content-length", "0") or 0)
        body = await r.readexactly(n) if n else b""
        self.requests.append((lines[0], headers, body))
        status, h, data = self.handler(lines[0], headers)
        out = ["HTTP/1.1 " + str(status) + " X", "Content-Length: " + str(len(data)), "Connection: close"]
        out += [k + ": " + v for k, v in h.items()]
        try:
            w.write(("\r\n".join(out) + "\r\n\r\n").encode() + data)
            await w.drain()
        except ConnectionError:
            pass   # the helper stopped reading (a reply too big): that's the point
        w.close()

    def close(self):
        self.server.close()


def resolver_to(*ips):
    calls = []

    async def resolve(host, port):
        calls.append(host)
        out = []
        for ip in ips:
            fam = socket.AF_INET6 if ":" in ip else socket.AF_INET
            out.append((fam, socket.SOCK_STREAM, 6, "", (ip, port) if fam == socket.AF_INET else (ip, port, 0, 0)))
        return out
    resolve.calls = calls
    return resolve


FETCHER = """from uber_tv import app, fetch, FetchError, Message
import json
@app.action
def action(item, how):
    spec = json.loads(item)
    try:
        r = fetch(spec["url"], method=spec.get("method", "GET"), headers=spec.get("headers"), body=spec.get("body"))
        return Message("status " + str(r.status) + " " + r.text[:200])
    except FetchError as e:
        return Message("error " + e.code + " " + str(e))
app.run()
"""


async def fetch_via(h, url, method="GET", headers=None, body=None):
    spec = {"url": url, "method": method}
    if headers:
        spec["headers"] = headers
    if body:
        spec["body"] = body
    r = await h.call("action", {"item": json.dumps(spec), "action": "go"})
    return r["value"]["text"] if r and r["kind"] == "message" else str(r)


class Frames(unittest.IsolatedAsyncioTestCase):
    async def run_raw(self, body, **cfg):
        h = Harness(make_app("raw_" + str(abs(hash(body)) % 10 ** 8), RAW + body), **cfg)
        await h.start()
        await asyncio.wait_for(h.rt.done.wait(), 15)
        return h

    async def test_flood(self):
        h = await self.run_raw("send({'t':'ready'})\nfor i in range(300): send({'t':'log','text':'x'})\ntime.sleep(5)\n")
        self.assertEqual(h.rt.stop_why[0], "violation")

    async def test_oversize(self):
        h = await self.run_raw("send({'t':'ready'})\nsend(b'{\"t\":\"log\",\"text\":\"' + b'x' * (1024 * 1024 + 10) + b'\"}\\n')\ntime.sleep(5)\n")
        self.assertEqual(h.rt.stop_why, ("violation", "a frame is longer than 1 MiB"))

    async def test_duplicate_keys(self):
        h = await self.run_raw("send(b'{\"t\":\"ready\",\"t\":\"ready\"}\\n')\ntime.sleep(5)\n")
        self.assertEqual(h.rt.stop_why[0], "violation")
        self.assertIn("twice", h.rt.stop_why[1])

    async def test_depth(self):
        deep = "[" * 13 + "]" * 13
        h = await self.run_raw("send({'t':'ready'})\nsend(b'{\"t\":\"log\",\"text\":\"a\",\"x\":" + deep.replace("[", "[").encode().decode() + "}\\n')\ntime.sleep(5)\n")
        self.assertEqual(h.rt.stop_why[0], "violation")
        self.assertIn("deeper", h.rt.stop_why[1])

    async def test_unknown_type_and_field(self):
        h = await self.run_raw("send({'t':'ready'})\nsend({'t':'shell','cmd':'id'})\ntime.sleep(5)\n")
        self.assertEqual(h.rt.stop_why[0], "violation")
        h = await self.run_raw("send({'t':'ready','extra':1})\ntime.sleep(5)\n")
        self.assertEqual(h.rt.stop_why[0], "violation")

    async def test_before_ready(self):
        h = await self.run_raw("send({'t':'fetch','id':1,'parent':1,'url':'https://x.example/','method':'GET'})\ntime.sleep(5)\n")
        self.assertEqual(h.rt.stop_why[0], "violation")

    async def test_not_ready_in_time(self):
        h = await self.run_raw("time.sleep(8)\n")
        self.assertEqual(h.rt.stop_why[0], "start")

    async def test_invalid_utf8_and_nan(self):
        h = await self.run_raw("send({'t':'ready'})\nsend(b'{\"t\":\"log\",\"text\":\"\\xff\"}\\n')\ntime.sleep(5)\n")
        self.assertEqual(h.rt.stop_why[0], "violation")
        h = await self.run_raw("send({'t':'ready'})\nsend(b'{\"t\":\"result\",\"id\":1,\"ok\":NaN}\\n')\ntime.sleep(5)\n")
        self.assertEqual(h.rt.stop_why[0], "violation")

    async def test_a_lone_surrogate(self):
        """text that isn't Unicode (an escaped lone surrogate: valid JSON): a
        violation, as invalid UTF-8 is, never a reader that stops quietly"""
        h = await self.run_raw("send({'t':'ready'})\nsend({'t':'log','text':'a\\udc00b'})\ntime.sleep(5)\n")
        self.assertEqual(h.rt.stop_why, ("violation", "a frame has text that isn't Unicode (a lone surrogate)"))
        h = await self.run_raw("send({'t':'ready'})\nsend({'t':'log','text':'\\ud83d\\ude00 a pair is fine'})\nsend({'t':'shell'})\ntime.sleep(5)\n")
        self.assertEqual(h.rt.stop_why[0], "violation")
        self.assertNotIn("surrogate", h.rt.stop_why[1], "an escaped pair is one character")

    async def test_unasked_result(self):
        h = await self.run_raw("send({'t':'ready'})\nsend({'t':'result','id':77,'ok':True})\ntime.sleep(5)\n")
        self.assertEqual(h.rt.stop_why[0], "violation")

    async def test_owner_rules(self):
        # a fetch naming both owners is a violation; a stale parent or flow just fails
        body = ("send({'t':'ready'})\n"
                "send({'t':'fetch','id':1,'parent':99,'url':'https://x.example/','method':'GET'})\n"
                "send({'t':'fetch','id':2,'flow':'0'*32,'url':'https://x.example/','method':'GET'})\n"
                "send({'t':'secretSet','id':3,'flow':'1'*32,'name':'token','value':'v'})\n"
                "time.sleep(1.5)\n"
                "send({'t':'fetch','id':4,'parent':1,'flow':'0'*32,'url':'https://x.example/','method':'GET'})\n"
                "time.sleep(5)\n")
        h = Harness(make_app("raw_owner", RAW + body))
        await h.start()
        await asyncio.wait_for(h.rt.done.wait(), 15)
        self.assertEqual(h.rt.stop_why[0], "violation")
        self.assertIn("exactly one of parent, flow or view", h.rt.stop_why[1])
        self.assertFalse(os.path.exists(h.cfg["secretsPath"]), "an unsolicited secretSet wrote nothing")

    async def test_crash(self):
        h = await self.run_raw("send({'t':'ready'})\nraise SystemExit(3)\n")
        self.assertEqual(h.rt.stop_why[0], "crash")


class Calls(unittest.IsolatedAsyncioTestCase):
    async def test_screen_round_trip_and_normalization(self):
        main = """from uber_tv import app, Screen, Row, Item
@app.home
def home():
    return Screen("Hi <b>there</b>", rows=[Row("r", "Row", [Item("a", "A\\x07title", image="icon.png"), Item("b", "B", image="https://img.example.com/b.png")])])
app.run()
"""
        png = apps.picture_problem  # just to be sure the asset passes as a picture
        icon = b"\x89PNG\r\n\x1a\n" + b"\0\0\0\x0dIHDR" + b"\0\0\0\x10\0\0\0\x10\x08\x06\0\0\0" + b"\0" * 20
        self.assertEqual(png(icon), "")
        h = Harness(make_app("screen", main, perms={"net": ["img.example.com"]}, extra={"icon.png": icon}))
        self.assertTrue(await h.start())
        r = await h.call("home")
        self.assertEqual(r["kind"], "screen")
        s = r["value"]
        self.assertEqual(s["title"], "Hi <b>there</b>", "markup stays plain text, never interpreted")
        self.assertEqual(s["rows"][0]["items"][0]["title"], "A title", "the toolkit turns control characters into spaces")
        self.assertTrue(s["rows"][0]["items"][0]["image"]["path"].endswith("/icon.png"))
        self.assertIn("token", s["rows"][0]["items"][1]["image"])
        self.assertNotIn("img.example.com", json.dumps(s), "the guide never gets the app's picture links")
        await h.stop()

    async def test_raw_control_characters_refused(self):
        body = ("send({'t':'ready'})\nline = sys.stdin.buffer.readline()\nc = json.loads(line)\n"
                "send({'t':'result','id':c['id'],'screen':{'title':'bad\\u202etitle','rows':[]}})\ntime.sleep(5)\n")
        h = Harness(make_app("raw_ctrl", RAW + body))
        await h.start()
        r = await h.call("home")
        self.assertEqual(r["kind"], "error")
        self.assertEqual(r["value"]["code"], "invalid")
        await h.stop()

    async def test_wrong_answer_kind(self):
        main = "from uber_tv import app, Message\n@app.home\ndef home():\n    return Message('hi')\napp.run()\n"
        h = Harness(make_app("wrongkind", main))
        await h.start()
        r = await h.call("home")
        self.assertEqual(r["kind"], "error")
        await h.stop()

    async def test_half_a_character_is_still_answered(self):
        """A lone surrogate (half of a character, which UTF-8 can't carry):
        the toolkit's text drops it, and an answer it's left in elsewhere is
        answered as an error, never left to time out and stop the app"""
        main = """from uber_tv import app, Screen, Row, Item, Message
@app.home
def home():
    return Screen("x", rows=[Row("r", "R", [Item("a", "A", image="https://img.example.com/\\ud800.png")])])
@app.action
def action(item, how):
    return Message("half \\ud800 a character")
app.run()
"""
        old = apprun.DEFAULT_DEADLINE
        apprun.DEFAULT_DEADLINE = 2.0
        try:
            h = Harness(make_app("surrogate", main, perms={"net": ["img.example.com"]}))
            await h.start()
            r = await h.call("action", {"item": "a", "action": "go"}, wait=5)
            self.assertEqual((r["kind"], r["value"]), ("message", {"text": "half a character"}))
            r = await h.call("home", wait=5)
            self.assertEqual((r["kind"], r["value"]["code"]), ("error", "crash"), r)
            r = await h.call("action", {"item": "a", "action": "go"}, wait=5)
            self.assertEqual(r["kind"], "message", "the app goes on")
            self.assertEqual(h.rt.state, "ready")
            await h.stop()
        finally:
            apprun.DEFAULT_DEADLINE = old

    async def test_deadline_then_stop(self):
        main = "import time\nfrom uber_tv import app\n@app.home\ndef home():\n    time.sleep(30)\napp.run()\n"
        old = dict(apprun.DEADLINES), apprun.DEFAULT_DEADLINE, apprun.GRACE
        apprun.DEFAULT_DEADLINE, apprun.GRACE = 1.0, 1.0
        try:
            h = Harness(make_app("slow", main))
            await h.start()
            r = await h.call("home", wait=5)
            self.assertEqual(r["value"]["code"], "timeout")
            await asyncio.wait_for(h.rt.done.wait(), 5)
            self.assertEqual(h.rt.stop_why[0], "timeout")
        finally:
            apprun.DEFAULT_DEADLINE, apprun.GRACE = old[1], old[2]

    async def test_cancel_drops_result(self):
        main = "import time\nfrom uber_tv import app, Screen\n@app.home\ndef home():\n    time.sleep(0.5)\n    return Screen('late')\napp.run()\n"
        h = Harness(make_app("cancel", main))
        await h.start()
        h.n += 1
        await h.rt.from_guide({"t": "call", "id": h.n, "method": "home", "args": {}})
        await h.rt.from_guide({"t": "cancel", "id": h.n})
        await asyncio.sleep(1.5)
        self.assertFalse([f for f in h.frames if f.get("t") == "result" and f.get("id") == h.n], "a cancelled call's result is dropped")
        self.assertEqual(h.rt.state, "ready")
        await h.stop()

    async def test_busy(self):
        main = "import time\nfrom uber_tv import app\n@app.home\ndef home():\n    time.sleep(3)\napp.run()\n"
        h = Harness(make_app("busy", main))
        await h.start()
        for i in range(9):
            await h.rt.from_guide({"t": "call", "id": 100 + i, "method": "home", "args": {}})
        busy = [f for f in h.frames if f.get("t") == "result" and f["value"].get("code") == "busy"]
        self.assertEqual(len(busy), 1, "the ninth pending call is refused")
        await h.stop()

    async def test_unavailable_without_bwrap(self):
        old = apprun.BWRAP
        apprun.BWRAP = "/nonexistent/bwrap"
        try:
            h = Harness(make_app("nobwrap", "from uber_tv import app\napp.run()\n"))
            self.assertFalse(await h.start())
            self.assertEqual(h.rt.stop_why[0], "unavailable")
        finally:
            apprun.BWRAP = old


class Fetches(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.srv = await LocalServer().start()
        self.base = "http://127.0.0.1:" + str(self.srv.port)

    async def asyncTearDown(self):
        self.srv.close()

    async def test_server_prefix_and_canonical_target(self):
        h = Harness(make_app("fetch_srv", FETCHER, perms={"server": {"label": "S"}}), server=self.base + "/jf")
        await h.start()
        ok = await fetch_via(h, self.base + "/jf/a/./b/../c%41?x=%41&y=1")
        self.assertTrue(ok.startswith("status 200"), ok)
        self.assertEqual(self.srv.requests[-1][0], "GET /jf/a/cA?x=%41&y=1 HTTP/1.1", "the target sent is the canonical one")
        n = self.srv.connections
        for bad in ["/jf-other/x", "/jf/%2e%2e/admin", "/jf/%252e%252e/admin", "/jf/.%252e/x", "/jf/%2e%252e/x", "/jf/a%252fb",
                    "/jf/a%2fb", "/jf/a%2Fb", "/jf/%2E%2E/x", "/jf/../admin", "/jf/a%5cb", "/jf/a%0d%0aHost:x", "/jf/a%00b",
                    "/JF/x", "/"]:
            res = await fetch_via(h, self.base + bad)
            self.assertTrue(res.startswith("error"), bad + " -> " + res)
        self.assertEqual(self.srv.connections, n, "no refused request reached the server")
        await h.stop()

    async def test_methods(self):
        h = Harness(make_app("fetch_meth", FETCHER, perms={"server": {"label": "S"}, "net": ["api.example.com"]}), server=self.base + "/jf")
        await h.start()
        n = self.srv.connections
        for bad in ["GET X", "GE\tT", "GET\r", "GET\n", "GET\x00", "GE/T", "GE:T", "GÉT", "get", "BREW", "CONNECT", "TRACE"]:
            res = await fetch_via(h, self.base + "/jf/x", method=bad)
            self.assertTrue(res.startswith("error") or "violation" in res or res.startswith("{"), repr(bad) + " -> " + res)
        self.assertEqual(self.srv.connections, n, "no byte reached the server for a bad method")
        res = await fetch_via(h, self.base + "/jf/items/1", method="DELETE")
        self.assertTrue(res.startswith("status 200"), res)
        self.assertEqual(self.srv.requests[-1][0], "DELETE /jf/items/1 HTTP/1.1")
        self.assertEqual(self.srv.connections, n + 1, "exactly one request")
        res = await fetch_via(h, "https://api.example.com/x", method="POST")
        self.assertIn("error method", res, "a net host gets GET and HEAD only")
        await h.stop()

    async def test_headers(self):
        h = Harness(make_app("fetch_hdr", FETCHER, perms={"server": {"label": "S"}}), server=self.base + "/jf")
        await h.start()
        for bad in [{"Host": "evil"}, {"Cookie": "a=b"}, {"Transfer-Encoding": "chunked"}, {"X-A": "a\r\nX-B: b"}, {"Bad Name": "x"}]:
            res = await fetch_via(h, self.base + "/jf/x", headers=bad)
            self.assertTrue(res.startswith("error headers"), json.dumps(bad) + " -> " + res)
        res = await fetch_via(h, self.base + "/jf/x", headers={"Authorization": "MediaBrowser Token=abc"})
        self.assertTrue(res.startswith("status 200"), res)
        line, headers, _ = self.srv.requests[-1]
        self.assertEqual(headers.get("host"), "127.0.0.1:" + str(self.srv.port))
        self.assertEqual(headers.get("accept-encoding"), "identity")
        await h.stop()

    async def test_private_resolution_refused_before_connect(self):
        for ips in [("10.0.0.1",), ("127.0.0.1",), ("224.0.0.1",), ("100.64.0.1",), ("169.254.169.254",), ("::1",),
                    ("::ffff:127.0.0.1",), ("fe80::1",), ("93.184.216.34", "127.0.0.1"), ("2001:db8::1",), ("0.0.0.0",)]:
            res_ = resolver_to(*ips)
            h = Harness(make_app("fetch_priv", FETCHER, perms={"net": ["api.example.com"]}), resolver=res_)
            await h.start()
            res = await fetch_via(h, "https://api.example.com/x")
            self.assertIn("error private", res, str(ips))
            self.assertEqual(len(res_.calls), 1, "resolved once, the address checked is the one connected to")
            await h.stop()

    async def test_exact_hosts(self):
        h = Harness(make_app("fetch_host", FETCHER, perms={"net": ["img.example.com"]}), resolver=resolver_to("10.9.9.9"))
        await h.start()
        for url in ["https://example.com/", "https://www.img.example.com/", "https://img.example.com.evil.net/",
                    "https://imgXexample.com/", "https://IMG.EXAMPLE.COM:443@evil.net/", "https://img.example.com:444/",
                    "http://img.example.com/", "https://[::ffff:10.0.0.1]/", "https://0x7f.1/", "https://2130706433/"]:
            res = await fetch_via(h, url)
            self.assertTrue(res.startswith("error") and "private" not in res, url + " -> " + res)
        res = await fetch_via(h, "https://IMG.example.com/a")
        self.assertIn("error private", res, "case doesn't matter, and then the address check runs")
        await h.stop()

    async def test_redirects(self):
        def handler(line, headers):
            path = line.split()[1]
            if path == "/jf/out":
                return 302, {"Location": "https://evil.example/steal"}, b""
            if path == "/jf/escape":
                return 302, {"Location": "/admin"}, b""
            if path == "/jf/escape2":
                return 301, {"Location": "../jf-other/x"}, b""
            if path == "/jf/inside":
                return 302, {"Location": "next"}, b""
            if path == "/jf/loop":
                return 302, {"Location": "/jf/loop"}, b""
            if path == "/jf/encoded":
                return 302, {"Location": "/jf/%2e%2e/admin"}, b""
            return 200, {}, path.encode()
        self.srv.handler = handler
        h = Harness(make_app("fetch_redir", FETCHER, perms={"server": {"label": "S"}}), server=self.base + "/jf")
        await h.start()
        self.assertIn("error origin", await fetch_via(h, self.base + "/jf/out"))
        self.assertIn("error origin", await fetch_via(h, self.base + "/jf/escape"))
        self.assertIn("error origin", await fetch_via(h, self.base + "/jf/escape2"))
        self.assertIn("error path", await fetch_via(h, self.base + "/jf/encoded"))
        self.assertIn("error redirects", await fetch_via(h, self.base + "/jf/loop"))
        self.assertEqual(await fetch_via(h, self.base + "/jf/inside"), "status 200 /jf/next")
        await h.stop()

    async def test_authorization_dropped_across_origins(self):
        seen = []

        class Fake:
            def __init__(self, status, loc):
                self.status, self.loc = status, loc
                self.headers = [("Location", loc)] if loc else []

            def header(self, name):
                return self.loc if name == "location" else None

            def close(self):
                pass

        async def fake_exchange(url, method, headers, body, gate, kind, pin="", resolver=None):
            seen.append((str(url), method, dict(headers)))
            if url.host == "home.example" and url.path == "/jf/a":
                return Fake(307, "https://img.example.com/b")
            return Fake(200, None)
        real = net.exchange
        net.exchange = fake_exchange
        try:
            rules = net.Rules(["img.example.com"], net.normalize_base("https://home.example/jf"))
            await net.request(rules, "https://home.example/jf/a", "GET", {"Authorization": "secret"}, None, net.Gate())
        finally:
            net.exchange = real
        self.assertEqual(seen[0][2].get("Authorization"), "secret")
        self.assertNotIn("Authorization", seen[1][2], "Authorization doesn't follow a redirect to another origin")

    async def test_ownerless_after_result(self):
        """A fetch naming a call that's already answered fails, and reaches nothing"""
        main = """from uber_tv import app, fetch, Message
import uber_tv
saved = {}
@app.action
def action(item, how):
    if item == "first":
        saved["owner"] = uber_tv._local.owner
        return Message("done")
    mine = uber_tv._local.owner
    uber_tv._local.owner = saved["owner"]   # the finished call's
    try:
        fetch("http://127.0.0.1:%d/jf/x")
        out = "reached"
    except BaseException as e:
        out = "refused " + type(e).__name__ + " " + getattr(e, "code", "")
    uber_tv._local.owner = mine
    return Message(out)
app.run()
""" % self.srv.port
        h = Harness(make_app("fetch_late", main, perms={"server": {"label": "S"}}), server=self.base + "/jf")
        await h.start()
        await h.call("action", {"item": "first", "action": "y"})
        r = await h.call("action", {"item": "second", "action": "y"})
        self.assertEqual(r["value"]["text"], "refused FetchError cancelled", r)
        self.assertEqual(self.srv.connections, 0)
        await h.stop()


def png(w, h, extra=0):
    import struct
    return b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0) + b"\0" * (16 + extra)


class Images(unittest.IsolatedAsyncioTestCase):
    async def test_image_broker(self):
        pics = {"/jf/ok.png": png(64, 64), "/jf/huge.png": png(100000, 100000), "/jf/wide.png": png(4097, 10),
                "/jf/big.png": png(10, 10, 3 * 1024 * 1024), "/jf/page.png": b"<html>not a picture</html>", "/jf/gone.png": None}

        def handler(line, headers):
            path = line.split()[1]
            data = pics.get(path)
            return (404, {}, b"") if data is None else (200, {"Content-Type": "image/png"}, data)
        srv = await LocalServer(handler).start()
        base = "http://127.0.0.1:" + str(srv.port)
        main = """from uber_tv import app, Screen, Row, Item
@app.home
def home():
    names = ["ok", "huge", "wide", "big", "page", "gone"]
    return Screen("pics", rows=[Row("r", "R", [Item(n, n, image="%s/jf/" + n + ".png") for n in names])])
app.run()
""" % base
        h = Harness(make_app("images", main, perms={"server": {"label": "S"}}), server=base + "/jf")
        await h.start()
        r = await h.call("home")
        items = r["value"]["rows"][0]["items"]
        for it in items:
            await h.rt.from_guide({"t": "image", "token": it["image"]["token"]})
        await asyncio.sleep(1.5)
        got = {}
        for f in h.frames:
            if f.get("t") == "image":
                name = next(i["id"] for i in items if i["image"]["token"] == f["token"])
                got[name] = f
        self.assertIn("path", got["ok"], got["ok"])
        self.assertEqual(oct(os.stat(got["ok"]["path"]).st_mode & 0o777), "0o600")
        self.assertEqual(oct(os.stat(os.path.dirname(got["ok"]["path"])).st_mode & 0o777), "0o700")
        self.assertIn("4096", got["huge"]["error"])
        self.assertIn("4096", got["wide"]["error"])
        self.assertIn("2 MB", got["big"]["error"])
        self.assertIn("PNG", got["page"]["error"])
        self.assertIn("404", got["gone"]["error"])
        await h.stop()
        srv.close()

    async def test_picture_outside_the_rules_refused(self):
        main = """from uber_tv import app, Screen, Row, Item
@app.home
def home():
    return Screen("x", rows=[Row("r", "R", [Item("a", "a", image="https://evil.example/x.png")])])
app.run()
"""
        h = Harness(make_app("images_out", main, perms={"net": ["img.example.com"]}))
        await h.start()
        r = await h.call("home")
        self.assertEqual(r["kind"], "error")
        self.assertIn("evil.example", r["value"]["text"])
        await h.stop()

    def test_screens_draw_plain_text(self):
        """Every text the app screen draws is plain (a Label, or textFormat PlainText)"""
        import re
        for name in ("AppScreen.qml", "AppCard.qml"):
            src = open(os.path.join(ROOT, "ui", name)).read()
            for m in re.finditer(r"\n\s*(Text|TextEdit|TextArea)\s*\{", src):
                block = src[m.end():m.end() + 400]
                self.assertIn("textFormat: Text.PlainText", block, name + ": a " + m.group(1) + " that isn't plain text")
        label = open(os.path.join(ROOT, "ui", "Label.qml")).read()
        self.assertIn("textFormat: Text.PlainText", label)


MEDIA = os.path.join(WORK, "media")


def make_media():
    """Real files, made by FFmpeg: a direct MP4 and an HLS stream of TS segments"""
    if os.path.exists(os.path.join(MEDIA, "movie.mp4")):
        return True
    if not os.path.exists("/usr/bin/ffmpeg"):
        return False
    os.makedirs(MEDIA, exist_ok=True)
    src = ["-f", "lavfi", "-i", "testsrc=size=320x240:rate=25", "-f", "lavfi", "-i", "sine=frequency=440", "-t", "4",
           "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-g", "25", "-sc_threshold", "0", "-c:a", "aac", "-shortest"]
    q = ["/usr/bin/ffmpeg", "-hide_banner", "-loglevel", "error", "-y"]
    subprocess.run(q + src + [os.path.join(MEDIA, "movie.mp4")], check=True)
    subprocess.run(q + src + ["-f", "hls", "-hls_time", "1", "-hls_list_size", "0", "-hls_segment_filename",
                              os.path.join(MEDIA, "seg%d.ts"), os.path.join(MEDIA, "media.m3u8")], check=True)
    # a single-file fMP4 stream: its init section and every segment are
    # byteranges of one file (the init at offset 0)
    sf = os.path.join(MEDIA, "sf")
    os.makedirs(sf, exist_ok=True)
    subprocess.run(q + ["-f", "lavfi", "-i", "testsrc=d=4:size=160x120:rate=25", "-c:v", "libx264", "-preset", "ultrafast", "-g", "25",
                        "-sc_threshold", "0", "-f", "hls", "-hls_time", "1", "-hls_list_size", "0", "-hls_segment_type", "fmp4",
                        "-hls_flags", "single_file", os.path.join(sf, "out.m3u8")], check=True, cwd=sf)
    for n in ("out.m3u8", "out.m4s"):
        os.replace(os.path.join(sf, n), os.path.join(MEDIA, n))
    with open(os.path.join(MEDIA, "master.m3u8"), "w") as f:
        f.write('#EXTM3U\n#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",URI="subs.m3u8"\n'
                '#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=320x240,SUBTITLES="subs"\nmedia.m3u8\n')
    media = open(os.path.join(MEDIA, "media.m3u8")).read()
    with open(os.path.join(MEDIA, "keyed.m3u8"), "w") as f:
        f.write(media.replace("#EXTINF", '#EXT-X-KEY:METHOD=AES-128,URI="key.bin",IV=0x00000000000000000000000000000001\n#EXTINF', 1))
    with open(os.path.join(MEDIA, "badkey.m3u8"), "w") as f:
        f.write(media.replace("#EXTINF", '#EXT-X-KEY:METHOD=AES-128,URI="key15.bin"\n#EXTINF', 1))
    with open(os.path.join(MEDIA, "mixed.m3u8"), "w") as f:
        f.write("#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:1,\nseg0.ts\n#EXTINF:1,\nseg1.ts\n#EXTINF:1,\nhttps://evil.example/x.ts\n#EXT-X-ENDLIST\n")
    with open(os.path.join(MEDIA, "key.bin"), "wb") as f:
        f.write(bytes(range(16)))
    with open(os.path.join(MEDIA, "key15.bin"), "wb") as f:
        f.write(bytes(15))
    with open(os.path.join(MEDIA, "noise.bin"), "wb") as f:
        f.write(os.urandom(100000))
    return True


def media_handler(seen):
    def handler(line, headers):
        seen.append((line, headers))
        path = line.split()[1].split("?")[0]
        if path == "/jf/redirect.mp4":
            return 302, {"Location": "/jf/movie.mp4"}, b""
        name = path[len("/jf/"):] if path.startswith("/jf/") else ""
        full = os.path.join(MEDIA, name)
        if not name or "/" in name or not os.path.isfile(full):
            return 404, {}, b""
        data = open(full, "rb").read()
        rng = headers.get("range", "")
        if rng.startswith("bytes="):
            a, _, b = rng[6:].partition("-")
            a = int(a)
            b = min(int(b) if b else len(data) - 1, len(data) - 1)
            return 206, {"Content-Range": "bytes %d-%d/%d" % (a, b, len(data)), "Accept-Ranges": "bytes"}, data[a:b + 1]
        return 200, {"Accept-Ranges": "bytes"}, data
    return handler


async def relay_get(url, headers=None, method="GET"):
    """A plain HTTP request to the relay, as the player makes it"""
    hostport, path = url[len("http://"):].split("/", 1)
    host, port = hostport.split(":")
    r, w = await asyncio.open_connection(host, int(port))
    lines = [method + " /" + path + " HTTP/1.1", "Host: " + hostport] + [k + ": " + v for k, v in (headers or {}).items()]
    w.write(("\r\n".join(lines) + "\r\n\r\n").encode())
    await w.drain()
    data = await asyncio.wait_for(r.read(), 30)
    w.close()
    head, _, body = data.partition(b"\r\n\r\n")
    rows = head.decode("latin-1").split("\r\n")
    status = int(rows[0].split()[1])
    hdrs = dict((x.split(":", 1)[0].lower(), x.split(":", 1)[1].strip()) for x in rows[1:] if ":" in x)
    return status, hdrs, body


PLAYER_APP = """from uber_tv import app, Play, Message
import json
@app.play
def play(item):
    return Play(SERVER + "/jf/" + item, headers={"Authorization": "MediaBrowser Token=abc"}, title=item, context={"item": item})
@app.playback
def playback(event):
    print("EVENT", event["state"], event.get("reason", ""), json.dumps(event.get("context")))
app.run()
"""


class Relay(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        if not make_media():
            self.skipTest("no ffmpeg")
        self.seen = []
        self.srv = await LocalServer(media_handler(self.seen)).start()
        self.base = "http://127.0.0.1:" + str(self.srv.port)
        main = "SERVER = %r\n" % self.base + PLAYER_APP
        self.h = Harness(make_app("player", main, perms={"server": {"label": "S"}, "play": True}), server=self.base + "/jf")
        await self.h.start()

    async def asyncTearDown(self):
        await self.h.stop()
        self.srv.close()

    async def play(self, item):
        r = await self.h.call("play", {"item": item})
        self.assertEqual(r["kind"], "play", r)
        self.assertRegex(r["value"]["url"], r"^http://127\.0\.0\.1:[0-9]+/[0-9a-f]{32}/media\.")
        self.assertNotIn(str(self.srv.port), r["value"]["url"].split("/")[2], "the player never gets the server's address")
        return r["value"]

    async def test_direct_mp4_and_ranges(self):
        v = await self.play("movie.mp4")
        full = open(os.path.join(MEDIA, "movie.mp4"), "rb").read()
        st, hd, body = await relay_get(v["url"])
        self.assertEqual(st, 200)
        self.assertEqual(body, full)
        self.assertEqual(hd["content-type"], "video/mp4")
        st, hd, body = await relay_get(v["url"], {"Range": "bytes=1000-1999"})
        self.assertEqual((st, len(body), body), (206, 1000, full[1000:2000]))
        self.assertEqual(hd["content-range"], "bytes 1000-1999/%d" % len(full))
        st, hd, body = await relay_get(v["url"], method="HEAD")
        self.assertEqual((st, body), (200, b""))
        self.assertTrue(any(h.get("authorization") == "MediaBrowser Token=abc" for _, h in self.seen), "the app's headers go upstream")
        st, _, _ = await relay_get(v["url"].rsplit("/", 2)[0] + "/" + "0" * 32 + "/media.mp4")
        self.assertEqual(st, 404, "an id the relay never gave")

    async def test_redirect_followed_inside(self):
        v = await self.play("redirect.mp4")
        st, hd, body = await relay_get(v["url"])
        self.assertEqual(st, 200, "the relay follows redirects itself, never passing a 3xx on")
        self.assertEqual(len(body), os.path.getsize(os.path.join(MEDIA, "movie.mp4")))

    async def test_not_media_refused(self):
        v = await self.play("noise.bin")
        st, _, body = await relay_get(v["url"])
        self.assertEqual((st, body), (502, b""))

    async def test_hls_master_media_segments_key(self):
        v = await self.play("master.m3u8")
        st, hd, body = await relay_get(v["url"])
        self.assertEqual(st, 200)
        self.assertEqual(hd["content-type"], "application/vnd.apple.mpegurl")
        text = body.decode()
        self.assertNotIn("SUBTITLES", text, "the subtitles rendition and its reference are gone")
        self.assertNotIn(str(self.srv.port), text, "no upstream address in what the player reads")
        child = [l for l in text.splitlines() if l.startswith("http://127.0.0.1:")][0]
        st, _, media = await relay_get(child)
        self.assertEqual(st, 200)
        segs = [l for l in media.decode().splitlines() if l.startswith("http://127.0.0.1:")]
        self.assertGreaterEqual(len(segs), 3)
        st, hd, seg = await relay_get(segs[0])
        self.assertEqual(st, 200)
        self.assertEqual(seg, open(os.path.join(MEDIA, "seg0.ts"), "rb").read())
        self.assertEqual(hd["content-type"], "video/mp2t")
        v2 = await self.play("keyed.m3u8")
        st, _, keyed = await relay_get(v2["url"])
        key = [x for x in keyed.decode().split('"') if x.startswith("http://127.0.0.1:")][0]
        st, _, k = await relay_get(key)
        self.assertEqual((st, k), (200, bytes(range(16))))
        v3 = await self.play("badkey.m3u8")
        st, _, bad = await relay_get(v3["url"])
        key15 = [x for x in bad.decode().split('"') if x.startswith("http://127.0.0.1:")][0]
        st, _, _ = await relay_get(key15)
        self.assertEqual(st, 502, "a key that isn't 16 bytes")

    async def test_single_file_fmp4_byteranges(self):
        """The map and each segment are byteranges of one file, the init at 0:
        each is checked from its own first range, and plays"""
        import re as _re
        v = await self.play("out.m3u8")
        st, _, pl = await relay_get(v["url"])
        self.assertEqual(st, 200)
        text = pl.decode()
        mapline = [l for l in text.splitlines() if l.startswith("#EXT-X-MAP")][0]
        map_url = _re.search(r'URI="([^"]+)"', mapline).group(1)
        n, off = _re.search(r'BYTERANGE="(\d+)@(\d+)"', mapline).groups()
        st, hd, init = await relay_get(map_url, {"Range": "bytes=%s-%d" % (off, int(off) + int(n) - 1)})
        self.assertEqual((st, init[4:8]), (206, b"ftyp"))
        lines = text.splitlines()
        ranges = [(_re.match(r"#EXT-X-BYTERANGE:(\d+)@(\d+)", l).groups(), lines[i + 1]) for i, l in enumerate(lines) if l.startswith("#EXT-X-BYTERANGE")]
        seg_url = ranges[0][1]
        self.assertNotEqual(seg_url, map_url, "the map and the segments are separate relay ids for the same file")
        for (n, off), url in ranges[:3]:
            st, hd, seg = await relay_get(url, {"Range": "bytes=%s-%d" % (off, int(off) + int(n) - 1)})
            self.assertEqual(st, 206, "a segment's own byterange, checked as a segment")
            self.assertIn(seg[4:8], (b"styp", b"moof", b"sidx"))

    async def test_refused_playlist_keeps_no_ids(self):
        v = await self.play("mixed.m3u8")
        st, _, _ = await relay_get(v["url"])
        self.assertEqual(st, 502, "a segment on another host refuses the whole playlist")
        ids = self.h.rt.relay.sessions[v["session"]]["ids"]
        self.assertEqual(len(ids), 1, "only the play URL's own id: the two segments it named before the refusal are gone")

    async def test_one_playback_and_revocation(self):
        v1 = await self.play("movie.mp4")
        v2 = await self.play("movie.mp4")
        st, _, _ = await relay_get(v1["url"])
        self.assertEqual(st, 404, "a new play closes the one before")
        await self.h.rt.from_guide({"t": "relayClose", "session": v2["session"]})
        st, _, _ = await relay_get(v2["url"])
        self.assertEqual(st, 404, "closed: its ids are gone")

    async def test_events_carry_the_context(self):
        v = await self.play("movie.mp4")
        r = await self.h.call("playback", {"session": v["session"], "seq": 1, "state": "started", "position": 0, "duration": 4})
        self.assertEqual(r["kind"], "ok")
        r = await self.h.call("playback", {"session": "f" * 32, "seq": 2, "state": "progress", "position": 1, "duration": 4})
        self.assertEqual(r["value"]["code"], "closed", "a session that isn't open")
        await asyncio.sleep(0.3)
        self.h.rt.log.flush()
        self.assertIn('EVENT started  {"item": "movie.mp4"}', self.h.log())

    async def test_stream_outlives_the_call_deadline(self):
        old = dict(apprun.DEADLINES)
        apprun.DEADLINES["play"] = 1.0
        try:
            v = await self.play("movie.mp4")
            await asyncio.sleep(2.5)
            st, _, body = await relay_get(v["url"])
            self.assertEqual(st, 200)
            self.assertGreater(len(body), 10000)
            self.assertEqual(self.h.rt.state, "ready")
        finally:
            apprun.DEADLINES.clear()
            apprun.DEADLINES.update(old)


class HangUp(unittest.TestCase):
    def test_player_hanging_up_mid_stream(self):
        """The real helper (its own process, SIGPIPE as it is there) survives a
        player closing the connection in the middle of a long stream"""
        if not os.path.exists("/usr/bin/ffmpeg"):
            self.skipTest("no ffmpeg")
        d = os.path.join(WORK, "hangup")
        os.makedirs(d, exist_ok=True)
        subprocess.run(["/usr/bin/ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=640x480:rate=30",
                        "-t", "30", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "10", "-pix_fmt", "yuv420p", os.path.join(d, "long.mp4")], check=True)
        self.assertGreater(os.path.getsize(os.path.join(d, "long.mp4")), 2 * 1024 * 1024)
        with open(os.path.join(d, "fixtures.json"), "w") as f:
            json.dump({"requests": [{"method": "GET", "url": "https://media.example.com/long.mp4", "status": 200, "bodyFile": "long.mp4"}]}, f)
        app = make_app("hangup_app", "from uber_tv import app, Play\n@app.play\ndef play(item):\n    return Play('https://media.example.com/long.mp4')\n"
                       "@app.playback\ndef playback(e):\n    print('heard', e['state'])\napp.run()\n",
                       perms={"net": ["media.example.com"], "play": True})
        r = subprocess.run(["/usr/bin/python3", "-I", os.path.join(ROOT, "bin", "om-pg-apprun"), "try", app, "--fixtures",
                            os.path.join(d, "fixtures.json"), "--call", "play", "--play"], capture_output=True, text=True, timeout=70)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("heard stopped", r.stdout)


class PlayRules(unittest.IsolatedAsyncioTestCase):
    async def test_play_urls_refused(self):
        main = """from uber_tv import app, Play
import json
@app.play
def play(item):
    return Play(item)
app.run()
"""
        h = Harness(make_app("player_rules", main, perms={"net": ["cdn.example.com"], "play": True}), resolver=resolver_to("10.0.0.5"))
        await h.start()
        for url in ["file:///etc/passwd", "http://127.0.0.1:1/x.mp4", "https://evil.example/x.mp4", "rtsp://cdn.example.com/x",
                    "https://cdn.example.com:8443/x.mp4"]:
            r = await h.call("play", {"item": url})
            self.assertEqual(r["kind"], "error", url)
        r = await h.call("play", {"item": "https://cdn.example.com/x.mp4"})
        self.assertEqual(r["kind"], "play", "allowed, until the relay resolves it to a private address")
        st, _, _ = await relay_get(r["value"]["url"])
        self.assertEqual(st, 502)
        await h.stop()

    async def test_no_play_permission(self):
        main = "from uber_tv import app, Play\n@app.play\ndef play(item):\n    return Play('https://cdn.example.com/x.mp4')\napp.run()\n"
        h = Harness(make_app("player_noperm", main, perms={"net": ["cdn.example.com"]}))
        await h.start()
        r = await h.call("play", {"item": "x"})
        self.assertEqual(r["kind"], "error")
        self.assertIn("play", r["value"]["text"])
        await h.stop()


SIGNIN_APP = """import time
from uber_tv import app, fetch, secret, Screen, Message
@app.home
def home():
    return Screen("signed in" if secret("token") else "signed out")
@app.sign_in
def sign_in(flow):
    r = fetch(SERVER + "/jf/QuickConnect/Initiate", method="POST").json()
    flow.show_code(r["Code"], url=SERVER + "/jf/web/qc", expires=r.get("expires", 60))
    while flow.sleep(0.2):
        st = fetch(SERVER + "/jf/QuickConnect/Connect?Secret=" + r["Secret"]).json()
        if st["Authenticated"]:
            flow.keep("token", "tok-" + r["Secret"])
            flow.done(True, "Signed in.")
            return
@app.sign_out
def sign_out():
    print("signing out with", secret("token") is not None)
app.run()
"""


class SignIn(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.polls = 0
        self.expires = 60

        def handler(line, headers):
            path = line.split()[1]
            if path.startswith("/jf/QuickConnect/Initiate"):
                return 200, {}, json.dumps({"Code": "ABC123", "Secret": "s3", "expires": self.expires}).encode()
            if path.startswith("/jf/QuickConnect/Connect"):
                self.polls += 1
                return 200, {}, json.dumps({"Authenticated": self.polls >= 3 and self.expires > 5}).encode()
            return 404, {}, b""
        self.srv = await LocalServer(handler).start()
        self.base = "http://127.0.0.1:" + str(self.srv.port)
        main = "SERVER = %r\n" % self.base + SIGNIN_APP
        self.folder = make_app("signin", main, perms={"server": {"label": "S"}, "signIn": "code"})

    async def asyncTearDown(self):
        self.srv.close()

    def flow(self):
        return secrets_hex()

    async def wait_frame(self, h, t, wait=8):
        end = time.monotonic() + wait
        while time.monotonic() < end:
            for f in h.frames:
                if f.get("t") == t:
                    return f
            await asyncio.sleep(0.05)
        return None

    async def test_code_flow_after_the_result(self):
        h = Harness(self.folder, server=self.base + "/jf")
        await h.start()
        flow = secrets_hex()
        r = await h.call("signIn", {"flow": flow})
        self.assertEqual(r["kind"], "ok", "the signIn call answers at once; the flow goes on after it")
        code = await self.wait_frame(h, "signInCode")
        self.assertEqual((code["flow"], code["code"], code["url"]), (flow, "ABC123", self.base + "/jf/web/qc"))
        done = await self.wait_frame(h, "signInDone")
        self.assertEqual((done["flow"], done["ok"], done["message"]), (flow, True, "Signed in."))
        self.assertGreaterEqual(self.polls, 3, "flow-owned fetches after the call's result")
        kept = json.load(open(h.cfg["secretsPath"]))
        self.assertEqual(kept["signIn"], {"server": self.base + "/jf", "values": {"token": "tok-s3"}})
        r = await h.call("home")
        self.assertEqual(r["value"]["title"], "signed in")
        await h.stop()
        # the same app pointed at another server: that sign-in isn't its
        h2 = Harness(self.folder, server=self.base + "/other", secretsPath=h.cfg["secretsPath"])
        await h2.start()
        r = await h2.call("home")
        self.assertEqual(r["value"]["title"], "signed out", "a sign-in belongs to its server")
        await h2.stop()

    async def test_the_guides_record_decides_the_sign_ins_values(self):
        # run mode: what a sign-in kept is the app's only once the guide takes it as done
        h = Harness(self.folder, server=self.base + "/jf", secretsSet=[], signedIn=False)
        await h.start()
        await h.call("signIn", {"flow": secrets_hex()})
        await self.wait_frame(h, "signInDone")
        r = await h.call("home")
        self.assertEqual(r["value"]["title"], "signed out", "kept, but not the app's until the guide says so")
        await h.rt.from_guide({"t": "signedIn"})
        r = await h.call("home")
        self.assertEqual(r["value"]["title"], "signed in")
        await h.stop()
        # a sign-out whose clean-up failed: the token is still in the file, and the record says signed out
        h2 = Harness(self.folder, server=self.base + "/jf", secretsPath=h.cfg["secretsPath"], secretsSet=[], signedIn=False)
        await h2.start()
        r = await h2.call("home")
        self.assertEqual(r["value"]["title"], "signed out", "what a failed clean-up left isn't the app's")
        await h2.stop()

    async def test_sign_out_forgets(self):
        h = Harness(self.folder, server=self.base + "/jf")
        await h.start()
        await h.call("signIn", {"flow": secrets_hex()})
        await self.wait_frame(h, "signInDone")
        r = await h.call("signOut")
        self.assertEqual(r["kind"], "ok")
        await h.rt.stop("normal", "", "signIn")
        kept = json.load(open(h.cfg["secretsPath"]))
        self.assertEqual(kept["signIn"]["values"], {}, "the guide forgets the sign-in whatever the app did")
        self.assertIn("signing out with True", h.log(), "the app's signOut ran while its token still worked")

    async def test_expiry(self):
        self.expires = 5            # the helper keeps a flow at least 5 s
        h = Harness(self.folder, server=self.base + "/jf")
        await h.start()
        flow = secrets_hex()
        await h.call("signIn", {"flow": flow})
        done = await self.wait_frame(h, "signInDone", wait=10)
        self.assertEqual((done["flow"], done["ok"], done["message"]), (flow, False, "The code expired."))
        self.assertIsNone(h.rt.flow)
        self.assertFalse(os.path.exists(h.cfg["secretsPath"]) and json.load(open(h.cfg["secretsPath"]))["signIn"]["values"])
        await h.stop()

    async def test_cancel(self):
        h = Harness(self.folder, server=self.base + "/jf")
        await h.start()
        flow = secrets_hex()
        await h.call("signIn", {"flow": flow})
        await self.wait_frame(h, "signInCode")
        await h.rt.from_guide({"t": "signInCancel", "flow": flow})
        done = await self.wait_frame(h, "signInDone")
        self.assertEqual((done["ok"], done["message"]), (False, ""))
        polls = self.polls
        await asyncio.sleep(0.8)
        self.assertLessEqual(self.polls - polls, 1, "the app's flow stops polling once it's called off")
        await h.stop()

    async def test_foreign_flow_frames(self):
        body = ("send({'t':'ready'})\n"
                "line = json.loads(sys.stdin.buffer.readline())\n"
                "f = line['args']['flow']\n"
                "send({'t':'result','id':line['id'],'ok':True})\n"
                "other = 'f' * 32\n"
                "send({'t':'signInCode','flow':other,'code':'EVIL','url':'','expires':60})\n"
                "send({'t':'secretSet','id':5,'flow':other,'name':'token','value':'evil'})\n"
                "send({'t':'signInDone','flow':other,'ok':True,'message':'pwned'})\n"
                "send({'t':'signInCode','flow':f,'code':'GOOD','url':'https://not-allowed.example/','expires':60})\n"
                "send({'t':'signInCode','flow':f,'code':'GOOD2','url':'','expires':60})\n"
                "time.sleep(5)\n")
        h = Harness(make_app("raw_flow", RAW + body, perms={"server": {"label": "S"}, "signIn": "code"}), server=self.base + "/jf")
        await h.start()
        flow = secrets_hex()
        await h.call("signIn", {"flow": flow})
        await asyncio.sleep(1)
        codes = [f for f in h.frames if f.get("t") == "signInCode"]
        self.assertEqual([c["code"] for c in codes], ["GOOD2"], "another flow's frames are ignored; a link off its origins is refused")
        self.assertFalse([f for f in h.frames if f.get("t") == "signInDone"])
        self.assertFalse(os.path.exists(h.cfg["secretsPath"]), "a secret for another flow isn't kept")
        await h.stop()

    async def test_no_sign_in_permission(self):
        h = Harness(make_app("nosignin", "SERVER=''\n" + SIGNIN_APP, perms={"server": {"label": "S"}}), server=self.base + "/jf")
        await h.start()
        r = await h.call("signIn", {"flow": secrets_hex()})
        self.assertEqual(r["kind"], "error")
        await h.stop()


def secrets_hex():
    return os.urandom(16).hex()


class Pinning(unittest.IsolatedAsyncioTestCase):
    async def test_pinned_self_signed_server(self):
        import ssl
        d = os.path.join(WORK, "tls")
        os.makedirs(d, exist_ok=True)
        key, crt = os.path.join(d, "k.pem"), os.path.join(d, "c.pem")
        subprocess.run(["/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", crt,
                        "-days", "1", "-subj", "/CN=home.test", "-addext", "subjectAltName=IP:127.0.0.1"], check=True, capture_output=True)
        der = ssl.PEM_cert_to_DER_cert(open(crt).read())
        pin = hashlib.sha256(der).hexdigest()
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(crt, key)
        srv = LocalServer()
        srv.server = await asyncio.start_server(srv.serve, "127.0.0.1", 0, ssl=ctx)
        port = srv.server.sockets[0].getsockname()[1]
        base = "https://127.0.0.1:%d" % port
        folder = make_app("pinned", FETCHER, perms={"server": {"label": "S"}})
        for given, want in [("", "error tls"), ("0" * 64, "error pin"), (pin, "status 200")]:
            h = Harness(folder, server=base + "/jf", pin=given)
            self.assertTrue(await h.start(), h.rt.stop_why)
            res = await fetch_via(h, base + "/jf/x")
            self.assertTrue(res.startswith(want), (given[:8], res))
            for _ in range(3):   # after a refused handshake, the runtime's own pipes still work
                self.assertTrue((await fetch_via(h, base + "/jf/x")).startswith(want))
            await h.stop()
        srv.close()


class StorageAndSecrets(unittest.IsolatedAsyncioTestCase):
    async def test_store_quota_and_coalescing(self):
        st = apprun.Store(os.path.join(WORK, "q", "store.json"))
        for i in range(256):
            self.assertEqual(st.put("k" + str(i), b"x", False), "")
        self.assertIn("256", st.put("one-more", b"x", False))
        st2 = apprun.Store(os.path.join(WORK, "q", "store2.json"))
        self.assertIn("64 KB", st2.put("big", b"x" * (64 * 1024 + 1), False))
        for i in range(64):
            st2.put("v" + str(i), b"x" * (64 * 1024), False)
        self.assertIn("4 MB", st2.put("v64", b"x" * 1024, False))
        writes = []
        real = apprun.write_private
        apprun.write_private = lambda p, d: (writes.append(p), real(p, d))
        try:
            main = """from uber_tv import app, storage, Message
@app.home
def home():
    for i in range(40):
        storage.put("k" + str(i % 5), "v" * 100)
    return Message("x")
@app.action
def action(item, how):
    return __import__("uber_tv").Message(storage.get(item) or "none")
app.run()
"""
            h = Harness(make_app("store", main, perms={"storage": True}))
            await h.start()
            await h.call("home")
            await asyncio.sleep(1.3)
            store_writes = [w for w in writes if w.endswith("store.json")]
            self.assertLessEqual(len(store_writes), 2, "forty puts, at most a write a second")
            r = await h.call("action", {"item": "k1", "action": "get"})
            self.assertEqual(r["value"]["text"], "v" * 100)
            await h.stop()
            data = json.load(open(h.cfg["storePath"]))
            self.assertEqual(len(data["keys"]), 5)
            self.assertEqual(oct(os.stat(h.cfg["storePath"]).st_mode & 0o777), "0o600")
        finally:
            apprun.write_private = real

    async def test_no_storage_permission(self):
        main = "from uber_tv import app, storage, Message, AppError\n@app.home\ndef home():\n    storage.put('a', 'b')\napp.run()\n"
        h = Harness(make_app("nostore", main))
        await h.start()
        r = await h.call("home")
        self.assertEqual(r["kind"], "error")
        self.assertIn("storage", r["value"]["text"])
        await h.stop()

    async def test_secret_stays_out_of_logs_and_argv(self):
        secret = "s3cr3t-VALUE-12345"
        main = """from uber_tv import app, secret, fetch, Message, FetchError
@app.home
def home():
    s = secret("apiKey")
    print("the key is", s)
    try:
        fetch("https://api.example.com/x?key=" + s, headers={"Authorization": "Bearer " + s})
    except FetchError:
        pass
    return Message("ok")
app.run()
"""
        h = Harness(make_app("secretlog", main, perms={"net": ["api.example.com"]}, settings=[{"key": "apiKey", "type": "secret", "label": "Key"}]),
                    online=False, fixtures=apprun.Fixtures(""))
        os.makedirs(os.path.dirname(h.cfg["secretsPath"]), exist_ok=True)
        apprun.write_private(h.cfg["secretsPath"], json.dumps({"user": {"apiKey": secret}}).encode())
        await h.start()
        self.assertNotIn(secret, " ".join(h.rt.sandbox()))
        self.assertNotIn(secret, open("/proc/" + str(h.rt.proc.pid) + "/cmdline", "rb").read().decode(errors="replace"))
        await h.call("home")
        await h.stop()
        log = h.log()
        self.assertIn("the key is", log)
        self.assertNotIn(secret, log)
        self.assertNotIn(secret, json.dumps(h.frames))

    def test_authorization_redacted_whole(self):
        log = apprun.Log(None, lambda: set())
        for line, leak in [("Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig", "eyJ"),
                           ('{"Authorization": "MediaBrowser Client=\\"Uber TV\\", Token=\\"s3cr3t\\""}', "s3cr3t"),
                           ("authorization=Basic dXNlcjpwYXNz", "dXNlcjpwYXNz"),
                           ("headers {'Authorization': 'Bearer abc.def.ghi'}", "abc.def")]:
            out = log.redact(line)
            self.assertNotIn(leak, out, out)
            self.assertIn("[hidden]", out)
        self.assertIn("[hidden]", log.redact("X-Emby-Token: abcdef"))
        self.assertNotIn("abcdef", log.redact("X-Emby-Token: abcdef"))

    async def test_only_declared_secrets(self):
        main = "from uber_tv import app, secret, Message\n@app.home\ndef home():\n    return Message(str(secret('apiKey')))\n" \
               "@app.action\ndef action(i, a):\n    return Message(str(secret('apiKey')))\napp.run()\n"
        for declared, want in [(True, "kept-key"), (False, "None")]:
            settings = [{"key": "apiKey", "type": "secret", "label": "Key"}] if declared else []
            h = Harness(make_app("declared_" + str(declared).lower(), main, settings=settings))
            os.makedirs(os.path.dirname(h.cfg["secretsPath"]), exist_ok=True)
            apprun.write_private(h.cfg["secretsPath"], json.dumps({"user": {"apiKey": "kept-key"}}).encode())
            await h.start()
            r = await h.call("action", {"item": "x", "action": "y"})
            self.assertEqual(r["value"]["text"], want, "a setting the app no longer declares isn't its secret any more")
            await h.stop()

    async def test_only_secrets_the_guide_marked_set(self):
        # a secret an update dropped (its clear failed) and a later version declares again: not the app's, unmarked
        main = "from uber_tv import app, secret, Message\n@app.action\ndef action(i, a):\n    return Message(str(secret('apiKey')))\napp.run()\n"
        for marked, want in [(["apiKey"], "kept-key"), ([], "None")]:
            h = Harness(make_app("marked_" + str(bool(marked)).lower(), main, settings=[{"key": "apiKey", "type": "secret", "label": "Key"}]),
                        secretsSet=marked, signedIn=False)
            os.makedirs(os.path.dirname(h.cfg["secretsPath"]), exist_ok=True)
            apprun.write_private(h.cfg["secretsPath"], json.dumps({"user": {"apiKey": "kept-key"}}).encode())
            await h.start()
            r = await h.call("action", {"item": "x", "action": "y"})
            self.assertEqual(r["value"]["text"], want)
            await h.stop()

    def test_a_sign_in_reads_what_it_keeps_while_it_runs(self):
        path = os.path.join(WORK, "inflow", "secrets.json")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        s = apprun.Secrets(path, "http://127.0.0.1:9/jf", [], True, [], False)
        self.assertEqual(s.set_sign_in("token", "fresh"), "")
        self.assertEqual(s.get("token"), "fresh", "during the flow that kept it")
        s.in_flow = False
        self.assertIsNone(s.get("token"), "after it, only once the guide says signed in")
        s.signed_in = True
        self.assertEqual(s.get("token"), "fresh")

    def test_every_secret_kept_is_read_back(self):
        """32 secrets of the most text each may be, however JSON writes it:
        the file is read back whole and the next one kept loses none; a
        sign-in's value past 4 KB of UTF-8 is refused when it's set"""
        path = os.path.join(WORK, "bigsecrets", "secrets.json")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        s = apprun.Secrets(path, "http://127.0.0.1:9/jf", [], True, [], False)
        self.assertEqual(s.set_sign_in("one", "\u00e9" * 2049), "a secret is up to 4 KB of text")
        for i in range(31):
            self.assertEqual(s.set_sign_in("k%d" % i, "\u00e9" * 2048), "")   # 4 KB of UTF-8, 12 KB of JSON
        self.assertGreater(os.path.getsize(path), 256 * 1024)
        self.assertEqual(s.set_sign_in("last", "x"), "")
        self.assertEqual(len(apps.read_secrets(path)["signIn"]["values"]), 32, "none lost")
        # what you type in its settings, through bin/om-pg-apps: control characters, 6 bytes each in JSON
        path = os.path.join(WORK, "bigsecrets", "typed.json")
        for i in range(32):
            apps.do_secret_set(path, "k%d" % i, "\x01" * 4096)
        self.assertGreater(os.path.getsize(path), 768 * 1024)
        self.assertEqual(len(apps.read_secrets(path)["user"]), 32, "none lost")

    def test_a_secrets_file_that_cant_be_read_is_left_as_it_is(self):
        path = os.path.join(WORK, "badsecrets", "secrets.json")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        for bad in (b"{not json", b"[]", b'{"user": {}}' + b" " * (1024 * 1024)):
            with open(path, "wb") as f:
                f.write(bad)
            s = apprun.Secrets(path, "http://127.0.0.1:9/jf", [], True, [], False)
            self.assertIn("couldn't be read", s.set_sign_in("token", "fresh"))
            with self.assertRaises(apps.Bad):
                apps.do_secret_set(path, "apiKey", "typed")
            with self.assertRaises(apps.Bad):
                apps.do_secret_clear(path, "apiKey")
            s.forget_sign_in()
            self.assertEqual(open(path, "rb").read(), bad, "never written over")
        apps.do_secret_clear(path, "*")
        self.assertEqual(apps.read_secrets(path), {"user": {}, "signIn": {"server": "", "values": {}}}, "forgetting all of it needs nothing from it")

    async def test_sign_in_values_only_for_an_app_that_signs_in(self):
        main = "from uber_tv import app, secret, Message\n@app.action\ndef action(i, a):\n    return Message(str(secret('token')))\napp.run()\n"
        srv = "http://127.0.0.1:9/jf"
        for signs_in, want in [(True, "old-token"), (False, "None")]:
            perms = {"server": {"label": "S"}, "signIn": "code"} if signs_in else {"server": {"label": "S"}}
            h = Harness(make_app("signsin_" + str(signs_in).lower(), main, perms=perms), server=srv)
            os.makedirs(os.path.dirname(h.cfg["secretsPath"]), exist_ok=True)
            apprun.write_private(h.cfg["secretsPath"], json.dumps({"user": {}, "signIn": {"server": srv, "values": {"token": "old-token"}}}).encode())
            await h.start()
            r = await h.call("action", {"item": "x", "action": "y"})
            self.assertEqual(r["value"]["text"], want, "a version that no longer signs in doesn't get the old token")
            await h.stop()

    async def test_offline_gate_no_network(self):
        tried = []
        real_gai = socket.getaddrinfo
        real_conn = net.connect

        async def no_connect(*a, **k):
            tried.append(a)
            raise AssertionError("connect called offline")
        socket.getaddrinfo = lambda *a, **k: tried.append(a) or real_gai(*a, **k)
        net.connect = no_connect
        try:
            h = Harness(make_app("offline", FETCHER, perms={"net": ["api.example.com"]}), online=False, fixtures=apprun.Fixtures(""))
            await h.start()
            res = await fetch_via(h, "https://api.example.com/x")
            self.assertIn("error offline", res)
            await h.stop()
        finally:
            socket.getaddrinfo = real_gai
            net.connect = real_conn
        self.assertEqual(tried, [], "no lookup and no socket offline")


class Toolkit(unittest.TestCase):
    def test_try_offline_cli(self):
        app = make_app("trycli", FETCHER.replace("@app.action", "@app.home\ndef home():\n    return action(json.dumps({'url': 'https://api.example.com/x'}), 'go')\n@app.action"),
                       perms={"net": ["api.example.com"]})
        # home returns a Message, so it's refused as a home answer: the try still reports cleanly and offline
        r = subprocess.run(["/usr/bin/python3", "-I", os.path.join(ROOT, "bin", "om-pg-apprun"), "try", app], capture_output=True, text=True, timeout=70)
        self.assertIn("network: offline", r.stdout)
        self.assertNotEqual(r.returncode, 0)

    def test_try_runs_in_a_limited_scope(self):
        """try's sandbox runs in a systemd user scope with the guide's limits"""
        if subprocess.run(["/usr/bin/systemctl", "--user", "is-system-running"], capture_output=True).returncode not in (0, 1):
            self.skipTest("no systemd user manager")
        app = make_app("tryscope", "import time\nfrom uber_tv import app, Screen\n@app.home\ndef home():\n    time.sleep(4)\n    return Screen('slow')\napp.run()\n")
        p = subprocess.Popen(["/usr/bin/python3", "-I", os.path.join(ROOT, "bin", "om-pg-apprun"), "try", app], stdout=subprocess.PIPE, text=True)
        unit, props = "", {}
        for _ in range(30):
            time.sleep(0.2)
            out = subprocess.run(["/usr/bin/systemctl", "--user", "list-units", "--type=scope", "--plain", "--no-legend", "om-pg-try-*"],
                                 capture_output=True, text=True).stdout.split()
            if out:
                unit = out[0]
                break
        self.assertTrue(unit.startswith("om-pg-try-"), "a scope named om-pg-try-…")
        r = subprocess.run(["/usr/bin/systemctl", "--user", "show", unit, "-pMemoryMax", "-pTasksMax", "-pCPUQuotaPerSecUSec"], capture_output=True, text=True)
        props = dict(l.split("=", 1) for l in r.stdout.split())
        self.assertEqual((props["MemoryMax"], props["TasksMax"], props["CPUQuotaPerSecUSec"]), (str(320 * 1024 * 1024), "48", "500ms"))
        out, _ = p.communicate(timeout=60)
        self.assertIn("SCREEN slow", out)
        time.sleep(0.5)
        left = subprocess.run(["/usr/bin/systemctl", "--user", "list-units", "--type=scope", "--plain", "--no-legend", unit], capture_output=True, text=True).stdout
        self.assertNotIn("running", left, "nothing left after the try")

    def test_scores_offline(self):
        """The bundled scores app, under try, against a recorded ESPN scoreboard"""
        r = subprocess.run(["/usr/bin/python3", "-I", os.path.join(ROOT, "bin", "om-pg-apprun"), "try",
                            os.path.join(ROOT, "apps", "first-party", "tv.uber.scores"), "--fixtures",
                            os.path.join(ROOT, "tests", "fixtures", "scores-try.json"), "--call", "home",
                            "--call", 'details:{"item":"999000001"}', "--json"], capture_output=True, text=True, timeout=70)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        lines = [json.loads(l) for l in r.stdout.splitlines() if l.startswith("{")]
        home, detail = lines[0], lines[1]
        self.assertEqual(home["kind"], "screen")
        self.assertEqual([row["id"] for row in home["value"]["rows"]], ["in", "pre", "post"])
        self.assertTrue(home["value"]["live"], "api 4: live, its games updating while it's on")
        self.assertEqual(home["value"]["refresh"], 60.0)
        self.assertEqual(detail["kind"], "detail")
        self.assertIn("Dallas Cowboys", detail["value"]["title"])

    def test_whole_plugin_by_absolute_path(self):
        """Nothing in the plugin starts a program found through PATH, collects a
        command's output without a bound, or deletes with rm -rf"""
        import glob
        import re
        qml = glob.glob(os.path.join(ROOT, "*.qml")) + glob.glob(os.path.join(ROOT, "ui", "*.qml"))
        bad = []
        for f in qml:
            src = open(f).read()
            if "StdioCollector" in src:
                bad.append(os.path.basename(f) + ": an unbounded StdioCollector")
            for m in re.finditer(r'(command:\s*\[|command = \[|execDetached\(\[|\.start\(\[|\.replace\(\[|argv:\s*(?:root\.\w+\s*\?\s*)?\[)\s*"([^"]*)"', src):
                if not m.group(2).startswith("/"):
                    bad.append(os.path.basename(f) + ": " + m.group(2) + " by name")
            if "rm -rf" in src.replace("never rm -rf", ""):
                bad.append(os.path.basename(f) + ": rm -rf")
        for f in glob.glob(os.path.join(ROOT, "bin", "om-pg-*")):
            src = open(f).read()
            first = src.split("\n", 1)[0]
            if first.startswith("#!") and "/env " in first:
                bad.append(os.path.basename(f) + ": an env shebang")
            for m in re.finditer(r'subprocess\.(?:run|Popen|check_output|call)\(\[\s*"([^"]+)"', src):
                if not m.group(1).startswith("/"):
                    bad.append(os.path.basename(f) + ": " + m.group(1) + " by name")
        skill = open(os.path.join(ROOT, "bin", "om-pg-skill")).read()
        self.assertIn("PATH=/usr/bin", skill)
        self.assertEqual(bad, [])

    def test_no_program_by_path(self):
        """Every program the helper starts is named by its absolute path"""
        src = open(os.path.join(ROOT, "bin", "om-pg-apprun")).read()
        self.assertIn('BWRAP = "/usr/bin/bwrap"', src)
        self.assertIn('PYTHON = "/usr/bin/python3"', src)
        self.assertNotIn("shutil.which", src)
        self.assertNotIn("os.system", src)
        self.assertNotIn("import subprocess", src)
        self.assertEqual(src.count("create_subprocess_exec("), 1, "one place starts a process")
        self.assertIn("create_subprocess_exec(\n                *self.sandbox()", src)
        h = Harness(make_app("paths", "from uber_tv import app\napp.run()\n"))
        h.rt = None
        fake = type("R", (), {"app_dir": "/x", "manifest": {"main": "main.py"}, "cfg": {}})()
        argv = apprun.Runtime.sandbox(fake)
        self.assertEqual(argv[0], "/usr/bin/bwrap")
        self.assertIn("/usr/bin/python3", argv)
        fake.cfg = {"scope": "om-pg-try-0123456789abcdef"}
        argv = apprun.Runtime.sandbox(fake)
        self.assertEqual(argv[:4], ["/usr/bin/systemd-run", "--user", "--scope", "--quiet"])
        self.assertIn("/usr/bin/bwrap", argv)
        for name in ("appnet.py", "appblocks.py", "appmedia.py"):
            self.assertNotIn("subprocess", open(os.path.join(ROOT, "lib", name)).read())


class StartCleanUp(unittest.TestCase):
    """Clean-ups the guide couldn't finish (a sign-out's, an update's dropped
    secrets): the helper does them before the app runs, or it doesn't run"""

    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="om-pg-cleanup-", dir=WORK)
        self.source = "file:00000000cafef00d"
        self.server = "http://127.0.0.1:9/jf"
        sd = apps.source_dir(self.source)
        main = "from uber_tv import app, secret, Screen\n@app.home\ndef home():\n    return Screen(str(secret('token')) + '/' + str(secret('apiKey')))\napp.run()\n"
        folder = make_app("clean", main, perms={"server": {"label": "S"}, "signIn": "code"},
                          settings=[{"key": "apiKey", "type": "secret", "label": "Key"}])
        shutil.copytree(folder, os.path.join(self.home, ".local", "share", "om-pg", "apps", sd, "tv.example.clean", "1.0.0"))
        self.secrets = os.path.join(self.home, ".config", "om-pg", "app-secrets", sd, "tv.example.clean.json")
        os.makedirs(os.path.dirname(self.secrets))

    def start(self, **init):
        p = subprocess.Popen(["/usr/bin/python3", "-I", "-S", "-B", "-u", os.path.join(ROOT, "bin", "om-pg-apprun"), "run"],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env={"HOME": self.home})
        frame = dict({"t": "init", "id": "tv.example.clean", "source": self.source, "version": "1.0.0", "gen": 1, "server": self.server}, **init)
        p.stdin.write((json.dumps(frame) + "\n").encode())
        p.stdin.flush()
        return p, json.loads(p.stdout.readline())

    def stop(self, p):
        p.stdin.close()
        p.wait(10)

    def test_owed_clean_ups_are_done_first(self):
        apprun.write_private(self.secrets, json.dumps({"user": {"apiKey": "dropped", "other": "o"},
                                                        "signIn": {"server": self.server, "values": {"token": "old"}}}).encode())
        # even told signed in and the key set, what's owed is cleared before the app runs
        p, first = self.start(forget=["signIn"], clear=["apiKey"], secretsSet=["apiKey"], signedIn=True)
        self.assertEqual(first, {"t": "state", "state": "ready"})
        p.stdin.write(b'{"t":"call","id":1,"method":"home","args":{}}\n')
        p.stdin.flush()
        self.assertEqual(json.loads(p.stdout.readline())["value"]["title"], "None/None")
        self.stop(p)
        kept = json.load(open(self.secrets))
        self.assertEqual((kept["user"], kept["signIn"]["values"]), ({"other": "o"}, {}))

    def test_a_clean_up_that_fails_keeps_the_app_from_running(self):
        os.makedirs(self.secrets)            # not a plain file: clearing it fails
        p, first = self.start(forget=["signIn"])
        self.assertEqual((first["t"], first["state"]), ("state", "stopped"))
        self.assertIn("couldn't be cleared first", first["text"])
        self.stop(p)

    def test_a_bad_clean_up_list_is_refused(self):
        p, first = self.start(forget=["everything"])
        self.assertEqual(first["state"], "stopped")
        self.stop(p)


class Scope(unittest.TestCase):
    """The real tree: systemd-run scope, the helper, bwrap, the app"""

    def setUp(self):
        if not os.path.exists("/usr/bin/systemd-run") or subprocess.run(["/usr/bin/systemctl", "--user", "is-system-running"], capture_output=True).returncode not in (0, 1):
            self.skipTest("no systemd user manager")
        self.home = tempfile.mkdtemp(prefix="om-pg-scope-")
        self.source = "file:00000000deadbeef"
        sd = apps.source_dir(self.source)
        target = os.path.join(self.home, ".local", "share", "om-pg", "apps", sd, "tv.example.scope", "1.0.0")
        os.makedirs(target)
        with open(os.path.join(target, "app.json"), "w") as f:
            json.dump({"id": "tv.example.scope", "name": "Scope", "version": "1.0.0", "api": 2, "kind": "app", "author": "T",
                       "main": "main.py", "permissions": {}}, f)
        with open(os.path.join(target, "main.py"), "w") as f:
            f.write("from uber_tv import app, Screen\n@app.home\ndef home():\n    return Screen('scope')\napp.run()\n")
        self.unit = "om-pg-app-" + sd + "-" + hashlib.sha256(b"tv.example.scope").hexdigest()[:12] + "-" + str(os.getpid())

    def tearDown(self):
        subprocess.run(["/usr/bin/systemctl", "--user", "stop", self.unit + ".scope"], capture_output=True)
        shutil.rmtree(self.home, ignore_errors=True)

    def start(self):
        env = {k: os.environ[k] for k in ("XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS") if k in os.environ}
        env["HOME"] = self.home
        p = subprocess.Popen(["/usr/bin/systemd-run", "--user", "--scope", "--quiet", "--unit=" + self.unit,
                              "-p", "MemoryMax=320M", "-p", "MemorySwapMax=0", "-p", "CPUQuota=50%", "-p", "TasksMax=48", "--",
                              "/usr/bin/python3", "-I", "-S", "-B", "-u", os.path.join(ROOT, "bin", "om-pg-apprun"), "run"],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        p.stdin.write((json.dumps({"t": "init", "id": "tv.example.scope", "source": self.source, "version": "1.0.0", "gen": 1}) + "\n").encode())
        p.stdin.flush()
        first = json.loads(p.stdout.readline())
        self.assertEqual(first, {"t": "state", "state": "ready"})
        return p

    def show(self, *props):
        r = subprocess.run(["/usr/bin/systemctl", "--user", "show", self.unit + ".scope"] + ["-p" + x for x in props], capture_output=True, text=True)
        return dict(l.split("=", 1) for l in r.stdout.strip().splitlines() if "=" in l)

    def gone(self, wait=6):
        end = time.time() + wait
        while time.time() < end:
            s = self.show("ActiveState", "LoadState")
            alive = subprocess.run(["/usr/bin/pgrep", "-f", self.home], capture_output=True).stdout.strip()
            if s.get("ActiveState") in ("inactive", "failed", "") and not alive:
                return True
            time.sleep(0.2)
        return False

    def test_limits_on_the_live_scope_and_membership(self):
        p = self.start()
        s = self.show("MemoryMax", "MemorySwapMax", "TasksMax", "CPUQuotaPerSecUSec", "ActiveState", "ControlGroup")
        self.assertEqual(s["ActiveState"], "active")
        self.assertEqual(s["MemoryMax"], str(320 * 1024 * 1024))
        self.assertEqual(s["MemorySwapMax"], "0")
        self.assertEqual(s["TasksMax"], "48")
        self.assertEqual(s["CPUQuotaPerSecUSec"], "500ms")
        procs = os.path.join("/sys/fs/cgroup", s["ControlGroup"].lstrip("/"), "cgroup.procs")
        if os.path.exists(procs):
            with open(procs) as f:
                members = f.read().split()
            self.assertIn(str(p.pid), members, "the started process (the helper, exec'd in place) is in the scope")
            self.assertGreaterEqual(len(members), 3, "helper, bwrap and the app")
        p.stdin.write(b'{"t":"call","id":1,"method":"home","args":{}}\n')
        p.stdin.flush()
        self.assertEqual(json.loads(p.stdout.readline())["value"]["title"], "scope")
        p.stdin.close()
        p.wait(10)
        self.assertTrue(self.gone(), "closing stdin (the guide exiting) leaves nothing behind")

    def test_helper_killed(self):
        p = self.start()
        os.kill(p.pid, 9)
        p.wait(5)
        self.assertTrue(self.gone(), "killing the helper takes the sandbox with it")

    def test_scope_stopped(self):
        p = self.start()
        subprocess.run(["/usr/bin/systemctl", "--user", "kill", "--signal=KILL", self.unit + ".scope"], capture_output=True)
        p.wait(5)
        self.assertTrue(self.gone(), "killing the unit leaves no survivor")

    def test_app_killed_inside(self):
        p = self.start()
        kids = subprocess.run(["/usr/bin/pgrep", "-f", "/sdk/launch.py"], capture_output=True, text=True).stdout.split()
        mine = []
        for k in kids:
            with open("/proc/" + k + "/cgroup") as f:
                if self.unit in f.read():
                    mine.append(k)
        self.assertTrue(mine)
        for k in mine:
            os.kill(int(k), 9)
        line = json.loads(p.stdout.readline())
        self.assertEqual((line["state"], line["why"]), ("stopped", "crash"))
        p.wait(5)
        self.assertTrue(self.gone())


# ---- API 3 ----------------------------------

def checked(kind, value, api, method=None):
    """blocks.result for one block, every link a token named after it"""
    return blocks.result(method or {"screen": "home", "detail": "details", "rows": "homeRow"}[kind],
                         {"t": "result", "id": 1, kind: value}, lambda ref, where: {"token": ref.get("url", ref.get("asset"))}, api)


def refused(test, kind, value, api, why):
    with test.assertRaises(blocks.Invalid, msg=why) as cm:
        checked(kind, value, api)
    return str(cm.exception)


class Api3Blocks(unittest.TestCase):
    """Every API 3 field and cap, and API 2 exactly as it was"""

    def test_api2_unchanged(self):
        _, v = checked("screen", {"rows": [{"id": "Any ID at all!", "items": [{"id": "a", "title": "A"}]}]}, 2)
        self.assertEqual(sorted(v["rows"][0]), ["id", "items", "layout", "title"], "an API 2 row as it always was")
        self.assertEqual(v["rows"][0]["layout"], "row")
        self.assertEqual(sorted(v["rows"][0]["items"][0]), ["badge", "id", "image", "kind", "progress", "subtitle", "title"])
        for row in ({"id": "r", "shape": "poster", "items": []}, {"id": "r", "size": "small", "items": []},
                    {"id": "r", "layout": "hero", "items": []}, {"id": "r", "layout": None, "items": []},
                    {"id": "r", "items": [{"id": "a", "title": "A", "images": {}}]},
                    {"id": "r", "items": [{"id": "a", "title": "A", "meta": "m"}]},
                    {"id": "r", "items": [{"id": "a", "title": "A", "text": "t"}]},
                    {"id": "r", "items": [{"id": "a", "title": "A", "watched": True}]}):
            refused(self, "screen", {"rows": [row]}, 2, "API 2 refuses an API 3 field: " + str(row))
        for d in ({"title": "T", "style": "classic"}, {"title": "T", "logo": {"url": "https://x"}}, {"title": "T", "meta": "m"},
                  {"title": "T", "chips": ["a"]}, {"title": "T", "rows": [{"id": "r" + str(i), "items": []} for i in range(4)]}):
            refused(self, "detail", d, 2, "API 2 details refuse " + str(sorted(d)))
        refused(self, "rows", [{"id": "a", "title": "A", "images": {"wide": {"url": "https://x"}}}], 2, "API 2 Home rows too")

    def test_api3_rows(self):
        _, v = checked("screen", {"rows": [{"id": "lib-0a1b2c", "shape": "poster", "size": "large", "items": []},
                                           {"id": "continue_watching", "layout": "grid", "items": []}]}, 3)
        a, b = v["rows"]
        self.assertEqual((a["layout"], a["shape"], a["size"]), (None, "poster", "large"), "an unset layout stays unset (app.json's can apply)")
        self.assertEqual((b["layout"], b["shape"], b["size"]), ("grid", None, None))
        for rid in ("Upper", "1st", "-x", "a b", "a.b", "a/b", "é", "a" * 65, "__proto__", ""):
            refused(self, "screen", {"rows": [{"id": rid, "items": []}]}, 3, "the row id pattern: " + repr(rid))
        self.assertEqual(checked("screen", {"rows": [{"id": "a" * 64, "items": []}]}, 3)[1]["rows"][0]["id"], "a" * 64)
        for k, bad in (("layout", "carousel"), ("shape", "oval"), ("size", "huge"), ("shape", 3)):
            refused(self, "screen", {"rows": [{"id": "r", k: bad, "items": []}]}, 3, k + " " + repr(bad))
        hero = [{"id": str(i), "title": "x"} for i in range(11)]
        self.assertEqual(len(checked("screen", {"rows": [{"id": "h", "layout": "hero", "items": hero[:10]}]}, 3)[1]["rows"][0]["items"]), 10)
        self.assertIn("10", refused(self, "screen", {"rows": [{"id": "h", "layout": "hero", "items": hero}]}, 3, "a hero row of 11"))
        refused(self, "screen", {"rows": [{"id": "r", "items": []}, {"id": "r", "items": []}]}, 3, "a row id twice")

    def test_api3_items(self):
        it = {"id": "a", "title": "A", "image": {"url": "https://x/p"},
              "images": {"poster": {"url": "https://x/p"}, "wide": {"url": "https://x/w"}, "square": {"asset": "s.png"},
                         "backdrop": {"url": "https://x/b"}, "logo": {"url": "https://x/l"}},
              "meta": "2019 · 2 h 10 min · PG-13", "text": "one\ntwo\nthree\nfour", "watched": False}
        _, v = checked("screen", {"rows": [{"id": "r", "items": [it]}]}, 3)
        got = v["rows"][0]["items"][0]
        self.assertEqual(sorted(got["images"]), ["backdrop", "logo", "poster", "square", "wide"])
        self.assertEqual((got["meta"], got["text"], got["watched"]), (it["meta"], it["text"], False))
        _, v = checked("screen", {"rows": [{"id": "r", "items": [{"id": "a", "title": "A", "images": {"poster": None}}]}]}, 3)
        self.assertEqual(v["rows"][0]["items"][0]["images"], {}, "a picture left null is left out")
        for bad in ({"images": {"thumb": {"url": "https://x"}}}, {"images": {"poster": "https://x"}}, {"images": []},
                    {"images": {"poster": {"url": "https://x", "asset": "a.png"}}}, {"meta": "a\nb"}, {"meta": "x" * 81},
                    {"meta": "‮"}, {"text": "1\n2\n3\n4\n5"}, {"text": "x" * 301}, {"text": "\x07"}, {"watched": "yes"}, {"watched": 1}):
            refused(self, "screen", {"rows": [{"id": "r", "items": [dict({"id": "a", "title": "A"}, **bad)]}]}, 3, str(bad))

    def test_api3_details(self):
        _, d = checked("detail", {"title": "T", "style": "cinematic", "logo": {"url": "https://x/l"}, "meta": "m" * 120,
                                  "chips": ["Drama", "x" * 24] + ["c"] * 6, "rows": [{"id": "r" + str(i), "items": []} for i in range(4)]}, 3)
        self.assertEqual((d["style"], d["logo"], len(d["meta"]), len(d["chips"]), len(d["rows"])), ("cinematic", {"token": "https://x/l"}, 120, 8, 4))
        self.assertEqual(checked("detail", {"title": "T"}, 3)[1]["style"], None, "no style: the look's, or classic")
        for bad in ({"style": "fancy"}, {"meta": "x" * 121}, {"meta": "a\nb"}, {"chips": ["c"] * 9}, {"chips": ["x" * 25]},
                    {"chips": [""]}, {"chips": "Drama"}, {"chips": [3]}, {"logo": "https://x"},
                    {"rows": [{"id": "r" + str(i), "items": []} for i in range(5)]}, {"title": None}):
            refused(self, "detail", dict({"title": "T"}, **bad), 3, str(bad))

    def test_new_text_counts_toward_the_256_kib(self):
        def rows(extra):
            return [{"id": "r" + str(n), "items": [dict({"id": str(i), "title": "€" * 120, "subtitle": "€" * 120}, **extra)
                                                   for i in range(50)]} for n in range(4)]
        self.assertTrue(checked("screen", {"rows": rows({})}, 3), "200 items without the new text fit")
        self.assertIn("256", refused(self, "screen", {"rows": rows({"meta": "€" * 80, "text": "€" * 300})}, 3,
                                     "the same items with their line and text are past 256 KiB"))

    def test_not_an_api(self):
        with self.assertRaises(blocks.Invalid):
            checked("screen", {"rows": []}, 5)
        with self.assertRaises(blocks.Invalid):
            checked("screen", {"rows": []}, 1)

    def test_api4_results_are_3s(self):
        """api 4 adds nothing to results in milestone 1: an api 3 screen and
        details page check the same at 4"""
        item = {"id": "a", "title": "A", "images": {"poster": {"url": "https://img.example.com/p.jpg"}}, "meta": "2026", "watched": True}
        screen = {"title": "T", "rows": [{"id": "hero", "title": "H", "layout": "hero", "shape": "wide", "size": "large", "items": [item]}]}
        detail = {"title": "D", "style": "cinematic", "chips": ["x"], "rows": [{"id": "more", "title": "More", "items": [item]}]}
        s4 = checked("screen", screen, 4)
        self.assertEqual(s4[1].pop("live"), False, "(api 4's screen says whether it's live)")
        self.assertEqual(s4, checked("screen", screen, 3))
        self.assertEqual(checked("detail", detail, 4), checked("detail", detail, 3))


HELLO = """from uber_tv import app, Screen, Row, Item, Detail
import uber_tv
@app.home
def home():
    return Screen("api " + str(uber_tv.api), rows=[Row("hero-row", "H", [Item(str(i), "x", images={"wide": "https://img.example.com/" + str(i)}) for i in range(12)],
                  layout="hero", shape="wide")])
@app.details
def details(item):
    return Detail("T", style="cinematic", chips=["Drama"], rows=[Row("r" + str(i), "", [Item("a", "A")]) for i in range(4)])
app.run()
"""


class Api3Runtime(unittest.IsolatedAsyncioTestCase):
    """hello names the app's own API, and its results are checked against it"""

    def app_with(self, name, api, **over):
        folder = make_app(name, over.pop("main", HELLO), perms={"net": ["img.example.com"]})
        m = json.load(open(os.path.join(folder, "app.json")))
        m.update(api=api, **over)
        json.dump(m, open(os.path.join(folder, "app.json"), "w"))
        return folder

    async def test_api3_app(self):
        h = Harness(self.app_with("api3", 3))
        await h.start()
        r = await h.call("home")
        self.assertEqual(r["kind"], "screen", r)
        row = r["value"]["rows"][0]
        self.assertEqual((r["value"]["title"], row["layout"], row["shape"], len(row["items"])), ("api 3", "hero", "wide", 10),
                         "hello said 3; the toolkit cut the hero row to 10")
        self.assertIn("token", row["items"][0]["images"]["wide"])
        d = await h.call("details", {"item": "a"})
        self.assertEqual((d["kind"], d["value"]["style"], len(d["value"]["rows"])), ("detail", "cinematic", 4), d)
        await h.stop()

    async def test_api2_app_with_the_same_code(self):
        h = Harness(self.app_with("api2same", 2))
        await h.start()
        r = await h.call("home")
        self.assertEqual(r["kind"], "screen", r)
        row = r["value"]["rows"][0]
        self.assertEqual((r["value"]["title"], row["layout"]), ("api 2", "row"), "hello said 2; the toolkit sent what API 2 takes")
        self.assertNotIn("images", row["items"][0])
        d = await h.call("details", {"item": "a"})
        self.assertEqual((d["kind"], len(d["value"]["rows"])), ("detail", 3), d)
        await h.stop()

    async def test_api2_app_sending_api3_fields_is_refused(self):
        raw = RAW + """send({"t": "ready"})
for line in sys.stdin.buffer:
    f = json.loads(line)
    if f.get("t") == "call":
        send({"t": "result", "id": f["id"], "screen": {"title": "x", "rows": [{"id": "r", "shape": "poster", "items": []}]}})
"""
        h = Harness(self.app_with("api2raw", 2, main=raw))
        await h.start()
        r = await h.call("home")
        self.assertEqual((r["kind"], r["value"]["code"]), ("error", "invalid"), r)
        self.assertIn("shape", r["value"]["text"])
        self.assertEqual(h.rt.state, "ready", "a refused result: the app keeps running")
        await h.stop()


class Gate:
    """The picture budget held shut until opened (what's waiting for it waits)"""

    def __init__(self):
        self.open = False

    def take(self, n=1):
        return self.open

    def wait(self, n=1):
        return 0.02


def pics_server(names, delay=0.0):
    seen = []

    def handler(line, headers):
        path = line.split()[1]
        seen.append(path)
        if delay:
            time.sleep(delay)
        n = path.rsplit("/", 1)[-1]
        if n in names:
            return 200, {"Content-Type": "image/png"}, names[n]
        return 404, {}, b""
    srv = LocalServer(handler)
    srv.seen = seen
    return srv


GRID = """from uber_tv import app, Screen, Row, Item
import json
@app.browse
def browse(item):
    spec = json.loads(item)
    return Screen("pics", rows=[Row("r", "R", [Item(n, n, image="%s/" + n) for n in spec["names"]])])
@app.action
def action(item, how):
    return Screen("bad", rows=[Row("r", "R", [Item(n, n, image="%s/" + n) for n in json.loads(item)["names"]] + [{"id": "z", "title": "Z", "kind": "nope"}])])
app.run()
"""


class Tokens(unittest.IsolatedAsyncioTestCase):
    """Picture tokens: one transaction per result, pinned by its id until the
    guide drops it, only unpinned ones let go (least recently used first)"""

    async def asyncSetUp(self):
        self.srv = await pics_server({"p" + str(i): png(30 + i, 20) for i in range(40)}).start()
        self.base = "http://127.0.0.1:" + str(self.srv.port) + "/jf"
        self.h = Harness(make_app("tokens", GRID % (self.base, self.base), perms={"server": {"label": "S"}}), server=self.base)
        await self.h.start()

    async def asyncTearDown(self):
        await self.h.stop()
        self.srv.close()

    async def screen(self, names, method="browse"):
        r = await self.h.call(method, {"item": json.dumps({"names": names}), "action": "go"} if method == "action" else {"item": json.dumps({"names": names})})
        return r

    def toks(self, r):
        return [it["image"]["token"] for it in r["value"]["rows"][0]["items"]]

    async def test_pins_drop_and_least_recently_used(self):
        rt = self.h.rt
        old = apprun.MAX_TOKENS
        apprun.MAX_TOKENS = 6
        try:
            a = await self.screen(["p0", "p1", "p2", "p3"])
            b = await self.screen(["p4", "p5", "p6", "p7"])
            ta, tb = self.toks(a), self.toks(b)
            self.assertEqual(len(rt.tokens), 8, "both results pinned: nothing let go past the cap")
            self.assertEqual(rt.live[a["id"]], set(ta))
            # p3 then p2 are used (images asked): p0 and p1 are a's least recently used
            await rt.from_guide({"t": "image", "token": ta[3], "epoch": 0, "prio": "visible"})
            await rt.from_guide({"t": "image", "token": ta[2], "epoch": 0, "prio": "visible"})
            await rt.from_guide({"t": "drop", "results": [a["id"]]})
            self.assertNotIn(a["id"], rt.live)
            self.assertEqual(sorted(t for t in ta if t in rt.tokens), sorted(ta[2:]), "the two least recently used free ones went at the drop")
            # p3 is free, and used again: kept longest
            await rt.from_guide({"t": "image", "token": ta[3], "epoch": 0, "prio": "visible"})
            c = await self.screen(["p8"])
            self.assertEqual(len(rt.tokens), 6, "past the cap: free ones let go")
            self.assertTrue(all(t in rt.tokens for t in tb), "pinned tokens are never let go")
            self.assertIn(ta[3], rt.tokens, "use keeps a free token longest")
            self.assertNotIn(ta[2], rt.tokens)
            await rt.from_guide({"t": "image", "token": ta[0], "epoch": 0, "prio": "visible"})
            await asyncio.sleep(0.2)
            gone = [f for f in self.h.frames if f.get("t") == "image" and f["token"] == ta[0]]
            self.assertEqual((gone[-1]["code"], gone[-1]["error"]), ("unknown", "unknown picture"))
            self.assertIn(self.toks(c)[0], rt.tokens)
        finally:
            apprun.MAX_TOKENS = old

    async def test_a_refused_result_makes_no_tokens(self):
        rt = self.h.rt
        before = len(rt.tokens)
        r = await self.screen(["p10", "p11", "p12"], method="action")
        self.assertEqual(r["kind"], "error", r)
        self.assertEqual(len(rt.tokens), before, "the result's tokens were one transaction: none made")
        self.assertEqual(rt.live, {})

    async def test_the_same_link_is_one_token(self):
        r = await self.screen(["p20", "./p20"])
        self.assertEqual(len(set(self.toks(r))), 1, "two links to one place (its canonical URL): one token")
        r2 = await self.screen(["p20"])
        self.assertEqual(self.toks(r2)[0], self.toks(r)[0], "a later result naming it gets the same token, pinned to it too")
        self.assertEqual(self.h.rt.tokens[self.toks(r)[0]]["results"], {r["id"], r2["id"]})

    async def test_hard_cap(self):
        old = apprun.HARD_TOKENS
        apprun.HARD_TOKENS = 3
        try:
            r = await self.screen(["p30", "p31", "p32", "p33"])
            self.assertEqual((r["kind"], r["value"]["code"]), ("error", "invalid"), "past the hard cap: refused, not let go")
        finally:
            apprun.HARD_TOKENS = old


class Queue(unittest.IsolatedAsyncioTestCase):
    """The picture queue: at most 64 waiting, one fetch a token, the focus
    picture first, then visible cards, then the rest; a newer demand epoch
    drops older work before it spends any budget"""

    async def asyncSetUp(self):
        self.names = {"p" + str(i): png(40, 60) for i in range(90)}
        self.srv = await pics_server(self.names).start()
        self.base = "http://127.0.0.1:" + str(self.srv.port) + "/jf"
        self.h = Harness(make_app("queue", GRID % (self.base, self.base), perms={"server": {"label": "S"}}), server=self.base)
        await self.h.start()
        self.gate = self.h.rt.image_rate = Gate()

    async def asyncTearDown(self):
        await self.h.stop()
        self.srv.close()

    async def tokens(self, names):
        out = {}
        for i in range(0, len(names), 40):   # a row holds 50
            r = await self.h.call("browse", {"item": json.dumps({"names": names[i:i + 40]})})
            out.update({it["id"]: it["image"]["token"] for it in r["value"]["rows"][0]["items"]})
        return out

    async def want(self, tok, epoch, prio="visible"):
        await self.h.rt.from_guide({"t": "image", "token": tok, "epoch": epoch, "prio": prio})

    def replies(self, tok):
        return [f for f in self.h.frames if f.get("t") == "image" and f["token"] == tok]

    async def settle(self):
        for _ in range(100):
            if not self.h.rt.queue and not self.h.rt.fetching:
                return
            await asyncio.sleep(0.05)

    async def test_focus_first_then_visible_then_the_rest(self):
        t = await self.tokens(["p" + str(i) for i in range(12)])
        old = apprun.IMAGE_FETCHES
        apprun.IMAGE_FETCHES = 1                         # one at a time, so the order shows
        try:
            await self.want(t["p0"], 1)                  # takes the one fetch, waiting for budget
            await self.want(t["p6"], 1, "rest")
            await self.want(t["p1"], 1, "visible")
            await self.want(t["p7"], 1, "visible")
            await self.want(t["p8"], 1, "focus")
            await self.want(t["p7"], 1, "visible")       # asked again: still one
            await self.want(t["p6"], 1, "visible")       # asked again, more urgently: moves up
            self.gate.open = True
            await self.settle()
        finally:
            apprun.IMAGE_FETCHES = old
        order = [s.rsplit("/", 1)[-1] for s in self.srv.seen]
        self.assertEqual(order, ["p0", "p8", "p6", "p1", "p7"], "focus, then visible by when they were first asked (p6 waited longest)")
        self.assertEqual(order.count("p7"), 1, "one fetch a token")
        for n in ("p6", "p7", "p8"):
            self.assertEqual((self.replies(t[n])[-1]["w"], self.replies(t[n])[-1]["h"]), (40, 60), "w and h with the picture")

    async def test_rapid_focus_changes(self):
        t = await self.tokens(["p" + str(i) for i in range(30)])
        for epoch in range(1, 31):
            await self.want(t["p" + str(epoch - 1)], epoch, "focus")   # the cursor moving, a picture each time
        self.gate.open = True
        await self.settle()
        fetched = [s.rsplit("/", 1)[-1] for s in self.srv.seen]
        self.assertEqual(fetched, ["p29"], "only the current picture spent budget: " + str(fetched))
        self.assertIn("path", self.replies(t["p29"])[-1])
        for i in range(29):
            last = self.replies(t["p" + str(i)])[-1]
            self.assertEqual(last["code"], "stale", last)
            self.assertEqual(last["epoch"], i + 1, "a stale answer says which demand it was for")
        await self.want(t["p3"], 5)
        self.assertEqual(self.replies(t["p3"])[-1]["code"], "stale", "a request for an older demand is stale at once")

    async def test_at_most_64_waiting(self):
        t = await self.tokens(["p" + str(i) for i in range(72)])
        for i in range(70):
            await self.want(t["p" + str(i)], 1, "rest" if i >= 60 else "visible")
        self.assertEqual((len(self.h.rt.fetching), len(self.h.rt.queue)), (6, 64))
        await self.want(t["p70"], 1, "rest")
        self.assertEqual(self.replies(t["p70"])[-1]["code"], "busy", "no better than what waits: refused")
        await self.want(t["p71"], 1, "focus")
        self.assertIn(t["p71"], self.h.rt.queue, "the focus picture always gets in")
        busy = [n for n in ("p" + str(i) for i in range(60, 70)) if self.replies(t[n]) and self.replies(t[n])[-1]["code"] == "busy"]
        self.assertEqual(len(busy), 1, "one of the rest made room: " + str(busy))
        self.gate.open = True
        await self.settle()


class CacheHits(unittest.IsolatedAsyncioTestCase):
    """A kept picture is read through its descriptor; one that's a link, not
    a regular file, too big or not a picture is deleted and fetched again"""

    async def test_kept_pictures(self):
        srv = await pics_server({"a.png": png(64, 36), "b.png": png(10, 10)}).start()
        base = "http://127.0.0.1:" + str(srv.port) + "/jf"
        h = Harness(make_app("cachehits", GRID % (base, base), perms={"server": {"label": "S"}}), server=base)
        await h.start()
        r = await h.call("browse", {"item": json.dumps({"names": ["a.png", "b.png"]})})
        ta, tb = (it["image"]["token"] for it in r["value"]["rows"][0]["items"])

        async def ask(tok):
            n = len(h.frames)
            await h.rt.from_guide({"t": "image", "token": tok, "epoch": 0, "prio": "visible"})
            for _ in range(100):
                got = [f for f in h.frames[n:] if f.get("t") == "image" and f["token"] == tok]
                if got:
                    return got[-1]
                await asyncio.sleep(0.02)
            return None
        first = await ask(ta)
        self.assertEqual((first["w"], first["h"]), (64, 36), first)
        path = first["path"]
        again = await ask(ta)
        self.assertEqual((again["path"], again["w"], again["h"], len(srv.seen)), (path, 64, 36, 1), "kept: no second fetch")
        other = (await ask(tb))["path"]

        def swap(make):
            os.unlink(path)
            make()
        cases = [("a link to another picture", lambda: os.symlink(other, path)),
                 ("a pipe", lambda: os.mkfifo(path, 0o600)),
                 ("not a picture", lambda: open(path, "wb").write(b"<html>no</html>")),
                 ("too big", lambda: open(path, "wb").write(png(64, 36, apprun.MAX_IMAGE)))]
        for what, make in cases:
            fetched = len(srv.seen)
            swap(make)
            got = await ask(ta)
            self.assertEqual((got.get("path"), got.get("w")), (path, 64), what + ": " + str(got))
            self.assertEqual(len(srv.seen), fetched + 1, what + ": deleted and fetched again")
            self.assertTrue(stat_regular(path), what + ": a regular file again")
        await h.stop()
        srv.close()

    async def test_a_packaged_picture_has_its_size(self):
        main = """from uber_tv import app, Screen, Row, Item
@app.home
def home():
    return Screen("x", rows=[Row("r", "R", [Item("a", "a", image="pic.png")])])
app.run()
"""
        h = Harness(make_app("assetsize", main, extra={"pic.png": png(30, 45)}))
        await h.start()
        r = await h.call("home")
        img = r["value"]["rows"][0]["items"][0]["image"]
        self.assertEqual((os.path.basename(img["path"]), img["w"], img["h"]), ("pic.png", 30, 45), img)
        await h.stop()


class Round1Fixes(unittest.IsolatedAsyncioTestCase):
    """Milestone 1, ycodex round 1"""

    async def test_api2_raw_dicts_with_null_rows(self):
        """#1: an API 2 handler's plain dictionary with rows: null still shows"""
        main = """from uber_tv import app
@app.home
def home():
    return {"title": "Raw", "rows": None}
@app.details
def details(item):
    return {"title": "D", "rows": None}
app.run()
"""
        h = Harness(make_app("raw2", main))
        await h.start()
        r = await h.call("home")
        self.assertEqual((r["kind"], r["value"]["rows"]), ("screen", []), r)
        d = await h.call("details", {"item": "a"})
        self.assertEqual((d["kind"], d["value"]["rows"]), ("detail", []), d)
        await h.stop()

    def test_a_hero_by_app_json_holds_ten(self):
        """#2: a row whose layout is left to app.json's hero holds ten items"""
        rows = lambda n: {"rows": [{"id": "big", "items": [{"id": str(i), "title": "x"} for i in range(n)]}]}
        img = lambda ref, where: {"token": "t"}
        call = lambda v: blocks.result("home", {"t": "result", "id": 1, "screen": v}, img, 3, frozenset({"big"}))
        self.assertEqual(len(call(rows(10))[1]["rows"][0]["items"]), 10)
        with self.assertRaises(blocks.Invalid):
            call(rows(11))
        # its own layout said: that one counts
        v = rows(30)
        v["rows"][0]["layout"] = "grid"
        self.assertEqual(len(call(v)[1]["rows"][0]["items"]), 30)

    async def test_a_hero_by_app_json_through_the_helper(self):
        main = """from uber_tv import app, Screen, Row, Item
@app.home
def home():
    return Screen("x", rows=[Row("big", "Big", [Item(str(i), "x") for i in range(12)])])
app.run()
"""
        folder = make_app("heroapp", main)
        with open(os.path.join(folder, "app.json")) as f:
            m = json.load(f)
        m.update(api=3, layout={"rows": [{"id": "big", "label": "Big", "layout": "hero"}]})
        with open(os.path.join(folder, "app.json"), "w") as f:
            json.dump(m, f)
        h = Harness(folder)
        await h.start()
        r = await h.call("home")
        self.assertEqual((r["kind"], r["value"]["code"]), ("error", "invalid"), "twelve items in app.json's hero: refused")
        await h.stop()

    def test_try_prints_a_row_left_to_app_json(self):
        """#5: try prints an api 3 row with no layout of its own"""
        lines = []
        one = [{"id": "x", "title": "X", "subtitle": "", "badge": "", "kind": "info", "image": None, "progress": None}]
        apprun.render("screen", {"title": "T", "refresh": None, "empty": "", "rows": [
            {"id": "a", "title": "A", "layout": None, "shape": None, "size": None, "items": one},
            {"id": "b", "title": "B", "layout": None, "shape": None, "size": None, "items": one},
            {"id": "c", "title": "C", "layout": None, "shape": None, "size": None, "items": []}]}, lines.append,
            {"b": {"id": "b", "layout": "grid"}})
        self.assertIn("in the Classic look:", lines[1], "the look it's drawn in, before anyone's choices")
        self.assertIn("ROW a: A [1 items] layout row (the default)", lines[2])
        self.assertIn("ROW b: B [1 items] layout grid (app.json)", lines[4])
        self.assertEqual(lines[6], "  ROW c: C [0 items] not drawn: it has no items")

    def test_try_prints_shapes_and_picture_choices(self):
        """milestone 4: each row's layout, shape and size and where each came
        from, an auto shape worked out as the guide does, and the picture
        each card shows"""
        pic = lambda w, h: {"path": "/x.png", "w": w, "h": h}
        item = lambda i, **k: dict({"id": i, "title": i.upper(), "subtitle": "", "badge": "", "kind": "info", "image": None, "progress": None}, **k)
        rows = [
            {"id": "own", "title": "Own", "layout": None, "shape": "poster", "size": "large",
             "items": [item("a", image=pic(320, 180), images={"poster": pic(200, 300)}), item("b", image=pic(320, 180))]},
            {"id": "manifest", "title": "From app.json", "layout": None, "shape": None, "size": None, "items": [item("c", image=pic(200, 200))]},
            {"id": "tall", "title": "Auto tall", "layout": None, "shape": None, "size": None,
             "items": [item("d", image=pic(200, 300)), item("e", image=pic(210, 300)), item("f", image=pic(320, 180))]},
            {"id": "tie", "title": "Auto tie", "layout": None, "shape": None, "size": None,
             "items": [item("g", image=pic(200, 300)), item("h", image=pic(200, 200)), item("i", image=pic(320, 180))]},
            {"id": "later", "title": "Fetched later", "layout": None, "shape": None, "size": None, "items": [item("j", image={"token": "t1"})]},
            {"id": "hero", "title": "Hero", "layout": "hero", "shape": None, "size": None, "items": [item("k", images={"wide": pic(320, 180)})]},
            {"id": "lines", "title": "Lines", "layout": "list", "shape": None, "size": None, "items": [item("l", meta="S1 E1", watched=True)]}]
        lines = []
        apprun.render("screen", {"title": "T", "refresh": None, "empty": "", "rows": rows}, lines.append,
                      {"manifest": {"id": "manifest", "shape": "square", "size": "small"}})
        text = "\n".join(lines)
        self.assertIn("ROW own: Own [2 items] layout row (the default), shape poster (the row says), size large (the row says)", text)
        self.assertIn("{info a}  picture: images.poster 200×300", text, "its picture for the row's shape")
        self.assertIn("{info b}  picture: image 320×180 (no images.poster: its image instead)", text, "else its image, and why")
        self.assertIn("shape square (app.json), size small (app.json)", text)
        self.assertIn("ROW tall: Auto tall [3 items] layout row (the default), shape auto: poster from its first pictures (200×300, 210×300, 320×180)", text)
        self.assertIn("ROW tie: Auto tie [3 items] layout row (the default), shape auto: wide", text, "a tie: wide, as the guide does")
        self.assertIn("shape auto: from its first pictures, once the guide has them", text)
        self.assertIn("hero: one item at a time", text)
        self.assertIn("backdrop: images.wide, logo: its title", text)
        self.assertIn("ROW lines: Lines [1 items] layout list (the row says), shape auto: wide from its first pictures (no picture), size medium (the default); list: a line each", text)
        self.assertIn("L — S1 E1 · watched ✓", text)
        lines = []
        drows = [{"id": "cast", "title": "Cast", "layout": None, "shape": "circle", "size": None, "items": [item("p", image=pic(160, 160))]},
                 {"id": "more", "title": "More", "layout": None, "shape": "poster", "size": "small",
                  "items": [item("m", image=pic(320, 180), images={"poster": pic(200, 300)}), item("n", image=pic(320, 180))]},
                 {"id": "extra", "title": "Extra", "layout": None, "shape": None, "size": None, "items": [item("e", image=pic(320, 180))]}]
        apprun.render("detail", {"title": "D", "subtitle": "", "text": "", "facts": [], "actions": [], "rows": drows, "image": pic(200, 300),
                                 "backdrop": None, "style": "cinematic", "logo": pic(320, 100), "meta": "2019 · PG", "chips": ["Drama", "4K"]}, lines.append,
                      {"extra": {"id": "extra", "layout": "grid", "size": "large"}})
        self.assertIn("style cinematic (the app says) · its logo for the title · 2019 · PG · chips: Drama, 4K", lines[1])
        self.assertIn("picture: its image 200×300; backdrop: none", lines[2])
        # a details page's rows: the same decisions as a screen's, each card's picture included
        self.assertEqual(lines[3:], [
            "  ROW cast: Cast [1 items] layout row (the default), shape circle (the row says), size medium (the default)",
            "    - P  {info p}  picture: image 160×160",
            "  ROW more: More [2 items] layout row (the default), shape poster (the row says), size small (the row says)",
            "    - M  {info m}  picture: images.poster 200×300",
            "    - N  {info n}  picture: image 320×180 (no images.poster: its image instead)",
            "  ROW extra: Extra [1 items] layout grid (app.json), shape auto: wide from its first pictures (320×180), size large (app.json)",
            "    - E  {info e}  picture: image 320×180 (no images.wide: its image instead)"])

    def test_try_draws_what_the_guide_draws_in_every_look(self):
        """milestone 4: for each look an app can suggest (and none), try's
        layout, shape, size, where each came from, each card's picture and
        a details page's style are what the guide's own AppLooks.js gives
        (its model, cardImage and detailStyleOf, run in node)"""
        pic = lambda name, w, h: {"path": "/p/" + name + ".png", "w": w, "h": h}
        item = lambda i, **k: dict({"id": i, "title": i, "subtitle": "", "badge": "", "kind": "info", "image": None, "progress": None}, **k)
        P, W, S, G = (200, 300), (320, 180), (200, 200), (320, 100)
        full = lambda i: item(i, image=pic(i, *W), images={"poster": pic(i + "-p", *P), "wide": pic(i + "-w", *W), "logo": pic(i + "-l", *G)})
        row = lambda i, items, **k: dict({"id": i, "title": i, "layout": None, "shape": None, "size": None, "items": items}, **k)
        rows = [
            row("hinted", [full("a"), full("b")], shape="wide", size="large"),
            row("defaulted", [full("c")]),
            row("logos", [item("d", images={"logo": pic("d-l", *G)})], shape="logo"),
            row("mixed", [full("e"), item("f", image=pic("f", *P))]),
            row("posters", [item("g", image=pic("g", *P), images={"poster": pic("g-p", *P)}), item("h", image=pic("h", *P), images={"poster": pic("h-p", *P)})]),
            row("squares", [item("i", image=pic("i", *S), images={"square": pic("i-s", *S)}), item("j", image=pic("j", *S)), item("k", image=pic("k", *P))]),
            row("tie", [item("l", image=pic("l", *P)), item("m", image=pic("m", *S)), item("n", image=pic("n", *W))]),
            row("wides", [item("o", image=pic("o", *W), images={"wide": pic("o-w", *W)}), item("p", image=pic("p", *W))]),
            row("none", [item("q"), item("r")]),
            row("hero", [full("s")], layout="hero"),
            row("listed", [item("t", image=pic("t", *W))]),
            row("grid", [full("u"), full("v")], layout="grid", shape="poster", size="small"),
            row("circles", [item("w", image=pic("w", *S))], shape="circle"),
            row("later", [item("x", image={"token": "t1"}), item("y", image=pic("y", *P), images={"wide": pic("y-w", *W)})])]
        defaults = {"defaulted": {"id": "defaulted", "shape": "square", "size": "small"}, "listed": {"id": "listed", "layout": "list"},
                    "hinted": {"id": "hinted", "shape": "poster", "size": "small", "layout": "grid"}}
        details = [{"style": "cinematic"}, {"style": "classic"}, {"style": None}]
        looks = ["", "classic", "posters", "cinematic", "wall", "compact"]
        script = os.path.join(WORK, "guide-looks.mjs")
        with open(script, "w") as f:
            f.write("""import { readFileSync } from "node:fs"
const L = new Function(readFileSync(process.argv[2], "utf8").replace(".pragma library", "") + "; return { model, cardImage, autoShape, detailStyleOf, screenOf }")()
const c = JSON.parse(readFileSync(0, "utf8"))
const defaults = {}
for (const id in c.defaults) defaults["d:" + id] = c.defaults[id]
// the shapes the rows learn, as the guide's view samples them: the first three items' own pictures
// (none counts neither way; one still to be fetched leaves it waiting)
const learned = {}
for (const r of c.rows) {
  const settled = {}
  r.items.slice(0, 3).forEach((it, i) => { const im = it.image; if (!im) settled[i] = 0; else if (im.w && im.h) settled[i] = im.w / im.h })
  const s = L.autoShape(settled, r.items.length, false)
  if (s) learned["r:" + r.id] = s
}
const out = {}
for (const look of c.looks) {
  const m = L.model({ kind: "screen", value: { rows: c.rows } }, { width: 1280, u: 16, choices: {}, suggested: look, learned, defaults })
  out[look] = { rows: m.lines.map(l => ({ id: l.id, layout: l.layout, layoutFrom: l.layoutFrom, shape: l.shape, from: l.from, size: l.size, sizeFrom: l.sizeFrom,
                                         pictures: l.items.map(it => { const p = L.cardImage(it, l); return p ? p.path : null }) })),
                details: c.details.map(v => L.detailStyleOf(v, L.screenOf({}, look))) }
}
process.stdout.write(JSON.stringify(out))
""")
        p = subprocess.run(["node", script, os.path.join(ROOT, "AppLooks.js")], input=json.dumps({"rows": rows, "defaults": defaults, "details": details, "looks": looks}),
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(p.returncode, 0, p.stderr[-600:])
        guide = json.loads(p.stdout)
        where = lambda f: "look" if f.endswith(" look") else "app" if f in ("the row says", "app.json") else "default" if f == "the default" else f
        seen = set()
        for look in looks:
            self.assertEqual([g["id"] for g in guide[look]["rows"]], [r["id"] for r in rows])
            for r, g in zip(rows, guide[look]["rows"]):
                t = apprun.presented(r, defaults, look)
                at = (look or "(none)") + " " + r["id"]
                self.assertEqual((t["layout"], where(t["layout_from"])), (g["layout"], g["layoutFrom"]), at + ": layout")
                self.assertEqual((t["shape"], where(t["shape_from"])), ({"autoSquare": "square"}.get(g["shape"], g["shape"]), g["from"]), at + ": shape")
                self.assertEqual((t["size"], where(t["size_from"])), (g["size"], g["sizeFrom"]), at + ": size")
                self.assertEqual([x[1].get("path") if x else None for x in t["pictures"]], g["pictures"], at + ": pictures")
                seen.add(g["from"])
            for v, g in zip(details, guide[look]["details"]):
                self.assertEqual(apprun.detail_style(v, look)[0], g, (look or "(none)") + ": details " + str(v["style"]))
        self.assertEqual(seen, {"look", "app", "learned", "auto"}, "every source of a shape came up")

    def test_the_showcase_example_checks_and_runs_offline(self):
        """milestone 4: apps/sdk/examples/showcase passes check, and try runs
        every handler offline (it asks for no network) with every block"""
        folder = os.path.join(ROOT, "apps", "sdk", "examples", "showcase")
        c = subprocess.run([sys.executable, "-I", os.path.join(ROOT, "bin", "om-pg-apps"), "check", folder], capture_output=True, text=True, timeout=60)
        res = json.loads(c.stdout.strip().splitlines()[-1])
        self.assertTrue(res.get("ok") and not res.get("errors") and not res.get("warnings"), c.stdout[-400:])
        self.assertEqual(res["manifest"]["api"], 4)
        self.assertEqual(res["manifest"]["permissions"]["net"], [], "offline: no network at all")
        self.assertEqual(res["manifest"]["permissions"]["netWrite"], {}, "and changes nothing anywhere")
        calls = ["home", 'details:{"item":"title:1"}', 'details:{"item":"title:5"}', 'details:{"item":"album:2"}', 'browse:{"item":"person:1"}',
                 'search:{"query":"moon"}', 'action:{"item":"title:1","action":"watched"}', 'homeRow:{"key":"picks"}']
        p = subprocess.run([sys.executable, "-I", os.path.join(ROOT, "bin", "om-pg-apprun"), "try", folder] + sum([["--call", x] for x in calls], []),
                           capture_output=True, text=True, timeout=90)
        self.assertEqual(p.returncode, 0, p.stdout[-600:] + p.stderr[-300:])
        out = p.stdout
        for want in ["[3 items] layout hero (the row says)", "shape poster (the row says)", "shape wide (the row says)", "shape square (the row says), size small (the row says)",
                     "shape logo (the row says)", "shape circle (the row says)", "shape auto: wide from its first pictures", "[8 items] layout grid (the row says)",
                     "[5 items] layout list (the row says)", "picture: images.poster 200×300", "picture: images.logo 320×100", "no images.square: its image instead",
                     "backdrop: images.backdrop, logo: images.logo", "watched ✓", "[NEW]", "[LIVE]", "25%",
                     "style cinematic (the app says) · its logo for the title", "style classic (the app says)", "chips: Drama, Mystery", "[Mark watched] {action watched}",
                     "SCREEN Person 1", "SCREEN Results for moon", "MESSAGE Marked as watched", "ROW ITEMS Paper Moons, Glass Harbor, Second Signal",
                     "network: offline (no request left this computer)"]:
            self.assertIn(want, out)
        self.assertNotIn("error ", out)
        # each details page's rows, in its own part of the output
        details = out.split('== details:{"item":"title:1"}')[1].split("== ")[0]
        self.assertIn("  ROW cast: Cast [3 items] layout row (the default), shape circle (the row says), size medium (the default)\n"
                      "    - Person 1 — Actor  {open person:1}  picture: image 160×160", details)
        self.assertIn("  ROW more: More like this [4 items] layout row (the default), shape poster (the row says), size medium (the default)\n"
                      "    - Paper Moons — 2021 · 1 h 48 min · PG  {info title:2}  picture: images.poster 200×300", details)

    def test_try_runs_an_api3_app(self):
        main = """from uber_tv import app, Screen, Row, Item
@app.home
def home():
    return Screen("x", rows=[Row("plain", "Plain", [Item("a", "A")])])
app.run()
"""
        folder = make_app("tryapi3", main)
        with open(os.path.join(folder, "app.json")) as f:
            m = json.load(f)
        m.update(api=3)
        with open(os.path.join(folder, "app.json"), "w") as f:
            json.dump(m, f)
        p = subprocess.run([sys.executable, "-I", os.path.join(ROOT, "bin/om-pg-apprun"), "try", folder, "--call", "home"],
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertIn("ROW plain: Plain [1 items] layout row (the default)", p.stdout)


class EpochsAndEviction(unittest.IsolatedAsyncioTestCase):
    """#6, #8, #9, #10: demand, pruning after a drop, eviction mid-fetch, broken files"""

    async def asyncSetUp(self):
        self.srv = await pics_server({"p" + str(i): png(40, 60) for i in range(20)}).start()
        self.base = "http://127.0.0.1:" + str(self.srv.port) + "/jf"
        self.h = Harness(make_app("epochs", GRID % (self.base, self.base), perms={"server": {"label": "S"}}), server=self.base)
        await self.h.start()
        self.gate = self.h.rt.image_rate = Gate()

    async def asyncTearDown(self):
        await self.h.stop()
        self.srv.close()

    async def screen(self, names):
        return await self.h.call("browse", {"item": json.dumps({"names": names})})

    def replies(self, tok):
        return [f for f in self.h.frames if f.get("t") == "image" and f["token"] == tok]

    async def settle(self):
        for _ in range(100):
            if not self.h.rt.queue and not self.h.rt.fetching:
                return
            await asyncio.sleep(0.05)

    async def test_the_same_picture_wanted_again_under_a_newer_demand(self):
        r = await self.screen(["p0"])
        tok = r["value"]["rows"][0]["items"][0]["image"]["token"]
        await self.h.rt.from_guide({"t": "image", "token": tok, "epoch": 1, "prio": "visible"})
        self.assertIn(tok, self.h.rt.fetching, "it's being fetched (waiting for budget)")
        await self.h.rt.from_guide({"t": "image", "token": tok, "epoch": 2, "prio": "focus"})
        self.assertEqual(self.h.rt.fetching[tok], 2, "now wanted under the newer demand")
        self.gate.open = True
        await self.settle()
        self.assertIn("path", self.replies(tok)[-1], "answered, not left waiting: " + str(self.replies(tok)))
        self.assertFalse(any(f.get("code") == "stale" for f in self.replies(tok)))

    async def test_a_demand_with_nothing_to_ask_for(self):
        r = await self.screen(["p" + str(i) for i in range(10)])
        toks = [it["image"]["token"] for it in r["value"]["rows"][0]["items"]]
        for t in toks:
            await self.h.rt.from_guide({"t": "image", "token": t, "epoch": 1, "prio": "visible"})
        self.assertEqual((len(self.h.rt.fetching), len(self.h.rt.queue)), (6, 4))
        await self.h.rt.from_guide({"t": "demand", "epoch": 2})      # the guide moved on, wanting nothing here
        self.assertEqual(len(self.h.rt.queue), 0, "what was queued went")
        self.gate.open = True
        await self.settle()
        self.assertEqual(self.srv.seen, [], "and nothing spent budget: " + str(self.srv.seen))
        self.assertTrue(all(self.replies(t)[-1]["code"] == "stale" for t in toks))

    async def test_a_drop_brings_the_tokens_under_the_cap_at_once(self):
        old = apprun.MAX_TOKENS
        apprun.MAX_TOKENS = 6
        try:
            a = await self.screen(["p0", "p1", "p2", "p3"])
            b = await self.screen(["p4", "p5", "p6", "p7"])
            self.assertEqual(len(self.h.rt.tokens), 8, "both held")
            await self.h.rt.from_guide({"t": "drop", "results": [a["id"]]})
            self.assertEqual(len(self.h.rt.tokens), 6, "down to the cap as soon as a is let go")
        finally:
            apprun.MAX_TOKENS = old

    async def test_a_token_let_go_while_its_picture_comes(self):
        old = apprun.MAX_TOKENS
        apprun.MAX_TOKENS = 1
        try:
            a = await self.screen(["p10"])
            ta = a["value"]["rows"][0]["items"][0]["image"]["token"]
            await self.h.rt.from_guide({"t": "image", "token": ta, "epoch": 0, "prio": "visible"})
            self.assertIn(ta, self.h.rt.fetching)
            await self.h.rt.from_guide({"t": "drop", "results": [a["id"]]})
            await self.screen(["p11"])                                 # pinned: a's token is let go
            self.assertNotIn(ta, self.h.rt.tokens)
            self.gate.open = True
            await self.settle()
            self.assertEqual(self.replies(ta)[-1]["code"], "unknown", "no answer names a token let go")
            self.assertFalse(os.path.exists(self.h.rt.image_path(self.base + "/p10")), "and nothing was kept of it")
        finally:
            apprun.MAX_TOKENS = old

    async def test_a_file_the_guide_couldnt_draw_is_fetched_again(self):
        self.gate.open = True
        r = await self.screen(["p12"])
        tok = r["value"]["rows"][0]["items"][0]["image"]["token"]
        await self.h.rt.from_guide({"t": "image", "token": tok, "epoch": 0, "prio": "visible"})
        await self.settle()
        self.assertEqual(len(self.srv.seen), 1)
        await self.h.rt.from_guide({"t": "image", "token": tok, "epoch": 0, "prio": "visible"})
        await self.settle()
        self.assertEqual(len(self.srv.seen), 1, "kept: answered without a fetch")
        await self.h.rt.from_guide({"t": "image", "token": tok, "epoch": 0, "prio": "visible", "broken": True})
        await self.settle()
        self.assertEqual(len(self.srv.seen), 2, "broken: fetched again")
        self.assertIn("path", self.replies(tok)[-1])


class HeldServer(LocalServer):
    """Pictures whose answers wait until they're let go (so a fetch stays in
    flight, its budget spent), or that fail when they come"""

    def __init__(self, names, held=(), fail=()):
        super().__init__()
        self.names = names
        self.held = {n: asyncio.Event() for n in held}
        self.fail = set(fail)
        self.seen = []

    async def serve(self, r, w):
        try:
            head = await asyncio.wait_for(r.readuntil(b"\r\n\r\n"), 5)
        except Exception:
            w.close()
            return
        path = head.decode("latin-1").split("\r\n")[0].split()[1]
        self.seen.append(path)
        n = path.rsplit("/", 1)[-1]
        if n in self.held:
            await self.held[n].wait()
        status, data = (500, b"") if n in self.fail else (200, self.names[n]) if n in self.names else (404, b"")
        out = "HTTP/1.1 %d X\r\nContent-Length: %d\r\nContent-Type: image/png\r\nConnection: close\r\n\r\n" % (status, len(data))
        try:
            w.write(out.encode() + data)
            await w.drain()
        except ConnectionError:
            pass
        w.close()


class Round2Fixes(unittest.IsolatedAsyncioTestCase):
    """Milestone 1, ycodex round 2: every way a fetch ends is checked against
    the demand and the token, and work no result holds is dropped"""

    async def asyncSetUp(self):
        self.srv = await HeldServer({"p" + str(i): png(40, 60) for i in range(20)}, held=("h0", "h1", "h2", "e0", "e1"),
                                    fail=("e0", "e1")).start()
        self.srv.names.update({n: png(40, 60) for n in ("h0", "h1", "h2")})
        self.base = "http://127.0.0.1:" + str(self.srv.port) + "/jf"
        self.h = Harness(make_app("round2", GRID % (self.base, self.base), perms={"server": {"label": "S"}}), server=self.base)
        await self.h.start()

    async def asyncTearDown(self):
        for e in self.srv.held.values():
            e.set()
        await self.h.stop()
        self.srv.close()

    async def screen(self, names):
        return await self.h.call("browse", {"item": json.dumps({"names": names})})

    def replies(self, tok):
        return [f for f in self.h.frames if f.get("t") == "image" and f["token"] == tok]

    async def until(self, cond):
        for _ in range(200):
            if cond():
                return True
            await asyncio.sleep(0.02)
        return False

    async def in_flight(self, name, epoch=1):
        r = await self.screen([name])
        tok = r["value"]["rows"][0]["items"][0]["image"]["token"]
        await self.h.rt.from_guide({"t": "image", "token": tok, "epoch": epoch, "prio": "visible"})
        self.assertTrue(await self.until(lambda: any(p.endswith("/" + name) for p in self.srv.seen)), "its fetch began")
        return r, tok

    async def test_a_picture_that_comes_after_the_demand_moved(self):
        """#1: fetched under epoch 1, the guide moved to 2 while it came:
        kept (its budget's spent), answered stale, never as a path"""
        r, tok = await self.in_flight("h0")
        await self.h.rt.from_guide({"t": "demand", "epoch": 2})
        self.srv.held["h0"].set()
        self.assertTrue(await self.until(lambda: tok not in self.h.rt.fetching))
        self.assertEqual([(f.get("code"), f.get("epoch")) for f in self.replies(tok)], [("stale", 1)])
        self.assertTrue(os.path.exists(self.h.rt.image_path(self.base + "/h0")), "kept for when it's wanted")
        # wanted again under the new demand: there at once, nothing fetched
        await self.h.rt.from_guide({"t": "image", "token": tok, "epoch": 2, "prio": "visible"})
        self.assertIn("path", self.replies(tok)[-1])
        self.assertEqual(len([p for p in self.srv.seen if p.endswith("/h0")]), 1)

    async def test_wanted_again_while_it_comes_still_answers(self):
        """the same picture asked for under the new demand while it comes:
        answered with its path when it lands"""
        r, tok = await self.in_flight("h1")
        await self.h.rt.from_guide({"t": "demand", "epoch": 2})
        await self.h.rt.from_guide({"t": "image", "token": tok, "epoch": 2, "prio": "focus"})
        self.srv.held["h1"].set()
        self.assertTrue(await self.until(lambda: tok not in self.h.rt.fetching))
        self.assertIn("path", self.replies(tok)[-1], self.replies(tok))
        self.assertFalse(any(f.get("code") == "stale" for f in self.replies(tok)))

    async def test_a_failure_for_a_token_let_go_while_it_came(self):
        """#2: let go mid-fetch, then the server fails: unknown, as a body would be"""
        old = apprun.MAX_TOKENS
        apprun.MAX_TOKENS = 1
        try:
            r, tok = await self.in_flight("e0", epoch=0)
            await self.h.rt.from_guide({"t": "drop", "results": [r["id"]]})
            await self.screen(["p1"])                       # pinned: e0's token is let go
            self.assertNotIn(tok, self.h.rt.tokens)
            self.srv.held["e0"].set()
            self.assertTrue(await self.until(lambda: tok not in self.h.rt.fetching))
            self.assertEqual([f.get("code") for f in self.replies(tok)], ["unknown"])
        finally:
            apprun.MAX_TOKENS = old

    async def test_a_failure_after_the_demand_moved(self):
        """#2: the server fails after the guide moved on: stale, not failed"""
        r, tok = await self.in_flight("e1")
        await self.h.rt.from_guide({"t": "demand", "epoch": 2})
        self.srv.held["e1"].set()
        self.assertTrue(await self.until(lambda: tok not in self.h.rt.fetching))
        self.assertEqual([(f.get("code"), f.get("epoch")) for f in self.replies(tok)], [("stale", 1)])

    async def test_a_dropped_result_takes_its_waiting_pictures(self):
        """#1: a Home row (or a view) replaced: what only the old result named
        stops waiting at once, so the new one's pictures aren't turned away"""
        self.h.rt.image_rate = Gate()
        a = await self.screen(["p" + str(i) for i in range(10)])
        b = await self.screen(["p" + str(i) for i in range(8, 18)])
        ta = [it["image"]["token"] for it in a["value"]["rows"][0]["items"]]
        tb = [it["image"]["token"] for it in b["value"]["rows"][0]["items"]]
        self.assertEqual(ta[8:], tb[:2], "the same pictures share their tokens")
        for t in ta:
            await self.h.rt.from_guide({"t": "image", "token": t, "epoch": 1, "prio": "visible"})
        self.assertEqual((len(self.h.rt.fetching), len(self.h.rt.queue)), (6, 4))
        await self.h.rt.from_guide({"t": "drop", "results": [a["id"]]})
        self.assertEqual(sorted(self.h.rt.queue), sorted(ta[8:]), "only what b still holds waits")
        for t in ta[6:8]:
            self.assertEqual((self.replies(t)[-1]["code"], self.replies(t)[-1]["epoch"]), ("stale", 1))
        for t in tb[2:]:
            await self.h.rt.from_guide({"t": "image", "token": t, "epoch": 1, "prio": "visible"})
        self.assertFalse(any(f.get("code") == "busy" for t in tb for f in self.replies(t)), "none of b's turned away")


def stat_regular(path):
    import stat as st
    return st.S_ISREG(os.lstat(path).st_mode)


# ---- code apps v2, milestone 1: writes to sites, redirects, Activity -------

activity = apprun.activity


class FakeRes:
    """A reply to one hop, as appnet.exchange gives it"""

    def __init__(self, url, method, status, location=None, body=b"ok"):
        self.url, self.method, self.status, self.data = url, method, status, body
        self.headers = [("Location", location)] if location else []
        self.received = 0
        self.on_close = None
        self.closed = False

    def header(self, name):
        found = [v for k, v in self.headers if k.lower() == name]
        return found[0] if found else None

    async def body(self, limit):
        self.received = len(self.data)
        return self.data

    def close(self):
        self.closed = True
        told, self.on_close = self.on_close, None
        if told:
            told(self.received)


class FakeNet:
    """net.exchange replaced: each hop recorded, answered by routes
    (url string -> (status, location))"""

    def __init__(self, routes=None):
        self.routes = routes or {}
        self.hops = []

    def __enter__(self):
        self.real = net.exchange
        net.exchange = self.exchange
        return self

    def __exit__(self, *a):
        net.exchange = self.real

    async def exchange(self, url, method, headers, body, gate, kind, pin="", resolver=None):
        gate.allow(url)
        self.hops.append((str(url), method, dict(headers), body))
        status, loc = self.routes.get(str(url), (200, None))
        if status == "fail":
            raise net.NetError(loc, "couldn't connect to " + url.host)
        return FakeRes(url, method, status, loc, b"answer from " + str(url).encode())


class Writes(unittest.IsolatedAsyncioTestCase):
    def rules(self):
        return net.Rules(["api.example.com", "b.example.com"], None, {"api.example.com": ["POST", "DELETE"], "other.example.com": ["POST"]})

    def test_rules(self):
        r = self.rules()
        for m in ("GET", "HEAD", "POST", "DELETE"):
            self.assertEqual(r.check(net.parse_url("https://api.example.com/x"), m), "net", m)
        for m in ("PUT", "PATCH"):
            with self.assertRaises(net.NetError) as e:
                r.check(net.parse_url("https://api.example.com/x"), m)
            self.assertIn("only GET, HEAD, POST and DELETE go to api.example.com", str(e.exception))
        with self.assertRaises(net.NetError) as e:
            r.check(net.parse_url("https://b.example.com/x"), "POST")
        self.assertIn("only GET and HEAD go to b.example.com", str(e.exception), "a host without netWrite reads only")
        with self.assertRaises(net.NetError):
            r.check(net.parse_url("https://other.example.com/x"), "POST")   # netWrite never adds a host net doesn't have
        with self.assertRaises(net.NetError):
            r.check(net.parse_url("https://x.api.example.com/x"), "POST")
        with self.assertRaises(net.NetError):
            r.check(net.parse_url("http://api.example.com/x"), "POST")

    async def req(self, routes, url, method, headers=None, body=None, rules=None):
        seen = []
        with FakeNet(routes) as f:
            res = await net.request(rules or self.rules(), url, method, headers, body, net.Gate(),
                                    observe=lambda *a: seen.append(a))
        return res, f.hops, seen

    async def test_redirect_methods(self):
        A, B = "https://api.example.com", "https://b.example.com"
        H = {"Authorization": "Bearer t", "X-Plex-Token": "p", "X-Api-Key": "k", "X-Custom": "c"}
        # 301, 302, 303: a GET without the body (a HEAD stays one), each method
        for status in (301, 302, 303):
            for method in ("POST", "DELETE", "GET"):
                res, hops, _ = await self.req({A + "/w": (status, A + "/next")}, A + "/w", method, H, b"data" if method == "POST" else None)
                self.assertEqual([(h[1], h[3]) for h in hops], [(method, b"data" if method == "POST" else None), ("GET", None)], (status, method))
                self.assertEqual(hops[1][2], H, "the same origin keeps the app's headers")
            res, hops, _ = await self.req({A + "/w": (status, A + "/next")}, A + "/w", "HEAD")
            self.assertEqual([h[1] for h in hops], ["HEAD", "HEAD"])
        # 307, 308: the method and body kept within the origin
        for status in (307, 308):
            res, hops, _ = await self.req({A + "/w": (status, A + "/next")}, A + "/w", "POST", H, b"data")
            self.assertEqual([(h[1], h[3]) for h in hops], [("POST", b"data"), ("POST", b"data")], status)
            self.assertEqual(res.status, 200)
            # a write to another origin isn't followed: the redirect is the answer
            for method, body in (("POST", b"data"), ("DELETE", None)):
                res, hops, _ = await self.req({A + "/w": (status, B + "/next")}, A + "/w", method, H, body)
                self.assertEqual(len(hops), 1, "a write is never carried to another origin")
                self.assertEqual((res.status, res.header("location")), (status, B + "/next"))
            # a read is followed there, its headers dropped
            res, hops, _ = await self.req({A + "/r": (status, B + "/next")}, A + "/r", "GET", H)
            self.assertEqual([h[1] for h in hops], ["GET", "GET"])
            self.assertEqual(hops[1][2], {}, "every header the app set stays with its origin")
            # but never with a body, whatever the method: the redirect is the answer
            for method in ("GET", "HEAD"):
                res, hops, _ = await self.req({A + "/r": (status, B + "/next")}, A + "/r", method, H, b"secret-body")
                self.assertEqual(len(hops), 1, method + " with a body isn't carried to another origin")
                self.assertEqual((res.status, res.header("location")), (status, B + "/next"))
                res, hops, _ = await self.req({A + "/r": (status, A + "/next")}, A + "/r", method, H, b"body")
                self.assertEqual([(h[1], h[3]) for h in hops], [(method, b"body")] * 2, "within its origin, the body stays")

    async def test_headers_never_cross_origins(self):
        A, B = "https://api.example.com", "https://b.example.com"
        H = {"Authorization": "Bearer t", "X-Plex-Token": "p", "X-Api-Key": "k", "X-Custom": "c"}
        for status in (301, 302, 303, 307, 308):
            res, hops, _ = await self.req({A + "/r": (status, B + "/x"), B + "/x": (302, A + "/back")}, A + "/r", "GET", H)
            self.assertEqual(hops[0][2], H)
            self.assertEqual(hops[1][2], {}, status)
            self.assertEqual(hops[2][2], {}, "dropped for good, even back on the first origin")
            res, hops, _ = await self.req({A + "/w": (status, B + "/x")}, A + "/w", "POST", H, b"secret body")
            self.assertTrue(all(h[3] is None for h in hops[1:]), "a body never goes to another origin")
            self.assertTrue(all(h[2] == {} for h in hops[1:]))

    async def test_refused_redirect_observed(self):
        A = "https://api.example.com"
        with self.assertRaises(net.NetError) as e:
            await self.req({A + "/r": (302, "https://tracker.example/x?id=secret")}, A + "/r", "GET")
        self.assertEqual(e.exception.code, "origin")
        seen = []
        with FakeNet({A + "/r": (302, "https://tracker.example/x?id=secret")}):
            with self.assertRaises(net.NetError):
                await net.request(self.rules(), A + "/r", "GET", None, None, net.Gate(), observe=lambda *a: seen.append(a))
        self.assertEqual([(str(s[0]), s[3], s[5]) for s in seen], [(A + "/r", 200 if False else 302, None), ("https://tracker.example/x?id=secret", None, "origin")])

    async def test_writes_through_the_helper(self):
        perms = {"net": ["api.example.com"], "netWrite": {"api.example.com": ["POST"]}}
        h = Harness(make_app("w_helper", FETCHER, perms=perms, api=4))
        await h.start()
        with FakeNet() as f:
            res = await fetch_via(h, "https://api.example.com/items", method="POST", body="hello")
            self.assertTrue(res.startswith("status 200"), res)
            self.assertEqual(f.hops[-1][1:4:2], ("POST", b"hello"))
            res = await fetch_via(h, "https://api.example.com/items/1", method="DELETE")
            self.assertIn("error method", res)
            self.assertIn("only GET, HEAD and POST go to api.example.com", res)
            self.assertEqual(len(f.hops), 1, "nothing refused was sent")
        await h.stop()

    async def test_try_writes_only_with_allow_write(self):
        perms = {"net": ["api.example.com"], "netWrite": {"api.example.com": ["POST"]}}
        h = Harness(make_app("w_try", FETCHER, perms=perms, api=4), allowWrite=False)
        await h.start()
        with FakeNet() as f:
            res = await fetch_via(h, "https://api.example.com/items", method="POST", body="hello")
            self.assertIn("try: --allow-write lets POST reach api.example.com", res)
            self.assertTrue((await fetch_via(h, "https://api.example.com/items")).startswith("status 200"))
            self.assertEqual([x[1] for x in f.hops], ["GET"])
        await h.stop()


class ActivityFile(unittest.TestCase):
    def clock(self, start):
        t = [start]
        return t, (lambda: t[0])

    def test_counts(self):
        t, now = self.clock(time.time())
        a = activity.Activity(None, now)
        a.contacted("fetch", "api.example.com", False, "GET", 200, 0)
        a.received("fetch", "api.example.com", False, "GET", 900)
        a.contacted("fetch", "api.example.com", False, "POST", 201, 120)
        a.contacted("image", "api.example.com", False, "GET", 404, 0)
        a.failed("fetch", "api.example.com", False, "GET")
        a.contacted("media", "home.example:8096", True, "GET", 206, 0)
        a.refused("origin", "tracker.example")
        a.refused("origin", "tracker.example")
        a.refused("url")
        s = activity.Activity(a.dumps(), now).summary()
        api = [x for x in s["sites"] if x["site"] == "api.example.com"][0]
        self.assertEqual((api["reads"], api["writes"], api["sent"], api["received"], api["failed"]), (3, 1, 120, 900, 1))
        self.assertEqual(sorted(api["kinds"]), ["fetch", "image"])
        self.assertTrue([x for x in s["sites"] if x["server"] and x["site"] == "home.example:8096"])
        self.assertEqual(s["refused"], [{"site": "tracker.example", "count": 2, "last": int(t[0]), "change": False}])
        self.assertEqual(s["refusedMore"], 1, "a refusal with no name is still counted")

    def test_ninety_days(self):
        t, now = self.clock(time.time())
        a = activity.Activity(None, now)
        a.contacted("fetch", "old.example.com", False, "GET", 200, 0)
        a.refused("origin", "old-tracker.example")
        t[0] += 91 * 86400
        a.contacted("fetch", "new.example.com", False, "GET", 200, 0)
        s = activity.Activity(a.dumps(), now).summary()
        self.assertEqual([x["site"] for x in s["sites"]], ["new.example.com"], "past 90 days a site goes")
        self.assertEqual(s["refused"], [])
        self.assertEqual(json.loads(a.dumps())["sites"], [["new.example.com", 0]], "and its name in the table")

    def test_names_never_push_out_what_it_did(self):
        """90 days of 50 refused names a day, each as long as a host can be,
        and one allowed write on day one: under 1 MiB, day one still there"""
        t, now = self.clock(time.time() - 89 * 86400)
        a = activity.Activity(None, now)
        a.contacted("fetch", "api.example.com", False, "POST", 200, 64)
        for day in range(90):
            for n in range(60):   # ten more than a day names
                label = ("d%02dn%02d" % (day, n)).ljust(63, "x")
                a.refused("origin", ".".join([label, "x" * 63, "y" * 63, "z" * 61]))
            if day < 89:
                t[0] += 86400
            raw = a.dumps()
            a = activity.Activity(raw, now)
        self.assertLessEqual(len(raw), activity.MAX_FILE)
        s = a.summary()
        api = [x for x in s["sites"] if x["site"] == "api.example.com"]
        self.assertTrue(api and api[0]["writes"] == 1, "day one's write is still shown")
        self.assertEqual(sum(r["count"] for r in s["refused"]) + s["refusedMore"], 90 * 60, "every refusal counted, named or not")
        self.assertTrue(all(r["site"].startswith(("d89", "d88", "d87", "d86", "d85", "d84", "d83", "d82", "d81", "d80", "d7")) for r in s["refused"]),
                        "the names kept are the newest")
        self.assertLessEqual(sum(len(n) + 40 for n in json.loads(raw)["names"]), activity.NAMES_BUDGET)
        self.assertTrue(all(json.loads(raw)["days"][d]["nn"] <= 50 for d in json.loads(raw)["days"]), "at most 50 new names a day")

    def test_refused_names_kept_90_days_too(self):
        """a site refused 100 times, then once more past 90 days: once"""
        t, now = self.clock(time.time() - 100 * 86400)
        a = activity.Activity(None, now)
        for _ in range(100):
            a.refused("origin", "tracker.example")
        t[0] += 100 * 86400
        a.refused("origin", "tracker.example")
        raw = a.dumps()
        s = activity.Activity(raw, now).summary()
        self.assertEqual([(r["site"], r["count"]) for r in s["refused"]], [("tracker.example", 1)])
        self.assertEqual(s["refusedMore"], 0)
        kept = json.loads(raw)["names"]["tracker.example"]
        cut = time.strftime("%Y-%m-%d", time.localtime(t[0] - 90 * 86400))
        self.assertTrue(all(d > cut for d in kept["d"]), "no day of it older than 90 days")
        self.assertGreaterEqual(kept["l"], t[0] - 90 * 86400)
        # a day refused only as a change it may not make, then aged out: no longer marked
        a.refused("method", "api.example.com")
        t[0] += 91 * 86400
        a.refused("origin", "api.example.com")
        s = activity.Activity(a.dumps(), now).summary()
        self.assertEqual([(r["site"], r["count"], r["change"]) for r in s["refused"]], [("api.example.com", 1, False)])

    def test_names_kept_another_way_go_totals_stay(self):
        day = time.strftime("%Y-%m-%d")
        raw = json.dumps({"v": 1, "sites": [["a.example.com", 0]], "days": {day: {"a": {"0": {"f": [3, 0, 10, 3, 0, 0, 0, 0, 5]}}, "x": {"origin": 2}, "nn": 1}},
                          "names": {"tracker.example": [1, int(time.time()), 2, 0]}}).encode()
        s = activity.Activity(raw).summary()
        self.assertEqual((s["sites"][0]["reads"], s["refused"], s["refusedMore"]), (3, [], 2))

    def test_bad_file_is_nothing(self):
        for raw in (b"{", b"[]", b'{"v":2}', b'{"v":1,"sites":"x","days":{"2026-01-01":{"a":{"5":{"f":[1]}}}}}', b"\xff",
                    b'{"v":1,"sites":[["a.example.com",0]],"days":{"abcdefghij":{"a":{"0":{"f":[1,0,0,1,0,0,0,0,5]}}}}}',
                    b'{"v":1,"sites":[["a.example.com",0]],"days":{"2026-13-45":{"a":{"0":{"f":[1,0,0,1,0,0,0,0,5]}}}}}'):
            s = activity.Activity(raw).summary()
            self.assertEqual((s["sites"], s["refused"]), ([], []), raw)

    def test_sites_bounded(self):
        t, now = self.clock(time.time() - 60 * 86400)
        a = activity.Activity(None, now)
        for i in range(activity.MAX_SITES + 10):
            a.contacted("fetch", "server%d.example:8096" % i, True, "GET", 200, 0)
            t[0] += 86400
        self.assertLessEqual(len(a.sites), activity.MAX_SITES)
        self.assertEqual(a.sites[-1], ["server%d.example:8096" % (activity.MAX_SITES + 9), 1])


class ActivityRuntime(unittest.IsolatedAsyncioTestCase):
    async def test_recorded_without_paths(self):
        secret = "s3cr3t-reset-token"
        perms = {"net": ["api.example.com"], "netWrite": {"api.example.com": ["POST"]}}
        base = tempfile.mkdtemp(prefix="activity-", dir=WORK)
        path = os.path.join(base, "act", "app.json")
        h = Harness(make_app("act_rt", FETCHER, perms=perms, api=4), activityPath=path)
        await h.start()
        with FakeNet({"https://api.example.com/r/" + secret: (302, "https://tracker.example/" + secret + "?k=" + secret)}):
            self.assertTrue((await fetch_via(h, "https://api.example.com/a/" + secret + "?token=" + secret)).startswith("status 200"))
            self.assertTrue((await fetch_via(h, "https://api.example.com/w/%73" + secret, method="POST", body=secret)).startswith("status 200"))
            self.assertIn("error origin", await fetch_via(h, "https://tracker.example/" + secret + "?id=" + secret))
            self.assertIn("error origin", await fetch_via(h, "https://api.example.com/r/" + secret))
            self.assertIn("error method", await fetch_via(h, "https://api.example.com/d/" + secret, method="DELETE"))
        await h.stop()
        raw = open(path, "rb").read()
        self.assertEqual(oct(os.stat(path).st_mode & 0o777), "0o600")
        self.assertEqual(oct(os.stat(os.path.dirname(path)).st_mode & 0o777), "0o700")
        self.assertNotIn(secret.encode(), raw, "no path, query, body or header is kept")
        self.assertNotIn(b"/a/", raw)
        s = activity.Activity(raw).summary()
        api = [x for x in s["sites"] if x["site"] == "api.example.com"][0]
        self.assertEqual((api["reads"], api["writes"], api["sent"]), (2, 1, len(secret)))
        self.assertTrue(api["received"] > 0)
        named = {r["site"]: r for r in s["refused"]}
        self.assertEqual((named["tracker.example"]["count"], named["tracker.example"]["change"]), (2, False), "refused directly and through a redirect")
        self.assertEqual((named["api.example.com"]["count"], named["api.example.com"]["change"]), (1, True), "a DELETE it may not make there")
        self.assertEqual(s["refusedMore"], 0)
        told = [f for f in h.frames if f.get("t") == "refused"]
        self.assertEqual(told, [{"t": "refused", "site": "tracker.example"}], "the guide told once, the first time")
        self.assertNotIn(secret, json.dumps([f for f in h.frames if f.get("t") != "result"]), "(the app's own answers echo what it fetched)")
        self.assertNotIn(secret, h.log())

    async def test_header_refusals_counted(self):
        base = tempfile.mkdtemp(prefix="activity-", dir=WORK)
        path = os.path.join(base, "act.json")
        h = Harness(make_app("act_hdr", FETCHER, perms={"net": ["api.example.com"]}), activityPath=path)
        await h.start()
        with FakeNet() as f:
            for bad in ({"Cookie": "session=s3cr3t"}, {"X-A": "a\r\nHost: evil"}):
                self.assertIn("error headers", await fetch_via(h, "https://api.example.com/x?k=s3cr3t", headers=bad))
            self.assertEqual(f.hops, [], "nothing was sent")
        await h.stop()
        raw = open(path, "rb").read()
        self.assertNotIn(b"s3cr3t", raw)
        d = json.loads(raw)
        self.assertEqual(list(d["days"].values())[0]["x"], {"headers": 2})
        s = activity.Activity(raw).summary()
        self.assertEqual([(r["site"], r["count"]) for r in s["refused"]], [("api.example.com", 2)], "the site, not the address")
        self.assertEqual([f for f in h.frames if f.get("t") == "refused"], [{"t": "refused", "site": "api.example.com"}])

    async def test_each_hop_counted_where_it_went(self):
        base = tempfile.mkdtemp(prefix="activity-", dir=WORK)
        path = os.path.join(base, "act.json")
        perms = {"net": ["api.example.com", "b.example.com"]}
        h = Harness(make_app("act_hops", FETCHER, perms=perms), activityPath=path)
        await h.start()
        A, B = "https://api.example.com", "https://b.example.com"
        with FakeNet({A + "/r": (302, B + "/x"), B + "/x": ("fail", "connect"), A + "/nl": (302, None), A + "/bad": (302, "/%2e%2e/x")}):
            self.assertIn("error connect", await fetch_via(h, A + "/r"))
            self.assertIn("error http", await fetch_via(h, A + "/nl"))
            self.assertIn("error path", await fetch_via(h, A + "/bad"))
        await h.stop()
        s = activity.Activity(open(path, "rb").read()).summary()
        by = {x["site"]: x for x in s["sites"]}
        self.assertEqual((by[A[8:]]["reads"], by[A[8:]]["failed"]), (3, 0), "three redirects answered by the first site, none failed there")
        self.assertEqual((by[B[8:]]["reads"], by[B[8:]]["failed"]), (1, 1), "the failure counted where it happened")
        self.assertEqual((s["refused"], s["refusedMore"]), ([], 1), "a Location that couldn't be read: one refusal, no name, nothing counted twice")

    async def test_written_at_most_once_a_minute(self):
        perms = {"net": ["api.example.com"]}
        base = tempfile.mkdtemp(prefix="activity-", dir=WORK)
        path = os.path.join(base, "act.json")
        h = Harness(make_app("act_min", FETCHER, perms=perms), activityPath=path)
        await h.start()
        with FakeNet():
            await fetch_via(h, "https://api.example.com/a")
            h.rt.activity_at = h.rt.loop.time()
            await fetch_via(h, "https://api.example.com/b")
            h.rt.commit()
            self.assertFalse(os.path.exists(path), "not written again within a minute")
            h.rt.activity_at -= 61
            h.rt.commit()
            self.assertTrue(os.path.exists(path))
        await h.stop()

    async def test_try_keeps_none(self):
        h = Harness(make_app("act_try", FETCHER, perms={"net": ["api.example.com"]}))
        await h.start()
        with FakeNet():
            await fetch_via(h, "https://tracker.example/")
        await h.stop()
        self.assertIsNone(h.rt.activity)
        self.assertEqual([f for f in h.frames if f.get("t") == "refused"], [], "no notice without a guide")


# ---- code apps v2, milestone 2: password sign-in ----------------------------

PASSWORD_APP = """from uber_tv import app, fetch, Screen, Message, log
import os, sys, json
STATE = {"last": None}
@app.sign_in
def sign_in(flow):
    if flow.how != "password":
        flow.done(False, "only a password here")
        return
    typed = flow.credentials()
    if typed is None:
        print("credentials: none (called off)", file=sys.stderr)
        return
    user, pw = typed
    STATE["last"] = (user, pw)
    print("argv " + " ".join(sys.argv) + " env " + json.dumps(dict(os.environ)), file=sys.stderr)
    if pw == "right-password" or pw == "ab":
        flow.keep("token", "tok-" + user)
        flow.done(True, "Signed in.")
    else:
        flow.done(False, "Wrong password.")
@app.home
def home():
    # a careless app: it logs what it was given, after the sign-in is over
    if STATE["last"]:
        u, p = STATE["last"]
        print("the last password was " + p + " for " + u, file=sys.stderr)
        print("unrelated line", file=sys.stderr)
    return Screen("home", rows=[])
app.run()
"""


class PasswordSignIn(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.folder = make_app("pw_signin", PASSWORD_APP, perms={"server": {"label": "S"}, "signIn": ["code", "password"]}, api=4)

    async def started(self, **cfg):
        h = Harness(self.folder, server="http://127.0.0.1:9/jf", **cfg)
        await h.start()
        return h

    async def frame(self, h, t, flow, wait=8):
        end = time.monotonic() + wait
        while time.monotonic() < end:
            for f in h.frames:
                if f.get("t") == t and f.get("flow") == flow:
                    return f
            await asyncio.sleep(0.05)
        return None

    async def sign_in(self, h, password, username="alex"):
        flow = secrets_hex()
        r = await h.call("signIn", {"flow": flow, "how": "password"})
        self.assertEqual(r["kind"], "ok")
        await h.rt.from_guide({"t": "signInPassword", "flow": flow, "username": username, "password": password})
        return flow, await self.frame(h, "signInDone", flow)

    async def test_signed_in_and_never_kept_or_logged(self):
        h = await self.started()
        flow, done = await self.sign_in(h, "right-password")
        self.assertEqual((done["ok"], done["message"]), (True, "Signed in."))
        kept = json.load(open(h.cfg["secretsPath"]))
        self.assertEqual(kept["signIn"]["values"], {"token": "tok-alex"}, "what the service gave back, nothing typed")
        await h.call("home")
        await h.stop()
        log = h.log()
        self.assertIn("unrelated line", log)
        self.assertNotIn("right-password", log, "the password never in its log, even after the sign-in")
        self.assertNotIn("alex", log, "nor the username")
        self.assertIn("[secret]", log)
        for path in (h.cfg["storePath"], h.cfg["secretsPath"]):
            if os.path.exists(path):
                self.assertNotIn(b"right-password", open(path, "rb").read())
        self.assertNotIn("right-password", json.dumps(h.frames), "nor in anything the helper told the guide")

    async def test_short_password_lines_left_out(self):
        h = await self.started()
        flow, done = await self.sign_in(h, "ab", username="al")
        self.assertTrue(done["ok"])
        await h.call("home")
        await h.stop()
        log = h.log()
        self.assertNotIn("password was ab", log)
        self.assertIn(apprun.Log.LEFT_OUT, log, "a line holding a 1 to 3 character password is left out whole")

    async def test_failed_and_cancelled_attempts_stay_out_of_the_log(self):
        h = await self.started()
        flow, done = await self.sign_in(h, "wrong-one-1")
        self.assertEqual((done["ok"], done["message"]), (False, "Wrong password."))
        self.assertFalse(os.path.exists(h.cfg["secretsPath"]) and json.load(open(h.cfg["secretsPath"]))["signIn"]["values"])
        await h.call("home")
        # a cancelled one: the app hears it and stops waiting; nothing it was given
        flow2 = secrets_hex()
        await h.call("signIn", {"flow": flow2, "how": "password"})
        await h.rt.from_guide({"t": "signInCancel", "flow": flow2})
        self.assertFalse((await self.frame(h, "signInDone", flow2))["ok"])
        await asyncio.sleep(0.6)
        await h.stop()
        log = h.log()
        self.assertNotIn("wrong-one-1", log)
        self.assertIn("credentials: none (called off)", log, "a cancelled flow stops waiting at once")

    async def test_given_once_and_only_in_its_flow(self):
        h = await self.started()
        seen = []
        real = h.rt.to_app
        h.rt.to_app = lambda f: (seen.append(f) if f.get("t") == "credentials" else None, real(f))[1]
        flow = secrets_hex()
        await h.call("signIn", {"flow": flow, "how": "password"})
        for bad in ({"flow": secrets_hex(), "username": "u", "password": "p1234"},        # another flow
                    {"flow": flow, "username": "", "password": "p1234"},                  # no username
                    {"flow": flow, "username": "u", "password": "x" * 1025},              # too long
                    {"flow": flow, "username": "u\0", "password": "p1234"},              # NUL
                    {"flow": flow, "username": "u", "password": "abcd\nefgh"},           # a line break: the log reads lines
                    {"flow": flow, "username": "u", "password": "abcd\refgh"},
                    {"flow": flow, "username": "al\nex", "password": "p1234"}):
            await h.rt.from_guide(dict(bad, t="signInPassword"))
        self.assertEqual(seen, [])
        await h.rt.from_guide({"t": "signInPassword", "flow": flow, "username": "u", "password": "right-password"})
        await h.rt.from_guide({"t": "signInPassword", "flow": flow, "username": "u", "password": "second-try"})
        self.assertEqual([f["password"] for f in seen], ["right-password"], "once a flow")
        # a code flow takes none
        flow2 = secrets_hex()
        await h.call("signIn", {"flow": flow2, "how": "code"})
        await h.rt.from_guide({"t": "signInPassword", "flow": flow2, "username": "u", "password": "p1234"})
        self.assertEqual(len(seen), 1)
        await h.stop()

    async def test_a_password_flow_shows_no_code(self):
        folder = make_app("pw_code_in_pw", """from uber_tv import app, AppError
import sys
@app.sign_in
def sign_in(flow):
    flow.how = "code"          # a buggy app pretending, past the toolkit's own check
    flow.show_code("123456")
    flow.sleep(30)
app.run()
""", perms={"server": {"label": "S"}, "signIn": ["code", "password"]}, api=4)
        h = Harness(folder, server="http://127.0.0.1:9/jf")
        await h.start()
        flow = secrets_hex()
        await h.call("signIn", {"flow": flow, "how": "password"})
        await asyncio.sleep(1)
        self.assertEqual([f for f in h.frames if f.get("t") == "signInCode"], [], "the guide never sees a code in a password sign-in")
        self.assertIn("its sign-in code was refused", h.log())
        await h.stop()
        # and the toolkit says so at once to an app that calls it
        folder2 = make_app("pw_code_in_pw2", """from uber_tv import app
@app.sign_in
def sign_in(flow):
    flow.show_code("123456")
app.run()
""", perms={"server": {"label": "S"}, "signIn": ["code", "password"]}, api=4)
        h2 = Harness(folder2, server="http://127.0.0.1:9/jf")
        await h2.start()
        flow = secrets_hex()
        await h2.call("signIn", {"flow": flow, "how": "password"})
        done = await self.frame(h2, "signInDone", flow)
        self.assertEqual((done["ok"], "use flow.credentials()" in done["message"]), (False, True))
        await h2.stop()

    async def test_only_the_ways_it_offers(self):
        folder = make_app("pw_code_only", PASSWORD_APP, perms={"server": {"label": "S"}, "signIn": "code"})
        h = Harness(folder, server="http://127.0.0.1:9/jf")
        await h.start()
        r = await h.call("signIn", {"flow": secrets_hex(), "how": "password"})
        self.assertEqual((r["kind"], r["value"]["code"]), ("error", "invalid"))
        r = await h.call("signIn", {"flow": secrets_hex(), "how": "fingerprint"})
        self.assertEqual(r["kind"], "error")
        await h.stop()

    async def test_older_apps_hear_no_cancel(self):
        folder = make_app("pw_api3", PASSWORD_APP, perms={"server": {"label": "S"}, "signIn": "code"}, api=3)
        h = Harness(folder, server="http://127.0.0.1:9/jf")
        await h.start()
        seen = []
        real = h.rt.to_app
        h.rt.to_app = lambda f: (seen.append(f.get("t")), real(f))[1]
        flow = secrets_hex()
        await h.call("signIn", {"flow": flow})
        await h.rt.from_guide({"t": "signInCancel", "flow": flow})
        self.assertNotIn("signInCancel", seen, "an api 3 app isn't sent a frame it doesn't know")
        await h.stop()


# ---- code apps v2, milestone 2: choosing your server during sign-in --------

ACCOUNT_APP = """from uber_tv import app, fetch, storage, secret, Screen, FetchError
import uber_tv, json
SERVERS = json.loads(SERVERS_JSON)   # what the account lists, each with its own token
@app.sign_in
def sign_in(flow):
    flow.show_code("123456")
    flow.sleep(0.2)
    tokens = {s["handle"]: s["token"] for s in SERVERS}
    chosen = flow.offer_servers([{"handle": s["handle"], "label": s["label"], "urls": s["urls"]} for s in SERVERS])
    if chosen is None:
        return
    storage.put("serverName", chosen["handle"], server=True)
    flow.keep("token", tokens[chosen["handle"]])
    if FAIL:
        flow.done(False, "That server said no.")
        return
    try:
        r = fetch(chosen["url"].rstrip("/") + "/identity", headers={"X-Plex-Token": tokens[chosen["handle"]]})
        ok = r.status == 200 and uber_tv.server == chosen["url"]
    except FetchError:
        ok = False
    flow.done(ok, "Signed in." if ok else "That server didn't answer.")
@app.home
def home():
    tok = secret("token")
    return Screen(("signed in to " + uber_tv.server) if tok and uber_tv.server else "signed out", rows=[])
app.run()
"""


class ServerFromSignIn(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.a = await LocalServer().start()
        self.b = await LocalServer().start()
        self.A = "http://127.0.0.1:" + str(self.a.port) + "/"   # as the helper makes a server's address canonical
        self.B = "http://127.0.0.1:" + str(self.b.port) + "/"
        self.servers = [{"handle": "res-a", "label": "Living room", "urls": [self.A.rstrip("/")], "token": "tok-a"},
                        {"handle": "res-b", "label": "Office", "urls": ["http://192.0.2.9:32400"], "token": "tok-b"}]

    async def asyncTearDown(self):
        self.a.close()
        self.b.close()

    def app(self, fail=False, from_sign_in=True, name="acct"):
        main = "SERVERS_JSON = %r\nFAIL = %r\n" % (json.dumps(self.servers), fail) + ACCOUNT_APP
        server = {"label": "Your server"}
        if from_sign_in:
            server["fromSignIn"] = True
        return make_app(name, main, perms={"server": server, "signIn": "code", "storage": True}, api=4)

    async def frame(self, h, t, flow, wait=8):
        end = time.monotonic() + wait
        while time.monotonic() < end:
            for f in h.frames:
                if f.get("t") == t and f.get("flow") == flow:
                    return f
            await asyncio.sleep(0.05)
        return None

    async def begin(self, h):
        flow = secrets_hex()
        r = await h.call("signIn", {"flow": flow})
        self.assertEqual(r["kind"], "ok")
        offered = await self.frame(h, "signInServers", flow)
        self.assertIsNotNone(offered, "the servers reach the guide")
        return flow, offered

    async def test_two_servers_and_an_address_typed_for_the_second(self):
        h = Harness(self.app(), server=None, signedIn=False)
        await h.start()
        flow, offered = await self.begin(h)
        self.assertEqual(offered["servers"], [{"handle": "res-a", "label": "Living room", "urls": [self.A]},
                                              {"handle": "res-b", "label": "Office", "urls": ["http://192.0.2.9:32400/"]}],
                         "names, canonical addresses and handles: never a token")
        self.assertNotIn("tok-", json.dumps(h.frames))
        await h.rt.from_guide({"t": "signInServer", "flow": flow, "handle": "res-b", "typedAddress": self.B.rstrip("/")})
        done = await self.frame(h, "signInDone", flow)
        self.assertEqual((done["ok"], done["server"]), (True, self.B), "done, with the server chosen, canonical")
        self.assertEqual([r[1].get("x-plex-token") for r in self.b.requests], ["tok-b"], "the second's token, to the address typed for it")
        self.assertEqual(self.a.requests, [], "the first's never reached anywhere")
        kept = json.load(open(h.cfg["secretsPath"]))
        self.assertEqual(kept["signIn"], {"server": self.B, "values": {"token": "tok-b"}})
        await h.stop()
        # the helper evicted, or a full restart: the record has the server and the sign-in
        h2 = Harness(self.app(), server=self.B, signedIn=True, secretsPath=h.cfg["secretsPath"], storePath=h.cfg["storePath"])
        await h2.start()
        r = await h2.call("home")
        self.assertEqual(r["value"]["title"], "signed in to " + self.B, "no new sign-in needed")
        await h2.stop()

    async def test_only_its_own_handles_and_addresses(self):
        h = Harness(self.app(), server=None, signedIn=False)
        await h.start()
        flow, _ = await self.begin(h)
        chosen = lambda: [f for f in h.frames if f.get("t") == "signInServerRefused"]
        await h.rt.from_guide({"t": "signInServer", "flow": secrets_hex(), "handle": "res-a", "url": self.A})   # another flow
        await h.rt.from_guide({"t": "signInServer", "flow": flow, "handle": "res-z", "url": self.A})          # not a handle it listed
        self.assertEqual(chosen(), [], "ignored")
        await h.rt.from_guide({"t": "signInServer", "flow": flow, "handle": "res-b", "url": self.A})          # the first's address for the second
        await h.rt.from_guide({"t": "signInServer", "flow": flow, "handle": "res-b", "typedAddress": "ftp://x"})
        await asyncio.sleep(0.3)
        self.assertEqual(len(chosen()), 2, "refused, saying why")
        self.assertIsNone(h.rt.server, "nothing chosen")
        await h.rt.from_guide({"t": "signInServer", "flow": flow, "handle": "res-a", "url": self.A})
        done = await self.frame(h, "signInDone", flow)
        self.assertEqual((done["ok"], done["server"]), (True, self.A))
        await h.stop()

    async def test_a_runtime_with_a_server_takes_only_that_one(self):
        h = Harness(self.app(), server=self.A, signedIn=False)
        await h.start()
        flow, _ = await self.begin(h)
        await h.rt.from_guide({"t": "signInServer", "flow": flow, "handle": "res-b", "typedAddress": self.B})
        refused = await self.frame(h, "signInServerRefused", flow)
        self.assertIn("switch it first", refused["why"])
        await h.rt.from_guide({"t": "signInServer", "flow": flow, "handle": "res-a", "url": self.A})
        done = await self.frame(h, "signInDone", flow)
        self.assertEqual((done["ok"], done["server"]), (True, self.A))
        await h.stop()

    async def test_a_sign_in_that_fails_keeps_nothing(self):
        for how in ("fail", "cancel"):
            h = Harness(self.app(fail=how == "fail", name="acct_" + how), server=None, signedIn=False)
            await h.start()
            flow, _ = await self.begin(h)
            if how == "cancel":
                # an address that doesn't answer (TEST-NET): called off while it waits
                await h.rt.from_guide({"t": "signInServer", "flow": flow, "handle": "res-b", "url": "http://192.0.2.9:32400/"})
                await asyncio.sleep(0.5)
                await h.rt.from_guide({"t": "signInCancel", "flow": flow})
            else:
                await h.rt.from_guide({"t": "signInServer", "flow": flow, "handle": "res-a", "url": self.A})
            done = await self.frame(h, "signInDone", flow)
            self.assertEqual((done["ok"], done.get("server", "")), (False, ""), how)
            self.assertIsNone(h.rt.server, how + ": back to no server")
            self.assertEqual(h.rt.secrets.server, "")
            kept = json.load(open(h.cfg["secretsPath"])) if os.path.exists(h.cfg["secretsPath"]) else {"signIn": {"values": {}}}
            self.assertEqual(kept["signIn"]["values"], {}, how + ": what it kept for that server forgotten")
            self.assertNotIn("serverName", h.rt.store.map, how + ": and its storage marked for that server")
            await h.stop()

    async def test_an_app_that_doesnt_choose_its_server_cant_offer_any(self):
        h = Harness(self.app(from_sign_in=False, name="acct_plain"), server=self.A, signedIn=False)
        await h.start()
        flow = secrets_hex()
        await h.call("signIn", {"flow": flow})
        await asyncio.sleep(1)
        self.assertEqual([f for f in h.frames if f.get("t") == "signInServers"], [])
        await h.stop()
        self.assertIn("its list of servers was refused", h.log())

    def test_the_accounts_example_signs_in_and_chooses_offline(self):
        """apps/sdk/examples/accounts with its fixtures: a password sign-in,
        the account's servers, the one the call names, kept with its token"""
        folder = os.path.join(ROOT, "apps", "sdk", "examples", "accounts")
        c = subprocess.run([sys.executable, "-I", os.path.join(ROOT, "bin", "om-pg-apps"), "check", folder], capture_output=True, text=True, timeout=60)
        res = json.loads(c.stdout.strip().splitlines()[-1])
        self.assertTrue(res.get("ok") and not res.get("errors") and not res.get("warnings"), c.stdout[-400:])
        self.assertEqual(res["manifest"]["permissions"]["server"].get("fromSignIn"), True)
        sec = os.path.join(WORK, "accounts-secrets.json")
        with open(sec, "w") as f:
            json.dump({"@username": "alex", "@password": "example-password"}, f)
        os.chmod(sec, 0o600)
        p = subprocess.run([sys.executable, "-I", os.path.join(ROOT, "bin", "om-pg-apprun"), "try", folder, "--fixtures", os.path.join(folder, "fixtures.json"),
                            "--secrets", sec, "--allow-write", "--call", 'signIn:{"how":"password","server":"office","url":"http://192.168.1.20:32400/"}',
                            "--call", "home"], capture_output=True, text=True, timeout=90)
        out = p.stdout
        self.assertEqual(p.returncode, 0, out[-600:] + p.stderr[-300:])
        self.assertIn("SIGN IN server office: Office at http://192.168.1.20:32400/, https://office.example:32400/", out)
        self.assertIn("SIGN IN done: Signed in to Office. (server http://192.168.1.20:32400/)", out)
        self.assertIn("Office — http://192.168.1.20:32400/", out, "home: the server it kept")
        self.assertNotIn("token-office", out, "a server's token never shows")
        self.assertNotIn("example-password", out)

    def test_the_frame_is_checked(self):
        flow = secrets_hex()
        ok = {"t": "signInServers", "flow": flow, "servers": [{"handle": "a", "label": "A", "urls": ["http://h"]}]}
        self.assertEqual(blocks.check_frame(ok), "signInServers")
        for bad in ([{"handle": "a", "label": "A", "urls": ["http://h"]}] * 2,                       # a handle twice
                    [{"handle": "a b", "label": "A", "urls": ["http://h"]}],                          # not a handle
                    [{"handle": "a", "label": "A", "urls": []}],                                      # no address
                    [{"handle": "a", "label": "A", "urls": ["http://h"] * 9}],                        # 9 addresses
                    [{"handle": "h" + str(i), "label": "A", "urls": ["http://h"]} for i in range(11)],  # 11 servers
                    [{"handle": "a", "label": "A", "urls": ["http://h"], "token": "x"}]):             # anything else
            with self.assertRaises(blocks.Violation):
                blocks.check_frame(dict(ok, servers=bad))


# ---- code apps v2, milestone 3: richer blocks -------------------------------

class Api4Raw(unittest.IsolatedAsyncioTestCase):
    async def test_an_answer_that_cant_be_checked_still_answers(self):
        """a details answer with a 310-digit number (valid JSON): refused as
        invalid, and the helper goes on reading the app"""
        body = ("send({'t':'ready'})\n"
                "for line in sys.stdin:\n"
                "    f = json.loads(line)\n"
                "    if f.get('t') != 'call': continue\n"
                "    if f['method'] == 'details':\n"
                "        out.write(('{\"t\":\"result\",\"id\":%d,\"detail\":{\"title\":\"T\",\"chart\":{\"points\":[0,' % f['id'] + '9' * 310 + ']}}}\\n').encode()); out.flush()\n"
                "    else:\n"
                "        send({'t':'result','id':f['id'],'screen':{'title':'still here','rows':[]}})\n")
        folder = make_app("raw_bigint", RAW + body, api=4)
        h = Harness(folder)
        await h.start()
        r = await h.call("details", {"item": "a"})
        self.assertIsNotNone(r, "it answered")
        self.assertEqual((r["kind"], r["value"]["code"]), ("error", "invalid"))
        r = await h.call("home")
        self.assertEqual((r["kind"], r["value"]["title"]), ("screen", "still here"), "and the next call is read")
        await h.stop()

    async def test_a_check_that_breaks_still_answers(self):
        """whatever a check raises (a bug of the guide's own), the call is
        answered and the reader goes on"""
        folder = make_app("raw_broken_check", RAW + "send({'t':'ready'})\nfor line in sys.stdin:\n    f = json.loads(line)\n"
                          "    if f.get('t') == 'call': send({'t':'result','id':f['id'],'screen':{'title':'ok','rows':[]}})\n", api=4)
        h = Harness(folder)
        await h.start()
        real = blocks.result
        blocks.result = lambda *a, **k: (_ for _ in ()).throw(RecursionError("a check gone wrong"))
        try:
            r = await h.call("home")
        finally:
            blocks.result = real
        self.assertEqual((r["kind"], r["value"]["code"]), ("error", "invalid"))
        r = await h.call("home")
        self.assertEqual((r["kind"], r["value"]["title"]), ("screen", "ok"))
        await h.stop()


class Api4Blocks(unittest.TestCase):
    def table(self, **over):
        row = {"id": "standings", "title": "Standings", "layout": "table",
               "columns": [{"label": "#", "align": "end"}, {"label": "Team"}],
               "items": [{"id": "t1", "title": "Gulls", "cells": ["1", "Gulls"], "chart": {"points": [1, 3, 2], "low": "0", "high": "9"}}]}
        row.update(over)
        return {"rows": [row]}

    def test_a_table(self):
        out = checked("screen", self.table(), 4)[1]
        r = out["rows"][0]
        self.assertEqual(r["columns"], [{"label": "#", "align": "end"}, {"label": "Team", "align": "start"}])
        self.assertEqual(r["items"][0]["cells"], ["1", "Gulls"])
        self.assertEqual(r["items"][0]["chart"], {"points": [1.0, 3.0, 2.0], "low": "0", "high": "9"})
        for over, why in [({"columns": []}, "no columns"),
                          ({"columns": [{"label": str(i)} for i in range(9)]}, "9 columns"),
                          ({"columns": [{"label": "x" * 25}]}, "a label over 24"),
                          ({"columns": [{"label": "a", "align": "middle"}]}, "an align that isn't one"),
                          ({"items": [{"id": "t1", "title": "G", "cells": ["1"]}]}, "fewer cells than columns"),
                          ({"items": [{"id": "t1", "title": "G", "cells": ["1", "x" * 41]}]}, "a cell over 40"),
                          ({"items": [{"id": "t1", "title": "G"}]}, "an item without cells"),
                          ({"items": [{"id": "t1", "title": "G", "cells": ["1", "a\nb"]}]}, "a cell with a line break")]:
            refused(self, "screen", self.table(**over), 4, why)
        refused(self, "screen", self.table(), 3, "a table at api 3")

    def test_cells_and_columns_only_in_a_table(self):
        refused(self, "screen", {"rows": [{"id": "r", "title": "R", "layout": "list", "columns": [{"label": "a"}], "items": []}]}, 4, "columns on a list")
        refused(self, "screen", {"rows": [{"id": "r", "title": "R", "layout": "list", "items": [{"id": "a", "title": "A", "cells": ["x"]}]}]}, 4, "cells in a list")

    def test_a_ticker(self):
        items = [{"id": "n%d" % i, "title": "News %d" % i, "badge": "NEW"} for i in range(30)]
        out = checked("screen", {"rows": [{"id": "news", "title": "News", "layout": "ticker", "items": items}]}, 4)[1]
        self.assertEqual(len(out["rows"][0]["items"]), 30)
        refused(self, "screen", {"rows": [{"id": "news", "title": "News", "layout": "ticker", "items": items + [{"id": "x", "title": "X"}]}]}, 4, "31 items")
        for extra in ({"image": {"url": "https://img.example.com/a.jpg"}}, {"images": {"poster": {"asset": "a.png"}}}, {"chart": {"points": [1, 2]}}):
            refused(self, "screen", {"rows": [{"id": "news", "title": "News", "layout": "ticker", "items": [dict({"id": "a", "title": "A"}, **extra)]}]}, 4,
                    "a ticker item with " + list(extra)[0])
        refused(self, "screen", {"rows": [{"id": "news", "title": "News", "layout": "ticker", "items": items[:1]}]}, 3, "a ticker at api 3")

    def test_a_chart(self):
        out = checked("detail", {"title": "Team", "chart": {"points": [0, 2.5, -1]}}, 4)[1]
        self.assertEqual(out["chart"], {"points": [0.0, 2.5, -1.0], "low": "", "high": ""})
        for c, why in [({"points": [1]}, "one point"), ({"points": list(range(121))}, "121 points"), ({"points": [1, float("nan")]}, "NaN"),
                       ({"points": [1, "2"]}, "a string"), ({"points": [1, True]}, "true"), ({"points": [1, 2], "low": "x" * 25}, "a label over 24"),
                       ({"points": [1, 2], "color": "red"}, "styling")]:
            refused(self, "detail", {"title": "Team", "chart": c}, 4, why)
        refused(self, "detail", {"title": "Team", "chart": {"points": [1, 2]}}, 3, "a chart at api 3")

    def test_a_page(self):
        sections = [{"heading": "H%d" % i, "text": "Line one\nLine two"} for i in range(30)]
        kind, out = blocks.result("browse", {"t": "result", "id": 1, "page": {"title": "An article", "sections": sections}}, lambda r, w: None, 4)
        self.assertEqual((kind, out["title"], len(out["sections"]), out["sections"][0]["text"]), ("page", "An article", 30, "Line one\nLine two"))
        for method in ("details", "action"):
            self.assertEqual(blocks.result(method, {"t": "result", "id": 1, "page": {"title": "A", "sections": []}}, lambda r, w: None, 4)[0], "page")
        page = lambda v, m="browse", api=4: blocks.result(m, {"t": "result", "id": 1, "page": v}, lambda r, w: None, api)
        for v, why in [({"title": "A", "sections": sections + [{"text": "x"}]}, "31 sections"),
                       ({"title": "A", "sections": [{"text": "x" * 4000}] * 8}, "over 30,000 characters"),
                       ({"title": "A", "sections": [{"text": "x" * 4001}]}, "a section over 4,000"),
                       ({"title": "", "sections": []}, "no title"),
                       ({"title": "A", "sections": [{"heading": "", "text": "  "}]}, "an empty section"),
                       ({"title": "A", "sections": [{"text": "a‮b"}]}, "a bidi override"),
                       ({"title": "A", "sections": [], "image": {"asset": "a.png"}}, "a picture")]:
            with self.assertRaises(blocks.Invalid, msg=why):
                page(v)
        with self.assertRaises(blocks.Invalid):
            page({"title": "A", "sections": []}, "home")
        with self.assertRaises(blocks.Invalid):
            page({"title": "A", "sections": []}, api=3)
        self.assertEqual(blocks.check_frame({"t": "result", "id": 1, "page": {"title": "A"}}), "result")

    def test_a_page_keeps_every_line_its_text_holds(self):
        text201 = "\n".join("x" * 201)
        kind, out = blocks.result("browse", {"t": "result", "id": 1, "page": {"title": "A", "sections": [{"text": text201}]}}, lambda r, w: None, 4)
        self.assertEqual(out["sections"][0]["text"], text201, "201 lines, 401 characters: kept as they are")
        sys.path.insert(0, os.path.join(ROOT, "apps", "sdk"))
        try:
            import importlib
            ut = importlib.import_module("uber_tv")
        finally:
            sys.path.pop(0)
        self.assertEqual(ut.Section("H", text201).to_dict()["text"], text201, "and the toolkit keeps them too")
        with self.assertRaises(blocks.Invalid):
            blocks.result("browse", {"t": "result", "id": 1, "page": {"title": "A", "sections": [{"text": "x\n" * 2001}]}}, lambda r, w: None, 4)

    def test_numbers_too_big_for_a_float(self):
        self.assertFalse(blocks.is_num(10 ** 309), "a 310-digit integer isn't a number the guide takes")
        self.assertTrue(blocks.is_num(10 ** 300))
        refused(self, "detail", {"title": "T", "chart": {"points": [0, 10 ** 309]}}, 4, "a point past a float")
        refused(self, "screen", {"rows": [{"id": "r", "title": "R", "layout": "row", "items": [{"id": "a", "title": "A", "progress": 10 ** 309}]}]}, 4, "a progress past a float")

    def test_the_toolkit_leaves_api_4_out_for_api_3(self):
        sys.path.insert(0, os.path.join(ROOT, "apps", "sdk"))
        try:
            import importlib
            ut = importlib.import_module("uber_tv")
        finally:
            sys.path.pop(0)
        row = ut.Row("s", "S", [ut.Item("a", "A", cells=["1"], chart=ut.Chart([1, 2]))], layout="table", columns=[ut.Column("#")])
        out = ut._api3({"screen": ut.Screen("T", rows=[row]).to_dict()})
        r = out["screen"]["rows"][0]
        self.assertEqual((r["layout"], "columns" in r, "cells" in r["items"][0], "chart" in r["items"][0]), ("list", False, False, False))
        with self.assertRaises(ut.AppError):
            ut._api3({"page": ut.Page("A").to_dict()})


# ---- code apps v2, milestone 4: live updates --------------------------------

LIVE_APP = """from uber_tv import app, Screen, Row, Item, Message, fetch, FetchError
import uber_tv, json
@app.home
def home():
    return Screen("Live", rows=[Row("a", "A", [Item("a1", "One", image="https://img.example.com/a.jpg")]),
                                Row("b", "B", [Item("b1", "Bee", image="https://img.example.com/b.jpg")])], live=True)
@app.home_row
def home_row(key):
    return [Item("h1", "Home one", image="https://img.example.com/h.jpg")]
@app.action
def action(item, how):
    # a test's frame, sent as the app would send it
    uber_tv._send(json.loads(item))
    return Message("sent")
@app.live
def live(view):
    if view.method != "home":
        return
    try:
        r = fetch("https://api.example.com/score")
        said = "fetched " + str(r.status)
    except FetchError as e:
        said = "error " + e.code
    view.update([Row("b", "B", [Item("b1", said)])])
    while view.sleep(0.1):
        pass
    uber_tv._send({"t": "log", "text": "the live view went"})
app.run()
"""


class StreamRes:
    """A reply to a stream: its type, then its chunks"""

    def __init__(self, url, chunks, ctype="text/event-stream", status=200):
        self.url, self.method, self.status = url, "GET", status
        self.headers = [("Content-Type", ctype)]
        self.chunks = list(chunks)
        self.received = 0
        self.on_close = None

    def header(self, name):
        return dict((k.lower(), v) for k, v in self.headers).get(name)

    async def chunk(self, size=65536):
        if not self.chunks:
            await asyncio.sleep(3600)   # a stream that stays open
        c = self.chunks.pop(0)
        if c == "wait":
            await asyncio.sleep(3600)
        return c

    def close(self):
        told, self.on_close = self.on_close, None
        if told:
            told(self.received)


class LiveViews(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.stream_chunks = [b"data: one\n", b"data: two\n", "wait"]
        self.real = net.exchange
        test = self

        async def exchange(url, method, headers, body, gate, kind, pin="", resolver=None):
            gate.allow(url)
            if url.host == "stream.example.com":
                return StreamRes(url, test.stream_chunks)
            return FakeRes(url, method, 200, None, b'{"ok":true}')
        net.exchange = exchange
        perms = {"net": ["api.example.com", "img.example.com", "stream.example.com"], "storage": True}
        self.h = Harness(make_app("live_views", LIVE_APP, perms=perms, extra=None, api=4))
        # Home rows come from app.json's home
        m = json.load(open(os.path.join(self.h.cfg["appDir"], "app.json")))
        m["home"] = [{"key": "now", "label": "Now"}]
        json.dump(m, open(os.path.join(self.h.cfg["appDir"], "app.json"), "w"))
        await self.h.start()
        r = await self.h.call("home")
        self.assertEqual(r["kind"], "screen")
        self.rid = self.h.n
        self.assertTrue(r["value"]["live"])

    async def asyncTearDown(self):
        await self.h.stop()
        net.exchange = self.real

    async def send(self, frame):
        r = await self.h.call("action", {"item": json.dumps(frame), "action": "send"})
        self.assertEqual(r["value"]["text"], "sent")
        await asyncio.sleep(0.15)

    def updates(self):
        return [f for f in self.h.frames if f.get("t") == "update"]

    def row(self, rid, title, url=None):
        it = {"id": rid + "1", "title": title}
        if url:
            it["image"] = {"url": url}
        return {"id": rid, "title": rid.upper(), "items": [it]}

    async def test_on_updates_off(self):
        await self.send({"t": "update", "view": self.rid, "rows": [self.row("a", "early")]})
        self.assertEqual(self.updates(), [], "an update before the view is on: dropped")
        await self.h.rt.from_guide({"t": "viewOn", "view": self.rid})
        await asyncio.sleep(0.6)
        ups = self.updates()
        self.assertEqual(len(ups), 1, "the app's live handler, started by viewOn")
        self.assertEqual(ups[0]["rows"][0]["items"][0]["title"], "fetched 200", "a view's own fetch works while it's on")
        await asyncio.sleep(1.1)
        await self.send({"t": "update", "view": self.rid, "rows": [self.row("a", "two", "https://img.example.com/a2.jpg")]})
        ups = self.updates()
        self.assertEqual(len(ups), 2)
        self.assertEqual(ups[1]["rows"][0]["items"][0]["title"], "two")
        tok = ups[1]["rows"][0]["items"][0]["image"]["token"]
        self.assertIn((self.rid, "a"), self.h.rt.live)
        self.assertEqual(self.h.rt.live[(self.rid, "a")], {tok}, "the row holds its new picture only")
        await self.send({"t": "update", "view": self.rid, "rows": [self.row("a", "too soon")]})
        self.assertEqual(len(self.updates()), 2, "within a second of the last: dropped")
        await self.h.rt.from_guide({"t": "viewOff", "view": self.rid})
        await asyncio.sleep(1.1)
        await self.send({"t": "update", "view": self.rid, "rows": [self.row("a", "after off")]})
        self.assertEqual(len(self.updates()), 2, "the view's gone: dropped")
        await asyncio.sleep(0.4)
        self.h.rt.commit()
        self.assertIn("the live view went", self.h.log(), "the app's live handler heard viewOff")

    async def test_what_an_update_may_not_do(self):
        await self.h.rt.from_guide({"t": "viewOn", "view": self.rid})
        await asyncio.sleep(0.4)
        v = self.h.rt.views[self.rid]
        bad = [({"t": "update", "view": self.rid, "rows": [self.row("z", "a new row")]}, "a row it doesn't have"),
               ({"t": "update", "view": self.rid, "rows": [{"id": "a", "title": "A", "items": [{"id": "x%d" % i, "title": "x"} for i in range(50)]},
                                                           {"id": "b", "title": "B", "items": [{"id": "y%d" % i, "title": "y"} for i in range(50)]}]} , None),
               ({"t": "update", "view": self.rid, "items": [{"id": "a", "title": "A"}]}, "items for a screen"),
               ({"t": "update", "view": self.rid, "rows": [{"id": "a", "title": "A", "items": [{"id": "x", "title": "x" * 100}] * 1}] * 1 + [{"id": "b", "title": "B" * 70000, "items": []}]}, "past 64 KB")]
        n = len(self.updates())
        for frame, why in bad:
            v["next"] = 0
            await self.send(frame)
            if why:
                self.assertEqual(len(self.updates()), n, why)
            else:
                n = len(self.updates())   # 100 items fit
        # the merged screen within the caps: 200 items
        v["next"] = 0
        many = [{"id": "a", "title": "A", "items": [{"id": "x%d" % i, "title": "x"} for i in range(50)]}]
        await self.send({"t": "update", "view": self.rid, "rows": many})
        self.assertEqual(sum(len(r["items"]) for r in v["value"]["rows"]), 100)
        self.assertIn("its update was refused: it names a row the screen doesn't have", (self.h.rt.commit() or self.h.log()))

    async def test_pictures_stay_in_proportion(self):
        """a row replaced again and again with fresh pictures, well past the
        helper's token cap: held tokens stay those on the screen"""
        await self.h.rt.from_guide({"t": "viewOn", "view": self.rid})
        await asyncio.sleep(0.4)
        v = self.h.rt.views[self.rid]
        for i in range(apprun.MAX_TOKENS + 300):
            v["next"] = 0
            self.h.rt.on_update({"t": "update", "view": self.rid, "rows": [self.row("a", "n%d" % i, "https://img.example.com/p%d.jpg" % i)]})
        held = set(t for t, x in self.h.rt.tokens.items() if x["results"])
        self.assertEqual(held, apprun.Runtime.tokens_in(v["value"]), "the pictures on the screen now, no more")
        self.assertEqual(len(held), 1, "(row a's: the live handler gave row b a line without one)")
        self.assertLessEqual(len(self.h.rt.tokens), apprun.MAX_TOKENS, "and what's kept at all within the cap")
        await self.h.rt.from_guide({"t": "drop", "results": [self.rid]})
        self.assertNotIn(self.rid, self.h.rt.views, "let go: the view ends with its result")
        self.assertEqual([t for t, x in self.h.rt.tokens.items() if x["results"]], [])

    async def test_a_home_row(self):
        r = await self.h.call("homeRow", {"key": "now"})
        self.assertEqual(r["kind"], "rows")
        hid = self.h.n
        await self.h.rt.from_guide({"t": "viewOn", "view": hid})
        await asyncio.sleep(0.2)
        await self.send({"t": "update", "view": hid, "items": [{"id": "h2", "title": "Home two"}]})
        ups = [u for u in self.updates() if u["view"] == hid]
        self.assertEqual([u["items"][0]["title"] for u in ups], ["Home two"])
        self.h.rt.views[hid]["next"] -= 1.5
        await self.send({"t": "update", "view": hid, "items": [{"id": "h3", "title": "Home three"}]})
        self.assertEqual(len([u for u in self.updates() if u["view"] == hid]), 1, "a Home row: every 5 seconds at most")

    async def test_a_stream(self):
        await self.h.rt.from_guide({"t": "viewOn", "view": self.rid})
        await asyncio.sleep(0.3)
        seen = []
        real = self.h.rt.to_app
        self.h.rt.to_app = lambda f: (seen.append(f) if f.get("t") in ("streamData", "streamEnd") else None, real(f))[1]
        await self.send({"t": "stream", "id": 901, "view": self.rid, "url": "https://stream.example.com/live"})
        await asyncio.sleep(0.3)
        self.assertEqual([f["line"] for f in seen if f["t"] == "streamData"], ["data: one", "data: two"])
        await self.send({"t": "stream", "id": 902, "view": self.rid, "url": "https://stream.example.com/live"})
        self.assertEqual(seen[-1], {"t": "streamEnd", "id": 902, "error": {"code": "stream", "text": "it has a stream open already"}})
        await self.h.rt.from_guide({"t": "viewOff", "view": self.rid})
        await asyncio.sleep(0.2)
        ends = [f for f in seen if f["t"] == "streamEnd" and f["id"] == 901]
        self.assertEqual(ends[0]["error"]["code"], "closed", "its view went: closed")
        await self.h.rt.from_guide({"t": "viewOn", "view": self.rid})
        await asyncio.sleep(0.2)
        await self.send({"t": "stream", "id": 903, "view": self.rid, "url": "https://stream.example.com/live"})
        self.assertIn("wait", seen[-1]["error"]["text"], "a new one waits after the last ended")
        self.h.rt.stream_wait = 0
        await self.send({"t": "stream", "id": 904, "view": self.rid, "url": "https://api.example.com/x"})
        await asyncio.sleep(0.2)
        self.assertEqual(seen[-1]["error"]["code"], "stream", "a reply that isn't lines: refused")
        self.h.rt.stream_wait = 0
        self.stream_chunks[:] = [b"x" * (apprun.STREAM_LINE + 1)]
        await self.send({"t": "stream", "id": 905, "view": self.rid, "url": "https://stream.example.com/live"})
        await asyncio.sleep(0.2)
        self.assertIn("16 KB", seen[-1]["error"]["text"])
        self.h.rt.stream_wait = 0
        self.stream_chunks[:] = [b"".join(b"l%d\n" % i for i in range(40))]
        await self.send({"t": "stream", "id": 906, "view": self.rid, "url": "https://stream.example.com/live"})
        await asyncio.sleep(0.2)
        self.assertIn("20 lines a second", seen[-1]["error"]["text"])
        self.h.rt.stream_wait = 0
        await self.send({"t": "stream", "id": 907, "view": self.rid, "url": "https://tracker.example/x"})
        await asyncio.sleep(0.2)
        self.assertEqual(seen[-1]["error"]["code"], "origin", "only to one of its net hosts")
        self.h.rt.stream_wait = 0
        await self.send({"t": "stream", "id": 908, "view": 4242, "url": "https://stream.example.com/live"})
        self.assertIn("isn't on the screen", seen[-1]["error"]["text"])

    async def test_dropped_while_on_ends_its_handler(self):
        """the guide lets go of a live view that's on (its drop before its
        viewOff): the app hears viewOff all the same, once, and its handler
        ends; time after time, nothing piles up"""
        for i in range(3):
            if i:
                await self.h.call("home")
                self.rid = self.h.n
            await self.h.rt.from_guide({"t": "viewOn", "view": self.rid})
            await asyncio.sleep(0.3)
            await self.h.rt.from_guide({"t": "drop", "results": [self.rid]})
            await self.h.rt.from_guide({"t": "viewOff", "view": self.rid})   # late: changes nothing
            await asyncio.sleep(0.4)
            self.h.rt.commit()
            self.assertEqual(self.h.log().count("the live view went"), i + 1, "its handler ended, once")
            self.assertEqual(self.h.rt.views, {})

    async def test_an_update_that_cant_be_checked_is_refused(self):
        """whatever an update holds, the helper goes on reading the app"""
        await self.h.rt.from_guide({"t": "viewOn", "view": self.rid})
        await asyncio.sleep(0.4)
        v = self.h.rt.views[self.rid]
        n = len(self.updates())
        for bad in ("bad\udc00", "\ud800"):
            v["next"] = 0
            self.h.rt.on_update({"t": "update", "view": self.rid, "rows": [self.row("a", bad)]})   # (past the frame check)
        self.assertEqual(len(self.updates()), n)
        v["next"] = 0
        await self.send({"t": "update", "view": self.rid, "rows": [self.row("a", "fine")]})
        self.assertEqual(self.updates()[-1]["rows"][0]["items"][0]["title"], "fine", "and the next is read")
        self.assertEqual(self.h.rt.state, "ready")
        # and whatever the guide hands the app, it's written (text that isn't Unicode as escapes)
        self.h.rt.to_app({"t": "viewOff", "view": 99999, "method": "home", "args": {"x": "\udc00"}})
        await asyncio.sleep(0.2)
        self.assertEqual(self.h.rt.state, "ready")

    def test_the_frames_are_checked(self):
        for bad in ({"t": "update", "view": 1}, {"t": "update", "view": 1, "rows": [], "items": []}, {"t": "update", "view": "x", "rows": []},
                    {"t": "stream", "id": 1, "view": 1, "url": ""}, {"t": "fetch", "id": 1, "parent": 1, "view": 2, "url": "u", "method": "GET"}):
            with self.assertRaises(blocks.Violation, msg=json.dumps(bad)):
                blocks.check_frame(bad)
        self.assertEqual(blocks.check_frame({"t": "fetch", "id": 1, "view": 2, "url": "u", "method": "GET"}), "fetch")
        for bad in ("a\udc00", "\ud800b"):
            with self.assertRaises(blocks.Invalid):
                blocks.plain(bad, 10, "a title")
        self.assertEqual(blocks.plain("\U0001f600", 10, "a title"), "\U0001f600")


class ScoresMissingKeys(unittest.IsolatedAsyncioTestCase):
    """The bundled scores app, with ESPN sending a game without what a card
    needs: that game is left out, the rest shown, and its live view goes on
    updating (it used to end at the first such game)"""

    async def asyncSetUp(self):
        board = json.load(open(os.path.join(ROOT, "tests", "fixtures", "espn-nfl-scoreboard.json")))
        live = next(e for e in board["events"] if e["competitions"][0]["status"]["type"]["state"] == "in")
        no_team = json.loads(json.dumps(live))
        no_team["id"] = "bad-1"
        del no_team["competitions"][0]["competitors"][0]["team"]
        no_home = json.loads(json.dumps(live))
        no_home["id"] = "bad-2"
        for c in no_home["competitions"][0]["competitors"]:
            c["homeAway"] = "away"
        board["events"] = [no_team, no_home] + board["events"]
        self.good = len(board["events"]) - 2
        data = json.dumps(board).encode()
        self.real = net.exchange

        async def exchange(url, method, headers, body, gate, kind, pin="", resolver=None):
            gate.allow(url)
            return FakeRes(url, method, 200, None, data)
        net.exchange = exchange
        self.h = Harness(os.path.join(ROOT, "apps", "first-party", "tv.uber.scores"))
        await self.h.start()

    async def asyncTearDown(self):
        await self.h.stop()
        net.exchange = self.real

    async def test_a_bad_game_is_left_out(self):
        r = await self.h.call("home")
        self.assertEqual(r["kind"], "screen", r)
        ids = [it["id"] for row in r["value"]["rows"] for it in row["items"]]
        self.assertEqual(len(ids), self.good)
        self.assertFalse({"bad-1", "bad-2"} & set(ids))
        await self.h.rt.from_guide({"t": "viewOn", "view": self.h.n})
        end = time.monotonic() + 25   # its first turn comes after 15 seconds
        while time.monotonic() < end and not [f for f in self.h.frames if f.get("t") == "update"]:
            await asyncio.sleep(0.2)
        ups = [f for f in self.h.frames if f.get("t") == "update"]
        self.assertTrue(ups, "the live view updated")
        self.assertEqual(sum(len(row["items"]) for row in ups[0]["rows"]), self.good)


class StreamRedirects(unittest.IsolatedAsyncioTestCase):
    async def test_a_stream_never_reaches_the_server(self):
        """a stream goes to its net hosts at every hop: a net host sending it
        on to the server (here a LAN address over http) is refused before
        that hop is reached; a redirect between its net hosts is fine"""
        hops = []
        real = net.exchange

        async def exchange(url, method, headers, body, gate, kind, pin="", resolver=None):
            gate.allow(url)
            hops.append((str(url), kind))
            if url.host == "stream.example.com" and url.path == "/start":
                return FakeRes(url, method, 302, "http://192.168.1.8/jf/events")
            if url.host == "stream.example.com" and url.path == "/hop":
                return FakeRes(url, method, 302, "https://stream.example.com/live")
            if url.host == "stream.example.com":
                return StreamRes(url, [b"data: ok\n", "wait"])
            return FakeRes(url, method, 200, None, b'{"ok":true}')
        net.exchange = exchange
        perms = {"net": ["api.example.com", "img.example.com", "stream.example.com"], "server": {"label": "S"}}
        h = Harness(make_app("stream_srv", LIVE_APP, perms=perms, api=4), server="http://192.168.1.8/jf")
        try:
            await h.start()
            await h.call("home")
            rid = h.n
            await h.rt.from_guide({"t": "viewOn", "view": rid})
            await asyncio.sleep(0.3)
            seen = []
            to_app = h.rt.to_app
            h.rt.to_app = lambda f: (seen.append(f) if f.get("t") in ("streamData", "streamEnd") else None, to_app(f))[1]

            async def stream(sid, url):
                h.rt.stream_wait = 0
                r = await h.call("action", {"item": json.dumps({"t": "stream", "id": sid, "view": rid, "url": url}), "action": "send"})
                self.assertEqual(r["value"]["text"], "sent")
                await asyncio.sleep(0.3)
            await stream(901, "https://stream.example.com/start")
            self.assertEqual(seen[-1]["t"], "streamEnd")
            self.assertEqual(seen[-1]["error"]["code"], "origin")
            self.assertNotIn("192.168.1.8", json.dumps(hops), "the server never reached")
            await stream(902, "https://stream.example.com/hop")
            self.assertEqual([f["line"] for f in seen if f["t"] == "streamData"], ["data: ok"])
        finally:
            await h.stop()
            net.exchange = real


if __name__ == "__main__":
    try:
        unittest.main(verbosity=1)
    finally:
        shutil.rmtree(WORK, ignore_errors=True)
