# Tell refusals, a flow section (flow_report.py gives its globals): how often a tell is refused, by
# where it was going and the state it read. Over the tell and tell:<kind> lines of events.tsv whose
# local day is in the window, a refusal is one whose outcome (events_outcome) is neither ok nor a
# queued: or replaced: line, nor, on a tell or tell:findings line, one holding `herdr sent it the
# brief`, which findings_told (agents.sh) counts as delivered. Its pane is agent when agent_name of the
# line's target (the slug as typed) has an agents.tsv line (any day), else other; its state is the
# line's state= field (tell_agent and tell_gone write it), or - with none: a sent, queued or replaced
# tell, a refusal before the state was read, or a line older than the field. TSV pane state tells
# refused, where tells counts lines (a queued tell has its queued: line and its delivery's), per pane
# kind its all row, then a row per state in name order; then, after a blank line, TSV target
# could_not_reach, the refusals whose outcome starts `could not reach` per target, most first. A line
# in place of a block with nothing to count. --epic does not narrow it.
import datetime, os, sys
from events_outcome import fields, outcome
from report import agent_name

def day(t):
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).astimezone().date().isoformat()
    except ValueError:
        return None

def refused(cmd, o):
    if cmd in ("tell", "tell:findings") and "herdr sent it the brief" in o:
        return False   # delivered, as findings_told counts it
    return not (o == "ok" or o.startswith(("queued:", "replaced:")))   # a sent tell logs ok alone

names = set()
for line in open(agents, errors="ignore") if os.path.exists(agents) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) > 2:
        names.add(f[2])

counts, unreached = {}, {}   # (pane, state) -> [tells, refused]; target -> could-not-reach refusals
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) != 5 or not (f[1] == "tell" or f[1].startswith("tell:")) or not since <= (day(f[0]) or "") <= until:
        continue
    o, pane = outcome(f), "agent" if agent_name(f[2]) in names else "other"
    no = refused(f[1], o)
    for state in ("all", fields(f).get("state", "-")):
        n = counts.setdefault((pane, state), [0, 0])
        n[0] += 1
        n[1] += no
    if no and o.startswith("could not reach"):
        unreached[f[2]] = unreached.get(f[2], 0) + 1
if not counts:
    print("no tell in the window")
    sys.exit()   # ends this section alone (flow_report.py)
print("pane\tstate\ttells\trefused")
for (pane, state), (n, no) in sorted(counts.items(), key=lambda kv: (kv[0][0], kv[0][1] != "all", kv[0][1])):
    print(f"{pane}\t{state}\t{n}\t{no}")
print()
if not unreached:
    print("no could not reach refusal in the window")
    sys.exit()
print("target\tcould_not_reach")
for target, n in sorted(unreached.items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"{target}\t{n}")
