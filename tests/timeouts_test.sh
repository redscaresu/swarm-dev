#!/usr/bin/env bash
# timeouts_test.sh — in the shell files of bin/ and hooks/, a call that can wait forever names its
# bound in the same command. The calls are `curl`, `gh run download`, `gh run view ... --log` and
# herdr's blocking ones (`herdr ... --wait`, `herdr agent wait`, `herdr pane wait-output`). Each needs
# `--max-time` or `--timeout` among its own arguments, or `within <seconds>` / `timeout <seconds>` as
# the command's own prefix, or the line ends with a comment `# no-timeout: <reason>`.
# Use `within` (merge.sh: a perl alarm): stock macOS has no `timeout`, so a call written with it exits
# 127 there. A command is what is left after splitting on ; & | ( ) and $( ) and backticks, so a bound
# on another command, or inside a quoted argument or a comment, does not count. A comment (a whole line or the end of
# one) is never a call, and a line ending in \ joins the next unless a comment ends it. A backtick
# escaped as \` (the prose of a heredoc) is text, not a command substitution. Heredoc bodies are
# scanned line by line like code: a prose line that starts with a call fails, which is the safe way
# round. Python files are not scanned.
# shellcheck disable=SC2016,SC1003 # the fixtures are shell text, not expansions
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export HOME="${dir}/home"   # under its own root, so parallel runs share no ~

# untimed <file>... — one `file:line: text` per logical line with a call that names no bound.
untimed() {
  python3 -I - "$@" <<'EOF'
import re, shlex, sys

PREFIX = re.compile(r'(?:(?:!|then|do|else|if|while|until|\{)\s+|[A-Za-z_]\w*=(?:"[^"]*"|\'[^\']*\'|[^\s"\']*)\s+)')
BOUND = re.compile(r'--(max-time|timeout)(=.*)?')
CALLS = [r'curl(\s|$)', r'gh\s+run\s+download\b', r'gh\s+run\s+view\b.*\s--log',
         r'herdr\s+(agent\s+wait|pane\s+wait-output)\b', r'herdr\b.*\s--wait\b']
HINT = ("bound it with `within <seconds>` (stock macOS has no timeout), --max-time or --timeout, "
        "or end the line with `# no-timeout: <reason>`")


def parse(t):
    """(commands, comment, continued) of one logical line: commands are split on ; & | ( ) outside
    quotes; a $( ) or backtick substitution is a command of its own and a bare $() in the one around it."""
    out, bufs, kinds, qs, q, i = [], [""], [], [], None, 0
    comment, cont = "", False
    while i < len(t):
        c = t[i]
        if q == "'":
            bufs[-1] += c
            q = None if c == "'" else q
        elif c == "\\":
            if i + 1 == len(t):
                cont = True
            else:
                bufs[-1] += t[i:i + 2]
            i += 1
        elif c == "#" and q is None and (i == 0 or t[i - 1] in " \t;|&()"):
            comment = t[i:]
            break
        elif c == "'" and q is None:
            bufs[-1] += c
            q = "'"
        elif c == '"':
            bufs[-1] += c
            q = None if q == '"' else '"'
        elif t.startswith("$(", i) or (c == "`" and (not kinds or kinds[-1] != "`")):
            bufs.append("")
            kinds.append(c)
            qs.append(q)
            q = None
            i += 1 if c == "$" else 0
        elif c == "`" or (c == ")" and q is None and kinds):
            out.append(bufs.pop())
            kinds.pop()
            q = qs.pop()
            bufs[-1] += "$()"
        elif q is None and c in ";|&()":
            out.append(bufs[-1])
            bufs[-1] = ""
        else:
            bufs[-1] += c
        i += 1
    return out + bufs, comment, cont


def unbounded(cmd):
    s = cmd.strip()
    m = PREFIX.match(s)
    while m:
        s = s[m.end():]
        m = PREFIX.match(s)
    if re.match(r'(timeout|within)\s', s) or not any(re.match(c, s) for c in CALLS):
        return False
    try:
        words = shlex.split(s)
    except ValueError:
        words = s.split()
    return not any(BOUND.fullmatch(w) for w in words)


def check(path, text, start):
    cmds, comment, _ = parse(text)
    if any(unbounded(c) for c in cmds) and not re.match(r'#\s*no-timeout:\s*\S', comment):
        print(f"{path}:{start}: {text.strip()}  <- {HINT}")


for path in sys.argv[1:]:
    buf, start = "", 0
    for n, line in enumerate(open(path, errors="replace").read().splitlines(), 1):
        start = start if buf else n
        text = buf + line
        if parse(text)[2]:
            buf = text[:-1]
            continue
        check(path, text, start)
        buf = ""
    if buf:
        check(path, buf, start)
EOF
}

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
flagged() { # <line>... — how many logical lines untimed flags
  printf '%s\n' "$@" > "${dir}/f.sh"; untimed "${dir}/f.sh" | wc -l | tr -d ' '
}

check "a bare curl is flagged" 1 "$(flagged 'x="$(curl -fsSL "$URL")"')"
check "a bare gh run download is flagged" 1 "$(flagged '  gh run download "$id" --dir out')"
check "a bare gh run view --log-failed is flagged" 1 "$(flagged 'log="$(gh run view "$id" --log-failed)"')"
check "a bare herdr --wait is flagged" 1 "$(flagged 'herdr agent prompt a hi --wait --until idle')"
check "a bare herdr agent wait is flagged" 1 "$(flagged 'herdr agent wait "$t" --until idle')"
check "a bare herdr pane wait-output is flagged" 1 "$(flagged 'herdr pane wait-output "$p" --match ready')"
check "a bare call in backticks is flagged" 1 "$(flagged 'x=`curl "$U"`')"
check "a bare call is flagged once, not once per line, when it continues" 1 "$(flagged 'gh run download "$id" \' '  --dir out')"
check "a bare call on a file's last line ending in a backslash is flagged" 1 "$(flagged 'curl "$U" \')"
check "a call after a comment ending in a backslash is flagged" 1 "$(flagged '# note \' 'curl "$U"')"
check "--max-time passes" 0 "$(flagged 'curl -fsSL --max-time 5 "$URL"')"
check "timeout as the prefix passes" 0 "$(flagged 'timeout 30 gh run download "$id"')"
check "within as the prefix passes" 0 "$(flagged 'within 30 gh run view "$id" --log-failed')"
check "within after an assignment passes" 0 "$(flagged 'x="$(FOO=1 within 30 curl "$U")"')"
check "--timeout on a continuation line passes" 0 "$(flagged 'herdr agent prompt a hi --wait \' '  --timeout 5000')"
check "--timeout passes herdr agent wait and pane wait-output" 0 \
  "$(flagged 'herdr agent wait "$t" --timeout 5000' 'herdr pane wait-output "$p" --match x --timeout 5000')"
check "a timeout on another command does not bound the call" 1 "$(flagged 'timeout 5 git fetch && curl "$U"')"
check "the word timeout in a string does not bound the call" 1 "$(flagged 'echo timeout reached && curl "$U"')"
check "a bound on a second call does not bound the first" 1 "$(flagged 'x="$(curl "$a")"; y="$(curl --max-time 5 "$b")"')"
check "a bound inside a nested command does not bound the outer one" 1 "$(flagged 'curl "$u" "$(foo --timeout 5)"')"
check "a bound inside a quoted argument does not bound the call" 1 "$(flagged 'curl -H "X-Note: --max-time 5" "$URL"')"
check "a quoted option is a bound" 0 "$(flagged 'curl "--max-time" 5 "$URL"')"
check "the opt-out with a reason passes" 0 "$(flagged 'curl "$URL"  # no-timeout: the caller bounds it')"
check "the opt-out with no reason is flagged" 1 "$(flagged 'curl "$URL"  # no-timeout:')"
check "the opt-out inside a string is flagged" 1 "$(flagged 'curl "$URL" "# no-timeout: r"')"
check "the opt-out not at the start of the comment is flagged" 1 "$(flagged 'curl "$URL"  # TODO no-timeout: r')"
check "a comment line is not a call" 0 "$(flagged '# curl "$URL" has no bound')"
check "a comment naming --max-time does not bound the call" 1 "$(flagged 'curl "$URL"  # TODO: add --max-time 5')"
check "a trailing comment naming the call is not a call" 0 "$(flagged 'x=1  # curl is not run here')"
check "an escaped backtick in a heredoc's prose is not a command substitution" 0 "$(flagged 'run \`gh run download <id>\` to fetch it')"
check "the finding says to use within" yes "$(printf '%s\n' 'curl "$U"' > "${dir}/f.sh"; untimed "${dir}/f.sh" | grep -q 'within <seconds>' && echo yes || echo no)"

files=()
for f in "${REPO}/bin/swarm.sh" "${REPO}"/bin/lib/*.sh "${REPO}"/bin/gh-shim/* "${REPO}"/hooks/*.sh; do
  [[ -f "${f}" ]] && files+=("${f}")
done
check "the shell files of bin/ and hooks/ are found" "bin/swarm.sh bin/lib bin/gh-shim hooks" \
  "$(for d in bin/swarm.sh bin/lib bin/gh-shim hooks; do printf '%s\n' "${files[@]}" | grep -q "/${d}" && printf '%s ' "${d}"; done | sed 's/ $//')"
found="$(untimed "${files[@]}")" || { echo "FAIL the scan of bin/ and hooks/ failed"; fails=$((fails + 1)); }
check "every curl, gh run download/view --log and herdr wait in the shell files of bin/ and hooks/ names its timeout" "" "${found}"

(( fails == 0 )) || exit 1
