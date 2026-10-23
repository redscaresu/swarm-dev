#!/usr/bin/env bash
# dash_watch_test.sh — --watch, off a terminal and on one (a pty): redraws, keys, colour and a
# failed render.
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
REALPATH="${PATH}"
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
# Every watch's clock is fixed (SWARM_DASH_NOW) here, so its ages (s-three's "up 15h54m") cannot tick
# over a minute between frames and print a changed frame; the header's own HH:MM:SS still moves. The
# row's day comes from it too, so a setup that crosses midnight still agrees with the clock.
DASH_NOW="$(date +%s)"
printf '%s\tcode\ts-three\tclaude\topus\thigh\tsess-today\n' "$(python3 -c 'import datetime, sys; print(datetime.date.fromtimestamp(int(sys.argv[1])))' "${DASH_NOW}")" >> "${P}/.swarm/agents.tsv"
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

# --watch off a terminal prints a frame only when it changed, plain, until stopped.
# The stubs go first on PATH, so no watch here reaches the real herdr or gh. A python3 ahead of them
# logs each run of dash_render.py, one per frame. Renders run one after another, so once the third
# has started the second has been compared with the first and, had it changed, printed: the test
# waits up to 60 s for that, and an unchanged frame must not have printed again.
mkdir -p "${ROOT}/countpy"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\ncase "$1" in */dash_render.py) echo render >> "%s" ;; esac\nexec "%s" "$@"\n' "${ROOT}/renders.log" "$(command -v python3)" > "${ROOT}/countpy/python3"
chmod +x "${ROOT}/countpy/python3"
renders() { if [ -f "${ROOT}/renders.log" ]; then wc -l < "${ROOT}/renders.log" | tr -d ' '; else echo 0; fi; }
(cd "${P}" && exec env -u HERDR_ENV SWARM_DASH_NOW="${DASH_NOW}" PATH="${ROOT}/countpy:${ROOT}/bin:${PATH}" bash "${SWARM}" dash --watch 1 > "${ROOT}/watch.out" 2>&1) &
pid=$!
for _ in $(seq 300); do [ "$(renders)" -ge 3 ] && break; sleep 0.2; done
got="$(renders)"
kill -TERM "${pid}" || true; wait "${pid}" || true
w="$(cat "${ROOT}/watch.out")"
check "--watch off a terminal draws the frame" has "─ needs you" "${w}"
check "--watch off a terminal renders a third frame" test "${got}" -ge 3
check "--watch off a terminal does not repeat an unchanged frame" test "$(grep -c -- '─ needs you' <<< "${w}")" -eq 1
check "--watch off a terminal has no ANSI escapes" lacks $'\033' "${w}"

# --watch on a terminal: a pty, 30x120, its size read with the real stty. ptywatch.py runs
# `dash --watch <seconds>` and times everything from its first frame (its first cursor home, waited
# for up to 30 seconds), so a slow render only makes the run longer: it resizes the pty to 30x150 and
# sends SIGWINCH <resize-after> seconds after it (0: never), types each <key>@<seconds> given after
# <q>, and types q <q> seconds after it, or with H<n> once n cursor homes have come and with N<n>
# once n frames have (at most 15 seconds after the first frame, well inside --watch 30), then kills
# the watch if it is still running 5 seconds later. A key or q waits for 0.3 seconds with no output:
# typed mid-frame, the tty would echo it between the bytes of a character.
cat > "${ROOT}/ptywatch.py" <<'PY'
import fcntl, os, pty, re, select, signal, struct, sys, termios, time
swarm, out_path, every, resize_after, q = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), sys.argv[5]
until = (q[0], int(q[1:])) if q[0] in "HN" else None
q_after = 15.0 if until else float(q)
keys = [(k.split("@")[0].encode(), float(k.split("@")[1])) for k in sys.argv[6:]]
def size(fd, rows, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
def seen(kind):
    if kind == "H":
        return out.count(b"\x1b[H")
    return re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", out).count("╭─ needs you".encode())
pid, fd = pty.fork()
if pid == 0:
    size(0, 30, 120)
    os.execvp("bash", ["bash", swarm, "dash", "--watch", every])
out, start, first, resized, typed, status, last = b"", time.time(), None, False, False, None, time.time()
while status is None:
    if first is None and (b"\x1b[H" in out or time.time() - start > 30):
        first = time.time()
    now = time.time() - first if first is not None else -1
    quiet = time.time() - last > 0.3
    if resize_after and not resized and now > resize_after:
        size(fd, 30, 150); os.kill(pid, signal.SIGWINCH); resized = True
    while keys and now > keys[0][1] and quiet:
        os.write(fd, keys.pop(0)[0])
    if until and now >= 0 and seen(until[0]) >= until[1]:
        q_after, until = min(q_after, now), None
    if not typed and now > q_after and quiet:
        os.write(fd, b"q"); typed = True
    if now > q_after + 5:
        os.kill(pid, signal.SIGKILL)
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            out += os.read(fd, 65536); last = time.time()
        except OSError:
            pass
    done, st = os.waitpid(pid, os.WNOHANG)
    if done:
        status = st
while select.select([fd], [], [], 0.5)[0]:   # what the watch wrote before it exited, still in the pty
    try:
        chunk = os.read(fd, 65536)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
open(out_path, "wb").write(out)
sys.exit(os.waitstatus_to_exitcode(status))
PY
ptywatch() { # <out> <seconds> <resize-after> <q> [<key>@<seconds>...]; PTY_BIN puts another stub dir first on PATH
  (cd "${P}" && env -u HERDR_ENV SWARM_DASH_NOW="${DASH_NOW}" PATH="${PTY_BIN:-${ROOT}/bin}:${ROOT}/bin:${REALPATH}" python3 -I "${ROOT}/ptywatch.py" "${SWARM}" "$@")
}
plain() { python3 -c 'import re, sys; print(re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", sys.stdin.read().replace("\r", "")))' < "$1"; }
frames() { grep -o -- '╭─ needs you' | wc -l | tr -d ' '; }

# Nothing changes after the first frame at --watch 1: one full frame, then the header line rewritten
# each second (q once three cursor homes have come).
if ptywatch "${ROOT}/pty.out" 1 0 H3; then rc=0; else rc=$?; fi
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
# At --watch 30, a resize 2 seconds after the first frame redraws at once (q once two frames have
# come, at most 15 seconds after the first), at the new width.
ptywatch "${ROOT}/pty2.out" 30 2 N2 || true
text="$(plain "${ROOT}/pty2.out")"
check "--watch redraws at once on SIGWINCH" test "$(frames <<< "${text}")" -eq 2
check "--watch re-measures on SIGWINCH (150 columns, two columns)" test "$(grep -E '^╭─ needs you ─+╮ ╭─ recent ─+╮$' <<< "${text}" | widest)" -eq 150
# t shows the tree in place of the epics, l adds the ladder (beside recent from 140 columns).
ptywatch "${ROOT}/pty4.out" 30 0 N3 t@1.5 l@2.5 || true
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
(cd "${P}" && exec env -u HERDR_ENV SWARM_DASH_NOW="${DASH_NOW}" PATH="${ROOT}/badpy:${ROOT}/bin:${PATH}" bash "${SWARM}" dash --watch 1 > "${ROOT}/badwatch.out" 2>&1) &
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

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
