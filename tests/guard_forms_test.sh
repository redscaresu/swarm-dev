#!/usr/bin/env bash
# guard_forms_test.sh — guard_rule (bin/lib/build.sh): the builder brief (through merge_rule, under
# both merge settings), the review brief and the conductor brief each hold it whole; its backticked
# forms are exactly the ones listed here; each Bash form it says passes, fed to hooks/merge-guard.sh
# as an agent's Bash call, is allowed, and the one it says never to write is refused. The Write tool
# and quoted-heredoc guidance is no Bash call, so it is checked as text, as is the no-prompt delete.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${REPO}/bin/swarm.sh"; HOOK="${REPO}/hooks/merge-guard.sh"
# Under /tmp, as merge_guard_test.sh's: no path in a call may say merge, or the guard parses every call.
tmp="$(mktemp -d /tmp/guard-forms.XXXXXX)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
case "${ROOT}" in *[Mm][Ee][Rr][Gg][Ee]*) echo "the test dir ${ROOT} says merge" >&2; rm -rf "${ROOT}"; exit 1 ;; esac
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo no; fi; }
flat() { tr -s '[:space:]' ' ' <<< "$1"; }

# A project whose board holds the epic f and its story s1.
P="${ROOT}/proj"; B="${P}/docs"
mkdir -p "${P}/.claude/swarm" "${B}/stories" "${B}/epics" "${P}/sub"
printf -- '---\nstatus: active\n---\n\n# f\n' > "${B}/epics/f.md"
printf -- '---\nstatus: ready\nkind: code\nepic: f\ntouches: [x.sh]\n---\n\n# s1\n\n**Done when:**\n- it holds\n' > "${B}/stories/s1.md"
git -C "${P}" init -q
git -C "${P}" add . && git -C "${P}" -c user.name=t -c user.email=t@t commit -qm init

RULE="$(flat "$(bash -c 'source "$1"; guard_rule' _ "${REPO}/bin/lib/build.sh")")"
# builder <merge> — the brief swarm.sh gives s1's builder under merge = <merge>.
builder() { echo "merge = $1" > "${P}/.claude/swarm/config"; (cd "${P}" && env -u SWARM_PROJECT bash "${SWARM}" _brief s1 2>&1); }
# lib <code> — <code> run with swarm.sh's libraries loaded for the project, names as swarm.sh makes them.
lib() {
  # shellcheck disable=SC1090,SC1091 # the libraries, from the repo under test
  PROJECT_DIR="${P}" BOARD="${B}" SWARM_HOME="${REPO}" bash -c '
    CFG_merge=agent; CFG_goal=off
    agent_name() { printf "%s" "$1"; }
    story_items() { sed -n "/^\*\*$2:\*\*/,/^\$/p" "$1"; }
    for f in agents reports build board merge lifecycle dash; do . "${SWARM_HOME}/bin/lib/${f}.sh"; done
    eval "$1"' _ "$1" 2>&1
}

check "guard_rule renders" yes "$(has 'guard hook checks each Bash call' "${RULE}")"
for m in human agent; do
  check "the builder brief under merge = ${m} holds guard_rule whole" yes "$(has "${RULE}" "$(flat "$(builder "${m}")")")"
done
check "the review brief holds guard_rule whole" yes \
  "$(has "${RULE}" "$(flat "$(lib "review_brief s1 https://github.com/o/r/pull/7 main ${P}/.swarm/reviews/s1.md abc 1")")")"
check "the conductor brief holds guard_rule whole" yes "$(has "${RULE}" "$(flat "$(lib 'conduct_brief f')")")"
check "the backlog conductor brief holds guard_rule whole" yes "$(has "${RULE}" "$(flat "$(lib 'conduct_brief backlog')")")"

# Every form guard_rule shows, in order, and what this test does with it: allow (fed to the guard,
# which must pass it), refuse (fed, must be refused) or none (not a guard matter: the variable delete
# that stopped a builder on a permission prompt).
FORMS="cd <dir> || exit 1 && <command>	allow
cd <dir>; <command>	refuse
swarm.sh merge <PR URL>	allow
--body \"\$(cat <<'EOF' ... EOF)\"	allow
swarm.sh wait <name>	allow
swarm.sh wait-pr <PR URL>	allow
rm -rf <absolute path>	allow
rm -rf \"\$SP/\$m\"	none"
# shellcheck disable=SC2016 # backticks to match, not run
check "guard_rule's forms are exactly the listed ones" "$(cut -f1 <<< "${FORMS}")" "$(grep -o '`[^`]*`' <<< "${RULE}" | tr -d '`')"

# call <command> — the guard's exit code on <command> as a swarm agent's Bash call from the project.
call() {
  local json rc=0
  json="$(python3 -c 'import json, sys; print(json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Bash",
    "cwd": sys.argv[1], "tool_input": {"command": sys.argv[2]}}))' "${P}" "$1")"
  (cd "${P}" && printf '%s' "${json}" | SWARM_AGENT=s1 CLAUDE_PLUGIN_ROOT="${REPO}" bash "${HOOK}" >/dev/null 2>&1) || rc=$?
  echo "${rc}"
}
# filled <form> — the form as an agent would run it: placeholders filled, the heredoc's ... a body line
# that mentions a merge, inside a gh pr create.
filled() {
  python3 - "$1" "${P}" <<'PY'
import sys
form, p = sys.argv[1], sys.argv[2]
for k, v in (("<dir>", p + "/sub"), ("<command>", "make check"), ("<PR URL>", "https://github.com/o/r/pull/7"),
             ("<name>", "s1"), ("<absolute path>", p + "/scratch")):
    form = form.replace(k, v)
if form.startswith("--body"):
    form = "gh pr create --title t " + form.replace(" ... ", "\nit names gh pr merge\n").replace("EOF)", "EOF\n)")
print(form)
PY
}
while IFS=$'\t' read -r form want; do
  case "${want}" in
    allow) check "the guard allows ${form}" 0 "$(call "$(filled "${form}")")" ;;
    refuse) check "the guard refuses ${form}" 2 "$(call "$(filled "${form}")")" ;;
  esac
done <<< "${FORMS}"

check "the Write tool and quoted-heredoc guidance is stated" "yes|yes" \
  "$(has 'Text that mentions a merge (a PR body, a comment) goes in a file through the Write tool, or into the command as a quoted heredoc' "${RULE}")|$(has 'Bash that writes it to a file, through a redirect or tee, is refused as a raw merge' "${RULE}")"
# shellcheck disable=SC2016 # backticks to match, not run
check "the no-prompt delete form is the path spelled out in full" yes \
  "$(has 'Delete with the path spelled out in full, `rm -rf <absolute path>`: auto mode runs that with no permission prompt' "${RULE}")"

echo "${fails} failed"
[[ ${fails} -eq 0 ]]
