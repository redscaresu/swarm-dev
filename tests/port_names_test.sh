#!/usr/bin/env bash
# port_names_test.sh — every name docs/port/names.tsv freezes from v0.31.3 is still there. A command is
# still one of swarm.sh's commands (tests/swarm_commands.sh: an arm of dispatch or its early case, or a
# ported command's marker under bin/ported/);
# a setting gets a `<key> = ` line from `swarm.sh config` in a stand-in project; a config that sets a
# removed setting still loads, with a warning naming it when its where starts with REMOVED_KEYS; an
# event hook is still run by hooks/hooks.json on its event, and its script exists; bin/gh-shim/gh, which
# swarm.sh puts on PATH, exists and can be run. Each failure names docs/port/names.tsv and the name.
# The settings and removed settings are checked from outside, through swarm.sh config, so the check
# holds once config is ported, and a command whose arm a port moves out of dispatch is found by its marker.
# It reads files by path, never through git, so it runs the same on a copy of the tree without .git.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
# shellcheck source=tests/swarm_commands.sh
source "$(dirname "${BASH_SOURCE[0]}")/swarm_commands.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMES="docs/port/names.tsv"
# The rows names.tsv has for each kind at v0.31.3, so a row deleted to quiet a failure fails here. The
# command count is one less: dash's row went on 2026-11-20, when the user chose to delete it (delete-dash).
WANT_ROWS="command=67 setting=25 removed-setting=5 hook=11"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
fails=0

gone() { echo "FAIL ${NAMES}: $1 $2 is gone: $3"; fails=$((fails + 1)); }

# event_hooks — one `<event> <command>` line for each command hooks/hooks.json runs, as names.tsv
# spells it: the plugin root and the quotes dropped.
event_hooks() {
  python3 - "${REPO}/hooks/hooks.json" <<'EOF'
import json, sys
for event, groups in json.load(open(sys.argv[1]))["hooks"].items():
    for group in groups:
        for hook in group["hooks"]:
            print(event, hook["command"].replace('"${CLAUDE_PLUGIN_ROOT}/', "").replace('"', ""))
EOF
}

# swarm_config <project> — swarm.sh config in <project>, its stderr in ${ROOT}/err.
swarm_config() { (cd "$1" && env -u HERDR_ENV -u SWARM_PROJECT bash "${REPO}/bin/swarm.sh" config "${@:2}" 2>"${ROOT}/err" < /dev/null); }

[[ -f "${REPO}/${NAMES}" ]] || { echo "FAIL ${NAMES} is missing"; exit 1; }
rows="$(grep -v '^#' "${REPO}/${NAMES}")"
bad="$(awk -F'\t' 'NF != 3 || $1 !~ /^(command|setting|removed-setting|hook)$/' <<< "${rows}")"
if [[ -n "${bad}" ]]; then echo "FAIL ${NAMES}: a row is not <kind> TAB <name> TAB <where>:"; echo "${bad}"; fails=$((fails + 1)); fi
for want in ${WANT_ROWS}; do
  got="$(awk -F'\t' -v k="${want%%=*}" '$1 == k' <<< "${rows}" | wc -l | tr -d ' ')"
  if [[ "${got}" == "${want#*=}" ]]; then echo "ok   ${NAMES} has ${got} ${want%%=*} rows"
  else echo "FAIL ${NAMES}: want ${want#*=} ${want%%=*} rows, got ${got}"; fails=$((fails + 1)); fi
done

have_arms="$(swarm_commands "${REPO}")" || exit 1
have_hooks="$(event_hooks)"
proj="${ROOT}/proj"; mkdir -p "${proj}/.claude/swarm"; : > "${proj}/.claude/swarm/config"
code=0; shown="$(swarm_config "${proj}")" || code=$?
[[ ${code} -eq 0 ]] || { echo "FAIL swarm.sh config in a stand-in project exits ${code}: $(cat "${ROOT}/err")"; fails=$((fails + 1)); }

while IFS=$'\t' read -r kind name where; do
  case "${kind}" in
    command)
      grep -qxF -- "${name}" <<< "${have_arms}" || gone command "${name}" "no arm of bin/swarm.sh's dispatch or early case, and no marker under bin/ported/" ;;
    setting)
      grep -q "^${name} = " <<< "${shown}" || gone setting "${name}" "swarm.sh config prints no '${name} = ' line" ;;
    removed-setting)
      printf 'merge = agent\n%s = anything\n' "${name}" > "${proj}/.claude/swarm/config"
      code=0; out="$(swarm_config "${proj}" merge)" || code=$?
      err="$(cat "${ROOT}/err")"
      if [[ ${code} -ne 0 || "${out}" != agent ]]; then
        gone removed-setting "${name}" "a config that sets it no longer loads (exit ${code}: ${err})"
      elif [[ "${where}" == REMOVED_KEYS* && "${err}" != *warning*" ${name} "* ]]; then
        gone removed-setting "${name}" "the config loads with no warning naming it (stderr: '${err}')"
      fi ;;
    hook)
      if [[ "${where}" == hooks/hooks.json ]]; then
        script="${name#* }"; script="${script%% *}"
        grep -qxF -- "${name}" <<< "${have_hooks}" || gone hook "'${name}'" "hooks/hooks.json no longer runs it on that event"
        [[ -f "${REPO}/${script}" ]] || gone hook "'${name}'" "${script} does not exist"
      else
        [[ -f "${REPO}/${name}" && -x "${REPO}/${name}" ]] || gone hook "${name}" "it is not an executable file"
      fi ;;
  esac
done <<< "${rows}"

if [[ ${fails} -eq 0 ]]; then echo "ok   every name in ${NAMES} is still there"; fi
[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
