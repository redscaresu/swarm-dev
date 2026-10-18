#!/usr/bin/env bash
# lead_queue_wait_test.sh — flow's lead_queue section over a fixture events.tsv (flow run with TZ=UTC so
# the local day is UTC's): a held, an escalated and an awaiting-merge item on each of two days give each
# day's median and maximum minutes, as do an impossible close and a review whose PR closed unmerged
# (reconcile reopened it). A failed reset, a close that held nothing (no held line) and a merge of one
# of an item's two PRs change nothing; the finished reconcile after the last ends its wait. A day before
# --since is left out, an item still waiting is marked open with its minutes up to now, and held_story
# logs the held line.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

P="${ROOT}/repo"; mkdir -p "${P}/.swarm"; git -C "${P}" init -q
ev() { printf '%s\t%s\t%s\tw:1\t%s\n' "$1" "$2" "$3" "${4:-ok}" >> "${P}/.swarm/events.tsv"; }
ev 2026-09-30T10:00:00Z review old
ev 2026-09-30T10:05:00Z reconcile old "ok (finished)"
# 2026-10-01: held 30, escalated 120, merge 10, reopened 6.
ev 2026-10-01T09:00:00Z close:paused z
ev 2026-10-01T10:00:00Z close:paused a
ev 2026-10-01T10:00:00Z held a "ok (paused)"
ev 2026-10-01T10:30:00Z reset:held a "ok (lifted)"
ev 2026-10-01T11:00:00Z escalated b "ok (attempts 3, 1 PRs)"
ev 2026-10-01T11:45:00Z reset b "reset: refuses a second reset"
ev 2026-10-01T13:00:00Z drop b "ok (gone)"
ev 2026-10-01T12:00:00Z review c
ev 2026-10-01T12:04:00Z merge c
ev 2026-10-01T12:09:00Z merge c
ev 2026-10-01T12:10:00Z reconcile c "ok (finished)"
ev 2026-10-01T14:00:00Z review h
ev 2026-10-01T14:06:00Z reconcile h "ok (reopened)"
# 2026-10-02: merge 45 (its first merge failed), held 60, escalated 20, impossible 55.
ev 2026-10-02T09:00:00Z review d
ev 2026-10-02T09:05:00Z merge d "the head is not green"
ev 2026-10-02T09:45:00Z reconcile d "ok (finished by its PR)"
ev 2026-10-02T10:00:00Z held e "ok (cleared-on-error)"
ev 2026-10-02T11:00:00Z story e
ev 2026-10-02T08:00:00Z escalated f "ok (attempts 3, 0 PRs)"
ev 2026-10-02T08:20:00Z reset f "ok (re-scoped)"
ev 2026-10-02T12:00:00Z close:impossible i
ev 2026-10-02T12:55:00Z drop i "ok (cannot be met)"
# 2026-10-03: still waiting.
ev 2026-10-03T12:00:00Z review g
mkdir -p "${ROOT}/bin"; printf '#!/bin/sh\nexit 1\n' > "${ROOT}/bin/gh"; chmod +x "${ROOT}/bin/gh"
out="$(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT TZ=UTC PATH="${ROOT}/bin:${PATH}" bash "${REPO}/bin/swarm.sh" flow --since 2026-10-01)"
section="$(sed -n '/^## lead_queue$/,/^$/p' <<< "${out}" | sed '/^$/d')"
check "flow prints each day's median and maximum wait" "$(sed -n 1,4p <<< "${section}")" "$(printf '%s\n' \
  "## lead_queue" $'day\titems\tmedian_min\tmax_min\topen' $'2026-10-01\t4\t20\t120\t-' $'2026-10-02\t4\t50\t60\t-')"
open="$(sed -n 5p <<< "${section}")"
check "a still-waiting item is marked open" "$(cut -f1,2,5 <<< "${open}")" $'2026-10-03\t1\tmerge:g'
mins="$(cut -f4 <<< "${open}")"
want="$(python3 -c 'import datetime as d; print(round((d.datetime.now(d.timezone.utc) - d.datetime(2026, 10, 3, 12, tzinfo=d.timezone.utc)).total_seconds() / 60))')"
check "an open item counts up to now" "$([[ "${mins}" =~ ^[0-9]+$ && ${mins} -ge $((want - 1)) && ${mins} -le ${want} ]] && echo yes)" yes

# held_story, its board writes stubbed, logs the held line the section reads.
held="$(
  PROJECT_DIR="${ROOT}/held"; SWARM_HOME="${REPO}"; BOARD="${PROJECT_DIR}/board"; mkdir -p "${PROJECT_DIR}"
  # shellcheck source=bin/lib/agents.sh
  source "${REPO}/bin/lib/agents.sh"
  # shellcheck source=bin/lib/lifecycle.sh
  source "${REPO}/bin/lib/lifecycle.sh"
  lead_block() { :; }; set_fm() { :; }
  held_story s paused "[]" >/dev/null
  cut -f2,3,5 "${EVENTS_LOG}" 2>/dev/null || true
)"
check "held_story logs held" "${held}" $'held\ts\tok (paused)'

[[ ${fails} -eq 0 ]] || { echo "${section}"; echo "${fails} failed"; exit 1; }
echo "all passed"
