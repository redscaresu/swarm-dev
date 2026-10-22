import json, os, sys

# longest_child.py <herdr pane process-info JSON> < `ps -A -o pid=,ppid=,etime=,command=` — the command
# a builder's foreground Bash tool call runs, as `longest-running: pid <PID>, <N> min: <program> (under
# <its parents, outermost first, the same way>)`. Of Claude Code's Bash tool shells (`... -c source
# .../shell-snapshots/...`) under the pane's shell (herdr's shell_pid), the newest that runs a command
# is the foreground call (a run_in_background one started earlier lives on beside it); from it, the
# oldest child at each step down to the leaf: the hung `sleep`, not the `make test` above it. Nothing
# else counts (caffeinate, an MCP or LSP server, a hook). Each process is its program name only
# (argv[0]'s basename), never its arguments, which may hold a token. ps's etime is in seconds, so
# siblings started in the same second cannot be told apart: the newest pid is taken. Prints nothing
# when no tool shell runs a command, or the JSON gives no shell pid.
try:
    shell = int(json.loads(sys.argv[1])["result"]["process_info"]["shell_pid"])
except (ValueError, KeyError, TypeError, IndexError):
    sys.exit()
procs, kids = {}, {}
for l in sys.stdin:
    f = l.split(None, 3)
    if len(f) == 4 and f[0].isdigit() and f[1].isdigit():
        procs[int(f[0])] = (int(f[1]), f[2], f[3].strip())
        kids.setdefault(int(f[1]), []).append(int(f[0]))

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
    return "pid %d, %d min: %s" % (p, secs(p) // 60, os.path.basename(procs[p][2].split()[0]).lstrip("-"))

tools = [t for t, v in procs.items() if "/shell-snapshots/" in v[2] and t in kids and under(t)]
if not tools:
    sys.exit()
chain = [max(tools, key=lambda p: (-secs(p), p))]
while chain[-1] in kids:
    chain.append(max(kids[chain[-1]], key=lambda p: (secs(p), p)))
up = " > ".join(show(p) for p in chain[1:-1])
print("longest-running: " + show(chain[-1]) + (" (under %s)" % up if up else ""))
