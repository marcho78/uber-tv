#!/usr/bin/python3
"""The helpers never write compiled Python (.pyc) into the plugin's folder:
Omarchy watches that folder, and a file written in it reloads the guide,
closing it. Each helper that loads the guide's own modules (lib/) is run
from a copy of the plugin, with bytecode allowed as on a user's computer,
and loads them; nothing new may appear in the copy:
/usr/bin/python3 tests/bytecode.test.py"""

import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# the helper, and what makes it load every module it can (at the top of the
# file, or through its own loaders)
HELPERS = [("bin/om-pg-apprun", ""), ("bin/om-pg-streamer", ""),
           ("bin/om-pg-apps", "g['NET'](); g['SOURCES'](); g['APPFILES']()"),
           ("bin/om-pg-dvr", "g['relay_module'](); g['buffer_module']()")]
DRIVER = "import runpy, sys\ng = runpy.run_path(sys.argv[1], run_name='helper')\n%s\n"
failures = 0


def check(name, cond, detail=""):
    global failures
    if not cond:
        failures += 1
    print(("ok   " if cond else "FAIL ") + name + ("" if cond or detail == "" else "  " + str(detail)[:600]))


def files(top):
    return {os.path.relpath(os.path.join(d, n), top) for d, _, names in os.walk(top) for n in names}


work = tempfile.mkdtemp(prefix="om-pg-bytecode-test-")
try:
    plugin = os.path.join(work, "plugin")
    shutil.copytree(ROOT, plugin, ignore=shutil.ignore_patterns(".git", "__pycache__", "*.pyc", ".claude"))
    env = {k: v for k, v in os.environ.items() if k not in ("PYTHONDONTWRITEBYTECODE", "PYTHONPYCACHEPREFIX")}
    env["HOME"] = os.path.join(work, "home")
    os.mkdir(env["HOME"])
    for rel, calls in HELPERS:
        before = files(plugin)
        run = subprocess.run([sys.executable, "-c", DRIVER % calls, os.path.join(plugin, rel)], env=env,
                             cwd=work, capture_output=True, text=True, timeout=60)
        check(rel + " loads its modules", run.returncode == 0, run.stderr[-600:])
        new = sorted(files(plugin) - before)
        check(rel + " writes nothing in the plugin's folder", not new, new)
finally:
    shutil.rmtree(work, ignore_errors=True)

print("\n" + ("bytecode: all good" if not failures else str(failures) + " failed"))
sys.exit(1 if failures else 0)
