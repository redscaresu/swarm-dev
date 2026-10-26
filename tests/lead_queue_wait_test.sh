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
# A kept line opens a kept item (ending a stale one for its slug; none for a child held by an open
# parent), which the close that kept it does not end: it is open while its story is in review with
# kept:. A later review (which opens a merge item) or held line ends it at its own time; a close --drop
# ends it at the last close once a new build, a leaving line other than a finish or reconcile, or the
# story no longer kept shows it dropped the build. A finish or reconcile (finished or reopened) ends it
# at its own time.
# No-agent items get their own table: a builder's close to its no-agent wake, a step-up:failed line or
# a review agent's failed start to theirs, each since the story's last start; an alert line with no wake
# is open while the story is ready, and a no-agent wake while a builder was started and not closed
# counts as woken while working. A refused step-up opens nothing, and an upgrade of a story's epic ends its wait.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

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

# 2026-10-04, kept items (keep_build logs kept inside the close that kept it, so that close ends
# nothing): kk is in review with kept: in board-state, so open to the midnight after --until (840);
# kr's review closes it (30) and enters merge:kr, open while kr is in review (750); kd's close --drop
# closes it (20), as kd is no longer kept; kn's close dropped nothing (gh could not list its PRs), so
# its review closes it (50); kb's close --drop closes it (15), as its next build started before the
# review of that build. kh's close paused --drop logs held before its close: the kept wait ends there
# (25) and held:kh opens, open while kh is held (455).
ev 2026-10-04T10:00:00Z kept kk "ok (https://github.com/o/r/pull/1; not reviewed)"
ev 2026-10-04T10:00:00Z close kk
ev 2026-10-04T11:00:00Z kept kr "ok (https://github.com/o/r/pull/2; not green, not reviewed)"
ev 2026-10-04T11:00:00Z close:stalled kr
ev 2026-10-04T11:30:00Z review kr "ok (https://github.com/o/r/pull/2)"
ev 2026-10-04T12:00:00Z kept kd "ok (https://github.com/o/r/pull/3; not reviewed)"
ev 2026-10-04T12:00:00Z close kd
ev 2026-10-04T12:20:00Z close kd
ev 2026-10-04T13:00:00Z kept kn "ok (https://github.com/o/r/pull/4; not reviewed)"
ev 2026-10-04T13:00:00Z close kn
ev 2026-10-04T13:10:00Z close kn
ev 2026-10-04T13:50:00Z review kn "ok (https://github.com/o/r/pull/4)"
ev 2026-10-04T14:00:00Z kept kb "ok (https://github.com/o/r/pull/5; not reviewed)"
ev 2026-10-04T14:00:00Z close kb
ev 2026-10-04T14:15:00Z close kb
ev 2026-10-04T14:40:00Z story kb
ev 2026-10-04T15:30:00Z review kb "ok (https://github.com/o/r/pull/6)"
ev 2026-10-04T16:00:00Z kept kh "ok (https://github.com/o/r/pull/7; not reviewed)"
ev 2026-10-04T16:00:00Z close kh
ev 2026-10-04T16:25:00Z held kh "ok (paused)"
ev 2026-10-04T16:25:00Z close:paused kh
story "${P}/docs" kk "status: ready"; story "${P}/docs" kr "status: review"; story "${P}/docs" kh "status: ready" "held_for: paused"
printf 'status: review\nstatus@base: ready\nkept: 2026-10-04 close (not reviewed)\n' > "${P}/.swarm/board-state/stories/kk"
check "a kept story in review is open as kept:, and a later review or close --drop ends a kept item" \
  "$(flow "${P}" --since 2026-10-04 --until 2026-10-04 | tail -1)" $'2026-10-04\t8\t40\t840\theld:kh,kept:kk,merge:kr'
# 2026-10-05: kq's first close --drop could not list its PRs (dropped nothing); the second dropped the
# build, so the kept wait ends there (20).
ev 2026-10-05T10:00:00Z kept kq "ok (https://github.com/o/r/pull/8; not reviewed)"
ev 2026-10-05T10:00:00Z close kq
ev 2026-10-05T10:10:00Z close kq
ev 2026-10-05T10:20:00Z close kq
check "a kept wait ends at the last close --drop, not one that dropped nothing" \
  "$(flow "${P}" --since 2026-10-05 --until 2026-10-05 | tail -1)" $'2026-10-05\t1\t20\t20\t-'
# 2026-10-06: kj's first close --drop dropped nothing; its close paused --drop logs held inside the
# close that drops the build, so the kept wait ends at the held line (40), not the earlier close.
ev 2026-10-06T10:00:00Z kept kj "ok (https://github.com/o/r/pull/9; not reviewed)"
ev 2026-10-06T10:00:00Z close kj
ev 2026-10-06T10:10:00Z close kj
ev 2026-10-06T10:40:00Z held kj "ok (paused)"
ev 2026-10-06T10:40:00Z close:paused kj
check "a held line inside the dropping close ends a kept wait at its own time" \
  "$(flow "${P}" --since 2026-10-06 --until 2026-10-06 | tail -1)" $'2026-10-06\t1\t40\t40\t-'
# 2026-10-07: ks was reviewed (merge:ks), sent back to ready by a close --drop (which ends no merge
# item), built again and kept: the kept line ends merge:ks (120) and opens kept:ks, open while ks is in
# review with kept: (720).
ev 2026-10-07T10:00:00Z review ks "ok (https://github.com/o/r/pull/10)"
ev 2026-10-07T10:30:00Z close ks
ev 2026-10-07T11:00:00Z story ks
ev 2026-10-07T12:00:00Z kept ks "ok (https://github.com/o/r/pull/11; not reviewed)"
ev 2026-10-07T12:00:00Z close ks
story "${P}/docs" ks "status: review" "kept: 2026-10-07 close (not reviewed)"
check "a kept line ends a stale merge item for its slug and opens kept:" \
  "$(flow "${P}" --since 2026-10-07 --until 2026-10-07 | tail -1)" $'2026-10-07\t2\t420\t720\tkept:ks'
# 2026-10-08: kc is a child a close kept while its parent kp is open (blocked, held_by: kp), which
# status and wait --lead list as blocked: its kept line opens nothing, so its later close ends nothing.
ev 2026-10-08T10:00:00Z kept kc "ok (https://github.com/o/r/pull/12; not reviewed)"
ev 2026-10-08T10:00:00Z close kc
ev 2026-10-08T10:30:00Z close kc
# kc2, kept while held, was unblocked and reviewed again: the unblock shows it was held, so its kept
# item counts nothing. kc3, kept while held, had its build dropped (blocked still, its held_by: gone):
# blocked at the end, so nothing either.
ev 2026-10-08T11:00:00Z kept kc2 "ok (https://github.com/o/r/pull/15; not reviewed)"
ev 2026-10-08T11:00:00Z close kc2
ev 2026-10-08T12:00:00Z unblock kc2
ev 2026-10-08T13:00:00Z review kc2 "ok (https://github.com/o/r/pull/15)"
ev 2026-10-08T14:00:00Z kept kc3 "ok (https://github.com/o/r/pull/16; not reviewed)"
ev 2026-10-08T14:00:00Z close kc3
ev 2026-10-08T14:30:00Z close kc3
# kc4's stale merge item (reviewed, sent back by a close --drop, rebuilt) meets a kept line while kc4
# is held: that line ends nothing either, so merge:kc4 is dropped with no end, as kc4 is not in review.
ev 2026-10-08T15:00:00Z review kc4 "ok (https://github.com/o/r/pull/17)"
ev 2026-10-08T15:30:00Z close kc4
ev 2026-10-08T16:00:00Z story kc4
ev 2026-10-08T17:00:00Z kept kc4 "ok (https://github.com/o/r/pull/18; not reviewed)"
ev 2026-10-08T17:00:00Z close kc4
story "${P}/docs" kc4 "status: blocked" "held_by: kp" "kept: 2026-10-08 close (not reviewed)"
story "${P}/docs" kc "status: blocked" "held_by: kp" "kept: 2026-10-08 close (not reviewed)"
story "${P}/docs" kc3 "status: blocked"
check "a child held by an open parent opens no kept item, held now, unblocked since or dropped" \
  "$(flow "${P}" --since 2026-10-08 --until 2026-10-08 | tail -1)" $'day\titems\tmedian_min\tmax_min\topen'
# 2026-10-10: kv was kept on an earlier build and reviewed (30); its later build is held by an open
# parent now (no kept line: review held it). That hold is the current build's, so the earlier wait counts.
ev 2026-10-10T10:00:00Z kept kv "ok (https://github.com/o/r/pull/20; not reviewed)"
ev 2026-10-10T10:00:00Z close kv
ev 2026-10-10T10:30:00Z review kv "ok (https://github.com/o/r/pull/20)"
ev 2026-10-10T11:00:00Z story kv
story "${P}/docs" kv "status: blocked" "held_by: kp" "prs: https://github.com/o/r/pull/21"
check "a kept wait on an earlier build counts though the story is held by a parent now" \
  "$(flow "${P}" --since 2026-10-10 --until 2026-10-10 | tail -1)" $'2026-10-10\t1\t30\t30\t-'
# 2026-10-09: kx's close --drop sent it back to ready, so its later drop ends the kept wait at that
# close (5); ky's close dropped nothing and its PR merged, so the finished reconcile ends it there (45);
# kz's close dropped nothing and its PR was closed by hand, so the reopening reconcile, which reopens
# only an item still in review, ends it there (60).
ev 2026-10-09T10:00:00Z kept kx "ok (https://github.com/o/r/pull/13; not reviewed)"
ev 2026-10-09T10:00:00Z close kx
ev 2026-10-09T10:05:00Z close kx
ev 2026-10-09T18:00:00Z drop kx "ok (gone)"
ev 2026-10-09T11:00:00Z kept ky "ok (https://github.com/o/r/pull/14; not reviewed)"
ev 2026-10-09T11:00:00Z close ky
ev 2026-10-09T11:10:00Z close ky
ev 2026-10-09T11:45:00Z reconcile ky "ok (finished)"
ev 2026-10-09T12:00:00Z kept kz "ok (https://github.com/o/r/pull/19; not reviewed)"
ev 2026-10-09T12:00:00Z close kz
ev 2026-10-09T12:10:00Z close kz
ev 2026-10-09T13:00:00Z reconcile kz "ok (reopened)"
check "after a close --drop, a leaving line ends a kept wait at the close; a reconcile, finished or reopened, at its own time" \
  "$(flow "${P}" --since 2026-10-09 --until 2026-10-09 | tail -1)" $'2026-10-09\t3\t45\t60\t-'

# No-agent items, under their own table. 2026-10-11: na's builder closed at 10:00 and wait --lead woke
# the lead 90 s later (1.5 minutes, 2 as the section rounds); a held line's wake (not an alert) measures nothing.
ev 2026-10-11T09:00:00Z story na
ev 2026-10-11T10:00:00Z close na
ev 2026-10-11T10:01:00Z no-agent na
ev 2026-10-11T10:01:30Z lead-woken na "ok (no-agent)"
ev 2026-10-11T10:02:00Z lead-woken z "ok (held)"
nohead=$'no_agent_day\titems\tmedian_min\tmax_min\twoken_while_working\topen'
check "a no-agent item runs from the builder's close to its wake" \
  "$(flow "${P}" --since 2026-10-11 --until 2026-10-11 | tail -2)" "${nohead}"$'\n2026-10-11\t1\t2\t2\t0\t-'
# 2026-10-12: su's step-up closed its builder with no close line and logged step-up:failed at 11:00
# (then its own failed line); woken 11:20 (20). nr's builder closed at 11:45, then its review agent
# failed to start at 12:00; woken as no-review at 12:45 (45, from the failed start, not the close), with
# no builder running. nb's builder closed at 13:00
# and was restarted at 13:05 (an ok start), closed again at 14:00 and woken at 14:03 (3). op's close
# and no-agent line have no wake and op is ready: open to the midnight after --until (510). dn's close and no-agent
# line have no wake, but dn is done; rv's too, but rv is in review, whose alert only the poll can judge;
# fin's close has no wake and no alert line; ff's first start failed, so it has no build: none of them
# is open. A story named review-na is its own, never na's review agent. The
# median of 3, 20, 45 and 510 is 32.5, shown as 32.
ev 2026-10-12T10:30:00Z story su
ev 2026-10-12T11:00:00Z step-up:failed su "ok (exit 1)"
ev 2026-10-12T11:00:01Z step-up su "failed (exit 1)"
ev 2026-10-12T11:20:00Z lead-woken su "ok (step-up failed)"
ev 2026-10-12T11:30:00Z story nr
ev 2026-10-12T11:45:00Z close nr
ev 2026-10-12T12:00:00Z review-agent nr "failed (exit 1)"
ev 2026-10-12T12:45:00Z lead-woken nr "ok (no-review)"
ev 2026-10-12T12:30:00Z story nb
ev 2026-10-12T13:00:00Z close nb
ev 2026-10-12T13:05:00Z restart nb "ok (resumed session x)"
ev 2026-10-12T14:00:00Z close nb
ev 2026-10-12T14:03:00Z lead-woken nb "ok (no-agent)"
ev 2026-10-12T15:00:00Z story op
ev 2026-10-12T15:30:00Z close op
ev 2026-10-12T15:31:00Z no-agent op
ev 2026-10-12T16:00:00Z story dn
ev 2026-10-12T16:10:00Z close dn
ev 2026-10-12T16:11:00Z no-agent dn
ev 2026-10-12T16:20:00Z story rv
ev 2026-10-12T16:30:00Z close rv
ev 2026-10-12T16:31:00Z no-agent rv
ev 2026-10-12T17:00:00Z story fin
ev 2026-10-12T17:20:00Z story ff "failed (exit 1)"
ev 2026-10-12T17:30:00Z story review-na
ev 2026-10-12T17:40:00Z close review-na
ev 2026-10-12T17:41:00Z no-agent review-na
ev 2026-10-12T17:10:00Z close fin
story "${P}/docs" op "status: ready" "kind: code"; story "${P}/docs" dn "status: done" "kind: code"; story "${P}/docs" fin "status: ready"; story "${P}/docs" rv "status: review" "kind: code"
story "${P}/docs" ff "status: ready"; story "${P}/docs" review-na "status: ready"; story "${P}/docs" na "status: done"
check "a step-up item runs from its step-up:failed line, a no-review one from its failed start, and an item since its last start" \
  "$(flow "${P}" --since 2026-10-12 --until 2026-10-12 | tail -1)" $'2026-10-12\t5\t45\t510\t0\tno-agent:op,no-agent:review-na'
# 2026-10-13: wk's builder started at 15:00 and never closed, yet a no-agent line and a wake came for
# it: one alert while its builder was working.
ev 2026-10-13T15:00:00Z story wk
ev 2026-10-13T15:10:00Z no-agent wk
ev 2026-10-13T15:11:00Z lead-woken wk "ok (no-agent)"
check "a no-agent wake while its builder was started and not closed counts as woken while working" \
  "$(flow "${P}" --since 2026-10-11 --until 2026-10-13 | tail -3 | cut -f1,5)" $'2026-10-11\t0\n2026-10-12\t0\n2026-10-13\t1'
# 2026-10-14: rs's step-up was refused before it closed its builder (a failed step-up line, no
# step-up:failed): no item. ug and ug2 each had a close and a no-agent line, then an upgrade of ug's
# epic restarted ug's agents: only ug2 (another epic) is open, from its close at 10:00 to midnight (840).
ev 2026-10-14T09:00:00Z story rs
ev 2026-10-14T09:30:00Z step-up rs "failed (exit 1)"
ev 2026-10-14T09:00:00Z story ug
ev 2026-10-14T09:00:00Z story ug2
ev 2026-10-14T10:00:00Z close ug
ev 2026-10-14T10:00:00Z close ug2
ev 2026-10-14T10:01:00Z no-agent ug
ev 2026-10-14T10:01:00Z no-agent ug2
ev 2026-10-14T10:30:00Z upgrade e1
story "${P}/docs" rs "status: ready"; story "${P}/docs" ug "status: ready" "epic: e1"; story "${P}/docs" ug2 "status: ready" "epic: e2"
check "a refused step-up opens nothing, and an upgrade of its epic ends a no-agent wait" \
  "$(flow "${P}" --since 2026-10-14 --until 2026-10-14 | tail -1)" $'2026-10-14\t1\t840\t840\t0\tno-agent:ug2'
# 2026-10-15: sc's builder closed at 10:45 with no wake, then its step-up logged step-up:failed at
# 11:00; woken 11:20: 20 minutes from the step-up:failed line, not 35 from the close.
ev 2026-10-15T09:00:00Z story sc
ev 2026-10-15T10:45:00Z close sc
ev 2026-10-15T11:00:00Z step-up:failed sc "ok (exit 1)"
ev 2026-10-15T11:20:00Z lead-woken sc "ok (step-up failed)"
check "a step-up:failed line restarts the wait an earlier close began" \
  "$(flow "${P}" --since 2026-10-15 --until 2026-10-15 | tail -1)" $'2026-10-15\t1\t20\t20\t0\t-'

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
  PROJECT_DIR="${ROOT}/held"; SWARM_HOME="${REPO}"; BOARD="${PROJECT_DIR}/board"; CFG_step_up_findings=3; CFG_top_rung_rounds=2; mkdir -p "${PROJECT_DIR}"
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
