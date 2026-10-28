#!/usr/bin/env bash
# dash_needs_you_test.sh — session states, and lead = session: needs you keeps the user's steps and
# the lead's queue the rest.
# `swarm.sh dash` against a throwaway board, a fake agents.tsv, findings.tsv and events.tsv, a stub
# herdr on PATH printing a fixed agent list, and a stub gh. stty and tput are stubbed to fail, so the
# width comes from COLUMNS (or the default 100), except in the pty tests.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

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
# Claude Code's sessions: the conductor (sess-1) and s-three's builder (sess-today) are busy, and
# s-one's builder waits on a permission prompt.
printf '[{"sessionId":"sess-1","status":"busy"},{"sessionId":"sess-2","status":"waiting","waitingFor":"input"},{"sessionId":"sess-today","status":"busy"}]' > "${ROOT}/claude.json"

ago() { python3 -c 'import datetime, sys; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }

# herdr: this project's conductor (working) and builder (blocked), an empty pane (w1:p3), and
# another project's agent (w9:p1), which must not be shown. s-three's herdr status is done while its
# session is busy: the session's word is the one dash shows.
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"conduct-e1","agent_status":"working","pane_id":"w1:p1","agent_session":{"value":"sess-1"}},{"name":"conduct-e2","agent_status":"idle","pane_id":"w1:p8"},{"name":"s-one","agent_status":"blocked","pane_id":"w1:p2"},{"name":"foreign","agent_status":"working","pane_id":"w9:p1"},{"name":"old-done","agent_status":"idle","pane_id":"w1:p4"},{"name":"odd","agent_status":"idle","pane_id":"w1:p5","agent_session":"not-an-object"},{"name":"prose","agent_status":"working","pane_id":"w1:p6"},{"name":"halfway","agent_status":"working","pane_id":"w1:p7"},{"name":"s-three","agent_status":"done","pane_id":"w1:p9"},{"name":"aaaaaaaaaa-bbbbbbbbbb-cccccccccc","agent_status":"working","pane_id":"w1:p10"},{"name":"s-two","agent_status":"starting","pane_id":"w1:p11"},{"name":"s-re-done","agent_status":"idle","pane_id":"w2:p1"},{"name":"s-re","agent_status":"'"${RE_HERDR:-working}"'","pane_id":"w2:p2"},{"name":"s-lost","agent_status":"idle","pane_id":"w2:p3"},{"name":"s-odd","agent_status":"working","pane_id":"w2:p4"},{"name":"cx","agent_status":"blocked","pane_id":"w2:p5"},{"name":"s-dash","agent_status":"working","pane_id":"w2:p6"},{"name":"s-auth","agent_status":"idle","pane_id":"w2:p7"},{"name":"x-esc","agent_status":"working","pane_id":"w2:p8"},{"name":"plan-e9","agent_status":"working","pane_id":"w2:p9"},{"name":"s-limit","agent_status":"working","pane_id":"w2:p10"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w1:p1"},{"pane_id":"w1:p2"},{"pane_id":"w1:p3"},{"pane_id":"w9:p1"},{"pane_id":"w1:p4"},{"pane_id":"w1:p5"},{"pane_id":"w1:p6"},{"pane_id":"w1:p7"},{"pane_id":"w1:p8"},{"pane_id":"w1:p9"},{"pane_id":"w1:p10"},{"pane_id":"w1:p11"},{"pane_id":"w2:p1"},{"pane_id":"w2:p2"},{"pane_id":"w2:p3"},{"pane_id":"w2:p4"},{"pane_id":"w2:p5"},{"pane_id":"w2:p6"},{"pane_id":"w2:p7"},{"pane_id":"w2:p8"},{"pane_id":"w2:p9"},{"pane_id":"w2:p10"}]}}' ;;
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
  "agent read") [ "$3" = w2:p10 ] || exit 0   # s-limit's pane: the usage-limit dialog, or with LIMIT_WAITING the line after it
    if [ -n "${LIMIT_WAITING:-}" ]; then printf '%s\n' '⏺ Working on it.' '⚠ Usage limit reached · limit resets 3pm' '  Continuing shortly'
    else printf '%s\n' '⏺ Working on it.' '❯ 1. Stop and wait for limit to reset' '  2. Wait here, then continue automatically'; fi ;;
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

# --- Session states, in a project of its own (S) whose panes are w2's: a session with no entry
# (s-lost) and one in a state not known (s-odd) need a look; a reused name (s-re: the older agent
# retired to s-re-done, the newer running) shows its newer session; a codex agent (cx) and one with
# no session recorded (s-dash) show herdr's word. herdr says s-re is RE_HERDR, the opposite of its
# newer session each time. s-auth is idle, and its transcript ends on an expired login: auth, not idle.
S="${ROOT}/s"; mkdir -p "${S}/.swarm/state" "${S}/docs/stories"; git -C "${S}" init -q; touch "${S}/docs/stories/README.md"
printf 'w2:p1 s-re\nw2:p2 s-re\nw2:p3 s-lost\nw2:p4 s-odd\nw2:p5 cx\nw2:p6 s-dash\nw2:p7 s-auth\nw2:p10 s-limit\n' > "${S}/.swarm/state/t"
cp "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/login-expired.jsonl" "${ROOT}/projects/p/auth.jsonl"
printf '2026-10-13\tcode\t%s\t%s\t%s\thigh\t%s\n' s-re claude opus re-old s-re claude opus re-new s-lost claude sonnet lost \
  s-odd claude haiku odd cx codex gpt - s-dash claude fable - s-auth claude opus auth s-limit claude opus limit > "${S}/.swarm/agents.tsv"
sdash() { # <re-old status> <re-new status> <herdr's s-re status> — dash --tree in S
  printf '[{"sessionId":"re-old","status":"%s"},{"sessionId":"re-new","status":"%s"},{"sessionId":"odd","status":"compacting"},{"sessionId":"auth","status":"idle"},{"sessionId":"limit","status":"busy"}]' "$1" "$2" > "${ROOT}/s.json"
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
check "a working agent whose pane is on the usage-limit dialog is usage-limit, not working" grep -qE '⏸ s-limit .* usage-limit' <<< "${out}"
check "an agent on the usage limit is not in needs you" lacks s-limit "${needs}"
st="$(cd "${S}" || exit 1; HERDR_ENV=1 CLAUDE_STUB_AGENTS="${ROOT}/s.json" RE_HERDR=working PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status 2>&1 || true)"
check "status shows usage-limit for an agent on the usage limit" grep -qE '^  s-limit +usage-limit  \[' <<< "${st}"
sed 's/"limit","status":"busy"/"limit","status":"idle"/' "${ROOT}/s.json" > "${ROOT}/s-idle.json"
st="$(cd "${S}" || exit 1; HERDR_ENV=1 LIMIT_WAITING=1 CLAUDE_STUB_AGENTS="${ROOT}/s-idle.json" RE_HERDR=working PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status --all 2>&1 || true)"
check "an idle agent under the usage-limit waiting line is idle in status" grep -qE '^  s-limit +idle: ' <<< "${st}"
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
# A second story with a **You:** step: needs you shows only the first one's, with +1 more.
litem stories/you-two.md '**You:** rotate the key' 'status: ready' 'kind: lead'
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
# A costs: money merge: the user's under either merge setting.
litem stories/m-paid.md '' 'status: review' 'costs: money' 'prs: https://github.com/o/l/pull/5'
# With merge = human a merge is the user's unless its agreed HLD grants merge (hgm) and it does not cost
# money: g-ok is the lead's, g-paid (costs: money) and g-none (its HLD hg grants epics only) the user's,
# as are the m- stories above, under no HLD. With merge = agent only the costs: money ones are (below).
litem hld/hgm.md '' 'status: agreed' 'grants: [merge]' 'planned: 2026-10-01'
litem epics/ge.md '' 'status: active' 'hld: hgm'
litem epics/gn.md '' 'status: active' 'hld: hg'
litem stories/g-ok.md '' 'status: review' 'epic: ge' 'prs: https://github.com/o/l/pull/7'
litem stories/g-paid.md '' 'status: review' 'epic: ge' 'costs: money' 'prs: https://github.com/o/l/pull/8'
litem stories/g-none.md '' 'status: review' 'epic: gn' 'prs: https://github.com/o/l/pull/10'
# An epic in review under the granting HLD: its merge row is the lead's too.
litem epics/ge-rev.md '' 'status: review' 'hld: hgm' 'prs: https://github.com/o/l/pull/11'
# A story a close kept (kept:, its PR not reviewed): the lead's to review or drop, never a merge row.
litem stories/k-kept.md '' 'status: review' 'prs: https://github.com/o/l/pull/6' 'kept: 2026-10-14 close (not reviewed)'
litem stories/l-stall.md '' 'status: ready' 'kind: code'
# A started story whose builder's pane is gone (no_agent_lines' no-agent: line): the lead's, with its exit.
litem stories/l-na.md '' 'status: ready' 'kind: code'
litem epics/d.md '' 'status: draft'
litem hld/h.md '' 'status: draft'
# A staged draft (stage: and an hld: naming an agreed HLD that grants epics) waits on v1.3.0's tag and
# then the lead's stage step: a lead's-queue row, no agree row.
litem hld/hg.md '' 'status: agreed' 'grants: [epics]'
litem epics/c.md '' 'status: draft' 'stage: v1.4.0' 'hld: hg'
# Drafts the epic guard would let go active unagreed (waiting_on_user's lead line): one whose parent:
# is split, one under an agreed HLD that grants epics. A lead's-queue row each, no agree row.
litem epics/pa.md '' 'status: split'
litem epics/kid.md '' 'status: draft' 'parent: pa'
litem epics/uh.md '' 'status: draft' 'hld: hg'
printf 'w4:p1 l-auth\nw4:p2 l-wait\nw4:p3 l-empty\nw4:p4 l-gone\nw4:p5 l-stall\n' > "${L}/.swarm/state/l"
printf '2026-10-13\tcode\t%s\tclaude\topus\thigh\t%s\n' l-auth lauth l-wait lwait l-gone lgone l-stall lstall > "${L}/.swarm/agents.tsv"
cp "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/login-expired.jsonl" "${ROOT}/projects/p/lauth.jsonl"
printf '%s\tstory\tl-stall\tw4:p5\tok\n' "$(ago 120)" > "${L}/.swarm/events.tsv"
printf '%s\t%s\tl-na\tw4:p6\tok\n' "$(ago 30)" story "$(ago 20)" no-agent >> "${L}/.swarm/events.tsv"
printf '[{"sessionId":"lauth","status":"idle"},{"sessionId":"lwait","status":"waiting","waitingFor":"input"},{"sessionId":"lstall","status":"busy"}]' > "${ROOT}/l.json"
cat > "${ROOT}/lbin/herdr" <<'STUB'
#!/bin/sh
# With NA_LISTED set, l-na's builder is listed in w4:p6. With PANE_FAIL set, the pane list fails.
NA_AGENT=""; NA_PANE=""
if [ -n "${NA_LISTED:-}" ]; then NA_AGENT=',{"name":"l-na","agent_status":"working","pane_id":"w4:p6"}'; NA_PANE=',{"pane_id":"w4:p6"}'; fi
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"l-auth","agent_status":"idle","pane_id":"w4:p1"},{"name":"l-wait","agent_status":"blocked","pane_id":"w4:p2"},{"name":"l-gone","agent_status":"idle","pane_id":"w4:p4"},{"name":"l-stall","agent_status":"working","pane_id":"w4:p5"}'"${NA_AGENT}"']}}' ;;
  "pane list") [ -z "${PANE_FAIL:-}" ] || exit 1
    echo '{"result":{"panes":[{"pane_id":"w4:p1"},{"pane_id":"w4:p2"},{"pane_id":"w4:p3"},{"pane_id":"w4:p4"},{"pane_id":"w4:p5"}'"${NA_PANE}"']}}' ;;
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
  "pr view https://github.com/o/l/pull/5") echo '{"statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}' ;;
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
YOURS=("! run lead story you-ask" "! auth: run /login (l-auth's login expired)" "! agree draft epic d: /epic d" "! agree draft HLD h: /hld h"
  "! merge l#1 (✓ green) m-green" "! merge l#5 (✓ green) m-paid (costs money)" "! merge l#2 (✗ failing) m-fail" "! merge m-unk: https://github.com/o/l/pull/3" "! merge l#4 (◐ CI running) m-run"
  "! merge g-paid (costs money): https://github.com/o/l/pull/8" "! merge g-none: https://github.com/o/l/pull/10")
LEADS=("! merge g-ok: https://github.com/o/l/pull/7" "! merge epic ge-rev: https://github.com/o/l/pull/11"
  "! run lead story no-you" "! run lead story talks" "! by hand: v-odd"
  "! review kept story k-kept: swarm.sh review k-kept https://github.com/o/l/pull/6 or swarm.sh close k-kept --drop"
  "! no agent on story l-na: swarm.sh hold l-na <reason>"
  "! decide escalated story esc: swarm.sh reset esc or swarm.sh drop esc" "! decide escalated story esc-imp: swarm.sh reset esc-imp or swarm.sh drop esc-imp" "! answer l-wait (waiting on input)" "! close the empty pane l-empty"
  "! look at l-gone: session ended" "! look at l-stall: working 1" "! staged epic c: stage v1.4.0, after v1.3.0"
  "! set draft epic kid active: parent pa is split" "! set draft epic uh active: hld hg grants epics")
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
  check "lead = session at ${cols} columns: a staged draft has no agree draft epic row" lacks "agree draft epic c" "${out}"
  check "lead = session at ${cols} columns: a draft whose parent: is split has no agree draft epic row" lacks "agree draft epic kid" "${out}"
  check "lead = session at ${cols} columns: a draft under an HLD granting epics has no agree draft epic row" lacks "agree draft epic uh" "${out}"
  check "lead = session at ${cols} columns: a draft HLD is one needs-you row, not also a waiting line" \
    test "$(grep -c 'draft HLD h\|draft hld' <<< "${out}")" -eq 1
  check "lead = session at ${cols} columns: the legend says ! is needs you or the lead" has "! needs you or the lead (session gone or unknown)" "${out}"
  check "lead = session at ${cols} columns: needs you shows the first **You:** step's text, with +1 more" \
    has "! run lead story you-ask waits for: you: create the read-only user +1 more" "$(joined "${needs}")"
  check "lead = session at ${cols} columns: the other **You:** step is not listed" lacks "rotate the key" "${out}"
  check "lead = session at ${cols} columns: a ready lead story with no **You:** line waits for the lead" \
    has "! run lead story no-you waits for: the lead" "$(joined "${queue}")"
  check "lead = session at ${cols} columns: the no-agent row follows the kept row" \
    grep -q "review kept story k-kept.*no agent on story l-na" <<< "$(joined "${queue}")"
  # L has no commits, so no row's file gives a wait start: l-na's no-agent line is the only one.
  check "lead = session at ${cols} columns: the oldest wait starts at the no-agent line" has "waiting on you or the lead, oldest " "${out}"
done
# With l-na's builder listed in a pane this project opened, no_agent_lines prints nothing: no row.
echo "w4:p6 l-na" >> "${L}/.swarm/state/l"
out="$(NA_LISTED=1 ldash 100)"
check "lead = session: with the builder listed, no no-agent row" lacks "no agent on story l-na" "${out}"
check "lead = session: and the lead's queue still has the kept row" has "review kept story k-kept" "$(joined "$(lbox "lead's queue" "${out}")")"
sed -i.bak '/^w4:p6 l-na$/d' "${L}/.swarm/state/l"; rm -f "${L}/.swarm/state/l.bak"
# herdr's pane list fails but its agent list answers: no_agent_lines needs only the agent list.
check "lead = session: with herdr's pane list failing, the no-agent row stays" \
  has "! no agent on story l-na: swarm.sh hold l-na <reason>" "$(joined "$(lbox "lead's queue" "$(PANE_FAIL=1 ldash 100)")")"
# A no-agent row explained by a failed start (no no-agent line) waits from that start, 2h30m ago, not
# from its file's last commit (L has none, so no age at all) or l-na's newer no-agent line.
litem stories/l-nf.md '' 'status: ready' 'kind: code'
printf '%s\t%s\tl-nf\t-\t%s\n' "$(ago 200)" story ok "$(ago 150)" restart failed >> "${L}/.swarm/events.tsv"
out="$(ldash 100)"
check "lead = session: a story whose restart failed is a no-agent row" \
  has "! no agent on story l-nf: swarm.sh hold l-nf <reason>" "$(joined "$(lbox "lead's queue" "${out}")")"
check "lead = session: and its row waits from the failed start" has "waiting on you or the lead, oldest 2h" "${out}"
rm "${L}/docs/stories/l-nf.md"
# With merge = agent swarm.sh merge holds a costs: money story for the user: no lead session can merge it.
# With lead_epics = on every draft is the lead's, the plain draft d too: no agree row left.
printf 'lead = session\nlead_epics = on\n' > "${L}/.claude/swarm/config"; out="$(ldash 100)"
needs="$(lbox "needs you" "${out}")"; queue="$(lbox "lead's queue" "${out}")"
check "lead = session, lead_epics = on: the lead's queue holds the plain draft" has "! set draft epic d active: lead_epics = on" "$(joined "${queue}")"
check "lead = session, lead_epics = on: needs you has no agree draft epic row" lacks "agree draft epic" "$(joined "${needs}")"
printf 'lead = session\nmerge = agent\n' > "${L}/.claude/swarm/config"; out="$(ldash 100)"
check "lead = session, merge = agent: a costs: money merge is under needs you" \
  has "! merge l#5 (✓ green) m-paid (costs money)" "$(joined "$(lbox "needs you" "${out}")")"
check "lead = session, merge = agent: a costs: money merge is not in the lead's queue" \
  lacks "! merge l#5 (✓ green) m-paid (costs money)" "$(joined "$(lbox "lead's queue" "${out}")")"
# merge = agent keeps the rule from before grants: costs: money is the user's, every other merge the lead's.
needs="$(joined "$(lbox "needs you" "${out}")")"; queue="$(joined "$(lbox "lead's queue" "${out}")")"
for want in "! merge l#1 (✓ green) m-green" "! merge g-ok: https://github.com/o/l/pull/7" "! merge g-none: https://github.com/o/l/pull/10"; do
  check "lead = session, merge = agent: '${want}' is in the lead's queue" has "${want}" "${queue}"
  check "lead = session, merge = agent: '${want}' is not under needs you" lacks "${want}" "${needs}"
done
check "lead = session, merge = agent: a costs: money merge under a granting HLD is under needs you" \
  has "! merge g-paid (costs money): https://github.com/o/l/pull/8" "${needs}"
# An epic in review listing the same held PR: one row for it.
litem epics/ep-paid.md '' 'status: review' 'prs: https://github.com/o/l/pull/5'; out="$(ldash 100)"
check "lead = session, merge = agent: a held PR a story and its epic both list is one row" \
  test "$(grep -c 'l#5' <<< "$(lbox "needs you" "${out}")$(lbox "lead's queue" "${out}")")" -eq 1
rm -f "${L}/docs/epics/ep-paid.md"
# A review story with no live agent: under merge = agent no_agent_lines names it. With no passing review
# its exit is review-agent, a row beside its merge row. Its merge row waits from its review line,
# 3h20m ago, not from its newer no-agent line.
litem stories/l-nr.md '' 'status: review' 'kind: code' 'prs: https://github.com/o/l/pull/9'
printf '%s\t%s\tl-nr\t-\tok\n' "$(ago 240)" story "$(ago 200)" review "$(ago 10)" no-agent >> "${L}/.swarm/events.tsv"
out="$(ldash 100)"; queue="$(joined "$(lbox "lead's queue" "${out}")")"
check "lead = session, merge = agent: a review story with no agent has its merge row" has "! merge l-nr: https://github.com/o/l/pull/9" "${queue}"
check "lead = session, merge = agent: with no passing review, a no-agent row with review-agent too" \
  has "! no agent on story l-nr: swarm.sh review-agent l-nr https://github.com/o/l/pull/9" "${queue}"
check "lead = session, merge = agent: its merge row waits from its review line" has "waiting on you or the lead, oldest 3h" "${out}"
# A review that passed on its head: the exit is that merge, so the merge row is its one row.
H=0123456789abcdef0123456789abcdef01234567
mkdir -p "${L}/.swarm/reviews"; printf 'head: %s\n\n## Findings\n\nNone.\n' "${H}" > "${L}/.swarm/reviews/l-nr.md"
out="$(ldash 100)"
check "lead = session, merge = agent: with a passing review, the merge row is its one row" \
  test "$(grep -c 'l-nr' <<< "$(lbox "needs you" "${out}")$(lbox "lead's queue" "${out}")")" -eq 1
rm "${L}/docs/stories/l-nr.md" "${L}/.swarm/reviews/l-nr.md"
echo "lead = session" > "${L}/.claude/swarm/config"
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
check "lead off: needs you lists a kept story with its exits" \
  has "! review kept story k-kept: swarm.sh review k-kept https://github.com/o/l/pull/6 or swarm.sh close k-kept --drop" "$(joined "$(lbox "needs you" "${out}")")"
check "lead off: an escalated lead story with no **You:** step is not listed" lacks "decide escalated story esc" "${out}"
check "lead off: needs you lists the no-agent story with its exit" \
  has "! no agent on story l-na: swarm.sh hold l-na <reason>" "$(joined "$(lbox "needs you" "${out}")")"

# An agreed HLD with no planned: is the lead's to plan (next's plan-hld), no row the user must act on;
# a draft one beside it keeps its row.
H="${ROOT}/hproj"; mkdir -p "${H}/docs/hld" "${H}/docs/stories"; touch "${H}/docs/stories/README.md"; git -C "${H}" init -q
printf -- '---\nstatus: agreed\n---\n\n# ha\n\n## Epics\n' > "${H}/docs/hld/ha.md"
printf -- '---\nstatus: draft\n---\n\n# hd\n' > "${H}/docs/hld/hd.md"
out="$(fresh; cd "${H}" || exit 1; env -u HERDR_ENV COLUMNS=160 PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "an agreed unplanned HLD: the header's next names plan-hld ha" has "next plan-hld ha" "${out}"
check "an agreed unplanned HLD has no needs-you row" lacks "HLD ha" "$(lbox "needs you" "${out}")"
check "a draft HLD beside it keeps its agree draft HLD row" has "! agree draft HLD hd: /hld hd" "$(joined "$(lbox "needs you" "${out}")")"
# An open plan PR (its worktree), then an open finish PR, is a row status and dash both show, as next's gate does.
hrun() { # <swarm.sh args...> — in H, with herdr and gh failing
  fresh; (cd "${H}" || exit 1; env -u HERDR_ENV COLUMNS=160 PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" "$@" 2>&1 || true)
}
mkdir -p "${ROOT}/hproj-wt/_board-plan-ha"
check "an open plan PR is under status's Waiting on you" has "  plan PR awaiting merge: ha" "$(sed -n '/^Waiting on you$/,/^$/p' <<< "$(hrun status)")"
check "an open plan PR is a dash needs-you row" has "! plan PR awaiting merge: ha" "$(joined "$(lbox "needs you" "$(hrun dash)")")"
printf -- '---\nstatus: agreed\nplanned: 2026-10-24\n---\n\n# ha\n' > "${H}/docs/hld/ha.md"
mv "${ROOT}/hproj-wt/_board-plan-ha" "${ROOT}/hproj-wt/_board-finish-ha"
check "an open finish PR is under status's Waiting on you" has "  finish PR awaiting merge: ha" "$(sed -n '/^Waiting on you$/,/^$/p' <<< "$(hrun status)")"
check "an open finish PR is a dash needs-you row" has "! finish PR awaiting merge: ha" "$(joined "$(lbox "needs you" "$(hrun dash)")")"
# lead = session and merge = human: a finish PR is the user's, grant or not; a plan PR the lead's only
# when its HLD grants merge. merge = agent keeps both in the lead's queue.
hrows() { # <config> <row> — "<needs you>|<lead's queue>": where dash in H draws the row, yes or no each
  local out
  printf '%s\n' "$1" > "${H}/.claude/swarm/config"; out="$(hrun dash)"
  printf '%s|%s' "$(has "$2" "$(joined "$(lbox "needs you" "${out}")")" && echo yes || echo no)" \
    "$(has "$2" "$(joined "$(lbox "lead's queue" "${out}")")" && echo yes || echo no)"
}
mkdir -p "${H}/.claude/swarm"
printf -- '---\nstatus: agreed\nplanned: 2026-10-24\ngrants: [merge]\n---\n\n# ha\n' > "${H}/docs/hld/ha.md"
check "lead = session, merge = human: a finish PR under a granting HLD is under needs you" \
  test "$(hrows "lead = session" "! finish PR awaiting merge: ha")" = "yes|no"
check "lead = session, merge = agent: a finish PR is in the lead's queue" \
  test "$(hrows "$(printf 'lead = session\nmerge = agent')" "! finish PR awaiting merge: ha")" = "no|yes"
mv "${ROOT}/hproj-wt/_board-finish-ha" "${ROOT}/hproj-wt/_board-plan-ha"
printf -- '---\nstatus: agreed\ngrants: [merge]\n---\n\n# ha\n\n## Epics\n' > "${H}/docs/hld/ha.md"
check "lead = session, merge = human: a plan PR under a granting HLD is in the lead's queue" \
  test "$(hrows "lead = session" "! plan PR awaiting merge: ha")" = "no|yes"
printf -- '---\nstatus: agreed\ngrants: [epics]\n---\n\n# ha\n\n## Epics\n' > "${H}/docs/hld/ha.md"
check "lead = session, merge = human: a plan PR with no merge grant is under needs you" \
  test "$(hrows "lead = session" "! plan PR awaiting merge: ha")" = "yes|no"
check "lead = session, merge = agent: a plan PR with no merge grant is in the lead's queue" \
  test "$(hrows "$(printf 'lead = session\nmerge = agent')" "! plan PR awaiting merge: ha")" = "no|yes"


[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
