#!/usr/bin/env bash
# review_yield_test.sh — `swarm.sh flow`'s reviewers section against fixtures. The first project: findings.tsv rows
# of four, five, six and seven fields (the first two read as reviewer unknown), one dated before a --since, and
# builders for slugs a (PR #1) and b (PR #2), whose tells give the rounds. The second: a story built
# twice on one PR, a story built twice with a PR per attempt, each in its own epic, for --epic. gh is a
# stub on PATH. TZ is UTC, so a build with no session log starts at a known time.
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
export SWARM_GH_CACHE=""   # each run reads gh afresh, as its stub answers change between runs (gh_cache_test.sh tests the cache)
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
P="${dir}/repo"; U=https://github.com/o/r/pull
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects/p" "${dir}/bin" "${dir}/prs"
git -C "${P}" init -q
for s in a b; do printf -- '---\nkind: code\nstatus: ready\n---\n' > "${P}/docs/stories/${s}.md"; done
# gh answers from prs/<head with / as _>: its `url<TAB>state<TAB>mergedAt` lines, newest first.
# shellcheck disable=SC2016 # the stub's own shell expands these
# pr view <n> prints heads/<n>, its head branch (a split's board PR's is board/scope-<epic>), and
# fails while ghfail exists.
printf '#!/bin/sh\n[ "$1 $2" = "pr view" ] && { [ ! -e "%s/ghfail" ] && cat "%s/heads/$3" 2>/dev/null; exit; }\n[ "$1 $2 $3" = "pr list --head" ] || exit 1\ncat "%s/prs/$(echo "$4" | tr / _)" 2>/dev/null\nexit 0\n' "${dir}" "${dir}" "${dir}" > "${dir}/bin/gh"
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

yield_of() { # <project> [args] — flow's reviewers section (or all flow printed, when it failed) and its exit code
  local p="$1" out code; shift
  out="$(cd "${p}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" \
    bash "${SWARM}" flow "$@" 2>&1)" && code=0 || code=$?
  [[ ${code} -ne 0 ]] || out="$(awk '/^## / { f = $0 == "## reviewers"; next } f' <<< "${out}")"
  printf '%s\nexit %s\n' "${out}" "${code}"
}
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
snap() { cksum "${P}/.swarm/findings.tsv" "${P}/.swarm/events.tsv"; }
before="$(snap)"
H1=$'reviewer\tkind\traised\tfixed\tdeclined\tdecline_rate\trework'
H2=$'prs\trounds\trounds_per_pr\tmax_rounds'
B1="$(printf '%s\n' "${H1}" \
  $'codex\tall\t4\t1\t3\t75%\t0' $'codex\tvacuous\t3\t1\t2\t67%\t0' $'codex\tnit\t1\t0\t1\t100%\t0' \
  $'lead\tall\t2\t2\t0\t0%\t0' $'lead\tmissing-check\t1\t1\t0\t0%\t0' $'lead\tnit\t1\t1\t0\t0%\t0' \
  $'unknown\tall\t2\t1\t1\t50%\t0' $'unknown\tscope\t1\t0\t1\t100%\t0' $'unknown\tnit\t1\t1\t0\t0%\t0' \
  $'all\tvacuous\t3\t1\t2\t67%\t0' $'all\tnit\t3\t2\t1\t33%\t0' $'all\tscope\t1\t0\t1\t100%\t0' $'all\tmissing-check\t1\t1\t0\t0%\t0' \
  $'all\tall\t8\t4\t4\t50%\t0')"
check "block 1 per reviewer and kind (4- and 5-field rows as unknown), per kind, and all all; block 2 sums each PR's rounds" \
  "$(yield_of "${P}")" "$(printf '%s\n' "${B1}" "" "${H2}" $'2\t3\t1.5\t3' "exit 0")"
# A declined row with its reason (7 fields) beside the 4- and 6-field ones: the old rows count as
# before; only the new row's own lines and all all change. An escaped row (a defect review missed)
# counts nowhere: were it counted, vacuous's lines would change and an escaped line appear.
cp "${P}/.swarm/findings.tsv" "${dir}/findings.bak"
printf '%s\n' $'2026-10-03\tplan-gap\to/r#1\tt\tdeclined\tskeptic\tnit' \
  $'2026-10-03\tvacuous\to/r#1\tt\tescaped\tescaped' >> "${P}/.swarm/findings.tsv"
old_rows() { grep -v -e '^skeptic' -e $'\tplan-gap\t' -e $'^all\tall\t' <<< "$1"; }
check "a 7-field row leaves the 4-, 5- and 6-field rows' counts as they were" \
  "$(old_rows "$(yield_of "${P}")")" "$(old_rows "$(printf '%s\n' "${B1}" "" "${H2}" $'2\t3\t1.5\t3' "exit 0")")"
out="$(yield_of "${P}")"
check "the 7-field row counts as one decline, all all only adds it, and no escaped line" \
  "$(grep -E $'^(skeptic|all\tall|escaped)\t' <<< "${out}")" "$(printf '%s\n' $'skeptic\tall\t1\t0\t1\t100%\t0' $'skeptic\tplan-gap\t1\t0\t1\t100%\t0' $'all\tall\t9\t4\t5\t56%\t0')"
cp "${dir}/findings.bak" "${P}/.swarm/findings.tsv"
# A split's board PR (#9): one finding the split critic raised and the lead fixed, and one split-gap it
# missed that a child's plan found later (escaped). The critic's counts are a reviewer of their own, and
# the split block sets its fix beside the escaped gap; neither row changes block 1's old counts.
printf '%s\n' $'2026-10-03\tsplit-order\to/r#9\tt\tfixed\tsplit-critic' \
  $'2026-10-04\tsplit-gap\to/r#9\tt\tescaped\tescaped' >> "${P}/.swarm/findings.tsv"
out="$(yield_of "${P}")"
check "the split critic's fixed finding is a reviewers row" \
  "$(grep -E $'^split-critic\t' <<< "${out}")" "$(printf '%s\n' $'split-critic\tall\t1\t1\t0\t0%\t0' $'split-critic\tsplit-order\t1\t1\t0\t0%\t0')"
check "the split block sets the critic's fix beside the escaped split-gap" \
  "$(grep -A1 $'^split\t' <<< "${out}")" "$(printf '%s\n' $'split\tcritic_fixed\tcritic_declined\tescaped_split_gaps' $'o/r#9\t1\t0\t1')"
# A split is dated by its critic's rows (2026-10-03); every escaped gap counts against it, whatever its day.
check "--until 2026-10-03 keeps the split and still counts its later escaped split-gap" \
  "$(yield_of "${P}" --until 2026-10-03 | grep -A1 $'^split\t')" "$(printf '%s\n' $'split\tcritic_fixed\tcritic_declined\tescaped_split_gaps' $'o/r#9\t1\t0\t1')"
check "--since 2026-10-04 leaves out the split made before it, its later escaped gap too" \
  "$(yield_of "${P}" --since 2026-10-04 | grep -c $'^split\t' || true)" "0"
# --epic: gh names #9's head board/scope-big, so the split is big's, and its child big-a's by its parent:.
mkdir -p "${dir}/heads" "${P}/docs/epics"; echo board/scope-big > "${dir}/heads/9"
printf -- '---\nstatus: active\nparent: big\n---\n' > "${P}/docs/epics/big-a.md"
SPLIT="$(printf '%s\n' $'split\tcritic_fixed\tcritic_declined\tescaped_split_gaps' $'o/r#9\t1\t0\t1')"
check "--epic big (the parent) prints the split line" "$(yield_of "${P}" --epic big | grep -A1 $'^split\t')" "${SPLIT}"
check "--epic big-a (a child) prints its parent's split line" "$(yield_of "${P}" --epic big-a | grep -A1 $'^split\t')" "${SPLIT}"
check "--epic other prints no split" "$(yield_of "${P}" --epic other | grep -c $'^split\t' || true)" "0"
# A child that finished (its file deleted from the board) still names its parent, from git history.
git -C "${P}" add docs/epics/big-a.md && git -C "${P}" -c user.name=t -c user.email=t@t commit -qm child
git -C "${P}" rm -q docs/epics/big-a.md && git -C "${P}" -c user.name=t -c user.email=t@t commit -qm finished
check "--epic big-a after its file is deleted still prints its parent's split line" "$(yield_of "${P}" --epic big-a | grep -A1 $'^split\t')" "${SPLIT}"
# When gh fails, a split with no split-pr record is left out of --epic, and a note says so.
touch "${dir}/ghfail"
check "--epic big when gh fails: no split line, and a note that gh could not name the epic" \
  "$(yield_of "${P}" --epic big | grep -c $'^split\t' || true) $(yield_of "${P}" --epic big | grep -c '^split: gh could not name the epic of 1 split board PR' || true)" "0 1"
# A split board-pr open recorded (.swarm/<epic>/split-pr) shows even when the critic found nothing,
# dated by that day, and --epic finds it there with no gh.
mkdir -p "${P}/.swarm/clean"; printf '2026-10-03\t%s\n' "${U}/10" > "${P}/.swarm/clean/split-pr"
check "a clean split shows with 0 fixed, 0 declined, 0 escaped" "$(yield_of "${P}" | grep -F "${U}/10")" "${U}/10	0	0	0"
check "--epic clean finds the recorded split with gh failing" "$(yield_of "${P}" --epic clean | grep -A1 $'^split\t')" \
  "$(printf '%s\n' $'split\tcritic_fixed\tcritic_declined\tescaped_split_gaps' "${U}/10	0	0	0")"
check "--since 2026-10-04 leaves out the clean split dated 2026-10-03" "$(yield_of "${P}" --since 2026-10-04 | grep -cF "${U}/10" || true)" "0"
rm -rf "${dir}/heads" "${dir}/ghfail" "${P}/docs/epics" "${P}/.swarm/clean"
cp "${dir}/findings.bak" "${P}/.swarm/findings.tsv"
check "--since 2026-10-01 drops the 2026-09-30 row from every count it was in" \
  "$(yield_of "${P}" --since 2026-10-01)" "$(printf '%s\n' "${H1}" \
  $'codex\tall\t4\t1\t3\t75%\t0' $'codex\tvacuous\t3\t1\t2\t67%\t0' $'codex\tnit\t1\t0\t1\t100%\t0' \
  $'lead\tall\t2\t2\t0\t0%\t0' $'lead\tmissing-check\t1\t1\t0\t0%\t0' $'lead\tnit\t1\t1\t0\t0%\t0' \
  $'unknown\tall\t1\t0\t1\t100%\t0' $'unknown\tscope\t1\t0\t1\t100%\t0' \
  $'all\tvacuous\t3\t1\t2\t67%\t0' $'all\tnit\t2\t1\t1\t50%\t0' $'all\tscope\t1\t0\t1\t100%\t0' $'all\tmissing-check\t1\t1\t0\t0%\t0' \
  $'all\tall\t7\t3\t4\t57%\t0' "" "${H2}" $'2\t3\t1.5\t3' "exit 0")"
USAGE="swarm: usage: swarm.sh flow [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--epic <slug>] [--no-cache]"
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
  $'codex\tall\t1\t0\t1\t100%\t0' $'codex\tvacuous\t1\t0\t1\t100%\t0' $'all\tvacuous\t1\t0\t1\t100%\t0' $'all\tall\t1\t0\t1\t100%\t0' \
  "" "${H2}" $'1\t3\t3\t3' "" pr "${U}/3" "exit 0")"
check "--epic ed: #4 with its one round and #5 with its four, ec left out" \
  "$(yield_of "${Q}" --epic ed)" "$(printf '%s\n' "${H1}" \
  $'codex\tall\t1\t1\t0\t0%\t0' $'codex\tnit\t1\t1\t0\t0%\t0' $'lead\tall\t1\t0\t1\t100%\t0' $'lead\tnit\t1\t0\t1\t100%\t0' \
  $'all\tnit\t2\t1\t1\t50%\t0' $'all\tall\t2\t1\t1\t50%\t0' \
  "" "${H2}" $'2\t5\t2.5\t4' "" pr "${U}/4" "${U}/5" "exit 0")"
# --since keeps #4's finding (dated 2026-10-02) but not its build's round (started 2026-10-01), so
# block 3 lists both PRs: each one that either block counted.
check "--epic ed --since 2026-10-02: #4 in block 1 only, #5 in both, and block 3 lists the two" \
  "$(yield_of "${Q}" --epic ed --since 2026-10-02)" "$(printf '%s\n' "${H1}" \
  $'codex\tall\t1\t1\t0\t0%\t0' $'codex\tnit\t1\t1\t0\t0%\t0' $'lead\tall\t1\t0\t1\t100%\t0' $'lead\tnit\t1\t0\t1\t100%\t0' \
  $'all\tnit\t2\t1\t1\t50%\t0' $'all\tall\t2\t1\t1\t50%\t0' \
  "" "${H2}" $'1\t4\t4\t4' "" pr "${U}/4" "${U}/5" "exit 0")"
check "--epic ed --since 2026-10-03: nothing counted, so block 3 lists no PR" \
  "$(yield_of "${Q}" --epic ed --since 2026-10-03)" "$(printf '%s\n' "${H1}" $'all\tall\t0\t0\t0\t-\t0' "" "${H2}" $'0\t0\t0\t0' "" pr "exit 0")"

# A finding whose kind is the word all (log-finding takes it) is a kind of its own, counted once.
R="${dir}/three"
mkdir -p "${R}/.swarm"
git -C "${R}" init -q
printf '%s\n' $'2026-10-02\tall\to/r#1\tt\tfixed\tcodex' $'2026-10-02\tnit\to/r#1\tt\tdeclined\tcodex' > "${R}/.swarm/findings.tsv"
check "a kind named all is counted once, apart from the totals" \
  "$(yield_of "${R}")" "$(printf '%s\n' "${H1}" \
  $'codex\tall\t2\t1\t1\t50%\t0' $'codex\tnit\t1\t0\t1\t100%\t0' $'codex\tall\t1\t1\t0\t0%\t0' \
  $'all\tnit\t1\t0\t1\t100%\t0' $'all\tall\t1\t1\t0\t0%\t0' $'all\tall\t2\t1\t1\t50%\t0' "" "${H2}" $'0\t0\t0\t0' "exit 0")"

# --epic with no split rows reads no epic's history: a git on PATH logs every call.
printf '#!/bin/sh\necho "$*" >> "%s/git.log"\nexec %s "$@"\n' "${dir}" "$(command -v git)" > "${dir}/bin/git"; chmod +x "${dir}/bin/git"
yield_of "${R}" --epic e >/dev/null
check "--epic with no splits runs no git log over the board's history" "$(grep -c -- '--diff-filter=D' "${dir}/git.log" || true)" "0"
rm "${dir}/bin/git"

if [[ "${fails}" -ne 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
