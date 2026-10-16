#!/usr/bin/env bash
# review_yield_test.sh — `swarm.sh review-yield` against fixtures. The first project: findings.tsv rows
# of four, five and six fields (the first two read as reviewer unknown), one dated before a --since, and
# builders for slugs a (PR #1) and b (PR #2), whose tells give the rounds. The second: a story built
# twice on one PR, a story built twice with a PR per attempt, each in its own epic, for --epic. gh is a
# stub on PATH. TZ is UTC, so a build with no session log starts at a known time.
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; U=https://github.com/o/r/pull
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects/p" "${dir}/bin" "${dir}/prs"
git -C "${P}" init -q
for s in a b; do printf -- '---\nkind: code\nstatus: ready\n---\n' > "${P}/docs/stories/${s}.md"; done
# gh answers from prs/<head with / as _>: its `url<TAB>state<TAB>mergedAt` lines, newest first.
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\n[ "$1 $2 $3" = "pr list --head" ] || exit 1\ncat "%s/prs/$(echo "$4" | tr / _)" 2>/dev/null\nexit 0\n' "${dir}" > "${dir}/bin/gh"
chmod +x "${dir}/bin/gh"
printf '%s\tOPEN\t\n' "${U}/1" > "${dir}/prs/story_a"
printf '%s\tOPEN\t\n' "${U}/2" > "${dir}/prs/story_b"
printf '%s\n' \
  $'2026-10-01\tcode\ta\tclaude\topus\txhigh\t-' \
  $'2026-10-01\tconduct\tconduct-e\tclaude\topus\thigh\t-' \
  $'2026-10-01\tcode\tb\tclaude\topus\txhigh\t-' > "${P}/.swarm/agents.tsv"
# a: two ok tell:findings and one ok bare tell (findings) are its rounds; the refused tell and the
# nudge are not. b has none.
printf '%s\n' \
  $'2026-10-01T10:00:00Z\ttell:findings\ta\tw:1\tok' \
  $'2026-10-01T11:00:00Z\ttell:findings\ta\tw:1\tok' \
  $'2026-10-01T12:00:00Z\ttell\ta\tw:1\tok' \
  $'2026-10-01T13:00:00Z\ttell:findings\ta\tw:1\tswarm: a is still working' \
  $'2026-10-01T14:00:00Z\ttell:nudge\ta\tw:1\tok' > "${P}/.swarm/events.tsv"
printf '%s\n' \
  $'2026-09-30\tnit\to/r#1\tfour fields, fixed, unknown' \
  $'2026-10-01\tscope\to/r#1\tfive fields, unknown\tdeclined' \
  $'2026-10-02\tvacuous\to/r#1\tt\tfixed\tcodex' \
  $'2026-10-02\tvacuous\to/r#2\tt\tdeclined\tcodex' \
  $'2026-10-03\tvacuous\thttps://github.com/o/r/pull/2\tt\tdeclined\tcodex' \
  $'2026-10-03\tnit\to/r#2\tt\tdeclined\tcodex' \
  $'2026-10-03\tnit\to/r#2\tt\tfixed\tlead' \
  $'2026-10-03\tmissing-check\to/r#1\tt\tfixed\tlead' > "${P}/.swarm/findings.tsv"

yield_of() { # <project> [args] — the report and its exit code
  local p="$1"; shift
  (cd "${p}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" \
    bash "${SWARM}" review-yield "$@" 2>&1; echo "exit $?")
}
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
snap() { cksum "${P}/.swarm/findings.tsv" "${P}/.swarm/events.tsv"; }
before="$(snap)"
H1=$'reviewer\tkind\traised\tfixed\tdeclined\tdecline_rate'
H2=$'prs\trounds\trounds_per_pr\tmax_rounds'
B1="$(printf '%s\n' "${H1}" \
  $'codex\tall\t4\t1\t3\t75%' $'codex\tvacuous\t3\t1\t2\t67%' $'codex\tnit\t1\t0\t1\t100%' \
  $'lead\tall\t2\t2\t0\t0%' $'lead\tmissing-check\t1\t1\t0\t0%' $'lead\tnit\t1\t1\t0\t0%' \
  $'unknown\tall\t2\t1\t1\t50%' $'unknown\tscope\t1\t0\t1\t100%' $'unknown\tnit\t1\t1\t0\t0%' \
  $'all\tvacuous\t3\t1\t2\t67%' $'all\tnit\t3\t2\t1\t33%' $'all\tscope\t1\t0\t1\t100%' $'all\tmissing-check\t1\t1\t0\t0%' \
  $'all\tall\t8\t4\t4\t50%')"
check "block 1 per reviewer and kind (4- and 5-field rows as unknown), per kind, and all all; block 2 sums each PR's rounds" \
  "$(yield_of "${P}")" "$(printf '%s\n' "${B1}" "" "${H2}" $'2\t3\t1.5\t3' "exit 0")"
check "--since 2026-10-01 drops the 2026-09-30 row from every count it was in" \
  "$(yield_of "${P}" --since 2026-10-01)" "$(printf '%s\n' "${H1}" \
  $'codex\tall\t4\t1\t3\t75%' $'codex\tvacuous\t3\t1\t2\t67%' $'codex\tnit\t1\t0\t1\t100%' \
  $'lead\tall\t2\t2\t0\t0%' $'lead\tmissing-check\t1\t1\t0\t0%' $'lead\tnit\t1\t1\t0\t0%' \
  $'unknown\tall\t1\t0\t1\t100%' $'unknown\tscope\t1\t0\t1\t100%' \
  $'all\tvacuous\t3\t1\t2\t67%' $'all\tnit\t2\t1\t1\t50%' $'all\tscope\t1\t0\t1\t100%' $'all\tmissing-check\t1\t1\t0\t0%' \
  $'all\tall\t7\t3\t4\t57%' "" "${H2}" $'2\t3\t1.5\t3' "exit 0")"
USAGE="swarm: usage: swarm.sh review-yield [--since YYYY-MM-DD] [--epic <slug>]"
for args in "--since 2026-1-5" "--since" "--bogus"; do
  # shellcheck disable=SC2086 # split on purpose: each case is its own arguments
  check "${args} exits non-zero with the usage line" "$(yield_of "${P}" ${args})" "$(printf '%s\n' "${USAGE}" "exit 1")"
done
mv "${P}/.swarm/agents.tsv" "${dir}/agents.tsv"
check "with no agents.tsv: block 1 as before, block 2 all zero, exit 0" \
  "$(yield_of "${P}")" "$(printf '%s\n' "${B1}" "" "${H2}" $'0\t0\t0\t0' "exit 0")"
mv "${dir}/agents.tsv" "${P}/.swarm/agents.tsv"
check "findings.tsv and events.tsv are byte-identical after every run" "$(snap)" "${before}"

# --- Attempts and epics, in a second project. c (epic ec) is built twice with no session log, so both
# builds take its one PR #3: one tell to the first, two to the retry, three rounds on #3. d (epic ed)
# is built twice, each attempt opening its own PR (#4, then #5) as its session log names: one tell to
# the first, four to the retry.
Q="${dir}/two"
mkdir -p "${Q}/.swarm" "${Q}/docs/stories"
git -C "${Q}" init -q
printf -- '---\nkind: code\nepic: ec\nstatus: ready\n---\n' > "${Q}/docs/stories/c.md"
printf -- '---\nkind: code\nepic: ed\nstatus: ready\n---\n' > "${Q}/docs/stories/d.md"
printf '%s\tOPEN\t\n' "${U}/3" > "${dir}/prs/story_c"
printf '%s\tOPEN\t\n%s\tCLOSED\t\n' "${U}/5" "${U}/4" > "${dir}/prs/story_d"
for n in 4 5; do
  printf '{"type":"user","cwd":"%s/two-wt/d","timestamp":"2026-10-0%sT09:00:00Z"}\n{"type":"user","message":{"content":"%s/%s\\n"}}\n' \
    "${dir}" "$((n - 3))" "${U}" "${n}" > "${dir}/projects/p/d${n}.jsonl"
done
printf '%s\n' \
  $'2026-10-01\tcode\tc\tclaude\topus\txhigh\t-' \
  $'2026-10-01\tcode\td\tclaude\topus\txhigh\td4' \
  $'2026-10-02\tescalate\tc\tclaude\tfable\txhigh\t-' \
  $'2026-10-02\tescalate\td\tclaude\tfable\txhigh\td5' > "${Q}/.swarm/agents.tsv"
printf '%s\n' \
  $'2026-10-01T10:00:00Z\ttell:findings\tc\tw:1\tok' \
  $'2026-10-02T10:00:00Z\ttell:findings\tc\tw:1\tok' \
  $'2026-10-02T11:00:00Z\ttell:findings\tc\tw:1\tok' \
  $'2026-10-01T10:00:00Z\ttell:findings\td\tw:1\tok' \
  $'2026-10-02T10:00:00Z\ttell:findings\td\tw:1\tok' \
  $'2026-10-02T11:00:00Z\ttell:findings\td\tw:1\tok' \
  $'2026-10-02T12:00:00Z\ttell:findings\td\tw:1\tok' \
  $'2026-10-02T13:00:00Z\ttell:findings\td\tw:1\tok' > "${Q}/.swarm/events.tsv"
printf '%s\n' \
  $'2026-10-02\tvacuous\to/r#3\tt\tdeclined\tcodex' \
  $'2026-10-02\tnit\to/r#4\tt\tfixed\tcodex' \
  $'2026-10-02\tnit\to/r#5\tt\tdeclined\tlead' > "${Q}/.swarm/findings.tsv"
check "attempts sharing a PR add up; attempts with their own PRs keep their own tells" \
  "$(yield_of "${Q}" | tail -3)" "$(printf '%s\n' "${H2}" $'3\t8\t2.7\t4' "exit 0")"
check "--epic ec: only its PR #3 and its finding, and the PR it counted" \
  "$(yield_of "${Q}" --epic ec)" "$(printf '%s\n' "${H1}" \
  $'codex\tall\t1\t0\t1\t100%' $'codex\tvacuous\t1\t0\t1\t100%' $'all\tvacuous\t1\t0\t1\t100%' $'all\tall\t1\t0\t1\t100%' \
  "" "${H2}" $'1\t3\t3\t3' "" pr "${U}/3" "exit 0")"
check "--epic ed: #4 with its one round and #5 with its four, ec left out" \
  "$(yield_of "${Q}" --epic ed)" "$(printf '%s\n' "${H1}" \
  $'codex\tall\t1\t1\t0\t0%' $'codex\tnit\t1\t1\t0\t0%' $'lead\tall\t1\t0\t1\t100%' $'lead\tnit\t1\t0\t1\t100%' \
  $'all\tnit\t2\t1\t1\t50%' $'all\tall\t2\t1\t1\t50%' \
  "" "${H2}" $'2\t5\t2.5\t4' "" pr "${U}/4" "${U}/5" "exit 0")"
# --since keeps #4's finding (dated 2026-10-02) but not its build's round (started 2026-10-01), so
# block 3 lists both PRs: each one that either block counted.
check "--epic ed --since 2026-10-02: #4 in block 1 only, #5 in both, and block 3 lists the two" \
  "$(yield_of "${Q}" --epic ed --since 2026-10-02)" "$(printf '%s\n' "${H1}" \
  $'codex\tall\t1\t1\t0\t0%' $'codex\tnit\t1\t1\t0\t0%' $'lead\tall\t1\t0\t1\t100%' $'lead\tnit\t1\t0\t1\t100%' \
  $'all\tnit\t2\t1\t1\t50%' $'all\tall\t2\t1\t1\t50%' \
  "" "${H2}" $'1\t4\t4\t4' "" pr "${U}/4" "${U}/5" "exit 0")"
check "--epic ed --since 2026-10-03: nothing counted, so block 3 lists no PR" \
  "$(yield_of "${Q}" --epic ed --since 2026-10-03)" "$(printf '%s\n' "${H1}" $'all\tall\t0\t0\t0\t-' "" "${H2}" $'0\t0\t0\t0' "" pr "exit 0")"

# A finding whose kind is the word all (log-finding takes it) is a kind of its own, counted once.
R="${dir}/three"
mkdir -p "${R}/.swarm"
git -C "${R}" init -q
printf '%s\n' $'2026-10-02\tall\to/r#1\tt\tfixed\tcodex' $'2026-10-02\tnit\to/r#1\tt\tdeclined\tcodex' > "${R}/.swarm/findings.tsv"
check "a kind named all is counted once, apart from the totals" \
  "$(yield_of "${R}")" "$(printf '%s\n' "${H1}" \
  $'codex\tall\t2\t1\t1\t50%' $'codex\tnit\t1\t0\t1\t100%' $'codex\tall\t1\t1\t0\t0%' \
  $'all\tnit\t1\t0\t1\t100%' $'all\tall\t1\t1\t0\t0%' $'all\tall\t2\t1\t1\t50%' "" "${H2}" $'0\t0\t0\t0' "exit 0")"

if [[ "${fails}" -ne 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
