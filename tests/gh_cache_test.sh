#!/usr/bin/env bash
# gh_cache_test.sh — flow caches finished GitHub records (bin/lib/gh_cache.py) against a gh stub
# that logs each call. Stories a to d were built 6 days ago. a's PR 1 merged 5 days ago; its run 11
# went green on a rerun of a red attempt (whose log names a FAIL line). b's PR 2 is open. c's PR 3
# merged 4 days ago, but its run 31, created 2 days ago, is still running until the stub's done file
# exists. d's PR 4 was closed without a merge. PR 9 (no story's) merged 3 days ago, b's run 21 was
# created a day ago, and run 51 has sat queued for 3 days.
# A second flow --since 7 days ago prints what the first printed and reads nothing of PR 1 or its
# runs, nor PR 3's PR or commits, nor PR 4's commits or runs (only PR 4 itself, as a closed PR can be
# reopened). It searches merged PRs from a day before PR 9's day, and lists runs from 3 days before
# run 31's day (the queued run holds nothing). Once run 31 is done, a flow reads c's runs once more
# and caches them, and the next lists runs from 3 days before run 21's day. When PR 4's updated_at
# moves, its commits and runs are read again. A damaged cache file is read from gh again and
# rewritten; --no-cache reads everything again and writes it over the cache. A listing cut at
# GitHub's 1000 moves nothing on. An empty log (one GitHub has not archived yet) is not cached. A
# cached run created over 90 days ago is dropped.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
unset SWARM_GH_CACHE
P="${dir}/repo"; G="${dir}/gh"; C="${P}/.swarm/gh-cache/o--r"; U=https://github.com/o/r/pull
mkdir -p "${P}/.swarm" "${P}/docs/stories" "${G}" "${dir}/bin"
git -C "${P}" init -q
# <n> days ago: its local day, or with t its UTC time, or with d its UTC day.
ago() { python3 -c 'import datetime as d, sys; t = d.datetime.now(d.timezone.utc) - d.timedelta(days=int(sys.argv[1]))
print(t.strftime({"t": "%Y-%m-%dT%H:%M:%SZ", "d": "%Y-%m-%d"}[sys.argv[2]]) if sys.argv[2:] else t.astimezone().date())' "$@"; }
since="$(ago 7)"; m1="$(ago 5 t)"; m3="$(ago 4 t)"; m9="$(ago 3 t)"; r31="$(ago 2 t)"; r21="$(ago 1 t)"
for s in a b c d; do
  printf -- '---\nkind: code\nstatus: ready\n---\n' > "${P}/docs/stories/${s}.md"
  printf '%s\tcode\t%s\tclaude\topus\thigh\t-\n' "$(ago 6)" "${s}" >> "${P}/.swarm/agents.tsv"
done
run() { # <id> <sha> <workflow> <status> <conclusion> <attempt> <created>
  printf '{"databaseId":%s,"headSha":"%s","workflowName":"%s","event":"pull_request","status":"%s","conclusion":"%s","attempt":%s,"createdAt":"%s","startedAt":"%s","updatedAt":"%s"}' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$7" "$7"
}
listed() { # the same run as the runs listing names it
  printf '{"id":%s,"head_sha":"%s","name":"%s","event":"pull_request","status":"%s","conclusion":"%s","run_attempt":%s,"created_at":"%s"}' "$@"
}
printf '%s\tMERGED\t%s\t%s\t0\t\t\t%s\t0\n' "${U}/1" "${m1}" "${m1}" "${m1}" > "${G}/head-a"
printf '%s\tOPEN\t\t%s\t0\t\t\t\t0\n' "${U}/2" "${m1}" > "${G}/head-b"
printf '%s\tMERGED\t%s\t%s\t0\t\t\t%s\t0\n' "${U}/3" "${m3}" "${m3}" "${m3}" > "${G}/head-c"
printf '%s\tCLOSED\t\t%s\t0\t\t\t%s\t0\n' "${U}/4" "${m1}" "${m3}" > "${G}/head-d"
pull() { # <n> <story> <state> <merged_at, or null> <updated_at> [<head ref>]
  echo "{\"state\":\"$3\",\"merged_at\":$4,\"updated_at\":\"$5\",\"head\":{\"ref\":\"story/${6:-$2}\"},\"base\":{\"ref\":\"main\"}}" > "${G}/pull-$1"
  echo "[[{\"sha\":\"${2}1\",\"commit\":{\"message\":\"$2\"}}]]" > "${G}/commits-$1"
}
pull 1 a closed "\"${m1}\"" "${m1}"; pull 2 b open null "${m1}"; pull 3 c closed "\"${m3}\"" "${m3}"; pull 4 d closed null "${m3}"
echo "[$(run 11 a1 CI completed success 2 "${m1}")]" > "${G}/runs-a"
echo "[$(run 21 b1 CI completed success 1 "${r21}")]" > "${G}/runs-b"
echo "[$(run 31 c1 CI in_progress '' 1 "${r31}")]" > "${G}/runs-c"
echo "[$(run 31 c1 CI completed success 1 "${r31}")]" > "${G}/runs-c-done"
echo "[$(run 41 d1 CI completed success 1 "${m1}")]" > "${G}/runs-d"
echo "[{\"url\":\"${U}/1\",\"mergedAt\":\"${m1}\",\"title\":\"a\",\"body\":\"\",\"files\":[]},{\"url\":\"${U}/9\",\"mergedAt\":\"${m9}\",\"title\":\"x\",\"body\":\"\",\"files\":[]}]" > "${G}/merged"
echo '[{"jobs":[{"name":"test","run_attempt":1,"started_at":"2026-10-01T10:00:00Z","completed_at":"2026-10-01T10:05:00Z"}]}]' > "${G}/jobs"
printf 'test\trun\t2026-10-01T10:04:00.000Z FAIL tests/x_test.sh 3s\ntest\trun\t2026-10-01T10:04:01.000Z noise\n' > "${G}/log-11"
{ echo '#!/bin/sh'; echo "G=${G} U=${U}"
  echo "W='[{\"total_count\":4,\"workflow_runs\":[$(listed 11 a1 CI completed success 2 "${m1}"),$(listed 21 b1 CI completed success 1 "${r21}"),"
  echo "  $(listed 31 c1 CI in_progress '' 1 "${r31}"),$(listed 51 a1 lint queued '' 1 "${m9}")]}]'"
  echo "R61='$(listed 61 b1 CI completed success 1 "$(ago 0 t)")'"
  cat <<'EOF'; } > "${dir}/bin/gh"
echo "$*" >> "$G/gh.log"
done=""; [ ! -f "$G/done" ] || done=-done
case "$*" in
"pr list --head story/"*) cat "$G/head-${4##*/}" ;;
"pr list -R o/r --state merged "*) cat "$G/merged" ;;
"pr view $U/"*" --json createdAt"*) cut -f4 "$G/head-a" ;;
"api repos/o/r/pulls/"*) cat "$G/pull-${2##*/}" ;;
"api --paginate --slurp repos/o/r/pulls/"*"/commits?per_page=100") cat "$G/commits-$(echo "$4" | cut -d/ -f5)" ;;
"run list -R o/r --branch story/c "*) cat "$G/runs-c$done" ;;
"run list -R o/r --branch story/"*) cat "$G/runs-${6##*/}" ;;
"api --paginate --slurp repos/o/r/actions/runs?created="*) # CUT=1: cut at GitHub's 1000, with a run created today
  [ -z "${CUT:-}" ] || W=$(echo "$W" | sed "s/\"total_count\":4/\"total_count\":1000/; s/\"workflow_runs\":\[/&$R61,/")
  if [ -n "$done" ]; then echo "$W" | sed 's/"in_progress","conclusion":""/"completed","conclusion":"success"/'; else echo "$W"; fi ;;
"api --paginate --slurp repos/o/r/actions/runs/"*"/jobs?per_page=100") cat "$G/jobs" ;;
"api repos/o/r/actions/runs/11/attempts/1") echo '{"conclusion":"failure","status":"completed"}' ;;
"run view 11 -R o/r --attempt 1 --log-failed") [ -f "$G/nolog" ] || cat "$G/log-11" ;;   # nolog: GitHub has not archived it yet
esac
EOF
chmod +x "${dir}/bin/gh"

flow() { : > "${G}/gh.log"; (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${dir}/bin:${PATH}" bash "${SWARM}" flow --since "${since}" "$@" 2>/dev/null) \
  | awk '/^## / { f = $0 != "## gh_calls" } f'; }   # less gh_calls, which counts each run's own calls
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
calls() { grep -cE "$1" "${G}/gh.log" || true; }   # gh calls the last flow made whose arguments match
merged() { sed -n 's/^pr list -R o\/r --state merged .*--search merged:\([0-9-]*\)\.\..*/\1/p' "${G}/gh.log"; }
listing() { sed -n 's/^api --paginate --slurp repos\/o\/r\/actions\/runs?created=%3E%3D\([0-9-]*\)&.*/\1/p' "${G}/gh.log"; }   # the day runs are listed from
PR1='pulls/1$|pulls/1/|branch story/a |runs/11/|run view 11 |pull/1 '   # PR 1 and its runs, every call that reads them
first="$(flow)"
check "the first flow reads PR 1, its commits, runs, run 11's earlier attempt, jobs and log, and its createdAt" "$(calls "${PR1}")" 7
check "it lists merged PRs and runs from the window's start, runs in one call" "$(merged) $(listing) $(calls 'runs[?]created=')" "$(ago 5 d) ${since} 1"
check "the flaky test file comes from the log" "$(grep -c 'tests/x_test.sh' <<< "${first}")" 1
check "only the FAIL line of run 11's log is cached" "$(cat "${C}/logs/11-1.json")" '{"fail": "test\trun\t2026-10-01T10:04:00.000Z FAIL tests/x_test.sh 3s"}'
second="$(flow)"
check "a second flow prints what the first printed" "${second}" "${first}"
check "it reads nothing of merged PR 1 or its completed runs" "$(calls "${PR1}")" 0
check "nor PR 3's PR or commits" "$(calls 'pulls/3')" 0
check "it reads closed PR 4 again, as it can be reopened, but not its commits or runs" "$(calls 'pulls/4$') $(calls 'pulls/4/') $(calls 'branch story/d ')" "1 0 0"
check "it searches merged PRs from a day before the newest's day (PR 9's), runs from 3 days before run 31's, still running (run 51, queued for days, holds nothing)" \
  "$(merged) $(listing)" "$(ago 4 d) $(ago 5 d)"
check "it reads open PR 2 again, and c's runs, one still running" "$(calls 'pulls/2$') $(calls 'pulls/2/commits') $(calls 'branch story/b ') $(calls 'branch story/c ')" "1 1 1 1"
check "each story's PR list is read, as their stories are on the board" "$(calls '^pr list --head')" 4
check "the second flow makes 11 gh calls" "$(calls '^[a-z]')" 11   # a call's own lines (pr list's jq) start with a space
touch "${G}/done"
flow > /dev/null
check "once run 31 is done, c's runs are read once more, and its jobs" "$(calls 'branch story/c ') $(calls 'runs/31/attempts/1/jobs')" "1 1"
flow > /dev/null
check "then they are cached: no read of c's runs or run 31's jobs" "$(calls 'branch story/c ') $(calls 'runs/31/')" "0 0"
check "and runs are listed from 3 days before run 21's day, the newest, so a rerun since is read" "$(listing)" "$(ago 4 d)"
pull 4 d closed null "${r21}"   # reopened, pushed to and closed again
flow > /dev/null
check "once closed PR 4's updated_at moves, its commits and runs are read again" "$(calls 'pulls/4/') $(calls 'branch story/d ')" "1 1"
python3 -c 'import json, sys; p = sys.argv[1]; d = json.load(open(p))
d["items"]["9"] = dict(d["items"]["11"], databaseId=9, createdAt=sys.argv[2]); json.dump(d, open(p, "w"))' "${C}/runs.json" "$(ago 91 t)"
done_out="$(flow)"
check "a cached run created over 90 days ago is dropped" "$(grep -c '"databaseId": 9,' "${C}/runs.json")" 0
for f in "${C}/pulls/1.json" "${C}/runs.json" "${C}/merged.json"; do printf '{"half' > "${f}"; done
check "a damaged cache prints the same" "$(flow)" "${done_out}"
check "and reads PR 1 and lists runs and merged PRs from the window's start again" "$(calls 'pulls/1$') $(merged) $(listing)" "1 $(ago 5 d) ${since}"
check "then rewrites them whole" "$(python3 -c 'import json, sys; [json.load(open(f)) for f in sys.argv[1:]]; print("parsed")' "${C}/pulls/1.json" "${C}/runs.json" "${C}/merged.json")" parsed
sed 's/story\/a/story\/stale/' "${C}/pulls/1.json" > "${G}/stale" && mv "${G}/stale" "${C}/pulls/1.json"
check "--no-cache prints the same" "$(flow --no-cache)" "${done_out}"
check "and reads everything of PR 1 again, from the window's start" "$(calls "${PR1}") $(merged) $(listing)" "7 $(ago 5 d) ${since}"
check "and writes what gh answered over the cache, so the next flow reads none of PR 1" "$(grep -c story/a "${C}/pulls/1.json") $(flow > /dev/null; calls "${PR1}")" "1 0"
check "a listing cut at the 1000 says so" "$(CUT=1 flow | grep -c "^flaky tests: gh listed 5 of the 1000 runs of o/r created >=$(ago 4 d), the newest")" 1
flow > /dev/null
check "and moves nothing on: runs are listed from the same day, not from today's run 61" "$(listing)" "$(ago 4 d)"
rm "${C}/logs/11-1.json"; touch "${G}/nolog"
flow > /dev/null
check "an empty log (not archived yet) is not cached, and is read again next run" "$(test -f "${C}/logs/11-1.json" && echo cached; flow > /dev/null; calls 'run view 11 ')" 1
[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
