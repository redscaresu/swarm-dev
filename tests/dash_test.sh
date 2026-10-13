#!/usr/bin/env bash
# dash_test.sh — `swarm.sh dash` against a throwaway board, a fake agents.tsv, findings.tsv and
# events.tsv, a stub herdr on PATH printing a fixed agent list, and a stub gh. stty and tput are
# stubbed to fail, so the width comes from COLUMNS (or the default 100), except in the pty test.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
fails=0
P="${ROOT}/proj"
# The claude stub goes first on PATH, so no run here reaches the real claude.
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}" CLAUDE_STUB_AGENTS="${ROOT}/claude.json"

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
has() { grep -qF -- "$1" <<< "$2"; }
lacks() { ! grep -qF -- "$1" <<< "$2"; }

item() { # <path under docs> <front-matter line>...
  local path="${P}/docs/$1" title; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

mkdir -p "${P}/.swarm/state" "${ROOT}/bin" "${ROOT}/nobin" "${ROOT}/size" "${ROOT}/projects/p"
unset COLUMNS LINES
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/size/stty"
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/size/tput"
chmod +x "${ROOT}/size/stty" "${ROOT}/size/tput"
REALPATH="${PATH}"
export PATH="${ROOT}/size:${PATH}" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp"
mkdir -p "${TMPDIR}"
# fresh — drop dash's one-minute cache of gh and cost, so the next run asks again.
fresh() { rm -f "${TMPDIR}"/swarm-dash-*; }
git -C "${P}" init -q
item hld/2026-01-01-x.md 'status: agreed'
item epics/e1.md 'status: active' 'hld: 2026-01-01-x'
item epics/e2.md 'status: later'
item stories/s-one.md 'status: review' 'epic: e1' 'prs: https://github.com/o/r/pull/7'
item stories/s-two.md 'status: blocked' 'epic: e1' 'blocked_by: [s-one]'
item stories/s-three.md 'status: ready' 'epic: e1'
item stories/ask.md 'status: ready' 'kind: lead'
sed -i.bak 's/^# ask$/# Create the read-only IAM user/' "${P}/docs/stories/ask.md" && rm "${P}/docs/stories/ask.md.bak"
# A finished story of e1, deleted from the board after it merged: e1's progress counts it from git.
item stories/s-old.md 'status: review' 'epic: e1'
# Two slugs whose agent names are the same 32 characters: the done one must never be the builder's.
# Its PR is never asked about either: dash skips done items.
item stories/aaaaaaaaaa-bbbbbbbbbb-cccccccccc-1.md 'status: done' 'prs: https://github.com/o/r/pull/9'
item stories/aaaaaaaaaa-bbbbbbbbbb-cccccccccc-2.md 'status: ready' 'kind: code'
printf 'w1:p1 conductor\nw1:p2 s-one\nw1:p3 s-gone\nw1:p4 old\nw1:p5 odd\nw1:p11 s-two\n' > "${P}/.swarm/state/e1"
# e2's conductor wrote its report and went idle: [reported], not [idle].
printf 'w1:p8 conduct-e2\n' > "${P}/.swarm/state/e2"
# s-three's builder is working; with no sign of life on record it is never stalled (the stall block below).
printf 'w1:p9 s-three\nw1:p10 aaaaaaaaaa-bbbbbbbbbb-cccccccccc\n' > "${P}/.swarm/state/s-three"
echo "# report" > "${P}/.swarm/conduct-e2.report.md"
# A codex brief in state/ is prose, not a tab record (own_panes' rule): its pane must not show.
printf 'w1:p6 is where the brief says to look\n' > "${P}/.swarm/state/brief-x.md"
# A half-written tab record (*.tmp) is skipped, as status and tidy skip it.
printf 'w1:p7 halfway\n' > "${P}/.swarm/state/e1.tmp"
printf '2026-10-01\tconduct\tconduct-e1\tclaude\topus\thigh\tsess-1\n2026-10-02\tcode\ts-one\tclaude\topus\thigh\tsess-2\n' > "${P}/.swarm/agents.tsv"
# Today's cost, the same as `swarm.sh cost <today>`: 1M input at $4 + 1M output at $20.
printf '%s\tcode\ts-three\tclaude\topus\thigh\tsess-today\n' "$(date +%F)" >> "${P}/.swarm/agents.tsv"
echo '{"message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1000000,"output_tokens":1000000}}}' > "${ROOT}/projects/p/sess-today.jsonl"
printf '2026-10-03\tvacuous-test\thttps://github.com/o/r/pull/7\ta test that could not fail\n' > "${P}/.swarm/findings.tsv"
# Five findings on another PR the same day: one recent row, not five.
for i in 1 2 3 4 5; do printf '2026-10-04\tkind%s\thttps://github.com/o/r/pull/8\tfinding %s\n' "${i}" "${i}" >> "${P}/.swarm/findings.tsv"; done
ago() { python3 -c 'import datetime, sys; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
printf '2026-10-03T10:00:00Z\tfinish\ts-zero\tw1:p1\tok\n2026-10-04T10:00:00Z\treview\ts-one\tw1:p1\tok\n' > "${P}/.swarm/events.tsv"

# Claude Code's sessions: the conductor (sess-1) and s-three's builder (sess-today) are busy, and
# s-one's builder waits on a permission prompt. The wait checks below rewrite this file.
printf '[{"sessionId":"sess-1","status":"busy"},{"sessionId":"sess-2","status":"waiting","waitingFor":"input"},{"sessionId":"sess-today","status":"busy"}]' > "${ROOT}/claude.json"
# herdr: this project's conductor (working) and builder (blocked), an empty pane (w1:p3), and
# another project's agent (w9:p1), which must not be shown. s-three's herdr status is done while its
# session is busy: the session's word is the one dash shows.
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"conduct-e1","agent_status":"working","pane_id":"w1:p1","agent_session":{"value":"sess-1"}},{"name":"conduct-e2","agent_status":"idle","pane_id":"w1:p8"},{"name":"s-one","agent_status":"blocked","pane_id":"w1:p2"},{"name":"foreign","agent_status":"working","pane_id":"w9:p1"},{"name":"old-done","agent_status":"idle","pane_id":"w1:p4"},{"name":"odd","agent_status":"idle","pane_id":"w1:p5","agent_session":"not-an-object"},{"name":"prose","agent_status":"working","pane_id":"w1:p6"},{"name":"halfway","agent_status":"working","pane_id":"w1:p7"},{"name":"s-three","agent_status":"done","pane_id":"w1:p9"},{"name":"aaaaaaaaaa-bbbbbbbbbb-cccccccccc","agent_status":"working","pane_id":"w1:p10"},{"name":"s-two","agent_status":"starting","pane_id":"w1:p11"},{"name":"s-re-done","agent_status":"idle","pane_id":"w2:p1"},{"name":"s-re","agent_status":"'"${RE_HERDR:-working}"'","pane_id":"w2:p2"},{"name":"s-lost","agent_status":"idle","pane_id":"w2:p3"},{"name":"s-odd","agent_status":"working","pane_id":"w2:p4"},{"name":"cx","agent_status":"blocked","pane_id":"w2:p5"},{"name":"s-dash","agent_status":"working","pane_id":"w2:p6"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w1:p1"},{"pane_id":"w1:p2"},{"pane_id":"w1:p3"},{"pane_id":"w9:p1"},{"pane_id":"w1:p4"},{"pane_id":"w1:p5"},{"pane_id":"w1:p6"},{"pane_id":"w1:p7"},{"pane_id":"w1:p8"},{"pane_id":"w1:p9"},{"pane_id":"w1:p10"},{"pane_id":"w1:p11"},{"pane_id":"w2:p1"},{"pane_id":"w2:p2"},{"pane_id":"w2:p3"},{"pane_id":"w2:p4"},{"pane_id":"w2:p5"},{"pane_id":"w2:p6"}]}}' ;;
  "agent wait") echo "$*" >> "${WAIT_LOG:-/dev/null}"
    [ -z "${WAIT_TIMES:-}" ] || python3 -c 'import time; print(int(time.time() * 1000))' >> "${WAIT_TIMES}"
    [ -z "${WAIT_SLEEP:-}" ] || sleep "${WAIT_SLEEP}"
    if [ -n "${WAIT_SWAP:-}" ] && [ -e "${WAIT_SWAP}.new" ]; then mv "${WAIT_SWAP}.new" "${WAIT_SWAP}"; fi   # the session changes while herdr waits
    echo "herdr: a notice on stderr" >&2
    case "${WAIT_MODE:-done}" in
      timeout) echo '{"error":{"code":"timeout","message":"timed out waiting for agent status"}}' >&2; exit 1 ;;
      error) echo '{"error":{"code":"agent_not_found"}}' >&2; exit 1 ;;
      *) echo "{\"result\":{\"agent\":{\"agent_status\":\"${WAIT_MODE:-done}\"}}}" ;;
    esac ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"2026-01-01-x"},{"workspace_id":"w9","label":"other"}]}}' ;;
  *) exit 1 ;;
esac
STUB
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/nobin/herdr"
# gh: PR 7's checks are green and its branch is behind the base.
# PR 8 was updated at the time in pr8.updated.
cat > "${ROOT}/bin/gh" <<STUB
#!/bin/sh
U8="${ROOT}/pr8.updated"
STUB
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${U8%/*}/gh.log"
case "$1 $2 $3" in
  "pr view https://github.com/o/r/pull/7") echo '{"mergeStateStatus":"BEHIND","statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"StatusContext","state":"SUCCESS"}]}' ;;
  "pr view https://github.com/o/r/pull/8") if [ "$6" = -q ]; then cat "$U8"; else echo "{\"updatedAt\":\"$(cat "$U8")\"}"; fi ;;
  *) exit 1 ;;
esac
STUB
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/nobin/gh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/nobin/herdr" "${ROOT}/bin/gh" "${ROOT}/nobin/gh"

# The board is committed, with one merge on the base branch; then one board file is edited.
G=(git -C "${P}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
"${G[@]}" add docs && "${G[@]}" commit -qm board
"${G[@]}" rm -q docs/stories/s-old.md && "${G[@]}" commit -qm "finish s-old"
"${G[@]}" checkout -qb story/s-zero && "${G[@]}" commit -q --allow-empty -m work
# A fixed merge time, so no relative time in recent moves while the pty tests watch.
"${G[@]}" checkout -q - && GIT_COMMITTER_DATE=2026-10-05T12:00:00Z "${G[@]}" merge -q --no-ff -m "Merge pull request #9 from o/story/s-zero" story/s-zero
fresh; clean="$(cd "${P}" || exit 1; PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a committed board shows no drift line" lacks "board:" "${clean}"
echo "more" >> "${P}/docs/stories/s-three.md"

snapshot() { (cd "${P}" && find docs .swarm -type f -print0 | sort -z | xargs -0 cksum; ls -laR docs .swarm) ; }
before="$(snapshot)"

fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
for panel in "needs you" "epics" "recent"; do
  check "panel ${panel}" has "╭─ ${panel} ─" "${out}"
done
check "the header is one line: project, version, merge, next, clock" grep -qE '^proj  swarm-dev [0-9.]+  merge human  next wait conduct-e1 +[0-9]{2}:[0-9]{2}:[0-9]{2}$' <<< "$(head -1 <<< "${out}")"
check "the summary line counts epics, working agents, green PRs, stalls and cost" test "$(sed -n 2p <<< "${out}")" == "1 epics active · 3 agents working · 1 PRs green, waiting · 0 stalled · \$24.00 today"
check "an uncommitted board edit is one line under the summary" has "board: 1 uncommitted edit in the main checkout (reconcile pulls first)" "$(sed -n 3p <<< "${out}")"
check "needs you is the first panel" grep -q '^╭─ needs you ─' <<< "$(grep -m1 '^╭─' <<< "${out}")"
needs="$(sed -n '/^╭─ needs you/,/^╰/p' <<< "${out}")"
check "needs you lists a green PR as a merge" grep -qE '^│ ! merge r#7 \(✓ green · behind\)  s-one +│$' <<< "${needs}"
check "needs you lists a lead story with its title" has "! run lead story ask: create the read-only IAM user" "${needs}"
check "needs you lists an agent waiting on a prompt, with what its session waits for" has "! answer s-one (waiting on input): herdr agent read s-one" "${needs}"
check "needs you lists an empty pane" has "! close the empty pane s-gone: swarm.sh tidy" "${needs}"
# A long waitingFor over three lines is one line in needs you, cut at 60 characters, inside the box.
printf '%s' '[{"sessionId":"sess-1","status":"busy"},{"sessionId":"sess-2","status":"waiting","waitingFor":"Allow Bash to run:\n  rm -rf build && make all && make test && make install && echo done\n(y/n)"},{"sessionId":"sess-today","status":"busy"}]' > "${ROOT}/claude-long.json"
fresh; long="$(cd "${P}" || exit 1; HERDR_ENV=1 CLAUDE_STUB_AGENTS="${ROOT}/claude-long.json" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
longneeds="$(sed -n '/^╭─ needs you/,/^╰/p' <<< "${long}")"
check "a long, multi-line waitingFor is one line, cut with …" has "! answer s-one (waiting on Allow Bash to run: rm -rf build && make all && make test &&…): herdr agent read s-one" \
  "$(sed -e 's/^│ //' -e 's/ *│$//' <<< "${longneeds}" | paste -sd' ' - | tr -s ' ')"
check "a long, multi-line waitingFor keeps the needs-you box whole" test "$(sed '1d;$d' <<< "${longneeds}" | grep -cvE '^│ .* │$')" -eq 0
check "needs you lists only actionable items" test "$(grep -c '^│ ! ' <<< "${needs}")" -eq "$(($(wc -l <<< "${needs}") - 2))"
check "needs you lists no blocked item" lacks "s-two" "${needs}"
check "needs you lists no later item" lacks "e2" "${needs}"
check "blocked and later are one count line below the epics" grep -qE '^⏸ 1 blocked · 1 later  \(swarm.sh status --all lists them\)$' <<< "${out}"
epicp="$(sed -n '/^╭─ epics/,/^╰/p' <<< "${out}")"
check "an epic row shows progress, counting a finished story from git" grep -qE '^│ ! e1 +█{3}░{9}  1/4   1 review · 1 ready · 1 blocked +│$' <<< "${epicp}"
check "the conductor sits under its epic with role, model and status" grep -qE '^│   ● conduct-e1 +conduct +opus·high +working +│$' <<< "${epicp}"
check "an agent waiting on a prompt is marked ! with its waitingFor" grep -qE '^│   ! s-one +code +opus·high +waiting on input' <<< "${epicp}"
check "an epic's open PR sits under it" grep -qE '^│   ✓ r#7 +green · behind  s-one +│$' <<< "${epicp}"
check "an empty pane is marked !" grep -qE '! s-gone .*empty pane' <<< "${epicp}"
check "an odd agent record marks its row, not the panel" grep -qE '! odd .*unreadable: AttributeError' <<< "${epicp}"
check "a conductor that wrote its report shows under its later epic" grep -qE '✓ conduct-e2 .*reported' <<< "$(sed -n '/e2 (later)/,$p' <<< "${epicp}")"
check "an agent with no epic is grouped last" grep -qE '● aaaaaaaaaa-bbbbbbbbbb-ccccccc… .*working' <<< "$(sed -n '/no epic/,$p' <<< "${epicp}")"
check "a retired agent collapses into a count" grep -qE '^│ \+1 idle  \(--tree lists them\) +│$' <<< "${epicp}"
check "a collapsed agent is not listed" lacks "old-done" "${out}"
check "the workspace tree is not the main view" lacks "2026-01-01-x" "${out}"
check "the ladder is hidden by default" lacks "─ ladder" "${out}"
check "a date-only row sorts after that day's timed events" python3 -c 'import sys; t = sys.stdin.read(); sys.exit(not 0 < t.index("could not fail") < t.index("finish s-zero"))' <<< "${out}"
check "a line in a brief is not a pane of this project's" lacks "prose" "${out}"
check "a *.tmp tab record is skipped" lacks "halfway" "${out}"
check "another project's agent is not shown" lacks "foreign" "${out}"
recent="$(sed -n '/^╭─ recent/,/^╰/p' <<< "${out}")"
check "recent lists the newest first, with its icon and a relative time" grep -qE '^│ +[0-9]+d ago  ⇡ merged #9 story/s-zero ' <<< "$(sed -n 2p <<< "${recent}")"
check "recent shows an older action in days" grep -qE '^│ +[0-9]+d ago  · review s-one ' <<< "${recent}"
check "an agent in a state dash does not know shows ? and the word" grep -qE '^│   \? s-two +\? +\? +starting +│$' <<< "${epicp}"
check "recent lists a finding" grep -qE '✎ a test that could not fail \(#7\)' <<< "${recent}"
check "recent folds a PR's findings for a day into one row" has "5 findings: finding 1; finding 2" "${recent}"
check "recent's time and icon columns line up" test "$(sed '1d;$d' <<< "${recent}" | grep -cvE '^│ [ 0-9a-z]{9}  . ')" -eq 0
check "the legend is the last lines" test "$(tail -2 <<< "${out}" | paste -sd' ' -)" == "● working   ○ ready   ◐ review / CI running   ✓ done / green   ✗ failing   ⏸ blocked ! needs you (session gone or unknown)   ? unknown"
check "boxes have rounded corners" grep -qE '^╰─+╯$' <<< "${out}"
check "a run off a terminal has no ANSI escapes" lacks $'\033' "${out}"
widest() { python3 -c 'import sys; print(max(len(l) for l in sys.stdin.read().splitlines()))'; }
check "the default width is 100" test "$(widest <<< "${out}")" -eq 100

fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash --tree --ladder 2>&1 || true)"
check "--tree groups the agents by workspace" grep -qE '^│ 2026-01-01-x +│$' <<< "${out}"
check "--tree groups the agents by tab" has "├─ e1" "${out}"
check "--tree lists a retired agent" grep -qE 'old-done .*retired' <<< "${out}"
check "--tree shows a story's PR on its builder" grep -qE '! s-one .*waiting on input  https://g' <<< "${out}"
check "--ladder maps role to model and effort" has "code-risky → opus · xhigh" "${out}"
check "--ladder names codex" has "codex      → codex · high" "${out}"
check "below 140 columns the ladder and recent are stacked" lacks "╮ ╭─ recent" "${out}"

fresh; out="$(cd "${P}" || exit 1; env -u HERDR_ENV COLUMNS=160 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash --ladder 2>&1 || true)"
check "COLUMNS sets the width when stty and tput cannot" test "$(widest <<< "${out}")" -eq 160
check "from 140 columns the ladder and recent sit side by side" grep -qE '─ ladder ─+╮ ╭─ recent' <<< "${out}"
check "outside a herdr pane, a herdr that answers still shows the agents" grep -qE '● conduct-e1 +conduct +opus·high +working' <<< "${out}"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 COLUMNS=50 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "at 50 columns no line is wider than the terminal" test "$(widest <<< "${out}")" -le 50
check "at 50 columns the header drops version and merge mode, keeping next" grep -qE '^proj  next wait conduct-e1 +[0-9:]{8}$' <<< "$(head -1 <<< "${out}")"
joined="$(sed -n '/^╭─ needs you/,/^╰/p' <<< "${out}" | sed -e 's/^│ //' -e 's/ *│$//' | paste -sd' ' - | tr -s ' ')"
check "at 50 columns a needs-you action wraps, not cut" has "! run lead story ask: create the read-only IAM user !" "${joined}"
check "at 50 columns a wrapped needs-you line is indented under its action" grep -qE '^│   [a-z]' <<< "$(sed -n '/^╭─ needs you/,/^╰/p' <<< "${out}")"
for cols in 79 60 45; do
  fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 COLUMNS="${cols}" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash --ladder 2>&1 || true)"
  check "at ${cols} columns no line is wider than the terminal" test "$(widest <<< "${out}")" -le "${cols}"
  check "at ${cols} columns the layout is stacked, without role and model columns" grep -qE '^│   ● conduct-e1 +working +│$' <<< "${out}"
  check "at ${cols} columns a long line is cut with …" has "…" "${out}"
done

fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a failing herdr degrades: agents unavailable" has "agents unavailable" "${out}"
check "a failing herdr still prints the epics" grep -qE '^│ . e1 +█' <<< "${out}"
check "a failing gh leaves the PR URL" has "! merge s-one: https://github.com/o/r/pull/7" "${out}"
check "dash never asks gh about a done item's PR" lacks "pull/9" "$(cat "${ROOT}/gh.log")"
# The gh and cost cache lasts a minute and serves a one-shot dash too: a failing gh is not asked.
fresh; (cd "${P}" && PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash >/dev/null 2>&1) || true
out="$(cd "${P}" || exit 1; PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a one-shot dash reuses the cached PR state" has "! merge r#7 (✓ green · behind)" "${out}"
# gh gets 5 seconds a PR: one that hangs is left out, and dash still draws.
mkdir -p "${ROOT}/slowgh"
printf '#!/bin/sh\nexec sleep 60\n' > "${ROOT}/slowgh/gh"; chmod +x "${ROOT}/slowgh/gh"
fresh; t0=$(date +%s)
out="$(cd "${P}" || exit 1; PATH="${ROOT}/slowgh:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a hanging gh is cut off after 5 seconds" test $(( $(date +%s) - t0 )) -lt 15
check "a hanging gh leaves the PR URL" has "! merge s-one: https://github.com/o/r/pull/7" "${out}"
fresh; out="$(cd "${P}" || exit 1; env -u HERDR_ENV PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "outside herdr with no working herdr: agents unavailable" has "agents unavailable" "${out}"

# --watch off a terminal prints a frame only when it changed, plain, until stopped.
(cd "${P}" && exec env -u HERDR_ENV bash "${SWARM}" dash --watch 1 > "${ROOT}/watch.out" 2>&1) &
pid=$!; sleep 3; kill -TERM "${pid}" || true; wait "${pid}" || true
w="$(cat "${ROOT}/watch.out")"
check "--watch off a terminal draws the frame" has "─ needs you" "${w}"
check "--watch off a terminal does not repeat an unchanged frame" test "$(grep -c -- '─ needs you' <<< "${w}")" -eq 1
check "--watch off a terminal has no ANSI escapes" lacks $'\033' "${w}"

# --watch on a terminal: a pty, 30x120, its size read with the real stty. ptywatch.py runs
# `dash --watch <seconds>`, resizes the pty to 30x150 and sends SIGWINCH at <resize-at> seconds (0:
# never), types each <key>@<seconds> given after <q-at>, types q at <q-at>, and kills the watch if
# it is still running 5 seconds later.
cat > "${ROOT}/ptywatch.py" <<'PY'
import fcntl, os, pty, select, signal, struct, sys, termios, time
swarm, out_path, every, resize_at, q_at = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), float(sys.argv[5])
keys = [(k.split("@")[0].encode(), float(k.split("@")[1])) for k in sys.argv[6:]]
def size(fd, rows, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
pid, fd = pty.fork()
if pid == 0:
    size(0, 30, 120)
    os.execvp("bash", ["bash", swarm, "dash", "--watch", every])
out, start, resized, typed, status = b"", time.time(), False, False, None
while status is None:
    now = time.time() - start
    if resize_at and not resized and now > resize_at:
        size(fd, 30, 150); os.kill(pid, signal.SIGWINCH); resized = True
    while keys and now > keys[0][1]:
        os.write(fd, keys.pop(0)[0])
    if not typed and now > q_at:
        os.write(fd, b"q"); typed = True
    if now > q_at + 5:
        os.kill(pid, signal.SIGKILL)
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            out += os.read(fd, 65536)
        except OSError:
            pass
    done, st = os.waitpid(pid, os.WNOHANG)
    if done:
        status = st
open(out_path, "wb").write(out)
sys.exit(os.waitstatus_to_exitcode(status))
PY
ptywatch() { # <out> <seconds> <resize-at> <q-at> [<key>@<seconds>...]; PTY_BIN puts another stub dir first on PATH
  (cd "${P}" && env -u HERDR_ENV PATH="${PTY_BIN:-${ROOT}/bin}:${ROOT}/bin:${REALPATH}" python3 -I "${ROOT}/ptywatch.py" "${SWARM}" "$@")
}
plain() { python3 -c 'import re, sys; print(re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", sys.stdin.read().replace("\r", "")))' < "$1"; }
frames() { grep -o -- '╭─ needs you' | wc -l | tr -d ' '; }

# Nothing changes for 3.5 seconds at --watch 1: one full frame, the header line rewritten each second.
if ptywatch "${ROOT}/pty.out" 1 0 3.5; then rc=0; else rc=$?; fi
w="$(cat "${ROOT}/pty.out")"; text="$(plain "${ROOT}/pty.out")"
check "--watch on a terminal quits on q" test "${rc}" -eq 0
check "--watch enters the alternate screen and hides the cursor" test "${w:0:14}" == $'\033[?1049h\033[?25l'
check "--watch shows the cursor and leaves the alternate screen on exit" test "${w: -14}" == $'\033[?25h\033[?1049l'
check "--watch homes the cursor and clears below the frame" has $'\033[K\033[J' "${w}"
check "--watch draws an unchanged frame once" test "$(frames <<< "${text}")" -eq 1
check "--watch rewrites the header line while nothing changes" test "$(grep -o $'\033\\[H' <<< "${w}" | wc -l | tr -d ' ')" -ge 3
check "--watch measures the terminal with stty (120 columns)" grep -qE '^╰─{118}╯$' <<< "${text}"
check "--watch on a terminal paints the needs-you title red and bold" has $'\033[1;31mneeds you\033[0m' "${w}"
check "--watch lists its keys in the legend" grep -qE 'q quit · t tree · l ladder · r redraw' <<< "${text}"
# At --watch 30, a resize at 2 seconds redraws at once, at the new width, before the q at 4.
ptywatch "${ROOT}/pty2.out" 30 2 4 || true
text="$(plain "${ROOT}/pty2.out")"
check "--watch redraws at once on SIGWINCH" test "$(frames <<< "${text}")" -eq 2
check "--watch re-measures on SIGWINCH (150 columns)" grep -qE '^╰─{148}╯$' <<< "${text}"
# t shows the tree in place of the epics, l adds the ladder (beside recent from 140 columns).
ptywatch "${ROOT}/pty4.out" 30 0 4 t@1.5 l@2.5 || true
text="$(plain "${ROOT}/pty4.out")"
check "--watch redraws on t and on l" test "$(frames <<< "${text}")" -eq 3
check "t in --watch shows the tree" has "─ agents by workspace and tab" "${text}"
check "l in --watch shows the ladder" has "─ ladder" "${text}"
check "before t and l, the frame shows the epics, not the tree or the ladder" test "$(sed '/╭─ agents by/,$d' <<< "${text}" | grep -c -e '╭─ epics' -e '─ ladder')" -eq 1
# NO_COLOR keeps a terminal's frame free of colour; the cursor and screen controls stay.
NO_COLOR=1 ptywatch "${ROOT}/pty5.out" 30 0 2 || true
check "NO_COLOR on a terminal still draws the frame" has "needs you" "$(plain "${ROOT}/pty5.out")"
check "NO_COLOR leaves no colour on a terminal" test "$(grep -cE $'\033\\[[0-9;]*m' "${ROOT}/pty5.out")" -eq 0
# A failed render with a long error is cut to the terminal's 30 lines, and its last line is the error.
mkdir -p "${ROOT}/longpy"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\nif [ -n "${DASH_PROJECT:-}" ]; then seq 1 100 >&2; exit 1; fi\nexec "%s" "$@"\n' "$(command -v python3)" > "${ROOT}/longpy/python3"
chmod +x "${ROOT}/longpy/python3"
PTY_BIN="${ROOT}/longpy" ptywatch "${ROOT}/pty3.out" 30 0 3 || true
text="$(plain "${ROOT}/pty3.out")"
check "a failed render is cut to the terminal's height" test "$(wc -l <<< "${text}" | tr -d ' ')" -le 30
check "a cut failed render keeps its error line" grep -q '^(dash: this render failed; retrying in 30s)' <<< "${text}"
# A render that fails shows its error in the frame, and the watch keeps going.
mkdir -p "${ROOT}/badpy"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\nif [ -n "${DASH_PROJECT:-}" ]; then echo "render boom" >&2; exit 1; fi\nexec "%s" "$@"\n' "$(command -v python3)" > "${ROOT}/badpy/python3"
chmod +x "${ROOT}/badpy/python3"
(cd "${P}" && exec env -u HERDR_ENV PATH="${ROOT}/badpy:${PATH}" bash "${SWARM}" dash --watch 1 > "${ROOT}/badwatch.out" 2>&1) &
pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q "render boom" "${ROOT}/badwatch.out" && break; sleep 1; done
sleep 2; alive=no
if kill -0 "${pid}" 2>/dev/null; then alive=yes; fi
kill -TERM "${pid}" || true; wait "${pid}" || true
w="$(cat "${ROOT}/badwatch.out")"
check "--watch shows a failed render's error" has "render boom" "${w}"
check "--watch keeps going after a failed render" test "${alive}" == yes
check "--watch refuses a bad interval" bash -c "cd '${P}' && ! bash '${SWARM}' dash --watch 0 2>/dev/null"

check "dash changes nothing under the board or .swarm" test "$(snapshot)" == "${before}"

# --- Stalls. s-three's builder is working, and its story was started 2 hours ago with nothing since:
# no worktree commit, no PR. After the snapshot, since a stall's age changes every minute.
printf '%s\tstory\ts-three\tw1:p1\tok\n' "$(ago 120)" >> "${P}/.swarm/events.tsv"
printf '%s\tconduct\te1\tw1:p1\tok\n' "$(ago 4)" >> "${P}/.swarm/events.tsv"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a builder working 2 hours with no sign of life is stalled" grep -qE '! s-three .*stalled 1(19|20|21)m' <<< "${out}"
check "a stalled builder needs you" grep -qE '! look at s-three: working 1(19|20|21) min with no commit or PR update' <<< "${out}"
check "the summary counts the stall" has " · 1 stalled · " "$(sed -n 2p <<< "${out}")"
check "recent shows a start minutes ago, newest first" grep -qE '^│    4m ago  ▶ conduct e1 ' <<< "$(sed -n '/^╭─ recent/{n;p;}' <<< "${out}")"
check "recent shows hours ago" grep -qE '^│    2h ago  ▶ story s-three ' <<< "${out}"
mkdir -p "${P}/.claude/swarm"; echo "stall_minutes = 300" > "${P}/.claude/swarm/config"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "stall_minutes sets the threshold" lacks "look at s-three" "${out}"
rm "${P}/.claude/swarm/config"
# wait: herdr says done at once (the stub), and s-three's session (sess-today) is busy, so a wait
# sleeps out each slice and reads the session again; herdr's word is never the answer.
printf '[{"sessionId":"sess-today","status":"busy"},{"sessionId":"sess-cut","status":"busy"}]' > "${ROOT}/claude.json"
waitfor() { (cd "${P}" || exit 1; HERDR_ENV=1 SWARM_STALL_POLL_MS="${SWARM_STALL_POLL_MS:-1000}" CLAUDE_STUB_AGENTS="${CLAUDE_STUB_AGENTS:-${ROOT}/claude.json}" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" wait "$@" 2>&1); }
long_ago() { SWARM_WAIT_STARTED=$(( $(date +%s) - 7200 )) waitfor "$@"; }
t0=${SECONDS}
if out="$(WAIT_LOG="${ROOT}/wait.log" CLAUDE_STUB_LOG="${ROOT}/claude.log" waitfor s-three 3000)"; then rc=0; else rc=$?; fi
took=$((SECONDS - t0))
check "a bare wait on a busy, stalled builder times out with its state: no stall" test "${rc}:${out}" == "1:busy"
# The last slice is cut to the deadline, so it may be a little short of the others.
check "a bare wait polls herdr in slices" test "$(awk '$1 $2 $3 == "agentwaitw1:p9" && $4 == "--timeout" && $5 > 0 && $5 <= 1000 { n++ } END { print n, NR }' "${ROOT}/wait.log")" == "3 3"
check "each slice herdr cut short is slept out, so the wait lasts its timeout" test "${took}" -ge 2
# Slices are timed in milliseconds: a herdr wait of half a second is slept out to the slice, never
# rounded to a whole second (a gap of 0.5 s or 1.5 s between wakes).
WAIT_TIMES="${ROOT}/wait.times" WAIT_SLEEP=0.5 waitfor s-three 3000 >/dev/null || true
check "each slice lasts its STALL_POLL_MS, timed in milliseconds" test "$(awk 'NR > 1 { g = $1 - p; if (g < 900 || g > 1450) bad = 1 } { p = $1 } END { print NR, (bad ? "off" : "on time") }' "${ROOT}/wait.times")" == "3 on time"
# One read before the first wake, one after each of the 3, and one at the deadline after the last
# slice's early wake: herdr wakes at once here, so every slice is slept out.
check "a 3-slice wait lists Claude's sessions at most 5 times" test "$(grep -c '^agents --json$' "${ROOT}/claude.log")" -le 5
# wait --stall counts from when the wait began: started now, 2 hours of silence before it do not count.
if out="$(waitfor --stall s-three 3000)"; then rc=0; else rc=$?; fi
check "wait --stall counts from its own start" test "${rc}:$(grep -c stalled <<< "${out}")" == "1:0"
# Begun 2 hours ago (the test hook), it returns on the stall with exit code 3: herdr says done, but
# the session is busy, and busy is what the stall rule reads.
if out="$(long_ago --stall s-three 3000)"; then rc=0; else rc=$?; fi
check "wait --stall returns on a stall with exit code 3" test "${rc}" -eq 3
check "wait --stall says why" grep -qE '^stalled: working 1(19|20|21) min with no commit or PR update$' <<< "${out}"
# Past stall_minutes, the session is busy before the first wake and idle on the read after it: the
# stall check takes only the read after the wake, so wait returns idle, not stalled.
cp "${ROOT}/claude.json" "${ROOT}/claude.json.flip"
printf '[{"sessionId":"sess-today","status":"idle"}]' > "${ROOT}/claude.json.flip.new"
if out="$(WAIT_SWAP="${ROOT}/claude.json.flip" CLAUDE_STUB_AGENTS="${ROOT}/claude.json.flip" long_ago --stall s-three 3000)"; then rc=0; else rc=$?; fi
check "a builder idle on the read after the wake is idle, not stalled" test "${rc}:${out}" == "0:idle"
# An idle session has settled, and stalls are not checked.
printf '[{"sessionId":"sess-today","status":"idle"}]' > "${ROOT}/claude.json.idle"
if out="$(CLAUDE_STUB_AGENTS="${ROOT}/claude.json.idle" long_ago --stall s-three 3000)"; then rc=0; else rc=$?; fi
check "wait --stall returns an idle session's state" test "${rc}:${out}" == "0:idle"
# Two stories share an agent name's 32 characters; the builder is the one not done.
printf '%s\tstory\taaaaaaaaaa-bbbbbbbbbb-cccccccccc-2\tw1:p1\tok\n' "$(ago 120)" >> "${P}/.swarm/events.tsv"
# While that builder is a codex agent, herdr answers for it (herdr_wait): herdr's stderr notice never
# reaches the JSON parse, a step that times out is told from a real failure, and stalls are checked
# between steps.
printf '%s\tcode\taaaaaaaaaa-bbbbbbbbbb-cccccccccc\tcodex\tgpt\thigh\t-\n' "$(date +%F)" >> "${P}/.swarm/agents.tsv"
if out="$(WAIT_MODE=idle waitfor --stall aaaaaaaaaa-bbbbbbbbbb-cccccccccc 3000)"; then rc=0; else rc=$?; fi
check "a codex agent's wait reads herdr's status with a notice on stderr" test "${rc}:${out}" == "0:idle"
: > "${ROOT}/wait.log"; WAIT_LOG="${ROOT}/wait.log" WAIT_MODE=timeout waitfor aaaaaaaaaa-bbbbbbbbbb-cccccccccc 3000 >/dev/null || true
check "a codex agent's step that times out is stepped past" test "$(grep -c . "${ROOT}/wait.log")" -eq 3
rc=0; : > "${ROOT}/wait.log"; WAIT_LOG="${ROOT}/wait.log" WAIT_MODE=error waitfor aaaaaaaaaa-bbbbbbbbbb-cccccccccc 3000 >/dev/null || rc=$?
check "a codex agent's step that fails for real ends the stepping, and the wait fails" test "$(grep -c . "${ROOT}/wait.log"):${rc}" == "2:1"
if out="$(WAIT_MODE=timeout long_ago --stall aaaaaaaaaa-bbbbbbbbbb-cccccccccc-2 3000)"; then rc=0; else rc=$?; fi
check "a codex builder's wait --stall returns on a stall between steps" test "${rc}:$(grep -c '^stalled: working' <<< "${out}")" == "3:1"
printf '%s\tcode\taaaaaaaaaa-bbbbbbbbbb-cccccccccc\tclaude\topus\thigh\tsess-cut\n' "$(date +%F)" >> "${P}/.swarm/agents.tsv"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "dash maps a cut agent name to the story not done" grep -qE 'look at aaaaaaaaaa-bbbbbbbbbb-cccccccccc: working 1(19|20|21) min' <<< "${out}"
if out="$(long_ago --stall aaaaaaaaaa-bbbbbbbbbb-cccccccccc-2 3000)"; then rc=0; else rc=$?; fi
check "wait maps a cut agent name to the story not done" test "${rc}" -eq 3
# A PR updated a minute ago is a sign of life: neither dash nor wait --stall calls it stalled.
ago 1 > "${ROOT}/pr8.updated"
# Into the front matter: dash reads keys there only.
awk 'NR > 1 && /^---$/ && !d { print "prs: https://github.com/o/r/pull/8"; d = 1 } { print }' "${P}/docs/stories/s-three.md" > "${ROOT}/s3" && mv "${ROOT}/s3" "${P}/docs/stories/s-three.md"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a recent PR update is not a stall in dash" lacks "look at s-three" "${out}"
if out="$(long_ago --stall s-three 3000)"; then rc=0; else rc=$?; fi
check "a recent PR update is not a stall in wait --stall" test "${rc}:$(grep -c stalled <<< "${out}")" == "1:0"

# --- Session states, in a project of its own (S) whose panes are w2's: a session with no entry
# (s-lost) and one in a state not known (s-odd) need a look; a reused name (s-re: the older agent
# retired to s-re-done, the newer running) shows its newer session; a codex agent (cx) and one with
# no session recorded (s-dash) show herdr's word. herdr says s-re is RE_HERDR, the opposite of its
# newer session each time.
S="${ROOT}/s"; mkdir -p "${S}/.swarm/state"; git -C "${S}" init -q
printf 'w2:p1 s-re\nw2:p2 s-re\nw2:p3 s-lost\nw2:p4 s-odd\nw2:p5 cx\nw2:p6 s-dash\n' > "${S}/.swarm/state/t"
printf '2026-10-13\tcode\t%s\t%s\topus\thigh\t%s\n' s-re claude re-old s-re claude re-new s-lost claude lost \
  s-odd claude odd cx codex - s-dash claude - > "${S}/.swarm/agents.tsv"
sdash() { # <re-old status> <re-new status> <herdr's s-re status> — dash --tree in S
  printf '[{"sessionId":"re-old","status":"%s"},{"sessionId":"re-new","status":"%s"},{"sessionId":"odd","status":"compacting"}]' "$1" "$2" > "${ROOT}/s.json"
  fresh; (cd "${S}" || exit 1; CLAUDE_STUB_AGENTS="${ROOT}/s.json" RE_HERDR="$3" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash --tree 2>&1 || true)
}
out="$(sdash busy idle working)"
check "a recorded session with no entry is ! gone" grep -qE '! s-lost .* gone: session ended' <<< "${out}"
check "a session in a state dash does not know is ! unknown" grep -qE '! s-odd .* unknown: no session state' <<< "${out}"
needs="$(sed -n '/^╭─ needs you/,/^╰/p' <<< "${out}")"
check "needs you lists an agent whose session is gone" has "! look at s-lost: session ended" "${needs}"
check "needs you lists an agent whose session state is unknown" has "! look at s-odd: no session state" "${needs}"
check "a reused name shows the newer session (older busy, newer idle)" grep -qE '✓ s-re +code .* idle' <<< "${out}"
check "a retired pane is retired, whatever its name's newest session says" grep -qE '✓ s-re-done .* retired' <<< "${out}"
check "a codex agent herdr says is blocked is ! waiting" grep -qE '! cx .* waiting on a prompt' <<< "${out}"
check "a codex agent waiting is in needs you" has "! answer cx: herdr agent read cx" "${out}"
check "an agent with no session recorded shows herdr's word" grep -qE '● s-dash .* working' <<< "${out}"
out="$(sdash idle busy idle)"
check "a reused name shows the newer session (older idle, newer busy)" grep -qE '● s-re +code .* working' <<< "${out}"
check "a retired pane stays retired when its name's newest session is busy" grep -qE '✓ s-re-done .* retired' <<< "${out}"
out="$(fresh; cd "${S}" || exit 1; CLAUDE_STUB_AGENTS="${ROOT}/no-such-file" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash --tree 2>&1 || true)"
check "with a claude that cannot list, a recorded session is ! unknown" grep -qE '! s-lost .* unknown: no session state' <<< "${out}"
check "with a claude that cannot list, an agent with no session keeps herdr's word" grep -qE '● s-dash .* working' <<< "${out}"

# --- An epic's progress from history, in a project of its own (Q), with no herdr. Each story file
# below names epic x, and is deleted in a different way; only a deletion that closed its story counts.
Q="${ROOT}/q"
qitem() { P="${Q}" item "$@"; }
GQ=(git -C "${Q}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
mkdir -p "${Q}/.swarm/state" "${Q}/src"
git -C "${Q}" init -q -b main
echo .swarm/ > "${Q}/.gitignore"; echo "status" > "${Q}/STATUS.md"
qitem epics/x.md 'status: active'
qitem epics/y.md 'status: active'
qitem stories/y-wait.md 'status: blocked' 'epic: y' 'blocked_by: [x-b]'
qitem stories/y-then.md 'status: later' 'epic: y'
for s in x-merged x-big x-fin x-again x-gone x-scope x-scope2 x-twice x-squash x-ops; do qitem "stories/${s}.md" 'status: ready' 'epic: x'; done
qitem stories/x-own.md 'status: ready' 'epic: x' 'prs: https://github.com/o/r/pull/5'
qitem stories/x-rev.md 'status: review' 'epic: x' 'prs: https://github.com/o/r/pull/1'
# epic: x in the body, not the front matter: never x's, open or finished.
qitem stories/x-body.md 'status: ready' 'kind: code'
qitem stories/y-loose.md 'status: ready' 'kind: code'
echo "epic: x" >> "${Q}/docs/stories/x-body.md"; echo "epic: x" >> "${Q}/docs/stories/y-loose.md"
# A front matter only counts on the first line: this file's later --- block is body.
printf '# late\n\n---\nepic: x\n---\n' > "${Q}/docs/stories/y-late.md"
# CRLF line endings: still x's, and ready.
printf -- '---\r\nstatus: ready\r\nepic: x\r\n---\r\n\r\n# crlf\r\n' > "${Q}/docs/stories/x-crlf.md"
"${GQ[@]}" add -A && "${GQ[@]}" commit -qm board
# A story that listed its PR, deleted with its code (a squash merge looks like this). Counts.
echo 1 > "${Q}/src/a"; "${GQ[@]}" rm -q docs/stories/x-own.md docs/stories/x-body.md; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "ship x-own"
# Its own PR merge, the board file deleted on story/x-merged. Counts. "@@" in the subject must not
# split the commit: commits are split on NUL.
"${GQ[@]}" checkout -qb story/x-merged && "${GQ[@]}" rm -q docs/stories/x-merged.md && "${GQ[@]}" commit -qm "close x-merged"
"${GQ[@]}" checkout -q main && "${GQ[@]}" merge -q --no-ff -m "Merge pull request #2 from o/story/x-merged @@ x" story/x-merged
# A story PR squash-merged: its code and its board deletion in one commit, status still ready, no
# prs. Its own work, so it counts.
echo 4 > "${Q}/src/b"; "${GQ[@]}" rm -q docs/stories/x-squash.md; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "Ship x-squash (#8)"
# A story whose only work beside its board file sits under the board's directory (a runbook in
# docs/operations.md): its own work, so it counts.
echo "runbook" > "${Q}/docs/operations.md"; "${GQ[@]}" rm -q docs/stories/x-ops.md; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "Write the operations runbook (#9)"
# Re-scopes never count. A board/ PR, even one that changes code too:
echo 5 > "${Q}/src/b"; "${GQ[@]}" rm -q docs/stories/x-scope.md; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "Merge pull request #3 from o/board/lead-not-operator"
# and a commit whose only change off the board is a root note (infrafactory #409 edited STATUS.md).
echo "re-scoped" >> "${Q}/STATUS.md"; "${GQ[@]}" rm -q docs/stories/x-scope2.md; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "tidy the board"
# Board-only: a story in review taken off (reconcile's finish) counts; one the swarm logged as
# finished counts; a split (x-big into x-b and x-c in one board commit) does not.
"${GQ[@]}" rm -q docs/stories/x-rev.md docs/stories/x-fin.md && "${GQ[@]}" commit -qm "board: finished"
printf '2026-10-01T10:00:00Z\tfinish\tx-fin\tw1:p1\tok\n' > "${Q}/.swarm/events.tsv"
"${GQ[@]}" rm -q docs/stories/x-big.md; qitem stories/x-b.md 'status: ready' 'epic: x'; qitem stories/x-c.md 'status: ready' 'epic: x'
"${GQ[@]}" add -A && "${GQ[@]}" commit -qm "split x-big"
# Closed by its own PR, added again, then re-scoped away: closed once, so it counts once.
"${GQ[@]}" checkout -qb story/x-twice && "${GQ[@]}" rm -q docs/stories/x-twice.md && "${GQ[@]}" commit -qm "close x-twice"
"${GQ[@]}" checkout -q main && "${GQ[@]}" merge -q --no-ff -m "Merge pull request #4 from o/story/x-twice" story/x-twice
qitem stories/x-twice.md 'status: ready' 'epic: x'; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "x-twice again"
"${GQ[@]}" rm -q docs/stories/x-twice.md && "${GQ[@]}" commit -qm "drop x-twice"
# Deleted by its own PR, then added again: open, not also finished.
"${GQ[@]}" checkout -qb story/x-again && "${GQ[@]}" rm -q docs/stories/x-again.md && "${GQ[@]}" commit -qm "close x-again"
"${GQ[@]}" checkout -q main && "${GQ[@]}" merge -q --no-ff -m "Merge pull request #6 from o/story/x-again" story/x-again
qitem stories/x-again.md 'status: ready' 'epic: x'; "${GQ[@]}" add -A; "${GQ[@]}" commit -qm "x-again again"
# Closed on origin/main, which this checkout has not pulled: open here, not also finished.
"${GQ[@]}" checkout -qb story/x-gone && "${GQ[@]}" rm -q docs/stories/x-gone.md && "${GQ[@]}" commit -qm "close x-gone"
"${GQ[@]}" checkout -q main && "${GQ[@]}" merge -q --no-ff -m "Merge pull request #7 from o/story/x-gone" story/x-gone
git -C "${Q}" update-ref refs/remotes/origin/main HEAD
git -C "${Q}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
git -C "${Q}" reset -q --hard HEAD~1
# Findings dated yesterday and three days ago, and timed events late two days ago and early
# yesterday, all read in calendar days.
day() { python3 -c 'import datetime, sys; print(datetime.date.today() - datetime.timedelta(days=int(sys.argv[1])))' "$1"; }
at() { python3 -c 'import datetime, sys; d = datetime.date.today() - datetime.timedelta(days=int(sys.argv[1])); print(datetime.datetime.combine(d, datetime.time.fromisoformat(sys.argv[2])).astimezone().isoformat())' "$1" "$2"; }
printf '%s\tk1\thttps://github.com/o/r/pull/3\tone from yesterday\n%s\tk2\thttps://github.com/o/r/pull/4\tone from three days ago\n' "$(day 1)" "$(day 3)" > "${Q}/.swarm/findings.tsv"
printf '%s\ttell\tlate-two-days-ago\tw1:p1\tok\n%s\ttell\tearly-yesterday\tw1:p1\tok\n' "$(at 2 23:59:00)" "$(at 1 00:01:00)" >> "${Q}/.swarm/events.tsv"
qdash() { fresh; (cd "${Q}" || exit 1; env -u HERDR_ENV PATH="${ROOT}/nobin:${PATH}" "$@" bash "${SWARM}" dash 2>&1 || true); }
out="$(qdash env)"
# Finished: x-own, x-merged, x-squash, x-ops, x-rev, x-fin, x-twice. Open: x-b, x-c, x-again, x-gone, x-crlf.
XROW='^│ ○ x +█{7}░{5}  7/12  5 ready +│$'
check "progress counts only deletions that closed a story, once each" grep -qE "${XROW}" <<< "${out}"
check "an epic with ready stories and nothing running is ○ ready" grep -qE '^│ ○ x ' <<< "${out}"
check "an epic whose remaining stories are all blocked or later is ⏸" grep -qE '^│ ⏸ y +░{12}  0/2   1 blocked · 1 later +│$' <<< "${out}"
check "the legend names ○ ready" has "○ ready" "$(tail -2 <<< "${out}")"
check "a date-only entry from yesterday reads yesterday" grep -qE '^│ yesterday  ✎ one from yesterday' <<< "${out}"
check "a date-only entry three days old reads 3d ago" grep -qE '^│ +3d ago  ✎ one from three days ago' <<< "${out}"
check "a timed event late two days ago reads 2d ago" grep -qE '^│ +2d ago  · tell late-two-days-ago' <<< "${out}"
check "a timed event over a day ago, early yesterday, reads yesterday" grep -qE '^│ yesterday  · tell early-yesterday|^│ +[0-9]+h ago  · tell early-yesterday' <<< "${out}"
out="$(qdash env GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=diff.noprefix GIT_CONFIG_VALUE_0=true GIT_CONFIG_KEY_1=color.ui GIT_CONFIG_VALUE_1=always GIT_CONFIG_KEY_2=diff.mnemonicPrefix GIT_CONFIG_VALUE_2=true)"
check "progress holds under diff.noprefix and color.ui=always" grep -qE "${XROW}" <<< "${out}"
# The board in a repo of its own (board_dir), with no origin, while the project has origin/main: the
# base ref is resolved in the board's repo, which falls back to its HEAD (x-gone stays open). The
# project's events.tsv has no finish of x-fin, so x-fin does not count here.
R="${ROOT}/r"; B="${ROOT}/rboard"
mkdir -p "${R}/.claude/swarm" "${R}/.swarm"
git -C "${R}" init -q -b main && git -C "${R}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "${R}" update-ref refs/remotes/origin/main HEAD && git -C "${R}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
echo "board_dir = ../rboard/docs" > "${R}/.claude/swarm/config"
cp -R "${Q}/." "${B}" && rm -rf "${B}/.swarm" && git -C "${B}" update-ref -d refs/remotes/origin/main && git -C "${B}" symbolic-ref --delete refs/remotes/origin/HEAD
out="$(fresh; cd "${R}" || exit 1; env -u HERDR_ENV PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a board in its own repo counts from that repo's history" grep -qE '^│ ○ x +█{7}░{5}  6/11  5 ready +│$' <<< "${out}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
