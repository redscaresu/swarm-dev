#!/usr/bin/env bash
# guard_forms_test.sh — guard_rule (bin/lib/build.sh), read out of each brief that holds it: the
# builder's (through merge_rule, under both merge settings), the review agent's and both conductors'.
# Its backticked forms in each are exactly the ones listed here for that brief, with swarm.sh as the
# brief writes it; each Bash form it says passes, fed to hooks/merge-guard.sh as an agent's Bash call,
# is allowed, and the one it says never to write is refused. The Write tool and quoted-heredoc guidance
# is no Bash call, so it is checked as text, as is the no-prompt delete.
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
# rule_of <brief> — guard_rule as the brief holds it, whitespace flattened; empty when it is not there.
rule_of() { flat "$1" | sed -n "s/.*\(The plugin's guard hook checks each Bash call.*stops you on one\.\).*/\1/p"; }
# spans <rule> — each backticked form, as written, a tab, then with swarm.sh (and a SWARM_PROJECT=
# before it) as the bare word, so one list fits every brief.
spans() {
  # shellcheck disable=SC2016 # python's code, with backticks to match
  python3 -c 'import re, sys
for f in re.findall(r"`([^`]*)`", sys.argv[1]):
    print(f + "\t" + re.sub(r"^(SWARM_PROJECT=\S+ )?\S*swarm\.sh\b", "swarm.sh", f))' "$1"
}

# Every form guard_rule shows, in order, and what this test does with it: allow (fed to the guard,
# which must pass it), refuse (fed, must be refused) or none (not a guard matter: the variable delete
# that stopped a builder on a permission prompt). The waits are each brief's own; a conductor never
# waits on CI, so it is shown no wait-pr.
FORMS_HEAD="cd <dir> || exit 1 && <command>	allow
cd <dir>; <command>	refuse
swarm.sh merge <PR URL>	allow
--body \"\$(cat <<'EOF' ... EOF)\"	allow"
FORMS_TAIL="rm -rf <absolute path>	allow
rm -rf \"\$SP/\$m\"	none"
WAIT_BUILDER="swarm.sh wait-pr --head <sha> <PR URL>	allow"
WAIT_REVIEW="swarm.sh wait --stall <slug>	allow
swarm.sh wait-pr <PR URL>	allow"
WAIT_CONDUCT="swarm.sh watch	allow
swarm.sh wait <slug>	allow"

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
             ("<slug>", "s1"), ("<sha>", "abc1234"), ("<absolute path>", p + "/scratch")):
    form = form.replace(k, v)
if form.startswith("--body"):
    form = "gh pr create --title t " + form.replace(" ... ", "\nit names gh pr merge\n").replace("EOF)", "EOF\n)")
print(form)
PY
}

# brief_forms <name> <brief> <waits> — the brief holds guard_rule with exactly the listed forms and
# <waits>, the guard passes or refuses each Bash form as the list says, and the text-only guidance is there.
brief_forms() {
  local rule want raw mode
  rule="$(rule_of "$2")"
  want="$(printf '%s\n%s\n%s\n' "${FORMS_HEAD}" "$3" "${FORMS_TAIL}")"
  check "the $1 brief holds guard_rule, with exactly its listed forms" "$(cut -f1 <<< "${want}")" "$(spans "${rule}" | cut -f2)"
  [[ -n "${rule}" ]] || return 0
  while IFS=$'\t' read -r raw mode; do
    case "${mode}" in
      allow) check "the $1 brief's ${raw}: the guard allows it" 0 "$(call "$(filled "${raw}")")" ;;
      refuse) check "the $1 brief's ${raw}: the guard refuses it" 2 "$(call "$(filled "${raw}")")" ;;
    esac
  done < <(paste <(spans "${rule}" | cut -f1) <(cut -f2 <<< "${want}"))
  check "the $1 brief states the Write tool and quoted-heredoc guidance" "yes|yes" \
    "$(has 'Text that mentions a merge (a PR body, a comment) goes in a file through the Write tool, or into the command as a quoted heredoc' "${rule}")|$(has 'Bash that writes it to a file, through a redirect or tee, is refused as a raw merge' "${rule}")"
  # shellcheck disable=SC2016 # backticks to match, not run
  check "the $1 brief's no-prompt delete is the path spelled out in full" yes \
    "$(has 'Delete with the path spelled out in full, `rm -rf <absolute path>`: auto mode runs that with no permission prompt' "${rule}")"
}

for m in human agent; do brief_forms "builder (merge = ${m})" "$(builder "${m}")" "${WAIT_BUILDER}"; done
brief_forms review "$(lib "review_brief s1 https://github.com/o/r/pull/7 main ${P}/.swarm/reviews/s1.md abc 1")" "${WAIT_REVIEW}"
brief_forms conductor "$(lib 'conduct_brief f')" "${WAIT_CONDUCT}"
brief_forms "backlog conductor" "$(lib 'conduct_brief backlog')" "${WAIT_CONDUCT}"

echo "${fails} failed"
[[ ${fails} -eq 0 ]]
