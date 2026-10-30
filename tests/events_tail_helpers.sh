# shellcheck shell=bash
# events_tail_helpers.sh — sourced by the tests that run the events.tsv readers over the committed
# fixture, plain and with a tail on every row's outcome, and compare what they print. It defines no
# check and runs nothing when sourced.
#
# EVENTS_FIXTURE is tests/fixtures/events/v0.29.1-sample.tsv: a redacted sample of the swarm-dev
# project's own events.tsv, cut at the v0.29.1 tag's commit time (2026-10-29T01:14:39Z). It holds
# every row before the cut whose outcome holds `=` (37), the first row of each (command, first word
# of outcome) pair and three whole story lifecycles, 400 rows at most. tests/fixtures/events/redact.py
# made it; its header lists what the redaction keeps and what it swaps.
# shellcheck disable=SC2034 # the tests that source this file read it
EVENTS_FIXTURE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/events/v0.29.1-sample.tsv"

# events_project <dir> <events.tsv> [<tail>] — a stand-in swarm project at <dir>: a git repo with
# .claude/swarm/config, an empty board (docs/stories, docs/epics) and .swarm/events.tsv, a copy of
# <events.tsv> with <tail> appended to every row, so to column 5. Give the two projects you compare
# the same basename (…/plain/proj and …/tailed/proj): some commands print the project's name.
events_project() {
  mkdir -p "$1/.claude/swarm" "$1/docs/stories" "$1/docs/epics" "$1/.swarm" && : >> "$1/.claude/swarm/config" \
    && git -C "$1" init -q && TAIL="${3:-}" awk '{ print $0 ENVIRON["TAIL"] }' "$2" > "$1/.swarm/events.tsv"
}

# same_output <project> <project> <command>... — run <command> with each project as its cwd and fail
# when the two differ in what they print to stdout (each project's path read as <project>) or in
# their exit status, or when the first prints nothing: an empty output proves no reader ran. On a
# failure it prints the difference to stderr.
same_output() {
  local a="$1" b="$2" out_a out_b rc_a=0 rc_b=0
  shift 2
  out_a="$(cd "${a}" && "$@" 2>/dev/null)" || rc_a=$?
  out_b="$(cd "${b}" && "$@" 2>/dev/null)" || rc_b=$?
  out_a="${out_a//"${a}"/<project>}"; out_b="${out_b//"${b}"/<project>}"
  if [[ -z "${out_a}" ]]; then echo "same_output: $* printed nothing in ${a} (exit ${rc_a})" >&2; return 1; fi
  if [[ "${out_a}" == "${out_b}" && "${rc_a}" == "${rc_b}" ]]; then return 0; fi
  echo "same_output: $* differs (exit ${rc_a} in ${a}, ${rc_b} in ${b}):" >&2
  diff <(printf '%s\n' "${out_a}") <(printf '%s\n' "${out_b}") | head -20 >&2 || true
  return 1
}
