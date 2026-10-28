#!/usr/bin/env bash
# wait_pr_new_head_test.sh — swarm.sh wait-pr right after a push, when GitHub's first answer can still
# name the old head. Without --head it waits on the head of its first read, whatever that is; with
# --head <sha> (a full SHA or a prefix of 7 or more) it reads the PR again each poll until the head
# starts with <sha>, then waits on that head's checks alone. A head that never comes within the grace
# ends it with exit 2, naming both; a --head that is not hex is a usage error. gh is a stub on PATH:
# it logs every call to gh.log; its nth pr view answers ${FX}/view.<n> (else ${FX}/view), a line
# "<head> <mergeable> main OPEN"; the nth check-runs read of <sha> answers ${FX}/checks.<sha>.<n>
# (else ${FX}/checks.<sha>); commit statuses are none.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; FX="${ROOT}/fx"; URL=https://github.com/o/r/pull/7
# H0 is the head before the push, H1 the one pushed.
H0=0000000000000000000000000000000000000000; H1=1111111111111111111111111111111111111111
mkdir -p "${P}/.claude/swarm" "${P}/docs/stories" "${ROOT}/bin"; : > "${P}/.claude/swarm/config"
git -C "${P}" init -q

printf '#!/usr/bin/env bash\nFX="%s"; LOG="%s"\n' "${FX}" "${ROOT}/gh.log" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${LOG}"
# nth <key> — this read's number for <key>, counted in ${FX}/<key>.n.
nth() { n=$(( $(cat "${FX}/$1.n" 2>/dev/null || echo 0) + 1 )); echo "${n}" > "${FX}/$1.n"; }
case "$*" in
  "pr view"*) nth view; cat "${FX}/view.${n}" 2>/dev/null || cat "${FX}/view" ;;
  *check-runs*) a="$*"; sha="${a#*commits/}"; sha="${sha%%/*}"; nth "checks.${sha}"
    cat "${FX}/checks.${sha}.${n}" 2>/dev/null || cat "${FX}/checks.${sha}" ;;
  */status*) echo '{"total_count":0,"statuses":[]}' ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
chmod +x "${ROOT}/bin/gh"

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
said() { grep -qF -- "$1" "${ROOT}/out"; }
# reads <sha> — how many check-runs reads named <sha>.
reads() { grep -c "commits/$1/check-runs" "${ROOT}/gh.log" || true; }

# checks <file> <status> [conclusion] — a page with one check run, test.
checks() { local c=null; [[ -z "${3:-}" ]] || c="\"$3\""; printf '{"total_count":1,"check_runs":[{"name":"test","status":"%s","conclusion":%s}]}\n' "$2" "${c}" > "$1"; }
# pushed — the case the story reproduces: the first pr view still names H0, whose checks are green;
# every later one names H1, pending on its first read and green after.
pushed() {
  rm -rf "${FX}"; mkdir -p "${FX}"; : > "${ROOT}/gh.log"
  echo "${H0} MERGEABLE main OPEN" > "${FX}/view.1"; echo "${H1} MERGEABLE main OPEN" > "${FX}/view"
  checks "${FX}/checks.${H0}" completed success
  checks "${FX}/checks.${H1}.1" in_progress; checks "${FX}/checks.${H1}" completed success
}
# wait_pr [VAR=value]... [arg]... — swarm.sh wait-pr [arg]... ${URL}, polling with no pause unless VARs
# say otherwise; sets rc, output in ${ROOT}/out.
wait_pr() {
  local envs=(); rc=0
  while [[ "${1:-}" == [A-Z]*=* ]]; do envs+=("$1"); shift; done
  (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=0 SWARM_WAIT_PR_RETRY=0 \
    ${envs[@]+"${envs[@]}"} bash "${SWARM}" wait-pr "$@" "${URL}" > "${ROOT}/out" 2>&1) || rc=$?
}

# --- Without --head, the head of the first read is the one waited on: right after a push that can be
# the old one, green already, so the wait ends before the pushed head has run a check.
pushed; wait_pr
is "without --head: exits 0" 0 "${rc}"
check "without --head: waits on the head of its first read" said "head ${H0}"
is "without --head: reads the checks of that head alone" "1 0" "$(reads "${H0}") $(reads "${H1}")"

# --- With --head H1, H0's answer is pending and its checks are not read; once the PR names H1, its
# checks are waited on until green.
pushed; wait_pr --head "${H1}"
is "--head: exits 0" 0 "${rc}"
check "--head: waits on the pushed head" said "head ${H1}"
check "--head: the old head is pending" said "pending: head ${H0:0:7}, not ${H1}"
check "--head: the pushed head's pending check is printed" said "pending: test (in_progress)"
is "--head: exits only once H1 is green, reading H1's checks alone" "0 2" "$(reads "${H0}") $(reads "${H1}")"

# A prefix of 7 works the same, after --timeout too.
pushed; wait_pr --timeout 60 --head "${H1:0:7}"
is "--head prefix: exits 0" 0 "${rc}"
check "--head prefix: waits on the pushed head" said "head ${H1}"
is "--head prefix: reads H1's checks alone, until green" "0 2" "$(reads "${H0}") $(reads "${H1}")"

# H0 conflicted with the base and the push merged it in: H0's conflict does not end the wait.
pushed; echo "${H0} CONFLICTING main OPEN" > "${FX}/view.1"; wait_pr --head "${H1}"
is "--head: the old head's conflict is not judged" 0 "${rc}"

# --- A head that never comes within the grace ends it, naming the PR's head and the one wanted.
pushed; rm "${FX}/view.1"; echo "${H0} MERGEABLE main OPEN" > "${FX}/view"
wait_pr SWARM_WAIT_PR_GRACE=2 SWARM_MERGE_POLL=1 --head "${H1}"
is "--head never comes: exits 2" 2 "${rc}"
check "--head never comes: names both heads" said "the PR's head is ${H0}, not ${H1}"
check "--head never comes: read the PR again before it ended" test "$(grep -c '^pr view' "${ROOT}/gh.log")" -ge 2
is "--head never comes: reads no checks" "0 0" "$(reads "${H0}") $(reads "${H1}")"

# --- --head takes hex only: anything else is a usage error, before any read.
pushed; wait_pr --head xyz
is "--head xyz: exits 2" 2 "${rc}"
check "--head xyz: a usage error" said "usage: swarm.sh wait-pr"
check "--head xyz: reads nothing" test ! -s "${ROOT}/gh.log"

if [[ ${fails} -eq 0 ]]; then echo "all wait-pr new-head tests passed"; else echo "${fails} wait-pr new-head test(s) failed"; exit 1; fi
