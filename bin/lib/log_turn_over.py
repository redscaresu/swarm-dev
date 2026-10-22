import json, sys
from report import session_log

# Succeeds when the session's last assistant or user entry is an assistant message that ended its turn
# (stop_reason end_turn, which Claude Code writes on each entry of the message): no tool call waits for
# its result, and no user entry (a prompt, a scheduled one included, or a tool result) followed. Anything else, or no readable log, fails: busy.
TAIL = 1 << 20   # a log's last megabyte; an entry past it reads as not ended

def ended(path):
    with open(path, "rb") as f:
        end = f.seek(0, 2)
        f.seek(max(end - TAIL, 0))
        lines = f.read().split(b"\n")
    for l in reversed(lines[1:] if end > TAIL else lines):   # the first may be cut mid-line
        try:
            d = json.loads(l.decode("utf-8", "replace"))
        except ValueError:
            continue
        if not isinstance(d, dict) or d.get("type") not in ("assistant", "user") or d.get("isSidechain"):   # a Task subagent's entry is not the session's turn
            continue
        m = d.get("message") if isinstance(d.get("message"), dict) else {}
        return d["type"] == "assistant" and m.get("model") != "<synthetic>" and m.get("stop_reason") == "end_turn"
    return False

path = session_log(sys.argv[1], sys.argv[2])
try:
    sys.exit(0 if path and ended(path) else 1)
except OSError:
    sys.exit(1)
