# Short-lived copies of gh reads, so concurrent polls share each poll's reads: wait-pr runs on one head (a
# builder's, its review agent's, the lead's), and watch runs on one repo (each conductor's, the lead's). A
# read is cached only when the call asks for it, in one of two forms:
# - ci_gate's pages() (through below), when the call sets SWARM_POLL_CACHE (the directory,
#   <project>/.swarm/poll-cache) and SWARM_POLL_CACHE_SECONDS (the oldest entry it takes, in whole
#   seconds; 0 or unset is off). wait-pr sets both on its ci_gate head call, and watch on queued_line's
#   ci_gate age call.
# - The command form, for bash: `poll_cache.py <dir> <max-age> -- <command...>` prints the command's
#   stdout, from an entry or from a run, and exits as the command did. Only a run that exits 0 is kept; a
#   failed one's stdout and then its stderr pass through, and the next reader runs it again. A max age of
#   0 runs the command uncached. watch reads its open-PR list and each head's check runs this way.
# Each caller's max age is under its own poll, so a lone poller never reads its own entry; every other gh
# read goes to GitHub.
#
# One JSON file per command form (gh's argv and the output filter, if any; the command form's whole
# argv, its -q filter included), named by its sha256, holding that form, the time it was written and the
# output. A reader takes it only when the form matches its own exactly and it is younger than the
# reader's max age, so two forms of one path (ci_gate's raw pages, watch's filtered line) never read
# each other's. An entry is written only after the caller accepted the output (through's accept
# returned), by a temp file renamed over the old one (macOS has no flock), so no reader sees half of one.
# Writing one deletes any file in the directory older than PRUNE_SECONDS.
#
# Two readers that miss together make one read: the first to create <key>.lock (holding its pid) reads,
# and the others wait for its entry. A waiter reads for itself when the lock goes with no entry written
# (the read failed or was not accepted), when the pid in it has exited (killed before it wrote), or
# once it has waited its max age.
#
# A reader that took an entry writes its age, the oldest it took, in whole seconds, to the file
# SWARM_POLL_CACHE_AGE names, if any: wait-pr pauses that much less before its next poll, so a wait that
# reads another's entries polls in step with it and sees a change within one poll of it.
import hashlib, json, os, subprocess, sys, tempfile, time

PRUNE_SECONDS = 600   # a file older than this is deleted when an entry is written
LOCK_PAUSE = 0.05     # seconds between looks at another reader's lock
oldest = None         # the age in whole seconds of the oldest entry this process took, once it took one

def settings():
    """(directory, max age) when the call caches, else None."""
    d, age = os.environ.get("SWARM_POLL_CACHE", ""), os.environ.get("SWARM_POLL_CACHE_SECONDS", "")
    return (d, int(age)) if d and age.isdigit() and int(age) > 0 else None

def entry(path, form, age):
    """gh's output kept at path for form, when written under age seconds ago; else None."""
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
    except (OSError, ValueError):
        return None
    if not (isinstance(d, dict) and d.get("form") == form and isinstance(d.get("out"), str)
            and isinstance(d.get("at"), (int, float)) and 0 <= time.time() - d["at"] < age):
        return None
    took(time.time() - d["at"])
    return d["out"]

def took(secs):
    """Notes an entry secs old taken in place of a read, in SWARM_POLL_CACHE_AGE's file, best effort."""
    global oldest
    oldest = max(oldest or 0, int(secs))
    f = os.environ.get("SWARM_POLL_CACHE_AGE")
    if f:
        try:
            with open(f, "w") as fh:
                fh.write("%d\n" % oldest)
        except OSError:
            pass

def put(path, form, out):
    """Keeps out for form at path, best effort: a failed write costs only a later read."""
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump({"form": form, "at": time.time(), "out": out}, f)
        os.replace(tmp, path)
        tmp = None
    except (OSError, TypeError, ValueError):
        pass
    finally:
        if tmp:
            remove(tmp)
    prune(os.path.dirname(path))

def prune(d):
    """Deletes the files in d older than PRUNE_SECONDS: entries no reader takes, locks and temp files left
    by a reader that was killed."""
    cut = time.time() - PRUNE_SECONDS
    try:
        names = os.listdir(d)
    except OSError:
        return
    for name in names:
        p = os.path.join(d, name)
        try:
            if os.stat(p).st_mtime < cut:
                os.remove(p)
        except OSError:
            pass

def remove(path):
    try:
        os.remove(path)
    except OSError:
        pass

def lock(path):
    """True when this process now holds path, False when another does, None when it cannot be made."""
    try:
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
    except FileExistsError:
        return False
    except OSError:
        return None
    try:
        with os.fdopen(fd, "w") as f:
            f.write(str(os.getpid()))
    except OSError:   # a full disk: no lock, so the read goes to gh uncached
        remove(path)
        return None
    return True

def owner(path):
    """The pid in the lock at path; None when it is gone, 0 while it is still being written."""
    try:
        with open(path) as f:
            return int(f.read().strip())
    except FileNotFoundError:
        return None
    except (OSError, ValueError):
        return 0

def release(path, pid):
    """Removes the lock at path while it still names pid, so a reader never removes a lock that another
    took after the one it looked at."""
    if owner(path) == pid:
        remove(path)

def holder(path):
    """The lock's state and pid: "gone", "dead" (its pid has exited) or "alive" (one still being written
    too)."""
    pid = owner(path)
    if pid is None:
        return "gone", None
    try:
        if pid:
            os.kill(pid, 0)
    except ProcessLookupError:
        return "dead", pid
    except OSError:
        pass
    return "alive", pid

def through(argv, filt, fetch, accept, on=None):
    """accept(gh's output for argv and its output filter filt): fetch() reads it from gh. With the cache
    on (on, (directory, max age) or False for off; settings() when None), a fresh entry for the same form
    stands in for fetch(), and fetch()'s output is kept once accept returned. Whatever fetch or accept
    raises reaches the caller, and nothing is kept then."""
    on = settings() if on is None else on
    if not on:
        return accept(fetch())
    d, age = on
    form = [list(argv), filt]
    key = hashlib.sha256(json.dumps(form).encode("utf-8")).hexdigest()
    path, lk = os.path.join(d, key + ".json"), os.path.join(d, key + ".lock")
    try:
        os.makedirs(d, exist_ok=True)
    except OSError:
        return accept(fetch())
    held, end = False, time.time() + age
    while True:
        out = entry(path, form, age)
        if out is not None:
            return accept(out)
        held = lock(lk)
        if held is not False or time.time() >= end:
            break
        state, pid = holder(lk)
        if state == "dead":
            # Killed before it wrote or let go: the next pass takes the lock (one waiter does).
            release(lk, pid)
        elif state == "alive":
            time.sleep(LOCK_PAUSE)
    try:
        if held:
            # Another reader may have written and let go between the look above and the lock.
            out = entry(path, form, age)
            if out is not None:
                return accept(out)
        out = fetch()
        got = accept(out)
        put(path, form, out)
        return got
    finally:
        if held:
            release(lk, os.getpid())

class Failed(Exception):
    """The command form's command failed: its exit code, stdout and stderr (bytes), passed on, never kept."""
    def __init__(self, rc, out, err):
        Exception.__init__(self, rc)
        self.rc, self.out, self.err = rc, out, err

def run(cmd):
    """The command's stdout, as text that round-trips any bytes; its stderr goes on to ours. Raises Failed
    when it exits non-zero, is killed (128 + the signal) or cannot start (127)."""
    try:
        p = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True)
    except OSError as e:
        raise Failed(127, b"", ("poll_cache: %s: %s\n" % (cmd[0], e.strerror or e)).encode())
    if p.returncode:
        raise Failed(p.returncode if p.returncode > 0 else 128 - p.returncode, p.stdout, p.stderr)
    sys.stderr.buffer.write(p.stderr)
    sys.stderr.flush()
    return p.stdout.decode("utf-8", "surrogateescape")

USAGE = "usage: poll_cache.py <dir> <max-age seconds> -- <command...>"

def command(args):
    """The command form: prints <command>'s stdout, from an entry under <dir> younger than <max-age> or
    from a run of it, and returns its exit code. A run that exits 0 is kept; a failed one prints its
    stdout, then its stderr (so the last line is the error, as when both went to one pipe), and keeps
    nothing. A max age of 0 is off."""
    if len(args) < 4 or args[2] != "--" or not args[0] or not args[1].isdigit():
        sys.stderr.write(USAGE + "\n")
        return 2
    d, age, cmd = args[0], int(args[1]), args[3:]
    try:
        out = through(cmd, "", lambda: run(cmd), lambda s: s, (d, age) if age > 0 else False)
    except Failed as e:
        sys.stdout.buffer.write(e.out)
        sys.stdout.flush()
        sys.stderr.buffer.write(e.err)
        return e.rc
    sys.stdout.buffer.write(out.encode("utf-8", "surrogateescape"))
    return 0

if __name__ == "__main__":
    sys.exit(command(sys.argv[1:]))
