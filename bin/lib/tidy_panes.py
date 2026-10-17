import json, os, sys
from panes import *
state, agents_json, panes_json, me = sys.argv[1:5]
agents = {a.get("pane_id"): a for a in json.loads(agents_json)["result"]["agents"]}
live = {p["pane_id"] for p in json.loads(panes_json)["result"]["panes"]}
for tab, pane, recorded in pane_records(state, (set(os.environ["SWARM_OWN"].split()) & live) - {me}):
    a = agents.get(pane)
    name = (a or {}).get("name") or recorded
    reason = {"EMPTY": "empty: no agent started", "retired": "retired"}.get(agent_state(a, name)[0])
    if reason:
        print("\t".join((pane, name, reason, tab)))
