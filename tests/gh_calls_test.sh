#!/usr/bin/env bash
# gh_calls_test.sh — bin/gh-shim/gh in front of a stub gh: the stub's exit code, stdout and stdin pass
# through unchanged; each call logs one line with its caller, subcommand (an API path's numbers as
# :id) and budget, and no argument past the subcommand (a token-like one checked); an unwritable log
# still runs the call. Then `swarm.sh flow`'s gh_calls section over a fixture log: calls per hour by
# role (agents.tsv's) and by subcommand, each budget apart, most first, with its share of 5000.
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
rc=0; timeout -k 2 10 env PATH="${REPO}/bin/gh-shim:${dir}/stub:${PATH}" SWARM_GH_LOG="${LOG}" SWARM_GH_CALLER=b1 STUB_RC=2 gh api --header < /dev/null > /dev/null || rc=$?
check "a flag missing its value ends the parse: gh's exit code, no hang" "${rc}" 2
check "one line per call: caller, subcommand, API path with ids collapsed, budget, exit code" "$(cut -f2- "${LOG}")" "$(printf '%s\n' \
  $'b1\tpr view\tgraphql\t3' $'b1\tapi repos/o/r/pulls/:id/comments\trest\t0' $'b1\tapi graphql\tgraphql\t0' \
  $'b1\trun view\trest\t0' $'b1\tbrowse\trest\t0' $'b1\tpr diff\trest\t0' $'b1\tpr view\tgraphql\t0' $'b1\tapi ?\trest\t2')"
check "no argument past the subcommand is logged" "$(grep -c SECRET "${LOG}" || true)" 0
check "the time is UTC, to the second" "$(cut -f1 "${LOG}" | grep -cvE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || true)" 0

rc=0; out="$(PATH="${REPO}/bin/gh-shim:${dir}/stub:${PATH}" SWARM_GH_LOG="${dir}/no/such/dir/log" gh auth status < /dev/null 2>&1)" || rc=$?
check "an unwritable log still runs the call, quietly" "${rc} ${out}" "0 args: auth status"

# A shim killed outright (a Python caller's timeout sends KILL) takes gh with it: gh never finishes.
# A simple command, not the shim function, so $! is the shim's own PID.
PATH="${REPO}/bin/gh-shim:${dir}/stub:${PATH}" STUB_SLEEP=3 STUB_MARK="${dir}/late" gh pr view 13 < /dev/null > /dev/null 2>&1 &
killed=$!
sleep 1; kill -KILL "${killed}"; wait "${killed}" 2>/dev/null || true; sleep 4
check "a shim killed outright ends gh too" "$([[ -e "${dir}/late" ]] && echo "gh finished" || echo "gh ended")" "gh ended"

# A second shim folder (an older version's) is skipped too, so two shims never call each other.
mkdir -p "${dir}/old/gh-shim"; cp "${REPO}/bin/gh-shim/gh" "${dir}/old/gh-shim/gh"
out="$(PATH="${REPO}/bin/gh-shim:${dir}/old/gh-shim:${dir}/stub:${PATH}" gh pr list < /dev/null)"
check "another gh-shim folder on PATH is skipped" "${out}" "args: pr list"

# flow's gh_calls over a fixture: b1 is a builder (code), c1 a conductor; swarm.sh's own calls keep
# their command as the caller.
P="${dir}/repo"; mkdir -p "${P}/.swarm"; git -C "${P}" init -q
printf '%s\n' $'2026-10-01\tcode\tb1\tclaude\topus\thigh\ts1' $'2026-10-01\tconduct\tc1\tclaude\topus\thigh\ts2' > "${P}/.swarm/agents.tsv"
{
  for _ in 1 2 3; do printf '2026-10-01T10:05:00Z\tb1\tpr view\tgraphql\t0\n'; done
  printf '2026-10-01T10:10:00Z\tc1\tpr checks\tgraphql\t0\n'
  printf '2026-10-01T10:20:00Z\tswarm.sh wait-pr\tapi repos/o/r/commits/:id/check-runs\trest\t0\n'
  printf '2026-10-01T11:00:00Z\tb1\tpr view\tgraphql\t1\n'
  printf '2026-09-30T10:00:00Z\tb1\tpr view\tgraphql\t0\n'   # before --since
  printf 'garbage\n'
} > "${P}/.swarm/gh-calls.tsv"
# --until keeps out flow's own gh calls (outcomes' pr list, to the stub), logged as swarm.sh flow's.
out="$(cd "${P}" && PATH="${dir}/stub:${PATH}" env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=gh_calls bash "${REPO}/bin/swarm.sh" flow --since 2026-10-01 --until 2026-10-01)"
check "flow's gh_calls: by role, then by subcommand, each budget apart, most first" "${out}" "$(printf '%s\n' "## gh_calls" \
  $'hour\tapi\trole\tcalls\tshare' \
  $'2026-10-01 10:00\tgraphql\tall\t4\t0.1%' \
  $'2026-10-01 10:00\tgraphql\tcode\t3\t0.1%' \
  $'2026-10-01 10:00\tgraphql\tconduct\t1\t0.0%' \
  $'2026-10-01 10:00\trest\tall\t1\t0.0%' \
  $'2026-10-01 10:00\trest\tswarm.sh wait-pr\t1\t0.0%' \
  $'2026-10-01 11:00\tgraphql\tall\t1\t0.0%' \
  $'2026-10-01 11:00\tgraphql\tcode\t1\t0.0%' \
  '' \
  $'hour\tapi\tsubcommand\tcalls\tshare' \
  $'2026-10-01 10:00\tgraphql\tall\t4\t0.1%' \
  $'2026-10-01 10:00\tgraphql\tpr view\t3\t0.1%' \
  $'2026-10-01 10:00\tgraphql\tpr checks\t1\t0.0%' \
  $'2026-10-01 10:00\trest\tall\t1\t0.0%' \
  $'2026-10-01 10:00\trest\tapi repos/o/r/commits/:id/check-runs\t1\t0.0%' \
  $'2026-10-01 11:00\tgraphql\tall\t1\t0.0%' \
  $'2026-10-01 11:00\tgraphql\tpr view\t1\t0.0%')"
check "swarm.sh's own gh calls log with its command as the caller" "$(tail -1 "${P}/.swarm/gh-calls.tsv" | cut -f2,4)" $'swarm.sh flow\tgraphql'

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
