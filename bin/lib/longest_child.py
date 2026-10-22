import json, os, subprocess, sys, time

# longest_child.py <herdr pane process-info JSON> <last own work, epoch or ""> — the command a builder's
# foreground Bash tool call runs, as `longest-running: pid <PID>, <N> min: <program> (under <its
# parents, outermost first, the same way>)`. Of Claude Code's Bash tool shells (`... -c source
# .../shell-snapshots/...`) under the pane's shell (herdr's shell_pid), the newest that runs a command
# is the foreground call (a run_in_background one started earlier lives on beside it). One started
# before the session's last own work (session_mtime, less SLACK) cannot be: that entry came after it,
# so the builder is hung elsewhere (an MCP call, a Task subagent, the API), and none is named. From
# the foreground shell, the oldest child at each step down to the leaf: the hung `sleep`, not the
# `make test` above it. Nothing else counts (caffeinate, an MCP or LSP server, a hook). Each process
# is its program name only, the basename of ps's comm (a path may hold spaces), never its arguments,
# which may hold a token. ps's etime is in seconds, so siblings started in the same second cannot be
# told apart: the newest pid is taken. When none is named it says why: `longest-running: none named
# (<why>)`.

# SLACK: seconds a tool shell may seem to start before the tool call it runs: etime counts whole seconds.
SLACK = 2

def none(why):
    print("longest-running: none named (%s)" % why)
    sys.exit()

def ps(fmt):
    try:
        return subprocess.run(["ps", "-A", "-o", fmt], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return ""

try:
    shell = int(json.loads(sys.argv[1])["result"]["process_info"]["shell_pid"])
except (ValueError, KeyError, TypeError, IndexError):
    none("herdr's process info for its pane could not be read")
last = float(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else None
procs, kids, comm = {}, {}, {}
for l in ps("pid=,ppid=,etime=,command=").splitlines():
    f = l.split(None, 3)
    if len(f) == 4 and f[0].isdigit() and f[1].isdigit():
        procs[int(f[0])] = (int(f[1]), f[2], f[3].strip())
        kids.setdefault(int(f[1]), []).append(int(f[0]))
if not procs:
    none("ps could not be read")
for l in ps("pid=,comm=").splitlines():
    f = l.strip().split(None, 1)
    if len(f) == 2 and f[0].isdigit():
        comm[int(f[0])] = f[1].strip()

def secs(p):   # ps etime: [[dd-]hh:]mm:ss
    d, _, hms = procs[p][1].rpartition("-")
    t = [0, 0] + [int(x) for x in hms.split(":")]
    return int(d or 0) * 86400 + t[-3] * 3600 + t[-2] * 60 + t[-1]

def under(p):   # p is under the pane shell
    for _ in procs:
        if p not in procs:
            return False
        p = procs[p][0]
        if p == shell:
            return True
    return False

def show(p):
    name = comm.get(p) or procs[p][2].split()[0]   # gone between the two reads: the command's first word
    return "pid %d, %d min: %s" % (p, secs(p) // 60, os.path.basename(name).lstrip("-"))

tools = [t for t, v in procs.items() if "/shell-snapshots/" in v[2] and t in kids and under(t)]
if not tools:
    none("no Bash tool call is running a command")
now = time.time()
fg = [t for t in tools if last is None or now - secs(t) >= last - SLACK]
if not fg:
    none("no foreground Bash call: every tool shell running a command started before its last own work")
chain = [max(fg, key=lambda p: (-secs(p), p))]
while chain[-1] in kids:
    chain.append(max(kids[chain[-1]], key=lambda p: (secs(p), p)))
up = " > ".join(show(p) for p in chain[1:-1])
print("longest-running: " + show(chain[-1]) + (" (under %s)" % up if up else ""))
