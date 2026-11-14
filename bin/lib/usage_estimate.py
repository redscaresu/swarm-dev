# usage_estimate.py — an estimate of this week's Claude usage, from Claude Code's session logs: the
# price-weighted tokens (report.py's PRICES) since the weekly reset, Fable's apart from the rest, as a
# share of the week's limit and of Fable's own. It is an estimate, never a gate; /usage is the truth.
#
#   usage_estimate.py <projects> [--reading <file>] [--now <ISO time>]
#     prints the estimate as JSON: week and fable (percent), week_start, calibrated (the reading's time,
#     or null) and weight (percent of the week per estimated USD, for fable and for every other model).
#   usage_estimate.py <projects> --warn <percent> --state <dir> [--every <seconds>] [--reading <file>]
#     prints one `usage:` line, naming the week's start, when either share has reached <percent>, and nothing
#     once <dir>/usage-warned holds that week, whose logs it then never reads. wait --lead writes the week
#     there once it has printed the line (lifecycle.sh's usage_warned), so a line it never printed is not spent. <dir>/usage-at holds the
#     time of the last read, and with --every no read comes sooner than that many seconds after it.
#
# <projects> is Claude Code's projects directory. Of each line of each *.jsonl under it, only
# message.usage, message.model, message.id (so a turn logged on several lines counts once) and the
# line's timestamp are read; a line that names no usage is not parsed at all. Never the conversation.
#
# The reading is one line, `<read at> <resets at> <week %> <fable %>`, copied from /usage: ISO times
# (no offset is local time), the time it was read and the next weekly reset, then the two percentages.
# With it, a reading of this week is the base the spend since it adds to. Fable's limit is fitted from its own share, and Fable's weight in the week from that and
# FABLE_WEEK_SHARE; the other models' weight is fitted to the rest of the week's share. Without one the
# week starts Monday 00:00 UTC, and every model counts at its price alone against a guessed limit,
# which counts Fable low: on 2026-10-25 a single weighting read 90.6% while /usage showed 95%.
import datetime, glob, json, os, sys, time
from report import PRICES

WEEK = 7 * 86400
FABLE = "fable"
# Uncalibrated, the estimated USD the week's limit and Fable's own limit hold: a guess a reading replaces.
WEEK_USD = 2000.0
FABLE_USD = 800.0
# The share of the week's limit that all of Fable's own limit takes. On 2026-10-25 a night on Fable
# (#480) moved Fable's own limit 15 points (20% to 35%) and the week about 6 (HLD 2026-10-25-swarm-dev-0-28).
FABLE_WEEK_SHARE = 6 / 15

def epoch(s):
    d = datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
    return (d if d.tzinfo else d.astimezone()).timestamp()

def iso(t):
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).isoformat(timespec="minutes")

def read_reading(path):
    # (read at, resets at, week %, fable %) from the file's first line that is not blank or a comment,
    # or None, with a warning on stderr when that line is not one.
    try:
        lines = [(n, l.split("#")[0].split()) for n, l in enumerate(open(path, encoding="utf-8"), 1)]
    except OSError:
        return None
    for n, f in lines:
        if not f:
            continue
        try:
            r = (epoch(f[0]), epoch(f[1]), float(f[2]), float(f[3]))
            if len(f) == 4 and all(0 <= p <= 100 for p in r[2:]):
                return r
        except (ValueError, IndexError):
            pass
        print(f"swarm: warning: {path}:{n}: expected '<read at> <resets at> <week %> <fable %>', so the usage estimate is uncalibrated", file=sys.stderr)
        return None
    return None

def week_start(now, resets):
    # The start of the usage week holding now: the weeks run on from a reset, or from Monday 00:00 UTC.
    if resets is None:
        resets = 4 * 86400   # 1970-01-05, a Monday
    return resets + WEEK * ((now - resets) // WEEK)

def turns(projects, since):
    # (time, is Fable, est. USD) of each turn logged at or after since, each message id once.
    seen = set()
    for path in glob.glob(os.path.join(glob.escape(projects), "**", "*.jsonl"), recursive=True):
        try:
            if os.path.getmtime(path) < since:
                continue
            f = open(path, encoding="utf-8", errors="ignore")
        except OSError:
            continue
        with f:
            for line in f:
                if '"usage"' not in line:
                    continue
                try:
                    d = json.loads(line)
                    m = d.get("message") or {}
                    u, mid, model, t = m.get("usage"), m.get("id"), m.get("model"), epoch(d.get("timestamp"))
                    tok = [u.get(k, 0) for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")]
                    price = next((v for k, v in PRICES.items() if k in model), None)
                except (ValueError, AttributeError, TypeError):
                    continue
                if t < since or not mid or mid in seen or not price or not all(isinstance(x, (int, float)) for x in tok):
                    continue
                seen.add(mid)
                yield t, FABLE in model, sum(x * p for x, p in zip(tok, price)) / 1e6

def spend(rows, start, end):
    # (other models' USD, Fable's USD) of the turns in [start, end).
    other = sum(c for t, fable, c in rows if start <= t < end and not fable)
    return other, sum(c for t, fable, c in rows if start <= t < end and fable)

def estimate(projects, reading, now):
    start = week_start(now, reading[1] if reading else None)
    since = min(start, week_start(reading[0], reading[1])) if reading else start
    rows = list(turns(projects, since))
    other, fable = spend(rows, start, now + 1)
    w_other = w_fable = 100 / WEEK_USD
    k_fable, at = 100 / FABLE_USD, None
    if reading:
        o, f = spend(rows, week_start(reading[0], reading[1]), reading[0])
        if f > 0 and reading[3] > 0:   # a 0% reading fits no weight: it keeps the guess
            k_fable = reading[3] / f
        w_fable = FABLE_WEEK_SHARE * k_fable
        if o > 0 and reading[2] > w_fable * f:
            w_other = (reading[2] - w_fable * f) / o
        at = iso(reading[0])
    week, fable_share = w_other * other + w_fable * fable, k_fable * fable
    if reading and week_start(reading[0], reading[1]) == start and reading[0] <= now:
        # A reading of this week is the base, and only the spend since it is weighted: with fitted weights
        # that is the same figure, and with no logs from before the reading the reading still counts.
        week = reading[2] + w_other * (other - o) + w_fable * (fable - f)
        fable_share = reading[3] + k_fable * (fable - f)
    return {"week": round(week, 1), "fable": round(fable_share, 1),
            "week_start": iso(start), "calibrated": at, "weight": {"fable": round(w_fable, 4), "other": round(w_other, 4)}}

def warn(projects, reading, now, percent, state, every):
    key = datetime.datetime.fromtimestamp(week_start(now, reading[1] if reading else None), datetime.timezone.utc).date().isoformat()
    warned, stamp = os.path.join(state, "usage-warned"), os.path.join(state, "usage-at")
    try:
        if open(warned).read().strip() == key:
            return
    except OSError:
        pass
    try:
        if now - float(open(stamp).read()) < every:
            return
    except (OSError, ValueError):
        pass
    os.makedirs(state, exist_ok=True)
    with open(stamp, "w") as f:
        f.write(f"{now:.0f}\n")
    e = estimate(projects, reading, now)
    if max(e["week"], e["fable"]) < percent:
        return
    how = f"calibrated {e['calibrated']}" if e["calibrated"] else "uncalibrated, so it counts Fable low"
    # The week's start in the line, so two weeks' lines never read as one in wait --lead's seen queue.
    print(f"usage: estimate {e['week']:.0f}% of the week from {key} and {e['fable']:.0f}% of Fable's own limit, at or past usage_warn_percent {percent:g} "
          f"({how}; /usage is the truth), exit: check /usage, as nothing stops on this")

def main(argv):
    projects, opts = argv[0], dict(zip(argv[1::2], argv[2::2]))
    reading = read_reading(opts["--reading"]) if "--reading" in opts else None
    now = epoch(opts["--now"]) if "--now" in opts else time.time()
    if "--warn" in opts:
        warn(projects, reading, now, float(opts["--warn"]), opts["--state"], float(opts.get("--every", 0)))
    else:
        print(json.dumps(estimate(projects, reading, now)))

if __name__ == "__main__":
    main(sys.argv[1:])
