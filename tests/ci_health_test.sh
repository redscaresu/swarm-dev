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
# numbers; ci time keeps the PRs it could read and says how many it could not. With no --since, e (built today), f (6 days ago, the first day of the last 7) and g (9
# days ago) are in the window, and the section says so.
# Then ci time, per repo: a PR's newest head's longest run, from its last attempt's start, and that
# run's slowest job. a: 6 min, test 5; b: b2's 6 min pull_request run (not the 3 min push), test 4; c:
# 8 min, lint 7 (its run with no parseable start counts for nothing). So 6.0 min, and lint slowest at
# 7.0 (test's own median is 4.5). With FAILB=1 b's runs cannot be read: a and c alone, 7.0 min, and a
# line that says 1 PR was left out. e: 4 min, test 2; f: 19 min on f1, test 16 (on its jobs listing's
# second page; its older head f0's 40 min run is not its newest head's); g: 13 min, test 10 (a job
# whose name carries a bell and a line break). Over the last 7 days (--since 6 days ago) that is e
# and f, 11.5 min and test 9.0, against g's 13.0 and 10.0 the week before: -1.5. dash's ci line is
# that row, its change from the minutes it shows: ci 12m (slowest: test 9m) ▼1m vs last week. A dash whose refresh fails writes no line and
# tries again after 10 minutes, not 6 hours.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
P="${dir}/repo"; G="${dir}/gh"; U=https://github.com/o/r/pull
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${G}" "${dir}/bin" "${dir}/projects" "${dir}/tmp"
git -C "${P}" init -q
# <n> days ago: its local day, or with t its UTC time (a PR's createdAt).
ago() { python3 -c 'import datetime as d, sys; t = d.datetime.now(d.timezone.utc) - d.timedelta(days=int(sys.argv[1]))
print(t.strftime("%Y-%m-%dT%H:%M:%SZ") if sys.argv[2:] else t.astimezone().date())' "$@"; }
today="$(ago 0)"; start="$(ago 30)"; week="$(ago 6)"
for s in a b c d e f g; do printf -- '---\nkind: code\nstatus: ready\n---\n' > "${P}/docs/stories/${s}.md"; done
for s in a b c d; do printf '2020-01-01\tcode\t%s\tclaude\topus\thigh\t-\n' "${s}"; done > "${P}/.swarm/agents.tsv"
printf '%s\tcode\t%s\tclaude\topus\thigh\t-\n' "${today}" e "$(ago 6)" f "$(ago 9)" g >> "${P}/.swarm/agents.tsv"
run() { # <id> <head> <workflow> <event> <conclusion> <attempt> <created HH:MM> <updated HH:MM> [<started HH:MM>]
  printf '{"databaseId":%s,"headSha":"%s","workflowName":"%s","event":"%s","status":"completed","conclusion":"%s","attempt":%s,"createdAt":"2026-10-01T%s:00Z","startedAt":"2026-10-01T%s:00Z","updatedAt":"2026-10-01T%s:00Z"}' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "${9:-$7}" "$8"
}
jobs() { # <run id> [<name> <started HH:MM> <completed HH:MM> | /]... — that run's jobs listing, its
  # pages slurped into one array; / starts the next page
  local id="$1" sep="" out=""; shift
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == / ]]; then out+="]},{\"jobs\":["; sep=""; shift; continue; fi
    out+="${sep}{\"name\":\"$1\",\"started_at\":\"2026-10-01T$2:00Z\",\"completed_at\":\"2026-10-01T$3:00Z\"}"; sep=,; shift 3
  done
  echo "[{\"jobs\":[${out}]}]" > "${G}/jobs-${id}"
}
echo '{"headRefName":"story/a","commits":[{"oid":"a1"}]}' > "${G}/view-1"
echo '{"headRefName":"story/b","commits":[{"oid":"b1"},{"oid":"b2"}]}' > "${G}/view-2"
echo '{"headRefName":"story/c","commits":[{"oid":"c1"}]}' > "${G}/view-3"
echo '{"headRefName":"story/e","commits":[{"oid":"e1"}]}' > "${G}/view-5"
echo '{"headRefName":"story/f","commits":[{"oid":"f0"},{"oid":"f1"}]}' > "${G}/view-6"
echo '{"headRefName":"story/g","commits":[{"oid":"g1"}]}' > "${G}/view-7"
echo "[$(run 11 a1 CI pull_request success 1 10:10 10:16),$(run 10 a1 CI pull_request failure 1 10:00 10:04)]" > "${G}/runs-a"
echo "[$(run 12 a1 CI pull_request success 2 10:00 10:16 10:10)]" > "${G}/rerun-a"
echo '{"conclusion":"failure"}' > "${G}/attempt-12-1"
jobs 11 test 10:10 10:15 lint 10:10 10:11; cp "${G}/jobs-11" "${G}/jobs-12"
echo "[$(run 21 b2 CI pull_request success 1 10:20 10:26),$(run 22 b2 CI push failure 1 10:19 10:22),
  $(run 20 b1 CI pull_request failure 1 10:00 10:05),$(run 23 b1 lint pull_request startup_failure 1 10:00 10:01)]" > "${G}/runs-b"
echo "[$(run 31 c1 CI pull_request success 1 10:00 10:08),$(run 32 c1 zizmor pull_request success 2 10:01 10:07),
  $(run 33 c1 CI pull_request success 1 xx 10:40),$(run 30 c0 CI pull_request failure 1 09:00 09:30)]" > "${G}/runs-c"
echo '{"conclusion":"cancelled"}' > "${G}/attempt-32-1"
jobs 21 test 10:21 10:25 build 10:20 10:22
jobs 31 lint 10:00 10:07 test 10:00 10:03
echo "[$(run 51 e1 CI pull_request success 1 11:00 11:04)]" > "${G}/runs-e"
jobs 51 test 11:00 11:02 lint 11:00 11:01
echo "[$(run 61 f1 CI pull_request success 1 10:00 10:19),$(run 62 f1 zizmor pull_request success 1 10:00 10:01),
  $(run 63 f0 CI pull_request success 1 09:00 09:40)]" > "${G}/runs-f"
jobs 61 lint 10:01 10:05 / test 10:02 10:18
echo "[$(run 71 g1 CI pull_request success 1 10:00 10:13)]" > "${G}/runs-g"
jobs 71 'te\u0007s\nt' 10:01 10:11 build 10:00 10:03
# gh: pr list answers each story's PR (d's on Enterprise), pr view its createdAt or its commits, run
# list its branch's runs, and api a run's jobs or earlier attempt.
{ echo '#!/bin/sh'; echo "G=${G} U=${U}"; cat <<'EOF'; } > "${dir}/bin/gh"
case "$*" in
"pr list --head story/d"*) printf 'https://ghe.example.com/o/r/pull/9\tOPEN\t\t2026-10-01T10:00:00Z\t0\n' ;;
"pr list --head story/"*) printf '%s/%s\tOPEN\t\t2026-10-01T10:00:00Z\t0\n' "$U" "$(echo "${4##*/}" | tr abcefg 123567)" ;;
"pr view $U/"*" --json createdAt"*) echo 2026-10-01T10:00:00Z ;;
"pr view $U/"*) [ -z "${SLOW:-}" ] || sleep 12; cat "$G/view-${3##*/}" ;;
"run list -R o/r --branch story/a "*) if [ -n "${RERUN:-}" ]; then cat "$G/rerun-a"; else cat "$G/runs-a"; fi ;;
"run list -R o/r --branch story/b "*) [ -z "${FAIL:-}${FAILB:-}" ] || exit 1; cat "$G/runs-b" ;;
"run list -R o/r --branch story/"*) [ -z "${FAIL:-}" ] || exit 1; cat "$G/runs-${6##*/}" ;;
"api --paginate --slurp repos/o/r/actions/runs/"*"/jobs?per_page=100") cat "$G/jobs-$(echo "$4" | cut -d/ -f6)" ;;
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
T=$'repo\tprs\tci_min_median\tslowest_job\tslowest_job_min_median\tprev_prs\tprev_ci_min_median\tprev_slowest_job\tprev_slowest_job_min_median\tci_min_change'
check "a flaky head, a red head (one run could not start) fixed by a new head and a green PR: median 7.5 min, 1.33 red runs per PR, 1 flake; ci time 6.0 min, lint slowest at 7.0 (test's own median is 4.5), none the window before" \
  "$(flow "${W[@]}" | ci)" "${H}"$'\n3\t4\t7.5\t1.33\t1\n'"${T}"$'\no/r\t3\t6.0\tlint\t7.0\t0\t\t\t\t'
check "a run whose failed first attempt was rerun to green is red once and a flake, its ci time from the rerun's start" \
  "$(RERUN=1 flow "${W[@]}" | ci)" "${H}"$'\n3\t4\t7.5\t1.33\t1\n'"${T}"$'\no/r\t3\t6.0\tlint\t7.0\t0\t\t\t\t'
check "a failing gh prints the failure line and no numbers; ci time keeps a, whose runs it read" "$(FAIL=1 flow "${W[@]}" | ci)" \
  "ci health: gh failed"$'\n'"${T}"$'\no/r\t1\t6.0\ttest\t5.0\t0\t\t\t\t\nci time: gh could not read 2 of 3 PRs, left out'
check "a gh call over 10 seconds is a failure, and ci time has no row" "$(SLOW=1 flow "${W[@]}" | ci)" \
  "ci health: gh failed"$'\n'"${T}"$'\nci time: gh could not read 3 of 3 PRs, left out'
check "ci time keeps the PRs gh could read: a and c, and a line for b" "$(FAILB=1 flow "${W[@]}" | ci)" \
  "ci health: gh failed"$'\n'"${T}"$'\no/r\t2\t7.0\tlint\t7.0\t0\t\t\t\t\nci time: gh could not read 1 of 3 PRs, left out'
check "with no --since, the PRs of the last 30 days, and a line that says so" "$(flow | ci)" \
  "PRs from the last 30 days, ${start} on; --since sets the start"$'\n'"${H}"$'\n3\t4\t16.0\t0.00\t0\n'"${T}"$'\no/r\t3\t13.0\ttest\t10.0\t0\t\t\t\t'
now="$(flow --since "${week}" | ci)"
check "the last 7 days against the 7 before: 11.5 min, test slowest at 9.0, against 13.0 and 10.0, so -1.5" \
  "${now}" "${H}"$'\n2\t3\t19.0\t0.00\t0\n'"${T}"$'\no/r\t2\t11.5\ttest\t9.0\t1\t13.0\ttest\t10.0\t-1.5'

# dash's ci line is flow's row for the same week. A detached refresh runs flow and fills its cache,
# then the next dash (past its one-minute cache) shows it. One that fails (gh reads no PR) writes
# none, and the next dash starts another only once its marker is 10 minutes old.
git -C "${P}" remote add origin https://github.com/o/r.git && touch "${P}/docs/stories/README.md"
printf '#!/bin/sh\nexit 1\n' > "${dir}/bin/herdr"; chmod +x "${dir}/bin/herdr"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${dir}/bin/claude"
dash() { # dash's ci line, if it shows one; then its one-minute cache goes, so the next dash reads the ci cache again
  local out
  out="$(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${dir}/bin:${PATH}" TMPDIR="${dir}/tmp" CLAUDE_PROJECTS_DIR="${dir}/projects" \
    COLUMNS=200 bash "${SWARM}" dash 2>&1)" || true
  rm -f "${dir}"/tmp/swarm-dash-3-*
  grep -o "ci [0-9].*vs last week" <<< "${out}" || true
}
refreshed() { # waits up to 60 s for the detached refresh to end
  for _ in $(seq 300); do pgrep -f "dash_slow.py --ci .*${dir##*/}" > /dev/null || return 0; sleep 0.2; done
}
FAIL=1 dash > /dev/null; refreshed
check "a refresh where gh reads no PR writes no ci line" "$(dash)" ""
touch -t 202001010000 "${dir}"/tmp/swarm-dash-ci-*.run
dash > /dev/null; refreshed
want="$(awk -F'\t' '$1 == "o/r" { d = sprintf("%.0f", $3) - sprintf("%.0f", $7)
  printf "ci %.0fm (slowest: %s %.0fm) %s%dm vs last week", $3, $4, $5, (d < 0 ? "▼" : (d > 0 ? "▲" : "±")), (d < 0 ? -d : d) }' <<< "${now}")"
check "after 10 minutes another refresh runs, and dash's ci line agrees with flow's figures for the last 7 days" "$(dash)" "${want}"
check "which are this fixture's, the change from the minutes shown: ci 12m (slowest: test 9m) ▼1m vs last week" "${want}" \
  "ci 12m (slowest: test 9m) ▼1m vs last week"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
