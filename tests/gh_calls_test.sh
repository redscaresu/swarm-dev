#!/usr/bin/env bash
# gh_calls_test.sh — bin/gh-shim/gh in front of a stub gh: the stub's exit code, stdout and stdin pass
# through unchanged; each call logs one line with its agent, via, subcommand (an API path's numbers as
# :id, flags anywhere before the subcommand skipped), budget and many marker, and no argument past the
# subcommand (a token-like one checked); an unwritable log still runs the call; a killed shim ends gh.
# Then `swarm.sh flow`'s gh_calls section over a fixture log: gh runs per hour by role (agents.tsv's)
# and by subcommand, each hour's budget under its all row, with many and the share of 5000; what it
# says with no log or none in the window; and where swarm.sh's own calls are logged.
set -euo pipefail
export TZ=UTC

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# The stub: with STUB_SLEEP, sleeps that long then touches STUB_MARK; prints its arguments and stdin,
# exits with STUB_RC.
mkdir -p "${dir}/stub"
# shellcheck disable=SC2016 # the stub expands them
printf '#!/bin/sh\n[ -z "${STUB_SLEEP:-}" ] || { sleep "${STUB_SLEEP}"; touch "${STUB_MARK}"; }\necho "args: $*"\ncat\nexit "${STUB_RC:-0}"\n' > "${dir}/stub/gh"; chmod +x "${dir}/stub/gh"
LOG="${dir}/gh-calls.tsv"
shim() { PATH="${REPO}/bin/gh-shim:${dir}/stub:${PATH}" SWARM_GH_LOG="${LOG}" SWARM_GH_CALLER=b1 "$@"; }

rc=0; out="$(echo hello | STUB_RC=3 shim gh pr view 12 --json state)" || rc=$?
check "stdout and stdin pass through" "${out}" "$(printf 'args: pr view 12 --json state\nhello')"
check "the exit code passes through" "${rc}" 3
# A token-like argument, put together here so the secret scanners never see one in the file.
TOKEN="ghp_$(printf 'SECRET%s' 123)"
shim gh api -H "Authorization: token ${TOKEN}" repos/o/r/pulls/12/comments?per_page=100 < /dev/null > /dev/null
shim gh api graphql -f query="${TOKEN}" < /dev/null > /dev/null
shim gh run view "${TOKEN}" < /dev/null > /dev/null
shim gh browse "${TOKEN}" < /dev/null > /dev/null
shim gh pr diff 12 < /dev/null > /dev/null
shim gh -R o/r pr view 12 < /dev/null > /dev/null
shim gh pr --repo o/r view 1 < /dev/null > /dev/null
shim gh api https://api.github.com/graphql -f query=q < /dev/null > /dev/null
shim gh status < /dev/null > /dev/null
shim gh label list < /dev/null > /dev/null
shim gh api --paginate --slurp repos/o/r/pulls/7/files < /dev/null > /dev/null
shim gh pr checks 7 --watch < /dev/null > /dev/null
shim gh run watch 9 < /dev/null > /dev/null
SWARM_GH_VIA="swarm.sh wait-pr" shim gh api repos/o/r/commits/abc1234/check-runs < /dev/null > /dev/null
rc=0; timeout -k 2 10 env PATH="${REPO}/bin/gh-shim:${dir}/stub:${PATH}" SWARM_GH_LOG="${LOG}" SWARM_GH_CALLER=b1 STUB_RC=2 gh api --header < /dev/null > /dev/null || rc=$?
check "a flag missing its value ends the parse: gh's exit code, no hang" "${rc}" 2
check "one line per call: agent, via, subcommand, API path with ids collapsed, budget, many, exit code" "$(cut -f2- "${LOG}")" "$(printf '%s\n' \
  $'b1\t-\tpr view\tgraphql\t-\t3' $'b1\t-\tapi repos/o/r/pulls/:id/comments\trest\t-\t0' $'b1\t-\tapi graphql\tgraphql\t-\t0' \
  $'b1\t-\trun view\trest\t-\t0' $'b1\t-\tbrowse\trest\t-\t0' $'b1\t-\tpr diff\trest\t-\t0' $'b1\t-\tpr view\tgraphql\t-\t0' \
  $'b1\t-\tpr view\tgraphql\t-\t0' $'b1\t-\tapi graphql\tgraphql\t-\t0' $'b1\t-\tstatus\tgraphql\t-\t0' $'b1\t-\tlabel list\tgraphql\t-\t0' \
  $'b1\t-\tapi repos/o/r/pulls/:id/files\trest\tpaginate\t0' $'b1\t-\tpr checks\tgraphql\twatch\t0' $'b1\t-\trun watch\trest\twatch\t0' \
  $'b1\tswarm.sh wait-pr\tapi repos/o/r/commits/:id/check-runs\trest\t-\t0' $'b1\t-\tapi ?\trest\t-\t2')"
check "no argument past the subcommand is logged" "$(grep -c SECRET "${LOG}" || true)" 0
check "the time is UTC, to the second" "$(cut -f1 "${LOG}" | grep -cvE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || true)" 0

rc=0; out="$(PATH="${REPO}/bin/gh-shim:${dir}/stub:${PATH}" SWARM_GH_LOG="${dir}/no/such/dir/log" gh auth status < /dev/null 2>&1)" || rc=$?
check "an unwritable log still runs the call, quietly" "${rc} ${out}" "0 args: auth status"

# A shim killed outright (a Python caller's timeout sends KILL) takes gh with it: gh never finishes.
# A simple command, not the shim function, so $! is the shim's own PID.
# Where a pipe to a process cannot open (a sandbox that refuses /dev/fd), the shim runs without its
# watcher by design (checked below), so this is skipped there.
if bash -c 'exec 3> >(cat > /dev/null)' 2>/dev/null; then
  PATH="${REPO}/bin/gh-shim:${dir}/stub:${PATH}" STUB_SLEEP=3 STUB_MARK="${dir}/late" gh pr view 13 < /dev/null > /dev/null 2>&1 &
  killed=$!
  sleep 1; kill -KILL "${killed}"; wait "${killed}" 2>/dev/null || true; sleep 4
  check "a shim killed outright ends gh too" "$([[ -e "${dir}/late" ]] && echo "gh finished" || echo "gh ended")" "gh ended"
else
  echo "ok   a shim killed outright ends gh too (skipped: no pipe to a process here)"
fi

# A watcher pipe that cannot open (codex's macOS sandbox refuses /dev/fd) leaves gh running: its
# watcher never gets the shim's go. sandbox-exec stands in for that sandbox; where it cannot run
# (Linux, or inside another sandbox) the check is skipped.
NOFD='(version 1)(allow default)(deny file-write* (regex #"^/dev/fd/"))'
if sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>/dev/null; then
  rc=0; out="$(sandbox-exec -p "${NOFD}" env PATH="${REPO}/bin/gh-shim:${dir}/stub:${PATH}" SWARM_GH_LOG="${LOG}" STUB_SLEEP=1 STUB_MARK="${dir}/slow" \
    gh pr view 14 < /dev/null 2>&1)" || rc=$?
  check "a watcher pipe that cannot open leaves gh running, quietly" "${rc} ${out}" "0 args: pr view 14"
else
  echo "ok   a watcher pipe that cannot open leaves gh running, quietly (skipped: no sandbox-exec here)"
fi

# A second shim folder (an older version's) is skipped too, so two shims never call each other.
# The older one is a stand-in that says so, so a shim that ran it fails here rather than looping.
mkdir -p "${dir}/old/gh-shim"; printf '#!/bin/sh\necho "an older shim ran"\n' > "${dir}/old/gh-shim/gh"; chmod +x "${dir}/old/gh-shim/gh"
out="$(PATH="${REPO}/bin/gh-shim:${dir}/old/gh-shim:${dir}/stub:${PATH}" gh pr list < /dev/null)"
check "another gh-shim folder on PATH is skipped" "${out}" "args: pr list"

# flow's gh_calls over a fixture: b1 is a builder (code), c1 a conductor. Hour 10's GraphQL: b1's
# own 6 and its swarm.sh wait-pr's 4 (code, 10), c1's 4 watched pr checks (conduct); its REST: the
# lead's swarm.sh merge, paginated. Hour 11: c1's 8. Read from the end, the 09-20 line (more than two
# days before --since) stops the reading, so the 10-01 line written before it is never counted.
P="${dir}/repo"; mkdir -p "${P}/.swarm"; git -C "${P}" init -q; P="$(cd "${P}" && pwd -P)"   # as swarm.sh resolves it
# Outside any agent (this test may itself run in one): no SWARM_AGENT or SWARM_GH_CALLER.
flow() { (cd "${P}" && PATH="${dir}/stub:${PATH}" env -u HERDR_ENV -u SWARM_PROJECT -u SWARM_AGENT -u SWARM_GH_CALLER SWARM_FLOW_SECTIONS=gh_calls "$@" bash "${REPO}/bin/swarm.sh" flow --since 2026-10-01 --until 2026-10-01); }
# With no agents.tsv yet, flow itself runs no gh, so there is no log.
check "with no log yet, gh_calls says so" "$(flow | tail -1)" "no gh calls logged: no ${P}/.swarm/gh-calls.tsv yet (bin/gh-shim writes it once swarm.sh or an agent it started runs gh)"
printf '%s\n' $'2026-10-01\tcode\tb1\tclaude\topus\thigh\ts1' $'2026-10-01\tconduct\tc1\tclaude\topus\thigh\ts2' > "${P}/.swarm/agents.tsv"
{
  printf '2026-10-01T10:30:00Z\tb1\t-\tpr list\tgraphql\t-\t0\n'   # before the stop line: never read
  printf '2026-09-20T10:00:00Z\tb1\t-\tpr view\tgraphql\t-\t0\n'
  printf '2026-09-30T10:00:00Z\tb1\t-\tpr view\tgraphql\t-\t0\n'   # before --since
  for _ in 1 2 3 4 5 6; do printf '2026-10-01T10:05:00Z\tb1\t-\tpr view\tgraphql\t-\t0\n'; done
  for _ in 1 2 3 4; do printf '2026-10-01T10:06:00Z\tb1\tswarm.sh wait-pr\tapi graphql\tgraphql\t-\t0\n'; done
  for _ in 1 2 3 4; do printf '2026-10-01T10:10:00Z\tc1\t-\tpr checks\tgraphql\twatch\t0\n'; done
  printf '2026-10-01T10:20:00Z\t-\tswarm.sh merge\tapi repos/o/r/pulls/:id/files\trest\tpaginate\t0\n'
  for _ in 1 2 3 4 5 6 7 8; do printf '2026-10-01T11:00:00Z\tc1\t-\tpr view\tgraphql\t-\t1\n'; done
  printf 'garbage\n'
} > "${P}/.swarm/gh-calls.tsv"
# --until keeps out flow's own gh calls (outcomes' pr list, to the stub).
check "flow's gh_calls: by role, then by subcommand, each hour's budget under its all row, most first" "$(flow)" "$(printf '%s\n' "## gh_calls" \
  "# gh runs, not API requests: a run with many > 0 (--paginate, --watch) spends several, and GraphQL counts points" \
  $'hour\tapi\trole\truns\tmany\tshare' \
  $'2026-10-01 10:00\tgraphql\tall\t14\t4\t0.3%' \
  $'2026-10-01 10:00\tgraphql\tcode\t10\t0\t0.2%' \
  $'2026-10-01 10:00\tgraphql\tconduct\t4\t4\t0.1%' \
  $'2026-10-01 10:00\trest\tall\t1\t1\t0.0%' \
  $'2026-10-01 10:00\trest\t-\t1\t1\t0.0%' \
  $'2026-10-01 11:00\tgraphql\tall\t8\t0\t0.2%' \
  $'2026-10-01 11:00\tgraphql\tconduct\t8\t0\t0.2%' \
  '' \
  $'hour\tapi\tsubcommand\truns\tmany\tshare' \
  $'2026-10-01 10:00\tgraphql\tall\t14\t4\t0.3%' \
  $'2026-10-01 10:00\tgraphql\tpr view\t6\t0\t0.1%' \
  $'2026-10-01 10:00\tgraphql\tapi graphql via swarm.sh wait-pr\t4\t0\t0.1%' \
  $'2026-10-01 10:00\tgraphql\tpr checks\t4\t4\t0.1%' \
  $'2026-10-01 10:00\trest\tall\t1\t1\t0.0%' \
  $'2026-10-01 10:00\trest\tapi repos/o/r/pulls/:id/files via swarm.sh merge\t1\t1\t0.0%' \
  $'2026-10-01 11:00\tgraphql\tall\t8\t0\t0.2%' \
  $'2026-10-01 11:00\tgraphql\tpr view\t8\t0\t0.2%')"
check "a window with no lines says so" "$(cd "${P}" && PATH="${dir}/stub:${PATH}" env -u HERDR_ENV -u SWARM_PROJECT -u SWARM_AGENT -u SWARM_GH_CALLER SWARM_FLOW_SECTIONS=gh_calls bash "${REPO}/bin/swarm.sh" flow --since 2026-10-05 --until 2026-10-05 | tail -1)" \
  "no gh calls logged in the window (2026-10-05 to 2026-10-05)"
check "swarm.sh's own gh calls log with its command as via, outside any agent" "$(tail -1 "${P}/.swarm/gh-calls.tsv" | cut -f2,3,5)" $'-\tswarm.sh flow\tgraphql'
flow SWARM_GH_CALLER=b1 > /dev/null
check "a builder's swarm.sh keeps the builder as the agent, so its calls count under its role" "$(tail -1 "${P}/.swarm/gh-calls.tsv" | cut -f2,3)" $'b1\tswarm.sh flow'

# A command run for another project (as dash --project runs swarm.sh for each) logs in that project's log.
Q="${dir}/other"; mkdir -p "${Q}/.swarm" "${Q}/.claude/swarm"; : > "${Q}/.claude/swarm/config"; git -C "${Q}" init -q
cp "${P}/.swarm/agents.tsv" "${Q}/.swarm/"   # so its flow runs gh (outcomes)
before="$(wc -l < "${P}/.swarm/gh-calls.tsv")"
(cd "${P}" && PATH="${dir}/stub:${PATH}" env -u HERDR_ENV SWARM_PROJECT="${Q}" SWARM_FLOW_SECTIONS=gh_calls bash "${REPO}/bin/swarm.sh" flow --since 2026-10-01 > /dev/null)
check "a command for another project logs its gh calls there, not in the cwd's" "$(wc -l < "${P}/.swarm/gh-calls.tsv")|$(cut -f3 "${Q}/.swarm/gh-calls.tsv" | sort -u)" "${before}|swarm.sh flow"

# dash's guard on gh: the shim on PATH alone is not a gh. Folders of the test's own, as a runner's
# /usr/bin may hold a gh (gh_installed runs on builtins alone).
mkdir -p "${dir}/empty"
# shellcheck disable=SC2034 # SWARM_HOME is dash.sh's
gh_on() ( SWARM_HOME="${REPO}"
  # shellcheck source=bin/lib/dash.sh
  source "${REPO}/bin/lib/dash.sh"; PATH="$1"; if gh_installed; then echo yes; else echo no; fi )
check "dash looks past gh-shim for a gh: none behind it, one behind it" "$(gh_on "${REPO}/bin/gh-shim:${dir}/empty")|$(gh_on "${REPO}/bin/gh-shim:${dir}/empty:${dir}/stub")" "no|yes"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
