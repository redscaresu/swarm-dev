import datetime, re, time
def story_for(name, stories):
    base = re.sub(r"-done\d*$", "", name)
    hits = [s for s in stories if s[1] == base]
    hits.sort(key=lambda s: s[2] == "done")
    return hits[0][0] if hits else None
def epoch(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        try:
            return datetime.datetime.fromisoformat(str(x).replace("Z", "+00:00")).timestamp()
        except ValueError:
            return None
def sign_time(f):
    t = epoch(f[0]) if len(f) == 5 else None
    if t is None or f[1] in ("nudge", "incident", "usage-limit", "tell:nudge", "tell:note") or f[1].split(":")[0] == "board-pr" or (f[1].split(":")[0] == "tell" and f[4] != "ok"):
        return None
    return t
def last_seen(events):
    seen = {}
    try:
        for l in open(events, encoding="utf-8", errors="replace"):
            f = l.rstrip("\n").split("\t")
            t = sign_time(f)
            if t is not None and t > seen.get(f[2], 0):
                seen[f[2]] = t
    except OSError:
        pass
    return seen
def stall_age(seen, slug, name, signs, now=None):
    ts = [t for t in [seen.get(slug), seen.get(name)] + [epoch(x) for x in signs if x] if t is not None]
    return max(int(((now or time.time()) - max(ts)) // 60), 0) if ts else None
