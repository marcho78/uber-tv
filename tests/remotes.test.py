#!/usr/bin/python3
"""The phone remote's templates on disk (bin/om-pg-apps remote-list,
remote-save, remote-remove), in scratch folders:
/usr/bin/python3 tests/remotes.test.py

A folder of their own (~/.config/om-pg/remotes), only Uber TV writing there,
one change at a time under a lock file. It checks a save's steps in order
with a failure injected at each (anything up to and including the rename or
the link changes nothing and leaves nothing behind; only the last folder sync
failing is unconfirmed), that a copy takes the first free id and never
replaces a file already there, built-in ids refused, the 50 and 64 KB caps,
links and folders at a template's name, the folder itself a link, the list
reading only plain files, and removal."""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELPER = os.path.join(ROOT, "bin", "om-pg-apps")
_loader = importlib.machinery.SourceFileLoader("om_pg_apps", HELPER)
_spec = importlib.util.spec_from_loader("om_pg_apps", _loader)
apps = importlib.util.module_from_spec(_spec)
_loader.exec_module(apps)

failures = 0


def check(name, cond, detail=""):
    global failures
    if not cond:
        failures += 1
    print(("ok   " if cond else "FAIL ") + name + ("" if cond or detail == "" else "  " + str(detail)[:300]))


work = tempfile.mkdtemp(prefix="om-pg-remotes-test-")
builtin = os.path.join(work, "plugin-remotes")
os.makedirs(builtin)
for b in ("classic", "minimal"):
    with open(os.path.join(builtin, b + ".json"), "w") as f:
        json.dump({"id": b, "name": b.title()}, f)
apps.BUILTIN_REMOTES = builtin
folder = os.path.join(work, "remotes")


def req(**k):
    return json.dumps(dict({"dir": folder}, **k)).encode()


def save(rid, template, mode="replace"):
    return apps.do_remote_save(req(id=rid, template=template, mode=mode))


def raises(fn, *a):
    try:
        fn(*a)
        return False
    except apps.Bad:
        return True


def names():
    return sorted(os.listdir(folder)) if os.path.isdir(folder) else []


def templates():
    return sorted(n for n in names() if n.endswith(".json"))


def leftovers():
    return [n for n in names() if apps.REMOTE_TEMP.match(n)]


def content(rid):
    return json.load(open(os.path.join(folder, rid + ".json")))


class StepFS:
    """os, each step of a save named and recorded, and one made to fail"""
    def __init__(self, fail=None, error=None):
        self.fail, self.error, self.calls, self.dirs = fail, error, [], set()

    def step(self, name):
        self.calls.append(name)
        if self.fail == name:
            raise (self.error or OSError("injected: " + name))

    def makedirs(self, *a, **k):
        return os.makedirs(*a, **k)

    def open(self, path, flags, mode=0o777, *, dir_fd=None):
        base = os.path.basename(path)
        if flags & os.O_DIRECTORY:
            fd = os.open(path, flags, mode)
            self.dirs.add(fd)
            return fd
        if base == apps.REMOTE_LOCK:
            self.step("lock")
        elif flags & os.O_CREAT:
            self.step("create")
        elif apps.REMOTE_TEMP.match(base):
            self.step("readback")
        return os.open(path, flags, mode, dir_fd=dir_fd)

    def fsync(self, fd):
        self.step("dirsync" if fd in self.dirs else "sync")
        return os.fsync(fd)

    def replace(self, a, b, *, src_dir_fd=None, dst_dir_fd=None):
        self.step("rename")
        return os.replace(a, b, src_dir_fd=src_dir_fd, dst_dir_fd=dst_dir_fd)

    def link(self, a, b, *, src_dir_fd=None, dst_dir_fd=None, follow_symlinks=True):
        self.step("link")
        return os.link(a, b, src_dir_fd=src_dir_fd, dst_dir_fd=dst_dir_fd, follow_symlinks=follow_symlinks)

    def unlink(self, path, *, dir_fd=None):
        self.step("unlink")
        return os.unlink(path, dir_fd=dir_fd)


def with_fs(fs, fn, *a):
    apps._fs = fs
    try:
        return fn(*a)
    finally:
        apps._fs = os


# ---- a new template, saved --------------------------------------------------------
fs = StepFS()
res = with_fs(fs, save, "mine", {"name": "Mine", "layout": {"portrait": []}})
check("a new template: saved under its id", res == {"ok": True, "outcome": "saved", "id": "mine"}, res)
check("the steps in order: the lock, the temp file created and synced, read back, renamed, the folder synced",
      fs.calls == ["lock", "create", "sync", "readback", "rename", "dirsync"], fs.calls)
check("written whole, its id inside the one it's saved under", content("mine") == {"name": "Mine", "layout": {"portrait": []}, "id": "mine"})
check("readable by you alone, in a folder of its own",
      (os.stat(os.path.join(folder, "mine.json")).st_mode & 0o777, os.stat(folder).st_mode & 0o777) == (0o600, 0o700))
check("nothing else left beside it but the lock file", names() == [".lock", "mine.json"], names())
res = save("mine", {"name": "Mine 2", "id": "something-else"})
check("the same id again replaces it (its id field put right)", res["outcome"] == "saved" and content("mine") == {"name": "Mine 2", "id": "mine"}, content("mine"))

# ---- ids, built-ins, requests ------------------------------------------------------
for bad, why in [("Bad", "capitals"), ("-x", "a leading hyphen"), ("a" * 33, "33 characters"), ("a/b", "a slash"), ("", "empty"),
                 ("../x", "../"), (5, "a number"), (None, "none")]:
    check("refused id: " + why, raises(apps.do_remote_save, req(id=bad, template={"name": "x"})))
check("a built-in's id refused (replace)", raises(save, "classic", {"name": "Mine"}) and "classic.json" not in names())
check("refused: a template that isn't an object", raises(apps.do_remote_save, req(id="x", template=["no"])))
check("refused: an unknown mode", raises(apps.do_remote_save, req(id="x", template={}, mode="merge")))
check("refused: a folder not given by its full path", raises(apps.do_remote_save, json.dumps({"dir": "remotes", "id": "x", "template": {}}).encode()))
check("refused: not JSON", raises(apps.do_remote_save, b"{nope"))
check("refused: nested past what's readable", raises(apps.do_remote_save, b"[" * 100000))
res = apps.do_remote_save(b'{"dir": "' + folder.encode() + b'", "id": "nan", "template": {"x": NaN}}')
check("a template that isn't plain JSON (NaN): failed, nothing left", res["outcome"] == "failed" and "nan.json" not in names() and not leftovers(), res)
apps.BUILTIN_REMOTES = os.path.join(work, "no-such-folder")
check("the built-ins can't be read: nothing is saved", raises(save, "other", {"name": "x"}) and "other.json" not in names())
check("nor removed", raises(apps.do_remote_remove, req(id="mine")) and "mine.json" in names())
apps.BUILTIN_REMOTES = builtin

# ---- copies: the first free id, never replacing ---------------------------------------
res = save("classic", {"name": "Classic (yours)"}, "copy")
check("a copy of a built-in: never its id, the next free", res["id"] == "classic-2" and content("classic-2")["id"] == "classic-2", res)
res = save("mine", {"name": "Mine copy"}, "copy")
check("a copy where the id's taken: -2", res["id"] == "mine-2" and content("mine") == {"name": "Mine 2", "id": "mine"}, res)
res = save("mine", {"name": "Mine copy"}, "copy")
check("and again: -3, the others untouched", res["id"] == "mine-3" and content("mine-2")["name"] == "Mine copy", res)
with open(os.path.join(folder, "x-2.json"), "w") as f:
    f.write('{"id": "x-2", "name": "already there"}')
save("x", {"name": "X"})
res = save("x", {"name": "X copy"}, "copy")
check("a file already at -2 is never replaced: -3", res["id"] == "x-3" and content("x-2")["name"] == "already there", res)
os.symlink(os.path.join(work, "nowhere.json"), os.path.join(folder, "y.json"))
res = save("y", {"name": "Y"}, "copy")
check("a dangling link at the id: skipped, not written through", res["id"] == "y-2" and not os.path.exists(os.path.join(work, "nowhere.json")), res)
long = "a" * 32
save(long, {"name": "Long"})
res = save(long, {"name": "Long copy"}, "copy")
check("a copy of a 32-character id stays 32 characters", res["id"] == "a" * 30 + "-2" and len(res["id"]) == 32, res)
check("copies leave no temporary files", not leftovers(), leftovers())

# ---- what's at a template's name -------------------------------------------------------
outside = os.path.join(work, "outside.json")
with open(outside, "w") as f:
    f.write('{"name": "not yours to write"}')
os.symlink(outside, os.path.join(folder, "linked.json"))
res = save("linked", {"name": "Through the link"})
check("a link at its name: refused, the link's target untouched, nothing left",
      res["outcome"] == "failed" and open(outside).read() == '{"name": "not yours to write"}' and os.path.islink(os.path.join(folder, "linked.json"))
      and not leftovers(), res)
os.mkdir(os.path.join(folder, "afolder.json"))
res = save("afolder", {"name": "x"})
check("a folder at its name: refused", res["outcome"] == "failed" and os.path.isdir(os.path.join(folder, "afolder.json")) and not leftovers(), res)
os.rmdir(os.path.join(folder, "afolder.json"))
os.unlink(os.path.join(folder, "linked.json"))
os.unlink(os.path.join(folder, "y.json"))

linkdir = os.path.join(work, "linked-remotes")
os.symlink(folder, linkdir)
res = apps.do_remote_save(json.dumps({"dir": linkdir, "id": "via", "template": {}}).encode())
check("the folder itself a link: refused", res["outcome"] == "failed" and "via.json" not in names(), res)
check("listing through a linked folder: refused", apps.do_remote_list(json.dumps({"dir": linkdir}).encode())["ok"] is False)

# ---- 64 KB -----------------------------------------------------------------------------
res = save("big", {"name": "Big", "pad": "x" * (64 * 1024)})
check("bigger than 64 KB: failed, nothing written", res["outcome"] == "failed" and "64 KB" in res["why"] and "big.json" not in names() and not leftovers(), res)
res = save("fits", {"name": "Fits", "pad": "x" * (60 * 1024)})
check("just under: saved", res["outcome"] == "saved", res)

# ---- a failure at each step: nothing changed, nothing left ------------------------------
before = {n: open(os.path.join(folder, n), "rb").read() for n in templates()}
for step in ("lock", "create", "sync", "readback", "rename"):
    fs = StepFS(step)
    res = with_fs(fs, save, "mine", {"name": "Never"})
    after = {n: open(os.path.join(folder, n), "rb").read() for n in templates()}
    check("replace, failing at " + step + ": failed, the old file as it was, nothing left",
          res["outcome"] == "failed" and after == before and not leftovers(), (res, fs.calls))
for step in ("create", "sync", "readback", "link"):
    fs = StepFS(step)
    res = with_fs(fs, save, "mine", {"name": "Never"}, "copy")
    after = {n: open(os.path.join(folder, n), "rb").read() for n in templates()}
    check("copy, failing at " + step + ": failed, nothing new, nothing left",
          res["outcome"] == "failed" and after == before and not leftovers(), (res, fs.calls))
fs = StepFS("dirsync")
res = with_fs(fs, save, "mine", {"name": "Unconfirmed"})
check("only the last folder sync failing: unconfirmed, in place", res["outcome"] == "unconfirmed" and res["id"] == "mine" and content("mine")["name"] == "Unconfirmed", res)
fs = StepFS("dirsync")
res = with_fs(fs, save, "mine", {"name": "Copy unconfirmed"}, "copy")
check("a copy, the last sync failing: unconfirmed, with the id it took", res["outcome"] == "unconfirmed" and res["id"] == "mine-4", res)
fs = StepFS("unlink")
res = with_fs(fs, save, "late", {"name": "Late"}, "copy")
check("a copy whose temporary file won't go: still saved (it's in)", res["outcome"] == "saved" and res["id"] == "late", res)
check("and the next save takes the leftover away", leftovers() != [] and save("late", {"name": "Late 2"})["outcome"] == "saved" and not leftovers(), leftovers())
stale = os.path.join(folder, ".remote-0123456789abcdef.json.tmp")
os.symlink(outside, stale)
save("late", {"name": "Late 3"})
check("a link named like a temporary file: not followed, its target untouched",
      os.path.islink(stale) and open(outside).read() == '{"name": "not yours to write"}')
os.unlink(stale)

# ---- at most 50 --------------------------------------------------------------------------
for n in range(len(templates()), 50):
    save("fill-%02d" % n, {"name": "Fill"})
check("50 templates there", len(templates()) == 50, len(templates()))
res = save("one-more", {"name": "51"})
check("a 51st: refused, nothing written", res["outcome"] == "failed" and "50" in res["why"] and "one-more.json" not in names(), res)
res = save("mine", {"name": "Still replaceable"}, "copy")
check("a 51st as a copy: refused", res["outcome"] == "failed" and len(templates()) == 50, res)
res = save("mine", {"name": "Still replaceable"})
check("replacing one of the 50: fine", res["outcome"] == "saved", res)

# ---- the list -----------------------------------------------------------------------------
lst = apps.do_remote_list(req())
check("the first 50 by name, each with its text", lst["ok"] and len(lst["templates"]) == 50 and lst["skipped"] == 0
      and [t["id"] for t in lst["templates"]] == [n[:-5] for n in templates()]
      and json.loads(next(t["text"] for t in lst["templates"] if t["id"] == "mine"))["name"] == "Still replaceable", lst.get("skipped"))
listed = os.path.join(work, "listed")
os.makedirs(listed)
for i in range(52):
    with open(os.path.join(listed, "t-%02d.json" % i), "w") as f:
        json.dump({"name": str(i)}, f)
os.symlink(outside, os.path.join(listed, "a-link.json"))
with open(os.path.join(listed, "a-big.json"), "w") as f:
    f.write('{"pad": "' + "x" * (64 * 1024) + '"}')
with open(os.path.join(listed, "a-text.json"), "w") as f:
    f.write("not json")
with open(os.path.join(listed, "a-list.json"), "w") as f:
    f.write("[1, 2]")
os.mkdir(os.path.join(listed, "a-folder.json"))
os.mkfifo(os.path.join(listed, "a-pipe.json"))
for other in ("README", ".lock", ".remote-0123456789abcdef.json.tmp", "Bad.json"):
    with open(os.path.join(listed, other), "w") as f:
        f.write("{}")
lst = apps.do_remote_list(json.dumps({"dir": listed}).encode())
ids = [t["id"] for t in lst["templates"]]
check("only plain files, at most 50: links, oversize, non-JSON, lists, folders and pipes skipped and counted",
      lst["ok"] and ids == ["t-%02d" % i for i in range(50)] and lst["skipped"] == 8, (ids[:3], lst["skipped"]))
check("a missing folder: an empty list", apps.do_remote_list(json.dumps({"dir": os.path.join(work, "none")}).encode()) == {"ok": True, "templates": [], "skipped": 0})

# ---- removal ---------------------------------------------------------------------------
res = apps.do_remote_remove(req(id="mine"))
check("one of yours removed", res == {"ok": True, "outcome": "saved"} and "mine.json" not in names(), res)
res = apps.do_remote_remove(req(id="mine"))
check("again: it isn't there", res["outcome"] == "failed" and res["why"] == "it isn't there", res)
check("a built-in can't be", raises(apps.do_remote_remove, req(id="classic")))
os.symlink(outside, os.path.join(folder, "lnk.json"))
res = apps.do_remote_remove(req(id="lnk"))
check("a link at its name: not removed, its target untouched", res["outcome"] == "failed" and os.path.islink(os.path.join(folder, "lnk.json"))
      and os.path.exists(outside), res)
fs = StepFS("dirsync")
res = with_fs(fs, apps.do_remote_remove, req(id="mine-2"))
check("its folder sync failing: unconfirmed (it's gone)", res["outcome"] == "unconfirmed" and "mine-2.json" not in names(), res)
check("refused id on removal", raises(apps.do_remote_remove, req(id="../mine-3")))

# ---- through the helper itself ------------------------------------------------------------
w = subprocess.run([sys.executable, HELPER, "remote-list"], input=json.dumps({"dir": listed}).encode(), capture_output=True)
out = json.loads(w.stdout.decode().strip().splitlines()[-1])
check("remote-list through the helper: the request on stdin", out["ok"] and len(out["templates"]) == 50, w.stderr[-200:])
w = subprocess.run([sys.executable, HELPER, "remote-save"], input=b"not json", capture_output=True)
out = json.loads(w.stdout.decode().strip().splitlines()[-1])
check("remote-save through the helper: a bad request said in one line", out == {"ok": False, "error": "not a request"} and w.returncode == 1, out)

print("\n" + ("remotes: all good" if not failures else str(failures) + " failed"))
sys.exit(1 if failures else 0)
