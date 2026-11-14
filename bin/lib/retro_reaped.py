# retro's reaped section: what swarm-dev killed for running too long since the window's day, from the
# `reap` lines in events.tsv. One row per line whose time falls on or after that day, in local time
# (log order): `<local day>  <target>  <outcome>`, then its slug= and role= fields when it has them. Then
# `<n>  <target>` per target, most first. Two writers make reap lines: make test (scripts/test.sh, a
# test file's `TIMEOUT after <n>s`, to the events.tsv beside the run's test-runs.tsv) and codex-review
# (target codex-<x>, `timed out after <N> min`). A fallback reviewer killed on its timeout writes none,
# and the last line says so, so a short list is not read as no load. A missing file, or one with no
# reap line since the day, prints one line that says which. A line whose time does not parse is skipped.
# Run by retro_report.py, with day (YYYY-MM-DD) and events (the events.tsv path) among its globals.
import collections, csv, datetime, os
import events_outcome
from report import local_day, merge_time

since = datetime.date.fromisoformat(day)  # noqa: F821 # retro_report.py's context
path = events  # noqa: F821
rows = []
if os.path.isfile(path):
    with open(path, encoding="utf-8", errors="replace", newline="") as f:
        for row in csv.reader(f, delimiter="\t", quoting=csv.QUOTE_NONE):
            t = merge_time(row[0]) if len(row) > 4 and row[1] == "reap" else None
            if t and local_day(t) >= since:
                rows.append((local_day(t).isoformat(), row[2], row))
if not os.path.isfile(path):
    print(f"no reap lines: {path} does not exist")
elif not rows:
    print(f"no reap lines since {since} in {path}")
for d, target, row in rows:
    tail = events_outcome.fields(row)
    extra = " ".join(f"{k}={tail[k]}" for k in ("slug", "role") if k in tail)
    print(f"{d}  {target}  {events_outcome.outcome(row)}" + (f"  {extra}" if extra else ""))
if rows:
    print()
    counts = collections.Counter(target for _, target, _ in rows)
    for target, n in sorted(counts.items(), key=lambda c: (-c[1], c[0])):
        print(f"{n}  {target}")
print("a fallback reviewer killed on its timeout writes no reap line, so this list is not every kill")
