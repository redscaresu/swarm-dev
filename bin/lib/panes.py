import base64, calendar, glob, hashlib, json, os, re, shutil, signal, subprocess, time
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
# herdr_labels: {id: label} from herdr's workspace or tab list as read, an entry with no id skipped (else
# its label would answer for every pane with no id); {} for one herdr did not give.
def herdr_labels(raw, key, id_key):
    try:
        return {x[id_key]: x.get("label") for x in json.loads(raw)["result"][key] if isinstance(x, dict) and x.get(id_key)}
    except (ValueError, KeyError, TypeError, AttributeError):
        return {}
# pane_ids: (workspace id, tab id) of a pane, each from the first of its herdr entries (its pane list's,
# its agent list's) that has it; the workspace else by the pane id's prefix, the tab else None.
def pane_ids(pane, entries):
    ids = lambda k: next((e.get(k) for e in entries if isinstance(e, dict) and e.get(k)), None)
    return ids("workspace_id") or pane.split(":")[0], ids("tab_id")
# pane_where: (workspace label, tab label) of a pane, by pane_ids, from labels = (workspace labels, tab
# labels). A workspace herdr gives no label for is "-"; a tab is record, the name swarm-dev gave the tab
# (its tab record's), so where, status and dash name it alike whether or not herdr labelled it.
def pane_where(pane, entries, labels, record="-"):
    ws, tab = pane_ids(pane, entries)
    return labels[0].get(ws) or "-", labels[1].get(tab) or record
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
# SIGN_SECONDS: how long each call sign_blocked makes (git, gpg, gpg-connect-agent, ssh-add, ssh-keygen) may
# take; one past it is killed with its process group, and the probe says unknown.
SIGN_SECONDS = 5
def sign_call(argv):
    # (exit code, stdout) of argv, with no stdin and stderr dropped; None when it cannot start or runs past
    # SIGN_SECONDS.
    try:
        p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                             text=True, errors="replace", start_new_session=True)
    except (OSError, ValueError, subprocess.SubprocessError):
        return None
    try:
        out = p.communicate(timeout=SIGN_SECONDS)[0]
    except subprocess.TimeoutExpired:
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except OSError:
            pass
        p.wait()
        p.stdout.close()
        return None
    return p.returncode, out
def sign_blocked(worktree):
    # blocked, clear or unknown: whether the signer git is set to use in <worktree> can sign its uncommitted
    # work unprompted. gpgsign off or a clean tree is clear before any signer call; gpg.format picks the rest.
    git = lambda *a: sign_call(["git", "--no-optional-locks", "-C", worktree] + list(a))
    on = git("config", "--type=bool", "--get", "commit.gpgsign")
    if on is None or on[0] not in (0, 1):
        return "unknown"
    if on[1].strip() != "true":
        return "clear"
    st = git("status", "--porcelain")
    if st is None or st[0] != 0:
        return "unknown"
    if not st[1].strip():
        return "clear"
    fmt, key = git("config", "--get", "gpg.format"), git("config", "--get", "user.signingkey")
    if any(r is None or r[0] not in (0, 1) for r in (fmt, key)):
        return "unknown"
    fmt, key = fmt[1].strip() if fmt[0] == 0 else "openpgp", key[1].strip() if key[0] == 0 else None
    if key == "":
        return "unknown"
    if fmt == "openpgp":
        return gpg_blocked(worktree, git, key)
    return ssh_blocked(worktree, key) if fmt == "ssh" else "unknown"
def gpg_blocked(worktree, git, key):
    # Run the gpg git would (the last of gpg.program and gpg.openpgp.program, else gpg on PATH), and ask the
    # gpg-connect-agent in its directory, never one on PATH, whether gpg-agent caches the passphrase of the
    # (sub)key `gpg -u <key>` signs with. <key> None is git's own: the committer's `Name <email>`.
    prog = git("config", "--type=path", "--get-regexp", r"^gpg\.(openpgp\.)?program$")
    if prog is None or prog[0] not in (0, 1):
        return "unknown"
    prog = ([l.split(" ", 1)[1] for l in prog[1].splitlines() if " " in l] or ["gpg"])[-1]
    gpg = os.path.join(worktree, prog) if "/" in prog else shutil.which(prog)
    if key is None:
        ident = git("var", "GIT_COMMITTER_IDENT")
        key = ident[1][:ident[1].rfind(">") + 1] if ident and ident[0] == 0 else ""
    if not gpg or not key:
        return "unknown"
    ls = sign_call([gpg, "--batch", "--no-autostart", "--with-colons", "--with-keygrip", "--list-secret-keys", "--", key])
    grip = signing_keygrip(ls[1], key) if ls and ls[0] == 0 else None
    info = sign_call([os.path.join(os.path.dirname(gpg), "gpg-connect-agent"), "--no-autostart", "KEYINFO " + grip, "/bye"]) if grip else None
    # S KEYINFO <keygrip> <type> <serial> <idstr> <cached> <protection> ...: cached 1, or protection C (no
    # passphrase), signs; a key on disk (D) that is protected (P) and not cached needs a prompt.
    for f in (l.split() for l in (info[1] if info else "").splitlines()):
        if len(f) > 7 and f[:2] == ["S", "KEYINFO"] and f[2].upper() == grip.upper():
            if f[6] == "1" or f[7] == "C":
                return "clear"
            return "blocked" if f[3] == "D" and f[7] == "P" else "unknown"
    return "unknown"
def signing_keygrip(listing, spec):
    # The keygrip of the (sub)key `gpg -u <spec>` signs with, from gpg's --with-colons --with-keygrip
    # --list-secret-keys listing of <spec>: with <spec>! the (sub)key it names; else, in the first key that
    # has one, the newest usable signing subkey, else the primary when it can sign. Usable: s among its own
    # capabilities, not revoked, expired or invalid, and its secret no stub (#). None when none can sign.
    exact, blocks = re.sub("^0[xX]", "", spec[:-1]).upper() if spec.endswith("!") else "", []
    for f in (l.split(":") for l in listing.splitlines()):
        if f[0] == "sec":
            blocks.append([])
        if f[0] in ("sec", "ssb") and blocks and len(f) > 14:
            blocks[-1].append({"ids": [f[4].upper()], "grip": None, "created": int(f[5]) if f[5].isdigit() else 0,
                               "sign": "s" in f[11] and f[1] not in ("r", "e", "i") and f[14] != "#"})
        elif f[0] in ("fpr", "grp") and blocks and blocks[-1] and len(f) > 9:
            k = blocks[-1][-1]
            if f[0] == "fpr":
                k["ids"].append(f[9].upper())
            elif k["grip"] is None:
                k["grip"] = f[9]
    for keys in blocks:
        if exact:
            k = next((k for k in keys if any(i.endswith(exact) for i in k["ids"] if i)), None)
        else:
            subs = [k for k in keys[1:] if k["sign"]]
            k = max(subs, key=lambda k: k["created"]) if subs else keys[0] if keys and keys[0]["sign"] else None
        if k and k["sign"] and k["grip"]:
            return k["grip"]
    return None
def ssh_fingerprint(blob):
    # OpenSSH's SHA256 fingerprint of a base64 public key blob, as ssh-keygen -l prints it; None if not base64.
    try:
        return "SHA256:" + base64.b64encode(hashlib.sha256(base64.b64decode(blob, validate=True)).digest()).decode().rstrip("=")
    except ValueError:
        return None
def ssh_blocked(worktree, key):
    # blocked when <key> is a public key (a key:: literal, an ssh- one git reads as key::, or a .pub path,
    # fingerprinted by ssh-keygen -l) that ssh-add -L, on SSH_AUTH_SOCK, does not list (exit 0, or 1 for an
    # empty or locked agent); clear when it lists it. unknown when ssh-add reaches no agent (any other exit),
    # and for a .pub not listed with a file at its private key path (the path without -cert.pub or .pub),
    # which ssh-keygen -Y sign falls back to and which signs unprompted when it has no passphrase: that file
    # is only checked to exist, never opened. A private key file as <key> is unknown for the same reason.
    # gpg.ssh.program and ssh-keygen -Y sign never run.
    if key is None:
        return "unknown"
    priv = None
    if key.startswith(("key::", "ssh-")):
        f = key[5:].split() if key.startswith("key::") else key.split()
        want = ssh_fingerprint(f[1]) if len(f) > 1 else None
    elif key.endswith(".pub"):
        path = os.path.join(worktree, os.path.expanduser(key))
        fp = sign_call(["ssh-keygen", "-l", "-E", "sha256", "-f", path])
        f = fp[1].split() if fp and fp[0] == 0 else []
        want = f[1] if len(f) > 1 and f[1].startswith("SHA256:") else None
        priv = re.sub(r"(-cert)?\.pub$", "", path)
    else:
        return "unknown"
    listed = sign_call(["ssh-add", "-L"]) if want else None
    if listed is None or listed[0] not in (0, 1):
        return "unknown"
    if want in (ssh_fingerprint(l.split()[1]) for l in listed[1].splitlines() if len(l.split()) > 1):
        return "clear"
    return "unknown" if priv and os.path.exists(priv) else "blocked"
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
# READ_SECONDS: how long one pane read (pane_text) may take.
READ_SECONDS = 10
def pane_text(pane):
    # Under a report's deadline (SWARM_REPORT_END, an epoch to the millisecond, with SWARM_REPORT_SKIP_FILE:
    # status sets them on status_report.py, dash on its python runs, in dash_deadline), the read takes at
    # most the time left, and one due at or past the deadline never starts. Either way it is recorded as
    # skipped, as report_read (merge.sh) records a read it cuts, under the name the shell's herdr wrapper
    # gives the same read. With no deadline (dash --check, tidy, the agents.sh snippets), READ_SECONDS, and
    # nothing is recorded.
    timeout, end = READ_SECONDS, os.environ.get("SWARM_REPORT_END")
    if end:
        try:
            timeout = min(READ_SECONDS, float(end) - time.time())
        except ValueError:
            end = None
        if end and timeout < 0.001:
            read_skipped()
            return ""
    try:
        return subprocess.run(["herdr", "agent", "read", pane, "--source", "recent-unwrapped"], capture_output=True, text=True, timeout=timeout).stdout
    except subprocess.TimeoutExpired:
        if end:
            read_skipped()
        return ""
    except (OSError, subprocess.SubprocessError):
        return ""
def read_skipped():
    path = os.environ.get("SWARM_REPORT_SKIP_FILE")
    if path:
        try:
            with open(path, "a") as f:
                f.write("herdr agent read\n")
        except OSError:
            pass
# BRIEF_PASTE: how Claude Code shows a collapsed paste, a brief herdr typed into the pane.
BRIEF_PASTE = re.compile(r"\[Pasted text #\d+")
def box_borders(lines):
    # The last two border lines at the margin (─, ╭─ or ╰─), with no reply from the upper one down: the
    # input box pane_stop (agents.sh) reads when the pane has two or more. None when there is no such
    # pair. pane_stop also takes a lone border line as the box's top; turn_lines reads that.
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
# BOX_PROMPT: the input box's first line, its prompt at the margin. A dialog between two border lines
# starts with an indented title, a framed one with │.
BOX_PROMPT = re.compile(r"(>|❯)(\s|$)")
# STOP_LINE: a reply (⏺ or ●, at any indent) or a submitted prompt (`> text` or `❯ text` at the margin):
# the lines on which pane_stop (agents.sh) starts or clears a stop. pane_stop's auto-denied tool result
# is no stop here.
STOP_LINE = re.compile(r"\s*(⏺|●)|(>|❯) +\S")
# LOGIN_STOP: Claude Code's "<reason> · Please run /login", not a reply that only mentions /login.
LOGIN_STOP = re.compile(r"(⏺|●)\s*([^·]*·\s*)?Please run /login\s*(·|$)")
API_STOP = re.compile(r"(⏺|●)\s*API Error:")
MANUAL_MODE = re.compile(r"\s*⏸ manual mode on")
MID_COMMAND = "esc to interrupt"
def turn_lines(lines):
    # The lines pane_stop (agents.sh) reads for a stop: those above the input box's top border (the
    # second-to-last border line at the margin, or the only one), or every line when a reply (⏺ or ● at
    # the margin) sits on or below that border.
    borders = [i for i, l in enumerate(lines) if re.match("(╭|╰)?─", l)]
    top = borders[-2] if len(borders) > 1 else borders[-1] if borders else len(lines)
    return lines if any(re.match("(⏺|●)", l) for l in lines[top:]) else lines[:top]
def stuck_kind(text):
    # What the pane's last screen is stuck on, else None. It reads the lines after the last reply (⏺ or
    # ● at the margin), and the input box: box_borders' pair when the first line between them is
    # BOX_PROMPT, so a dialog between two border lines is no box.
    #   prompt: a live menu, a permission prompt ("Do you want to proceed?") or a dialog ("Teach auto
    #     mode about your environment?"): a selected option after the last reply and outside the input
    #     box, with no input box and no running command (esc to interrupt) under it. usage_limit's
    #     dialog is none (wait answers it);
    #   login: the turn ended (the last STOP_LINE in turn_lines) on Claude Code's "<reason> · Please
    #     run /login" ("Login expired · Please run /login");
    #   api-error: the turn ended on an `API Error:` reply at the margin, as pane_stop reads it;
    #   manual: the footer under the input box says manual mode.
    # Else a pane mid-command (esc to interrupt after the last reply), at an empty input box or on a
    # menu above the input box is none.
    lines = (text or "").splitlines()
    reply = max([i for i, l in enumerate(lines) if re.match("(⏺|●)", l)] or [-1])
    b = box_borders(lines)
    if b and not BOX_PROMPT.match(lines[b[0] + 1]):
        b = None
    sel = [i for i in range(reply + 1, len(lines))
           if PROMPT_OPTION.match(lines[i]) and not (b and b[0] < i < b[1])]
    if sel and not (b and b[0] > sel[-1]) and not any(MID_COMMAND in l for l in lines[sel[-1] + 1:]):
        return None if (usage_limit(text) or ("",))[0] == "dialog" else "prompt"
    if any(MID_COMMAND in l for l in lines[reply + 1:]):
        return None
    stop = ([""] + [l for l in turn_lines(lines) if STOP_LINE.match(l)])[-1]
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
