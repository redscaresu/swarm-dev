#!/usr/bin/env bash
# ci_health_test.sh — `swarm.sh flow`'s ci_health section against a gh stub. a to d were built on
# 2020-01-01, so the checks name that window. PR 1 (a) has a flaky head: CI red 10:00-10:04, then
# green 10:10-10:16 on a1 (16 min). PR 2 (b) is red on b1 (5 min), where lint could not start (a
# startup_failure, also red), and fixed by a new head b2 (10:19-10:26, 7 min), which is no flake;
# on b2 CI is red on push and green on pull_request, which is no flake either, as the two events
# differ. PR 3 (c) is green on c1 (8 min): its zizmor run was cancelled and rerun to green, which is
# neither red nor a flake, a run whose createdAt does not parse adds no minutes, and a run of an old
# head not among its commits is left out. d's PR is on GitHub Enterprise, so it is left out. So 3
# PRs, 4 heads, a median of 7.5 minutes, 4 red runs over 3 PRs and 1 flake. With RERUN=1, a1's two
# runs are one run whose first attempt failed and whose rerun went green: the same numbers. A gh
# whose run list fails, or whose pr view takes over 10 seconds, prints the failure line and no
# numbers. With no --since, only e, built today, is in the window, and the section says so.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
P="${dir}/repo"; G="${dir}/gh"; U=https://github.com/o/r/pull
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${G}" "${dir}/bin"
git -C "${P}" init -q
today="$(python3 -c 'import datetime; print(datetime.date.today())')"
start="$(python3 -c 'import datetime; print(datetime.date.today() - datetime.timedelta(days=30))')"
for s in a b c d e; do printf -- '---\nkind: code\nstatus: ready\n---\n' > "${P}/docs/stories/${s}.md"; done
for s in a b c d; do printf '2020-01-01\tcode\t%s\tclaude\topus\thigh\t-\n' "${s}"; done > "${P}/.swarm/agents.tsv"
printf '%s\tcode\te\tclaude\topus\thigh\t-\n' "${today}" >> "${P}/.swarm/agents.tsv"
run() { # <id> <head> <workflow> <event> <conclusion> <attempt> <created HH:MM> <updated HH:MM>
  printf '{"databaseId":%s,"headSha":"%s","workflowName":"%s","event":"%s","status":"completed","conclusion":"%s","attempt":%s,"createdAt":"2026-10-01T%s:00Z","updatedAt":"2026-10-01T%s:00Z"}' "$@"
}
echo '{"headRefName":"story/a","commits":[{"oid":"a1"}]}' > "${G}/view-1"
echo '{"headRefName":"story/b","commits":[{"oid":"b1"},{"oid":"b2"}]}' > "${G}/view-2"
echo '{"headRefName":"story/c","commits":[{"oid":"c1"}]}' > "${G}/view-3"
echo '{"headRefName":"story/e","commits":[{"oid":"e1"}]}' > "${G}/view-5"
echo "[$(run 11 a1 CI pull_request success 1 10:10 10:16),$(run 10 a1 CI pull_request failure 1 10:00 10:04)]" > "${G}/runs-a"
echo "[$(run 12 a1 CI pull_request success 2 10:00 10:16)]" > "${G}/rerun-a"
echo '{"conclusion":"failure"}' > "${G}/attempt-12-1"
echo "[$(run 21 b2 CI pull_request success 1 10:20 10:26),$(run 22 b2 CI push failure 1 10:19 10:22),
  $(run 20 b1 CI pull_request failure 1 10:00 10:05),$(run 23 b1 lint pull_request startup_failure 1 10:00 10:01)]" > "${G}/runs-b"
echo "[$(run 31 c1 CI pull_request success 1 10:00 10:08),$(run 32 c1 zizmor pull_request success 2 10:01 10:07),
  $(run 33 c1 CI pull_request success 1 xx 10:40),$(run 30 c0 CI pull_request failure 1 09:00 09:30)]" > "${G}/runs-c"
echo '{"conclusion":"cancelled"}' > "${G}/attempt-32-1"
echo "[$(run 51 e1 CI pull_request success 1 11:00 11:03)]" > "${G}/runs-e"
# gh: pr list answers each story's PR (d's on Enterprise), pr view its createdAt or its commits, run
# list its branch's runs, and api a run's earlier attempt.
{ echo '#!/bin/sh'; echo "G=${G} U=${U}"; cat <<'EOF'; } > "${dir}/bin/gh"
case "$*" in
"pr list --head story/d"*) printf 'https://ghe.example.com/o/r/pull/9\tOPEN\t\t2026-10-01T10:00:00Z\t0\n' ;;
"pr list --head story/"*) printf '%s/%s\tOPEN\t\t2026-10-01T10:00:00Z\t0\n' "$U" "$(echo "${4##*/}" | tr abce 1235)" ;;
"pr view $U/"*" --json createdAt"*) echo 2026-10-01T10:00:00Z ;;
"pr view $U/"*) [ -z "${SLOW:-}" ] || sleep 12; cat "$G/view-${3##*/}" ;;
"run list -R o/r --branch story/a "*) if [ -n "${RERUN:-}" ]; then cat "$G/rerun-a"; else cat "$G/runs-a"; fi ;;
"run list -R o/r --branch story/"*) [ -z "${FAIL:-}" ] || exit 1; cat "$G/runs-${6##*/}" ;;
"api repos/o/r/actions/runs/"*) cat "$G/attempt-$(echo "$2" | cut -d/ -f6,8 | tr / -)" ;;
esac
EOF
chmod +x "${dir}/bin/gh"

flow() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${dir}/bin:${PATH}" bash "${SWARM}" flow "$@"); }
W=(--since 2020-01-01 --until 2020-01-01)
ci() { awk '/^## / { f = $0 == "## ci_health"; next } f && NF'; } # flow's ci_health section
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
H=$'prs\theads\tci_min_median\tred_runs_per_pr\tflakes'
check "a flaky head, a red head (one run could not start) fixed by a new head and a green PR: median 7.5 min, 1.33 red runs per PR, 1 flake" \
  "$(flow "${W[@]}" | ci)" "${H}"$'\n3\t4\t7.5\t1.33\t1'
check "a run whose failed first attempt was rerun to green is red once and a flake" "$(RERUN=1 flow "${W[@]}" | ci)" "${H}"$'\n3\t4\t7.5\t1.33\t1'
check "a failing gh prints the failure line and no numbers" "$(FAIL=1 flow "${W[@]}" | ci)" "ci health: gh failed"
check "a gh call over 10 seconds is a failure" "$(SLOW=1 flow "${W[@]}" | ci)" "ci health: gh failed"
check "with no --since, the PRs of the last 30 days, and a line that says so" "$(flow | ci)" \
  "PRs from the last 30 days, ${start} on; --since sets the start"$'\n'"${H}"$'\n1\t1\t3.0\t0.00\t0'

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
