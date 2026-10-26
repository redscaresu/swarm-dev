#!/usr/bin/env bash
# test_cap_test.sh — ~/.swarm/test-cap caps the top-level make test runs that go at once on a
# machine, HOME here being a temp dir. With no cap file a run passes and makes nothing under
# ~/.swarm; an empty file or 0 is no cap either, and anything else, a number too big for bash
# included, stops the run before any test. With a cap of 1, two runs started together from two
# projects never overlap. A run that finds the slot held by a live run says it waits, naming that
# run's PID and slot, starts no perl while it is blocked, and starts its test only once that run has
# ended, though its TZ is not the holder's; so does a top-level run with TEST_RUNS_LOG set empty. A
# slot whose PID is dead or taken by another process since, an empty one and one holding only a
# hidden file are taken at once; one that is a file, or that the run cannot read or clear, stops the
# run, naming it. A live run whose path holds " --one " still holds its slot. A run that loses the
# take twice runs all the same, saying nothing, and one that loses it once and then finds the slot
# held names the real holder. A gone run's .new.<pid> is removed, and an interrupted run frees its slot. And every
# tests/*_test.sh that starts a top-level run (TEST_RUNS_LOG unset or set to a file, or TEST_SH_PID
# unset) exports HOME under its own mktemp root, so a cap in the real HOME never gates it.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
pids=()
trap 'for p in "${pids[@]+"${pids[@]}"}"; do kill "${p}" 2>/dev/null || true; done; { wait; } 2>/dev/null; chmod -R u+rwx "${ROOT}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
export HOME="${ROOT}/home"
mkdir -p "${HOME}"
fails=0 fin=""
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# start <project> <out> <file>... — scripts/test.sh on the files from <project>, a top-level run (no
# TEST_SH_PID) that logs to that project's own .swarm/test-runs.tsv, or to RUNLOG when set, even
# empty; in the background, its output in <out>; $! is its PID.
start() {
  local p="${ROOT}/$1" out="$2"
  shift 2
  mkdir -p "${p}"
  (cd "${p}" && exec env -u TEST_SH_PID TEST_RUNS_LOG="${RUNLOG-${p}/.swarm/test-runs.tsv}" JOBS=2 bash "${REPO}/scripts/test.sh" "$@" > "${out}" 2>&1) &
}
# finish <pid> — set fin to that run's exit status, or to "hung" (and stop it) when it runs past 30 s.
# Not in a $(...): only the shell that started the run can wait for it.
finish() {
  local i
  for ((i = 0; i < 300; i++)); do
    kill -0 "$1" 2>/dev/null || { wait "$1" && fin=0 || fin=$?; return 0; }
    sleep 0.1
  done
  kill "$1" 2>/dev/null; wait "$1" 2>/dev/null || true; fin=hung
}
# until_there <grep -E pattern> <file> — wait for a line that matches, 30 s at most. soon — the same,
# failing quietly, where the check after it says what went wrong.
until_there() { for _ in $(seq 300); do grep -qE "$1" "$2" 2>/dev/null && return 0; sleep 0.1; done; echo "FAIL no '$1' in $2"; exit 1; }
soon() { for _ in $(seq 300); do grep -qE "$1" "$2" 2>/dev/null && return 0; sleep 0.1; done; return 1; }
slots="${HOME}/.swarm/test-slots"
# plant [pid] — slot 1 naming that PID (a directory with a file named by it, holding a start time
# long past), or empty with none, over whatever an earlier case that failed left.
plant() { rm -rf "${slots}/1"; mkdir -p "${slots}/1"; [[ -z "${1:-}" ]] || echo "Thu Jan  1 00:00:00 1970" > "${slots}/1/$1"; }
# hold <name> <go> — a test that writes "start <name>", holds until <go> is there (30 s at most), then
# writes "end <name>". mark <name> — one that writes <name>.
# shellcheck disable=SC2016 # the stubs' own shell expands these
hold() { printf '#!/usr/bin/env bash\necho "start %s" >> "%s/order"\nfor _ in $(seq 300); do [ -e "%s" ] && break; sleep 0.1; done\necho "end %s" >> "%s/order"\n' "$1" "${ROOT}" "$2" "$1" "${ROOT}" > "${ROOT}/$1_test.sh"; }
mark() { printf '#!/usr/bin/env bash\necho "%s" >> "%s/order"\n' "$1" "${ROOT}" > "${ROOT}/$1_test.sh"; }
# A perl first on a run's PATH: it logs each call to PERL_LOG; while LOSE_FILE counts above 0 it
# counts down and fails, as a take that lost a race does, first writing LOSE_MARK and waiting for
# LOSE_UNTIL to hold something (30 s at most) when they are set; else it is the real perl.
REAL_PERL="$(command -v perl)"; export REAL_PERL
mkdir -p "${ROOT}/fakeperl"
cat > "${ROOT}/fakeperl/perl" <<'STUB'
#!/usr/bin/env bash
[ -z "${PERL_LOG:-}" ] || echo call >> "${PERL_LOG}"
n="$(cat "${LOSE_FILE:-/dev/null}" 2>/dev/null)"
if [ "${n:-0}" -gt 0 ]; then
  echo $((n - 1)) > "${LOSE_FILE}"
  if [ -n "${LOSE_MARK:-}" ]; then
    echo lost > "${LOSE_MARK}"
    for _ in $(seq 300); do [ -n "$(ls -A "${LOSE_UNTIL}" 2>/dev/null)" ] && break; sleep 0.1; done
  fi
  exit 1
fi
exec "${REAL_PERL}" "$@"
STUB
chmod +x "${ROOT}/fakeperl/perl"
FAKE_PATH="${ROOT}/fakeperl:${PATH}"
# left — what is left in the slots dir, hidden entries too, or empty.
left() {
  local f out=""
  [[ -d "${slots}" ]] || { echo "no slots dir"; return 0; }
  for f in "${slots}"/* "${slots}"/.[!.]*; do [[ -e "${f}" ]] && out+="${f##*/} "; done
  echo "${out:-empty}"
}

printf '#!/usr/bin/env bash\nexit 0\n' > "${ROOT}/pass_test.sh"
start p0 "${ROOT}/p0.out" "${ROOT}/pass_test.sh"; finish $!
check "with no cap file a run passes and makes nothing under ~/.swarm" "${fin}|$(ls -A "${HOME}")" "0|"

# capped <value> — with the cap file holding <value> (none at all for ''): "no cap" when a run passes
# and makes no slots dir, "refused" when it exits 1 saying why before its test runs.
capped() {
  mkdir -p "${HOME}/.swarm"
  if [[ -z "$1" ]]; then : > "${HOME}/.swarm/test-cap"; else printf '%s\n' "$1" > "${HOME}/.swarm/test-cap"; fi
  start p0 "${ROOT}/p0.out" "${ROOT}/pass_test.sh"; finish $!
  if [[ "${fin}" == 0 && ! -e "${slots}" ]]; then echo "no cap"
  elif [[ "${fin}" == 1 ]] && grep -qF "test-cap holds '$1', not a whole number" "${ROOT}/p0.out" && ! grep -q '^run ' "${ROOT}/p0.out"; then echo refused
  else echo "${fin}: $(cat "${ROOT}/p0.out")"; fi
}
check "an empty cap file and 0 are no cap; x, -1, 01, 1.5, 1 2 and 2^63 are refused before any test runs" \
  "$(capped '')|$(capped 0)|$(capped x)|$(capped -1)|$(capped 01)|$(capped 1.5)|$(capped '1 2')|$(capped 9223372036854775808)" \
  "no cap|no cap|refused|refused|refused|refused|refused|refused"

echo 1 > "${HOME}/.swarm/test-cap"
# Two runs started together from two projects: whichever starts its test first writes start, holds
# until the other run says it waits (20 s at most), then writes end.
# shellcheck disable=SC2016 # the stub's own shell expands it
printf '#!/usr/bin/env bash\necho start >> "%s/order"\nfor _ in $(seq 200); do grep -qs waiting "%s/p1.out" "%s/p2.out" && break; sleep 0.1; done\necho end >> "%s/order"\n' \
  "${ROOT}" "${ROOT}" "${ROOT}" "${ROOT}" > "${ROOT}/turn_test.sh"
start p1 "${ROOT}/p1.out" "${ROOT}/turn_test.sh"; r1=$!; pids+=("${r1}")
start p2 "${ROOT}/p2.out" "${ROOT}/turn_test.sh"; r2=$!; pids+=("${r2}")
finish "${r1}"; f1="${fin}"; finish "${r2}"; f2="${fin}"
check "with a cap of 1, two runs started together from two projects never overlap, one waiting, and leave no slot" \
  "$(tr '\n' ' ' < "${ROOT}/order")|${f1} ${f2}|$(cat "${ROOT}/p1.out" "${ROOT}/p2.out" | grep -c '^test.sh: waiting for a slot')|$(left)" \
  "start end start end |0 0|1|empty"

# A slot held by a live run H: W says it waits, naming H's PID and slot, starts no perl while it is
# blocked, and starts its test only after H has ended, though its TZ is not H's. W2, a top-level run
# with TEST_RUNS_LOG set empty, waits the same.
: > "${ROOT}/order"
hold H "${ROOT}/goH"; mark W; mark W2
TZ=UTC start p3 "${ROOT}/h.out" "${ROOT}/H_test.sh"; rh=$!; pids+=("${rh}")
until_there '^start H$' "${ROOT}/order"
# W's COLUMNS is narrow: procps' ps cuts a command line there unless told not to.
TZ=Asia/Tokyo COLUMNS=20 PATH="${FAKE_PATH}" PERL_LOG="${ROOT}/w.perl" start p4 "${ROOT}/w.out" "${ROOT}/W_test.sh"; rw=$!; pids+=("${rw}")
RUNLOG='' start p5 "${ROOT}/w2.out" "${ROOT}/W2_test.sh"; rw2=$!; pids+=("${rw2}")
soon '^test.sh: waiting' "${ROOT}/w.out" || true
soon '^test.sh: waiting' "${ROOT}/w2.out" || true
sleep 2   # two polls, so a run that only said it waits would have started its test by now
before="$(tr '\n' ' ' < "${ROOT}/order")|$(if [[ -e "${ROOT}/w.perl" ]]; then wc -l < "${ROOT}/w.perl" | tr -d ' '; else echo 0; fi)"
waits="test.sh: waiting for a slot, as ${HOME}/.swarm/test-cap allows 1 run(s) at once: PID ${rh} holds ${slots}/1. A slot frees when its run ends; to free one by hand, rm -r it."
touch "${ROOT}/goH"
finish "${rh}"; fh="${fin}"; finish "${rw}"; fw="${fin}"; finish "${rw2}"; fw2="${fin}"
# after <name> — yes when <name>'s line comes after "end H".
after() { awk -v n="$1" '$0 == "end H" { e = NR } $0 == n { w = NR } END { print (e && w > e) ? "yes" : "no" }' "${ROOT}/order"; }
check "a slot held by a live run: the run says it waits, naming the run and its slot, starts no perl while blocked, and runs its test only after that run ends" \
  "$(head -1 "${ROOT}/w.out")|${before}|${fh} ${fw}|$(after W)" "${waits}|start H |0|0 0|yes"
check "a top-level run with TEST_RUNS_LOG set empty waits on the cap too" "$(head -1 "${ROOT}/w2.out")|${fw2}|$(after W2)|$(left)" "${waits}|0|yes|empty"

# A slot whose PID is dead is taken back at once: no wait, and nothing left behind, not even aside.
sleep 0 & dead=$!; wait "${dead}"
plant "${dead}"
start p6 "${ROOT}/p6.out" "${ROOT}/pass_test.sh"; finish $!
check "a slot whose PID is dead is taken back: the run passes without waiting and leaves no slot" \
  "${fin}|$(grep -c waiting "${ROOT}/p6.out")|$(left)" "0|0|empty"
# So is one whose PID another process has taken since (here a sleep), which started later.
sleep 60 & other=$!; pids+=("${other}")
plant "${other}"
start p6 "${ROOT}/p6.out" "${ROOT}/pass_test.sh"; finish $!
check "a slot whose PID another process has taken since is taken: the run passes without waiting" \
  "${fin}|$(grep -c waiting "${ROOT}/p6.out")|$(left)|$(kill -0 "${other}" 2>/dev/null && echo "sleep alive")" "0|0|empty|sleep alive"
# An empty slot (a run killed while freeing its slot leaves one), and one holding only a hidden file.
plant
start p6 "${ROOT}/p6.out" "${ROOT}/pass_test.sh"; finish $!
o="${fin}|$(grep -c waiting "${ROOT}/p6.out")|$(left)"
plant; : > "${slots}/1/.DS_Store"
start p6 "${ROOT}/p6.out" "${ROOT}/pass_test.sh"; finish $!
check "an empty slot, and one holding only a hidden file, are taken: each run passes without waiting and leaves no slot" \
  "${o} ${fin}|$(grep -c waiting "${ROOT}/p6.out")|$(left)" "0|0|empty 0|0|empty"

# A slot that is no directory (here a file) cannot be taken: the run stops, naming it and its removal.
rm -rf "${slots}/1"; : > "${slots}/1"
start p7 "${ROOT}/p7.out" "${ROOT}/pass_test.sh"; finish $!
check "a slot that is a file stops the run with an error naming the slot and how to remove it, and runs no test" \
  "${fin}|$(cat "${ROOT}/p7.out")" "1|test.sh: ${slots}/1 is no slot this run can use (a directory it can read and write); remove it by hand: rm -r '${slots}/1'"
rm -f "${slots}/1"
# So does one it cannot read (mode 0300, a dead PID inside), and one holding what it cannot remove.
plant "${dead}"; chmod 0300 "${slots}/1"
start p7 "${ROOT}/p7.out" "${ROOT}/pass_test.sh"; finish $!
o="${fin}|$(cat "${ROOT}/p7.out")"
chmod 0700 "${slots}/1"; plant; mkdir "${slots}/1/junk"; : > "${slots}/1/junk/f"; chmod 0500 "${slots}/1/junk"
start p7 "${ROOT}/p7.out" "${ROOT}/pass_test.sh"; finish $!
check "a slot it cannot read, or cannot clear, stops the run with an error naming the slot" "${o} ${fin}|$(cat "${ROOT}/p7.out")" \
  "1|test.sh: ${slots}/1 is no slot this run can use (a directory it can read and write); remove it by hand: rm -r '${slots}/1' 1|test.sh: cannot clear ${slots}/1 of what a gone run left there; remove it by hand: rm -r '${slots}/1'"
chmod 0700 "${slots}/1/junk"; rm -rf "${slots}/1"

# A run that loses the take twice (a run took or freed the slot between its look and its rename)
# looks again and runs, saying nothing of waiting.
echo 2 > "${ROOT}/lose"
PATH="${FAKE_PATH}" LOSE_FILE="${ROOT}/lose" start p8 "${ROOT}/p8.out" "${ROOT}/pass_test.sh"; finish $!
check "a run that loses the take twice in a row still runs, and prints no waiting line" \
  "${fin}|$(cat "${ROOT}/lose")|$(grep -c waiting "${ROOT}/p8.out")|$(left)" "0|0|0|empty"
# One that loses it once, H2 taking the slot meanwhile, then finds it held: one waiting line, naming H2.
echo 1 > "${ROOT}/lose"; : > "${ROOT}/order"; hold H2 "${ROOT}/goH2"
PATH="${FAKE_PATH}" LOSE_FILE="${ROOT}/lose" LOSE_MARK="${ROOT}/lost" LOSE_UNTIL="${slots}/1" start p9 "${ROOT}/p9.out" "${ROOT}/pass_test.sh"; rl=$!; pids+=("${rl}")
until_there '^lost$' "${ROOT}/lost"
start p10 "${ROOT}/h2.out" "${ROOT}/H2_test.sh"; rh2=$!; pids+=("${rh2}")
until_there '^test.sh: waiting' "${ROOT}/p9.out"
said="$(cat "${ROOT}/p9.out")"
touch "${ROOT}/goH2"; finish "${rh2}"; finish "${rl}"
check "a run that loses the take once and then finds the slot held says it waits once, naming the real holder" \
  "${said}|${fin}" "test.sh: waiting for a slot, as ${HOME}/.swarm/test-cap allows 1 run(s) at once: PID ${rh2} holds ${slots}/1. A slot frees when its run ends; to free one by hand, rm -r it.|0"

# A live run whose test path holds " --one ", as its jobs' command lines do, still holds its slot.
mkdir -p "${ROOT}/a --one b"; : > "${ROOT}/order"
# shellcheck disable=SC2016 # the stub's own shell expands it
printf '#!/usr/bin/env bash\necho "start H3" >> "%s/order"\nfor _ in $(seq 300); do [ -e "%s/goH3" ] && break; sleep 0.1; done\n' "${ROOT}" "${ROOT}" > "${ROOT}/a --one b/h3_test.sh"
start p13 "${ROOT}/h3.out" "${ROOT}/a --one b/h3_test.sh"; rh3=$!; pids+=("${rh3}")
until_there '^start H3$' "${ROOT}/order"
start p14 "${ROOT}/w3.out" "${ROOT}/pass_test.sh"; rw3=$!; pids+=("${rw3}")
soon '^test.sh: waiting' "${ROOT}/w3.out" || true
o="$(grep -c "PID ${rh3} holds ${slots}/1" "${ROOT}/w3.out" || true)|$(grep -c '^run ' "${ROOT}/w3.out" || true)"
touch "${ROOT}/goH3"; finish "${rh3}"; finish "${rw3}"
check "a live run whose path holds ' --one ' still holds its slot: the next run waits on it" "${o}|${fin}|$(left)" "1|0|0|empty"

# A run killed while it waited left its .new.<pid>: the next run removes it.
sleep 0 & dead=$!; wait "${dead}"
mkdir -p "${slots}/.new.${dead}"; : > "${slots}/.new.${dead}/${dead}"
start p11 "${ROOT}/p11.out" "${ROOT}/pass_test.sh"; finish $!
check "a gone run's .new.<pid> is removed by the next run" "${fin}|$(left)" "0|empty"

# An interrupted run (TERM: a background run ignores INT) frees the slot it held.
printf '#!/usr/bin/env bash\necho start >> "%s/order"\nsleep 30\n' "${ROOT}" > "${ROOT}/long_test.sh"
: > "${ROOT}/order"
start p12 "${ROOT}/p12.out" "${ROOT}/long_test.sh"; r5=$!; pids+=("${r5}")
until_there '^start$' "${ROOT}/order"
held="$(cd "${slots}/1" && echo *)"
kill -TERM "${r5}"; finish "${r5}"
check "an interrupted run frees the slot it held" "${held}|${fin}|$(left)" "${r5}|143|empty"

# rooted <file> <var> — 0 when <file> sets <var> from mktemp, or from a variable it sets so (as
# sleep_scale_test.sh's).
rooted() {
  local from
  grep -qE "^$2=\"\\\$\(mktemp " "$1" && return 0
  from="$(sed -nE "s/^$2=\"\\\$\(cd \"\\\$\{([A-Za-z_]+)\}\".*/\1/p" "$1" | head -1)"
  [[ -n "${from}" ]] && grep -qE "^${from}=\"\\\$\(mktemp " "$1"
}
starters="" unhomed=""
for t in "${REPO}"/tests/*_test.sh; do
  grep -qE -- '-u TEST_RUNS_LOG|unset TEST_RUNS_LOG|TEST_RUNS_LOG="[^"]|-u TEST_SH_PID|unset TEST_SH_PID' "${t}" || continue
  starters+=" ${t##*/} "
  v="$(sed -nE 's/^export HOME="\$\{([A-Za-z_]+)\}.*/\1/p' "${t}" | head -1)"
  [[ -n "${v}" ]] && rooted "${t}" "${v}" || unhomed+="${t##*/} "
done
check "the tests that start a top-level run include flow_test_runs_test.sh, sleep_scale_test.sh and this one" \
  "$(for t in flow_test_runs_test.sh sleep_scale_test.sh test_cap_test.sh; do [[ "${starters}" == *" ${t} "* ]] && printf 'yes ' || printf '%s no ' "${t}"; done)" "yes yes yes "
check "every test that starts a top-level run exports HOME under its own mktemp root" "${unhomed}" ""

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
