#!/usr/bin/env bash
# env_allowlist_test.sh — every agent starts with an allowlisted environment (start_agent's
# clean_env), a story's env: adds names for its builder and its conductor, and no value goes through
# argv. herdr is a stub on PATH. Its `pane run` runs the typed line under the herdr server's own
# environment (which holds FAKE_SECRET=server-secret) and types `env > <file>` into whatever shell the
# line leaves, so each pane's environment is recorded; SWARM_AGENT_SHELL=/bin/sh stands in for zsh to
# read it. `agent start` gives the agent its pane's environment. The stub keeps every call's argv in
# herdr.log, each pane's screen (the typed line and its output), the launch files' modes when the line
# is typed, and whether the file the line names is left once it has run. With a number N in runfail,
# the next N pane runs fail before typing anything; in runtypedfail, they fail after it.
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
  "--version ") echo "herdr 0.9.5" ;;   # start_agent's require_herdr_version
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create")       next; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane split")       next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane run")         k=$(cat "$H/runfail" 2>/dev/null || echo 0)
                      if [ "$k" -gt 0 ]; then echo $((k - 1)) > "$H/runfail"; echo '{"error":{"code":"pane_not_ready"}}' >&2; exit 1; fi
                      ls -l "$P/.swarm/launch" | awk 'NR > 1 { print substr($1, 1, 10) }' >> "$H/modes"
                      printf '%s\n' "$4" >> "$H/screen-$3"
                      printf 'env > "%s"\n' "$H/env-$3" | env -i PATH=/usr/bin:/bin HOME="$H/server-home" TERM=dumb \
                        FAKE_SECRET=server-secret HERDR_ENV=1 HERDR_PANE_ID="$3" HERDR_WORKSPACE_ID=w HERDR_SOCKET_PATH="$H/sock" \
                        /bin/sh -c "$4" >> "$H/screen-$3" 2>&1
                      if [ -e "${4##* }" ]; then echo 1; else echo 0; fi >> "$H/left"
                      k=$(cat "$H/runtypedfail" 2>/dev/null || echo 0)
                      if [ "$k" -gt 0 ]; then echo $((k - 1)) > "$H/runtypedfail"; echo '{"error":{"code":"timeout"}}' >&2; exit 1; fi ;;
  "pane wait-output") grep -qF -- "$5" "$H/screen-$3" ;;
  "agent start")      cp "$H/env-$7" "$H/agent-env-$3"; echo "$3 $7" >> "$H/agents" ;;
  "agent prompt")     echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "tab list")         echo '{"result":{"tabs":[]}}' ;;
  "pane list")        echo '{"result":{"panes":[]}}' ;;
  "agent list")       awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                           { printf "%s{\"name\":\"%s\",\"agent_status\":\"working\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"agents":[]}}' ;;
esac
EOF
printf '#!/bin/sh\necho "[]"\n' > "${STUB_BIN}/gh"
chmod +x "${STUB_BIN}/herdr" "${STUB_BIN}/gh"

# The lead: its own FAKE_SECRET (the value a story's env: passes on), LEAD_SECRET (a lead story's) and
# REVIEW_SECRET (a story in review's), config paths, bash as its SHELL, and a HOME whose zsh and bash
# startup files export ZSH_LEAK and BASH_LEAK, proxy, CA, git ssh and gpg settings, and a swarm.sh
# setting (SWARM_MERGE_CI_SECONDS), in the project. A stray AGENT_ENV_NAMES names nothing.
NET=(HTTPS_PROXY=http://proxy:1 HTTP_PROXY=http://proxy:2 NO_PROXY=a.example https_proxy=http://proxy:3 http_proxy=http://proxy:4
  no_proxy=b.example SSL_CERT_FILE="${ROOT}/ca.pem" NODE_EXTRA_CA_CERTS="${ROOT}/extra.pem" GIT_SSH_COMMAND="ssh -F /dev/null"
  GNUPGHOME="${ROOT}/gnupg")
# The Linux session bus and XDG directories, and a Bedrock provider setup with a secret beside it.
DESK=(DBUS_SESSION_BUS_ADDRESS="unix:path=${ROOT}/bus" XDG_RUNTIME_DIR="${ROOT}/run" XDG_DATA_HOME="${ROOT}/data"
  XDG_CACHE_HOME="${ROOT}/cache" XDG_STATE_HOME="${ROOT}/state")
PROVIDER=(CLAUDE_CODE_USE_BEDROCK=1 CLAUDE_CODE_USE_VERTEX=0 CLAUDE_CODE_USE_FOUNDRY=0 ANTHROPIC_MODEL=m1 ANTHROPIC_SMALL_FAST_MODEL=m2
  AWS_REGION=eu-west-2 AWS_PROFILE=dev CLOUD_ML_REGION=europe-west4 ANTHROPIC_VERTEX_PROJECT_ID=proj-1)
LEAD_PATH="${STUB_BIN}:${PATH}" TEST_HOME="${ROOT}/home"
mkdir -p "${TEST_HOME}"; : > "${ROOT}/gitconfig"
for f in zshenv zprofile zshrc; do echo "export ZSH_LEAK=${f}" > "${TEST_HOME}/.${f}"; done
for f in bashrc bash_profile; do echo "export BASH_LEAK=${f}" > "${TEST_HOME}/.${f}"; done
run() {
  (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${LEAD_PATH}" TERM=xterm-test HOME="${TEST_HOME}" \
    XDG_CONFIG_HOME="${ROOT}/xdg" GH_CONFIG_DIR="${ROOT}/gh" GIT_CONFIG_GLOBAL="${ROOT}/gitconfig" \
    "${NET[@]}" "${DESK[@]}" "${PROVIDER[@]}" AWS_SECRET_ACCESS_KEY=aws-secret GPG_TTY=/dev/lead-tty SWARM_MERGE_CI_SECONDS=7 SHELL=/bin/bash FAKE_SECRET=lead-secret LEAD_SECRET=lead-only REVIEW_SECRET=review-only AGENT_ENV_NAMES=FAKE_SECRET PROVIDER_KEY=provider-key \
    SWARM_AGENT_SHELL=/bin/sh bash "${SWARM}" "$@" 2>&1)
}
# agent_env <agent> — its recorded environment, one NAME=value per line, into the array a.
agent_env() { local l; a=(); while IFS= read -r l; do a+=("${l}"); done < "${ROOT}/agent-env-$1"; }
# as_agent <agent> <args>... — swarm.sh run as <agent> would run it: in its recorded environment
# alone, plus the test's stand-in shell, from the project.
as_agent() {
  local a; agent_env "$1"; shift
  (cd "${p}" && env -i "${a[@]}" SWARM_AGENT_SHELL=/bin/sh bash "${SWARM}" "$@" 2>&1)
}
var() { sed -n "s/^$2=//p" "${ROOT}/agent-env-$1"; }   # <agent> <name> — its value in the agent's environment
pane_of() { awk -v n="$1" '$1 == n { print $2 }' "${ROOT}/agents"; }
launch_left() { find "${p}/.swarm/launch" -type f | wc -l | tr -d ' '; }
# started — the panes opened, lines typed and agents started so far.
started() { grep -cE '^(tab create|pane split|pane run|agent start) ' "${ROOT}/herdr.log" || true; }
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
# Neither a lead story's names nor a done story's reach the conductor, and a done one's bad name stops nothing.
item stories/l-e.md "status: ready" "kind: lead" "epic: e" "env: [LEAD_SECRET]"
item stories/d-e.md "status: done" "kind: code" "epic: e" "env: [bad-name]"
# A story in review may go back to ready; s-restart's builder is started again through swarm.sh agent.
item stories/r-e.md "status: review" "kind: code" "epic: e" "repo: svc" "env: [REVIEW_SECRET]"
item stories/s-restart.md "status: ready" "kind: code" "epic: e" "repo: svc" "env: [FAKE_SECRET]"

# --- An agent whose stories name nothing: no FAKE_SECRET, from the lead or the server.
run conduct plain >/dev/null
check "a conductor whose stories name no env: has no FAKE_SECRET" "" "$(var conduct-plain FAKE_SECRET)"
check "PATH (gh-shim first), HOME and TERM reach it with swarm.sh's values" "${SWARM%/*}/gh-shim:${LEAD_PATH}|${TEST_HOME}|xterm-test" \
  "$(var conduct-plain PATH)|$(var conduct-plain HOME)|$(var conduct-plain TERM)"
check "gh-shim logs its gh calls under its own name, not as the command that started it" "conduct-plain|${p}/.swarm/gh-calls.tsv|" \
  "$(var conduct-plain SWARM_GH_CALLER)|$(var conduct-plain SWARM_GH_LOG)|$(var conduct-plain SWARM_GH_VIA)"
check "the swarm.sh variables reach it: HERDR_ENV, and herdr's own for its pane" "1|$(pane_of conduct-plain)|w|${ROOT}/sock" \
  "$(var conduct-plain HERDR_ENV)|$(var conduct-plain HERDR_PANE_ID)|$(var conduct-plain HERDR_WORKSPACE_ID)|$(var conduct-plain HERDR_SOCKET_PATH)"
check "XDG_CONFIG_HOME, GH_CONFIG_DIR and GIT_CONFIG_GLOBAL reach it, so gh and git find their config" \
  "${ROOT}/xdg|${ROOT}/gh|${ROOT}/gitconfig" \
  "$(var conduct-plain XDG_CONFIG_HOME)|$(var conduct-plain GH_CONFIG_DIR)|$(var conduct-plain GIT_CONFIG_GLOBAL)"
check "the proxy, CA, git ssh and gpg settings reach it" "$(printf '%s|' "${NET[@]}")" \
  "$(for v in "${NET[@]}"; do printf '%s=%s|' "${v%%=*}" "$(var conduct-plain "${v%%=*}")"; done)"
check "swarm.sh's own SWARM_* settings and CLAUDE_PROJECTS_DIR reach it" "7|${ROOT}/projects" \
  "$(var conduct-plain SWARM_MERGE_CI_SECONDS)|$(var conduct-plain CLAUDE_PROJECTS_DIR)"
# zdot <agent> — its ZDOTDIR's mode and the files in it.
# shellcheck disable=SC2012 # one directory, a path swarm.sh made; ls -ld's mode string reads the same on macOS and Linux
zdot() { local d; d="$(var "$1" ZDOTDIR)"; printf '%s|%s' "$(ls -ld "${d}" | cut -c1-10)" "$(find "${d}" -mindepth 1 2>&1 | sed 's#.*/##' | sort | tr '\n' ' ')"; }
ZDOT_FILES="drwx------|.zprofile .zshenv "
check "its ZDOTDIR is its own 0700 directory under .swarm, holding only swarm.sh's .zshenv and .zprofile" \
  "${p}/.swarm/zdotdir/conduct-plain|${ZDOT_FILES}" "$(var conduct-plain ZDOTDIR)|$(zdot conduct-plain)"
# shellcheck disable=SC2016 # the sourcing bash expands them
check "and they put back the PATH a login shell was given, after a path_helper-style reorder" "/extra:${LEAD_PATH}" \
  "$(env -i PATH="/extra:${LEAD_PATH}" bash -c '. "$1/.zshenv"; PATH="/usr/bin:/bin:${PATH}"; . "$1/.zprofile"; printf %s "${PATH}"' \
    _ "$(var conduct-plain ZDOTDIR)")"
check "the session bus and XDG directories reach it, so gh and git reach the Secret Service on Linux" "$(printf '%s|' "${DESK[@]}")" \
  "$(for v in "${DESK[@]}"; do printf '%s=%s|' "${v%%=*}" "$(var conduct-plain "${v%%=*}")"; done)"
check "GPG_TTY is the pane's own terminal (none here), never the lead's" "" "$(var conduct-plain GPG_TTY)"
check "the provider and model selection reaches it, and the secret beside it does not" "$(printf '%s|' "${PROVIDER[@]}")|" \
  "$(for v in "${PROVIDER[@]}"; do printf '%s=%s|' "${v%%=*}" "$(var conduct-plain "${v%%=*}")"; done)|$(var conduct-plain AWS_SECRET_ACCESS_KEY)"
check "a herdr variable the pane lacks is left unset, not set empty" "0|0" \
  "$(grep -c '^HERDR_TAB_ID=' "${ROOT}/agent-env-conduct-plain")|$(grep -c '^HERDR_BIN_PATH=' "${ROOT}/agent-env-conduct-plain")"
if command -v zsh >/dev/null; then
  agent_env conduct-plain
  # shellcheck disable=SC2016 # the agent's zsh expands it
  check "a zsh -lc the agent starts sees no secret exported in HOME's .zshenv or .zprofile" "none" \
    "$(env -i "${a[@]}" zsh -lc 'echo ${ZSH_LEAK:-none}' 2>&1 </dev/null)"
  # shellcheck disable=SC2016 # the agent's zsh expands it
  check "and keeps swarm.sh's PATH, in its order, past /etc/zprofile" "${SWARM%/*}/gh-shim:${LEAD_PATH}" "$(env -i "${a[@]}" zsh -lc 'printf %s "${PATH}"' 2>&1 </dev/null)"
else
  echo "skip a zsh -lc the agent starts sees no secret exported in HOME's .zshenv or .zprofile (no zsh here)"
  echo "skip and keeps swarm.sh's PATH, in its order, past /etc/zprofile (no zsh here)"
fi
agent_env conduct-plain
check "its SHELL is the agent shell, not the lead's bash" "/bin/sh" "$(var conduct-plain SHELL)"
# shellcheck disable=SC2016 # the agent's shell expands them
check "a login shell the agent starts from SHELL sees no secret exported in HOME's .bashrc or .bash_profile" "none" \
  "$(env -i "${a[@]}" /bin/sh -c '"$SHELL" -lic "echo \${BASH_LEAK:-none}"' 2>/dev/null </dev/null | tail -1)"
check "a stray AGENT_ENV_NAMES in swarm.sh's environment adds nothing" "" "$(var conduct-plain FAKE_SECRET)"
# agent_env adds names only when the config sets it (the Foundry case below): without it, nothing extra leaks.
check "with no agent_env, PROVIDER_KEY from the lead does not reach it" "" "$(var conduct-plain PROVIDER_KEY)"

# --- A story's env: reaches its conductor, then the builder that conductor starts, with the lead's value.
check "conduct e starts, though a done story of its epic names a bad env:" "0" "$(set +e; run conduct e >/dev/null; echo $?)"
check "the conductor of an epic whose story names FAKE_SECRET receives the lead's value" "lead-secret" "$(var conduct-e FAKE_SECRET)"
check "but not the names of its epic's lead story" "" "$(var conduct-e LEAD_SECRET)"
check "and it does get a story in review's names, for a rebuild if its PR closes" "review-only" "$(var conduct-e REVIEW_SECRET)"
as_agent conduct-e story s-env >/dev/null
check "a builder of a story with env: [FAKE_SECRET], started by that conductor, receives it" "lead-secret" "$(var s-env FAKE_SECRET)"
as_agent conduct-e story s-plain >/dev/null
check "a builder of its epic's story with no env: does not" "" "$(var s-plain FAKE_SECRET)"
check "and the builders get HERDR_ENV and their own pane" "1|$(pane_of s-env)" "$(var s-env HERDR_ENV)|$(var s-env HERDR_PANE_ID)"
echo "brief" > "${ROOT}/brief.md"
as_agent conduct-e agent e s-restart "${p}" code "${ROOT}/brief.md" >/dev/null
check "a builder the conductor restarts with swarm.sh agent gets its story's env: too" "lead-secret" "$(var s-restart FAKE_SECRET)"
item stories/s-late.md "status: ready" "kind: code" "epic: e" "repo: svc" "env: [LATE_SECRET]"
check "a story added after its conductor started, with a new env: name, is refused with the restart to run" "1|yes" \
  "$(set +e; o="$(as_agent conduct-e story s-late)"; echo "$?|$(has "the lead restarts it with \`swarm.sh conduct e\` so it picks the name up" "${o}")")"

# --- A pane run that fails typed nothing: retried once, then the pane is closed and nothing is left.
echo 1 > "${ROOT}/runfail"
check "a pane run that fails once is retried, and the agent starts" "0|2" \
  "$(set +e; run agent t1 retry-one "${p}" conduct "${ROOT}/brief.md" >/dev/null; echo $?)|$(grep -c "^pane run $(pane_of retry-one) " "${ROOT}/herdr.log")"
echo 2 > "${ROOT}/runfail"
o="$(set +e; run agent t2 retry-two "${p}" conduct "${ROOT}/brief.md"; echo "rc=$?")"
check "one that fails twice stops the start, closes its pane, and leaves no launch file" "yes|yes|yes|no|0" \
  "$(has "rc=1" "${o}")|$(has "retry-two: the pane's shell did not take the agent's environment" "${o}")|$(has "pane close w:$(cat "${ROOT}/n")" "$(cat "${ROOT}/herdr.log")")|$([[ -e "${ROOT}/agent-env-retry-two" ]] && echo yes || echo no)|$(launch_left)"

# A board found only through SWARM_PROJECT (run from outside it): the agent keeps it, so its own
# swarm.sh calls find the same project.
(cd "${ROOT}" && env SWARM_PROJECT=proj HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${LEAD_PATH}" HOME="${TEST_HOME}" \
  SWARM_AGENT_SHELL=/bin/sh bash "${SWARM}" agent t3 by-project "${p}" conduct "${ROOT}/brief.md" >/dev/null 2>&1) || true
check "SWARM_PROJECT, when swarm.sh has it, reaches the agent, resolved from relative to absolute" "${p}" "$(var by-project SWARM_PROJECT)"

echo 1 > "${ROOT}/runtypedfail"
# A .zshenv an earlier agent left in typed-once's ZDOTDIR is gone once it starts.
mkdir -p "${p}/.swarm/zdotdir/typed-once"; echo "export PLANTED=1" > "${p}/.swarm/zdotdir/typed-once/.zshenv"
run agent t4 typed-once "${p}" conduct "${ROOT}/brief.md" >/dev/null
check "an agent's ZDOTDIR is made afresh at each launch: a .zshenv left there is gone" "${ZDOT_FILES}|0" \
  "$(zdot typed-once)|$(grep -c PLANTED "${p}/.swarm/zdotdir/typed-once/.zshenv")"
run close typed-once >/dev/null
check "closing the agent removes its ZDOTDIR" "no" "$([[ -e "${p}/.swarm/zdotdir/typed-once" ]] && echo yes || echo no)"
scr="${ROOT}/screen-$(pane_of typed-once)"
check "a pane run that typed its line and then failed is retried with its own marker, and the wait is for that one" "2|yes" \
  "$(grep '^swarm: agent environment ready' "${scr}" | sort -u | wc -l | tr -d ' ')|$(has "--match $(grep '^swarm: agent environment ready' "${scr}" | tail -1) --timeout" "$(cat "${ROOT}/herdr.log")")"

# --- No value in argv, on any screen, or left on disk.
check "neither FAKE_SECRET value appears in any recorded herdr argv" "0" "$(grep -c -e lead-secret -e server-secret "${ROOT}/herdr.log" || true)"
check "nor on any pane's screen" "0" "$(cat "${ROOT}"/screen-* | grep -c -e lead-secret -e server-secret || true)"
# shellcheck disable=SC2016 # the typed line's own $NAME, which the pane's shell expands
check "each pane's screen shows the typed line, with no value in it" "yes" "$(has 'exec /usr/bin/env -i HERDR_ENV=1 HERDR_PANE_ID="$HERDR_PANE_ID"' "$(cat "${ROOT}/screen-$(pane_of s-env)")")"
check "each launch file was 0600 when the line was typed" "-rw-------" "$(sort -u "${ROOT}/modes")"
check "the wrapper deleted its file itself, every launch" "0" "$(sort -u "${ROOT}/left")"
check "and no launch file is left" "0" "$(launch_left)"

# --- A story's env: that cannot be honoured is refused, by story and by conduct, before anything starts.
# refused <env front-matter line>... <the refusal's text> — story bad, then conduct --backlog (bad is the only one-off).
refused() {
  local why="${*: -1}" n o
  item stories/bad.md "status: ready" "kind: code" "repo: svc" "${@:1:$#-1}"
  n="$(started)"
  o="$(set +e; run story bad; echo "rc=$?")"
  printf '%s|%s|%s|' "$(has "rc=1" "${o}")" "$(has "${why}" "${o}")" "$([[ -e "${ROOT}/svc-wt/bad" ]] && echo worktree || echo none)"
  o="$(set +e; run conduct --backlog; echo "rc=$?")"
  printf '%s|%s|%s\n' "$(has "rc=1" "${o}")" "$(has "${why}" "${o}")" "$(( $(started) - n ))"
}
REFUSED="yes|yes|none|yes|yes|0"
check "env: [bad-name] is refused" "${REFUSED}" "$(refused "env: [bad-name]" "env: 'bad-name' is not a variable name")"
check "env: [HERDR_PANE_ID] is refused: it would replace the agent's own pane" "${REFUSED}" \
  "$(refused "env: [HERDR_PANE_ID]" "env: HERDR_PANE_ID is reserved")"
check "env: [PATH], an allowlisted name, is refused" "${REFUSED}" "$(refused "env: [PATH]" "env: PATH is reserved")"
check "env: [ZDOTDIR], which swarm.sh sets, is refused" "${REFUSED}" "$(refused "env: [ZDOTDIR]" "env: ZDOTDIR is reserved")"
# reserved_all <name>... — refused for each, one line per distinct answer.
reserved_all() { local n; for n in "$@"; do refused "env: [${n}]" "env: ${n} is reserved"; done | sort -u; }
check "names that load code or belong to the lead's session are refused" "${REFUSED}" \
  "$(reserved_all BASH_ENV ENV LD_PRELOAD DYLD_INSERT_LIBRARIES CLAUDECODE CLAUDE_CODE_OAUTH_TOKEN CLAUDE_PID)"
check "and so are swarm.sh's own settings and the passed-through proxy and CA names" "${REFUSED}" \
  "$(reserved_all SWARM_MERGE_CI_SECONDS HTTPS_PROXY SSL_CERT_FILE GIT_SSH_COMMAND CLAUDE_PROJECTS_DIR XDG_RUNTIME_DIR GPG_TTY AWS_PROFILE)"
check "a name swarm.sh's environment does not have is refused, naming it" "${REFUSED}" \
  "$(refused "env: [NOT_SET_HERE]" "env: NOT_SET_HERE is not set here, so its builder would start without it")"
check "a block-style env: list is refused, not read as no names" "${REFUSED}" \
  "$(refused "env:" "  - FAKE_SECRET" "env: is not a one-line list; write it as env: [NAME, ...]")"
check "and so is one whose env: line has a comment" "${REFUSED}" \
  "$(refused "env: # the token" "  - FAKE_SECRET" "env: is not a one-line list; write it as env: [NAME, ...]")"
check "and one with its items at column 0" "${REFUSED}" "$(refused "env:" "- FAKE_SECRET" "env: is not a one-line list; write it as env: [NAME, ...]")"
check "and a list over several lines" "${REFUSED}" "$(refused "env: [" "  FAKE_SECRET," "]" "env: is not a one-line list; write it as env: [NAME, ...]")"
check "and a bare name" "${REFUSED}" "$(refused "env: FAKE_SECRET" "env: is not a one-line list; write it as env: [NAME, ...]")"

# --- agent_env: names every agent of every role gets, set once in the config. Last, since it changes the config.
# Why agent_env exists: agents on Azure Foundry (or another provider) need its endpoint, key and
# model names (ANTHROPIC_FOUNDRY_RESOURCE, ANTHROPIC_FOUNDRY_API_KEY, ANTHROPIC_DEFAULT_*_MODEL) in
# every pane, not only builders'; without them every agent stops at its start. Boards outside
# swarm-dev and infrafactory set it, so finding it unset in those two configs is no reason to remove it.
# Each check below guards one part of that: a non-builder and a builder both get the names, a restart
# keeps them, a session without the provider still starts agents, and a bad name stops at config load.
rm -f "${b}/stories/bad.md"
printf 'agent_env = PROVIDER_KEY UNSET_HERE\n' > "${p}/.claude/swarm/config"
o="$(run agent t5 co-author "${p}" hld "${ROOT}/brief.md")"
check "a name in agent_env reaches an agent that builds nothing (role hld), with the lead's value" "provider-key" "$(var co-author PROVIDER_KEY)"
check "one the lead's session does not have is skipped with a warning, and the agent still starts" "yes|1" \
  "$(has "swarm: warning: agent_env: UNSET_HERE is not set here, so the agent starts without it" "${o}")|$(var co-author HERDR_ENV)"
run story p1 >/dev/null
check "and it reaches a builder whose story names no env:" "provider-key" "$(var p1 PROVIDER_KEY)"
session="$(awk -F'\t' '$3 == "co-author" { s = $7 } END { print s }' "${p}/.swarm/agents.tsv")"
check "its restart wrapper keeps it from the restored pane, and still drops a name nothing gave it" "PROVIDER_KEY=restored|" \
  "$(env -i PATH=/usr/bin:/bin PROVIDER_KEY=restored FAKE_SECRET=restored python3 -I "${CLAUDE_CONFIG_DIR}/swarm-dev/resume/${session}.py" env | grep -E '^(PROVIDER_KEY|FAKE_SECRET)=' | paste -sd'|' -)|"
# config_refused <agent_env value> <the refusal's text> — the config stops swarm.sh, naming its line, before any pane opens.
config_refused() {
  local n o
  printf 'agent_env = %s\n' "$1" > "${p}/.claude/swarm/config"
  n="$(started)"
  o="$(set +e; run agent t6 refused "${p}" hld "${ROOT}/brief.md"; echo "rc=$?")"
  printf '%s|%s|%s\n' "$(has "rc=1" "${o}")" "$(has ".claude/swarm/config:1: agent_env: $2" "${o}")" "$(( $(started) - n ))"
}
check "a malformed name in agent_env is refused at config load" "yes|yes|0" "$(config_refused "PROVIDER_KEY bad-name" "'bad-name' is not a variable name")"
check "so is a reserved one: PATH, which every agent gets already" "yes|yes|0" "$(config_refused "PATH" "PATH is reserved")"
check "and HERDR_PANE_ID, which would replace the agent's own pane" "yes|yes|0" "$(config_refused "PROVIDER_KEY HERDR_PANE_ID" "HERDR_PANE_ID is reserved")"
: > "${p}/.claude/swarm/config"

# --- Foundry on: its settings reach every agent with no agent_env line.
# Why: a session on Azure Foundry keeps its endpoint, key and model names only in the environment,
# so an agent without them stops at its first request ("Must provide one of the baseURL or resource
# arguments"). The lead already chose Foundry, so swarm.sh passes them on without a config line.
FOUNDRY=(ANTHROPIC_FOUNDRY_RESOURCE=res-1 ANTHROPIC_FOUNDRY_API_KEY=fkey ANTHROPIC_DEFAULT_OPUS_MODEL=opus-x)
SAVED=("${PROVIDER[@]}")
PROVIDER=("${SAVED[@]}" "${FOUNDRY[@]}")
run agent t7 foundry-off "${p}" hld "${ROOT}/brief.md" >/dev/null
check "with CLAUDE_CODE_USE_FOUNDRY=0, the Foundry settings stay out" "||" \
  "$(var foundry-off ANTHROPIC_FOUNDRY_RESOURCE)|$(var foundry-off ANTHROPIC_FOUNDRY_API_KEY)|$(var foundry-off ANTHROPIC_DEFAULT_OPUS_MODEL)"
PROVIDER=("${SAVED[@]}" "${FOUNDRY[@]}" CLAUDE_CODE_USE_FOUNDRY=1)
run agent t7 foundry-on "${p}" hld "${ROOT}/brief.md" >/dev/null
check "with it on, an agent that builds nothing gets the endpoint, key and model names" "res-1|fkey|opus-x|" \
  "$(var foundry-on ANTHROPIC_FOUNDRY_RESOURCE)|$(var foundry-on ANTHROPIC_FOUNDRY_API_KEY)|$(var foundry-on ANTHROPIC_DEFAULT_OPUS_MODEL)|$(var foundry-on PROVIDER_KEY)"
PROVIDER=("${SAVED[@]}")

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
