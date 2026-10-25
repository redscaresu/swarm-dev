#!/usr/bin/env bash
# prediction_scores_test.sh — flow's predictions section over `swarm.sh dataset`'s output on
# dataset_test.sh's fixture (its setup, every line before `fails=0`, sourced), plus one line kept from
# a last run, planned by sonnet. The fixture's six stories, all planned by opus:
#   easy-easy  easy, was easy         est 30,  diff 10   (off by 20)
#   easy-hard  easy, was not          est 40,  diff 120  (80)
#   escalated  not easy, was not      est 200, diff 30   (170)
#   rebased    easy, was easy         est 20,  diff 10   (10)
#   retried    easy, was not          est 10,  diff 7    (3)
#   early      easy, was_easy null    est 5,   diff null (in neither score)
#   by-sonnet  not easy, was easy     est 50,  diff 80   (30), merged 2026-08-03
# So opus: precision 2 of 4, recall 2 of 2, errors 3 10 20 80 170 (median 20, mean 56.6); with
# --since 2026-09-03, easy-easy and by-sonnet drop out. With no dataset file, the hint prints.
set -euo pipefail
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
grep -qx 'fails=0' "${TESTS}/dataset_test.sh" || { echo "FAIL dataset_test.sh has no fails=0 line to end its fixture at"; exit 1; }
root="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${root}"' EXIT
export CLAUDE_CONFIG_DIR="${root}/claude-config" TMPDIR="${root}"   # the fixture's own mktemp lands under root
# dataset_test.sh's setup: dir, P, SWARM, the gh stub in ${dir}/bin. eval, as bash 3.2's source reads
# nothing from a <(...). Its trap removes dir alone, so root's goes back on after it.
eval "$(sed '/^fails=0$/q' "${TESTS}/dataset_test.sh")"
trap 'rm -rf "${root}"' EXIT
printf '%s\n' '{"slug": "by-sonnet", "inputs": {"easy": false, "estimate_lines": 50, "planner_model": "sonnet"}, "results": {"diff_lines": 80, "merged_at": "2026-08-03T00:00:00Z"}, "was_easy": true}' \
  >> "${P}/.swarm/dataset.jsonl"

fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
# shellcheck disable=SC2154 # dir is the fixture's
swarm() { # <command> [args...] — swarm.sh in the fixture's project, with its gh stub
  (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" SWARM_FLOW_SECTIONS=predictions \
    PATH="${dir}/bin:${PATH}" bash "${SWARM}" "$@" 2>/dev/null)
}
check "dataset writes the fixture's six stories and keeps the sonnet line" "$(swarm dataset | tail -1)" \
  "wrote 9 stories to $(cd "${P}" && pwd -P)/.swarm/dataset.jsonl (3 kept from the last run)"
H=$'## predictions\nplanner_model\tstories\teasy_precision\teasy_recall\testimated\test_err_median\test_err_mean'
check "per planner model, then all: easy's precision and recall against was_easy, and the size-estimate error" "$(swarm flow)" \
  "${H}"$'\nopus\t6\t2/4 50%\t2/2 100%\t5\t20\t57\nsonnet\t1\t-\t0/1 0%\t1\t30\t30\nall\t7\t2/4 50%\t2/3 67%\t6\t25\t52'
check "--since leaves out the stories merged before it" "$(swarm flow --since 2026-09-03)" \
  "${H}"$'\nopus\t5\t1/3 33%\t1/1 100%\t4\t45\t66\nall\t5\t1/3 33%\t1/1 100%\t4\t45\t66'
rm "${P}/.swarm/dataset.jsonl"
check "with no dataset file, a line says to run swarm.sh dataset" "$(swarm flow)" \
  $'## predictions\nno .swarm/dataset.jsonl: run swarm.sh dataset to score the planner\'s easy labels and size estimates'

if [[ ${fails} -eq 0 ]]; then echo "all prediction score checks passed"; else echo "${fails} prediction score check(s) failed"; exit 1; fi
