#!/usr/bin/env bash
# dash_widths_test.sh — the frame at each width: COLUMNS, side by side from 140 columns, stacked
# below, and nothing wider than the terminal.
# `swarm.sh dash` against a throwaway board, a fake agents.tsv, findings.tsv and events.tsv, a stub
# herdr on PATH printing a fixed agent list, and a stub gh. stty and tput are stubbed to fail, so the
# width comes from COLUMNS (or the default 100), except in the pty tests.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
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
export PATH="${ROOT}/size:${PATH}" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp"
mkdir -p "${TMPDIR}"
# fresh — drop dash's one-minute cache of gh and cost, so the next run asks again.
fresh() { rm -rf "${TMPDIR}"/swarm-dash-*; }
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
# escalation block's fixed now (SWARM_DASH_NOW, 2026-10-10 noon).
touch -t 202610101100 "${ROOT}/projects/p/sess-esc.jsonl"
printf '2026-10-03\tvacuous-test\thttps://github.com/o/r/pull/7\ta test that could not fail\n' > "${P}/.swarm/findings.tsv"
# Five findings on another PR the same day: one recent row, not five.
for i in 1 2 3 4 5; do printf '2026-10-04\tkind%s\thttps://github.com/o/r/pull/8\tfinding %s\n' "${i}" "${i}" >> "${P}/.swarm/findings.tsv"; done
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
echo "more" >> "${P}/docs/stories/s-three.md"; echo "more" >> "${P}/docs/stories/s-two.md"

widest() { python3 -c 'import sys; print(max(len(l) for l in sys.stdin.read().splitlines()))'; }
# gh-calls.tsv is gh-shim's log of dash's own gh calls, made before the snapshot so the folder's entry holds.
: >> "${P}/.swarm/gh-calls.tsv"
mkdir -p "${P}/.swarm/gh-cache"   # flow's cache of finished GitHub records, which dash's ci refresh (a flow) fills
# shellcheck disable=SC2010 # names swarm.sh wrote, filtered for the one file dash may write
snapshot() { (cd "${P}" && find docs .swarm -path .swarm/gh-cache -prune -o -type f ! -name gh-calls.tsv -print0 | sort -z | xargs -0 cksum
  find docs .swarm -path .swarm/gh-cache -prune -o ! -name gh-calls.tsv -print0 | sort -z | xargs -0 ls -ld) ; }
before="$(snapshot)"

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
check "at 50 columns a needs-you action wraps, not cut" has "! run lead story ask: create the read-only IAM user waits for: the lead !" "${joined}"
check "at 50 columns a wrapped needs-you line is indented under its action" grep -qE '^│   [a-z]' <<< "$(sed -n '/^╭─ needs you/,/^╰/p' <<< "${out}")"
for cols in 79 60 45; do
  fresh; out="$(cd "${P}" || exit 1; HERDR_ENV=1 COLUMNS="${cols}" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash --ladder 2>&1 || true)"
  check "at ${cols} columns no line is wider than the terminal" test "$(widest <<< "${out}")" -le "${cols}"
  check "at ${cols} columns the layout is stacked, without role and model columns" grep -qE '^│   ● conduct-e1 +working +│$' <<< "${out}"
  check "at ${cols} columns a long line is cut with …" has "…" "${out}"
done


check "dash changes nothing under the board or .swarm" test "$(snapshot)" == "${before}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
