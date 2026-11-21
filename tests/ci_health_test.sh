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
# whose run list fails, or whose PR read takes over 10 seconds, leaves those PRs out of the row and of
# ci time, which say how many, with a line for each naming the gh call and its error. A reset
# connection or a 5xx is tried three times: b's run list, failing twice with FLAKY=b, still counts,
# and with FLAKY=c, c's two failures do not stand in for b's error; any other error once. Once the
# hourly rate limit is spent (RATELIMIT=1), no more gh calls. With no --since, e
# (built today), f (6 days ago, the first day of the last 7, and 8 days ago) and g (9 days ago) are
# in the window, and the section says so.
# Then ci time, per repo: a PR's newest head's longest run, from its last attempt's start, and that
# run's slowest job, from that attempt's own jobs. a: 6 min, test 5 (with RERUN=1, attempt 2's jobs,
# not attempt 1's 20 min test, nor the 9 min build attempt 2's listing carried over from attempt 1);
# b: b2's 6 min pull_request run (not the 3 min push), test 4; c: 8 min,
# lint 7 (its run with no parseable start counts for nothing). So 6.0 min, and lint slowest at 7.0
# (test's own median is 4.5). With FAILB=1 b's runs cannot be read: a and c alone, 7.0 min, and a
# line that says 1 PR was left out. e: 4 min, test 2; f: 19 min on f1, test 16 (on its jobs
# listing's second page; its older head f0's 40 min run is not its newest head's); g: 13 min, test
# 10 (a job whose name carries a bell and a line break; its PR's URL spells the repo O/r, still o/r;
# its older head g0's 20 min run was created after g1's, and still is not its newest head's). Over the last 7 days (--since 6 days ago)
# that is e and f, 11.5 min and test 9.0, against g's 13.0 and 10.0 the week before (f, built in
# both weeks, counts in its latest alone): -1.5. SWARM_DASH_NOW pins flow's today. A gh answer of {}
# leaves that PR out, never the section.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
export SWARM_GH_CACHE=""   # each run reads gh afresh, as its stub answers change between runs (gh_cache_test.sh tests the cache)
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
P="${dir}/repo"; G="${dir}/gh"; U=https://github.com/o/r/pull
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${G}" "${dir}/bin" "${dir}/projects" "${dir}/tmp"
git -C "${P}" init -q
# Every day below is a local day, counted back from one instant (T0), as flow counts its own from its
# local today. The PRs' and runs' times are fixed UTC instants, which no
# window reads.
T0="$(date +%s)"
ago() { # <n> [<epoch>] — the local day n days before T0's, or before <epoch>'s
  python3 -c 'import datetime as d, sys; print(d.date.fromtimestamp(int(sys.argv[2])) - d.timedelta(days=int(sys.argv[1])))' "$1" "${2:-${T0}}"; }
today="$(ago 0)"; start="$(ago 30)"; week="$(ago 6)"
for s in a b c d e f g; do printf -- '---\nkind: code\nstatus: ready\n---\n' > "${P}/docs/stories/${s}.md"; done
for s in a b c d; do printf '2020-01-01\tcode\t%s\tclaude\topus\thigh\t-\n' "${s}"; done > "${P}/.swarm/agents.tsv"
printf '%s\tcode\t%s\tclaude\topus\thigh\t-\n' "${today}" e "$(ago 6)" f "$(ago 8)" f "$(ago 9)" g >> "${P}/.swarm/agents.tsv"
run() { # <id> <head> <workflow> <event> <conclusion> <attempt> <created HH:MM> <updated HH:MM> [<started HH:MM>]
  printf '{"databaseId":%s,"headSha":"%s","workflowName":"%s","event":"%s","status":"completed","conclusion":"%s","attempt":%s,"createdAt":"2026-10-01T%s:00Z","startedAt":"2026-10-01T%s:00Z","updatedAt":"2026-10-01T%s:00Z"}' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "${9:-$7}" "$8"
}
jobs() { # <run id>-<attempt> [<name>[@<run_attempt>] <started HH:MM> <completed HH:MM> | /]... — that
  # attempt's jobs listing, its pages slurped into one array; / starts the next page, and a job's
  # run_attempt is the listing's own unless @ names an earlier one (a job a rerun carried over)
  local id="$1" sep="" out="" name n; shift
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == / ]]; then out+="]},{\"jobs\":["; sep=""; shift; continue; fi
    name="${1%@*}"; n="${id##*-}"; [[ "$1" != *@* ]] || n="${1##*@}"
    out+="${sep}{\"name\":\"${name}\",\"run_attempt\":${n},\"started_at\":\"2026-10-01T$2:00Z\",\"completed_at\":\"2026-10-01T$3:00Z\"}"; sep=,; shift 3
  done
  echo "[{\"jobs\":[${out}]}]" > "${G}/jobs-${id}"
}
pr() { # <n> <branch> <sha>... — PR n's REST answers: the PR (its head branch) and its commits, slurped
  local n="$1" b="$2" c="" s; shift 2
  for s in "$@"; do c+="${c:+,}{\"sha\":\"${s}\"}"; done
  echo "{\"head\":{\"ref\":\"${b}\"}}" > "${G}/pull-${n}"; echo "[[${c}]]" > "${G}/commits-${n}"
}
pr 1 story/a a1; pr 2 story/b b1 b2; pr 3 story/c c1; pr 5 story/e e1; pr 6 story/f f0 f1; pr 7 story/g g0 g1
echo "[$(run 11 a1 CI pull_request success 1 10:10 10:16),$(run 10 a1 CI pull_request failure 1 10:00 10:04)]" > "${G}/runs-a"
echo "[$(run 12 a1 CI pull_request success 2 10:00 10:16 10:10)]" > "${G}/rerun-a"
echo '{"conclusion":"failure"}' > "${G}/attempt-12-1"
jobs 11-1 test 10:10 10:15 lint 10:10 10:11
jobs 12-2 test 10:10 10:15 lint 10:10 10:11 build@1 10:00 10:09
jobs 12-1 test 10:00 10:20
echo "[$(run 21 b2 CI pull_request success 1 10:20 10:26),$(run 22 b2 CI push failure 1 10:19 10:22),
  $(run 20 b1 CI pull_request failure 1 10:00 10:05),$(run 23 b1 lint pull_request startup_failure 1 10:00 10:01)]" > "${G}/runs-b"
echo "[$(run 31 c1 CI pull_request success 1 10:00 10:08),$(run 32 c1 zizmor pull_request success 2 10:01 10:07),
  $(run 33 c1 CI pull_request success 1 xx 10:40),$(run 30 c0 CI pull_request failure 1 09:00 09:30)]" > "${G}/runs-c"
echo '{"conclusion":"cancelled"}' > "${G}/attempt-32-1"
# With FAILATTEMPT=1 c's zizmor run had 3 attempts, and reading its first fails, though its second answers.
sed 's/"conclusion":"success","attempt":2/"conclusion":"success","attempt":3/' "${G}/runs-c" > "${G}/runs-c3"
echo '{"conclusion":"cancelled"}' > "${G}/attempt-32-2"
jobs 21-1 test 10:21 10:25 build 10:20 10:22
jobs 31-1 lint 10:00 10:07 test 10:00 10:03
echo "[$(run 51 e1 CI pull_request success 1 11:00 11:04)]" > "${G}/runs-e"
jobs 51-1 test 11:00 11:02 lint 11:00 11:01
echo "[$(run 61 f1 CI pull_request success 1 10:00 10:19),$(run 62 f1 zizmor pull_request success 2 10:00 10:01),
  $(run 63 f0 CI pull_request success 1 09:00 09:40)]" > "${G}/runs-f"
jobs 61-1 lint 10:01 10:05 / test 10:02 10:18
echo '{"conclusion":"success"}' > "${G}/attempt-62-1"
echo "[$(run 72 g0 CI pull_request success 1 10:30 10:50),$(run 71 g1 CI pull_request success 1 10:00 10:13)]" > "${G}/runs-g"
jobs 71-1 'te\u0007s\nt' 10:01 10:11 build 10:00 10:03
# gh: pr list answers each story's PR (d's on Enterprise; g's with the repo spelled O/r), pr view its
# createdAt or its commits (with BADPR=1, an object with neither), run list its branch's runs, and api
# a run's jobs or earlier attempt. O/r is o/r: GitHub ignores the case.
{ echo '#!/bin/sh'; echo "G=${G} U=${U}"; cat <<'EOF'; } > "${dir}/bin/gh"
echo "$*" >> "$G/gh.log"
# RATELIMIT=1: the hourly limit is spent for every REST call (outcomes' pr list and pr view still answer)
case "$*" in api*|run*) [ -z "${RATELIMIT:-}" ] || { echo 'gh: API rate limit exceeded for user ID 1. (HTTP 403)' >&2; exit 1; } ;; esac
case "$*" in "run list -R o/r --branch story/${FLAKY:-} "*) # FLAKY=<story>: its run list fails twice, then answers
  [ "$(cat "$G/flaky-$FLAKY" 2>/dev/null)" = xx ] || { printf x >> "$G/flaky-$FLAKY"; echo 'read: connection reset by peer' >&2; exit 1; } ;;
esac
case "$*" in
"pr list --head story/d"*) printf 'https://ghe.example.com/o/r/pull/9\tOPEN\t\t2026-10-01T10:00:00Z\t0\n' ;;
"pr list --head story/g"*) printf 'https://github.com/O/r/pull/7\tOPEN\t\t2026-10-01T10:00:00Z\t0\n' ;;
"pr list --head story/"*) printf '%s/%s\tOPEN\t\t2026-10-01T10:00:00Z\t0\n' "$U" "$(echo "${4##*/}" | tr abcef 12356)" ;;
"pr view https://github.com/"[oO]"/r/pull/"*" --json createdAt"*) echo 2026-10-01T10:00:00Z ;;
"api repos/"[oO]"/r/pulls/"*) [ -z "${SLOW:-}" ] || sleep 12; if [ -n "${BADPR:-}" ]; then echo '{}'; else cat "$G/pull-${2##*/}"; fi ;;
"api --paginate --slurp repos/"[oO]"/r/pulls/"*"/commits?per_page=100") cat "$G/commits-$(echo "$4" | cut -d/ -f5)" ;;
"run list -R o/r --branch story/a "*) if [ -n "${RERUN:-}" ]; then cat "$G/rerun-a"; else cat "$G/runs-a"; fi ;;
"run list -R o/r --branch story/b "*) [ -z "${FAIL:-}${FAILB:-}" ] || { echo 'HTTP 403: You have exceeded a secondary rate limit.' >&2; exit 1; }
  [ -z "${BADJSON:-}" ] || { echo 'not json'; exit 0; }
  cat "$G/runs-b" ;;
"run list -R "[oO]"/r --branch story/"*) [ -z "${FAIL:-}" ] || exit 1; [ -z "${FAILWEEK:-}" ] || [ "${6##*/}" = g ] || exit 1; cat "$G/runs-${6##*/}${FAILATTEMPT:+3}" ;;
"api --paginate --slurp repos/o/r/actions/runs?created="*) echo '[{"total_count":0,"workflow_runs":[]}]' ;;   # flow_test.sh has the flaky tests
"api --paginate --slurp repos/"[oO]"/r/actions/runs/"*"/attempts/"*"/jobs?per_page=100") cat "$G/jobs-$(echo "$4" | cut -d/ -f6,8 | tr / -)" ;;
"api repos/"[oO]"/r/actions/runs/"*) [ -z "${FAILATTEMPT:-}" ] || [ "$2" != repos/o/r/actions/runs/32/attempts/1 ] || { echo 'HTTP 502: Bad Gateway' >&2; exit 1; }
  cat "$G/attempt-$(echo "$2" | cut -d/ -f6,8 | tr / -)" ;;
esac
EOF
chmod +x "${dir}/bin/gh"

flow() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${dir}/bin:${PATH}" bash "${SWARM}" flow "$@"); }
W=(--since 2020-01-01 --until 2020-01-01)
ci() { awk '/^## / { f = $0 == "## ci_health"; next } f && NF && !/^flaky tests: /'; } # flow's ci_health section, less the flaky tests' lines (flow_test.sh checks them)
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
B="gh run list -R o/r --branch story/b --limit 200: HTTP 403: You have exceeded a secondary rate limit."
C="gh run list -R o/r --branch story/c --limit 200: exit 1"
N="ci time: gh could not read"
left() { # <section> <error, with % for the PR's number> <n>... — the left-out line of each PR n
  local n; for n in "${@:3}"; do printf '\n%s: left out %s/%s: %s' "$1" "${U}" "${n}" "${2//%/${n}}"; done
}
calls() { grep -c "$1" "${G}/gh.log" || true; }
: > "${G}/gh.log"
check "a failing gh leaves out the PRs it could not read, from the row too, and names each with its call and gh's error; a's numbers stay" \
  "$(FAIL=1 flow "${W[@]}" | ci)" "${H}"$'\n1\t1\t16.0\t1.00\t1\n'"ci health: gh could not read 2 of 3 PRs, left out$(left "ci health" "${B}" 2)$(left "ci health" "${C}" 3)"$'\n'"${T}"$'\no/r\t1\t6.0\ttest\t5.0\t0\t\t\t\t\n'"${N} 2 of 3 PRs (2 of 3 in this window), left out$(left "ci time" "${B}" 2)$(left "ci time" "${C}" 3)"
check "an error that is not a reset connection or a 5xx (here a secondary rate limit) is not tried again" "$(calls 'run list -R o/r --branch story/b ')" 1
check "a PR answered with no branch is left out" "$(BADPR=1 flow "${W[@]}" | ci)" \
  "${H}"$'\n0\t0\t\t\t0\n'"ci health: gh could not read 3 of 3 PRs, left out$(left "ci health" "gh api repos/o/r/pulls/%: no branch" 1 2 3)"$'\n'"${T}"$'\n'"${N} 3 of 3 PRs (3 of 3 in this window), left out$(left "ci time" "gh api repos/o/r/pulls/%: no branch" 1 2 3)"
check "a gh call over 10 seconds is a failure, and ci time has no row" "$(SLOW=1 flow "${W[@]}" | ci)" \
  "${H}"$'\n0\t0\t\t\t0\n'"ci health: gh could not read 3 of 3 PRs, left out$(left "ci health" "gh api repos/o/r/pulls/%: over 10 s" 1 2 3)"$'\n'"${T}"$'\n'"${N} 3 of 3 PRs (3 of 3 in this window), left out$(left "ci time" "gh api repos/o/r/pulls/%: over 10 s" 1 2 3)"
check "ci time and the row keep the PRs gh could read: a and c, and a line for b with gh's error" "$(FAILB=1 flow "${W[@]}" | ci)" \
  "${H}"$'\n2\t2\t12.0\t0.50\t1\n'"ci health: gh could not read 1 of 3 PRs, left out$(left "ci health" "${B}" 2)"$'\n'"${T}"$'\no/r\t2\t7.0\tlint\t7.0\t0\t\t\t\t\n'"${N} 1 of 3 PRs (1 of 3 in this window), left out$(left "ci time" "${B}" 2)"
check "and c's run list failing twice before it answers does not stand in for b's error" "$(FAILB=1 FLAKY=c flow "${W[@]}" | ci)" \
  "${H}"$'\n2\t2\t12.0\t0.50\t1\n'"ci health: gh could not read 1 of 3 PRs, left out$(left "ci health" "${B}" 2)"$'\n'"${T}"$'\no/r\t2\t7.0\tlint\t7.0\t0\t\t\t\t\n'"${N} 1 of 3 PRs (1 of 3 in this window), left out$(left "ci time" "${B}" 2)"
: > "${G}/gh.log"
check "an earlier attempt gh cannot read names that attempt's call, not a later one's that answered" "$(FAILATTEMPT=1 flow "${W[@]}" | ci)" \
  "${H}"$'\n2\t3\t7.0\t2.00\t1\n'"ci health: gh could not read 1 of 3 PRs, left out$(left "ci health" "gh api repos/o/r/actions/runs/32/attempts/1: HTTP 502: Bad Gateway" 3)"$'\n'"${T}"$'\no/r\t3\t6.0\tlint\t7.0\t0\t\t\t\t'
check "a 5xx is tried three times" "$(calls 'runs/32/attempts/1$')" 3
check "a run list that fails twice on a reset connection, then answers, still counts b" "$(FLAKY=b flow "${W[@]}" | ci)" \
  "${H}"$'\n3\t4\t7.5\t1.33\t1\n'"${T}"$'\no/r\t3\t6.0\tlint\t7.0\t0\t\t\t\t'
rm -f "${G}/flaky-b"   # b's run list fails twice again
check "a try that answers with something not JSON, after two that failed, names that, not their error" "$(FLAKY=b BADJSON=1 flow "${W[@]}" | ci | grep 'ci time: left out')" \
  "ci time: left out ${U}/2: gh run list -R o/r --branch story/b --limit 200: an answer that is not JSON"
: > "${G}/gh.log"
L1="gh: API rate limit exceeded for user ID 1. (HTTP 403)"
check "once the hourly rate limit is spent, flow makes no more gh calls and names that error for each PR" "$(RATELIMIT=1 flow "${W[@]}" | ci)" \
  "${H}"$'\n0\t0\t\t\t0\n'"ci health: gh could not read 3 of 3 PRs, left out$(left "ci health" "gh api repos/o/r/pulls/1: ${L1}" 1)$(left "ci health" "gh api repos/o/r/pulls/%: not tried: ${L1}" 2 3)"$'\n'"${T}"$'\n'"${N} 3 of 3 PRs (3 of 3 in this window), left out$(left "ci time" "gh api repos/o/r/pulls/1: ${L1}" 1)$(left "ci time" "gh api repos/o/r/pulls/%: not tried: ${L1}" 2 3)"
check "one REST call, the first" "$(grep -cE '^(api|run) ' "${G}/gh.log" || true)" 1
# flow counts the 30 days from its own today: should the day turn after T0, its start is a day later.
got="$(flow | ci)"; late="$(ago 30 "$(date +%s)")"
[[ "${got}" != "PRs from the last 30 days, ${late} on;"* ]] || start="${late}"
check "with no --since, the PRs of the last 30 days, and a line that says so" "${got}" \
  "PRs from the last 30 days, ${start} on; --since sets the start"$'\n'"${H}"$'\n3\t5\t19.0\t0.00\t0\n'"${T}"$'\no/r\t3\t13.0\ttest\t10.0\t0\t\t\t\t'
now="$(flow --since "${week}" | ci)"
check "the last 7 days against the 7 before: 11.5 min, test slowest at 9.0, against 13.0 and 10.0, so -1.5" \
  "${now}" "${H}"$'\n2\t3\t19.0\t0.00\t0\n'"${T}"$'\no/r\t2\t11.5\ttest\t9.0\t1\t13.0\ttest\t10.0\t-1.5'

# SWARM_DASH_NOW fixes flow's day (bin/lib/clock.py): at noon 3 days back, the last 7 days run from 6
# days before that to that day, which holds f's two builds and g's but not e's today, and the 7 days
# before hold no PR, so the row has no change. flow_ci_health.py's window, with no end, would hold e.
pinned="$(python3 -c 'import datetime as d, sys; print(int(d.datetime.combine(d.date.fromisoformat(sys.argv[1]), d.time(12)).timestamp()))' "$(ago 3)")"
check "with SWARM_DASH_NOW 3 days back, flow's 7 days to that day hold f and g alone: ci 16m (slowest: test 13m)" \
  "$(SWARM_DASH_NOW="${pinned}" flow --since "$(ago 6 "${pinned}")" | ci | awk -F'\t' '$1 == "o/r" && $7 == "" { printf "ci %.0fm (slowest: %s %.0fm)", $3, $4, $5 }')" \
  "ci 16m (slowest: test 13m)"
# And flow's own start with no --since, 30 days before that day (flow_ci_health.py's date.today() had it).
check "with SWARM_DASH_NOW 3 days back and no --since, flow's window starts 30 days before that day" \
  "$(SWARM_DASH_NOW="${pinned}" flow | ci | head -1)" "PRs from the last 30 days, $(ago 30 "${pinned}") on; --since sets the start"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
