#!/usr/bin/env bash
# merge-guard.sh — the plugin's PreToolUse hook on Bash (hooks/hooks.json). Inside a swarm project
# (a .claude/swarm/ at or above the call's cwd, or above its main checkout when the cwd is a git
# worktree) it stops careless merges, so a PR merges through a lone `swarm.sh merge <PR URL>`; it is
# no defence against deliberate evasion. It reads the tool call's JSON on stdin and exits 2, naming
# the form, on gh pr merge, gh api .../pulls/<n>/merge, a graphql mergePullRequest, any of them in
# code handed to a shell or an interpreter (-c, eval, a heredoc, a here-string, a pipe) or written
# to a file, and on swarm.sh merge joined to another command. A mention in echo, printf or grep
# passes. Each block appends an incident line, `merge-blocked: <form>`, to the project's
# .swarm/events.tsv. Outside a swarm project it allows all.
set -uo pipefail

input="$(cat)"
# Fast path: a call that never says merge, not even through quotes and backslashes (mer"ge,
# me''rge, mer\ge), cannot merge. grep reads all its input, so pipefail never sees tr's SIGPIPE.
printf '%s' "${input}" | tr -d "\"'\\\\" | grep -i merge >/dev/null || exit 0
# Past here the call says merge, so the guard fails closed: anything but its own verdict refuses it.
command -v python3 >/dev/null || { echo "merge-guard: python3 is missing, so a call that says merge is refused" >&2; exit 2; }

IFS= read -r -d '' prog <<'PY' || true
import itertools, json, os, re, subprocess, sys, time

# A merge in text that runs as code nothing here parses (an interpreter's, a file's, a pipe's).
RAW = re.compile(r"\bgh\W+pr\W+merge\b|pulls/[^/\s]+/merge\b|mergePullRequest|enablePullRequestAutoMerge")
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
INTERPRETER = re.compile(r"python[0-9.]*|node|perl|ruby|php|deno|bun|osascript")
SHELL_CODE = re.compile(r"-[A-Za-z]*c[A-Za-z]*")
INTERPRETER_CODE = re.compile(r"-[A-Za-z]*[ceEp]|--eval|--print")
MENTIONS = {"echo", "printf", "grep", "egrep", "fgrep", "rg"}
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
REDIRECT = re.compile(r"<<<|<<-?|&>>?|>>|>[|&]?|<[&>]?")
QUIET = {"/dev/null", "/dev/stdout", "/dev/stderr"}
QUOTING = re.compile(r"[\"'\\]")
PIPES = itertools.count()
MESSAGE = """merge-guard: blocked ({}). In a swarm project only `swarm.sh merge <PR URL>`, run alone,
merges a PR (docs/reference.md § Merging). Text that only mentions a merge, such as a PR body, can go
through the Write tool or --body "$(cat <<'EOF' ... EOF)"."""


class Blocked(Exception):
    pass


class Shell:
    """Just enough of a shell parser to find the simple commands in a Bash call, those in $( ),
    backticks, process substitutions and unquoted heredocs included. Each is a dict: words (quotes
    removed), bodies (its heredocs and here-strings), file (it writes a file), pipe (its pipeline),
    nested (in a substitution) and end (the operator after it)."""

    def __init__(self, s):
        self.s, self.i, self.cmds, self.heredocs = s, 0, [], []

    def new(self, nested, pipe=None):
        cmd = {"words": [], "bodies": [], "file": False, "nested": nested, "end": "",
               "pipe": next(PIPES) if pipe is None else pipe}
        self.cmds.append(cmd)
        return cmd

    def parse(self, nested=False, closes=False):
        """Read commands to the end, or past the ) that closes the $( ) being read (closes). A ( )
        or { } group is one pipeline, so whatever any command in it prints feeds a pipe after it."""
        cmd, depth = self.new(nested), 0
        while self.i < len(self.s):
            c = self.s[self.i]
            if c in " \t":
                self.i += 1
            elif c == "#":
                j = self.s.find("\n", self.i)
                self.i = len(self.s) if j < 0 else j
            elif c in "<>" or self.s.startswith("&>", self.i):
                self.redirect(cmd)
            elif c == ")" and closes and depth == 0:
                self.i += 1
                return
            elif c in "\n;&|()":
                depth += (c == "(") - (c == ")" and depth > 0)
                cmd = self.op(cmd, nested, depth > 0)
            else:
                w = self.word()
                if w in ("{", "}") and not cmd["words"]:
                    depth += 1 if w == "{" else -(depth > 0)
                elif not (w.isdigit() and self.s[self.i:self.i + 1] in ("<", ">")):  # else a redirect's fd
                    cmd["words"].append(w)

    def op(self, cmd, nested, grouped):
        two = self.s[self.i:self.i + 2]
        cmd["end"] = two if two in ("&&", "||", ";;", "|&") else two[:1]
        self.i += len(cmd["end"])
        if cmd["end"] == "\n":
            self.read_heredocs()
        keep = grouped or cmd["end"] in ("|", "|&", "(", ")")
        return self.new(nested, cmd["pipe"] if keep else None)

    def word(self):
        """One word, quotes removed; a substitution in it stays as its source text."""
        out = ""
        while self.i < len(self.s) and self.s[self.i] not in " \t\n;&|()<>":
            c = self.s[self.i]
            self.i += 1
            if c == "\\":
                out += self.s[self.i:self.i + 1].strip("\n")
                self.i += 1
            elif c == "'":
                j = self.s.find("'", self.i)
                j = len(self.s) if j < 0 else j
                out, self.i = out + self.s[self.i:j], j + 1
            elif c == '"':
                out += self.dquote()
            elif c == "`" or (c == "$" and self.s[self.i:self.i + 1] == "("):
                out += self.sub(c)
            else:
                out += c
        return out

    def dquote(self, end='"'):
        """Text up to end (to the end of the text when None), parsing each substitution in it."""
        out = ""
        while self.i < len(self.s):
            c = self.s[self.i]
            self.i += 1
            if c == end:
                break
            if c == "\\" and self.s[self.i:self.i + 1] in ('"', "\\", "$", "`", "\n"):
                out += self.s[self.i].strip("\n")
                self.i += 1
            elif c == "`" or (c == "$" and self.s[self.i:self.i + 1] == "("):
                out += self.sub(c)
            else:
                out += c
        return out

    def sub(self, c):
        """Parse a $( ), <( ), >( ) or backtick substitution's code as nested commands."""
        start = self.i - 1
        if c == "`":
            j = self.s.find("`", self.i)
            j = len(self.s) if j < 0 else j
            inner = Shell(self.s[self.i:j])
            inner.parse(nested=True)
            self.cmds += inner.cmds
            self.i = j + 1
        else:
            self.i += 1
            self.parse(nested=True, closes=True)
        return self.s[start:self.i]

    def redirect(self, cmd):
        op = REDIRECT.match(self.s, self.i).group()
        self.i += len(op)
        if op in ("<", ">") and self.s[self.i:self.i + 1] == "(":
            cmd["words"].append(self.sub(op))
            return
        while self.s[self.i:self.i + 1] in (" ", "\t"):
            self.i += 1
        start = self.i
        target = self.word()
        if op == "<<<":
            cmd["bodies"].append(target)
        elif op.startswith("<<"):
            quoted = any(q in self.s[start:self.i] for q in "'\"\\")
            self.heredocs.append((target, op == "<<-", cmd, quoted))
        elif ">" in op and target not in QUIET and not (op.endswith("&") and re.fullmatch(r"\d*-?", target)):
            cmd["file"] = True

    def read_heredocs(self):
        for delim, strip, cmd, quoted in self.heredocs:
            body = []
            while self.i < len(self.s):
                j = self.s.find("\n", self.i)
                j = len(self.s) if j < 0 else j
                line, self.i = self.s[self.i:j], j + 1
                if (line.lstrip("\t") if strip else line) == delim:
                    break
                body.append(line)
            cmd["bodies"].append("\n".join(body))
            if not quoted:  # bash runs the $( ) and backticks in an unquoted heredoc
                inner = Shell(cmd["bodies"][-1])
                inner.dquote(end=None)
                self.cmds += inner.cmds
        self.heredocs = []


def raw(s):
    """RAW in s seen through quotes and backslashes (mer\"ge, me''rge, mer\\ge), as a shell would run it."""
    return RAW.search(QUOTING.sub("", s))


def text(cmd):
    return " ".join(cmd["words"] + cmd["bodies"])


def check(code, via=""):
    """Raise Blocked, naming the form, when shell code merges a PR other than by a lone swarm.sh merge."""
    sh = Shell(code.strip())
    sh.parse()
    cmds = [c for c in sh.cmds if c["words"] or c["bodies"]]
    for n, cmd in enumerate(cmds):
        fed = [text(c) for c in cmds[:n] if c["pipe"] == cmd["pipe"]] + cmd["bodies"]
        check_cmd(cmd, fed, via, len(cmds) > 1 or via != "" or cmd["nested"] or cmd["end"] == "&")


def check_cmd(cmd, fed, via, joined):
    """One simple command; fed is the text piped or heredoc'd into it."""
    args = list(itertools.dropwhile(ASSIGNMENT.match, cmd["words"]))
    if cmd["file"] and raw(" ".join([text(cmd)] + fed)):
        raise Blocked("a merge written to a file")
    if not args or os.path.basename(args[0]) in MENTIONS:
        return
    for i, w in enumerate(args):
        b, rest = os.path.basename(w), args[i + 1:]
        if b == "gh":
            check_gh(rest, fed, via)
        elif b == "swarm.sh" and rest[:1] == ["merge"] and joined:
            raise Blocked("swarm.sh merge joined to another command" + via)
        elif b == "tee" and raw(" ".join(fed)):
            raise Blocked("a merge written to a file")
        elif b in SHELLS or b == "eval" or INTERPRETER.fullmatch(b):
            check_code(b, rest, fed)


def check_gh(rest, fed, via):
    """gh's words with its flags dropped, and the value of a separate -R or --repo (-Ro/r is one flag)."""
    args, value = [], False
    for w in rest:
        if not value and not w.startswith("-"):
            args.append(w)
        value = not value and w in ("-R", "--repo")
    if args[:2] == ["pr", "merge"]:
        raise Blocked("gh pr merge" + via)
    if args[:1] == ["api"] and raw(" ".join(rest + fed)):
        raise Blocked("gh api merge" + via)


def check_code(b, rest, fed):
    """A shell, eval or an interpreter: its code is the argument after its code flag (-c, -e), and
    whatever reaches its stdin through a pipe, a heredoc or a here-string, flag or not."""
    if b == "eval":
        return check(" ".join(rest), " via eval")
    flag = SHELL_CODE if b in SHELLS else INTERPRETER_CODE
    k = next((k for k, w in enumerate(rest[:-1]) if flag.fullmatch(w)), None)
    if k is not None and b in SHELLS:
        check(rest[k + 1], " via %s %s" % (b, rest[k]))
    elif k is not None and raw(rest[k + 1]):
        raise Blocked("a merge in %s code" % b)
    if raw(" ".join(fed)):
        raise Blocked("a merge fed to %s" % b)


def main_checkout(d):
    """d as it sits in its repo's main checkout, as swarm.sh's main_checkout; None outside git."""
    try:
        git = lambda *a: subprocess.run(["git", "-C", d, "rev-parse", *a], capture_output=True, text=True,
                                        check=True).stdout.strip()
        top, common = git("--show-toplevel"), git("--path-format=absolute", "--git-common-dir")
        return os.path.dirname(common) + d[len(top):]
    except (OSError, subprocess.CalledProcessError):
        return None


def swarm_dir(d):
    """The nearest folder at or above d with a .claude/swarm/ (swarm.sh init makes it), or None."""
    while d and not os.path.isdir(os.path.join(d, ".claude", "swarm")):
        d = None if d == os.path.dirname(d) else os.path.dirname(d)
    return d


def project(cwd):
    """The swarm project cwd is in: looked for from cwd, then from its main checkout, since a story
    worktree sits beside its repo and has no untracked .claude/swarm/."""
    d = os.path.realpath(cwd)
    return swarm_dir(d) or swarm_dir(main_checkout(d))


def record(d, form):
    """Append the incident to events.tsv in record_event's five fields: time, command, target, the
    actor's pane, outcome. A worktree logs to its main checkout, as swarm.sh does; a log that cannot
    be written never changes the verdict."""
    d = main_checkout(d) or d
    fields = [time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "incident", "-",
              os.environ.get("HERDR_PANE_ID") or "-", "merge-blocked: " + form]
    try:
        os.makedirs(os.path.join(d, ".swarm"), exist_ok=True)
        with open(os.path.join(d, ".swarm", "events.tsv"), "a") as f:
            f.write("\t".join(re.sub(r"[\t\n\r]", " ", x) for x in fields) + "\n")
    except OSError:
        pass


def main():
    try:
        call = json.load(sys.stdin)
        code = (call.get("tool_input") or {}).get("command")
        d = project(call.get("cwd") or os.getcwd())
        if not d or not isinstance(code, str):
            return 0
        check(code)
    except Blocked as b:
        record(d, str(b))
        print(MESSAGE.format(b), file=sys.stderr)
        return 2
    except Exception as e:  # fail closed: the call says merge, and nothing here vouches for it
        print("merge-guard: the check failed (%s), so a call that says merge is refused" % type(e).__name__,
              file=sys.stderr)
        return 2
    return 0


sys.exit(main())
PY

python3 -I -c "${prog}" <<< "${input}"
rc=$?
[[ ${rc} -ne 0 && ${rc} -ne 2 ]] || exit "${rc}"
echo "merge-guard: the check exited ${rc}, so a call that says merge is refused" >&2
exit 2
