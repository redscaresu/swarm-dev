#!/usr/bin/env bash
# flow_totals_test.sh — flow's epic_totals section over a two-epic fixture of outcomes rows. e1 has a
# ($1.50, 10 min to its PR #1, 30 to merge, 1 main merge), a's retry on the same PR #1 ($0.50; no
# start_to_pr_min, as it started after #1 was created; #1 counts once), b ($2.00, 20 min, PR #2 60 to merge, 0 main merges) and g, whose PR #6 is still open
# with 0 main merges ($0.25, 8 min), and h, with no cost, PR or minutes (no session log): $4.25 with 1
# not in the logs, 38 (empty minutes are skipped with no note), 90, and 1 of 2 merged PRs, 50%, as #6 is left out. e2 has c (#3, 2 main
# merges) and d (#4, minutes and main_merges empty: gh could not read it, so it is not in the share)
# and e, dated before --since. The window: 2 of 3 merged, readable PRs, 67%. f has no epic.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

iso="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${iso}"' EXIT
export CLAUDE_CONFIG_DIR="${iso}/claude-config"   # under its own root, so parallel runs share no ~/.claude

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/lib"
U=https://github.com/o/r/pull
M=2026-10-04T12:00:00Z
row() { # <date> <slug> <epic> <cost> <pr> <pr_state> <merged_at> <start_to_pr> <pr_to_merge> <main_merges>
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}
ROWS="$(printf 'date\tslug\tepic\tcost_usd\tpr\tpr_state\tmerged_at\tstart_to_pr_min\tpr_to_merge_min\tmain_merges\n'
  row 2026-10-02 a e1 1.50 "${U}/1" MERGED "${M}" 10 30 1
  row 2026-10-02 a e1 0.50 "${U}/1" MERGED "${M}" "" 30 1
  row 2026-10-02 b e1 2.00 "${U}/2" MERGED "${M}" 20 60 0
  row 2026-10-03 g e1 0.25 "${U}/6" OPEN "" 8 "" 0
  row 2026-10-03 h e1 "" "" "" "" "" "" ""
  row 2026-10-03 c e2 3.25 "${U}/3" MERGED "${M}" 40 15 2
  row 2026-10-03 d e2 1.00 "${U}/4" MERGED "${M}" "" "" ""
  row 2026-09-30 e e2 9.00 "${U}/5" MERGED "${M}" 99 99 0
  row 2026-10-03 f "" 0.75 "" "" "" "" "" "")"
flow() { # <since> <epic> — the epic_totals section alone, as flow runs it
  SWARM_ROWS="${ROWS}" python3 "${LIB}/flow_report.py" "$1" 9999-12-30 "$2" x x x x x x x "" x epic_totals
}
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
H=$'## epic_totals\nepic\tbuilds\tcost_usd\tstart_to_pr_min\tpr_to_merge_min\tmerged_prs\tmain_merged\tmain_merged_share'
B=$'\nmain_merged_share against leaner-faster-swarm\'s baseline: 55% of story PRs needed main merged in.'
check "each epic's cost and minutes, its merged PRs' merged-in-main share and the window's, beside the 55% baseline" \
  "$(flow 2026-10-01 "")" "${H}"$'
e1\t5\t4.25 (1 not in the logs)\t38\t90\t2\t1\t50%
e2\t2\t4.25\t40\t15\t1\t1\t100%
all\t8\t9.25 (1 not in the logs)\t78\t105\t3\t2\t67%\n'"${B}"
check "cost_usd says how many builds have no cost; the minutes skip empty cells with no note" \
  "$(flow 2026-10-01 "" | awk -F'\t' '$1 == "e1" || $1 == "all" { print $1, $3, $4, $5 }')" \
  "$(printf '%s\n' "e1 4.25 (1 not in the logs) 38 90" \
    "all 9.25 (1 not in the logs) 78 105")"
check "--epic prints that epic's row alone" "$(flow 2026-10-01 e1)" "${H}"$'\ne1\t5\t4.25 (1 not in the logs)\t38\t90\t2\t1\t50%\n'"${B}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
