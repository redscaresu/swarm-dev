#!/usr/bin/env bash
# ci_health_test.sh — `swarm.sh flow`'s ci_health section against a gh stub. PR 1 (a) has a flaky
# head: CI red 10:00-10:04, then green 10:10-10:16 on a1 (16 min). PR 2 (b) is red on b1 (5 min)
# and fixed by a new head b2 (6 min), which is no flake. PR 3 (c) is green on c1 (8 min), and a run
# of an old head not among its commits is left out. So 3 PRs, 4 heads, a median of 7.0 minutes, 2 red
# runs over 3 PRs and 1 flake. With RERUN=1, a1's two runs are one run rerun to green (attempt 2):
# still 1 red and 1 flake. A gh whose run list fails prints the failure line and no numbers.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; G="${dir}/gh"; U=https://github.com/o/r/pull
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${G}" "${dir}/bin"
git -C "${P}" init -q
for s in a b c; do printf -- '---\nkind: code\nstatus: ready\n---\n' > "${P}/docs/stories/${s}.md"; done
printf '%s\n' $'2026-10-01\tcode\ta\tclaude\topus\thigh\t-' $'2026-10-01\tcode\tb\tclaude\topus\thigh\t-' \
  $'2026-10-01\tcode\tc\tclaude\topus\thigh\t-' > "${P}/.swarm/agents.tsv"
run() { # <head> <workflow> <conclusion> <attempt> <created HH:MM> <updated HH:MM>
  printf '{"headSha":"%s","workflowName":"%s","status":"completed","conclusion":"%s","attempt":%s,"createdAt":"2026-10-01T%s:00Z","updatedAt":"2026-10-01T%s:00Z"}' "$@"
}
echo '{"headRefName":"story/a","commits":[{"oid":"a1"}]}' > "${G}/view-1"
echo '{"headRefName":"story/b","commits":[{"oid":"b1"},{"oid":"b2"}]}' > "${G}/view-2"
echo '{"headRefName":"story/c","commits":[{"oid":"c1"}]}' > "${G}/view-3"
echo "[$(run a1 CI success 1 10:10 10:16),$(run a1 CI failure 1 10:00 10:04)]" > "${G}/runs-a"
echo "[$(run a1 CI success 2 10:00 10:16)]" > "${G}/rerun-a"
echo "[$(run b2 CI success 1 10:20 10:26),$(run b1 CI failure 1 10:00 10:05)]" > "${G}/runs-b"
echo "[$(run c1 CI success 1 10:00 10:08),$(run c0 CI failure 1 09:00 09:30)]" > "${G}/runs-c"
# gh: pr list answers each story's PR, pr view its createdAt or its commits, run list its branch's runs.
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\nG=%s\ncase "$*" in\n"pr list --head story/"*) printf "%s/%%s\\tOPEN\\t\\t2026-10-01T10:00:00Z\\t0\\n" "$(echo "${4##*/}" | tr abc 123)" ;;\n"pr view %s/"*" --json createdAt"*) echo 2026-10-01T10:00:00Z ;;\n"pr view %s/"*) cat "$G/view-${3##*/}" ;;\n"run list -R o/r --branch story/a "*) [ -n "${RERUN:-}" ] && cat "$G/rerun-a" || cat "$G/runs-a" ;;\n"run list -R o/r --branch story/"*) [ -z "${FAIL:-}" ] || exit 1; cat "$G/runs-${6##*/}" ;;\nesac\nexit 0\n' \
  "${G}" "${U}" "${U}" "${U}" > "${dir}/bin/gh"
chmod +x "${dir}/bin/gh"

flow() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT "$@" PATH="${dir}/bin:${PATH}" bash "${SWARM}" flow); }
ci() { awk '/^## / { f = $0 == "## ci_health"; next } f && NF'; } # flow's ci_health section
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
H=$'prs\theads\tci_min_median\tred_runs_per_pr\tflakes'
check "a flaky head, a red head fixed by a new head and a green PR: median 7.0 min, 0.67 red runs per PR, 1 flake" \
  "$(flow RERUN= | ci)" "${H}"$'\n3\t4\t7.0\t0.67\t1'
check "a run rerun to green counts its earlier attempt red and is a flake" "$(flow RERUN=1 | ci)" "${H}"$'\n3\t4\t7.0\t0.67\t1'
check "a failing gh prints the failure line and no numbers" "$(flow FAIL=1 | ci)" "ci health: gh failed"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
