#!/usr/bin/env bash
# lead_queue_wait_test.sh — flow's lead_queue section over fixture events.tsv files (flow run with TZ=UTC
# so the local day is UTC's). A held, an escalated and an awaiting-merge item on each of two days give
# each day's median and maximum minutes, as do an impossible close and a review whose PR closed unmerged
# (reconcile reopened it). A failed reset, a close that held nothing (no held line) and a merge of one
# of an item's two PRs change nothing; the finished reconcile after the last ends its wait. A day before
# --since is left out. An item with no leaving line is open while board-state has its story in review
# (counted up to now, or to midnight after --until), and dropped once its story is gone from the board,
# though git still has it; one that left after --until is open there; an open and a closed item that
# entered in the same second both count. With merge = agent (board_dir under ~, with a space), only a
# review of a story whose costs: is not none (any case, brackets or quotes, a block list, or a deleted
# story's last version, or HEAD's; an unreadable story is money, an epic never) counts. held_story logs the held line.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
mkdir -p "${ROOT}/bin"; printf '#!/bin/sh\nexit 1\n' > "${ROOT}/bin/gh"; chmod +x "${ROOT}/bin/gh"
# flow <project> [flags] — flow's lead_queue section, its blank line dropped.
flow() {
  (cd "$1" && env -u HERDR_ENV -u SWARM_PROJECT TZ=UTC HOME="${ROOT}/home" PATH="${ROOT}/bin:${PATH}" \
    bash "${REPO}/bin/swarm.sh" flow "${@:2}") | sed -n '/^## lead_queue$/,/^$/p' | sed '/^$/d'
}
# story <board> <slug> <front matter line>... — a story file.
story() { mkdir -p "$1/stories"; printf -- '---\n%s\n---\n\n# %s\n' "$(printf '%s\n' "${@:3}")" "$2" > "$1/stories/$2.md"; }
commit() { git -C "$1" add -A && git -C "$1" -c user.name=t -c user.email=t@t commit -qm "$2"; }

P="${ROOT}/repo"; mkdir -p "${P}/.swarm"; git -C "${P}" init -q
ev() { printf '%s\t%s\t%s\tw:1\t%s\n' "$1" "$2" "$3" "${4:-ok}" >> "${E}"; }
E="${P}/.swarm/events.tsv"
ev 2026-09-30T10:00:00Z review old
ev 2026-09-30T10:05:00Z reconcile old "ok (finished)"
# 2026-10-01: held 30, escalated 120, merge 40, reopened 6, merge 360 (left after 2026-10-01); z's
# close held nothing, so its build ends no wait.
ev 2026-10-01T09:00:00Z close:paused z
ev 2026-10-01T09:30:00Z story z
ev 2026-10-01T10:00:00Z close:paused a
ev 2026-10-01T10:00:00Z held a "ok (paused)"
ev 2026-10-01T10:30:00Z reset:held a "ok (lifted)"
ev 2026-10-01T11:00:00Z escalated b "ok (attempts 3, 1 PRs)"
ev 2026-10-01T11:45:00Z reset b "reset: refuses a second reset"
ev 2026-10-01T13:00:00Z drop b "ok (gone)"
ev 2026-10-01T12:00:00Z review c
ev 2026-10-01T12:05:00Z merge c
ev 2026-10-01T12:39:00Z merge c
ev 2026-10-01T12:40:00Z reconcile c "ok (finished)"
ev 2026-10-01T14:00:00Z review h
ev 2026-10-01T14:06:00Z reconcile h "ok (reopened)"
ev 2026-10-01T23:00:00Z review k
ev 2026-10-02T05:00:00Z reconcile k "ok (finished)"
# 2026-10-02: merge 45 (its first merge failed), held 60, escalated 20, impossible 55.
ev 2026-10-02T09:00:00Z review d
ev 2026-10-02T09:05:00Z merge d "the head is not green"
ev 2026-10-02T09:45:00Z reconcile d "ok (finished by its PR)"
ev 2026-10-02T10:00:00Z held e "ok (cleared-on-error)"
ev 2026-10-02T11:00:00Z reset:held e "ok (lifted)"
ev 2026-10-02T11:05:00Z story e
ev 2026-10-02T08:00:00Z escalated f "ok (attempts 3, 0 PRs)"
ev 2026-10-02T08:20:00Z reset f "ok (re-scoped)"
ev 2026-10-02T12:00:00Z close:impossible i
ev 2026-10-02T12:55:00Z drop i "ok (cannot be met)"
# 2026-10-03: g still waiting (in review in board-state), s closed in the same second, gone deleted.
ev 2026-10-03T12:00:00Z review g
ev 2026-10-03T12:00:00Z review s
ev 2026-10-03T12:10:00Z reconcile s "ok (finished)"
ev 2026-10-03T13:00:00Z review gone
story "${P}/docs" g "status: ready"
mkdir -p "${P}/.swarm/board-state/stories"; printf 'status: review\nstatus@base: ready\n' > "${P}/.swarm/board-state/stories/g"
story "${P}/docs" gone "status: review"; commit "${P}" "add gone"
git -C "${P}" rm -q docs/stories/gone.md; commit "${P}" "remove gone"

section="$(flow "${P}" --since 2026-10-01)"
check "flow prints each day's median and maximum wait" "$(sed -n 1,4p <<< "${section}")" "$(printf '%s\n' \
  "## lead_queue" $'day\titems\tmedian_min\tmax_min\topen' $'2026-10-01\t5\t40\t360\t-' $'2026-10-02\t4\t50\t60\t-')"
open="$(sed -n 5p <<< "${section}")"
check "a still-waiting item is marked open, a deleted one dropped" "$(cut -f1,2,5 <<< "${open}")" $'2026-10-03\t2\tmerge:g'
mins="$(cut -f4 <<< "${open}")"
want="$(python3 -c 'import datetime as d; print(round((d.datetime.now(d.timezone.utc) - d.datetime(2026, 10, 3, 12, tzinfo=d.timezone.utc)).total_seconds() / 60))')"
check "an open item counts up to now" "$([[ "${mins}" =~ ^[0-9]+$ && ${mins} -ge $((want - 1)) && ${mins} -le ${want} ]] && echo yes)" yes
check "with --until, an open item counts to the midnight after it" "$(flow "${P}" --since 2026-10-03 --until 2026-10-03 | tail -1)" \
  $'2026-10-03\t2\t365\t720\tmerge:g'
check "with --until, an item that left after it is open there" "$(flow "${P}" --since 2026-10-01 --until 2026-10-01 | tail -1)" \
  $'2026-10-01\t5\t40\t120\tmerge:k'

# merge = agent, the board at "~/my board": m (costs: [Money]) 30, o (deleted, a block list of money) 20,
# held q 50, u (in neither the board nor git, so money) 10; n (costs: "None"), p (no costs:), r (gone
# from the checkout, HEAD's costs: none) and the epic ep are not the lead's.
A="${ROOT}/agent"; B="${ROOT}/home/my board"; mkdir -p "${A}/.claude/swarm" "${A}/.swarm" "${B}"; git -C "${B}" init -q
printf 'board_dir = ~/my board\nmerge = agent  # agents merge\n' > "${A}/.claude/swarm/config"
story "${B}" m "costs: [Money]"; story "${B}" n 'costs: "None"'; story "${B}" p "status: ready"
story "${B}" o "costs:" "  - money  # a cloud bill"; story "${B}" r "costs: none"; commit "${B}" "add"
git -C "${B}" rm -q stories/o.md; commit "${B}" "remove o"; rm "${B}/stories/r.md"
mkdir -p "${B}/epics"; printf -- '---\nstatus: review\n---\n' > "${B}/epics/ep.md"
E="${A}/.swarm/events.tsv"
ev 2026-10-01T10:00:00Z review m
ev 2026-10-01T10:30:00Z reconcile m "ok (finished)"
ev 2026-10-01T11:00:00Z review n
ev 2026-10-01T11:05:00Z reconcile n "ok (finished)"
ev 2026-10-01T12:00:00Z review o
ev 2026-10-01T12:20:00Z reconcile o "ok (finished)"
ev 2026-10-01T13:00:00Z review p
ev 2026-10-01T13:01:00Z reconcile p "ok (finished)"
ev 2026-10-01T14:00:00Z held q "ok (paused)"
ev 2026-10-01T14:50:00Z reset:held q "ok (lifted)"
ev 2026-10-01T15:00:00Z review r
ev 2026-10-01T15:40:00Z reconcile r "ok (finished)"
ev 2026-10-01T16:00:00Z review u
ev 2026-10-01T16:10:00Z reconcile u "ok (finished)"
ev 2026-10-01T17:00:00Z review ep
ev 2026-10-01T17:05:00Z reconcile ep "ok (finished)"
check "with merge = agent only reviews that cost money count" "$(flow "${A}" --since 2026-10-01 | tail -1)" $'2026-10-01\t4\t25\t50\t-'

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
