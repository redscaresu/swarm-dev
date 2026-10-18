#!/usr/bin/env bash
# time_in_state_test.sh — `swarm.sh outcomes` splits a build's start-to-merge minutes into building,
# CI running, review wait, fixing and merge wait, and flow's time_in_state section sums them per epic,
# largest first. The fixture story tis (epic e1) starts at 10:50 and opens PR #1 at 11:00; CI runs from
# 11:00 to 11:20 while its review agent has started (11:05), a rerun from 11:25 to 11:35 runs into the
# findings at 11:30, the fix's push starts CI from 11:45 to 12:00, the review hands it to the merger at
# 12:10, a rerun runs from 12:15 to 12:20, and it merges at 12:30. By precedence (fixing > CI > review
# wait > merge wait > building): building 10, CI 20 + 5 + 15 + 5 = 45, review wait 5 + 10 = 15, fixing
# 11:30 to 11:45 = 15, merge wait 20 - 5 = 15, 100 in all. A retry build on the same PR starts
# at 11:35, takes the 12:10 review, and splits its own 55 minutes with the first build's tell; flow
# counts the PR once, by the first build. The retry's agents.tsv day is 10-02, so --since 2026-10-02
# leaves the first build out of outcomes, but not its tell.
set -euo pipefail
export TZ=UTC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; PR=https://github.com/o/r/pull/1; D=2026-10-01T
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${dir}/projects/p" "${dir}/bin"
git -C "${P}" init -q
printf -- '---\nkind: code\nepic: e1\nstatus: review\n---\n' > "${P}/docs/stories/tis.md"
session() { # <id> <HH:MM start> — a session log in the tis worktree that names PR #1
  printf '{"type":"user","cwd":"%s/repo-wt/tis","timestamp":"%s%s:00Z"}\n' "${dir}" "${D}" "$2"
  printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"%s\\n"}]}}\n' "${PR}"
}
session s1 10:50 > "${dir}/projects/p/s1.jsonl"
session s2 11:35 > "${dir}/projects/p/s2.jsonl"
printf '%s\n' $'2026-10-01\tcode\ttis\tclaude\topus\txhigh\ts1' $'2026-10-02\tcode\ttis\tclaude\topus\txhigh\ts2' > "${P}/.swarm/agents.tsv"
# A refused tell never reached the builder, so it starts no fixing.
printf '%s\n' \
  "${D}11:05:00Z"$'\treview-agent\ttis\tw:1\tok' \
  "${D}11:30:00Z"$'\ttell:findings\ttis\tw:1\tok' \
  "${D}11:50:00Z"$'\ttell:findings\ttis\tw:1\ttis is still working' \
  "${D}12:10:00Z"$'\treview\ttis\tw:1\tok' \
  "${D}12:30:00Z"$'\tmerge\ttis\tw:1\tok' > "${P}/.swarm/events.tsv"
CHECKS="${D}11:00:00Z/${D}11:20:00Z;${D}11:25:00Z/${D}11:35:00Z;${D}11:45:00Z/${D}12:00:00Z;${D}12:15:00Z/${D}12:20:00Z"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\n[ "$1 $2" = "pr list" ] || exit 1\nprintf "%s\\tMERGED\\t%s\\t%s\\t0\\t%s\\n"\n' \
  "${PR}" "${D}12:30:00Z" "${D}11:00:00Z" "${CHECKS}" > "${dir}/bin/gh"
chmod +x "${dir}/bin/gh"

outcomes() { # [args] — the rows, with the gh stub first on PATH
  (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" \
    PATH="${dir}/bin:${PATH}" bash "${ROOT}/bin/swarm.sh" outcomes "$@" | sed '/^$/,$d')
}
out="$(outcomes)"
# started, then each phase column and their sum, from the report's own header.
cols() { awk -F'\t' -v OFS='\t' 'NR == 1 { for (i = 1; i <= NF; i++) at[$i] = i; next }
  { b = $at["building_min"]; c = $at["ci_min"]; r = $at["review_wait_min"]; f = $at["fixing_min"]; m = $at["merge_wait_min"]
    print $at["started"], b, c, r, f, m, b + c + r + f + m }' <<< "${out}"; }

fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
check "the five phases are the last columns of outcomes" "$(head -1 <<< "${out}" | cut -f43-)" \
  $'building_min\tci_min\treview_wait_min\tfixing_min\tmerge_wait_min'
# The retry: fixing 11:35 to 11:45, CI 11:45 to 12:00 and 12:15 to 12:20, review wait 12:00 to 12:10,
# merge wait 12:10 to 12:15 and 12:20 to 12:30; nothing is building.
check "each build's minutes split by precedence, summing to its start-to-merge minutes" "$(cols)" "$(printf '%s\n' \
  "${D}10:50:00Z"$'\t10\t45\t15\t15\t15\t100' \
  "${D}11:35:00Z"$'\t0\t20\t10\t10\t15\t55')"
check "--since keeps the tell of a build before it in the retry's fixing" "$(out="$(outcomes --since 2026-10-02)" cols)" \
  "${D}11:35:00Z"$'\t0\t20\t10\t10\t15\t55'

flow() { # [epic] — the time_in_state section alone, as flow runs it, over the outcomes rows
  SWARM_ROWS="${out}" python3 "${ROOT}/bin/lib/flow_report.py" 0000-00-00 9999-12-30 "${1:-}" x x x x x x x "" x time_in_state
}
check "flow's epic line counts the PR once and lists the phases largest first, a tie in column order" "$(flow)" "$(printf '%s\n' \
  "## time_in_state" $'epic\tprs\tstart_to_merge_min\tlargest_first' \
  $'e1\t1\t100\tci:45 review_wait:15 fixing:15 merge_wait:15 building:10' \
  $'all\t1\t100\tci:45 review_wait:15 fixing:15 merge_wait:15 building:10')"
check "--epic prints that epic's line alone" "$(flow e1 | tail -1)" $'e1\t1\t100\tci:45 review_wait:15 fixing:15 merge_wait:15 building:10'

if [[ "${fails}" -eq 0 ]]; then echo "all passed"; else echo "${fails} failed"; exit 1; fi
