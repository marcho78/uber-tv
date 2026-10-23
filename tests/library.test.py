#!/usr/bin/python3
"""Library.qml never saves over a library.json or history.json it couldn't
read (a hand edit gone wrong, a broken file): it says so, and keeps that file
as it is; files it read are saved as before. Library.qml itself, in a
Quickshell of its own (qs -p) with a pretend guide, in a scratch folder:
/usr/bin/python3 tests/library.test.py"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GOOD_LIBRARY = json.dumps({"version": 1, "items": [{"title": "Kept", "url": "https://example.com/k.mp4"}], "myList": []}) + "\n"
GOOD_HISTORY = json.dumps({"vfeedbeef": {"position": 5, "duration": 100, "updated": 1, "title": "Seen"}}) + "\n"
BROKEN = '{"version": 1, "items": [{"title": "Mine", "url": '   # cut off
failures = 0


def run(want, library, history):
    """Library.qml over these files; what it said, and the files after"""
    global failures
    work = tempfile.mkdtemp(prefix="om-pg-library-test-")
    try:
        for name, text in (("library.json", library), ("history.json", history)):
            with open(os.path.join(work, name), "w") as f:
                f.write(text)
        env = dict(os.environ, QT_QPA_PLATFORM=os.environ.get("QT_QPA_PLATFORM", "offscreen"), T=work, OM_PG_ROOT=ROOT, WANT=want, XDG_CONFIG_HOME=os.path.join(work, "xdgc"),
                   XDG_CACHE_HOME=os.path.join(work, "xdgcache"), XDG_STATE_HOME=os.path.join(work, "state"))
        try:
            out = subprocess.run(["qs", "-p", os.path.join(ROOT, "tests/qml/library.shell.qml")], env=env,
                                 capture_output=True, text=True, timeout=60).stdout
        except subprocess.TimeoutExpired as e:
            out = (e.stdout or b"").decode(errors="replace") + "\nH FAIL the shell didn't finish in 60 seconds\n"
        lines = [l[l.index("H "):] for l in out.splitlines() if any(k in l for k in ("H PASS", "H FAIL", "H ERR", "H DONE"))]
        for l in lines:
            if l.startswith("H PASS"):
                print("ok   " + l[7:])
            elif l.startswith("H FAIL"):
                print("FAIL " + l[7:])
            elif not l.startswith("H DONE"):
                print("FAIL " + l)
        if not any(l.startswith("H DONE") for l in lines) or any(l.startswith(("H FAIL", "H ERR")) for l in lines):
            failures += 1
            if not lines:
                print(out[-2000:])
        after = {}
        for name in ("library.json", "history.json"):
            with open(os.path.join(work, name)) as f:
                after[name] = f.read()
        return after
    finally:
        shutil.rmtree(work, ignore_errors=True)


def check(name, cond, detail=""):
    global failures
    if not cond:
        failures += 1
    print(("ok   " if cond else "FAIL ") + name + ("" if cond or detail == "" else "  " + str(detail)[:300]))


after = run("none", GOOD_LIBRARY, GOOD_HISTORY)
check("files it read are saved: what was played", "v0123abcd" in json.loads(after["history.json"]), after["history.json"])
check("files it read are saved: the library", "Played" in after["library.json"], after["library.json"])

for want, library, history in (("library", BROKEN, GOOD_HISTORY), ("history", GOOD_LIBRARY, BROKEN),
                               ("both", BROKEN, BROKEN), ("library", "[1, 2]", GOOD_HISTORY), ("history", GOOD_LIBRARY, "null")):
    after = run(want, library, history)
    if want in ("library", "both"):
        check("an unreadable library.json is kept as it was (%r)" % library[:20], after["library.json"] == library, after["library.json"])
    else:
        check("a readable library.json is still saved", "Played" in after["library.json"], after["library.json"])
    if want in ("history", "both"):
        check("an unreadable history.json is kept as it was (%r)" % history[:20], after["history.json"] == history, after["history.json"])
    else:
        check("a readable history.json is still saved", "v0123abcd" in after["history.json"], after["history.json"])

print("\n" + ("library: all good" if not failures else str(failures) + " failed"))
sys.exit(1 if failures else 0)
