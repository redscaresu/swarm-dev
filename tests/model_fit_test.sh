#!/usr/bin/env bash
# model_fit_test.sh — flow's model_fit section. Cell opus/high code <=300 bin/ holds five stories:
# s1 ($2.00 and $0.50 of subagents, PR #1, 120 min, 2 findings), s2 ($1.00, #2, 60 min), s3 (opus
# $1.00, then escalated to fable $3.00 on #3, 1440 min, 1 finding; it stays under opus), s4 ($1.00,
# #4 still open, 1 finding) and s5 ($0.50, #5, 60 min): $9.00 over 4 merged is 2.25, 3 of 4 on the
# first attempt (s4 is still in flight, so it is left out), 6 builds over 5, 4 findings over 5 PRs, 420 minutes on average. Rework
# is outcomes' column: 1 on s1's build and on s3's latest, so 2 stories; an escaped finding on #3 and one on
# #5 count as escaped.
# Cell sonnet/medium docs none root holds two stories, so it prints its count alone. The by_risk block
# has a header of its own and a row per model, effort, kind and risk over every size and area: with the
# s stories at risk: high and split over two sizes, each cell is a count alone and the by_risk row has
# the five-story figures; with s5 left out, the row of 4 is a count alone; four neighbour groups, each
# differing from it in one field (effort, risk, kind or model), get rows of their own. Then the same
# through swarm.sh flow: a story deleted in a git commit keeps its class. The s stories' touches hold
# a parenthesised note and functions after a file (`bin/y.sh:f, g, h, i`), which are no files; t1's
# and t2's name a bare Makefile and LICENSE the project has, which are files at the root (root), and t2's docs file
# counts once whatever functions follow it. Also, a cell
# whose merges gh could not read prints no rate, a story closed unmerged counts against the rate, a
# build with 0.00 of subagents adds to no subagent row, and:
# which PR texts fix a PR (a fix phrase; never a Merge after, Depends on, Stacked on or Merged
# origin/main clause, a negated fix or a release PR, while a negation about the bug leaves the fix
# standing; a bare #N in its own repo only), a mergedAt that does not parse
# is skipped, a merged story with no merged_at adds no wait, and a build
# with no cost is named.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
export TZ=UTC

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
mkdir -p "${dir}/bin"
U=https://github.com/o/r/pull
row() { # <date> <slug> <kind> <model> <effort> <cost> <attempts> <fixed> <pr> <merged_at> <story_merged> <started> <subagent_cost> <pr_state> <rework>
  printf '%s\t%s\t%s\t\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\te1\t%s\t%s\n' "$@"
}
# A build with a session log has a subagent cost, 0.00 when it ran none, as outcomes writes it.
ROWS="$(printf 'date\tslug\tkind\trisk\tmodel\teffort\tcost_usd\tattempts\tfindings_fixed\tpr\tmerged_at\tstory_merged\tstarted\tsubagent_cost_usd\tepic\tpr_state\trework\n'
  row 2026-10-02 s1 code opus high 2.00 1 2 "${U}/1" 2026-10-02T12:00:00Z true 2026-10-02T10:00:00Z 0.50 MERGED 1
  row 2026-10-02 s2 code opus high 1.00 1 0 "${U}/2" 2026-10-02T11:00:00Z true 2026-10-02T10:00:00Z 0.00 MERGED 0
  row 2026-10-02 s3 code opus high 1.00 1 0 "${U}/3" 2026-10-03T10:00:00Z true 2026-10-02T10:00:00Z 0.00 MERGED ""
  row 2026-10-03 s3 code fable xhigh 3.00 2 1 "${U}/3" 2026-10-03T10:00:00Z true 2026-10-03T08:00:00Z 0.00 MERGED 1
  row 2026-10-02 s4 code opus high 1.00 1 1 "${U}/4" "" false 2026-10-02T10:00:00Z 0.00 OPEN ""
  row 2026-10-10 s5 code opus high 0.50 1 0 "${U}/5" 2026-10-10T10:00:00Z true 2026-10-10T09:00:00Z 0.00 MERGED 0
  row 2026-10-02 t1 docs sonnet medium 0.20 1 0 "${U}/6" 2026-10-02T12:00:00Z true 2026-10-02T10:00:00Z 0.00 MERGED 0
  row 2026-10-02 t2 docs sonnet medium 0.20 1 0 "" "" "" "" "" "" "")"
STORIES="$(for s in s1 s2 s3 s4 s5; do printf '%s\t150\tbin/lib/x.py (new, renamed), bin/y.sh:f, g, h, i, docs/z.md\n' "${s}"; done
  printf 't1\t\tdocs/b.md, Makefile, LICENSE\nt2\t\tdocs/a.md:f, g, h, Makefile, LICENSE\n')"
P="${dir}/proj"; mkdir -p "${P}/.swarm"; touch "${P}/Makefile" "${P}/LICENSE"
printf '%s\n' $'2026-10-06\tmissed\thttps://github.com/o/r/pull/3\tx\tescaped\tescaped' \
  $'2026-10-18\tmissed\thttps://github.com/o/r/pull/5\tx\tescaped\tescaped' \
  $'2026-10-06\tnit\thttps://github.com/o/r/pull/1\tx\tdeclined\tcodex\tnit' > "${P}/.swarm/findings.tsv"
# gh fails: model_fit reads rework from outcomes' column (rework_test.sh checks how outcomes computes it).
printf '#!/bin/sh\nexit 1\n' > "${dir}/bin/gh"
chmod +x "${dir}/bin/gh"
PY="$(command -v python3)"
section() { # the model_fit section alone, as flow runs it; PATH may be given
  PATH="${PATH_FOR:-${dir}/bin:${PATH}}" SWARM_FINDING_REVIEWERS="codex escaped" SWARM_ROWS="${ROWS}" SWARM_STORIES="${STORIES}" \
    "${PY}" "${REPO}/bin/lib/flow_report.py" "${SINCE:-2026-10-01}" "${UNTIL:-9999-12-30}" "" x x "${P}/.swarm/findings.tsv" x x x x "" x model_fit
}
table() { sed '/^$/,$d'; }               # the main table, up to the first blank line
by_risk() { sed -n '/^by_risk\t/,/^$/p' | sed '/^$/d'; }   # the by_risk block, header included
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
out="$(section)"
check "the five-story cell: every column, the escalation to fable under opus, rework from outcomes' column" \
  "$(table <<< "${out}" | grep $'^opus\thigh\tcode')" $'opus\thigh\tcode\t-\t<=300\tbin/\t5\t2.25\t75%\t1.2\t0.8\t2\t2\t420'
check "no cell for the fable build" "$(grep -c '^fable' <<< "${out}" || true)" 0
check "the two-story cell prints its count and no verdict" \
  "$(table <<< "${out}" | grep $'^sonnet\tmedium')" $'sonnet\tmedium\tdocs\t-\tnone\troot\t2\t-\t-\t-\t-\t-\t-\t-'
CLOSED="${ROWS//$'\tOPEN'/$'\tCLOSED'}"
check "a story closed unmerged on its first build counts against the first-attempt rate: 3 of 5" \
  "$(ROWS="${CLOSED}" section | table | grep $'^opus\thigh\tcode' | cut -f9)" 60%
UNKNOWN="${ROWS//$'\ttrue\t'/$'\t\t'}"
check "a cell whose merges gh could not read prints no first-attempt rate" \
  "$(ROWS="${UNKNOWN//$'\tfalse\t'/$'\t\t'}" section | table | grep $'^opus\thigh\tcode' | cut -f9)" -
# by_risk: a row per model, effort, kind and risk over every size and area, through the same cell().
check "the by_risk block: its own header, one row per model, effort, kind and risk, the two-story row a count alone" \
  "$(by_risk <<< "${out}")" "$(printf '%s\n' \
  $'by_risk\teffort\tkind\trisk\tstories\tcost_per_merged_usd\tfirst_attempt_merge_rate\tmean_attempts\tfindings_per_pr\trework\tescaped\tstart_to_merge_min' \
  $'opus\thigh\tcode\t-\t5\t2.25\t75%\t1.2\t0.8\t2\t2\t420' $'sonnet\tmedium\tdocs\t-\t2\t-\t-\t-\t-\t-\t-\t-')"
check "the by_risk header is not the main table's (the line after ## model_fit)" \
  "$(by_risk <<< "${out}" | head -1 | cut -f1-4)/$(sed -n 2p <<< "${out}" | cut -f1-4)" $'by_risk\teffort\tkind\trisk/model\teffort\tkind\trisk'
# The five s stories as risk: high (their first builds; s3's fable build keeps none), s1 and s2 at 50
# lines, the rest at 150: two cells under 5, so each prints its count alone, and one by_risk row of 5.
HIGH="${ROWS//$'\tcode\t\topus\t'/$'\tcode\thigh\topus\t'}"
SPLIT="${STORIES//$'s1\t150'/$'s1\t50'}"; SPLIT="${SPLIT//$'s2\t150'/$'s2\t50'}"
check "five risk: high stories over two sizes: each cell a count alone" \
  "$(ROWS="${HIGH}" STORIES="${SPLIT}" section | table | grep $'^opus\thigh\tcode')" "$(printf '%s\n' \
  $'opus\thigh\tcode\thigh\t<=100\tbin/\t2\t-\t-\t-\t-\t-\t-\t-' $'opus\thigh\tcode\thigh\t<=300\tbin/\t3\t-\t-\t-\t-\t-\t-\t-')"
check "five risk: high stories over two sizes: one by_risk row of 5, \$9.00 over 4 merged and 3 of 4 on the first attempt" \
  "$(ROWS="${HIGH}" STORIES="${SPLIT}" section | by_risk | grep $'^opus\thigh\tcode\thigh\t')" $'opus\thigh\tcode\thigh\t5\t2.25\t75%\t1.2\t0.8\t2\t2\t420'
check "a by_risk row of 4 stories (s5 left out) prints its count alone" \
  "$(ROWS="$(grep -v $'\ts5\t' <<< "${HIGH}")" STORIES="${SPLIT}" section | by_risk | grep $'^opus\thigh\tcode\thigh\t')" \
  $'opus\thigh\tcode\thigh\t4\t-\t-\t-\t-\t-\t-\t-'
# Four neighbours of the risk: high group, each differing in one field: opus xhigh (five stories at $1.00,
# each merged on its one build in 60 minutes), risk medium, kind docs and model sonnet (one story each).
rrow() { # <risk> then row's arguments: row with its risk set
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\te1\t%s\t%s\n' "$2" "$3" "$4" "$1" "${@:5}"
}
NEAR="${HIGH}
$(for i in 1 2 3 4 5; do rrow high 2026-10-02 "x${i}" code opus xhigh 1.00 1 0 "${U}/2${i}" 2026-10-02T11:00:00Z true 2026-10-02T10:00:00Z 0.00 MERGED 0; done
  rrow medium 2026-10-02 m1 code opus high 1.00 1 0 "${U}/31" 2026-10-02T11:00:00Z true 2026-10-02T10:00:00Z 0.00 MERGED 0
  rrow high 2026-10-02 k1 docs opus high 1.00 1 0 "${U}/32" 2026-10-02T11:00:00Z true 2026-10-02T10:00:00Z 0.00 MERGED 0
  rrow high 2026-10-02 n1 code sonnet high 1.00 1 0 "${U}/33" 2026-10-02T11:00:00Z true 2026-10-02T10:00:00Z 0.00 MERGED 0)"
check "groups that differ only in effort, risk, kind or model each get their own by_risk row; opus high code high keeps its figures" \
  "$(ROWS="${NEAR}" STORIES="${SPLIT}" section | by_risk | tail -n +2)" "$(printf '%s\n' \
  $'opus\thigh\tcode\thigh\t5\t2.25\t75%\t1.2\t0.8\t2\t2\t420' $'opus\thigh\tcode\tmedium\t1\t-\t-\t-\t-\t-\t-\t-' \
  $'opus\thigh\tdocs\thigh\t1\t-\t-\t-\t-\t-\t-\t-' $'opus\txhigh\tcode\thigh\t5\t1.00\t100%\t1.0\t0.0\t0\t0\t60' \
  $'sonnet\thigh\tcode\thigh\t1\t-\t-\t-\t-\t-\t-\t-' $'sonnet\tmedium\tdocs\t-\t2\t-\t-\t-\t-\t-\t-\t-')"
check "a subagent row for opus alone, as no other model's builds ran subagents: 0.50 of 2.50 is 20%" \
  "$(sed -n '/^subagents/,/^$/p' <<< "${out}")" $'subagents\teffort\tsubagent_cost_usd\tbuild_cost_usd\tsubagent_share\nopus\thigh\t0.50\t2.50\t20%'
fixes() { # <later PR's key> <its text> [its files, JSON] — 1 when rework_of counts o/r#1 as fixed by it, else 0
  (cd "${REPO}/bin/lib" && python3 -c 'import json, sys; from report import rework_of
j, t, f = sys.argv[1:]
print(int("o/r#1" in rework_of({"o/r#1": ("2026-10-01T00:00:00Z", "", None), j: ("2026-10-02T00:00:00Z", t, json.loads(f))}, [])))' "$1" "$2" "${3:-null}")
}
check "a fix, rework of or regression from phrase fixes a PR, in a clause of its own" \
  "$(fixes o/r#2 'Fix #1')$(fixes o/r#2 $'Docs\nThis is a rework of #1.')$(fixes o/r#2 "Regression from ${U}/1")$(fixes o/r#2 'Merge after #3. Fixes #1')" 1111
check "fixing, hotfix, bugfix and quickfix are fix verbs" \
  "$(fixes o/r#2 'Fixing #1')$(fixes o/r#2 'Hotfix for #1')$(fixes o/r#2 'bugfix: #1 dropped rows')$(fixes o/r#2 'Quick-fix #1')" 1111
check "a negation elsewhere in the clause, or before another reference's fix verb, leaves the fix standing" \
  "$(fixes o/r#2 'Fixes #1, which was not a regression')$(fixes o/r#2 'Fixes #1: retries did not fix the flake')$(fixes o/r#2 "Fixes #1 and doesn't fix #4")" 111
check "a negation directly before the fix verb governing a reference cancels that reference alone" \
  "$(fixes o/r#2 "Fixes #4 and doesn't fix #1")$(fixes o/r#2 'Fixes #4, not yet fixing #1')" 00
check "a PR named on a Merge after, Depends on, Stacked on or Merged origin/main line, or with no fix phrase, is not fixed" \
  "$(fixes o/r#2 "Merge after the fix in ${U}/1")$(fixes o/r#2 'Depends on the fix in #1')$(fixes o/r#2 $'Docs\n- Stacked on the fix in #1')$(fixes o/r#2 'Merged origin/main at abc, which fixed #1')$(fixes o/r#2 'Refactors #1')" 00000
check "a fix phrase in another clause, or a negated one, does not fix a PR" \
  "$(fixes o/r#2 'Fixes review findings; merge after #1')$(fixes o/r#2 'Fix the typo. Stacked on #1')$(fixes o/r#2 "Doesn't fix #1 yet")$(fixes o/r#2 'Not fixing #1 here')" 0000
check "a negation that describes the bug leaves the fix standing" \
  "$(fixes o/r#2 'Fixes #1, where the guard was not applied')$(fixes o/r#2 "Fixes #1: the parser didn't escape quotes")" 11
check "a release PR, which changes only plugin.json, fixes nothing" \
  "$(fixes o/r#2 'Release: fixes #1' '[".claude-plugin/plugin.json"]')$(fixes o/r#2 'Fixes #1' '["bin/x.sh"]')" 01
check "a bare #N fixes a PR in its own repo alone; owner/repo#N one in another, with a left boundary" \
  "$(fixes b/two#2 'Fix #1')$(fixes b/two#2 'Fix o/r#1')$(fixes b/two#2 'Fix foo/r#1')" 010
check "a mergedAt that does not parse, or has no offset, is skipped and counted on stderr" \
  "$(cd "${REPO}/bin/lib" && python3 -c 'from report import rework_of
print(rework_of({"o/r#1": ("garbage", "", None), "o/r#2": ("2026-10-02T00:00:00", "Fix #1", None), "o/r#3": ("2026-10-03T00:00:00Z", "Fix #2", None)}, []))' 2>&1)" \
  $'rework: skipped 2 merged PRs whose mergedAt does not parse, as o/r#1\nset()'
# A story merged on a PR no build of it named (story_merged true, no merged_at) adds no wait and no
# crash; s4's build with no cost is named, not counted as free: $8.00 over 4.
ROWS="${ROWS//$'\t2026-10-10T10:00:00Z\ttrue'/$'\t\ttrue'}"
ROWS="${ROWS//$'\thigh\t1.00\t1\t1\t'/$'\thigh\t\t1\t1\t'}"
check "a merged story with no merged_at adds no wait; a build with no cost is named" \
  "$(section | table | grep $'^opus\thigh\tcode' | cut -f7,8,14)" $'5\t2.00 (1 not in the logs)\t540'

# Through swarm.sh flow: gone was planned at 400 lines in skills/ and templates/ (a tie, so skills/, the
# first named: any folder is an area), then deleted by a commit.
P="${dir}/repo"
mkdir -p "${P}/.swarm" "${P}/docs/stories"
git -C "${P}" init -q
printf -- '---\nkind: code\nstatus: ready\nestimate_lines: 400\ntouches: [skills/x/SKILL.md, templates/a.md]\n---\n' > "${P}/docs/stories/gone.md"
git -C "${P}" add -A && git -C "${P}" -c user.name=t -c user.email=t@t commit -qm add
git -C "${P}" rm -q docs/stories/gone.md && git -C "${P}" -c user.name=t -c user.email=t@t commit -qm merged
mkdir -p "${P}/docs/stories"   # the board is still there, without the story
printf '%s\n' $'2026-10-02\tcode\tgone\tclaude\topus\thigh\t-' > "${P}/.swarm/agents.tsv"
out="$(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" \
  bash "${REPO}/bin/swarm.sh" flow 2>/dev/null | awk '/^## / { f = $0 == "## model_fit"; next } f')" || true
check "a story deleted in a git commit still lands in its class" \
  "$(sed -n 2p <<< "${out}")" $'opus\thigh\tcode\t-\t>300\tskills/\t1\t-\t-\t-\t-\t-\t-\t-'

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
