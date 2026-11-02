#!/usr/bin/env bash
# start_cold_shell_test.sh — an agent's start when its pane's shell is slow to take the agent's
# environment, or never does (#688). herdr is a stub on PATH that logs every call's argv in herdr.log.
# `pane run` types nothing. `pane wait-output` stands for the shell printing clean_env's marker: it
# fails while the number in miss is above 0 (counting it down), and, with the file cold present,
# whenever its --timeout is under 45000 (a 45 s cold shell). With a number N in closefail, the next N
# pane closes fail; with N in openok, only the next N pane opens succeed, and the rest fail as
# pane_not_found. A closed pane's agent is no longer listed. The cases: a cold shell under the
# 60 s wait; a first pane that misses the marker, retried once in a fresh pane; two that miss; a
# miss in a pane that cannot be closed; a fresh pane herdr will not open; a story start, which keeps build_story's own retry only; and
# flow's start_failures over the start-retry lines those cases logged.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No .claude.json here, so require_trusted lets the agents start.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)
p="${ROOT}/proj"; b="${p}/docs"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }

cat > "${STUB_BIN}/herdr" <<EOF
#!/bin/sh
H="${ROOT}"
EOF
cat >> "${STUB_BIN}/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/n"; }
take() { k=$(cat "$H/$1" 2>/dev/null || echo 0); [ "$k" -gt 0 ] || return 1; echo $((k - 1)) > "$H/$1"; }
opens() { [ ! -e "$H/openok" ] || take openok || { echo '{"error":{"code":"pane_not_found","message":"pane w:0 not found"}}' >&2; exit 1; }; }
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;   # start_agent's require_herdr_version
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create")       opens; next; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane split")       opens; next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane run")         ;;
  "pane wait-output") if take miss; then echo '{"error":{"code":"timeout","message":"timeout waiting for output"}}' >&2; exit 1; fi
                      if [ -e "$H/cold" ] && [ "$7" -lt 45000 ]; then echo '{"error":{"code":"timeout","message":"cold shell"}}' >&2; exit 1; fi ;;
  "agent start")      echo "$3 $7" >> "$H/agents" ;;
  "agent prompt")     echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "pane close")       if take closefail; then exit 1; fi; echo "$3" >> "$H/closed" ;;
  "tab list")         echo '{"result":{"tabs":[]}}' ;;
  "pane list")        echo '{"result":{"panes":[]}}' ;;
  "agent list")       awk -v closed=" $(cat "$H/closed" 2>/dev/null | tr '\n' ' ') " 'BEGIN { printf "{\"result\":{\"agents\":[" }
                           index(closed, " " $2 " ") { next }
                           { printf "%s{\"name\":\"%s\",\"agent_status\":\"working\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"agents":[]}}' ;;
esac
EOF
printf '#!/bin/sh\necho "[]"\n' > "${STUB_BIN}/gh"
chmod +x "${STUB_BIN}/herdr" "${STUB_BIN}/gh"
mkdir -p "${ROOT}/home"

run() {
  (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${STUB_BIN}:${PATH}" HOME="${ROOT}/home" \
    SWARM_SLEEP_SCALE=0.01 bash "${SWARM}" "$@" 2>&1)
}
item() { # <path under the board> <front-matter line>...
  local path="${b}/$1" title; shift; title="$(basename "${path}" .md)"; mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}
"${GIT[@]}" init -q --bare "${ROOT}/svc.git"
"${GIT[@]}" clone -q "${ROOT}/svc.git" "${ROOT}/svc" 2>/dev/null
"${GIT[@]}" -C "${ROOT}/svc" commit -q --allow-empty -m init && "${GIT[@]}" -C "${ROOT}/svc" push -q origin main
mkdir -p "${p}/.claude/swarm"; : > "${p}/.claude/swarm/config"
"${GIT[@]}" -C "${p}" init -q
echo "brief" > "${ROOT}/brief.md"

# start <name> <knob> <n>... — swarm.sh agent <name> as a conductor in a tab of its own, with each stub
# <knob> set to its <n>; a knob cold makes the file. Sets rc, out (its output), opened (the panes it
# opened, one a line) and log (its herdr calls).
start() {
  local name="$1" n; shift
  rm -f "${ROOT}/miss" "${ROOT}/cold" "${ROOT}/closefail" "${ROOT}/openok"
  while [[ $# -gt 1 ]]; do echo "$2" > "${ROOT}/$1"; shift 2; done
  n="$(wc -l < "${ROOT}/herdr.log" 2>/dev/null || echo 0)"
  rc=0; out="$(run agent "tab-${name}" "${name}" "${p}" conduct "${ROOT}/brief.md")" || rc=$?
  log="$(tail -n +"$((n + 1))" "${ROOT}/herdr.log")"
  opened="$(awk '/^(tab create|pane split) /' <<< "${log}" | wc -l | tr -d ' ')"
}
# started_in <name> — the pane the last start's herdr agent start of <name> named; closes — the panes it
# closed, in pane number order; retries <name> — the outcome of each start-retry line of <name> in events.tsv.
started_in() { awk -v n="$1" '$1 == "agent" && $2 == "start" && $3 == n { for (i = 4; i < NF; i++) if ($i == "--pane") print $(i + 1) }' <<< "${log}"; }
closes() { awk '$1 == "pane" && $2 == "close" { print $3 }' <<< "${log}" | sort -u -t: -k2,2n | tr '\n' ' '; }
retries() { awk -F'\t' -v n="$1" '$2 == "start-retry" && $3 == n { print $5 }' "${p}/.swarm/events.tsv" 2>/dev/null | no_version; }
: > "${ROOT}/herdr.log"

MISS='{"error":{"code":"timeout","message":"timeout waiting for output"}}'   # the stub's reply to a missed marker
NOENV="the pane's shell did not take the agent's environment"

# --- A cold shell that takes 45 s: inside the 60 s wait, so the first pane's start finishes.
start cold-one cold 1
check "a 45 s cold shell: the start finishes in its first pane, with no retry" "0|1|w:$(cat "${ROOT}/n")|" \
  "${rc}|${opened}|$(started_in cold-one)|$(retries cold-one)"

# --- A first pane that never shows the marker: closed, and the agent starts in a fresh pane.
start miss-one miss 1
first="w:$(( $(cat "${ROOT}/n") - 1 ))"   # the stub numbers panes w:1, w:2, ...: the start's first of two
check "a first pane with no marker: rc 0, two panes, the agent in the second, the first closed" \
  "0|2|w:$(cat "${ROOT}/n")|${first} " "${rc}|${opened}|$(started_in miss-one)|$(closes)"
check "and stderr says it tries once more in a fresh pane, naming the first pane" "yes" \
  "$(has "swarm: miss-one: ${NOENV}: ${MISS}; pane ${first} is closed, and the start is tried once more in a fresh pane" "${out}")"
check "it logs one start-retry event, ok: the fresh pane saved the start" \
  "ok (miss-one: ${NOENV}: ${MISS})" \
  "$(retries miss-one)"

# --- No marker in either pane: the start stops after exactly two panes, both closed, and no agent starts.
start miss-all miss 99
check "no marker ever: rc 1, two panes, both closed, no herdr agent start" \
  "1|2|w:$(( $(cat "${ROOT}/n") - 1 )) w:$(cat "${ROOT}/n") |0" \
  "${rc}|${opened}|$(closes)|$(grep -c '^agent start ' <<< "${log}" || true)"
check "and its die names the second pane's failure, after the retry line" "yes|yes" \
  "$(has "tried once more in a fresh pane" "${out}")|$(has "swarm: miss-all: ${NOENV}" "$(tail -1 <<< "${out}")")"
check "it logs one start-retry event, with the second failure: not saved" \
  "miss-all: ${NOENV}: ${MISS}" \
  "$(retries miss-all)"

# --- A miss in a pane that cannot be closed: it may still be open, so no second pane.
start miss-open miss 99 closefail 1
check "a miss in a pane that cannot be closed: rc 1, one pane, no herdr agent start, no retry event" \
  "1|1|0|" "${rc}|${opened}|$(grep -c '^agent start ' <<< "${log}" || true)|$(retries miss-open)"
check "and it says to close the pane by hand, with no retry line" "yes|no" \
  "$(has "(and pane w:$(cat "${ROOT}/n") could not be closed: close it by hand)" "${out}")|$(grep -q 'tried once more' <<< "${out}" && echo yes || echo no)"

# --- A first pane with no marker, and a fresh pane herdr will not open: the retried start is logged, not saved.
start miss-noopen miss 99 openok 1
check "a fresh pane herdr will not open: rc 1, two opens tried, one pane opened and closed, no herdr agent start" \
  "1|2|w:$(cat "${ROOT}/n") |0" "${rc}|${opened}|$(closes)|$(grep -c '^agent start ' <<< "${log}" || true)"
check "and it dies naming the fresh pane herdr would not open" "yes" \
  "$(has "swarm: miss-noopen: the start was tried once more, but herdr could not open a fresh pane (see above)" "$(tail -1 <<< "${out}")")"
check "it logs one start-retry event, not saved" "miss-noopen: ${NOENV}: ${MISS}; herdr could not open a fresh pane" "$(retries miss-noopen)"

# --- A story start keeps build_story's own retry (3 starts) and gets none inside start_agent: 3 panes, not 6.
item stories/s-story.md "status: ready" "kind: code" "repo: svc"
rm -f "${ROOT}/cold" "${ROOT}/closefail" "${ROOT}/openok"; echo 99 > "${ROOT}/miss"
n="$(wc -l < "${ROOT}/herdr.log")"; k="$(cat "${ROOT}/n")"   # the story's panes are w:k+1 to w:k+3
rc=0; out="$(run story s-story)" || rc=$?
log="$(tail -n +"$((n + 1))" "${ROOT}/herdr.log")"
check "a story start with no marker ever: rc 1, three panes that each reached the marker wait and were closed, no herdr agent start, no retry event" \
  "1|3|w:$((k + 1)) w:$((k + 2)) w:$((k + 3)) |0|" \
  "${rc}|$(grep -c '^pane wait-output ' <<< "${log}")|$(closes)|$(grep -c '^agent start ' <<< "${log}" || true)|$(retries s-story)"
check "and no line of it says it tries in a fresh pane" "no" "$(grep -q 'tried once more' <<< "${out}" && echo yes || echo no)"

# --- flow's start_failures counts the start-retry lines: three retried today, one saved.
sf() { (cd "${p}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=start_failures bash "${SWARM}" flow "$@" | grep -v '^## start_failures$'); }
check "flow start_failures: today's row counts the three retried starts and the one the fresh pane saved" \
  "$(printf '%s\n' 'no failed review-agent start in the window' '' $'day\tretried\tsaved' "$(date -u +%F)"$'\t3\t1')" \
  "$(sf --since "$(date -u +%F)")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
