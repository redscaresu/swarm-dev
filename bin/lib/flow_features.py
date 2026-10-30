# Features, a flow section (flow_report.py gives its globals): each feature's uses from --since (by
# default the 30 days up to --until, or up to today) to --until, its metric and baseline, and delete?
# when unused or unmeasured (that verdict reads the last 30 days, whatever the window).
import datetime, os, re, subprocess, sys
from events_outcome import outcome
from report import *
recent = (datetime.date.today() - datetime.timedelta(days=30)).isoformat()
if since == "0000-00-00":
    end = datetime.date.today() if until == "9999-12-30" else datetime.date.fromisoformat(until)
    since = (end - datetime.timedelta(days=30)).isoformat()

def rows(path):
    return [l.rstrip("\n").split("\t") for l in open(path, errors="ignore")] if os.path.exists(path) else []

# (source, name, day) for every use the logs hold.
def local_day(t):
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).astimezone().date().isoformat()
    except ValueError:
        return None

uses = [("event", f[1], local_day(f[0])) for f in rows(events) if len(f) == 5 and outcome(f).startswith("ok") and local_day(f[0])]
uses += [(k, f[i], f[0]) for f in rows(agents) if len(f) == 7 for k, i in (("role", 1), ("agent", 2))]
uses += [("reviewer", f[5], f[0]) for f in finding_rows(findings)]

def count(sources, after, upto="9999-12-30"):
    n = 0
    for s in sources.split():
        kind, _, want = s.partition(":")
        n += sum(1 for k, name, day in uses if k == kind and after <= day <= upto
                 and (name == want or kind == "event" and name.startswith(want + ":")))
    return n

root = os.path.dirname(os.path.dirname(os.path.abspath(features)))   # the features file's repo
def git(*args):
    got = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)
    return got.stdout if got.returncode == 0 else ""

# The oldest commit day of each #N in a subject's last `(#N)`.
merged = {}
for line in git("log", "--format=%cs %s", "HEAD").splitlines():
    m = re.fullmatch(r"(\S+) .*\(#(\d+)\)", line)
    if m:
        merged["#" + m.group(2)] = m.group(1)
try:
    board_dir = re.search(r"^\s*board_dir\s*=\s*(\S+)", open(os.path.join(root, ".claude/swarm/config")).read(), re.M).group(1)
except (OSError, AttributeError):
    board_dir = "docs"

def landed_day(landed):
    # The day a date or #PR landed, or None when it cannot be read.
    try:
        return datetime.date.fromisoformat(merged.get(landed, landed)).isoformat()
    except ValueError:
        return None

def settled(feature, landed):
    # Whether its uses can judge it: landed 30 days ago or more, or an epic that has left the board.
    day = landed_day(landed)
    if not day and re.fullmatch(r"[a-z][a-z0-9_-]*", landed):
        epic = os.path.join(board_dir, "epics", landed + ".md")
        if os.path.exists(os.path.join(root, epic)):
            return False
        day = git("log", "-1", "--diff-filter=D", "--format=%cs", "HEAD", "--", epic).strip()
        return day < recent if day else True
    if day:
        return day < recent
    print(f"swarm.sh flow: features: {feature}: landed {landed!r} is not a date, a #PR git log knows, or an epic; judged by its uses",
          file=sys.stderr)
    return True

print("feature\tuses\tmetric\tbaseline\tverdict" if os.path.exists(features) else f"no feature list at {features}")
for f in rows(features)[1:]:
    feature, landed, metric, baseline, sources = (f + [""] * 5)[:5]
    if not feature:
        continue
    unlogged = sources.startswith("unlogged:")
    stale = settled(feature, landed) and not unlogged and count(sources, recent) == 0
    print("\t".join([feature, "-" if unlogged else str(count(sources, since, until)), metric, baseline,
                     "delete?" if not metric.strip() or stale else ""]))
