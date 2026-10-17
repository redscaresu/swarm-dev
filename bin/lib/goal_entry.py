import datetime, json, os, re, sys
from panes import *; from report import *
log, name, projects, since, cond = sys.argv[1:6]
want = " ".join(open(cond, encoding="utf-8").read().split()) if cond else None
sid = session_id(log, name)
path, kind, queued = session_log(projects, sid) if sid else "", "", False
for l in open(path, encoding="utf-8", errors="replace") if path else []:
    if "goal_status" not in l and "local_command" not in l and "queued_command" not in l:
        continue
    try:
        d = json.loads(l)
        t = datetime.datetime.fromisoformat(str(d.get("timestamp")).replace("Z", "+00:00")).timestamp()
    except (AttributeError, ValueError):
        continue
    a = d.get("attachment")
    if d.get("type") == "attachment" and isinstance(a, dict) and a.get("type") == "goal_status":
        if want is not None and " ".join(str(a.get("condition") or "").split()) != want:
            continue
        k = "set" if a.get("sentinel") else "met" if a.get("met") else "continuing"
    elif d.get("type") == "system" and d.get("subtype") == "local_command":
        m = re.match(r"<local-command-stdout>(/goal [^<]*)", str(d.get("content") or ""))
        if not m:
            continue
        k = "refused: " + " ".join(m.group(1).split())
    elif want is not None and d.get("type") == "attachment" and isinstance(a, dict) and a.get("type") == "queued_command":
        p = a.get("prompt")
        p = "".join(b.get("text") or "" for b in p if isinstance(b, dict)) if isinstance(p, list) else str(p or "")
        if t >= float(since) and " ".join(re.sub(r"</?pasted_content[^>]*>", " ", p).split()).startswith("/goal " + want):
            queued = True
        continue
    else:
        continue
    if t >= float(since):
        kind = k
print(kind or ("pasted" if queued else ""))
