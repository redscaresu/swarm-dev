#!/usr/bin/env bash
# events_tail_merge_test.sh — merge.sh's and board.sh's events.tsv readers read the outcome without its
# key=value tail (EVENT_OUTCOME_AWK's outcome()): base_merged (dropped_lines' read too, with an empty
# slug), base_merged_from, report_collected, key_reds, red_mains, stacked_parents, fix_main_owner,
# merge_refused, last_event and reset_at. Each runs over two stand-in projects (events_tail_helpers.sh):
# the committed fixture plus inline rows for forms its cut lacks, plain, and the same with a tail on
# every row. For every target of the rows it reads (every main_key for key_reds), a text reader prints
# the same in both and a predicate gives the same status; each gives its expected output, or its
# expected success and failure statuses, in both.
# swarm.sh hold refuses a story whose last row is a tailed reconcile reopen, as it does untailed.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${HERE}/.." && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# shellcheck source=tests/events_tail_helpers.sh
. "${HERE}/events_tail_helpers.sh"
fails=0

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

# The tail: agents.sh's EVENT_SEP, read by sourcing it as swarm.sh does, and two fields.
SEP="$(PROJECT_DIR="${ROOT}" bash -c '. "$1/bin/lib/agents.sh"; printf %s "${EVENT_SEP}"' _ "${REPO}")"
TAIL="${SEP}round=2 verdict=pass"

# Inline rows for forms the fixture's cut lacks, after its last row (2026-10-29T01:14:39Z).
# zzx: GitHub's merge of the base, named alone (BM1, the older form) and with the head it came from
# (BM2 from BM0). o/r main: red R1, a main-green naming no red (an older record, clearing R1), then red
# R2. o/s main: red S2, then red S1, whose fix-main story retired, superseded by S2's (red_mains gives
# S2). zzh: a held merge, then a new review that clears it. zzr: a ready story reset, then reopened by
# reconcile, its last row.
BM0=b000000000000000000000000000000000000000; BM1=b100000000000000000000000000000000000000
BM2=b200000000000000000000000000000000000000
R1=c100000000000000000000000000000000000000; R2=c200000000000000000000000000000000000000
S1=d100000000000000000000000000000000000000; S2=d200000000000000000000000000000000000000
G0=e000000000000000000000000000000000000000
EVENTS="${ROOT}/events.tsv"
cp "${EVENTS_FIXTURE}" "${EVENTS}"
row() { printf '2026-10-29T0%s:00:00Z\t%s\t%s\twz:pz\t%s\n' "$1" "$2" "$3" "$4" >> "${EVENTS}"; }
row 2 merge zzx "base-merged ${BM1}"
row 2 merge zzx "base-merged ${BM2} from ${BM0}"
row 3 main-red "${R1}" "o/r main test (failure)"
row 3 main-green "${G0}" "o/r main"
row 3 main-red "${R2}" "o/r main test (failure)"
row 4 main-red "${S2}" "o/s main test (failure)"
row 4 main-red "${S1}" "o/s main test (failure)"
row 4 fix-main "fix-main-${S1:0:7}" "retired: superseded by fix-main-${S2:0:7}"
row 5 merge zzh "held: https://github.com/o/r/pull/90 (costs money); the user merges it"
row 5 review zzh "ok (https://github.com/o/r/pull/90)"
row 6 reset zzr "ok (re-scoped)"
row 6 reconcile zzr "ok (reopened)"

# Both projects: the fixture's zzd story was started from pane wb:pb, which a tab record names as
# conductor conduct-zzq (fix_main_owner), and zzr and zzs are ready stories on the board (hold).
PLAIN="${ROOT}/plain/proj"; TAILED="${ROOT}/tailed/proj"
for p in "${PLAIN}" "${TAILED}"; do
  if [[ "${p}" == "${TAILED}" ]]; then events_project "${p}" "${EVENTS}" "${TAIL}"; else events_project "${p}" "${EVENTS}"; fi
  mkdir -p "${p}/.swarm/state"; echo "wb:pb conduct-zzq" > "${p}/.swarm/state/zzq"
  for s in zzr zzs; do printf -- '---\nkind: code\nstatus: ready\n---\n\n# %s\n' "${s}" > "${p}/docs/stories/${s}.md"; done
done
all_tailed() { awk -F'\t' -v t="${TAIL}" 'substr($5, length($5) - length(t) + 1) != t { bad = 1 } END { exit bad || NR < 400 }' "$1"; }
check "the tailed copy's rows all end in the tail" all_tailed "${TAILED}/.swarm/events.tsv"

# Two reports for report_collected: one written before every row, one after them all (whose status is
# 1 for every target in both projects, so only its expected-value check reads it).
OLD="${ROOT}/report-old.md"; NEW="${ROOT}/report-new.md"
: > "${OLD}"; : > "${NEW}"; touch -t 200001010000 "${OLD}"; touch -t 209901010000 "${NEW}"

# targets <commands> — every target of the events file's rows whose command matches the regex
# <commands>. A reader runs for each target of the rows it reads: for any other it reads no row, and
# gives the same in both projects.
targets() { awk -F'\t' -v c="$1" '$2 ~ c { print $3 }' "${EVENTS}" | sort -u; }
# Every main_key the main-red and main-green rows name (key_reds' argument).
KEYS="$(awk -F'\t' '$2 == "main-red" || $2 == "main-green" { split($5, w, " "); print w[1] " " w[2] }' "${EVENTS}" | sort -u)"

# lib <command>... — <command> over the project in the current directory (same_output cd's into it),
# with the bin/lib files the readers need sourced in swarm.sh's order, and swarm.sh's agent_name
# stubbed: the conductor names here are already herdr's.
# shellcheck disable=SC2034 # the sourced files read these
lib() {
  (
    PROJECT_DIR="${PWD}"; SWARM_HOME="${REPO}"; BOARD="${PWD}/docs"; STATE_DIR="${PWD}/.swarm/state"
    for l in agents build board merge; do
      # shellcheck source=/dev/null
      . "${REPO}/bin/lib/${l}.sh"
    done
    # shellcheck disable=SC2317,SC2329 # conduct_epic calls it
    agent_name() { printf '%s' "$1"; }
    "$@"
  )
}
# each <list> <function> [args...] — for each line of <list> and an empty one (base_merged's any
# story, dropped_lines' read): a line `<it>:`, then what <function> <it> [args...] prints.
each() {
  local t list="$1" fn="$2"; shift 2
  while IFS= read -r t <&3; do echo "${t}:"; "${fn}" "${t}" "$@"; done 3<<< "${list}"$'\n'
}
# each_rc <list> <function> [args...] — for each of each's lines, `<it><tab><exit status>`.
each_rc() {
  local t r list="$1" fn="$2"; shift 2
  while IFS= read -r t <&3; do r=0; "${fn}" "${t}" "$@" || r=$?; printf '%s\t%s\n' "${t}" "${r}"; done 3<<< "${list}"$'\n'
}
# rc <command>... — the exit status of <command>, printed.
rc() { local r=0; "$@" || r=$?; echo "${r}"; }
# both <want> <command>... — <command> prints <want> over the plain project and over the tailed one.
both() {
  local want="$1" p got; shift
  for p in "${PLAIN}" "${TAILED}"; do
    got="$(cd "${p}" && lib "$@" 2>/dev/null)" || true
    [[ "${got}" == "${want}" ]] || { echo "  ${p#"${ROOT}/"}: want '${want}', got '${got}'" >&2; return 1; }
  done
}
same() { same_output "${PLAIN}" "${TAILED}" lib "$@"; }

# Every target, plain and tailed: the same output for a text reader, the same status for a predicate.
MERGES="$(targets '^merge$')"
check "base_merged, a head named alone: the same status for every merge target" same each_rc "${MERGES}" base_merged "${BM1}"
check "base_merged, a head named with its from: the same status for every merge target" same each_rc "${MERGES}" base_merged "${BM2}"
check "base_merged_from: the same head for every merge target" same each "${MERGES}" base_merged_from "${BM2}"
check "report_collected, a report older than every row: the same status for every close target" \
  same each_rc "$(targets '^close')" report_collected "${OLD}"
check "key_reds: the same reds for every key" same each "${KEYS}" key_reds
check "key_reds live: the same reds for every key" same each "${KEYS}" key_reds live
check "red_mains: the same reds" same red_mains
check "stacked_parents: the same parents for every stacked, story, close or reset target" \
  same each "$(targets '^(stacked|story|close|reset)(:|$)')" stacked_parents
check "fix_main_owner: the same owner for every story target" same each "$(targets '^story$')" fix_main_owner
check "merge_refused: the same status for every merge or review target" same each_rc "$(targets '^(merge|review)$')" merge_refused
check "last_event: the same command and outcome for every target" same each "$(targets .)" last_event
check "reset_at: the same time for every reset target" same each "$(targets '^reset')" reset_at

# What each gives, plain and tailed: a text reader prints its value; a predicate succeeds and fails.
check "base_merged: a head named alone is zzx's base merge" both 0 rc base_merged zzx "${BM1}"
check "base_merged: a head named with the head it came from is zzx's base merge" both 0 rc base_merged zzx "${BM2}"
check "base_merged: the head it came from is not" both 1 rc base_merged zzx "${BM0}"
check "base_merged: zzx's base merge is not another story's" both 1 rc base_merged zzep "${BM2}"
check "base_merged, empty slug (dropped_lines): any story's base merge" both 0 rc base_merged "" "${BM2}"
check "base_merged, empty slug (dropped_lines): not a head no row names" both 1 rc base_merged "" "${BM0}"
check "base_merged_from: the head zzx's base merge came from" both "${BM0}" base_merged_from zzx "${BM2}"
check "report_collected: an ok close of zza after the report" both 0 rc report_collected zza "${OLD}"
check "report_collected: zza's only close is before the report" both 1 rc report_collected zza "${NEW}"
check "report_collected: review-zzeo's close failed" both 1 rc report_collected review-zzeo "${OLD}"
check "key_reds: both of o/r main's reds" both "${R1}"$'\n'"${R2}" key_reds "o/r main"
check "key_reds live: the red after the green that names no red" both "${R2}" key_reds "o/r main" live
check "red_mains: each key's live red, oldest first, a superseded red giving way to the one covering it" \
  both "0000000000000000000000000000000000000002 zzbp/swarm-dev main test (failure)"$'\n'"${R2} o/r main test (failure)"$'\n'"${S2} o/s main test (failure)" red_mains
check "stacked_parents: zzm's build stacked on zzd" both zzd stacked_parents zzm
check "fix_main_owner: zzd was started from conduct-zzq's pane" both zzq fix_main_owner zzd
check "merge_refused: a held merge goes to the user" both 0 rc merge_refused https://github.com/o/r/pull/20
check "merge_refused: an ok merge does not" both 1 rc merge_refused zzep
check "merge_refused: a review after the held merge clears it" both 1 rc merge_refused zzh
check "last_event: zzr's reconcile reopen" both $'reconcile\tok (reopened)' last_event zzr
check "last_event: zzd's reconcile" both $'reconcile\tok (finished by its PR)' last_event zzd
check "reset_at: when zzr was reset" both 2026-10-29T06:00:00Z reset_at zzr

# swarm.sh hold: zzr's last row is reconcile's reopen, so hold refuses it, tailed as untailed. zzs,
# ready with no row, is held in both: the refusal is zzr's own.
hold() { # <project> <slug> — hold's status and the line it printed last
  local out r=0
  out="$(cd "$1" && env -u HERDR_ENV -u SWARM_PROJECT bash "${REPO}/bin/swarm.sh" hold "$2" 'touches x' 2>&1)" || r=$?
  echo "${r} ${out##*$'\n'}"
}
REFUSED="1 swarm: hold: zzr's PR was closed unmerged; it is the lead's: list it in your report"
check "hold refuses zzr, its last row reconcile's reopen, untailed" [ "$(hold "${PLAIN}" zzr)" == "${REFUSED}" ]
check "hold refuses zzr, its last row reconcile's reopen, tailed" [ "$(hold "${TAILED}" zzr)" == "${REFUSED}" ]
check "hold holds zzs, a ready story with no row, untailed and tailed" \
  [ "$(hold "${PLAIN}" zzs)|$(hold "${TAILED}" zzs)" == "0 logged: hold zzs: touches x|0 logged: hold zzs: touches x" ]

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
