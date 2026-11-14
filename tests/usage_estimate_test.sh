#!/usr/bin/env bash
# usage_estimate_test.sh — bin/lib/usage_estimate.py, the usage estimate wait --lead warns on: over fixture
# session logs under a stand-in projects directory (never the real ~/.claude/projects), the week's share and
# Fable's, calibrated against a /usage reading, with Fable weighted apart from Opus. A turn before the
# week's start is left out and a turn logged on two lines counts once. Without a reading, or with a
# malformed one (which warns), every model counts at its price alone; a 0% Fable reading keeps Fable's guess,
# and a reading of this week with no logs before it is the base the later spend adds to.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

EST="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/lib/usage_estimate.py"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
fails=0
check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# turn <time> <message id> <model> <input tokens> — one assistant line of a session log. report.py's
# PRICES put 1M input tokens at 4 USD on Opus and 10 on Fable.
turn() {
  printf '{"timestamp":"%s","type":"assistant","message":{"id":"%s","model":"%s","usage":{"input_tokens":%s,"output_tokens":0}}}\n' "$@"
}
C="${ROOT}/projects"; mkdir -p "${C}/-proj/s1/subagents"
{
  turn 2026-11-09T12:00:00.000Z old claude-opus-5-5 10000000          # before the week (from 2026-11-10 09:00)
  turn 2026-11-11T10:00:00.000Z o1 claude-opus-5-5 1000000            # 4 USD before the reading
  turn 2026-11-11T10:00:00.500Z o1 claude-opus-5-5 1000000            # the same turn's second line
  printf '{"timestamp":"2026-11-11T10:30:00.000Z","type":"user","message":{"content":"no usage here"}}\n'
  turn 2026-11-11T11:00:00.000Z f1 claude-fable-5-2 1000000           # 10 USD before the reading
  turn 2026-11-13T10:00:00.000Z o2 claude-opus-5-5 1000000            # 4 USD after it
} > "${C}/-proj/s1.jsonl"
{
  turn 2026-11-13T11:00:00.000Z f2 claude-fable-5-2 1000000                # 10 USD after it, in a subagent's log
  turn 2026-11-13T12:00:00.000Z f3 claude-fable-5-2 1000000                # and 10 more: the mix moves to Fable
} > "${C}/-proj/s1/subagents/a.jsonl"
R="${ROOT}/reading"
printf '# /usage on 2026-11-12\n2026-11-12T12:00Z 2026-11-17T09:00Z 30 20\n' > "${R}"
est() { python3 "${EST}" "${C}" --now 2026-11-14T12:00Z "$@"; }
field() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1], {"d": d}))' "$1"; }

# At the reading 4 USD on Opus and 10 on Fable gave 30% of the week and 20% of Fable's limit: Fable's limit
# is 2% per USD, Fable's weight in the week FABLE_WEEK_SHARE (0.4) of that, 0.8, and Opus's the rest of the
# 30%, (30 - 0.8 x 10) / 4 = 5.5. Now, 8 USD on Opus and 30 on Fable: 5.5 x 8 + 0.8 x 30 = 68% of the week,
# where one weighting fitted to the reading would read 30 x 38 / 14 = 81%, or, Fable at its price, 60.5%.
out="$(est --reading "${R}")"
check "the calibrated week's share" "68.0" "$(field 'd["week"]' <<< "${out}")"
check "the calibrated Fable share" "60.0" "$(field 'd["fable"]' <<< "${out}")"
check "Fable's weight in the week is fitted apart from Opus's" "0.8 5.5" "$(field '"%g %g" % (d["weight"]["fable"], d["weight"]["other"])' <<< "${out}")"
check "Fable's weight differs from Opus's" "True" "$(field 'd["weight"]["fable"] != d["weight"]["other"]' <<< "${out}")"
check "the week starts a week before the reading's reset" "2026-11-10T09:00+00:00" "$(field 'd["week_start"]' <<< "${out}")"
check "it names the reading it is calibrated on" "2026-11-12T12:00+00:00" "$(field 'd["calibrated"]' <<< "${out}")"

# Without a reading: the week from Monday 00:00 UTC (2026-11-09), so the first Opus turn counts too, and
# every model at its price against WEEK_USD (2000) and FABLE_USD (800): (40 + 8 + 30) / 20 and 30 / 8.
out="$(est)"
check "uncalibrated, the week's share counts every model at its price" "3.9" "$(field 'd["week"]' <<< "${out}")"
check "uncalibrated, Fable's share" "3.8" "$(field 'd["fable"]' <<< "${out}")"
check "uncalibrated, Fable weighs as Opus does" "True" "$(field 'd["weight"]["fable"] == d["weight"]["other"]' <<< "${out}")"
check "uncalibrated, it says so" "None" "$(field 'd["calibrated"]' <<< "${out}")"

# A 0% reading for Fable fits it no weight, so Fable keeps its guessed limit (FABLE_USD) rather than counting
# for nothing: the 20 USD on Fable since the reading add 20 / 8 = 2.5% of its limit to the 0%, and it weighs
# 0.4 x 100 / 800 = 0.05 of the week per USD.
printf '2026-11-12T12:00Z 2026-11-17T09:00Z 30 0\n' > "${R}.zero"
out="$(est --reading "${R}.zero")"
check "a 0% Fable reading keeps Fable counting" "2.5 0.05" "$(field '"%g %g" % (d["fable"], d["weight"]["fable"])' <<< "${out}")"

# A reading of this week with no logs before it (a new machine, pruned logs) is still the base: 90% and 20%,
# plus every turn since at the guessed weights, 38 / 20 and 30 / 8.
printf '2026-11-11T09:30Z 2026-11-17T09:00Z 90 20\n' > "${R}.early"
check "a reading with no logs before it is the base the spend adds to" "91.9 23.8" "$(est --reading "${R}.early" | field '"%g %g" % (d["week"], d["fable"])')"

printf '2026-11-12T12:00Z 30 20\n' > "${R}.bad"
err="$(est --reading "${R}.bad" 2>&1 > /dev/null)"
check "a malformed reading warns, naming its line" \
  "swarm: warning: ${R}.bad:1: expected '<read at> <resets at> <week %> <fable %>', so the usage estimate is uncalibrated" "${err}"
check "and the estimate is uncalibrated" "3.9" "$(est --reading "${R}.bad" 2>/dev/null | field 'd["week"]')"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
