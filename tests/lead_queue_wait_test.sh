#!/usr/bin/env bash
# lead_queue_wait_test.sh — `swarm.sh flow`'s lead_queue section against a fixture events.tsv. On
# 10-01 a is held 30 minutes, b escalated 90 and c awaits its merge 60: 3 items, median 60, max 90.
# On 10-02 d awaits its merge 10 (its failed merge does not end the wait) and e is held 50: median 30,
# max 50; g's close:paused held nothing (no held line), so its merge 120 minutes later ends no wait.
# On 10-03 at 10:00, f is escalated by close:impossible and still is on the board, so it counts up to
# now and is open; k, reviewed in the same second, waits 20; h's review has no end, but h is not on
# the board, so it is left out.
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
  $'2026-10-03T11:00:00Z\treview\th\tw:1\tok' > "${P}/.swarm/events.tsv"

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
  "${day} ${n} $(( max >= lo && max <= hi && 2 * med >= lo + 19 && 2 * med <= hi + 21 )) ${open}" "2026-10-03 2 1 escalated: f"
check "--since and --until keep the days in the window" "$(run "${P}" --since 2026-10-02 --until 2026-10-02 | lq)" \
  "${H}"$'\n2026-10-02\t2\t30\t50\t'
check "with --until in the past, a still-waiting item counts up to local midnight after it (840 minutes)" \
  "$(run "${P}" --until 2026-10-03 | lq | grep ^2026-10-03)" $'2026-10-03\t2\t430\t840\tescalated: f'

# merge = agent: n's review is the conductor's to merge, so it opens no wait; m's (costs: money, its
# story since merged and deleted from the board) waits on the user, 30 minutes.
Q="${dir}/q"; mkdir -p "${Q}/.swarm" "${Q}/.claude/swarm" "${Q}/docs/stories"; git -C "${Q}" init -q
printf 'merge = agent\n' > "${Q}/.claude/swarm/config"
G=(git -C "${Q}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
printf -- '---\nkind: code\nstatus: review\ncosts: money\n---\n' > "${Q}/docs/stories/m.md"
printf -- '---\nkind: code\nstatus: review\n---\n' > "${Q}/docs/stories/n.md"
"${G[@]}" add -A && "${G[@]}" commit -qm board && "${G[@]}" rm -q docs/stories/m.md docs/stories/n.md && "${G[@]}" commit -qm finished
mkdir -p "${Q}/docs/stories"   # the board stays, empty, as git rm took its last file
printf '%s\n' $'2026-10-01T10:00:00Z\treview\tm\tw:1\tok' $'2026-10-01T10:30:00Z\tmerge\tm\tw:1\tok' \
  $'2026-10-01T11:00:00Z\treview\tn\tw:1\tok' $'2026-10-01T11:01:00Z\tmerge\tn\tw:1\tok' > "${Q}/.swarm/events.tsv"
check "with merge = agent only a costs: money review waits on the user" "$(run "${Q}" | lq)" "${H}"$'\n2026-10-01\t1\t30\t30\t'

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
