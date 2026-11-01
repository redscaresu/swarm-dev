# Short-lived copies of gh reads, so wait-pr runs on one head (a builder's, its review agent's, the
# lead's) share each poll's reads. A read is cached only when the call sets SWARM_POLL_CACHE (the
# directory, <project>/.swarm/poll-cache) and SWARM_POLL_CACHE_SECONDS (the oldest entry it takes, in
# whole seconds; 0 or unset is off). wait-pr sets both on its ci_gate call alone, to under one poll, so
# a lone waiter never reads its own entry; every other gh read goes to GitHub.
#
# One JSON file per command form (gh's argv and the output filter, if any), named by its sha256, holding
# that form, the time it was written and gh's output. A reader takes it only when the form matches its
# own exactly and it is younger than the reader's max age. An entry is written only after the caller
# accepted the output (through's accept returned), by a temp file renamed over the old one (macOS has
# no flock), so no reader sees half of one. Writing one deletes any file in the directory older than
# PRUNE_SECONDS.
#
# Two readers that miss together make one read: the first to create <key>.lock (holding its pid) reads,
# and the others wait for its entry. A waiter reads for itself when the lock goes with no entry written
# (the read failed or was not accepted), when the pid in it has exited (killed before it wrote), or
# once it has waited its max age.
#
# A reader that took an entry writes its age, the oldest it took, in whole seconds, to the file
# SWARM_POLL_CACHE_AGE names, if any: wait-pr pauses that much less before its next poll, so a wait that
# reads another's entries polls in step with it and sees a change within one poll of it.
import hashlib, json, os, tempfile, time

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

def through(argv, filt, fetch, accept):
    """accept(gh's output for argv and its output filter filt): fetch() reads it from gh. With the cache
    on, a fresh entry for the same form stands in for fetch(), and fetch()'s output is kept once accept
    returned. Whatever fetch or accept raises reaches the caller, and nothing is kept then."""
    on = settings()
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
