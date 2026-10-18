#!/usr/bin/env bash
# env_allowlist_test.sh — every agent starts with an allowlisted environment (start_agent's
# clean_env), a story's env: adds names for its builder and its conductor, and no value goes through
# argv. herdr is a stub on PATH. Its `pane run` runs the typed line under the herdr server's own
# environment (which holds FAKE_SECRET=server-secret) and types `env > <file>` into whatever shell the
# line leaves, so each pane's environment is recorded; SWARM_AGENT_SHELL=/bin/sh stands in for zsh to
# read it. `agent start` gives the agent its pane's environment. The stub keeps every call's argv in
# herdr.log, each pane's screen (the typed line and its output), the launch files' modes when the line
# is typed, and how many are left once it has run.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
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
H="${ROOT}"; P="${p}"
EOF
cat >> "${STUB_BIN}/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create")       next; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane split")       next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane run")         ls -l "$P/.swarm/launch" | awk 'NR > 1 { print substr($1, 1, 10) }' >> "$H/modes"
                      printf '%s\n' "$4" >> "$H/screen-$3"
                      printf 'env > "%s"\n' "$H/env-$3" | env -i PATH=/usr/bin:/bin HOME="$H/server-home" TERM=dumb \
                        FAKE_SECRET=server-secret HERDR_ENV=1 HERDR_PANE_ID="$3" HERDR_WORKSPACE_ID=w HERDR_SOCKET_PATH="$H/sock" \
                        /bin/sh -c "$4" >> "$H/screen-$3" 2>&1
                      ls "$P/.swarm/launch" | wc -l | tr -d ' ' >> "$H/left" ;;
  "pane wait-output") grep -qF -- "$5" "$H/screen-$3" ;;
  "agent start")      cp "$H/env-$7" "$H/agent-env-$3"; echo "$3 $7" >> "$H/agents" ;;
  "agent prompt")     echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent list")       awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                           { printf "%s{\"name\":\"%s\",\"agent_status\":\"working\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"agents":[]}}' ;;
esac
EOF
printf '#!/bin/sh\necho "[]"\n' > "${STUB_BIN}/gh"
chmod +x "${STUB_BIN}/herdr" "${STUB_BIN}/gh"

# The lead: its own FAKE_SECRET (the value a story's env: passes on), in the project.
LEAD_PATH="${STUB_BIN}:${PATH}"
run() {
  (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${LEAD_PATH}" TERM=xterm-test \
    FAKE_SECRET=lead-secret SWARM_AGENT_SHELL=/bin/sh bash "${SWARM}" "$@" 2>&1)
}
# as_agent <agent> <args>... — swarm.sh run as <agent> would run it: in its recorded environment
# alone, plus the test's stand-in shell, from the project.
as_agent() {
  local a=() l; while IFS= read -r l; do a+=("${l}"); done < "${ROOT}/agent-env-$1"; shift
  (cd "${p}" && env -i "${a[@]}" SWARM_AGENT_SHELL=/bin/sh bash "${SWARM}" "$@" 2>&1)
}
var() { sed -n "s/^$2=//p" "${ROOT}/agent-env-$1"; }   # <agent> <name> — its value in the agent's environment
pane_of() { awk -v n="$1" '$1 == n { print $2 }' "${ROOT}/agents"; }
launch_left() { find "${p}/.swarm/launch" -type f | wc -l | tr -d ' '; }
calls() { wc -l < "${ROOT}/herdr.log" | tr -d ' '; }   # how many herdr calls so far
item() { # <path under the board> <front-matter line>...
  local path="${b}/$1" title; shift; title="$(basename "${path}" .md)"; mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

"${GIT[@]}" init -q --bare "${ROOT}/svc.git"
"${GIT[@]}" clone -q "${ROOT}/svc.git" "${ROOT}/svc" 2>/dev/null
"${GIT[@]}" -C "${ROOT}/svc" commit -q --allow-empty -m init && "${GIT[@]}" -C "${ROOT}/svc" push -q origin main
mkdir -p "${p}/.claude/swarm"; : > "${p}/.claude/swarm/config"
item epics/plain.md "status: active"
item epics/e.md "status: active"
item stories/p1.md "status: ready" "kind: code" "epic: plain" "repo: svc"
item stories/s-env.md "status: ready" "kind: code" "epic: e" "repo: svc" "env: [FAKE_SECRET]"
item stories/s-plain.md "status: ready" "kind: code" "epic: e" "repo: svc"

# --- An agent whose stories name nothing: no FAKE_SECRET, from the lead or the server.
run conduct plain >/dev/null
check "a conductor whose stories name no env: has no FAKE_SECRET" "" "$(var conduct-plain FAKE_SECRET)"
check "PATH, HOME and TERM reach it with swarm.sh's values" "${LEAD_PATH}|${HOME}|xterm-test" \
  "$(var conduct-plain PATH)|$(var conduct-plain HOME)|$(var conduct-plain TERM)"
check "the swarm.sh variables reach it: HERDR_ENV, and herdr's own for its pane" "1|$(pane_of conduct-plain)|w|${ROOT}/sock" \
  "$(var conduct-plain HERDR_ENV)|$(var conduct-plain HERDR_PANE_ID)|$(var conduct-plain HERDR_WORKSPACE_ID)|$(var conduct-plain HERDR_SOCKET_PATH)"

# --- A story's env: reaches its conductor, then the builder that conductor starts, with the lead's value.
run conduct e >/dev/null
check "the conductor of an epic whose story names FAKE_SECRET receives the lead's value" "lead-secret" "$(var conduct-e FAKE_SECRET)"
as_agent conduct-e story s-env >/dev/null
check "a builder of a story with env: [FAKE_SECRET], started by that conductor, receives it" "lead-secret" "$(var s-env FAKE_SECRET)"
as_agent conduct-e story s-plain >/dev/null
check "a builder of its epic's story with no env: does not" "" "$(var s-plain FAKE_SECRET)"
check "and the builders get HERDR_ENV and their own pane" "1|$(pane_of s-env)" "$(var s-env HERDR_ENV)|$(var s-env HERDR_PANE_ID)"

# --- No value in argv, on any screen, or left on disk.
check "neither FAKE_SECRET value appears in any recorded herdr argv" "0" "$(grep -c -e lead-secret -e server-secret "${ROOT}/herdr.log" || true)"
check "nor on any pane's screen" "0" "$(cat "${ROOT}"/screen-* | grep -c -e lead-secret -e server-secret || true)"
# shellcheck disable=SC2016 # the typed line's own $NAME, which the pane's shell expands
check "each pane's screen shows the typed line, with no value in it" "yes" "$(has 'exec /usr/bin/env -i HERDR_ENV=1 HERDR_PANE_ID="$HERDR_PANE_ID"' "$(cat "${ROOT}/screen-$(pane_of s-env)")")"
check "each launch file was 0600 when the line was typed" "-rw-------" "$(sort -u "${ROOT}/modes")"
check "the wrapper deleted its file itself, every launch" "0" "$(sort -u "${ROOT}/left")"
check "and no launch file is left" "0" "$(launch_left)"

# --- A bad name is refused, by the story and by its conductor, before anything starts.
item stories/bad.md "status: ready" "kind: code" "repo: svc" "env: [bad-name]"
n="$(calls)"
check "story refuses env: [bad-name], and starts nothing" "1|yes|no|${n}" \
  "$(set +e; o="$(run story bad)"; echo "$?|$(has "env: 'bad-name' is not a variable name" "${o}")")|$([[ -e "${ROOT}/svc-wt/bad" ]] && echo yes || echo no)|$(calls)"
check "conduct --backlog refuses it too" "1|yes" \
  "$(set +e; o="$(run conduct --backlog)"; echo "$?|$(has "env: 'bad-name' is not a variable name" "${o}")")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
