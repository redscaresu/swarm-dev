#!/usr/bin/env bash
# swarm_commands.sh — the one reader of the command names bin/swarm.sh runs, for the tests that check a
# name against them: doc_check_test.sh, skill_test.sh, port_names_test.sh and events_test.sh. Only they
# source it. A test takes the reach of each helper it names (tests/port_tests_list_test.sh), so this
# reader in tests/test_helpers.sh, which every test sources, would give every test text reach.

# swarm_commands <repo> — every command <repo>'s bin/swarm.sh runs, one a line, sorted: dispatch's arms,
# the early case's names (version and update, which run before a project is looked for), and the name of
# each file under bin/ported/, a ported command's marker. No bin/ported/ is no marker, and neither is a
# dotfile there. Fails, with a FAIL line on stderr naming what it found empty, when dispatch's arms and the
# markers give no name (whatever the early case gives), and when the early case gives none.
swarm_commands() {
  local src="$1/bin/swarm.sh" ported="$1/bin/ported" early arms marks="" f
  [[ -f "${src}" ]] || { echo "FAIL swarm_commands: there is no ${src}" >&2; return 1; }
  # shellcheck disable=SC2016 # the ${1:-} is the literal text of swarm.sh's early case
  early="$(awk '/^case "\$\{1:-\}" in$/ { e = 1; next } e && /^esac/ { exit }
    e && match($0, /^  [a-z_-]+\)/) { print substr($0, 3, RLENGTH - 3) }' "${src}")"
  arms="$(awk '/^dispatch\(\) \{/ { d = 1; next } d && /^  esac/ { exit }
    d && match($0, /^    [a-z_|-]+\)/) { a = substr($0, 5, RLENGTH - 5); gsub(/\|/, "\n", a); print a }' "${src}")"
  if [[ -d "${ported}" ]]; then
    for f in "${ported}"/*; do [[ -f "${f}" ]] && marks="${marks}${f##*/}"$'\n'; done
  fi
  if [[ -z "${arms}${marks}" ]]; then
    echo "FAIL swarm_commands: found no command in ${src}'s dispatch arms or the markers under ${ported}/" >&2
    return 1
  fi
  if [[ -z "${early}" ]]; then
    echo "FAIL swarm_commands: the early case (case \"\${1:-}\" in) of ${src} gave no command" >&2
    return 1
  fi
  printf '%s\n%s\n%s' "${arms}" "${early}" "${marks}" | grep -v '^$' | LC_ALL=C sort -u
}
