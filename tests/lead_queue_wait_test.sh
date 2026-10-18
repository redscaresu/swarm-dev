#!/usr/bin/env bash
# lead_queue_wait_test.sh — `swarm.sh flow`'s lead_queue section against a fixture events.tsv. On
# 10-01 a is held 30 minutes, b escalated 90 and c awaits its merge 60: 3 items, median 60, max 90.
# On 10-02 d awaits its merge 10 (its failed merge does not end the wait) and e is held 50: median 30,
# max 50; g's close:paused held nothing (no held line), so its merge 120 minutes later ends no wait.
# On 10-03 at 10:00, f is escalated by close:impossible and still is on the board, so it counts up to
# now and is open; k, reviewed in the same second, waits 20; late, reviewed at 20:00, is merged 360
# minutes later, the next day. h's review has no end, but h is not on the board, so it is left out; so
# is gone's, though git still has its story in review: it was deleted from the board.
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"
mkdir -p "${P}/.swarm" "${P}/docs/stories"
git -C "${P}" init -q
printf -- '---\nkind: lead\nstatus: ready\nescalated_from: code\n---\n' > "${P}/docs/stories/f.md"
printf -- '---\nkind: code\nstatus: review\n---\n' > "${P}/docs/stories/gone.md"
GP=(git -C "${P}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
"${GP[@]}" add -A && "${GP[@]}" commit -qm board && "${GP[@]}" rm -q docs/stories/gone.md && "${GP[@]}" commit -qm gone
printf '%s\n' \
  $'2026-10-01T09:00:00Z\theld\ta\tw:1\tok (paused)' \
  $'2026-10-01T09:00:00Z\tclose:paused\ta\tw:1\tok' \
  $'2026-10-01T09:30:00Z\treset:held\ta\tw:1\tok (lifted)' \
  $'2026-10-01T10:00:00Z\tescalated\tb\tw:1\tok (attempts 2, 1 PRs)' \
  $'2026-10-01T11:30:00Z\tdrop\tb\tw:1\tok (gone)' \
  $'2026-10-01T12:00:00Z\treview\tc\tw:1\tok' \
  $'2026-10-01T13:00:00Z\tmerge\tc\tw:1\tok' \
  $'2026-10-02T07:00:00Z\tclose:paused\tg\tw:1\tok' \
  $'2026-10-02T08:00:00Z\treview\td\tw:1\tok' \
  $'2026-10-02T08:05:00Z\tmerge\td\tw:1\tthe head abc1234 is not green: pending' \
  $'2026-10-02T08:10:00Z\treconcile\td\tw:1\tok (finished by its PR)' \
  $'2026-10-02T09:00:00Z\tmerge\tg\tw:1\tok' \
  $'2026-10-02T09:00:00Z\theld\te\tw:1\tok (cleared-on-error)' \
  $'2026-10-02T09:00:00Z\tclose:cleared-on-error\te\tw:1\tok' \
  $'2026-10-02T09:50:00Z\treset\te\tw:1\tok (retry)' \
  $'2026-10-03T10:00:00Z\tclose:impossible\tf\tw:1\tok' \
  $'2026-10-03T10:00:00Z\treview\tk\tw:1\tok' \
  $'2026-10-03T10:20:00Z\tmerge\tk\tw:1\tok' \
  $'2026-10-03T11:00:00Z\treview\th\tw:1\tok' \
  $'2026-10-03T12:00:00Z\treview\tgone\tw:1\tok' \
  $'2026-10-03T20:00:00Z\treview\tlate\tw:1\tok' \
  $'2026-10-04T02:00:00Z\tmerge\tlate\tw:1\tok' > "${P}/.swarm/events.tsv"

# A section that raises makes flow exit 1: its output still goes to the checks.
run() { (cd "${1}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${SWARM}" flow "${@:2}") || true; }
lq() { awk '/^## / { f = $0 == "## lead_queue"; next } f'; } # flow's lead_queue section
mins() { python3 -c 'import datetime, time; print(round((time.time() - datetime.datetime(2026, 10, 3, 10, tzinfo=datetime.timezone.utc).timestamp()) / 60))'; }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
H=$'day\titems\tmedian_min\tmax_min\topen'
lo="$(mins)"; out="$(run "${P}" 2>&1 | lq)"; hi="$(mins)"
check "per day: held, escalated and awaiting-merge items give the median and the max; a close that held nothing opens no wait" \
  "$(head -3 <<< "${out}")" "${H}"$'
2026-10-01\t3\t60\t90\t
2026-10-02\t2\t30\t50\t'
IFS=$'\t' read -r day n med max open <<< "$(sed -n 4p <<< "${out}")"
check "a still-waiting item counts up to now and is marked open, beside an item that entered in the same second; one off the board is left out" \
  "${day} ${n} $(( max >= lo && max <= hi )) ${med} ${open}" "2026-10-03 3 1 360 escalated: f"
check "a story deleted from the board with no end line is not open, though git has it in review" "$(grep -c gone <<< "${out}" || true)" 0
check "--since and --until keep the days in the window" "$(run "${P}" --since 2026-10-02 --until 2026-10-02 | lq)" \
  "${H}"$'\n2026-10-02\t2\t30\t50\t'
check "with --until in the past, a still-waiting item and one that left after it count up to local midnight after it (840 and 240 minutes), and both are open" \
  "$(run "${P}" --until 2026-10-03 | lq | grep ^2026-10-03)" $'2026-10-03\t3\t240\t840\tescalated: f, merge: late'

# merge = agent: n's review is the conductor's to merge, so it opens no wait; m's (costs: money, its
# story since merged and deleted from the board) waits on the user, 30 minutes.
Q="${dir}/q"; mkdir -p "${Q}/.swarm" "${Q}/.claude/swarm" "${Q}/docs/stories"; git -C "${Q}" init -q
printf 'merge = agent\n' > "${Q}/.claude/swarm/config"
G=(git -C "${Q}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
printf -- '---\nkind: code\nstatus: review\ncosts: money\n---\n' > "${Q}/docs/stories/m.md"
printf -- '---\nkind: code\nstatus: review\n---\n' > "${Q}/docs/stories/n.md"
"${G[@]}" add -A && "${G[@]}" commit -qm board && "${G[@]}" rm -q docs/stories/m.md docs/stories/n.md && "${G[@]}" commit -qm finished
# On 10-02, costs: None, [none] and "none" are none, as costs_value reads them, and a "- Money" list is
# money: only p waits, 40 minutes.
mkdir -p "${Q}/docs/stories"   # git rm took the board's last file
for c in o1:None 'o2:[none]' o3:'"none"'; do printf -- '---\nkind: code\nstatus: review\ncosts: %s\n---\n' "${c#*:}" > "${Q}/docs/stories/${c%%:*}.md"; done
printf -- '---\nkind: code\nstatus: review\ncosts:\n  - Money\n---\n' > "${Q}/docs/stories/p.md"
{ printf '%s\n' $'2026-10-01T10:00:00Z\treview\tm\tw:1\tok' $'2026-10-01T10:30:00Z\tmerge\tm\tw:1\tok' \
    $'2026-10-01T11:00:00Z\treview\tn\tw:1\tok' $'2026-10-01T11:01:00Z\tmerge\tn\tw:1\tok' \
    $'2026-10-02T10:00:00Z\treview\tp\tw:1\tok' $'2026-10-02T10:40:00Z\tmerge\tp\tw:1\tok'
  for o in o1 o2 o3; do printf '%s\n' "2026-10-02T11:00:00Z"$'\treview\t'"${o}"$'\tw:1\tok' "2026-10-02T11:05:00Z"$'\tmerge\t'"${o}"$'\tw:1\tok'; done
} > "${Q}/.swarm/events.tsv"
qout="$(run "${Q}" | lq)"
check "with merge = agent only a costs: money review waits on the user" "$(head -2 <<< "${qout}")" "${H}"$'\n2026-10-01\t1\t30\t30\t'
check "costs: None, [none] and \"none\" are none and a \"- Money\" list is money, as costs_value reads them" \
  "$(sed -n 3p <<< "${qout}")" $'2026-10-02\t1\t40\t40\t'

# board_dir as load_config reads it: a leading ~ is HOME, a space stays in the path, a # comment goes.
R="${dir}/r"; mkdir -p "${R}/.swarm" "${R}/.claude/swarm" "${dir}/home/lq board/stories"; git -C "${R}" init -q
printf 'board_dir = ~/lq board   # the shared board\n' > "${R}/.claude/swarm/config"
printf -- '---\nkind: lead\nstatus: ready\nescalated_from: code\n---\n' > "${dir}/home/lq board/stories/r.md"
printf '%s\n' $'2026-10-01T10:00:00Z\tescalated\tr\tw:1\tok' > "${R}/.swarm/events.tsv"
check "board_dir = ~/lq board: the board under HOME, with its space, shows r still escalated" \
  "$(HOME="${dir}/home" run "${R}" --until 2026-10-01 | lq | sed -n 2p)" $'2026-10-01\t1\t840\t840\tescalated: r'

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
