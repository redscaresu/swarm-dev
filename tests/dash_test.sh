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
item stories/s-two.md 'status: blocked' 'epic: e1' 'depends_on: [s-one]'
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
# One escalate agent whose session ran on opus (its first message with a model), not the fable its
# policy names; the ladder shows the session's model. No docs agent: docs shows 0.
printf '2026-10-02\tescalate\tx-esc\tclaude\tfable\txhigh\tsess-esc\n' >> "${P}/.swarm/agents.tsv"
# Ahead of opus: a non-string model and a failed turn's "<synthetic>" one, both skipped.
printf '%s\n' '{"type":"user","message":{"role":"user","content":"go"}}' '{"message":{"model":5}}' \
  '{"message":{"id":"e0","model":"<synthetic>"}}' '{"message":{"id":"e1","model":"claude-opus-5-5"}}' \
  '{"message":{"id":"e2","model":"claude-fable-5-1"}}' > "${ROOT}/projects/p/sess-esc.jsonl"
# A chore agent whose log cannot be read: it counts, with no model, and the ladder still draws.
printf '2026-10-02\tchore\tx-chore\tclaude\thaiku\tmedium\tsess-locked\n' >> "${P}/.swarm/agents.tsv"
echo '{}' > "${ROOT}/projects/p/sess-locked.jsonl"; chmod 000 "${ROOT}/projects/p/sess-locked.jsonl"
# A session log's mtime is a sign of life (the stall rule): x-esc's was written before the
# escalation block's fixed now (DASH_NOW, 2026-10-10 noon).
touch -t 202610101100 "${ROOT}/projects/p/sess-esc.jsonl"
printf '2026-10-03\tvacuous-test\thttps://github.com/o/r/pull/7\ta test that could not fail\n' > "${P}/.swarm/findings.tsv"
# Five findings on another PR the same day: one recent row, not five.
for i in 1 2 3 4 5; do printf '2026-10-04\tkind%s\thttps://github.com/o/r/pull/8\tfinding %s\n' "${i}" "${i}" >> "${P}/.swarm/findings.tsv"; done
ago() { python3 -c 'import datetime, sys; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }
printf '2026-10-03T10:00:00Z\tfinish\ts-zero\tw1:p1\tok\n2026-10-04T10:00:00Z\treview\ts-one\tw1:p1\tok\n' > "${P}/.swarm/events.tsv"
# Older actions, so that from 140 columns the recent log is taller than the needs-you box beside it.
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf '2026-09-%02dT10:00:00Z\ttell\told-%s\tw1:p1\tok\n' "${i}" "${i}" >> "${P}/.swarm/events.tsv"; done

# Claude Code's sessions: the conductor (sess-1) and s-three's builder (sess-today) are busy, and
# s-one's builder waits on a permission prompt. The wait checks below rewrite this file.
printf '[{"sessionId":"sess-1","status":"busy"},{"sessionId":"sess-2","status":"waiting","waitingFor":"input"},{"sessionId":"sess-today","status":"busy"}]' > "${ROOT}/claude.json"
# herdr: this project's conductor (working) and builder (blocked), an empty pane (w1:p3), and
# another project's agent (w9:p1), which must not be shown. s-three's herdr status is done while its
# session is busy: the session's word is the one dash shows.
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"conduct-e1","agent_status":"working","pane_id":"w1:p1","agent_session":{"value":"sess-1"}},{"name":"conduct-e2","agent_status":"idle","pane_id":"w1:p8"},{"name":"s-one","agent_status":"blocked","pane_id":"w1:p2"},{"name":"foreign","agent_status":"working","pane_id":"w9:p1"},{"name":"old-done","agent_status":"idle","pane_id":"w1:p4"},{"name":"odd","agent_status":"idle","pane_id":"w1:p5","agent_session":"not-an-object"},{"name":"prose","agent_status":"working","pane_id":"w1:p6"},{"name":"halfway","agent_status":"working","pane_id":"w1:p7"},{"name":"s-three","agent_status":"done","pane_id":"w1:p9"},{"name":"aaaaaaaaaa-bbbbbbbbbb-cccccccccc","agent_status":"working","pane_id":"w1:p10"},{"name":"s-two","agent_status":"starting","pane_id":"w1:p11"},{"name":"s-re-done","agent_status":"idle","pane_id":"w2:p1"},{"name":"s-re","agent_status":"'"${RE_HERDR:-working}"'","pane_id":"w2:p2"},{"name":"s-lost","agent_status":"idle","pane_id":"w2:p3"},{"name":"s-odd","agent_status":"working","pane_id":"w2:p4"},{"name":"cx","agent_status":"blocked","pane_id":"w2:p5"},{"name":"s-dash","agent_status":"working","pane_id":"w2:p6"},{"name":"s-auth","agent_status":"idle","pane_id":"w2:p7"},{"name":"x-esc","agent_status":"working","pane_id":"w2:p8"},{"name":"plan-e9","agent_status":"working","pane_id":"w2:p9"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w1:p1"},{"pane_id":"w1:p2"},{"pane_id":"w1:p3"},{"pane_id":"w9:p1"},{"pane_id":"w1:p4"},{"pane_id":"w1:p5"},{"pane_id":"w1:p6"},{"pane_id":"w1:p7"},{"pane_id":"w1:p8"},{"pane_id":"w1:p9"},{"pane_id":"w1:p10"},{"pane_id":"w1:p11"},{"pane_id":"w2:p1"},{"pane_id":"w2:p2"},{"pane_id":"w2:p3"},{"pane_id":"w2:p4"},{"pane_id":"w2:p5"},{"pane_id":"w2:p6"},{"pane_id":"w2:p7"},{"pane_id":"w2:p8"},{"pane_id":"w2:p9"}]}}' ;;
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
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
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
touch "${P}/docs/stories/README.md"   # init's marker: dash dies without it
"${G[@]}" add docs && "${G[@]}" commit -qm board
"${G[@]}" rm -q docs/stories/s-old.md && "${G[@]}" commit -qm "finish s-old"
"${G[@]}" checkout -qb story/s-zero && "${G[@]}" commit -q --allow-empty -m work
# A fixed merge time, so no relative time in recent moves while the pty tests watch.
"${G[@]}" checkout -q - && GIT_COMMITTER_DATE=2026-10-05T12:00:00Z "${G[@]}" merge -q --no-ff -m "Merge pull request #9 from o/story/s-zero" story/s-zero
fresh; clean="$(cd "${P}" || exit 1; PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a committed board shows no drift line" lacks "board:" "${clean}"
check "with no agent open and nothing held, the frame has no running-now box" lacks "running now" "${clean}"
echo "more" >> "${P}/docs/stories/s-three.md"

snapshot() { (cd "${P}" && find docs .swarm -type f -print0 | sort -z | xargs -0 cksum; ls -laR docs .swarm) ; }
before="$(snapshot)"

fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
for panel in "needs you" "epics" "recent"; do
  check "panel ${panel}" has "╭─ ${panel} ─" "${out}"
done
check "the header is one line: project, version, merge, next, clock" grep -qE '^proj  swarm-dev [0-9.]+  merge human  next wait conduct-e1 +[0-9]{2}:[0-9]{2}:[0-9]{2}$' <<< "$(head -1 <<< "${out}")"
check "the summary line counts epics, working agents, green PRs, stalls and cost" test "$(sed -n 2p <<< "${out}")" == "1 epics active · 3 agents working · 1 PRs green, waiting · 0 stalled · \$24.00 today"
check "below 140 columns, on call and today's escalations follow the summary, on a line of their own when it is full" test "$(sed -n 3p <<< "${out}")" == "on call: fable·xhigh · 0 escalations today"
check "an uncommitted board edit is one line under the summary" has "board: 1 uncommitted edit in the main checkout (reconcile pulls first)" "$(sed -n 4p <<< "${out}")"
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
check "--ladder counts a role's agents, with its sessions' models" has "code       → opus · high  2 opus " "${out}"
check "--ladder names the model a session ran on, not the policy's" has "escalate   → fable · xhigh  1 opus " "${out}"
check "--ladder shows 0 for a role with no agents" grep -qE "docs       → sonnet · medium  0( |$)" <<< "${out}"
check "--ladder has no verify row" lacks "verify" "${out}"
check "--ladder counts an agent whose log cannot be read, with no model" grep -qE "chore      → haiku · medium  1 +escalate" <<< "${out}"
check "--ladder cells are as wide as the longest row: two a row at 100 columns, every role aligned" python3 -c '
import sys
t = sys.stdin.read().splitlines()
rows = t[next(i for i, l in enumerate(t) if "╭─ ladder" in l) + 1:]
rows = rows[:next(i for i, l in enumerate(rows) if l.startswith("╰"))]
cols = {tuple(i for i, c in enumerate(l) if c == "→") for l in rows[:-1]}
sys.exit(not (len(cols) == 1 and len(next(iter(cols))) == 2))' <<< "${out}"
check "below 140 columns the ladder and recent are stacked" lacks "╮ ╭─ recent" "${out}"

fresh; out="$(cd "${P}" || exit 1; env -u HERDR_ENV COLUMNS=160 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash --ladder 2>&1 || true)"
check "COLUMNS sets the width when stty and tput cannot" test "$(widest <<< "${out}")" -eq 160
check "from 140 columns the ladder sits above recent, in the right column" python3 -c '
import sys
t = sys.stdin.read().splitlines()
lad = [(i, l.index("╭─ ladder")) for i, l in enumerate(t) if "╭─ ladder" in l]
rec = [(i, l.index("╭─ recent")) for i, l in enumerate(t) if "╭─ recent" in l]
sys.exit(not (lad and rec and 0 < lad[0][1] == rec[0][1] and lad[0][0] < rec[0][0]))' <<< "${out}"
check "outside a herdr pane, a herdr that answers still shows the agents" grep -qE '● conduct-e1 +conduct +opus·high +working' <<< "${out}"
fresh; out="$(cd "${P}" || exit 1; env -u HERDR_ENV COLUMNS=160 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "at 160 columns the epics and the recent log sit side by side" grep -qE '^│ ! e1 +█.* │ │ +[0-9]{2}[:-][0-9]{2}  . ' <<< "${out}"
check "at 160 columns needs you is the left column's first box, recent the right's" grep -qE '^╭─ needs you ─+╮ ╭─ recent ─+╮$' <<< "${out}"
check "at 160 columns recent's time column is HH:MM today, the date before" grep -qE '^│ 10-05  ⇡ merged #9 story/s-zero ' <<< "$(sed -n '/╭─ recent/{n;s/^.* │ │/│/;p;}' <<< "${out}")"
check "at 160 columns an agent's card has its role, model label and state" grep -qE '│   ● conduct-e1 +conduct +opus·high +working +│ ' <<< "${out}"
check "at 160 columns the status bar is the last lines, with merge, the counts, cost, on call and the keys" grep -qE '^merge human · 1 epics active · 3 agents working · 1 PRs green, waiting · 0 stalled · [$]24[.]00 today · on call: fable·xhigh · 0 escalations today +q quit · t tree · l ladder · r redraw' <<< "$(tail -2 <<< "${out}" | paste -sd' ' -)"
check "at 160 columns the summary line moves into the status bar" test "$(grep -c 'epics active' <<< "${out}")" -eq 1
check "at 160 columns, piped, there are no ANSI escapes" lacks $'\033[' "${out}"
for cols in 140 147 153 159; do
  for view in "" --tree; do
    fresh; out="$(cd "${P}" || exit 1; env -u HERDR_ENV COLUMNS="${cols}" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash --ladder ${view} 2>&1 || true)"
    check "at ${cols} columns ${view:-epics} no line is wider than the terminal" test "$(widest <<< "${out}")" -le "${cols}"
  done
done
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
check "--watch re-measures on SIGWINCH (150 columns, two columns)" test "$(grep -E '^╭─ needs you ─+╮ ╭─ recent ─+╮$' <<< "${text}" | widest)" -eq 150
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
# no worktree commit, no PR, its session log last written then. After the snapshot, since a stall's
# age changes every minute.
mins_ago() { python3 -c 'import sys, time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time() - 60 * int(sys.argv[1]))))' "$1"; }
touch -t "$(mins_ago 120)" "${ROOT}/projects/p/sess-today.jsonl"
printf '%s\tstory\ts-three\tw1:p1\tok\n' "$(ago 120)" >> "${P}/.swarm/events.tsv"
printf '%s\tconduct\te1\tw1:p1\tok\n' "$(ago 4)" >> "${P}/.swarm/events.tsv"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 COLUMNS=160 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "at 160 columns a working agent's card shows its state age, then the time since it started" grep -qE '● conduct-e1 +conduct +opus·high +working [45]m  [45]m +│' <<< "${out}"
check "at 160 columns a stalled builder keeps its !" grep -qE '! s-three +code +opus·high +stalled 1(19|20|21)m +│' <<< "${out}"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a builder working 2 hours with no sign of life is stalled" grep -qE '! s-three .*stalled 1(19|20|21)m' <<< "${out}"
check "a stalled builder needs you" grep -qE '! look at s-three: working 1(19|20|21) min with no commit, edit, session-log write or PR update' <<< "${out}"
check "the summary counts the stall" has " · 1 stalled · " "$(sed -n 2p <<< "${out}")"
check "recent shows a start minutes ago, newest first" grep -qE '^│    4m ago  ▶ conduct e1 ' <<< "$(sed -n '/^╭─ recent/{n;p;}' <<< "${out}")"
check "recent shows hours ago" grep -qE '^│    2h ago  ▶ story s-three ' <<< "${out}"
mkdir -p "${P}/.claude/swarm"; echo "stall_minutes = 300" > "${P}/.claude/swarm/config"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "stall_minutes sets the threshold" lacks "look at s-three" "${out}"
rm "${P}/.claude/swarm/config"
# A file edited a minute ago in s-three's worktree (its last commit 2 hours old) is a sign of life:
# working, not stalled. Aged past stall_minutes, it is not: stalled again.
wt="${P}-wt/s-three"; git init -q "${wt}"
GIT_COMMITTER_DATE="@$(($(date +%s) - 7200))" git -C "${wt}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q --allow-empty -m old
echo wip > "${wt}/wip.txt"; touch -t "$(mins_ago 1)" "${wt}/wip.txt"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a builder with a file edited a minute ago in its worktree is working, not stalled" grep -qE '● s-three .*working' <<< "${out}"
touch -t "$(mins_ago 120)" "${wt}/wip.txt"
fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "the same file edited 2 hours ago leaves it stalled" grep -qE '! s-three .*stalled 1(19|20|21)m' <<< "${out}"
rm -rf "${P}-wt"

# --- Escalation. DASH_NOW fixes dash's now at local noon on 2026-10-10, and every line here is
# minutes before it, so "today" cannot drift across midnight. Two ok escalate builds today (x-esc's
# attempt 3 an hour ago), one yesterday and one failed; each other escalation kind once ok, and a
# reset, a drop and a dialog that failed. x-esc, an escalate agent (agents.tsv), gets a pane and a busy
# session; its newest line (dialog) is 40 minutes old, so stall_minutes is 120 here to keep it working.
NOW="$(python3 -c 'import datetime; print(int(datetime.datetime(2026, 10, 10, 12).timestamp()))')"
before_now() { python3 -c 'import datetime, sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]) - 60 * int(sys.argv[2]), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' "${NOW}" "$1"; }
cp "${P}/.swarm/events.tsv" "${ROOT}/events.before-esc"
{
  printf '%s\tescalate\tx-esc\tw1:p1\tok (attempt 2)\n' "$(before_now 1500)"
  printf '%s\tescalate\tx-esc\tw1:p1\tok (attempt 3)\n' "$(before_now 60)"
  printf '%s\tescalate\ty-esc\tw1:p1\tok (attempt 3)\n' "$(before_now 50)"
  printf '%s\tescalate\tz-esc\tw1:p1\tfailed (exit 1)\n' "$(before_now 45)"
  printf '%s\tdialog\tx-esc\tw1:p1\tok\n' "$(before_now 40)"
  printf '%s\tescalated\tw-esc\tw1:p1\tok (attempts 3, 1 PRs)\n' "$(before_now 35)"
  printf '%s\treset\tw-esc\tw1:p1\tok\n' "$(before_now 30)"
  printf '%s\tdrop\tv-esc\tw1:p1\tok\n' "$(before_now 25)"
  printf '%s\ttell\tt-esc\tw1:p1\tok\n' "$(before_now 20)"
  printf '%s\treset\tr-bad\tw1:p1\tfailed (exit 1)\n' "$(before_now 15)"
  printf '%s\tdrop\td-bad\tw1:p1\tfailed (exit 1)\n' "$(before_now 10)"
  printf '%s\tdialog\tg-bad\tw1:p1\tfailed (exit 1)\n' "$(before_now 5)"
} >> "${P}/.swarm/events.tsv"
printf 'w2:p8 x-esc\n' > "${P}/.swarm/state/x-esc"
mkdir -p "${P}/.claude/swarm"; echo "stall_minutes = 120" > "${P}/.claude/swarm/config"
esc_at="$(python3 -c 'import datetime, sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]) - 3600).strftime("%H:%M"))' "${NOW}")"
printf '[{"sessionId":"sess-esc","status":"busy"}]' > "${ROOT}/claude-esc.json"
escdash() { (cd "${P}" || exit 1; fresh; HERDR_ENV=1 CLAUDE_STUB_AGENTS="${ROOT}/claude-esc.json" DASH_NOW="${NOW}" LINES=80 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true); }
out="$(COLUMNS=160 escdash)"
check "at 160 columns the status bar says who is on call" has "on call: fable·xhigh" "$(tail -2 <<< "${out}")"
check "at 160 columns the status bar counts today's ok escalate builds, not yesterday's or a failed one" has " · 2 escalations today" "$(tail -2 <<< "${out}")"
check "at 160 columns an escalated builder's card shows its state age, attempt and when" grep -qE "● x-esc +escalate +fable·xhigh +working 40m  attempt 3 · ${esc_at} +│" <<< "${out}"
out="$(COLUMNS=100 escdash)"
check "at 100 columns the line under the summary says who is on call and today's escalations" test "$(sed -n 3p <<< "${out}")" == "on call: fable·xhigh · 2 escalations today"
check "at 100 columns an escalated builder's row shows its attempt and when" grep -qE "● x-esc +escalate +fable·xhigh +working 40m +attempt 3 · ${esc_at} +│" <<< "${out}"
recent="$(sed -n '/^╭─ recent/,/^╰/p' <<< "${out}")"
for k in "escalate y-esc" "dialog x-esc" "escalated w-esc" "reset w-esc" "drop v-esc"; do
  check "recent marks ${k%% *} with ▲" grep -qE "^│ +[0-9]+m ago  ▲ ${k}" <<< "${recent}"
done
check "recent keeps · for a tell" grep -qE '^│ +20m ago  · tell t-esc' <<< "${recent}"
for k in "escalate z-esc" "reset r-bad" "drop d-bad" "dialog g-bad"; do
  check "recent marks a failed ${k%% *} ✗" grep -qE "^│ +[0-9]+m ago  ✗ ${k}: failed" <<< "${recent}"
done
echo "escalate_after = 0" >> "${P}/.claude/swarm/config"
check "with escalate_after = 0 nobody is on call" has "on call: off · 2 escalations today" "$(COLUMNS=100 escdash)"
rm "${P}/.claude/swarm/config" "${P}/.swarm/state/x-esc"
cp "${ROOT}/events.before-esc" "${P}/.swarm/events.tsv"

# --- State age. aaaa…-2's builder is working (herdr's word), started 25 minutes ago, and its
# worktree's last commit is 12 minutes old: the row shows 12m right after its state, and at 160
# columns the 25m since its start after that, so 12m can only be the state age.
cp "${P}/.swarm/events.tsv" "${ROOT}/events.before-age"; cp "${P}/.swarm/findings.tsv" "${ROOT}/findings.before-age"
A=aaaaaaaaaa-bbbbbbbbbb-cccccccccc
mkdir -p "${ROOT}/proj-wt/${A}-2" && git -C "${ROOT}/proj-wt/${A}-2" init -q
GIT_COMMITTER_DATE="$(ago 12)" git -C "${ROOT}/proj-wt/${A}-2" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q --allow-empty -m work
printf '%s\tstory\t%s-2\tw1:p1\tok\n' "$(ago 25)" "${A}" >> "${P}/.swarm/events.tsv"
agedash() { (cd "${P}" || exit 1; fresh; HERDR_ENV=1 LINES=80 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true); }
out="$(COLUMNS=160 agedash)"
check "at 160 columns a working builder shows its state age, then the time since it started" grep -qE '● aaaaaaaaaa-bbbbbbbbbb-ccccccc… .* working 1[23]m  2[56]m +│' <<< "${out}"
check "at 160 columns a conductor keeps its time since start after its state age" grep -qE '● conduct-e1 +conduct +opus·high +working [45]m  [45]m +│' <<< "${out}"
check "at 160 columns a stalled builder still shows stalled" grep -qE '! s-three +code +opus·high +stalled 1(19|20|21)m +│' <<< "${out}"
out="$(COLUMNS=100 agedash)"
check "at 100 columns a working builder shows its state age" grep -qE '● aaaaaaaaaa-bbbbbbbbbb-ccccccc… .* working 1[23]m +│$' <<< "${out}"
check "at 100 columns a stalled builder still shows stalled" grep -qE '! s-three .*stalled 1(19|20|21)m +│$' <<< "${out}"
check "a stalled builder still needs you, in the same words" grep -qE '! look at s-three: working 1(19|20|21) min with no commit, edit, session-log write or PR update' <<< "${out}"
check "a conductor below stall_minutes is working, not stalled" grep -qE '● conduct-e1 +conduct +opus·high +working [45]m +│$' <<< "${out}"
# The conductor's newest sign (its start, from its own pane) is 4 minutes old: past stall_minutes = 3.
echo "stall_minutes = 3" > "${P}/.claude/swarm/config"
out="$(COLUMNS=100 agedash)"
check "a conductor past stall_minutes is stalled" grep -qE '! conduct-e1 +conduct +opus·high +stalled [45]m +│$' <<< "${out}"
check "a stalled conductor needs you" grep -qE '! look at conduct-e1: working [45] min with no swarm action' <<< "${out}"
# A session log written a minute ago is a sign of life for any agent with a Claude session: the
# conductor (sess-1) and a planner (plan-e9, no story and no events.tsv line) are working. With the
# logs written 10 minutes ago, past stall_minutes, both are stalled.
printf 'w2:p9 plan-e9\n' > "${P}/.swarm/state/plan-e9"
printf '%s\tplan\tplan-e9\tclaude\topus\thigh\tsess-plan\n' "$(date +%F)" >> "${P}/.swarm/agents.tsv"
printf '[{"sessionId":"sess-1","status":"busy"},{"sessionId":"sess-today","status":"busy"},{"sessionId":"sess-plan","status":"busy"}]' > "${ROOT}/claude-plan.json"
for s in sess-1 sess-plan; do echo '{}' > "${ROOT}/projects/p/${s}.jsonl"; touch -t "$(mins_ago 1)" "${ROOT}/projects/p/${s}.jsonl"; done
out="$(CLAUDE_STUB_AGENTS="${ROOT}/claude-plan.json" COLUMNS=100 agedash)"
check "a conductor whose session log was written a minute ago is working" grep -qE '● conduct-e1 +conduct +opus·high +working [12]m +│$' <<< "${out}"
check "a planner whose session log was written a minute ago is working" grep -qE '● plan-e9 +plan +opus·high +working [12]m +│$' <<< "${out}"
touch -t "$(mins_ago 10)" "${ROOT}/projects/p/sess-1.jsonl" "${ROOT}/projects/p/sess-plan.jsonl"
out="$(CLAUDE_STUB_AGENTS="${ROOT}/claude-plan.json" COLUMNS=100 agedash)"
check "a conductor whose session log is older than stall_minutes is stalled" grep -qE '! conduct-e1 +conduct +opus·high +stalled [45]m +│$' <<< "${out}"
check "a planner whose session log is older than stall_minutes is stalled" grep -qE '! plan-e9 +plan +opus·high +stalled (9|10|11)m +│$' <<< "${out}"
rm "${P}/.swarm/state/plan-e9" "${ROOT}/projects/p/sess-1.jsonl" "${ROOT}/projects/p/sess-plan.jsonl"
# A nudge its pane sent a minute ago (wait's, or the lead's tell:nudge) and a tell that never reached
# anyone are not signs of life (STALL_PY's rule): the conductor stays stalled.
printf '%s\tnudge\ts-one\tw1:p1\tok\n%s\ttell:nudge\ts-one\tw1:p1\tok\n%s\ttell:findings\ts-one\tw1:p1\tfailed (exit 1)\n' "$(ago 1)" "$(ago 1)" "$(ago 1)" >> "${P}/.swarm/events.tsv"
check "a conductor whose only recent pane lines are nudges is still stalled" grep -qE '! conduct-e1 +conduct +opus·high +stalled [45]m +│$' <<< "$(COLUMNS=100 agedash)"
# The lead's board-pr step a minute ago, named after s-three (a re-scope of it), is no sign of life
# for s-three's builder: it stays stalled.
cp "${P}/.swarm/events.tsv" "${ROOT}/events.bak"
printf '%s\tboard-pr:start\ts-three\tw0:p1\tok\n' "$(ago 1)" >> "${P}/.swarm/events.tsv"
check "a board-pr line named after a story is no sign of life for its builder" grep -qE '! s-three .*stalled' <<< "$(COLUMNS=100 agedash)"
cp "${ROOT}/events.bak" "${P}/.swarm/events.tsv"
# A note the lead left the conductor a minute ago (tell:note, from the lead's pane) is no sign of
# life: with its session log older than stall_minutes it stays stalled. The same line as tell:resume is.
echo '{}' > "${ROOT}/projects/p/sess-1.jsonl"; touch -t "$(mins_ago 10)" "${ROOT}/projects/p/sess-1.jsonl"
cp "${P}/.swarm/events.tsv" "${ROOT}/events.bak"
for k in note resume; do
  cp "${ROOT}/events.bak" "${P}/.swarm/events.tsv"
  printf '%s\ttell:%s\tconduct-e1\tw0:p1\tok\n' "$(ago 1)" "${k}" >> "${P}/.swarm/events.tsv"
  out="$(COLUMNS=100 agedash)"
  if [[ ${k} == note ]]; then check "a conductor whose only recent line is a note to it is still stalled" grep -qE '! conduct-e1 +conduct +opus·high +stalled [45]m +│$' <<< "${out}"
  else check "a conductor whose only recent line is a resume tell to it is working" grep -qE '● conduct-e1 +conduct +opus·high +working [12]m +│$' <<< "${out}"; fi
done
cp "${ROOT}/events.bak" "${P}/.swarm/events.tsv"; rm "${ROOT}/projects/p/sess-1.jsonl"
# A command its own pane ran a minute ago (a review of s-one, not naming it) is a sign of life.
printf '%s\treview\ts-one\tw1:p1\tok\n' "$(ago 1)" >> "${P}/.swarm/events.tsv"
check "a line from a conductor's own pane is a sign of life" grep -qE '● conduct-e1 +conduct +opus·high +working [12]m +│$' <<< "$(COLUMNS=100 agedash)"
rm "${P}/.claude/swarm/config"

# --- Findings in recent. Eight declined findings on #133, a tell, three more on #133, a lone one on
# #134, a failed one, and a fix logged through log-finding (findings.tsv and events.tsv both).
{
  for i in 1 2 3 4 5 6 7 8; do printf '%s\tlog-finding:declined\tkind-x https://github.com/o/r/pull/133\tw1:p1\tok\n' "$(ago $((30 - i)))"; done
  printf '%s\ttell\tt-split\tw1:p1\tok\n' "$(ago 20)"
  for i in 1 2 3; do printf '%s\tlog-finding:declined\tkind-x https://github.com/o/r/pull/133\tw1:p1\tok\n' "$(ago $((20 - i)))"; done
  printf '%s\tlog-finding:declined\tkind-y https://github.com/o/r/pull/134\tw1:p1\tok\n' "$(ago 16)"
  printf '%s\tlog-finding:declined\tkind-x https://github.com/o/r/pull/133\tw1:p1\tfailed (exit 1)\n' "$(ago 15)"
  # One PR written three ways: one run, numbered from the PR, never from a commit or path after it.
  printf '%s\ttell\tt-split2\tw1:p1\tok\n' "$(ago 14)"
  for t in o/r#136 https://github.com/o/r/pull/136/files https://github.com/o/r/pull/136/commits/abc123; do
    printf '%s\tlog-finding:declined\tkind-w %s\tw1:p1\tok\n' "$(ago 13)" "${t}"
  done
} >> "${P}/.swarm/events.tsv"
(cd "${P}" && env -u HERDR_PANE_ID bash "${SWARM}" log-finding kind-z https://github.com/o/r/pull/135 "the fixed one" >/dev/null)
recent="$(sed -n '/^╭─ recent/,/^╰/p' <<< "$(COLUMNS=100 agedash)")"
check "eight consecutive declined findings on one PR are one recent row" test "$(grep -c '· 8 findings declined on #133 ' <<< "${recent}")" -eq 1
check "a tell between two runs of declined findings splits them" has "· 3 findings declined on #133 " "${recent}"
check "a declined run is one row: no single declined line on #133 is left" lacks "log-finding:declined kind-x https://github.com/o/r/pull/133 " "${recent}"
check "a PR's URL, its subpaths and owner/repo#N fold into one declined run" has "· 3 findings declined on #136 " "${recent}"
check "a lone declined finding reads as before" has "· log-finding:declined kind-y https://github.com/o/r/pull/134 " "${recent}"
check "a failed log-finding line stays its own ✗ row" has "✗ log-finding:declined kind-x https://github.com/o/r/pull/133: fail" "${recent}"
check "a fix logged through log-finding shows once in recent" test "$(grep -c 'the fixed one' <<< "${recent}")" -eq 1
check "a fix's log-finding line is not a recent row" lacks "log-finding kind-z" "${recent}"
cp "${ROOT}/events.before-age" "${P}/.swarm/events.tsv"; cp "${ROOT}/findings.before-age" "${P}/.swarm/findings.tsv"
rm -rf "${ROOT}/proj-wt"
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
check "wait --stall says why" grep -qE '^stalled: working 1(19|20|21) min with no commit, edit, session-log write or PR update$' <<< "${out}"
# A nudge is wait's doing, not a sign of life: a fresh `nudge s-three` line leaves the builder stalled.
printf '%s\tnudge\ts-three\tw1:p1\tok\n' "$(ago 0)" >> "${P}/.swarm/events.tsv"
if out="$(long_ago --stall s-three 3000)"; then rc=0; else rc=$?; fi
check "a nudge line does not lower a builder's stall age" test "${rc}" -eq 3
# A tell is a swarm action on its story when it reached the builder: its line (tell:<kind>, the slug
# as its target) lowers the stall age. A tell:nudge is a nudge, as wait's are, and a tell refused
# (the session busy) never reached the builder: neither lowers it.
printf '[{"sessionId":"sess-today","status":"idle"}]' > "${ROOT}/claude.json.told"
echo "- a finding" > "${ROOT}/findings.md"; cp "${P}/.swarm/events.tsv" "${ROOT}/events.keep"
tellstall() { # <session file> <kind> — tell s-three with its session read from <session file>, then
  # wait --stall on it (its session busy again); print "<told?>:<wait's exit>" and drop the tell's line
  local told=no rc=0
  (cd "${P}" && HERDR_ENV=1 CLAUDE_STUB_AGENTS="$1" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" tell s-three "$2" "${ROOT}/findings.md" >/dev/null 2>&1) && told=yes
  long_ago --stall s-three 3000 >/dev/null || rc=$?
  cp "${ROOT}/events.keep" "${P}/.swarm/events.tsv"
  echo "${told}:${rc}"
}
check "a delivered tell lowers its builder's stall age" test "$(tellstall "${ROOT}/claude.json.told" findings)" == "yes:1"
check "a tell:nudge does not lower its builder's stall age" test "$(tellstall "${ROOT}/claude.json.told" nudge)" == "yes:3"
check "a refused tell does not lower its builder's stall age" test "$(tellstall "${ROOT}/claude.json" findings)" == "no:3"
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
# newer session each time. s-auth is idle, and its transcript ends on an expired login: auth, not idle.
S="${ROOT}/s"; mkdir -p "${S}/.swarm/state" "${S}/docs/stories"; git -C "${S}" init -q; touch "${S}/docs/stories/README.md"
printf 'w2:p1 s-re\nw2:p2 s-re\nw2:p3 s-lost\nw2:p4 s-odd\nw2:p5 cx\nw2:p6 s-dash\nw2:p7 s-auth\n' > "${S}/.swarm/state/t"
cp "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/login-expired.jsonl" "${ROOT}/projects/p/auth.jsonl"
printf '2026-10-13\tcode\t%s\t%s\t%s\thigh\t%s\n' s-re claude opus re-old s-re claude opus re-new s-lost claude sonnet lost \
  s-odd claude haiku odd cx codex gpt - s-dash claude fable - s-auth claude opus auth > "${S}/.swarm/agents.tsv"
sdash() { # <re-old status> <re-new status> <herdr's s-re status> — dash --tree in S
  printf '[{"sessionId":"re-old","status":"%s"},{"sessionId":"re-new","status":"%s"},{"sessionId":"odd","status":"compacting"},{"sessionId":"auth","status":"idle"}]' "$1" "$2" > "${ROOT}/s.json"
  fresh; (cd "${S}" || exit 1; CLAUDE_STUB_AGENTS="${ROOT}/s.json" RE_HERDR="$3" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash --tree 2>&1 || true)
}
out="$(sdash busy idle working)"
check "a recorded session with no entry is ! gone" grep -qE '! s-lost .* gone: session ended' <<< "${out}"
check "a session in a state dash does not know is ! unknown" grep -qE '! s-odd .* unknown: no session state' <<< "${out}"
needs="$(sed -n '/^╭─ needs you/,/^╰/p' <<< "${out}")"
check "needs you lists an agent whose session is gone" has "! look at s-lost: session ended" "${needs}"
check "needs you lists an agent whose session state is unknown" has "! look at s-odd: no session state" "${needs}"
check "an idle agent whose login expired is ! auth, not idle" grep -qE '! s-auth .* auth: login expired' <<< "${out}"
check "needs you lists an agent whose login expired, with /login" has "! auth: run /login (s-auth's login expired), then /swarm-dev:swarm tells it to resume" "${needs}"
check "a reused name shows the newer session (older busy, newer idle)" grep -qE '✓ s-re +code .* idle' <<< "${out}"
check "a retired pane is retired, whatever its name's newest session says" grep -qE '✓ s-re-done .* retired' <<< "${out}"
check "a codex agent herdr says is blocked is ! waiting" grep -qE '! cx .* waiting on a prompt' <<< "${out}"
check "a codex agent waiting is in needs you" has "! answer cx: herdr agent read cx" "${out}"
check "an agent with no session recorded shows herdr's word" grep -qE '● s-dash .* working' <<< "${out}"
# Each model's label carries its own colour, on a terminal (a pty, 160 columns); NO_COLOR prints none.
cat > "${ROOT}/ptyonce.py" <<'PY'
import fcntl, os, pty, struct, sys, termios
pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 40, int(sys.argv[1]), 0, 0))
    os.execvp("bash", ["bash"] + sys.argv[2:])
out = b""
while True:
    try:
        b = os.read(fd, 65536)
    except OSError:
        break
    if not b:
        break
    out += b
os.waitpid(pid, 0)
sys.stdout.buffer.write(out)
PY
ptyonce() { (fresh; cd "${S}" || exit 1; CLAUDE_STUB_AGENTS="${ROOT}/s.json" PATH="${ROOT}/bin:${REALPATH}" python3 -I "${ROOT}/ptyonce.py" 160 "${SWARM}" dash --tree --ladder); }
w="$(ptyonce)"
for m in "opus:208" "sonnet:75" "haiku:114" "fable:213" "codex:250"; do
  check "on a terminal the ${m%:*} label is colour ${m#*:}" has $'\033[38;5;16;48;5;'"${m#*:}m ${m%:*}·high "$'\033[0m' "${w}"
done
check "on a terminal the ladder names a model in its colour" has $'\033[38;5;208mopus · xhigh\033[0m' "${w}"
check "NO_COLOR on a terminal prints no escape codes" lacks $'\033[' "$(NO_COLOR=1 ptyonce)"
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
qitem stories/y-wait.md 'status: blocked' 'epic: y' 'depends_on: [x-b]'
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
touch "${Q}/docs/stories/README.md"
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
printf '%s\ttell:findings\tlate-two-days-ago\tw1:p1\tok\n%s\ttell:nudge\tearly-yesterday\tw1:p1\tok\n' "$(at 2 23:59:00)" "$(at 1 00:01:00)" >> "${Q}/.swarm/events.tsv"
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
check "a timed event late two days ago reads 2d ago" grep -qE '^│ +2d ago  · tell:findings late-two-days-ago' <<< "${out}"
check "a timed event over a day ago, early yesterday, reads yesterday" grep -qE '^│ yesterday  · tell:nudge early-yesterday|^│ +[0-9]+h ago  · tell:nudge early-yesterday' <<< "${out}"
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

# --- lead = session, in a project of its own (L) whose panes are w4's: needs you keeps the user's
# steps (a story's **You:** line, an expired login, a draft HLD) and the rest goes to the lead's queue.
L="${ROOT}/lead"; mkdir -p "${L}/.swarm/state" "${L}/.claude/swarm" "${ROOT}/lbin"; git -C "${L}" init -q
litem() { # <path under docs> <body> <front-matter line>...
  local path="${L}/docs/$1" body="$2" title; shift 2
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; echo; printf '%s\n' "${body}"; } > "${path}"
}
mkdir -p "${L}/docs/stories"; touch "${L}/docs/stories/README.md"
litem stories/you-ask.md 'After the release merges. **You:** create the read-only user' 'status: ready' 'kind: lead'
litem stories/no-you.md 'The lead runs the migration.' 'status: ready' 'kind: lead'
# Prose that names the convention is no step: this story is the lead's.
litem stories/talks.md 'The lead does it all, so there is no **You:** step.' 'status: ready' 'kind: lead'
# A kind waiting_on_user lists that dash's rows do not parse: a verbatim line.
litem stories/v-odd.md '' 'status: ready' 'kind: by hand'
litem stories/esc.md "$(printf '%s\n' '<!-- swarm.sh escalated: swarm.sh reset removes this block -->' 'Failed on Fable: re-scope or drop.' '<!-- /swarm.sh escalated -->')" \
  'status: ready' 'kind: lead' 'escalated_from: code'
# An impossible story (#144's block) is the lead's too, even with a **You:** line in its body.
litem stories/esc-imp.md "$(printf '%s\n' '**You:** a step from before it escalated' '<!-- swarm.sh escalated: swarm.sh reset removes this block -->' '**Impossible.** the judge called it impossible' '<!-- /swarm.sh escalated -->')" \
  'status: ready' 'kind: lead' 'escalated_from: code'
litem stories/m-green.md '' 'status: review' 'prs: https://github.com/o/l/pull/1'
litem stories/m-fail.md '' 'status: review' 'prs: https://github.com/o/l/pull/2'
litem stories/m-unk.md '' 'status: review' 'prs: https://github.com/o/l/pull/3'
litem stories/m-run.md '' 'status: review' 'prs: https://github.com/o/l/pull/4'
litem stories/l-stall.md '' 'status: ready' 'kind: code'
litem hld/2026-10-01-d.md '' 'status: draft'
printf 'w4:p1 l-auth\nw4:p2 l-wait\nw4:p3 l-empty\nw4:p4 l-gone\nw4:p5 l-stall\n' > "${L}/.swarm/state/l"
printf '2026-10-13\tcode\t%s\tclaude\topus\thigh\t%s\n' l-auth lauth l-wait lwait l-gone lgone l-stall lstall > "${L}/.swarm/agents.tsv"
cp "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/login-expired.jsonl" "${ROOT}/projects/p/lauth.jsonl"
printf '%s\tstory\tl-stall\tw4:p5\tok\n' "$(ago 120)" > "${L}/.swarm/events.tsv"
printf '[{"sessionId":"lauth","status":"idle"},{"sessionId":"lwait","status":"waiting","waitingFor":"input"},{"sessionId":"lstall","status":"busy"}]' > "${ROOT}/l.json"
cat > "${ROOT}/lbin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"l-auth","agent_status":"idle","pane_id":"w4:p1"},{"name":"l-wait","agent_status":"blocked","pane_id":"w4:p2"},{"name":"l-gone","agent_status":"idle","pane_id":"w4:p4"},{"name":"l-stall","agent_status":"working","pane_id":"w4:p5"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w4:p1"},{"pane_id":"w4:p2"},{"pane_id":"w4:p3"},{"pane_id":"w4:p4"},{"pane_id":"w4:p5"}]}}' ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w4","label":"lead"}]}}' ;;
  *) exit 1 ;;
esac
STUB
# gh: PR 1 is green, PR 2 failing, PR 3 gh cannot read (unknown), and PR 4's CI is running.
cat > "${ROOT}/lbin/gh" <<'STUB'
#!/bin/sh
case "$1 $2 $3" in
  "pr view https://github.com/o/l/pull/1") echo '{"statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}' ;;
  "pr view https://github.com/o/l/pull/2") echo '{"statusCheckRollup":[{"status":"COMPLETED","conclusion":"FAILURE"}]}' ;;
  "pr view https://github.com/o/l/pull/4") echo '{"statusCheckRollup":[{"status":"IN_PROGRESS","conclusion":""}]}' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "${ROOT}/lbin/herdr" "${ROOT}/lbin/gh"
ldash() { # <columns> — dash in L
  fresh; (cd "${L}" || exit 1; env -u HERDR_ENV COLUMNS="$1" CLAUDE_STUB_AGENTS="${ROOT}/l.json" PATH="${ROOT}/lbin:${PATH}" bash "${SWARM}" dash 2>&1 || true)
}
lbox() { # <title> <frame> — that box of the left column, the right column cut off
  python3 -c '
import sys
t, out = sys.argv[1], []
for l in sys.stdin.read().splitlines():
    if l.startswith("╭─ " + t + " ") or out:
        out.append(l.split("╮ ")[0].split("╯ ")[0].split("│ │")[0])
        if l.startswith("╰"):
            break
print("\n".join(out))' "$1" <<< "$2"
}
joined() { sed -e 's/^│ //' -e 's/ *│$//' <<< "$1" | paste -sd' ' - | tr -s ' '; }
YOURS=("! run lead story you-ask" "! auth: run /login (l-auth's login expired)" "! agree draft HLD 2026-10-01-d: /hld 2026-10-01-d")
LEADS=("! merge l#1 (✓ green) m-green" "! merge l#2 (✗ failing) m-fail" "! merge m-unk: https://github.com/o/l/pull/3" "! merge l#4 (◐ CI running) m-run"
  "! run lead story no-you" "! run lead story talks" "! by hand: v-odd"
  "! decide escalated story esc: swarm.sh reset esc or swarm.sh drop esc" "! decide escalated story esc-imp: swarm.sh reset esc-imp or swarm.sh drop esc-imp" "! answer l-wait (waiting on input)" "! close the empty pane l-empty"
  "! look at l-gone: session ended" "! look at l-stall: working 1")
echo "lead = session" > "${L}/.claude/swarm/config"
for cols in 100 160; do
  out="$(ldash "${cols}")"
  needs="$(lbox "needs you" "${out}")"; queue="$(lbox "lead's queue" "${out}")"
  check "lead = session at ${cols} columns: the lead's queue is drawn right after needs you" \
    grep -qE "^╭─ lead's queue ─" <<< "$(sed -n '/^╰/{n;p;q;}' <<< "${out}")"
  check "lead = session at ${cols} columns: needs you has only the user's ${#YOURS[@]} steps" test "$(grep -c '^│ ! ' <<< "${needs}")" -eq ${#YOURS[@]}
  check "lead = session at ${cols} columns: the lead's queue has only its ${#LEADS[@]} rows" test "$(grep -c '^│ ! ' <<< "${queue}")" -eq ${#LEADS[@]}
  for want in "${YOURS[@]}"; do
    check "lead = session at ${cols} columns: needs you holds '${want}'" has "${want}" "$(joined "${needs}")"
    check "lead = session at ${cols} columns: the lead's queue lacks '${want}'" lacks "${want}" "$(joined "${queue}")"
  done
  for want in "${LEADS[@]}"; do
    check "lead = session at ${cols} columns: the lead's queue holds '${want}'" has "${want}" "$(joined "${queue}")"
    check "lead = session at ${cols} columns: needs you lacks '${want}'" lacks "${want}" "$(joined "${needs}")"
  done
  check "lead = session at ${cols} columns: the legend says ! is needs you or the lead" has "! needs you or the lead (session gone or unknown)" "${out}"
done
# Once reset (an ok reset line in events.tsv), an escalated story offers only drop, as next does.
printf '2026-10-14T10:00:00Z\treset\tesc\tw4:p5\tok\n' >> "${L}/.swarm/events.tsv"
check "lead = session: an escalated story reset once offers only drop" \
  has "! decide escalated story esc: swarm.sh drop esc" "$(joined "$(lbox "lead's queue" "$(ldash 100)")")"
# A held story (held_for:) can always lift its hold with reset, as next says, even after a reset.
litem stories/esc-held.md "$(printf '%s\n' '<!-- swarm.sh escalated: swarm.sh reset removes this block -->' '**Held (paused).** lift or drop' '<!-- /swarm.sh escalated -->')" \
  'status: ready' 'kind: lead' 'escalated_from: code' 'held_for: paused'
printf '2026-10-14T10:00:00Z\treset\tesc-held\tw4:p5\tok\n' >> "${L}/.swarm/events.tsv"
check "lead = session: a held story offers reset (lift the hold) or drop, though reset before" \
  has "! decide escalated story esc-held: swarm.sh reset esc-held or swarm.sh drop esc-held" "$(joined "$(lbox "lead's queue" "$(ldash 100)")")"
rm "${L}/docs/stories/esc-held.md"
rm "${L}/.claude/swarm/config"
out="$(ldash 100)"
check "lead off: no lead's queue" lacks "lead's queue" "${out}"
check "lead off: the legend says ! is needs you" has "! needs you (session gone or unknown)" "${out}"
check "lead off: needs you still lists merges, agents to look at and lead stories" has "! merge l#2 (✗ failing) m-fail" "$(joined "$(lbox "needs you" "${out}")")"
check "lead off: an escalated lead story with no **You:** step is not listed" lacks "decide escalated story esc" "${out}"

# --- A running codex review (codex-review's marker, .swarm/state/codex-review.<pid>: start epoch, base,
# cwd) is a row under its worktree's epic, with its age, in neither needs you nor the lead's queue. A
# marker whose pid is dead, or older than codex_minutes (10) plus 1, shows nothing, and dash leaves both.
C="${ROOT}/codex"; S="${C}/.swarm/state"; mkdir -p "${S}" "${C}/.claude/swarm" "${C}/docs/epics" "${C}/docs/stories"; git -C "${C}" init -q
touch "${C}/docs/stories/README.md"; echo "lead = session" > "${C}/.claude/swarm/config"
citem() { local path="${C}/docs/$1" body="$2" title; title="$(basename "$1" .md)"; shift 2; { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; echo; echo "${body}"; } > "${path}"; }
citem epics/alpha.md '' 'status: active'; citem epics/beta.md '' 'status: active'
citem stories/cs-one.md '' 'status: ready' 'epic: alpha'
citem stories/c-you.md '**You:** create the user' 'status: ready' 'kind: lead'
citem stories/c-lead.md 'The lead runs it.' 'status: ready' 'kind: lead'
# The live pids are this test's own sleeps, off its stdout so no pipe waits on them, killed on exit.
sleep 300 >/dev/null 2>&1 & live1=$!; sleep 300 >/dev/null 2>&1 & live2=$!; sleep 300 >/dev/null 2>&1 & live3=$!
sleep 300 >/dev/null 2>&1 & live4=$!
trap 'kill "${live1}" "${live2}" "${live3}" "${live4}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
sh -c 'exit 0' & dead=$!; wait "${dead}" || true
marker() { printf '%s\t%s\t%s\n' "$(( $(date +%s) - $2 * 60 ))" "${4:-main}" "${ROOT}/repo-wt/$3" > "${S}/codex-review.$1"; }   # <pid> <minutes ago> <worktree> [base]
marker "${live1}" 7 cs-one; marker "${live2}" 3 epic-beta; marker "${dead}" 2 dead-one; marker "${live3}" 12 old-one
# A long slug on an epic base: the name column is cut, never the base or the age.
citem stories/a-rather-long-story-slug.md '' 'status: ready' 'epic: alpha'
marker "${live4}" 4 a-rather-long-story-slug epic/alpha
before="$(cksum "${S}"/codex-review.*)"
for cols in 100 160; do
  out="$(fresh; cd "${C}" || exit 1; env -u HERDR_ENV -u SWARM_PROJECT COLUMNS="${cols}" PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
  # under <row text> — the epic header (a progress bar's line) above that row.
  under() { awk -v r="$1" '/[█░]/ { e = $0 } index($0, r) { print e; exit }' <<< "${out}" | grep -oE '(alpha|beta) '; }
  check "codex row at ${cols} columns: a story worktree's review shows with its 7m age and base" grep -qE 'codex review cs-one .*running 7m vs main' <<< "${out}"
  check "codex row at ${cols} columns: a story worktree's review sits under its story's epic" test "$(under 'codex review cs-one')" = "alpha "
  check "codex row at ${cols} columns: an epic worktree's review sits under that epic" test "$(under 'codex review epic-beta')" = "beta "
  check "codex row at ${cols} columns: a dead pid's marker shows no row" lacks "codex review dead-one" "${out}"
  check "codex row at ${cols} columns: a marker past codex_minutes plus 1 shows no row" lacks "codex review old-one" "${out}"
  check "codex row at ${cols} columns: not in needs you" lacks "codex review" "$(lbox "needs you" "${out}")"
  check "codex row at ${cols} columns: not in the lead's queue" lacks "codex review" "$(lbox "lead's queue" "${out}")"
done
check "codex row at 160 columns: a long slug's row keeps its base and age" grep -qE 'codex review a-rather.*running 4m vs epic/alpha' <<< "${out}"
check "dash leaves every codex-review marker, dead or overdue, as it was" test "$(cksum "${S}"/codex-review.*)" = "${before}"

# --- Running now, in a project of its own (D) whose panes are w5's: two epic builders at work, three
# idle one-off builders (their stories on no epic) and one held story.
D="${ROOT}/running"; mkdir -p "${D}/.swarm/state" "${D}/docs/epics" "${D}/docs/stories" "${ROOT}/dbin"; git -C "${D}" init -q
# An upstream remote beside origin: gh is asked about origin by name, never left to pick.
git -C "${D}" remote add upstream https://github.com/up/d.git && git -C "${D}" remote add origin https://github.com/o/d.git
touch "${D}/docs/stories/README.md"
ditem() { local path="${D}/docs/$1" title; title="$(basename "$1" .md)"; shift; { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"; }
ditem epics/re.md 'status: active'
ditem stories/rb-one.md 'status: ready' 'epic: re' 'prs: https://github.com/o/d/pull/11'
ditem stories/rb-two.md 'status: ready' 'epic: re' 'prs: https://github.com/o/d/pull/12'
# ro-review's PR is open on story/ro-review, which its file lists only from review on: gh pr list finds it.
ditem stories/ro-review.md 'status: ready'
ditem stories/ro-merge.md 'status: review' 'prs: https://github.com/o/d/pull/14'
ditem stories/ro-imp.md 'status: ready'
ditem stories/rh-held.md 'status: ready' 'kind: lead' 'escalated_from: code' 'held_for: paused'
printf 'w5:p1 rb-one\nw5:p2 rb-two\nw5:p3 ro-review\nw5:p4 ro-merge\nw5:p5 ro-imp\n' > "${D}/.swarm/state/d"
printf '%s\tcode\t%s\tclaude\topus\thigh\t%s\n' "$(date +%F)" rb-one drb1 "$(date +%F)" rb-two drb2 \
  "$(date +%F)" ro-review dro1 "$(date +%F)" ro-merge dro2 "$(date +%F)" ro-imp dro3 > "${D}/.swarm/agents.tsv"
printf '%s\tstory\trb-one\tw5:p1\tok\n' "$(ago 25)" > "${D}/.swarm/events.tsv"
dlog() { # <session> <minutes ago> <content block>
  printf '{"type":"assistant","timestamp":"%s","message":{"content":[%s]}}\n' "$(ago "$2")" "$3" >> "${ROOT}/projects/p/$1.jsonl"
}
dlog drb1 3 '{"type":"tool_use","name":"Bash","input":{}}'
dlog drb2 12 '{"type":"text","text":"reading"},{"type":"tool_use","name":"Read","input":{}}'
# rb-two's newest tool is a Write of 80 KB, longer than the 64 KB dash reads first, then its short result.
dlog drb2 10 "{\"type\":\"tool_use\",\"name\":\"Write\",\"input\":{\"content\":\"$(head -c 81920 /dev/zero | tr '\0' x)\"}}"
printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","content":"ok"}]}}\n' "$(ago 9)" >> "${ROOT}/projects/p/drb2.jsonl"
dlog dro1 30 '{"type":"text","text":"Opened the PR."}'
# A newest line whose message is not an object costs nothing: ro-review's row still reads.
echo '{"type":"assistant","timestamp":"2026-10-01T00:00:00Z","message":"odd"}' >> "${ROOT}/projects/p/dro1.jsonl"
dlog dro2 30 '{"type":"text","text":"Done; the PR is in review."}'
dlog dro3 40 '{"type":"text","text":"The plan first."}'
dlog dro3 20 '{"type":"text","text":"IMPOSSIBLE: the API has no such call"}'
# Then 80 KB of hook output and a small tool call: the reply is past the 64 KB read first, so dash
# reads further back for an idle one-off builder, the one row that needs it.
printf '{"type":"attachment","timestamp":"%s","content":"%s"}\n' "$(ago 19)" "$(head -c 81920 /dev/zero | tr '\0' x)" >> "${ROOT}/projects/p/dro3.jsonl"
dlog dro3 18 '{"type":"tool_use","name":"Bash","input":{}}'
printf '[{"sessionId":"drb1","status":"busy"},{"sessionId":"drb2","status":"busy"},{"sessionId":"dro1","status":"idle"},{"sessionId":"dro2","status":"idle"},{"sessionId":"dro3","status":"idle"}]' > "${ROOT}/d.json"
cat > "${ROOT}/dbin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"rb-one","agent_status":"working","pane_id":"w5:p1"},{"name":"rb-two","agent_status":"working","pane_id":"w5:p2"},{"name":"ro-review","agent_status":"idle","pane_id":"w5:p3"},{"name":"ro-merge","agent_status":"idle","pane_id":"w5:p4"},{"name":"ro-imp","agent_status":"idle","pane_id":"w5:p5"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w5:p1"},{"pane_id":"w5:p2"},{"pane_id":"w5:p3"},{"pane_id":"w5:p4"},{"pane_id":"w5:p5"}]}}' ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w5","label":"running"}]}}' ;;
  *) exit 1 ;;
esac
STUB
# gh: PR 11 is green, PR 12 failing, PR 14 green, and origin's open PR list (url and head only) has
# PR 13 on story/ro-review, whose CI is running.
cat > "${ROOT}/dbin/gh" <<'STUB'
#!/bin/sh
case "$1 $2 $3" in
  "pr view https://github.com/o/d/pull/11"|"pr view https://github.com/o/d/pull/14") echo '{"state":"OPEN","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}' ;;
  "pr view https://github.com/o/d/pull/12") echo '{"state":"OPEN","statusCheckRollup":[{"status":"COMPLETED","conclusion":"FAILURE"}]}' ;;
  "pr list -R") [ "$4" = https://github.com/o/d.git ] || exit 1
    echo '[{"url":"https://github.com/o/d/pull/13","headRefName":"story/ro-review"},{"url":"https://github.com/o/d/pull/15","headRefName":"other"}]' ;;
  "pr view https://github.com/o/d/pull/13") echo '{"state":"OPEN","statusCheckRollup":[{"status":"IN_PROGRESS","conclusion":""}]}' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "${ROOT}/dbin/herdr" "${ROOT}/dbin/gh"
for cols in 100 160; do
  out="$(fresh; cd "${D}" || exit 1; env -u HERDR_ENV COLUMNS="${cols}" CLAUDE_STUB_AGENTS="${ROOT}/d.json" PATH="${ROOT}/dbin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
  run="$(lbox "running now" "${out}")"; epicp="$(lbox "epics" "${out}")"
  check "running now at ${cols} columns: a builder's row has its running time, last tool and PR's CI state" grep -qE '● rb-one +up 25m +Bash 3m ago +#11 green' <<< "${run}"
  check "running now at ${cols} columns: the other builder's row too, its time from agents.tsv, its last entry past 64 KB" grep -qE '● rb-two +up [0-9hm]+ +Write 9m ago +#12 failing' <<< "${run}"
  check "running now at ${cols} columns: a held story with its cause" has "⏸ held rh-held: paused" "${run}"
  # Narrower than 140 columns it sits just above recent; from 140, in the left column just under the epics.
  check "running now at ${cols} columns: sits where its layout puts it" python3 -c '
import sys
t, wide = sys.stdin.read().splitlines(), sys.argv[1] == "160"
r = next(i for i, l in enumerate(t) if l.startswith("╭─ running now"))
end = next(i for i in range(r, len(t)) if t[i].startswith("╰"))
sys.exit(not (t[r - 1].startswith("╰") and "╭─ epics" in "".join(t[:r]) if wide else t[end + 1].startswith("╭─ recent")))' "${cols}" <<< "${out}"
  check "one-off builder at ${cols} columns: an open PR not in review waits for review" grep -qE 'ro-review .*#13 waits for review' <<< "${epicp}"
  check "running now at ${cols} columns: a PR found on the builder's branch shows its CI state" grep -qE 'ro-review .*#13 CI running' <<< "${run}"
  check "one-off builder at ${cols} columns: a story in review waits for the lead's merge" grep -qE "ro-merge .*#14 waits for the lead's merge" <<< "${epicp}"
  check "one-off builder at ${cols} columns: a last reply of IMPOSSIBLE: reads IMPOSSIBLE" grep -qE 'ro-imp .*IMPOSSIBLE' <<< "${epicp}"
  check "running now at ${cols} columns: a builder with no PR says so" grep -qE '! ro-imp .*no PR yet|✓ ro-imp .*no PR yet' <<< "${run}"
  check "no agent row at ${cols} columns reads a bare idle" lacks " idle " "${out}"
  out="$(fresh; cd "${D}" || exit 1; env -u HERDR_ENV COLUMNS="${cols}" CLAUDE_STUB_AGENTS="${ROOT}/d.json" PATH="${ROOT}/dbin:${PATH}" bash "${SWARM}" dash --tree 2>&1 || true)"
  check "--tree at ${cols} columns: an idle one-off builder says what it waits on" grep -qE 'ro-review .*#13 waits for review' <<< "${out}"
  check "--tree at ${cols} columns: no agent row reads a bare idle" lacks " idle " "${out}"
done

# --- A git repo with no board: dash and dash --watch stop at once and name swarm.sh init.
N="${ROOT}/noboard"; mkdir -p "${N}"; git -C "${N}" init -q
for args in "" "--watch 1"; do
  # shellcheck disable=SC2086 # args is split on purpose
  # perl's alarm kills it after 5 seconds (exit 142): macOS has no timeout(1).
  if out="$(fresh; cd "${N}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/nobin:${PATH}" perl -e 'alarm 5; exec @ARGV' bash "${SWARM}" dash ${args} 2>&1 </dev/null)"; then rc=0; else rc=$?; fi
  check "dash${args:+ }${args} with no board exits 1 within 5 s" test "${rc}" -eq 1
  check "dash${args:+ }${args} with no board says no board and names swarm.sh init" grep -q 'no board.*swarm.sh init' <<< "${out}"
  check "dash${args:+ }${args} with no board does not say nothing needs you" lacks "nothing needs you" "${out}"
done
# A board with nothing in progress or waiting: nothing needs you, and exit 0.
mkdir -p "${N}/docs/stories"; touch "${N}/docs/stories/README.md"
if out="$(fresh; cd "${N}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1)"; then rc=0; else rc=$?; fi
check "dash on an empty board exits 0" test "${rc}" -eq 0
check "dash on an empty board says nothing needs you" has "nothing needs you" "${out}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
