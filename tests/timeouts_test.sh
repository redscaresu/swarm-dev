#!/usr/bin/env bash
# timeouts_test.sh — in the shell files of bin/ and hooks/, a call that can wait forever names its
# bound in the same command. The calls are `curl`, `gh run download`, `gh run view ... --log` and
# herdr's blocking ones (`herdr ... --wait`, `herdr agent wait`, `herdr pane wait-output`), also
# behind if/elif/while/then/do, exec, command, time, nohup, env, a path and a `${VAR:-herdr}` command
# word. A bound is
#   - `within` as the command's prefix: a perl alarm, so it also runs on stock macOS. merge.sh's takes
#     <seconds> first (below 1 counts as 1); hooks/lead-stop.sh's takes the command and runs against
#     its own ${deadline}. A file that defines `within` has that one (the reader tells them apart by
#     the definition: one that passes `-- "$@"` takes seconds). bin/swarm.sh and bin/lib/*.sh have
#     merge.sh's, as swarm.sh sources them all together; so has any file that sources merge.sh. In
#     another file (other hooks, gh-shim) `within` is not there;
#   - `timeout <seconds>` as the prefix (coreutils; stock macOS has none, so prefer `within`; a
#     zero turns it off);
#   - `--max-time`, `-m` (also inside a bundle, `-sm 5`) or `--timeout` as an option of its own, for
#     curl and herdr; the last one wins and a zero is no bound. gh has no such flag, so a gh call
#     takes a prefix bound only;
#   - or a trailing comment `# no-timeout: <reason>`, which covers the calls of the line's last
#     list or pipeline (commands joined by || && |), not those before a ;.
# The file is read as shell: quotes (across lines), \ continuations, comments, and the commands left
# after splitting on ; | & ( ) and newlines. A $( ) or backtick substitution is a command of its own
# and a bare $() in the one around it; $(( )) is arithmetic and one word. A bound on another command, in a string or comment, or as an
# option's value does not count. An escaped backtick (\`) is text. A heredoc body is scanned line by
# line like code, so a prose line that starts with a call fails, the safe way round. The files are
# the ones git tracks under bin/ and hooks/ that end in .sh or start with a sh or bash shebang (as
# loose_match_test.sh's); Python files are not scanned.
# shellcheck disable=SC2016,SC1003 # the fixtures are shell text, not expansions
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export HOME="${dir}/home"   # under its own root, so parallel runs share no ~

# untimed <file>... — one `file:line: command` per call that names no bound; a file the reader ends
# inside a quote or $( ) in is one line too, as the reader has then misread it.
untimed() {
  python3 -I - "$@" <<'EOF'
import re, shlex, sys

KEYWORD = r'(?:!|then|do|else|elif|if|while|until|\{|exec|command|time|nohup)\s+'
ENV = r'env\s+(?:(?:-i|-u\s+\S+|-\S+)\s+)*'
ASSIGN = r'[A-Za-z_]\w*=(?:"[^"]*"|\'[^\']*\'|[^\s"\']*)\s+'
PREFIX = re.compile('(?:' + KEYWORD + '|' + ENV + '|' + ASSIGN + ')')
SECS_ANY = r'(?:\d\S*|"[^"]*"|\'[^\']*\'|\$\S*)'   # one word: a number, a quoted word or an expansion
ZERO = r'0+(?:\.0*)?[smhd]?'
COMMAND_WORD = r'^"?\$\{\w+:-(curl|gh|herdr)\}"?(?=\s|$)'
CALLS = [r'curl(\s|$)', r'gh\s+run\s+download\b', r'gh\s+run\s+view\b.*\s--log',
         r'herdr\s+(agent\s+wait|pane\s+wait-output)\b', r'herdr\s.*\s--wait(\s|=|$)']
BOUND = re.compile(r'--(?:max-time|timeout)(=.*)?')
# Per command, the options that take a value, so that the word after one is not an option. A
# value-taking option missing here can hide a bound; add it. curl's -n -p -a -j -q take none.
VALUE_OPTS = {
    "curl": set('''-H --header -d --data --data-raw --data-binary --data-urlencode -o --output -w
        --write-out -X --request -u --user -A --user-agent -e --referer -b --cookie -c --cookie-jar -F
        --form -T --upload-file -x --proxy'''.split()),
    "herdr": set('--until --match --source --lines --workspace --tab --pane'.split()),
}
CURL_VALUE_LETTERS = set("HdowXuAebcFTx")
HINT = ("bound it with `within <seconds> cmd` (bin/swarm.sh and bin/lib/*.sh have merge.sh's within; "
        "hooks/lead-stop.sh's own takes the command, `within cmd`; in another file define it or "
        "source merge.sh; stock macOS has no timeout), or --max-time/-m/--timeout as an option (curl and herdr; gh has no timeout flag, "
        "so a gh call takes only the prefix), or end the line with `# no-timeout: <reason>`")


def unbounded(cmd, within_kind):
    s = cmd.strip()
    m = PREFIX.match(s)
    while m:
        s = s[m.end():]
        m = PREFIX.match(s)
    m = re.match(r'(within|timeout)\s+', s)
    if m:
        rest = s[m.end():]
        if m.group(1) == "within" and within_kind == "command" and rest:
            return False
        d = re.match(SECS_ANY + r'\s+(?=\S)', rest)
        zero = d and re.fullmatch(ZERO, d.group(0).strip().strip('"\''))   # timeout(1) turns off at 0
        if d and ((m.group(1) == "within" and within_kind == "seconds") or (m.group(1) == "timeout" and not zero)):
            return False
        s = re.sub(r'^(?:' + SECS_ANY + r'\s+)?', '', rest)
    s = re.sub(COMMAND_WORD, r'\1', re.sub(r'^\S*/(?=\S)', '', s))
    if not any(re.match(c, s) for c in CALLS):
        return False
    if s.startswith("gh"):
        return True
    try:
        words = shlex.split(s)
    except ValueError:
        words = s.split()
    opts = VALUE_OPTS.get(words[0], set())   # words[0] is curl or herdr: CALLS match the whole word
    value = None   # the last bound option wins, as in curl
    for k, w in enumerate(words):
        m, number = BOUND.fullmatch(w), None
        if m:
            number = (m.group(1) or "").lstrip("=")
        elif words[0] == "curl":
            m = re.fullmatch(r'-([A-Za-z]*)m(\d*\.?\d*)', w)   # also in a bundle: -sm 5, -fsSLm5
            number = m.group(2) if m and not CURL_VALUE_LETTERS & set(m.group(1)) else None
        if number is None or words[k - 1] in opts:
            continue
        value = number or (words[k + 1] if k + 1 < len(words) else "")
    return value is None or re.fullmatch(ZERO, value) is not None


class Scan:
    """One pass over a file's text; quote and $( ) state carry across lines. A finding is an
    unbounded call not covered by an opt-out comment on its line."""

    def __init__(self, text, within_kind, ln=1):
        self.t, self.within_kind, self.ln, self.i = text, within_kind, ln, 0
        self.bufs, self.starts, self.segs = [""], [ln], [0]
        self.kinds, self.qs, self.q, self.seg = [], [], None, 0
        self.line, self.comment, self.found, self.heredocs = [], "", [], []

    def add(self, s):
        if not self.bufs[-1].strip() and s.strip():
            self.starts[-1] = self.ln
        self.bufs[-1] += s

    def emit(self):
        if self.bufs[-1].strip() and unbounded(self.bufs[-1], self.within_kind):
            self.line.append((self.segs[-1], self.starts[-1], " ".join(self.bufs[-1].split())))
        self.bufs[-1] = ""

    def settle(self):
        """End of a physical line: an opt-out comment covers the calls of the line's last command."""
        covered = re.match(r'#\s*no-timeout:\s*\S', self.comment)
        self.found += [(ln, c) for seg, ln, c in self.line if not (covered and seg == self.seg)]
        self.line, self.comment = [], ""

    def push(self, kind):
        self.bufs.append("")
        self.starts.append(self.ln)
        self.segs.append(self.seg)
        self.kinds.append(kind)
        self.qs.append(self.q)
        self.q = None

    def pop(self):
        self.emit()
        self.bufs.pop(), self.starts.pop(), self.segs.pop(), self.kinds.pop()
        self.q = self.qs.pop()
        self.add("$()")

    def split(self, same_list=False):
        """End a command. A ; or & starts a new list; | || && keep the next command in this one."""
        self.emit()
        if not self.kinds and not same_list:
            self.seg += 1
            self.segs[0] = self.seg

    def newline(self):
        if self.q is not None:
            self.add("\n")
            return
        self.emit()
        self.settle()
        if not self.kinds:
            self.seg += 1
            self.segs[0] = self.seg
        if self.heredocs:
            self.body()

    def body(self):
        """Read the heredoc bodies that start after this line, each line on its own."""
        for delim in self.heredocs:
            while self.i < len(self.t):
                j = self.t.find("\n", self.i)
                j = len(self.t) if j < 0 else j
                row, self.i = self.t[self.i:j], j + 1
                if row.strip() != delim:
                    sub = Scan(row + "\n", self.within_kind, self.ln)
                    sub.run()
                    self.found += sub.found
                self.ln += 1
                if row.strip() == delim:
                    break
        self.heredocs = []

    def run(self):
        t, n = self.t, len(self.t)
        while self.i < n:
            i, c = self.i, t[self.i]
            self.i += 1
            if c == "\n":
                self.ln += 1
                self.newline()
            elif self.q == "'":
                self.add(c)
                self.q = None if c == "'" else "'"
            elif c == "\\":
                if self.i < n and t[self.i] == "\n":
                    self.i += 1
                    self.ln += 1
                else:
                    self.add(t[i:i + 2])
                    self.i += 1
            elif c == "#" and self.q is None and (i == 0 or t[i - 1] in " \t\n;|&()"):
                j = t.find("\n", i)
                j = n if j < 0 else j
                self.comment, self.i = t[i:j], j
            elif c == "'" and self.q is None:
                self.add(c)
                self.q = "'"
            elif c == '"':
                self.add(c)
                self.q = None if self.q == '"' else '"'
            elif t.startswith("$((", i):
                depth, j = 0, i + 1
                while j < n and (depth or j == i + 1):
                    depth += (t[j] == "(") - (t[j] == ")")
                    j += 1
                self.add("$(())")
                self.i = j
            elif t.startswith("$(", i):
                self.push("$(")
                self.i += 1
            elif c == "`":
                if self.kinds and self.kinds[-1] == "`":
                    self.pop()
                else:
                    self.push("`")
            elif self.q is not None:
                self.add(c)
            elif c == ")" and self.kinds and self.kinds[-1] == "$(":
                self.pop()
            elif c == "<" and t.startswith("<<", i) and not t.startswith("<<<", i) and (
                    m := re.match(r'<<-?\s*(["\']?)\\?([A-Za-z_]\w*)\1', t[i:i + 80])):
                self.heredocs.append(m.group(2))
                self.i += m.end() - 1
            elif c == "|" or (c == "&" and "&" in t[i - 1:i] + t[i + 1:i + 2] and ">" not in t[i - 1:i]):
                self.split(same_list=True)
            elif c in ";()" or (c == "&" and t[i - 1:i] != ">" and t[i + 1:i + 2] != ">"):
                self.split()
            else:
                self.add(c)
        open_at_end = self.q is not None or bool(self.kinds)
        while self.kinds:
            self.pop()
        self.emit()
        self.settle()
        return open_at_end


for path in sys.argv[1:]:
    text = open(path, errors="replace").read()
    sourced = re.search(r'/bin/(?:lib/[^/]+\.sh|swarm\.sh)$', path) or re.search(r'^\s*(?:source|\.)\s+\S*merge\.sh', text, re.M)
    within_kind = "seconds" if sourced else None   # swarm.sh sources every bin/lib file with merge.sh
    defined = re.search(r'^\s*within\(\)[^\n]*', text, re.M)
    if defined:
        body = defined.group(0) if defined.group(0).rstrip().endswith("}") else text[defined.start():].split("\n}", 1)[0]
        within_kind = "seconds" if '-- "$@"' in body else "command"
    scan = Scan(text, within_kind)
    open_at_end = scan.run()
    for ln, cmd in scan.found:
        print(f"{path}:{ln}: {cmd}  <- {HINT}")
    if open_at_end:
        print(f"{path}: the reader ends inside a quote or $( ), so it has misread this file")
EOF
}

W_SECONDS='within() { perl -e 1 -- "$@"; }'   # merge.sh's: <seconds> first
W_COMMAND='within() { perl -e 1 "${deadline}" "$@"; }'   # hooks/lead-stop.sh's: the command first

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
flagged_at() { # <path under the fixture root> <line>... — how many findings untimed prints, or crash
  local out; mkdir -p "$(dirname "${dir}/$1")"; local at="$1"; shift
  printf '%s\n' "$@" > "${dir}/${at}"
  out="$(untimed "${dir}/${at}")" || { echo crash; return; }
  printf '%s\n' "${out}" | grep -c . || true
}
flagged() { flagged_at f.sh "$@"; } # <line>... — the same for a file of no particular place

check "a bare curl is flagged" 1 "$(flagged 'x="$(curl -fsSL "$URL")"')"
check "a bare gh run download is flagged" 1 "$(flagged '  gh run download "$id" --dir out')"
check "a bare gh run view --log-failed is flagged" 1 "$(flagged 'log="$(gh run view "$id" --log-failed)"')"
check "a prose word that starts with herdr is not a call, and does not crash the scan" 0 "$(flagged 'cat <<EOF' "herdr's pane --wait for it" 'EOF')"
check "a bare herdr --wait is flagged" 1 "$(flagged 'herdr agent prompt a hi --wait --until idle')"
check "a bare herdr agent wait is flagged" 1 "$(flagged 'herdr agent wait "$t" --until idle')"
check "a bare herdr pane wait-output is flagged" 1 "$(flagged 'herdr pane wait-output "$p" --match ready')"
check "a bare call in backticks is flagged" 1 "$(flagged 'x=`curl "$U"`')"
check "a bare call after elif is flagged" 1 "$(flagged 'elif curl "$URL"; then')"
check "a bare call behind exec, command, env, nohup, time or a path is flagged" 8 "$(flagged \
  'exec curl "$U"' 'command curl "$U"' 'env FOO=1 curl "$U"' 'env -u X FOO=1 curl "$U"' \
  'nohup gh run download 1' 'time curl "$U"' 'exec env FOO=1 curl "$U"' '/usr/bin/curl "$U"')"
check "a bare call is flagged once, not once per line, when it continues" 1 "$(flagged 'gh run download "$id" \' '  --dir out')"
check "a bare call on a file's last line ending in a backslash is flagged" 1 "$(printf 'curl "$U" \\' > "${dir}/f.sh"; untimed "${dir}/f.sh" | grep -c . || true)"
check "a call after a comment ending in a backslash is flagged" 1 "$(flagged '# note \' 'curl "$U"')"
check "a call after a double-quoted string that spans lines is flagged" 1 "$(flagged 'x="a' 'b"; curl "$U"')"
check "a call inside a multi-line substitution is flagged" 1 "$(flagged 'x="$(' '  curl "$U"' ')"')"
check "a call before a lone & is flagged" 1 "$(flagged 'curl "$U" & curl --max-time 5 "$V"')"
check "--max-time passes" 0 "$(flagged 'curl -fsSL --max-time 5 "$URL"')"
check "-m passes curl" 0 "$(flagged 'curl -m 5 "$URL"' 'curl -m5 "$URL"' 'curl -m0.5 "$URL"')"
check "timeout as the prefix passes" 0 "$(flagged 'timeout 30 gh run download "$id"')"
check "within, defined in the file, passes" 0 "$(flagged "${W_SECONDS}" 'within 30 gh run view "$id" --log-failed')"
check "within, defined in the file, passes after an assignment and with a variable" 0 \
  "$(flagged "${W_SECONDS}" 'x="$(FOO=1 within "${left}" curl "$U")"')"
check "a duration of \$((...)) or a quoted substitution is one word" 0 \
  "$(flagged "${W_SECONDS}" 'within $((e - n)) curl "$U"' 'within "$((e - n))" curl "$U"' 'within "$(release_left "$e")" gh api x' 'timeout $((e - n)) curl "$U"')"
check "within, sourced from merge.sh, passes" 0 "$(flagged 'source "${LIB}/merge.sh"' 'within 30 curl "$U"')"
check "within in a file that neither defines nor sources it is flagged" 1 "$(flagged 'within 30 curl "$U"')"
check "within in bin/lib/*.sh and bin/swarm.sh is merge.sh's, as swarm.sh sources them together" 00 \
  "$(flagged_at bin/lib/x.sh 'within 30 gh run view "$id" --log-failed')$(flagged_at bin/swarm.sh 'within 30 curl "$U"')"
check "within in another hook or gh-shim is flagged" 11 \
  "$(flagged_at hooks/x.sh 'within 30 curl "$U"')$(flagged_at bin/gh-shim/gh 'within 30 curl "$U"')"
check "bin/lib's within still needs its seconds" 1 "$(flagged_at bin/lib/x.sh 'within curl "$U"')"
check "within with no seconds is flagged" 1 "$(flagged "${W_SECONDS}" 'within curl "$U"')"
check "timeout 0 is no bound in a file that has merge.sh's within" 1 "$(flagged "${W_SECONDS}" 'timeout 0 curl "$U"')"
check "within with a zero is a 1 s bound in merge.sh's" 0 "$(flagged "${W_SECONDS}" 'within 0 curl "$U"')"
check "within, the lead-stop.sh kind, takes the command directly" 0 \
  "$(flagged "${W_COMMAND}" 'within curl "$U"' 'within "${HERDR_BIN_PATH:-herdr}" agent wait x')"
check "--timeout on a continuation line passes" 0 "$(flagged 'herdr agent prompt a hi --wait \' '  --timeout 5000')"
check "--timeout passes herdr agent wait and pane wait-output" 0 \
  "$(flagged 'herdr agent wait "$t" --timeout 5000' 'herdr pane wait-output "$p" --match x --timeout 5000')"
check "--timeout does not bound a gh call" 1 "$(flagged 'gh run download "$id" --timeout 5')"
check "--max-time does not bound a gh call" 1 "$(flagged 'gh run view "$id" --log-failed --max-time 5')"
check "a zero turns the timeout off, so it is no bound" 5 "$(flagged 'curl --max-time 0 "$U"' 'curl -m 0 "$U"' 'timeout 0 gh run download "$id"' 'timeout "0" gh run download "$id"' 'herdr agent wait "$t" --timeout=0')"
check "a positive bound overridden by a zero is flagged" 1 "$(flagged 'curl --max-time 5 --max-time 0 "$U"')"
check "a zero overridden by a positive bound passes" 0 "$(flagged 'curl --max-time 0 --max-time 5 "$U"')"
check "a \${VAR:-command} word is a call" 3 \
  "$(flagged '"${HERDR_BIN_PATH:-herdr}" agent wait x --until idle' '${GH:-gh} run download 1' '"${CURL:-curl}" "$U"')"
check "curl's boolean -n -p -a -j -q are not value options" 0 "$(flagged 'curl -n --max-time 5 "$U"' 'curl -p -a -j -q --max-time 5 "$U"')"
check "-m is read inside a bundle of short options" 0 "$(flagged 'curl -sm 5 "$U"' 'curl -fsSLm5 "$U"')"
check "a zero in a bundle is no bound, nor is a value-taking letter before the m" 2 "$(flagged 'curl -sm 0 "$U"' 'curl -om "$U"')"
check "--wait-for is not --wait" 0 "$(flagged 'herdr agent prompt a hi --wait-for x')"
check "a redirect's & does not split the call" 0 "$(flagged 'curl "$U" >&2 --max-time 5' 'curl "$U" 2>&1 --max-time 5' 'curl "$U" &> out --max-time 5')"
check "a timeout on another command does not bound the call" 1 "$(flagged 'timeout 5 git fetch && curl "$U"')"
check "the word timeout in a string does not bound the call" 1 "$(flagged 'echo timeout reached && curl "$U"')"
check "a bound on a second call does not bound the first" 1 "$(flagged 'x="$(curl "$a")"; y="$(curl --max-time 5 "$b")"')"
check "a bound inside a nested command does not bound the outer one" 1 "$(flagged 'curl "$u" "$(foo --timeout 5)"')"
check "a bound inside a quoted argument does not bound the call" 1 "$(flagged 'curl -H "X-Note: --max-time 5" "$URL"')"
check "a quoted option is a bound" 0 "$(flagged 'curl "--max-time" 5 "$URL"')"
check "an option's value is not a bound" 1 "$(flagged 'curl "$URL" --write-out "--timeout"')"
check "an option's value is not a bound for herdr either" 1 "$(flagged 'herdr agent wait "$t" --until "--timeout"')"
check "the opt-out with a reason passes" 0 "$(flagged 'curl "$URL"  # no-timeout: the caller bounds it')"
check "the opt-out covers a call joined by || && or |" 0 \
  "$(flagged 'curl "$U" || true  # no-timeout: r' 'gh run download 1 | tail -1  # no-timeout: r' 'curl "$U" && curl "$V"  # no-timeout: r')"
check "the opt-out stops at a ; before the list it ends" 1 "$(flagged 'curl "$U"; curl "$V" || true  # no-timeout: r')"
check "the opt-out covers the last command on its line only" 1 "$(flagged 'curl "$U"; curl "$V"  # no-timeout: r')"
check "the opt-out covers a call in a substitution on its line" 0 "$(flagged 'x="$(curl "$U")"  # no-timeout: r')"
check "the opt-out covers a call on its own line in a multi-line substitution" 0 "$(flagged 'x="$(' '  curl "$U"  # no-timeout: r' ')"')"
check "the opt-out with no reason is flagged" 1 "$(flagged 'curl "$URL"  # no-timeout:')"
check "the opt-out inside a string is flagged" 1 "$(flagged 'curl "$URL" "# no-timeout: r"')"
check "the opt-out not at the start of the comment is flagged" 1 "$(flagged 'curl "$URL"  # TODO no-timeout: r')"
check "a comment line is not a call" 0 "$(flagged '# curl "$URL" has no bound')"
check "a comment naming --max-time does not bound the call" 1 "$(flagged 'curl "$URL"  # TODO: add --max-time 5')"
check "a trailing comment naming the call is not a call" 0 "$(flagged 'x=1  # curl is not run here')"
check "an escaped backtick in a heredoc's prose is not a command substitution" 0 "$(flagged 'run \`gh run download <id>\` to fetch it')"
check "a heredoc body with an apostrophe leaves the lines after it read as code" 2 \
  "$(flagged 'cat <<EOF' "the user's decisions" 'EOF' 'curl "$U"' 'curl "$V"')"
check "a file that ends inside a quote is reported" 1 "$(flagged 'x="a')"
check "the finding says where within lives and that gh has no flag" yes \
  "$(printf '%s\n' 'curl "$U"' > "${dir}/f.sh"; untimed "${dir}/f.sh" | grep -q 'within <seconds>.*merge.sh.*gh has no timeout flag' && echo yes || echo no)"

# shell_files <repo> — the shell files git tracks under <repo>'s bin/ and hooks/: *.sh, or a first
# line that is a sh or bash shebang (as loose_match_test.sh's).
shell_files() {
  local f
  git -C "$1" ls-files bin hooks | while IFS= read -r f; do
    case "${f}" in
      *.sh) echo "${f}" ;;
      *) if head -n 1 "$1/${f}" | grep -qE '^#!.*[/ ](ba)?sh([[:space:]]|$)'; then echo "${f}"; fi ;;
    esac
  done
}

mkdir -p "${dir}/repo/bin/lib" "${dir}/repo/hooks/sub"
printf '#!/usr/bin/env bash\n' > "${dir}/repo/bin/new-tool"; printf '#!/bin/sh\n' > "${dir}/repo/hooks/sub/x"
printf '#!/usr/bin/env python3\n' > "${dir}/repo/bin/lib/y.py"; : > "${dir}/repo/bin/z.sh"
printf '{}\n' > "${dir}/repo/hooks/h.json"; : > "${dir}/repo/bin/untracked.sh"
git -C "${dir}/repo" init -q && git -C "${dir}/repo" add bin/new-tool hooks/sub/x bin/lib/y.py bin/z.sh hooks/h.json
check "the files are every tracked *.sh and sh or bash script under bin/ and hooks/" \
  "bin/new-tool bin/z.sh hooks/sub/x" "$(shell_files "${dir}/repo" | tr '\n' ' ' | sed 's/ $//')"

files=()
while IFS= read -r f; do files+=("${REPO}/${f}"); done < <(shell_files "${REPO}")
# grep reads a here-string, not a pipe from printf: grep -q exits on its first match, and printf, still
# writing the rest of the list, then fails with a broken pipe, which pipefail turns into a miss.
listed="$(printf '%s\n' "${files[@]}")"
check "the shell files of bin/ and hooks/ are found" "bin/swarm.sh bin/lib bin/gh-shim hooks" \
  "$(for d in bin/swarm.sh bin/lib bin/gh-shim hooks; do grep -q "/${d}" <<< "${listed}" && printf '%s ' "${d}"; done | sed 's/ $//')"
found="$(untimed "${files[@]}")" || { echo "FAIL the scan of bin/ and hooks/ failed"; fails=$((fails + 1)); }
check "every curl, gh run download/view --log and herdr wait in the shell files of bin/ and hooks/ names its timeout" "" "${found}"

(( fails == 0 )) || exit 1
