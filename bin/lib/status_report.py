import json, os, sys
from panes import *
state, agents_json, panes_json, show_all, log, projects = sys.argv[1:7]
try:
    agents = {a.get("pane_id"): a for a in json.loads(agents_json)["result"]["agents"]}
    live = {p["pane_id"]: p for p in json.loads(panes_json)["result"]["panes"]}
except (ValueError, KeyError):
    print("Agents\n  (herdr gave no agent list)"); sys.exit(0)
ws_labels = herdr_labels(os.environ.get("SWARM_WORKSPACES", ""), "workspaces", "workspace_id")
tab_labels = herdr_labels(os.environ.get("SWARM_TABS", ""), "tabs", "tab_id")
rows = []
for record, pane, name in pane_records(state, set(os.environ["SWARM_OWN"].split()) & set(live)):
        a = agents.get(pane)
        if a is not None:
            name = a.get("name") or name
        s = session_state(log, name, os.environ["SWARM_SESSIONS"])
        st, _ = shown_state(a, name, s, log, projects)
        what = {"EMPTY": "EMPTY: no agent started in this pane; close it",
                "auth": "auth: its login expired; run /login, then /swarm-dev:swarm tells it to resume",
                "WAITING": f"WAITING on {(s or ('', ''))[1] or 'a question'}: herdr agent read {name}",
                "retired": "done (retired)",
                "unknown": "unknown: no session state" if s else "unknown",
                "gone": "gone: session ended",
                "idle": "idle: finished, or waiting for its next step",
                "done": "idle: finished, or waiting for its next step"}.get(st, st)
        try:   # an odd herdr entry (an id that is not hashable) costs this row its labels, not status its Agents
            ws, tab = pane_where(pane, (live[pane], a), (ws_labels, tab_labels), record)
        except Exception:
            ws, tab = "-", record
        rows.append((name, what, f"pane {pane}, workspace {ws}, tab {tab}"))
quiet = [r for r in rows if r[1].startswith(("idle", "done"))]
shown = rows if show_all == "--all" else [r for r in rows if r not in quiet]
counts = [f"{len(rows) - len(quiet)} need a look or are working", f"{len(quiet)} idle or done"]
print("Agents: " + ", ".join(counts) if rows else "Agents: none open")
width = max((len(r[0]) for r in shown), default=0)
for name, what, where in shown:
    print(f"  {name:<{width}}  {what}  [{where}]")
if quiet and show_all != "--all":
    print("  (swarm.sh status --all lists them all)")
