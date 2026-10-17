#!/usr/bin/env bash
# lead_queue_wait_test.sh — `swarm.sh flow`'s lead_queue section against a fixture events.tsv. On
# 10-01 a is held 30 minutes, b escalated 90 and c awaits its merge 60: 3 items, median 60, max 90.
# On 10-02 d awaits its merge 10 (its failed merge does not end the wait) and e is held 50: median 30,
# max 50. f, escalated on 10-03 by close:impossible, still waits, so it counts up to now and is open.
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"
mkdir -p "${P}/.swarm"
git -C "${P}" init -q
printf '%s\n' \
  $'2026-10-01T09:00:00Z\tclose:paused\ta\tw:1\tok' \
  $'2026-10-01T09:30:00Z\treset:held\ta\tw:1\tok (lifted)' \
  $'2026-10-01T10:00:00Z\tescalated\tb\tw:1\tok (attempts 2, 1 PRs)' \
  $'2026-10-01T11:30:00Z\tdrop\tb\tw:1\tok (gone)' \
  $'2026-10-01T12:00:00Z\treview\tc\tw:1\tok' \
  $'2026-10-01T13:00:00Z\tmerge\tc\tw:1\tok' \
  $'2026-10-02T08:00:00Z\treview\td\tw:1\tok' \
  $'2026-10-02T08:05:00Z\tmerge\td\tw:1\tthe head abc1234 is not green: pending' \
  $'2026-10-02T08:10:00Z\treconcile\td\tw:1\tok (finished by its PR)' \
  $'2026-10-02T09:00:00Z\tclose:cleared-on-error\te\tw:1\tok' \
  $'2026-10-02T09:50:00Z\treset\te\tw:1\tok (retry)' \
  $'2026-10-03T10:00:00Z\tclose:impossible\tf\tw:1\tok' > "${P}/.swarm/events.tsv"

run() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${SWARM}" flow "$@"); }
lq() { awk '/^## / { f = $0 == "## lead_queue"; next } f'; } # flow's lead_queue section
mins() { python3 -c 'import datetime, time; print(round((time.time() - datetime.datetime(2026, 10, 3, 10, tzinfo=datetime.timezone.utc).timestamp()) / 60))'; }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
H=$'day\titems\tmedian_min\tmax_min\topen'
lo="$(mins)"; out="$(run | lq)"; hi="$(mins)"
check "per day: held, escalated and awaiting-merge items give the median and the max" "$(head -3 <<< "${out}")" "${H}"$'
2026-10-01\t3\t60\t90\t
2026-10-02\t2\t30\t50\t'
IFS=$'\t' read -r day n med max open <<< "$(sed -n 4p <<< "${out}")"
check "a still-waiting item counts up to now and is marked open" \
  "${day} ${n} $(( med == max && max >= lo && max <= hi )) ${open}" "2026-10-03 1 1 escalated: f"
check "--since and --until keep the days in the window" "$(run --since 2026-10-02 --until 2026-10-02 | lq)" \
  "${H}"$'\n2026-10-02\t2\t30\t50\t'

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
