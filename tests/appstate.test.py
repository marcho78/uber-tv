#!/usr/bin/python3
"""Apps.qml itself, in a Quickshell of its own (qs -p) with a pretend guide,
against the real bin/om-pg-apps in a scratch home:
/usr/bin/python3 tests/appstate.test.py

It checks that save() is true only when what's on disk is what it wrote,
that an update withdraws what it takes away on disk before its package
goes in (and that a later version doesn't get it back after a restart),
that a launcher keeps the clean-ups it still owes from when it had code and
the guide's start does them, that an update from code to a launcher does
them at once, that a secret isn't written while a start that may still
clear its name is under way, that a bundled app updated from api 2 to 3
asking for nothing new installs quietly (and keeps api 3 through a
restart), and that a bundled app with code starts through AppRuntime with
the init its record gives it. Step 9 stands in some of the helper's answers
(a stand-in plugin whose helper answers what the test asks it to, and runs
the real one otherwise): an update that install says changed nothing gives
back what it withdrew, a removed source's apps can't be turned on, a quiet
update queued for one install never acts on another, a removal is only
for the install it was asked for, a source removed and added again
(through Sources.qml itself) has the apps kept from it checked again,
where a check older than its removal or return changes nothing of them,
and an install that fails after the guide changed something itself first
(withdrew what it couldn't give back, removed the one it takes the place
of) says what, never that nothing changed.
Your sources are read under their lock (lib/appsources.py listing). The
guide's own apps are left running (sweep off), and every folder is a
scratch one."""

import fcntl
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SD = "9866a2d1833b76c1"   # bin/om-pg-apps source_dir("file:0123456789abcdef")
work = tempfile.mkdtemp(prefix="om-pg-appstate-test-")

# Scores' app.json before API 4 (1.0.2 at api 2, 1.1.0 at api 3 with its
# rows), asking for what it asks for now
SCORES = {
    "id": "tv.uber.scores", "name": "Scores", "kind": "app", "author": "Uber TV",
    "description": "Live scores, today's games and finals for the NFL, NBA, MLB, NHL, the Premier League and MLS, from ESPN.",
    "color": "#d62828", "icon": "icon.png", "main": "main.py",
    "permissions": {"net": ["site.api.espn.com", "a.espncdn.com"]},
    "settings": [{"key": "league", "type": "choice", "label": "League",
                  "choices": ["NFL", "NBA", "MLB", "NHL", "Premier League", "MLS"]}],
    "home": [{"key": "now", "label": "Scores now"}],
}
SCORES_ROWS = [
    {"id": "in", "label": "Live now", "shape": "logo", "layout": "grid"},
    {"id": "pre", "label": "Coming up", "shape": "logo", "layout": "grid"},
    {"id": "post", "label": "Final", "shape": "logo", "layout": "grid"},
]

# The stand-in helper (step 9): <answers>/<command>.json, if it's there and
# not empty, is that command's next answer (taken once), given once
# <answers>/<command>.hold (or the file its "_hold" names, for an answer
# held on its own) is empty or gone (a minute at most); anything else goes
# to the real helper. Every call is noted in <answers>/calls, once its
# answer is taken (a test that sees the call can put the next answer).
STUB = '''import json, os, sys, time
ANSWERS, REAL = %r, %r
cmd = sys.argv[1] if len(sys.argv) > 1 else ""
mine = os.path.join(ANSWERS, "taken-%%d" %% os.getpid())
try:
    os.rename(os.path.join(ANSWERS, cmd + ".json"), mine)
except OSError:
    mine = ""
with open(os.path.join(ANSWERS, "calls"), "a") as f:
    f.write(json.dumps(sys.argv[1:]) + "\\n")
if mine:
    with open(mine) as f:
        text = f.read().strip()
    os.unlink(mine)
    if text:
        said = json.loads(text)
        hold = os.path.join(ANSWERS, said.pop("_hold", "") or cmd + ".hold")
        for _ in range(3000):
            try:
                with open(hold) as f:
                    if not f.read().strip():
                        break
            except OSError:
                break
            time.sleep(0.02)
        print(json.dumps(said))
        sys.exit(0 if said.get("ok") else 1)
os.execv("/usr/bin/python3", ["/usr/bin/python3", REAL] + sys.argv[1:])
'''


def put(rel, obj, mode=0o600):
    path = os.path.join(work, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f)
    os.chmod(path, mode)


try:
    # every place the guide and the helper keep things is in here (the guide's
    # config is $XDG_CONFIG_HOME/om-pg, as the helper finds it)
    for d in ("xdgc/om-pg", "xdgcache/om-pg", "state", "home", "data/om-pg/app-store/" + SD):
        os.makedirs(os.path.join(work, d), exist_ok=True)
    os.makedirs(os.path.join(work, "xdgc/om-pg/app-secrets", SD), mode=0o700)
    os.chmod(os.path.join(work, "xdgc/om-pg/app-secrets"), 0o700)
    put("xdgc/om-pg/apps.json", {"on": False, "installed": [{
        "id": "tv.example.launch", "version": "1.0.0", "kind": "launcher", "name": "L",
        "source": "file:0123456789abcdef", "sourceDir": SD,
        "permissions": {"web": ["example.com"]}, "launch": {"web": "https://example.com/"},
        "values": {"@forget": ["data", "bogus"], "@clear": ["apiKey", "signIn", "*"], "junk": 1, "@signedIn": True}}]})
    put("xdgc/om-pg/app-secrets/%s/tv.example.launch.json" % SD,
        {"user": {"apiKey": "k", "other": "o"}, "signIn": {"server": "https://s", "values": {"token": "t"}}})
    put("xdgc/om-pg/app-secrets/%s/tv.example.code.json" % SD,
        {"user": {}, "signIn": {"server": "https://s.example", "values": {"token": "t2"}}})
    put("data/om-pg/app-store/%s/tv.example.launch.json" % SD, {"v": 1, "keys": {}})
    # the plugin as it was before API 3: its Scores, 1.0.2, api 2; and as it
    # was at API 3, before Scores went live: 1.1.0. Their app.json as they
    # were (the history they came from isn't in every clone), beside the
    # plugin's own main.py and icon (what step 4b checks is their app.json)
    for plugin, version, api, layout in (("oldplugin", "1.0.2", 2, None), ("midplugin", "1.1.0", 3, SCORES_ROWS)):
        folder = os.path.join(work, plugin, "apps", "first-party", "tv.uber.scores")
        os.makedirs(folder)
        old = dict(SCORES, version=version, api=api)
        if layout:
            old["layout"] = {"rows": layout}
        with open(os.path.join(folder, "app.json"), "w") as f:
            json.dump(old, f)
        for name in ("main.py", "icon.png"):
            shutil.copy(os.path.join(ROOT, "apps", "first-party", "tv.uber.scores", name), os.path.join(folder, name))
        # (its helper is the plugin's own: it finds its modules where it really is)
        os.symlink(os.path.join(ROOT, "bin"), os.path.join(work, plugin, "bin"))
    # one of your sources (milestone 6), its list kept and signed, at an
    # address that never resolves (.invalid): an install fails to get its
    # package without anything leaving this computer
    import base64
    import hashlib
    keydir = os.path.join(work, "keys")
    os.makedirs(keydir)
    subprocess.run(["/usr/bin/ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", os.path.join(keydir, "k")], check=True)
    with open(os.path.join(keydir, "k.pub")) as f:
        line = " ".join(f.read().split()[:2])
    blob = base64.b64decode(line.split()[1])
    fp = "SHA256:" + base64.b64encode(hashlib.sha256(blob).digest()).decode().rstrip("=")
    sid = "source:" + hashlib.sha256(blob).hexdigest()[:16]
    base_url = "https://src.invalid/tv/"
    entry = {"id": "tv.alex.films", "version": "1.0.0", "kind": "launcher", "name": "Films", "author": "Alex", "description": "",
             "color": "", "permissions": {"web": ["films.example.com"]}, "package": base_url + "films.tar.gz", "sha256": "a" * 64, "size": 100}
    listed = json.dumps({"format": 1, "name": "Alex's TV apps", "updated": 1000, "apps": [dict(entry, package="films.tar.gz")]}).encode()
    with open(os.path.join(keydir, "list.json"), "wb") as f:
        f.write(listed)
    subprocess.run(["/usr/bin/ssh-keygen", "-q", "-Y", "sign", "-f", os.path.join(keydir, "k"), "-n", "uber-tv-source", os.path.join(keydir, "list.json")],
                   check=True, capture_output=True)
    with open(os.path.join(keydir, "list.json.sig"), "rb") as f:
        sig = f.read()
    h = hashlib.sha256(listed).hexdigest()
    sfolder = os.path.join(work, "state", "om-pg", "sources", hashlib.sha256(sid.encode()).hexdigest()[:16])
    os.makedirs(sfolder, mode=0o700)
    with open(os.path.join(sfolder, h + ".json"), "wb") as f:
        f.write(listed)
    with open(os.path.join(sfolder, h + ".sig"), "wb") as f:
        f.write(sig)
    shown = {"updated": 1000, "fetched": 1, "apps": [entry], "revoked": [], "skipped": 0, "listSha256": h, "keyGen": 0}
    put("state/om-pg/sources/%s/list.json" % os.path.basename(sfolder), shown)
    with open(os.path.join(work, "sfolder"), "w") as f:
        f.write(os.path.basename(sfolder))
    # an app got ready for a list the source has since replaced: what a
    # review's Install finds when the source changed after it was prepared
    stale = os.path.join(work, "xdgcache", "om-pg", "app-staging", "app-stale")
    os.makedirs(os.path.join(stale, "files"), mode=0o700)
    with open(os.path.join(stale, "snapshot.json"), "w") as f:
        json.dump({"source": sid, "life": "c" * 32, "keyGen": 0, "listSha256": "f" * 64, "updated": 1000,
                   "entry": {"id": "tv.alex.films", "version": "1.1.0", "kind": "launcher"}}, f)
    # and one taking the place of an app you have from a file, whose source
    # changed after the guide's last look (install itself refuses it)
    stale2 = os.path.join(work, "xdgcache", "om-pg", "app-staging", "app-stale2")
    os.makedirs(os.path.join(stale2, "files"), mode=0o700)
    with open(os.path.join(stale2, "snapshot.json"), "w") as f:
        json.dump({"source": sid, "life": "c" * 32, "keyGen": 0, "listSha256": "f" * 64, "updated": 1000,
                   "entry": {"id": "tv.example.old", "version": "2.0.0", "kind": "launcher"}}, f)
    put("data/om-pg/app-store/%s/tv.example.old.json" % SD, {"v": 1, "keys": {"mine": "kept"}})
    # and an update of an app you have from that source, got ready for a list
    # it has since replaced (step 9n: install itself refuses it), with the
    # secrets and sign-in the one you have keeps
    stale3 = os.path.join(work, "xdgcache", "om-pg", "app-staging", "app-stale3")
    os.makedirs(os.path.join(stale3, "files"), mode=0o700)
    with open(os.path.join(stale3, "snapshot.json"), "w") as f:
        json.dump({"source": sid, "life": "c" * 32, "keyGen": 0, "listSha256": "f" * 64, "updated": 1000,
                   "entry": {"id": "tv.alex.code", "version": "2.0.0", "kind": "app"}}, f)
    put("xdgc/om-pg/app-secrets/%s/tv.alex.code.json" % SD,
        {"user": {"apiKey": "k3"}, "signIn": {"server": "https://s.example", "values": {"token": "t3"}}})
    put("xdgc/om-pg/sources.json", {"v": 1, "sources": [{"id": sid, "url": base_url, "name": "Alex's TV apps", "key": line, "fingerprint": fp,
                                                         "keyGen": 0, "pastKeys": [], "added": 1, "seen": 1000, "seenSha": h, "rev": 0, "life": "c" * 32}]})
    # source-list reads your sources under their lock, so what it answers
    # is all from before a fetch's commit or all from after it: each list
    # is read while the lock is held (no one else can take it then)
    spec = importlib.util.spec_from_file_location("appsources", os.path.join(ROOT, "lib", "appsources.py"))
    S = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(S)
    store = os.path.join(work, "xdgc", "om-pg", "sources.json")
    held_then = []

    def probing(shown):
        def probe(state_root, s):
            fd = os.open(os.path.dirname(store), os.O_RDONLY | os.O_DIRECTORY)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                held_then.append(False)
            except BlockingIOError:
                held_then.append(True)
            finally:
                os.close(fd)
            return shown(state_root, s)
        return probe
    S.shown_list = probing(S.shown_list)
    listed = S.listing(store, os.path.join(work, "state", "om-pg", "sources"))
    pyfails = []
    said = "your sources are read under their lock: " + json.dumps([held_then, [x["list"]["listSha256"] == h for x in listed["sources"]]])
    if held_then != [True] or [x["list"]["listSha256"] for x in listed["sources"]] != [h]:
        pyfails.append(said)
    print(("FAIL " if pyfails else "PASS ") + said)
    # the stand-in plugin of step 9: the plugin's apps, and a helper that
    # answers what the test put in answers/ (the real one otherwise)
    stub = os.path.join(work, "stubplugin")
    os.makedirs(os.path.join(stub, "bin"))
    os.makedirs(os.path.join(work, "answers"))
    os.symlink(os.path.join(ROOT, "apps"), os.path.join(stub, "apps"))
    os.symlink(os.path.join(ROOT, "bin", "om-pg-apprun"), os.path.join(stub, "bin", "om-pg-apprun"))
    with open(os.path.join(stub, "bin", "om-pg-apps"), "w") as f:
        f.write(STUB % (os.path.join(work, "answers"), os.path.join(ROOT, "bin", "om-pg-apps")))
    env = dict(os.environ, T=work, OM_PG_ROOT=ROOT, OLD_PLUGIN=os.path.join(work, "oldplugin"), MID_PLUGIN=os.path.join(work, "midplugin"), XDG_DATA_HOME=os.path.join(work, "data"), XDG_STATE_HOME=os.path.join(work, "state"),
               XDG_CONFIG_HOME=os.path.join(work, "xdgc"), XDG_CACHE_HOME=os.path.join(work, "xdgcache"),
               SOURCE_ID=sid, SOURCE_FP=fp, STUB_PLUGIN=stub)
    try:
        out = subprocess.run(["qs", "-p", os.path.join(ROOT, "tests/qml/appstate.shell.qml")], env=env,
                             capture_output=True, text=True, timeout=120).stdout
    except subprocess.TimeoutExpired as e:
        # what it said before it stopped (captured output is bytes here)
        out = (e.stdout or b"").decode(errors="replace") + "\nH FAIL the shell didn't finish in 120 seconds\n"
    lines = [l[l.index("H "):] for l in out.splitlines() if any(k in l for k in ("H PASS", "H FAIL", "H ERR", "H SKIP", "H DONE"))]
    for l in lines:
        print(l[2:])
    failed = [l for l in lines if l.startswith("H FAIL") or l.startswith("H ERR")] + pyfails
    if failed or not any(l.startswith("H DONE") for l in lines):
        if not lines:
            print(out[-3000:])
        print("FAILED")
        sys.exit(1)
    print("all passed")
finally:
    subprocess.run(["chmod", "-R", "u+rwx", work])
    shutil.rmtree(work, ignore_errors=True)
