# Start failures, a flow section (flow_report.py gives its globals): review agents that did not start,
# and whether a start followed. A failed start is a `review-agent` line of events.tsv whose outcome
# starts as review_start_failed's (build.sh) do and no_review_events (lifecycle.sh) matches them:
# `review-agent: review-<slug> did not start...`, `review-agent: review-<slug>'s start was unclear...` or
# `review-agent: review-<slug> took its brief...` (it stopped on an expired login).
# It is restarted when an ok `review-agent` line of the same slug comes after it in the log within
# RESTART_SECONDS. TSV day failed restarted_10m not_restarted, per local day of the failed starts in
# the window; then, after a blank line, TSV slug failed_at (the line's UTC time) for each one not
# restarted. A line in place of both with no failed start in the window. --epic does not narrow it.
import datetime, os, sys
from events_outcome import outcome

RESTART_SECONDS = 10 * 60

def when(t):
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00"))
    except ValueError:
        return None

def failed(slug, text):
    return any(text.startswith(f"review-agent: review-{slug}{m}") for m in (" did not start", "'s start was unclear", " took its brief"))

starts = []   # (slug, time, raw time, ok) per review-agent line, in log order
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) != 5 or f[1] != "review-agent" or (t := when(f[0])) is None:
        continue
    o = outcome(f)
    if o.startswith("ok"):
        starts.append((f[2], t, f[0], True))
    elif failed(f[2], o):
        starts.append((f[2], t, f[0], False))

days, missed = {}, []
for i, (slug, t, raw, ok) in enumerate(starts):
    day = t.astimezone().date().isoformat()
    if ok or not since <= day <= until:
        continue
    back = any(s == slug and o and 0 <= (u - t).total_seconds() <= RESTART_SECONDS for s, u, _, o in starts[i + 1:])
    n = days.setdefault(day, [0, 0])
    n[0] += 1
    n[1] += back
    if not back:
        missed.append(f"{slug}\t{raw}")
if not days:
    print("no failed review-agent start in the window")
    sys.exit()   # ends this section alone (flow_report.py)
print("day\tfailed\trestarted_10m\tnot_restarted")
for day, (n, back) in sorted(days.items()):
    print(f"{day}\t{n}\t{back}\t{n - back}")
if missed:
    print("", "slug\tfailed_at", *missed, sep="\n")
