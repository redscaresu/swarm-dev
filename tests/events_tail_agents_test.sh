#!/usr/bin/env bash
# events_tail_agents_test.sh — agents.sh's and build.sh's events.tsv readers read the outcome column
# through EVENT_OUTCOME_AWK's outcome(), so a key=value tail on a row changes nothing they decide.
# Over the fixture (events_tail_helpers.sh) plus synthetic rows for what it lacks, once plain and once
# with a tail on every row: login_incident, findings_told and review_rounds give the same answer for
# every target, and the plain run gives a non-trivial one for some target; sign_held over sign-blocked:
# and sign-clear: incidents holds and fails as expected, appends no duplicate on repeated blocked polls
# and one line on a clear, alike in both. And the writer contract: every fixture outcome written
# through append_event with k=v reads back through events_outcome.py as the outcome and {k: v}.
# The functions run in a copy of swarm.sh without its last line (main "$@"; exit), sourced in a
# stand-in project, beside a link to the real bin/lib.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$(cd "${HERE}/../bin/lib" && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
unset HERDR_PANE_ID
# shellcheck source=tests/events_tail_helpers.sh
. "${HERE}/events_tail_helpers.sh"
fails=0

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
same() { # <got> <want>
  [[ "$1" == "$2" ]] || { diff <(printf '%s\n' "$2") <(printf '%s\n' "$1") >&2 || true; return 1; }
}

# The loader: swarm.sh up to its dispatch, which a source would run.
LOADER="${ROOT}/swarm/bin/swarm.sh"
mkdir -p "${LOADER%/*}" && ln -s "${LIB}" "${LOADER%/*}/lib"
# shellcheck disable=SC2016 # the line itself
[[ "$(tail -1 "${LIB}/../swarm.sh")" == 'main "$@"; exit' ]] \
  || { echo "FAIL swarm.sh no longer ends in main \"\$@\"; exit, so the loader cannot cut it"; exit 1; }
sed '$d' "${LIB}/../swarm.sh" > "${LOADER}"
# in_swarm <script> [arg...] — bash <script>, its args as $1..., in the cwd's project once swarm.sh's
# functions are loaded. With TAILED set, record_event writes a k=v field, as a writer that passes
# fields will.
in_swarm() {
  # shellcheck disable=SC2016 # expanded by the inner shell
  bash -c 'L="$1" S="$2"; shift 2; args=("$@"); set --; source "${L}"
    [[ -z "${TAILED:-}" ]] || record_event() { append_event "$1" "$2" "${3:-ok}" k=v || true; }
    set -- "${args[@]+"${args[@]}"}"; eval "${S}"' _ "${LOADER}" "$@"
}
SEP="$(PROJECT_DIR="${ROOT}/src" bash -c 'source "$1/agents.sh"; printf %s "${EVENT_SEP}"' _ "${LIB}")"
check "the separator is agents.sh's EVENT_SEP" same "${SEP}" " ~~ "
TAIL="${SEP}k=v"

# The fixture, then synthetic rows for the cases it lacks: login incidents left open, closed by an ok
# tell or review-agent start, and kept open across an api-error; sign-blocked and sign-clear incidents.
EV="${ROOT}/events.tsv"
cp "${EVENTS_FIXTURE}" "${EV}"
SYN_N=0
syn() { SYN_N=$((SYN_N + 1)); printf '2026-10-29T02:00:%02dZ\t%s\t%s\t-\t%s\n' "${SYN_N}" "$@" >> "${EV}"; }
syn incident zzlogin-open "login: Login expired"
syn incident zzlogin-told "login: Login expired"
syn tell:findings zzlogin-told ok
syn incident zzlogin-kept "login: Login expired"
syn incident zzlogin-kept "api-error: API Error: 500"
syn incident review-zzlr "login: Login expired"
syn review-agent zzlr ok
syn incident zzsb "sign-blocked: zzsb (unsigned work since no commit)"
syn incident zzsc "sign-blocked: zzsc (unsigned work since no commit)"
syn incident zzsc "sign-clear: zzsc"
# pair <name> — ${ROOT}/<name>/plain/proj and ${ROOT}/<name>/tailed/proj over EV, the second with TAIL.
pair() {
  events_project "${ROOT}/$1/plain/proj" "${EV}" && events_project "${ROOT}/$1/tailed/proj" "${EV}" "${TAIL}"
}
TARGETS="$(cut -f3 "${EV}" | sort -u)"

# --- login_incident: per target, "logged" when it would log (record_event only says so here) and
# "open" when its login incident is still open. conductor_name backlog is the same for every target,
# so it is asked once.
LOGINS_SH="$(cat <<'SH'
record_event() { echo logged; }
b="$(conductor_name backlog)"; conductor_name() { echo "${b}"; }
while IFS= read -r t; do printf '%s %s\n' "${t}" "$(login_incident "${t}")"; done <<< "$1"
SH
)"
pair login
plain="$(cd "${ROOT}/login/plain/proj" && in_swarm "${LOGINS_SH}" "${TARGETS}" | sed 's/ $/ open/')"
tailed="$(cd "${ROOT}/login/tailed/proj" && in_swarm "${LOGINS_SH}" "${TARGETS}" | sed 's/ $/ open/')"
check "login_incident decides the same for every target, plain and tailed" same "${tailed}" "${plain}"
want="review-zzlr logged
zzlogin-kept open
zzlogin-open open
zzlogin-told logged"
check "login_incident keeps an open login (across an api-error too) and logs after an ok tell or start, plain" \
  same "$(grep -E '^(zzlogin-|review-zzlr )' <<< "${plain}")" "${want}"

# --- findings_told and review_rounds: "<target> <findings_told> <review_rounds>".
COUNTS_SH="$(cat <<'SH'
while IFS= read -r t; do printf '%s %s %s\n' "${t}" "$(findings_told "${t}")" "$(review_rounds "${t}")"; done <<< "$1"
SH
)"
pair counts
plain="$(cd "${ROOT}/counts/plain/proj" && in_swarm "${COUNTS_SH}" "${TARGETS}")"
tailed="$(cd "${ROOT}/counts/tailed/proj" && in_swarm "${COUNTS_SH}" "${TARGETS}")"
check "findings_told and review_rounds give the same for every target, plain and tailed" same "${tailed}" "${plain}"
check "findings_told counts a tell for some target, plain" grep -qE ' [1-9][0-9]* [0-9]+ [0-9]+$' <<< "${plain}"
check "review_rounds is past round 1 with a review started for some target, plain" \
  grep -qE ' ([2-9]|[1-9][0-9]+) [1-9][0-9]*$' <<< "${plain}"

# --- sign_held <name> <name> 1, its probe saying blocked, blocked, clear, clear, blocked; its worktree
# the project itself (no commit yet). Prints each poll's state and status, then <name>'s incidents.
SIGNS_SH="$(cat <<'SH'
repo_dir() { pwd -P; }
worktree_for() { pwd -P; }
sign_blocked() { echo "${SIGN_STATE}"; [[ "${SIGN_STATE}" == blocked ]]; }
for SIGN_STATE in blocked blocked clear clear blocked; do
  rc=0; sign_held "$1" "$1" 1 || rc=$?
  echo "${SIGN_STATE} ${rc}"
done
awk -F'\t' -v n="$1" "${EVENT_OUTCOME_AWK}"'$2 == "incident" && $3 == n { print outcome($5) }' "${EVENTS_LOG}"
SH
)"
signs() { in_swarm "${SIGNS_SH}" "$1"; }
pair sign
P="${ROOT}/sign/plain/proj"; T="${ROOT}/sign/tailed/proj"
polls="blocked 0
blocked 0
clear 1
clear 1
blocked 0"
# zzsb's newest incident is the blocked line: the blocked polls add nothing, the first clear adds one
# and the last blocked one.
want="${polls}
sign-blocked: zzsb (unsigned work since no commit)
sign-clear: zzsb
sign-blocked: zzsb (unsigned work since no commit)"
check "sign_held after an inline sign-blocked:, plain: no duplicate, one clear" same "$(cd "${P}" && signs zzsb)" "${want}"
check "sign_held after an inline sign-blocked:, tailed, its own lines with a field too: the same" \
  same "$(cd "${T}" && TAILED=1 signs zzsb)" "${want}"
# zzsc's newest is a clear: the first blocked poll adds one, and the first clear one more.
want="${polls}
sign-blocked: zzsc (unsigned work since no commit)
sign-clear: zzsc
sign-blocked: zzsc (unsigned work since no commit)
sign-clear: zzsc
sign-blocked: zzsc (unsigned work since no commit)"
check "sign_held after an inline sign-clear:, plain" same "$(cd "${P}" && signs zzsc)" "${want}"
check "sign_held after an inline sign-clear:, tailed: the same" same "$(cd "${T}" && TAILED=1 signs zzsc)" "${want}"

# --- The writer contract over the fixture: each row's outcome, through append_event with k=v.
W="${ROOT}/write/proj"
events_project "${W}" /dev/null
WRITE_SH="$(cat <<'SH'
while IFS=$'\t' read -r _ c t _ o; do append_event "${c}" "${t}" "${o}" k=v; done < "$1"
SH
)"
(cd "${W}" && in_swarm "${WRITE_SH}" "${EVENTS_FIXTURE}")
readback() {
  python3 -c 'import sys
sys.path.insert(0, sys.argv[1])
from events_outcome import fields, outcome
want = [l.rstrip("\n").split("\t") for l in open(sys.argv[2])]
got = [l.rstrip("\n").split("\t") for l in open(sys.argv[3])]
bad = [(w[4], outcome(g), fields(g)) for w, g in zip(want, got) if outcome(g) != w[4] or fields(g) != {"k": "v"}]
for b in bad[:5]:
    print("read back %r as %r, %r" % b, file=sys.stderr)
sys.exit(1 if bad or len(want) != len(got) or not want else 0)' "${LIB}" "${EVENTS_FIXTURE}" "${W}/.swarm/events.tsv"
}
check "every fixture outcome written with k=v reads back as itself and {k: v}" readback

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
