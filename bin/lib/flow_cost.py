# Cost, a flow section (flow_report.py gives its globals): tokens and estimated cost per role, in the window.
# The split-critic agent (/plan-epic's check on a large epic's split) is a critic with a row of its own.
import datetime, os
from report import *
log, agents, named = agents, [], set()
if os.path.exists(log):
    for line in open(log):
        f = line.rstrip("\n").split("\t")
        if len(f) == 7:
            named.add(f[6])
            if since <= f[0] <= until:
                agents.append({"role": "split-critic" if f[1:3] == ["critic", "split-critic"] else f[1], "kind": f[3], "session": f[6]})

def started(path):
    # The first timestamp's local day, as since and agents.tsv's dates are, or "".
    for line in log_lines(path) if path else ():
        try:
            ts = json.loads(line).get("timestamp")
            return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().date().isoformat()
        except (ValueError, AttributeError, TypeError):
            continue
    return ""

def in_window(path):
    # A lead session counts by its first timestamp's local day; one with none (or no log) only without --since.
    day = started(path)
    return since <= day <= until if day else since == "0000-00-00"

if lead and lead not in named and in_window(session_log(projects, lead, archive)):   # a conductor's own pane is already its agents.tsv row
    agents.append({"role": "lead", "kind": "claude", "session": lead})
    named.add(lead)

# The lead's own sessions: Claude Code keeps them under the project's path, all but letters and digits turned into -.
for path in sorted(glob.glob(os.path.join(glob.escape(own), "*.jsonl"))):
    session = os.path.basename(path)[:-len(".jsonl")]
    if session not in named and in_window(path):
        agents.append({"role": "lead", "kind": "claude", "session": session, "path": path})
rows, seen = {}, set()
for a in agents:
    r = rows.setdefault(a["role"], {"agents": 0, "models": set(), "tok": [0, 0, 0, 0], "usd": 0.0, "unpriced": 0})
    r["agents"] += 1
    path = a.get("path") or session_log(projects, a["session"], archive)
    if a["kind"] != "claude" or not path:
        r["unpriced"] += 1
        continue
    tok, usd, models = session_usage(path, seen)
    r["models"] |= models
    r["tok"] = [x + y for x, y in zip(r["tok"], tok)]
    r["usd"] += usd
def n(x):
    return f"{x/1e6:.1f}M" if x >= 1e6 else f"{x/1e3:.0f}k"
print("| role | agents | model | input | cache write | cache read | output | est. $ |")
print("|---|---|---|---|---|---|---|---|")
tot = [0, 0, 0, 0]; usd = 0.0
for role, r in sorted(rows.items(), key=lambda kv: -kv[1]["usd"]):
    tot = [x + y for x, y in zip(tot, r["tok"])]; usd += r["usd"]
    note = f" ({r['unpriced']} not in the logs)" if r["unpriced"] else ""
    print(f"| {role} | {r['agents']}{note} | {', '.join(sorted(r['models'])) or '-'} | " + " | ".join(n(x) for x in r["tok"]) + f" | {r['usd']:.2f} |")
print(f"| **total** | {sum(r['agents'] for r in rows.values())} | | " + " | ".join(n(x) for x in tot) + f" | {usd:.2f} |")
print("\nList prices; on a subscription this is plan usage, not a bill. Codex agents are not priced.")
if epic:
    print(f"Every agent in the window, not only epic {epic}'s.")
