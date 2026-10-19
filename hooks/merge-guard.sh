#!/usr/bin/env bash
# merge-guard.sh — the plugin's PreToolUse hook on Bash (hooks/hooks.json). Inside a swarm project
# (a .claude/swarm/ at or above the call's cwd, or above its main checkout when the cwd is a git
# worktree) it stops careless merges, so a PR merges through a lone `swarm.sh merge <PR URL>`; it is
# no defence against deliberate evasion. It reads the tool call's JSON on stdin and exits 2, naming
# the form, on gh pr merge, gh api .../pulls/<n>/merge, a graphql mergePullRequest, any of them in
# code handed to a shell or an interpreter (-c, eval, a heredoc, a here-string, a pipe) or written
# to a file, and on swarm.sh merge joined to another command. A mention in echo, printf or grep
# passes. It also exits 2 on commands that lose work: a cd followed by ; (outside $( ), and not in a
# while, until or if condition), a git
# checkout that overwrites uncommitted changes and, in a swarm agent's session (SWARM_AGENT set), git
# checkout, switch, restore, reset --hard, stash or clean run in the project's main checkout (the
# call's cwd, a cd or a -C); stash list and show and clean -n pass. A swarm agent's pkill, killall or
# kill $(pgrep ...) / $(pidof ...) is refused too, as is a kill of PID 0 or a negative one (every
# process, or a group): either can hit another session's process. So is its gh pr checks --watch, or a
# gh pr checks in a while/until loop's condition or body (not a while read loop): swarm.sh wait-pr exits on red, a conflict and a deadline.
# Those rules fail open on an error of their own. Each block appends an incident line, `merge-blocked: <form>` or `guard-blocked:
# <form>`, to the project's .swarm/events.tsv. Outside a swarm project it allows all.
set -uo pipefail

input="$(cat)"
# The rules read the command alone, never the call's cwd, transcript path or description. Input with
# no command string to find is read whole, so it still fails closed if it says merge.
command="${input}"
re='"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"'
[[ ${input} =~ ${re} ]] && command="${BASH_REMATCH[1]}"
# Fast path: a command that never says merge, nor git, cd or a kill as a word, nor both gh and checks, not even through quotes and
# backslashes (mer"ge, me''rge, mer\ge; JSON's \n and \t split words), has nothing to block.
plain="$(printf '%s' "${command}" | sed 's/\\[nrt]/ /g' | tr -d "\"'\\\\")"
word='(^|[^[:alnum:]_])(git|cd|kill|pkill|killall)([^[:alnum:]_]|$)'
gh='(^|[^[:alnum:]_])gh([^[:alnum:]_]|$)'; checks='(^|[^[:alnum:]_])checks([^[:alnum:]_]|$)'
if [[ ${plain} == *[Mm][Ee][Rr][Gg][Ee]* ]]; then says=merge
elif [[ ${plain} =~ ${word} ]] || [[ ${plain} =~ ${gh} && ${plain} =~ ${checks} ]]; then says=other
else exit 0
fi
# A command that says merge fails closed: anything but the guard's own verdict refuses it. One that
# only says git, cd, a kill or gh and checks fails open, since those rules save work rather than enforce the merge route.
command -v python3 >/dev/null || { [[ ${says} == merge ]] || exit 0; echo "merge-guard: python3 is missing, so a call that says merge is refused" >&2; exit 2; }

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
OPENERS = {"do", "then", "else"}  # words that can start a line before its command
# Words before a command in a condition or a group too; only the loop rule reads past them, so the
# cd and git rules never see a condition's cd or git.
LEADS = OPENERS | {"while", "until", "!", "if", "elif", "{"}
LOOPS = {"while", "until"}  # loops that poll their condition; for and select open a loop too, closed by done
MOVES = {"checkout", "switch", "restore", "stash", "clean"}  # git subcommands that move or reset a checkout
PATTERN_KILLS = {"pkill", "killall"}
BY_NAME = re.compile(r"(\$\(|`)\s*(pgrep|pidof)\b")  # kill $(pgrep ...): PIDs found by a pattern
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
    """gh pr merge, or gh api with a merge in its words or in what is fed to it."""
    args = gh_words(rest)
    if args[:2] == ["pr", "merge"]:
        raise Blocked("gh pr merge" + via)
    if args[:1] == ["api"] and raw(" ".join(rest + fed)):
        raise Blocked("gh api merge" + via)


def gh_words(rest):
    """gh's words with its flags dropped, and the value of a separate -R or --repo (-Ro/r is one flag)."""
    args, value = [], False
    for w in rest:
        if not value and not w.startswith("-"):
            args.append(w)
        value = not value and w in ("-R", "--repo")
    return args


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


def guard(code, cwd):
    """Raise Unsafe on a command that can lose work: a cd before ;, git checkout over a file with
    uncommitted changes and, in a swarm agent's session, git moving or resetting the main checkout
    and a kill by pattern or a CI wait of its own."""
    home = cwd if os.environ.get("SWARM_AGENT") else None
    sh = Shell(code.strip())
    sh.parse()
    d = cwd  # where the next command runs; None once a cd goes where this cannot tell
    loops = []  # the loops open around the command, innermost last
    for cmd in sh.cmds:
        lead = list(itertools.takewhile(lambda w: ASSIGNMENT.match(w) or w in LEADS, cmd["words"]))
        inner = cmd["words"][len(lead):]
        opens = [w for w in lead if w in LOOPS] + inner[:1] * (inner[:1] in (["for"], ["select"]))
        if opens and [w for w in lead if not ASSIGNMENT.match(w)][-1:] == opens[-1:] and inner[:1] == ["read"]:
            opens[-1] = "read"  # while read: one pass per line read, not a poll
        loops += opens
        if inner[:1] == ["done"]:
            loops = loops[:-1]
        args = list(itertools.dropwhile(lambda w: ASSIGNMENT.match(w) or w in OPENERS, cmd["words"]))
        name = os.path.basename(args[0]) if args else ""
        if name == "cd" and not cmd["nested"]:  # a cd in $( ) moves nothing outside it
            if cmd["end"] == ";":
                raise Unsafe("cd before ;", "If the cd fails, the rest runs where you were: use `cd <dir> || exit 1 &&`")
            # ponytail: no subshell scoping, so a cd inside ( ) still moves d for the commands after it.
            t = next((w for w in args[1:] if w == "-" or not w.startswith("-")), "~")
            d = None if t == "-" else at(d, t)
        elif name == "git":
            check_git(d, args[1:], home)
        elif home and (name in PATTERN_KILLS or (name == "kill" and kills_others(args[1:]))):
            raise Unsafe("pattern-kill", "A kill by name, of PID 0 or of a negative PID can hit another session's process: kill the PID you started ($!)")
        elif home and inner and os.path.basename(inner[0]) == "gh" and gh_words(inner[1:])[:2] == ["pr", "checks"] and (LOOPS & set(loops) or any(w.startswith("--watch") for w in inner)):
            raise Unsafe("gh pr checks loop", "Wait on CI with `swarm.sh wait-pr <PR URL>` in the background: it exits on red, on a conflict and at a deadline")


def kills_others(words):
    """Whether kill <words> signals PIDs found by a pattern, or 0 or a negative PID: every process the
    user owns, or a whole group."""
    if words[:1] in (["-s"], ["-n"]):
        words = words[2:]
    elif words[:1] and words[0].startswith("-") and words[0] != "--":
        words = words[1:]  # the signal: -9, -KILL, -s9
    pids = words[1:] if words[:1] == ["--"] else words
    return any(BY_NAME.search(w) or re.fullmatch(r"0|-\d+", w) for w in pids)


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
    if home and not reads_only(sub, rest) and (sub in MOVES or (sub == "reset" and "--hard" in rest)):
        here, ours = git_dirs(d), git_dirs(home)
        if here and ours and here[0] == ours[1]:
            raise Unsafe("git %s in the main checkout" % sub,
                         "A swarm agent never moves or resets the project's main checkout: run it in a worktree")
    if sub == "checkout" and drops_changes(d, rest):
        raise Unsafe("git checkout over uncommitted changes",
                     "git checkout drops them: back up with cp, then restore from the copy")


def reads_only(sub, rest):
    """git stash list or show, or git clean -n or --dry-run: they change nothing."""
    if sub == "stash":
        return rest[:1] in (["list"], ["show"])
    return sub == "clean" and any(w == "--dry-run" or re.fullmatch(r"-[A-Za-z]*n[A-Za-z]*", w) for w in rest)


def drops_changes(d, rest):
    """Whether git checkout <rest>, run in d, overwrites a change: an unstaged one, or a staged one
    too when it checks out from a commit (HEAD -- f, main f). A conflicted path is not counted."""
    if "--" in rest:
        k = rest.index("--")
        src, paths = [w for w in rest[:k] if not w.startswith("-")], rest[k + 1:]
    else:
        paths = [w for w in rest if not w.startswith("-")]
        src = paths[:1]  # git reads the first word as a commit when it names one
    if not paths:
        return False
    commit = any(git(d, "rev-parse", "--verify", "--quiet", w + "^{tree}") for w in src)
    # --no-optional-locks: a status that refreshes the index would take index.lock from another git.
    status = (git(d, "--no-optional-locks", "status", "--porcelain", "--untracked-files=no", "--", *paths)
              or "").splitlines()
    return any(line[:2] not in UNMERGED and (commit or line[1] != " ") for line in status)


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


def main_checkout(d):
    """d as it sits in its repo's main checkout, as swarm.sh's main_checkout; None outside git."""
    dirs = git_dirs(d)
    return dirs and dirs[1] + d[len(dirs[0]):]


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


def record(d, outcome):
    """Append the incident to events.tsv in record_event's five fields: time, command, target, the
    actor's pane, outcome. A worktree logs to its main checkout, as swarm.sh does; a log that cannot
    be written never changes the verdict."""
    d = main_checkout(d) or d
    fields = [time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "incident", "-",
              os.environ.get("HERDR_PANE_ID") or "-", outcome]
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
        cwd = os.path.realpath(call.get("cwd") or os.getcwd())
        d = project(cwd)
        if not d or not isinstance(code, str):
            return 0
        check(code)
        try:
            guard(code, cwd)
        except Unsafe:
            raise
        except Exception:  # the lose-work rules fail open: an error of theirs never refuses a call
            pass
    except Blocked as b:
        record(d, "%s: %s" % (b.kind, b.args[0]))
        print(b.message(), file=sys.stderr)
        return 2
    except Exception as e:  # fail closed when the call says merge: nothing here vouches for it
        if sys.argv[1:] != ["merge"]:
            return 0
        print("merge-guard: the check failed (%s), so a call that says merge is refused" % type(e).__name__,
              file=sys.stderr)
        return 2
    return 0


sys.exit(main())
PY

python3 -I -c "${prog}" "${says}" <<< "${input}"
rc=$?
[[ ${rc} -ne 0 && ${rc} -ne 2 ]] || exit "${rc}"
[[ ${says} == merge ]] || exit 0
echo "merge-guard: the check exited ${rc}, so a call that says merge is refused" >&2
exit 2
