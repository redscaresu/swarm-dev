#!/usr/bin/env bash
# flow_totals_test.sh — flow's epic_totals section over a two-epic fixture of outcomes rows. e1 has a
# ($1.50, 10 min to its PR #1, 30 to merge, 1 main merge), a's retry on the same PR #1 ($0.50, 5 min:
# #1 counts once) and b ($2.00, 20 min, PR #2 60 to merge, 0 main merges): $4.00, 35, 90, 1 of 2 PRs, 50%.
# e2 has c (#3, 2 main merges) and d (#4, main_merges empty: gh could not read it, so it is not in
# the share) and e, dated before --since. The window: 2 of 3 readable PRs, 67%. f has no epic.
set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/lib"
U=https://github.com/o/r/pull
row() { # <date> <slug> <epic> <cost> <pr> <start_to_pr> <pr_to_merge> <main_merges>
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}
ROWS="$(printf 'date\tslug\tepic\tcost_usd\tpr\tstart_to_pr_min\tpr_to_merge_min\tmain_merges\n'
  row 2026-10-02 a e1 1.50 "${U}/1" 10 30 1
  row 2026-10-02 a e1 0.50 "${U}/1" 5 30 1
  row 2026-10-02 b e1 2.00 "${U}/2" 20 60 0
  row 2026-10-03 c e2 3.25 "${U}/3" 40 15 2
  row 2026-10-03 d e2 1.00 "${U}/4" "" "" ""
  row 2026-09-30 e e2 9.00 "${U}/5" 99 99 0
  row 2026-10-03 f "" 0.75 "" "" "" "")"
flow() { # <since> <epic> — the epic_totals section alone, as flow runs it
  SWARM_ROWS="${ROWS}" python3 "${LIB}/flow_report.py" "$1" 9999-12-30 "$2" x x x x x x x "" x epic_totals
}
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
H=$'## epic_totals\nepic\tbuilds\tcost_usd\tstart_to_pr_min\tpr_to_merge_min\tprs\tmain_merged\tmain_merged_share'
B=$'\nmain_merged_share against leaner-faster-swarm\'s baseline: 55% of story PRs needed main merged in.'
check "each epic's cost and minutes, its merged-in-main share and the window's, beside the 55% baseline" \
  "$(flow 2026-10-01 "")" "${H}"$'
e1\t3\t4.00\t35\t90\t2\t1\t50%
e2\t2\t4.25\t40\t15\t1\t1\t100%
all\t6\t9.00\t75\t105\t3\t2\t67%\n'"${B}"
check "--epic prints that epic's row alone" "$(flow 2026-10-01 e1)" "${H}"$'\ne1\t3\t4.00\t35\t90\t2\t1\t50%\n'"${B}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
