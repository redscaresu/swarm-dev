#!/usr/bin/env bash
# merge-guard.sh — the plugin's PreToolUse hook on Bash (hooks/hooks.json). Inside a swarm project
# (a .claude/swarm/config at or above the call's cwd) a lone `swarm.sh merge <PR URL>` is the only
# way to merge a PR. It reads the tool call's JSON on stdin and exits 2, naming the form, on gh pr
# merge, gh api .../pulls/<n>/merge, a graphql mergePullRequest, any of them in code handed to a shell
# or an interpreter (-c, eval, a heredoc, a pipe) or written to a file, and on swarm.sh merge joined
# to another command. A mention in echo, printf or grep passes. It also exits 2 on commands that lose
# work: a cd followed by ;, git checkout over a file with uncommitted changes and, in a swarm agent's
# session (SWARM_AGENT set), git checkout, switch, restore, reset --hard, stash or clean run in the
# project's main checkout (the call's cwd, a cd or a -C). Each block appends an incident line,
# `merge-blocked: <form>` or `guard-blocked: <form>`, to the project's .swarm/events.tsv. Outside a
# swarm project it allows all.
set -uo pipefail

input="$(cat)"
# Fast path: a call that never says merge, git or cd has nothing to block.
case "${input}" in *[Mm][Ee][Rr][Gg][Ee]*|*git*|*cd*) ;; *) exit 0 ;; esac

HOOK_INPUT="${input}" exec python3 -I - <<'PY'
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
OPENERS = {"do", "then", "else", "{"}  # words that can start a line before its command
MOVES = {"checkout", "switch", "restore", "stash", "clean"}  # git subcommands that move or reset a checkout
UNMERGED = {"DD", "AU", "UD", "UA", "DU", "AA", "UU"}  # git status codes of a conflict, which --ours/--theirs resolves
PIPES = itertools.count()
MESSAGE = """merge-guard: blocked ({}). In a swarm project only `swarm.sh merge <PR URL>`, run alone,
merges a PR (docs/reference.md § Merging). Text that only mentions a merge, such as a PR body, can go
through the Write tool or --body "$(cat <<'EOF' ... EOF)"."""


class Blocked(Exception):
    """A merge any way but a lone swarm.sh merge; its argument names the form."""
    kind = "merge-blocked"

    def message(self):
        return MESSAGE.format(self.args[0])


class Unsafe(Blocked):
    """A command that can lose work; its arguments name the form and the fix."""
    kind = "guard-blocked"

    def message(self):
        return "merge-guard: blocked ({}). {}.".format(*self.args)


class Shell:
    """Just enough of a shell parser to find the simple commands in a Bash call, those in $( ),
    backticks and process substitutions included. Each is a dict: words (quotes removed), bodies (its
    heredocs and here-strings), file (it writes a file), pipe (its pipeline), nested (in a
    substitution) and end (the operator after it)."""

    def __init__(self, s):
        self.s, self.i, self.cmds, self.heredocs = s, 0, [], []

    def new(self, nested, pipe=None):
        cmd = {"words": [], "bodies": [], "file": False, "nested": nested, "end": "",
               "pipe": next(PIPES) if pipe is None else pipe}
        self.cmds.append(cmd)
        return cmd

    def parse(self, nested=False, closes=False):
        """Read commands to the end, or past the ) that closes the $( ) being read (closes)."""
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
                cmd = self.op(cmd, nested)
            else:
                w = self.word()
                if not (w.isdigit() and self.s[self.i:self.i + 1] in ("<", ">")):  # else a redirect's fd
                    cmd["words"].append(w)

    def op(self, cmd, nested):
        two = self.s[self.i:self.i + 2]
        cmd["end"] = two if two in ("&&", "||", ";;", "|&") else two[:1]
        self.i += len(cmd["end"])
        if cmd["end"] == "\n":
            self.read_heredocs()
        return self.new(nested, cmd["pipe"] if cmd["end"] in ("|", "|&") else None)

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

    def dquote(self):
        out = ""
        while self.i < len(self.s):
            c = self.s[self.i]
            self.i += 1
            if c == '"':
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
        target = self.word()
        if op == "<<<":
            cmd["bodies"].append(target)
        elif op.startswith("<<"):
            self.heredocs.append((target, op == "<<-", cmd))
        elif ">" in op and target not in QUIET and not (op.endswith("&") and re.fullmatch(r"\d*-?", target)):
            cmd["file"] = True

    def read_heredocs(self):
        for delim, strip, cmd in self.heredocs:
            body = []
            while self.i < len(self.s):
                j = self.s.find("\n", self.i)
                j = len(self.s) if j < 0 else j
                line, self.i = self.s[self.i:j], j + 1
                if (line.lstrip("\t") if strip else line) == delim:
                    break
                body.append(line)
            cmd["bodies"].append("\n".join(body))
        self.heredocs = []


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
    if cmd["file"] and RAW.search(" ".join([text(cmd)] + fed)):
        raise Blocked("a merge written to a file")
    if not args or os.path.basename(args[0]) in MENTIONS:
        return
    for i, w in enumerate(args):
        b, rest = os.path.basename(w), args[i + 1:]
        if b == "gh":
            check_gh(rest, via)
        elif b == "swarm.sh" and rest[:1] == ["merge"] and joined:
            raise Blocked("swarm.sh merge joined to another command" + via)
        elif b == "tee" and RAW.search(" ".join(fed)):
            raise Blocked("a merge written to a file")
        elif b in SHELLS or b == "eval" or INTERPRETER.fullmatch(b):
            check_code(b, rest, fed)


def check_gh(rest, via):
    args = [w for k, w in enumerate(rest) if w not in ("-R", "--repo") and rest[k - 1:k] not in (["-R"], ["--repo"])
            and not w.startswith("--repo=")]
    if args[:2] == ["pr", "merge"]:
        raise Blocked("gh pr merge" + via)
    if args[:1] == ["api"] and RAW.search(" ".join(args)):
        raise Blocked("gh api merge" + via)


def check_code(b, rest, fed):
    """A shell, eval or an interpreter: its code is in an argument, or on stdin when no flag names it."""
    if b == "eval":
        return check(" ".join(rest), " via eval")
    flag = SHELL_CODE if b in SHELLS else INTERPRETER_CODE
    k = next((k for k, w in enumerate(rest) if flag.fullmatch(w)), None)
    if b in SHELLS and k is not None and k + 1 < len(rest):
        check(rest[k + 1], " via %s %s" % (b, rest[k]))
    elif b not in SHELLS and RAW.search(" ".join(rest)):
        raise Blocked("a merge in %s code" % b)
    if k is None and RAW.search(" ".join(fed)):
        raise Blocked("a merge fed to %s" % b)


def guard(code, cwd):
    """Raise Unsafe on a command that can lose work: a cd before ;, git checkout over a file with
    uncommitted changes and, in a swarm agent's session, git moving or resetting the main checkout."""
    home = cwd if os.environ.get("SWARM_AGENT") else None
    sh = Shell(code.strip())
    sh.parse()
    d = cwd  # where the next command runs; None once a cd goes where this cannot tell
    for cmd in sh.cmds:
        args = list(itertools.dropwhile(lambda w: ASSIGNMENT.match(w) or w in OPENERS, cmd["words"]))
        name = os.path.basename(args[0]) if args else ""
        if name == "cd" and cmd["end"] == ";":
            raise Unsafe("cd before ;", "If the cd fails, the rest runs where you were: use `cd <dir> || exit 1 &&`")
        if name == "cd" and not cmd["nested"]:
            # ponytail: no subshell scoping, so a cd inside ( ) still moves d for the commands after it.
            t = next((w for w in args[1:] if w == "-" or not w.startswith("-")), "~")
            d = None if t == "-" else at(d, t)
        elif name == "git":
            check_git(d, args[1:], home)


def check_git(d, words, home):
    """One git command run from d; home is the call's cwd in a swarm agent's session, else None."""
    while words[:1] and words[0].startswith("-"):  # git's own options, before the subcommand
        if words[0] in ("-C", "-c") and len(words) > 1:
            d = at(d, words[1]) if words[0] == "-C" else d
            words = words[1:]
        words = words[1:]
    if d is None or not words:
        return
    sub, rest = words[0], words[1:]
    if home and (sub in MOVES or (sub == "reset" and "--hard" in rest)):
        here, ours = git_dirs(d), git_dirs(home)
        if here and ours and here[0] == ours[1]:
            raise Unsafe("git %s in the main checkout" % sub,
                         "A swarm agent never moves or resets the project's main checkout: run it in a worktree")
    if sub == "checkout":
        paths = rest[rest.index("--") + 1:] if "--" in rest else [w for w in rest if not w.startswith("-")]
        status = (git(d, "status", "--porcelain", "--untracked-files=no", "--", *paths) or "").splitlines() if paths else []
        if any(line[:2] not in UNMERGED for line in status):
            raise Unsafe("git checkout over uncommitted changes",
                         "git checkout drops them: back up with cp, then restore from the copy")


def at(d, path):
    """path from directory d, with ~ and $VARs expanded; None when that cannot be told."""
    p = os.path.expandvars(os.path.expanduser(path))
    if "$" in p or "`" in p or (d is None and not os.path.isabs(p)):
        return None
    return os.path.normpath(os.path.join(d or "/", p))


def git(d, *args):
    """git's output, run in d, or None when it fails."""
    try:
        return subprocess.run(["git", "-C", d, *args], capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None


def git_dirs(d):
    """The checkout d is in and its repository's main checkout, or None outside a git repository."""
    out = git(d, "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir")
    if not out:
        return None
    top, common = out.split("\n")[:2]
    return os.path.realpath(top), os.path.realpath(os.path.dirname(common))


def project(cwd):
    """The directory holding .claude/swarm/config at or above cwd, or None."""
    d = os.path.realpath(cwd)
    while not os.path.isfile(os.path.join(d, ".claude", "swarm", "config")):
        if d == os.path.dirname(d):
            return None
        d = os.path.dirname(d)
    return d


def record(d, outcome):
    """Append the incident to events.tsv in record_event's five fields: time, command, target, the
    actor's pane, outcome. A worktree logs to its main checkout, as swarm.sh does; a log that cannot
    be written never changes the verdict."""
    dirs = git_dirs(d)
    if dirs:
        d = dirs[1] + d[len(dirs[0]):]
    fields = [time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "incident", "-",
              os.environ.get("HERDR_PANE_ID") or "-", outcome]
    try:
        os.makedirs(os.path.join(d, ".swarm"), exist_ok=True)
        with open(os.path.join(d, ".swarm", "events.tsv"), "a") as f:
            f.write("\t".join(re.sub(r"[\t\n\r]", " ", x) for x in fields) + "\n")
    except OSError:
        pass


def main():
    call = json.loads(os.environ["HOOK_INPUT"])
    code = (call.get("tool_input") or {}).get("command")
    cwd = os.path.realpath(call.get("cwd") or os.getcwd())
    d = project(cwd)
    if not d or not isinstance(code, str):
        return 0
    try:
        check(code)
        guard(code, cwd)
    except Blocked as b:
        record(d, "%s: %s" % (b.kind, b.args[0]))
        print(b.message(), file=sys.stderr)
        return 2
    return 0


sys.exit(main())
PY
