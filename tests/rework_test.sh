#!/usr/bin/env bash
# rework_test.sh — outcomes' rework column and flow's reviewer rows against a fixture: a's PR #1 is fixed
# 3 days after it merged by fix-a's PR #2, whose body names #1 (rework); b's PR #3 is fixed 9 days after
# it merged by fix-b's PR #4, whose title names its URL (past 7 days: no rework); c's PR #5 has an escaped
# finding 3 days after it merged (rework); d's PR #6 never merged (no value); e's PR #7 merged at 00:30 UTC
# on 2026-10-03 and has an escaped finding dated 2026-10-02, a local day: rework in Los Angeles, where it
# merged on the evening of 2026-10-02, and not in UTC. gh is a stub on PATH.
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; U=https://github.com/o/r/pull
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects/p" "${dir}/bin" "${dir}/prs"
git -C "${P}" init -q
for s in a b c d e fix-a fix-b; do printf -- '---\nkind: code\nstatus: ready\n---\n' > "${P}/docs/stories/${s}.md"; done
# gh answers from prs/<head with / as _>: url state mergedAt createdAt main_merges names, one PR a line.
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\n[ "$1 $2 $3" = "pr list --head" ] || exit 1\ncat "%s/prs/$(echo "$4" | tr / _)" 2>/dev/null\nexit 0\n' "${dir}" > "${dir}/bin/gh"
chmod +x "${dir}/bin/gh"
pr() { printf '%s/%s\t%s\t%s\t2026-10-01T09:00:00Z\t0\t%s\n' "${U}" "$2" "$3" "$4" "${5:-}" > "${dir}/prs/story_$1"; }
pr a 1 MERGED 2026-10-01T10:00:00Z
pr fix-a 2 MERGED 2026-10-04T10:00:00Z '#1'
pr b 3 MERGED 2026-10-01T10:00:00Z
pr fix-b 4 MERGED 2026-10-10T10:00:00Z github.com/o/r/pull/3
pr c 5 MERGED 2026-10-02T10:00:00Z
pr d 6 OPEN ""
pr e 7 MERGED 2026-10-03T00:30:00Z
for s in a b c d e fix-a fix-b; do printf '2026-10-01\tcode\t%s\tclaude\topus\txhigh\t-\n' "${s}"; done > "${P}/.swarm/agents.tsv"
: > "${P}/.swarm/events.tsv"
printf '%s\n' \
  $'2026-10-01\tvacuous\to/r#1\tt\tfixed\tcodex' \
  $'2026-10-01\tnit\to/r#1\tt\tdeclined\tcode-review' \
  $'2026-10-01\tnit\to/r#3\tt\tfixed\tlead' \
  $'2026-10-02\tvacuous\to/r#5\tt\tfixed\tcodex' \
  $'2026-10-05\tmissed\to/r#5\tt\tescaped\tescaped' \
  $'2026-10-02\tmissed\to/r#7\tt\tescaped\tescaped' > "${P}/.swarm/findings.tsv"

run() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" bash "${SWARM}" "$@"); }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
rework() { run outcomes | sed '/^$/,$d' | awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) at[$i] = i } { print $at["slug"], $at["pr"], $at["rework"] }'; }
check "outcomes: rework is 1 for a fix 3 days later naming it and for an escaped finding, 0 at 9 days, empty unmerged" \
  "$(rework)" "$(printf '%s\n' "slug pr rework" "a ${U}/1 1" "b ${U}/3 0" "c ${U}/5 1" "d ${U}/6 " "e ${U}/7 0" "fix-a ${U}/2 0" "fix-b ${U}/4 0")"
check "outcomes: an escaped finding's local day counts from the merge's local day" \
  "$(TZ=America/Los_Angeles rework | grep '^e ')" "e ${U}/7 1"
check "flow reviewers: rework counts against each reviewer that raised a finding on the reworked PR" \
  "$(run flow | awk '/^## / { f = $0 == "## reviewers"; next } f && /^$/ { f = 0 } f' | cut -f1,2,7)" \
  "$(printf '%s\n' $'reviewer\tkind\trework' $'code-review\tall\t1' $'code-review\tnit\t1' $'codex\tall\t2' $'codex\tvacuous\t2' \
  $'lead\tall\t0' $'lead\tnit\t0' $'all\tnit\t1' $'all\tvacuous\t2' $'all\tall\t2')"
[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
