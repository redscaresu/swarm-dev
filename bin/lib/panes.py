import calendar, glob, json, os, re, subprocess, time
WHY_MAX = 60
def pane_records(state, keep):
    seen = set()
    for path in sorted(glob.glob(os.path.join(state, "*"))):
        if not os.path.isfile(path) or path.endswith(".tmp"):
            continue
        for line in open(path, errors="replace"):
            f = line.split()
            if not f or f[0] not in keep or f[0] in seen:
                continue
            seen.add(f[0])
            yield os.path.basename(path), f[0], (f[1] if len(f) > 1 else "-")
def agent_state(a, name, s=None):
    if a is None:
        return "EMPTY", True
    if s is not None:
        st = {"busy": "working", "waiting": "WAITING"}.get(s[0], s[0])
        return st, st not in ("working", "idle")
    st = a.get("agent_status") or "unknown"
    if st == "blocked":
        return "WAITING", True
    if st == "working":
        return "working", False
    if re.search(r"-done\d*$", name):
        return "retired", False
    return st, False
def session_id(log, name):
    line = None
    try:
        for l in open(log, encoding="utf-8", errors="replace"):
            f = l.rstrip("\n").split("\t")
            if len(f) == 7 and f[2] == name:
                line = f
    except OSError:
        pass
    return line[6] if line and line[3] == "claude" and line[6] not in ("", "-") else None
AUTOMATED_PROMPTS = ("<task-notification>", "[Request interrupted", "<command-name>", "<local-command")
def is_prompt(d):
    c = (d.get("message") or {}).get("content")
    if isinstance(c, list):
        c = next((x.get("text") for x in c if isinstance(x, dict) and x.get("type") == "text"), "")
    return not d.get("isMeta") and not str(c or "").startswith(AUTOMATED_PROMPTS)
def login_expired(log, name, projects):
    sid, last = session_id(log, name), None
    for path in glob.glob(os.path.join(projects, "*", sid + ".jsonl")) if sid else []:
        try:
            for l in open(path, encoding="utf-8", errors="replace"):
                if "\"type\":\"assistant\"" not in l and "\"type\":\"user\"" not in l:
                    continue
                try:
                    d = json.loads(l)
                except ValueError:
                    continue
                if not isinstance(d, dict) or d.get("isSidechain"):
                    continue
                if d.get("type") == "assistant" or (d.get("type") == "user" and is_prompt(d)):
                    last = d
        except OSError:
            return False
        break
    return last is not None and last.get("type") == "assistant" and last.get("error") == "authentication_failed"
def bg_running(log, name, projects):
    sid, live, monitors = session_id(log, name), set(), set()
    for path in glob.glob(os.path.join(projects, "*", sid + ".jsonl")) if sid else []:
        try:
            for l in open(path, encoding="utf-8", errors="replace"):
                if not any(k in l for k in ("backgroundTaskId", "async_launched", "taskId", "<task-notification>", '"Monitor"')):
                    continue
                try:
                    d = json.loads(l)
                except ValueError:
                    continue
                if not isinstance(d, dict) or d.get("isSidechain"):
                    continue
                content = (d.get("message") or {}).get("content")
                items = [c for c in content if isinstance(c, dict)] if isinstance(content, list) else []
                if d.get("type") == "assistant":   # which tool_use ids are Monitor calls
                    monitors.update(c.get("id") for c in items if c.get("type") == "tool_use" and c.get("name") == "Monitor")
                    continue
                r = d.get("toolUseResult")
                if isinstance(r, dict):
                    if isinstance(r.get("backgroundTaskId"), str):
                        live.add(r["backgroundTaskId"])
                    if r.get("status") == "async_launched" and isinstance(r.get("agentId"), str):
                        live.add(r["agentId"])
                    # A Monitor's taskId only: a task-list tool's (TaskUpdate) gets no notification.
                    if isinstance(r.get("taskId"), str) and any(c.get("tool_use_id") in monitors for c in items):
                        live.add(r["taskId"])
                    continue
                text = json.dumps([(d.get("message") or {}).get("content"), (d.get("attachment") or {}).get("prompt")])
                for n in re.findall(r"<task-notification>.*?</task-notification>", text):
                    if "<status>" in n:   # an end; a check-in on a running shell carries none
                        live.difference_update(re.findall(r"<task-id>([\w-]+)</task-id>", n))
        except OSError:
            return False
        break
    return bool(live)
# USAGE_TAIL: how many of the pane's last non-empty lines the live usage-limit dialog's options sit in.
USAGE_TAIL = 8
USAGE_OPTION = r"[\s│]*(?:❯\s*)?(\d+)\.\s*"
USAGE_PROMPT = re.compile(r"[\s│]*(>|❯)(\s|$)(?!\s*\d+\.)")
def usage_limit(text):
    lines = [l for l in (text or "").splitlines() if l.strip()]
    tail = lines[max([i for i, l in enumerate(lines) if re.match("(⏺|●)", l)] or [-1]) + 1:]
    # The live dialog: both options among the last lines, and no prompt line (an input box) under the
    # second, which a submitted prompt quoting the dialog always has.
    last = tail[-USAGE_TAIL:]
    stop = [i for i, l in enumerate(last) if re.match(USAGE_OPTION + "Stop and wait for limit to reset", l)]
    go = [(i, m.group(1)) for i, l in enumerate(last) for m in [re.match(USAGE_OPTION + "Wait here, then continue automatically", l)] if m]
    if stop and go and not any(USAGE_PROMPT.match(l) for l in last[go[-1][0] + 1:]):
        return "dialog", go[-1][1]
    joined = "\n".join(tail)
    if "Usage limit reached" in joined and re.search("Continuing shortly|limit resets", joined):
        return "waiting", ""
    return None
def pane_text(pane):
    try:
        return subprocess.run(["herdr", "agent", "read", pane, "--source", "recent-unwrapped"], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return ""
# BRIEF_PASTE: how Claude Code shows a collapsed paste, a brief herdr typed into the pane.
BRIEF_PASTE = re.compile(r"\[Pasted text #\d+")
def box_borders(lines):
    # The input box's two border lines, as pane_stop (agents.sh) reads them: the last two border lines
    # at the margin, with no reply from the upper one down. None when there is no such box.
    borders = [i for i, l in enumerate(lines) if re.match("(╭|╰)?─", l)]
    if len(borders) < 2 or any(re.match("(⏺|●)", l) for l in lines[borders[-2]:]):
        return None
    return borders[-2], borders[-1]
def input_box(text):
    # The input box: the lines between its borders (box_borders). None when there is no such box.
    lines = (text or "").splitlines()
    b = box_borders(lines)
    return None if b is None else lines[b[0] + 1:b[1]]
def unsent_brief(text):
    # A paste left in the input box. A submitted one above the box (`> [Pasted text #1 ...]`) is not.
    return any(BRIEF_PASTE.search(l) for l in input_box(text) or [])
# PROMPT_OPTION: the selected option of a live menu, a permission prompt's or a dialog's (`❯ 1. Yes`).
PROMPT_OPTION = re.compile(r"[\s│]*❯\s*\d+\.\s*\S")
# STOP_LINE: a reply (⏺ or ●) or a submitted prompt, the lines pane_stop (agents.sh) ends a turn on.
STOP_LINE = re.compile(r"\s*(⏺|●)|(>|❯) +\S")
# LOGIN_STOP: Claude Code's "<reason> · Please run /login", not a reply that only mentions /login.
LOGIN_STOP = re.compile(r"(⏺|●)\s*([^·]*·\s*)?Please run /login\s*(·|$)")
API_STOP = re.compile(r"(⏺|●)\s*API Error:")
MANUAL_MODE = re.compile(r"\s*⏸ manual mode on")
MID_COMMAND = "esc to interrupt"
def stuck_kind(text):
    # What the pane's last screen is stuck on, else None:
    #   prompt: a live menu, a permission prompt ("Do you want to proceed?") or a dialog ("Teach auto
    #     mode about your environment?"): its selected option among the last USAGE_TAIL non-empty lines,
    #     after the last reply (⏺ or ●) and not typed into the input box, with no input box or running
    #     command (esc to interrupt) under it; usage_limit's dialog is none (wait answers it). A framed
    #     dialog's borders (╭─, ╰─) read as a box (box_borders): of the box's lines, only those that
    #     start │ (a framed dialog's) are no typed input;
    #   login: the turn ended (the last reply or submitted prompt above the input box) on Claude Code's
    #     "<reason> · Please run /login" ("Login expired · Please run /login");
    #   api-error: the turn ended on an `API Error:` reply at the margin, as pane_stop reads it;
    #   manual: the footer under the input box says manual mode.
    # Else a pane mid-command (esc to interrupt among the last USAGE_TAIL non-empty lines, after the last
    # reply), at an empty input box or on a menu quoted above the box is none.
    lines = (text or "").splitlines()
    last = [i for i, l in enumerate(lines) if l.strip()][-USAGE_TAIL:]
    b = box_borders(lines)
    reply = max([i for i, l in enumerate(lines) if re.match("(⏺|●)", l)] or [-1])
    inside = range(b[0] + 1, b[1]) if b else ()
    sel = [i for i in last if i > reply and PROMPT_OPTION.match(lines[i])
           and not (i in inside and not lines[i].startswith("│"))]
    if sel and not (b and b[0] > sel[-1]) and not any(MID_COMMAND in lines[i] for i in last if i > sel[-1]):
        return None if (usage_limit(text) or ("",))[0] == "dialog" else "prompt"
    if any(MID_COMMAND in lines[i] for i in last if i > reply):
        return None
    stop = ([""] + [l for l in lines[:b[0] if b else len(lines)] if STOP_LINE.match(l)])[-1]
    if LOGIN_STOP.match(stop):
        return "login"
    if API_STOP.match(stop):
        return "api-error"
    footer = lines[b[1] + 1:] if b else []
    return "manual" if any(MANUAL_MODE.match(l) for l in footer) else None
def turn_since(log, name, projects, since, slack):
    # True when <name>'s Claude session log has a turn start (a prompt typed or pasted in, not a tool
    # result or an automated prompt) stamped later than <slack> seconds before <since> (an events.tsv
    # time, written once the command that sent the prompt returned, so a turn it started may be stamped
    # before it). With <since> "-", any turn start in the session counts. None when it cannot say: no
    # session on record, or no readable log of it (Claude Code writes the log before the first prompt,
    # so a missing one is no sign that no turn ran).
    sid, cut = session_id(log, name), ""
    try:
        if since != "-":
            cut = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(calendar.timegm(time.strptime(since[:19], "%Y-%m-%dT%H:%M:%S")) - int(slack)))
    except (ValueError, OverflowError):
        return True   # an unreadable time: never resend on it
    for path in glob.glob(os.path.join(glob.escape(projects), "*", glob.escape(sid) + ".jsonl")) if sid else []:
        try:
            for l in open(path, encoding="utf-8", errors="replace"):
                if "\"timestamp\"" not in l:
                    continue
                try:
                    d = json.loads(l)
                except ValueError:
                    continue
                m = d.get("message") if isinstance(d, dict) else None
                c = m.get("content") if isinstance(m, dict) else None
                typed = isinstance(c, str) or (isinstance(c, list) and any(isinstance(x, dict) and x.get("type") == "text" for x in c))
                if typed and d.get("type") == "user" and not d.get("isSidechain") and is_prompt(d) \
                        and str(d.get("timestamp") or "")[:19] > cut:
                    return True
        except OSError:
            return None
        return False
    return None
def shown_state(a, name, s, log, projects):
    st, look = agent_state(a, name, s)
    if st == "idle" and s is not None and login_expired(log, name, projects):
        return "auth", True
    u = usage_limit(pane_text(a["pane_id"])) if st in ("working", "idle", "done", "WAITING") and a and a.get("pane_id") else None
    # The waiting line counts only while the turn runs: an idle session under it is idle.
    if u and (u[0] == "dialog" or st in ("working", "WAITING")):
        return "usage-limit", False
    return st, look
def session_state(log, name, listing):
    sid = session_id(log, name)
    if sid is None:
        return None
    try:
        entries = json.loads(listing) if listing is not None else None
    except ValueError:
        entries = None
    if not isinstance(entries, list):
        return "unknown", ""
    e = next((x for x in entries if isinstance(x, dict) and x.get("sessionId") == sid), None)
    st = e.get("status") if e is not None else None
    if st is None:
        return "gone", ""
    if st == "waiting":
        why = " ".join(str(e.get("waitingFor") or "").split())
        return st, why if len(why) <= WHY_MAX else why[:WHY_MAX - 1] + "…"
    return (st, "") if st in ("busy", "idle") else ("unknown", "")
# TEST_RUN: a command line that runs a test suite: make with a test or check argument, a shell running
# scripts/test.sh, or the script run as itself. A word that only names one (grep scripts/test.sh, cat
# test) is none.
TEST_RUN = re.compile(r"(\S*/)?g?make(\s+\S+)*?\s+(test|check)(\s|$)"
                      r"|(\S*/)?(ba|z|da|k)?sh(\s+-\S+)*\s+(\S*/)?scripts/test\.sh(\s|$)"
                      r"|(\S*/)?scripts/test\.sh(\s|$)")
# TEST_RUN_STALLS: how many stall_minutes a test run counts as work for; an older one may be hung.
TEST_RUN_STALLS = 3
def etime_secs(t):   # ps etime: [[dd-]hh:]mm:ss
    d, _, hms = t.rpartition("-")
    h = [0, 0] + [int(x) for x in hms.split(":")]
    return int(d or 0) * 86400 + h[-3] * 3600 + h[-2] * 60 + h[-1]
def test_running(info, stall_minutes):
    try:
        shell = int(json.loads(info)["result"]["process_info"]["shell_pid"])
        cap = TEST_RUN_STALLS * int(stall_minutes) * 60
        out = subprocess.run(["ps", "-A", "-o", "pid=,ppid=,etime=,command="], capture_output=True, text=True, timeout=10)
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError):
        return False
    if out.returncode != 0:
        return False
    parent, runs = {}, set()
    for l in out.stdout.splitlines():
        f = l.split(None, 3)
        if len(f) == 4 and f[0].isdigit() and f[1].isdigit():
            parent[int(f[0])] = int(f[1])
            try:
                young = etime_secs(f[2]) < cap
            except ValueError:
                young = False
            if young and TEST_RUN.match(f[3].strip()):
                runs.add(int(f[0]))
    for p in runs:
        for _ in parent:   # up to the pane's shell; a cycle or a process with no parent listed ends the walk
            p = parent.get(p)
            if p is None or p == shell:
                break
        if p == shell:
            return True
    return False
