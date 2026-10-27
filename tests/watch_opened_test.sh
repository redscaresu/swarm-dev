#!/usr/bin/env bash
# watch_opened_test.sh — a conductor's watch (--epic or --backlog) returns once when a story PR of its
# own opens, `<repo> #<n> <branch> opened`, so the conductor starts its review agent; the lead's bare
# watch never says it. gh is a stub on PATH answering from prlist.json; every check run is still
# running, so a watch with nothing to say polls on.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\nF="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'EOF'
echo "$*" >> "$F/calls"
q=""; for a in "$@"; do [ "$p" = -q ] && q="$a"; p="$a"; done
case "$1 $2" in
  "repo view") echo o/svc; exit 0 ;;
esac
case "$2 $3" in
  "--paginate repos/o/svc/pulls?"*) out="$(jq -r "$q" "$F/prlist.json")"; printf '%s\n' "${out}"; exit 0 ;;
esac
case "$2" in
  repos/o/svc/pulls/*) echo MERGEABLE ;;
  repos/o/svc/commits/*/check-runs*) echo '1 1' ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "${ROOT}/bin/gh"

# Epic e has story a, the epic other has b, and c has no epic; all three are built in svc. b's PR comes
# first, so a watch of e that does not skip it says it first.
p="${ROOT}/proj"
mkdir -p "${p}/.claude/swarm" "${p}/docs/epics" "${p}/docs/stories" "${ROOT}/repos"
echo "repos_dir = ${ROOT}/repos" > "${p}/.claude/swarm/config"
git init -q "${ROOT}/repos/svc" && git -C "${ROOT}/repos/svc" remote add origin https://github.com/o/svc
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/e.md"
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/other.md"
printf -- '---\nstatus: ready\nkind: code\nepic: e\nrepo: svc\n---\n' > "${p}/docs/stories/a.md"
printf -- '---\nstatus: ready\nkind: code\nepic: other\nrepo: svc\n---\n' > "${p}/docs/stories/b.md"
printf -- '---\nstatus: ready\nkind: code\nrepo: svc\n---\n' > "${p}/docs/stories/c.md"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "${ROOT}/prlist.json" <<EOF
[{"number": 1, "head": {"ref": "story/b", "sha": "head1"}, "updated_at": "${now}"},
 {"number": 2, "head": {"ref": "story/a", "sha": "head2"}, "updated_at": "${now}"},
 {"number": 3, "head": {"ref": "story/c", "sha": "head3"}, "updated_at": "${now}"}]
EOF
seen="${p}/.swarm/state/watch-seen"

# watch_for <seconds> <watch args...> — what watch printed (stdout and stderr), then its exit code after
# a |. Bounded, polling every 0.12 s, so a watch that polls on ends at the alarm (exit 142) rather than
# hangs the run. calls then holds only this run's gh calls.
watch_for() {
  local secs="$1" out rc; shift
  : > "${ROOT}/calls"
  out="$(cd "${p}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_SLEEP_SCALE=0.002 PATH="${ROOT}/bin:${PATH}" \
    perl -e 'alarm shift; exec @ARGV' "${secs}" bash "${SWARM}" watch "$@" 2>&1)" && rc=0 || rc=$?
  printf '%s|%s' "${out}" "${rc}"
}

check "watch --epic says its own story's PR opened, skipping another epic's, and exits 0" "o/svc #2 story/a opened|0" "$(watch_for 10 --epic e)"
check "watch --epic reads nothing of the PR it says opened past the list" "0" "$(grep -cE 'pulls/2|commits/head2' "${ROOT}/calls" || true)"
check "watch --epic records the PR as opened in watch-seen" "opened o/svc#2" "$(grep '^opened ' "${seen}")"
out="$(watch_for 3 --epic e)"
check "a second watch --epic says no PR opened, not its own again nor another epic's" "0|0" \
  "$(grep -c 'opened' <<< "${out}" || true)|$(grep -c 'story/b' <<< "${out}" || true)"
check "the second watch --epic polls on" "yes" "$([[ $(grep -c 'pulls?state=open' "${ROOT}/calls") -ge 2 ]] && echo yes || echo no)"
check "watch --backlog says a no-epic story's PR opened, and exits 0" "o/svc #3 story/c opened|0" "$(watch_for 10 --backlog)"
check "a second watch --backlog does not say it again" "0" "$(watch_for 3 --backlog | grep -c 'opened' || true)"

# The lead's bare watch leaves the review starts to the conductors: no opened line, none recorded.
rm -f "${seen}"
check "the bare watch says no PR opened and records none" "0|0" \
  "$(watch_for 3 | grep -c 'opened' || true)|$(grep -c '^opened ' "${seen}" || true)"

if [[ ${fails} -gt 0 ]]; then echo "${fails} check(s) failed"; exit 1; fi
echo "all passed"
