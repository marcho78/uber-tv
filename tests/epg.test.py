#!/usr/bin/python3
"""Program listings (bin/om-pg-epg): /usr/bin/python3 tests/epg.test.py

Listings read plain, gzipped and xz'd (streams one after another too, with
padding between them), and matched to your channels; a show with no such
time is skipped, not the whole file. The limits: an .xz
file can't make its decoder reserve more than MAX_XZ_MEMORY (a 68-byte file
asks for 1.5 GB), a file can't unpack past MAX_UNPACKED, one entry can't
pass MAX_ENTRY (a show of half a million parts, a title of megabytes),
memory stays flat however many shows a file has (each is let go of once
read), and the run stops when its time is up, a download sending a few bytes
at a time included. Out of time, the shows from last time stay, the sources
not reached say so, and the time it ran is written, so the next try is the
usual one; last time's file, too big to read back, stays exactly as it was."""

import gzip
import http.server
import importlib.machinery
import importlib.util
import io
import json
import lzma
import os
import sys
import tempfile
import threading
import time
import tracemalloc
from contextlib import redirect_stdout

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELPER = os.path.join(ROOT, "bin", "om-pg-epg")
_loader = importlib.machinery.SourceFileLoader("om_pg_epg", HELPER)
_spec = importlib.util.spec_from_loader("om_pg_epg", _loader)
epg = importlib.util.module_from_spec(_spec)
_loader.exec_module(epg)

failures = 0


def check(name, cond, detail=""):
    global failures
    if not cond:
        failures += 1
    print(("ok   " if cond else "FAIL ") + name + ("" if cond or detail == "" else "  " + str(detail)[:300]))


def raises(fn, kind, words=""):
    try:
        fn()
    except kind as e:
        return words.lower() in str(e).lower()
    except Exception as e:
        return False
    return False


home = tempfile.mkdtemp(prefix="om-pg-epg-test-")
CHANNELS = [{"url": "http://iptv.example/cnn", "tvgId": "cnn.us", "name": "CNN"}]
START = epg.xmltv_time("20261018000000 +0000")
END = epg.xmltv_time("20261019000000 +0000")
LISTING = (b'<?xml version="1.0"?><tv>'
           b'<channel id="cnn.us"><display-name>CNN</display-name></channel>'
           b'<programme start="20261018120000 +0000" stop="20261018130000 +0000" channel="cnn.us"><title>News at noon</title></programme>'
           b'<programme start="20261018130000 +0000" stop="20261018140000 +0000" channel="cnn.us"><title>The afternoon</title></programme>'
           b'</tv>')


def write(name, data):
    path = os.path.join(home, name)
    with open(path, "wb") as f:
        f.write(data)
    return path


def titles(path):
    seen, matched, shows = epg.read(path, epg.Matcher(CHANNELS), START, END, set())
    return seen, [s[2] for s in shows.get("http://iptv.example/cnn", [])]


def reset():
    epg.deadline = float("inf")
    epg.MAX_UNPACKED = 4 * 1024 * 1024 * 1024
    epg.MAX_XZ_MEMORY = 128 * 1024 * 1024


# ---- reading ----
reset()
check("plain listings are read and matched", titles(write("plain.xml", LISTING)) == (1, ["News at noon", "The afternoon"]))
check("gzipped listings too", titles(write("g.xml.gz", gzip.compress(LISTING))) == (1, ["News at noon", "The afternoon"]))
check("xz'd listings too", titles(write("x.xml.xz", lzma.compress(LISTING))) == (1, ["News at noon", "The afternoon"]))
half = len(LISTING) // 2
two = lzma.compress(LISTING[:half]) + lzma.compress(LISTING[half:])
check("xz streams one after another are read in turn", titles(write("two.xml.xz", two)) == (1, ["News at noon", "The afternoon"]))
check("zero padding between xz streams is skipped, and the next stream read",
      titles(write("pad.xml.xz", lzma.compress(LISTING[:half]) + b"\0" * 4 + lzma.compress(LISTING[half:]))) == (1, ["News at noon", "The afternoon"]))
check("what follows the last xz stream isn't an error", titles(write("tail.xml.xz", lzma.compress(LISTING) + b"\0\0\0\0junk")) == (1, ["News at noon", "The afternoon"]))
bad_times = LISTING.replace(b"</tv>", b"".join(
    b'<programme start="%s +0000" stop="20261018150000 +0000" channel="cnn.us"><title>Bad %d</title></programme>' % (t, n)
    for n, t in enumerate([b"20261318140000", b"20261018240000", b"20261032140000", b"00001018140000"])) + b"</tv>")
try:
    got = titles(write("badtime.xml", bad_times))
except ValueError as e:
    got = e
check("a show with no such time (month 13, hour 24, day 32, year 0) is skipped, the rest of the file read",
      got == (1, ["News at noon", "The afternoon"]), got)
check("an xz file cut short is an error", raises(lambda: titles(write("cut.xml.xz", lzma.compress(LISTING)[:-20])), (EOFError, lzma.LZMAError)))

# ---- the .xz decoder's memory ----
greedy = lzma.compress(b"<tv></tv>", format=lzma.FORMAT_XZ,
                       filters=[{"id": lzma.FILTER_LZMA2, "dict_size": 1536 * 1024 * 1024}])
check("a %d-byte xz file asking for 1.5 GB is refused before it's unpacked" % len(greedy),
      raises(lambda: titles(write("greedy.xml.xz", greedy)), lzma.LZMAError, "memory"))
check("an ordinary xz file (xz -9's 64 MB) is fine",
      titles(write("x9.xml.xz", lzma.compress(LISTING, preset=9))) == (1, ["News at noon", "The afternoon"]))

# ---- what a file may unpack to ----
filler = b"<tv>" + (b"<x>" + b" " * 1000 + b"</x>") * 2100 + LISTING[LISTING.index(b"<channel"):]   # 2 MB in small entries
epg.MAX_UNPACKED = 1024 * 1024
check("gzip past the unpacked limit stops", raises(lambda: titles(write("big.xml.gz", gzip.compress(filler))), OSError, "unpacked"))
check("xz past it too", raises(lambda: titles(write("big.xml.xz", lzma.compress(filler))), OSError, "unpacked"))
check("a plain file past it too", raises(lambda: titles(write("big.xml", filler)), OSError, "unpacked"))
reset()
check("the same file under the limit is read", titles(write("big2.xml.gz", gzip.compress(filler))) == (1, ["News at noon", "The afternoon"]))

# ---- one entry can't grow without bound before it ends ----
head = LISTING[:LISTING.index(b"<programme")]
parts = head + b'<programme channel="cnn.us" start="20261018120000 +0000" stop="20261018130000 +0000">' + b"<x/>" * 500000 + b"</programme></tv>"
tracemalloc.start()
stopped = raises(lambda: titles(write("parts.xml.gz", gzip.compress(parts))), OSError, "one entry")
peak = tracemalloc.get_traced_memory()[1]
tracemalloc.stop()
check("a show of half a million parts (a 2 MB entry) stops, in little memory (peak %.1f MB)" % (peak / 1e6), stopped and peak < 30e6, peak)
huge = head + b'<programme channel="cnn.us" start="20261018120000 +0000" stop="20261018130000 +0000"><title>' + b"a" * (3 * 1024 * 1024) + b"</title></programme></tv>"
nested = (head + b'<programme channel="cnn.us" start="20261018120000 +0000" stop="20261018130000 +0000">'
          + (b"<x/>" * 180000 + b"<programme/><channel/>") * 4 + b"</programme></tv>")
check("channels and shows inside an entry are parts of it, not entries: they don't reset its limit",
      raises(lambda: titles(write("nested.xml.gz", gzip.compress(nested))), OSError, "one entry"))
check("a 3 MB title stops", raises(lambda: titles(write("huge.xml.gz", gzip.compress(huge))), OSError, "one entry"))
check("a long but ordinary description is fine",
      titles(write("long.xml", head + b'<programme channel="cnn.us" start="20261018120000 +0000" stop="20261018130000 +0000"><title>Long</title><desc>'
                   + b"words " * 20000 + b"</desc></programme></tv>")) == (1, ["Long"]))

# ---- an episode's own title and number (Record every episode tells episodes apart by them) ----
def episodes(xml):
    _, _, shows = epg.read(write("ep.xml", head + xml + b"</tv>"), epg.Matcher(CHANNELS), START, END, set())
    return [s[5:] for s in shows.get("http://iptv.example/cnn", [])]


show = b'<programme channel="cnn.us" start="20261018120000 +0000" stop="20261018130000 +0000"><title>Bake Off</title>%s</programme>'
check("an episode's title and number kept: on screen as given",
      episodes(show % b'<sub-title>Bread Week</sub-title><episode-num system="onscreen">S02E05</episode-num>') == [["Bread Week", "S02E05"]])
check("XMLTV's zero-based season.episode.part as S3E6",
      episodes(show % b'<episode-num system="xmltv_ns">2.5.0/1</episode-num>') == [["", "S3E6"]])
check("XMLTV with a total and no season: E6", episodes(show % b'<episode-num system="xmltv_ns">.5/10.</episode-num>') == [["", "E6"]])
check("on screen preferred over XMLTV's numbering",
      episodes(show % b'<episode-num system="xmltv_ns">0.0.</episode-num><episode-num system="onscreen">Ep 1</episode-num>') == [["", "Ep 1"]])
check("another system's id, named", episodes(show % b'<episode-num system="dd_progid">EP0123.0045</episode-num>') == [["", "dd_progid:EP0123.0045"]])
check("none: empty", episodes(show % b"") == [["", ""]])
check("the episode's title still leads the description (as shown)",
      epg.read(write("ep.xml", head + show % b"<sub-title>Bread Week</sub-title><desc>Loaves.</desc>" + b"</tv>"), epg.Matcher(CHANNELS), START, END, set())[2]
      ["http://iptv.example/cnn"][0][3] == "Bread Week. Loaves.")

# ---- memory stays flat: each show is let go of once read ----
many = 200000
body = (b'<tv><channel id="cnn.us"><display-name>CNN</display-name></channel>'
        + b'<programme channel="other" start="20261018120000 +0000" stop="20261018130000 +0000"/>' * many + b"</tv>")
path = write("many.xml.gz", gzip.compress(body))
tracemalloc.start()
seen, _ = titles(path)
peak = tracemalloc.get_traced_memory()[1]
tracemalloc.stop()
check("%d shows read in flat memory (peak %.1f MB, under 8)" % (many, peak / 1e6), seen == 1 and peak < 8e6, peak)

# ---- the run's time ----
epg.deadline = time.monotonic() - 1
check("reading stops once the run's time is up", raises(lambda: titles(write("late.xml", LISTING)), epg.OutOfTime))
reset()


class Drip(http.server.BaseHTTPRequestHandler):
    """A download that sends 20 bytes every 50 ms, of 10 MB said"""

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", str(10 * 1024 * 1024))
        self.end_headers()
        try:
            for _ in range(200):
                self.wfile.write(b"<" * 20)
                self.wfile.flush()
                time.sleep(0.05)
        except OSError:
            pass

    def log_message(self, *args):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Drip)
server.daemon_threads = True
threading.Thread(target=server.serve_forever, daemon=True).start()
drip_folder = tempfile.mkdtemp(dir=home)
epg.deadline = time.monotonic() + 0.5
began = time.monotonic()
stopped = raises(lambda: epg.fetch("http://127.0.0.1:%d/listings.xml" % server.server_address[1], drip_folder), epg.OutOfTime)
took = time.monotonic() - began
reset()
server.shutdown()
check("a download sending a few bytes at a time stops at the run's time (%.2f s for 0.5)" % took, stopped and took < 1.0, took)
check("and leaves no download behind", os.listdir(drip_folder) == [])


def run(sources, old=None):
    """main() on a request, in a folder of its own: (its lines, epg.json)"""
    folder = tempfile.mkdtemp(dir=home)
    out = os.path.join(folder, "epg.json")
    if old is not None:
        with open(out, "w") as f:
            json.dump(old, f)
    request = os.path.join(folder, "request.json")
    with open(request, "w") as f:
        json.dump({"sources": sources, "channels": CHANNELS, "from": START, "to": END, "out": out}, f)
    said = io.StringIO()
    argv = sys.argv
    sys.argv = ["om-pg-epg", request]
    try:
        with redirect_stdout(said):
            epg.main()
    finally:
        sys.argv = argv
    with open(out) as f:
        data = json.load(f)
    lines = [json.loads(x) for x in said.getvalue().splitlines() if x.strip()]
    return lines, data, out, folder


good = write("good.xml", LISTING)
lines, data, out, folder = run([good])
check("a run writes the shows", [s[2] for s in data["shows"].get("http://iptv.example/cnn", [])] == ["News at noon", "The afternoon"], data)
check("readable by you alone", oct(os.stat(out).st_mode & 0o777) == "0o600")
check("the request (it lists your channels) is gone", not os.path.exists(os.path.join(folder, "request.json")))

old = {"version": 1, "fetched": 1, "from": START - 100, "to": END + 100,
       "sources": [], "shows": {"http://iptv.example/kept": [[START, START + 60, "From last time", "", ""]]}}
saved = epg.RUN_SECONDS
epg.RUN_SECONDS = -1
try:
    lines, data, out, folder = run([good, write("second.xml", LISTING)], old)
finally:
    epg.RUN_SECONDS = saved
errors = [s["error"] for s in data["sources"]]
check("out of time: the source it was on says so, and the next wasn't read",
      errors == ["took too long", "not read: out of time"], errors)
check("out of time: the shows from last time stay", data["shows"].get("http://iptv.example/kept") == [[START, START + 60, "From last time", "", ""]], data["shows"])
check("out of time: when it ran is written, so the next try is the usual one", data["fetched"] > 1)
check("out of time: no download left behind", not [n for n in os.listdir(folder) if n.endswith(".download")])

big_old = dict(old, shows={"http://iptv.example/kept": [[START, START + 60, "x" * 2000, "", ""]]})
saved, saved_old = epg.RUN_SECONDS, epg.MAX_OLD
epg.RUN_SECONDS, epg.MAX_OLD = -1, 1024
try:
    folder = tempfile.mkdtemp(dir=home)
    out = os.path.join(folder, "epg.json")
    with open(out, "w") as f:
        json.dump(big_old, f)
    with open(out, "rb") as f:
        before = f.read()
    request = os.path.join(folder, "request.json")
    with open(request, "w") as f:
        json.dump({"sources": [good], "channels": CHANNELS, "from": START, "to": END, "out": out}, f)
    argv, sys.argv = sys.argv, ["om-pg-epg", request]
    try:
        with redirect_stdout(io.StringIO()):
            epg.main()
    finally:
        sys.argv = argv
    with open(out, "rb") as f:
        after = f.read()
finally:
    epg.RUN_SECONDS, epg.MAX_OLD = saved, saved_old
check("out of time with last time's listings too big to read back: the file stays exactly as it was", before == after)

print("\n%d failed" % failures if failures else "\nall passed")
sys.exit(1 if failures else 0)
