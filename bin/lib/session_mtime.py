import datetime, json, os, sys
from panes import *; from report import *

def own_work(d):
    # The agent's own work: an assistant message (not Claude Code's synthetic one) or a tool result. A
    # compaction, summary or background-task notice is not, though the session writes them while idle.
    if not isinstance(d, dict) or d.get("isCompactSummary") or d.get("isMeta"):
        return False
    m = d.get("message") if isinstance(d.get("message"), dict) else {}
    if d.get("type") == "assistant":
        return m.get("model") != "<synthetic>"
    c = m.get("content")
    return d.get("type") == "user" and isinstance(c, list) and any(isinstance(x, dict) and x.get("type") == "tool_result" for x in c)

def last_work(path):
    # The epoch of the newest own-work entry, read from the log's end back, or "" with none. One with no
    # timestamp is dated by the log's mtime.
    size = 65536
    with open(path, "rb") as f:
        end = f.seek(0, 2)
        while True:
            f.seek(max(end - size, 0))
            lines = f.read().decode("utf-8", "replace").splitlines()
            for l in reversed(lines[1:] if end > size else lines):   # the first may be cut mid-line
                try:
                    d = json.loads(l)
                except ValueError:
                    continue
                if not own_work(d):
                    continue
                try:
                    return int(datetime.datetime.fromisoformat(str(d["timestamp"]).replace("Z", "+00:00")).timestamp())
                except (KeyError, ValueError):
                    return int(os.path.getmtime(path))
            if size >= end:
                return ""
            size *= 4

sid = session_id(sys.argv[1], sys.argv[2])
path = session_log(sys.argv[3], sid) if sid else ""
try:
    print(last_work(path) if path else "")
except OSError:   # removed since the glob: no sign
    print("")
