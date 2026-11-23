#!/usr/bin/env bash
# update_test.sh — `swarm.sh update` acts on the plugin ID the copy is installed as (plugin_id in
# bin/swarm.sh): it runs `claude plugin marketplace update <marketplace>`, then
# `claude plugin update <plugin>@<marketplace>`, both read from the copy's path, and exits 0.
# Each case runs swarm.sh update from a folder that is no project, with a claude stub first on PATH that
# logs its arguments, SWARMDEV_BIN set (make test builds it) so no copy fetches, and SWARM_PROJECT unset.
#   A no-.git copy at <config>/plugins/cache/swarm-dev-pre/swarm-dev/1.0.0: the marketplace
#     swarm-dev-pre, then swarm-dev@swarm-dev-pre, and nothing else.
#   A copy at <config>/plugins/cache/swarm-dev/swarm-dev/1.0.0: swarm-dev, then swarm-dev@swarm-dev.
#   Copies of the -pre layout whose two segments above the marketplace are not exactly plugins, then
#     cache (plugins/caches, xplugins/cache): swarm-dev, then swarm-dev@swarm-dev, so only whole
#     segments match.
#   The checkout these tests run from: swarm-dev, then swarm-dev@swarm-dev.
# Then the new copy's run. The stub's `plugin update` copies ${ROOT}/next.json, when there is one, to
# <config>/plugins/installed_plugins.json, as Claude Code's update writes it; a new copy's bin/swarm.sh is a
# stub that logs `$0 $*` to the same log and prints a line. From a swarm-dev@swarm-dev copy:
#   An entry whose installPath names a copy: its swarm.sh version runs once, after the plugin update, and
#     its line comes before the restart line.
#   installPath names the older of two version folders: the older one runs, never the newer.
#   No user entry, two, or no bin/swarm.sh at installPath: one line naming swarm.sh version, no run.
#   A stub that sleeps, with SWARM_UPDATE_WAIT=2: update returns within 10 s with that one line.
#   A stub that runs its own binary_within, as a new copy's fetch bounds gh: once update's bound passes,
#     the inner command, in a process group of its own, is gone too.
# And from a swarm-dev@swarm-dev-pre copy, an entry for swarm-dev@swarm-dev alone counts as none.
# Every case exits 0.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${SWARMDEV_BIN:-}" || ! -x "${SWARMDEV_BIN}" ]]; then
  echo "FAIL SWARMDEV_BIN names no executable binary ('${SWARMDEV_BIN:-}'): run this test through make test, which builds it"
  exit 1
fi
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[[ -d "${tmp}" ]] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
# The nested case's inner command runs in a process group of its own; if a case leaves it, KILL it by its pid.
cleanup() {
  local p=""
  [[ ! -s "${ROOT}/inner.pid" ]] || p="$(cat "${ROOT}/inner.pid")"
  [[ -z "${p}" ]] || kill -KILL "${p}" 2>/dev/null || true
  rm -rf "${ROOT}"
}
trap cleanup EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, as every test file

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

TOOLS="${ROOT}/tools"; mkdir -p "${TOOLS}"
# claude: logs each call's arguments, one line a call, and succeeds. Never the real one. Its plugin update
# writes installed_plugins.json from ${ROOT}/next.json, when there is one.
cat > "${TOOLS}/claude" <<STUB
#!/bin/sh
echo "\$*" >> "${ROOT}/claude.log"
if [ "\$1 \$2" = "plugin update" ] && [ -f "${ROOT}/next.json" ]; then
  mkdir -p "${CLAUDE_CONFIG_DIR}/plugins" && cp "${ROOT}/next.json" "${CLAUDE_CONFIG_DIR}/plugins/installed_plugins.json"
fi
STUB
chmod +x "${TOOLS}/claude"
W="${ROOT}/work"; mkdir -p "${W}"   # where each call runs: no project
CACHE="${CLAUDE_CONFIG_DIR}/plugins/cache"
STABLE="plugin marketplace update swarm-dev|plugin update swarm-dev@swarm-dev"

# copy <dir> — a copy of the plugin as an install leaves it: bin/, scripts/build.sh, .claude-plugin/,
# go.mod, cmd/ and internal/, with no .git.
copy() {
  mkdir -p "$1/scripts"
  cp -R "${REPO}/bin" "${REPO}/.claude-plugin" "${REPO}/go.mod" "${REPO}/cmd" "${REPO}/internal" "$1/"
  cp "${REPO}/scripts/build.sh" "$1/scripts/"
}
# update <plugin root> — <root>'s swarm.sh update; sets rc, and log: the claude stub's calls, then each
# new copy's run, joined by |. It removes installed_plugins.json first, so only the stub's update writes one.
update() {
  rm -f "${ROOT}/claude.log" "${CLAUDE_CONFIG_DIR}/plugins/installed_plugins.json"; rc=0
  (cd "${W}" || exit 1
   env -u HERDR_ENV -u SWARM_PROJECT PATH="${TOOLS}:${PATH}" bash "$1/bin/swarm.sh" update) \
    < /dev/null > "${ROOT}/out" 2>&1 || rc=$?
  log="$(paste -sd'|' - < "${ROOT}/claude.log" 2>/dev/null || true)"
}

# --- Installed as swarm-dev@swarm-dev-pre: that marketplace, then that ID.
C="${CACHE}/swarm-dev-pre/swarm-dev/1.0.0"; copy "${C}"; update "${C}"
check "swarm-dev-pre copy: exits 0" 0 "${rc}"
check "swarm-dev-pre copy: updates marketplace swarm-dev-pre, then swarm-dev@swarm-dev-pre" \
  "plugin marketplace update swarm-dev-pre|plugin update swarm-dev@swarm-dev-pre" "${log}"

# --- Installed as swarm-dev@swarm-dev: as before the ID was read from the path.
C="${CACHE}/swarm-dev/swarm-dev/1.0.0"; copy "${C}"; update "${C}"
check "swarm-dev copy: exits 0" 0 "${rc}"
check "swarm-dev copy: updates marketplace swarm-dev, then swarm-dev@swarm-dev" "${STABLE}" "${log}"

# --- Not Claude Code's layout above the marketplace: the fixed ID, never swarm-dev-pre.
C="${CLAUDE_CONFIG_DIR}/plugins/caches/swarm-dev-pre/swarm-dev/1.0.0"; copy "${C}"; update "${C}"
check "plugins/caches copy: exits 0" 0 "${rc}"
check "plugins/caches copy (not cache): updates swarm-dev, then swarm-dev@swarm-dev" "${STABLE}" "${log}"
C="${ROOT}/xplugins/cache/swarm-dev-pre/swarm-dev/1.0.0"; copy "${C}"; update "${C}"
check "xplugins/cache copy: exits 0" 0 "${rc}"
check "xplugins/cache copy (not plugins): updates swarm-dev, then swarm-dev@swarm-dev" "${STABLE}" "${log}"

# --- The checkout: the fixed ID.
update "${REPO}"
check "checkout: exits 0" 0 "${rc}"
check "checkout: updates swarm-dev, then swarm-dev@swarm-dev" "${STABLE}" "${log}"

# --- The new copy's swarm.sh version, run once after the plugin update.
# new_copy <dir> [sleep seconds] — a new version's folder whose bin/swarm.sh logs `$0 $*` and prints a line
# (after sleeping, when given seconds).
new_copy() {
  mkdir -p "$1/bin"
  # shellcheck disable=SC2016 # $0 and $* are the stub's own, expanded when it runs
  printf '#!/bin/sh\n%secho "$0 $*" >> "%s/claude.log"\necho "new copy ran: $*"\n' \
    "${2:+sleep $2; }" "${ROOT}" > "$1/bin/swarm.sh"
}
# entries <plugin ID> <installPath>... — write next.json: one user entry per installPath under <plugin ID>,
# with the fields Claude Code writes.
entries() {
  python3 -I -c '
import json, sys
out, pid, paths = sys.argv[1], sys.argv[2], sys.argv[3:]
es = [{"scope": "user", "installPath": p, "version": p.rsplit("/", 1)[-1], "installedAt": "2026-11-22T00:00:00.000Z",
       "lastUpdated": "2026-11-22T00:00:00.000Z", "gitCommitSha": "0" * 40} for p in paths]
with open(out, "w") as f:
    json.dump({"version": 2, "plugins": {pid: es}}, f)' "${ROOT}/next.json" "$@"
}
# one_line <case> — out has exactly one line naming swarm.sh version.
one_line() {
  check "$1: one line naming swarm.sh version" 1 "$(grep -c 'swarm.sh version' "${ROOT}/out" || true)"
}
OLD="${CACHE}/swarm-dev/swarm-dev/0.9.0"; NEW="${CACHE}/swarm-dev/swarm-dev/2.0.0"
C="${CACHE}/swarm-dev/swarm-dev/1.0.0"   # the running copy, from the cases above
new_copy "${NEW}"; entries swarm-dev@swarm-dev "${NEW}"; update "${C}"
check "wrapper: exits 0" 0 "${rc}"
check "wrapper: the new copy's swarm.sh version runs once, after the plugin update" \
  "${STABLE}|${NEW}/bin/swarm.sh version" "${log}"
check "wrapper: its line, then the restart line, end update's output" \
  "new copy ran: version|Restart Claude Code to load the new version." "$(tail -n 2 "${ROOT}/out" | paste -sd'|' -)"

new_copy "${OLD}"; entries swarm-dev@swarm-dev "${OLD}"; update "${C}"
check "older installPath: exits 0" 0 "${rc}"
check "older installPath: the older folder's swarm.sh runs, the newer one's does not" \
  "${STABLE}|${OLD}/bin/swarm.sh version" "${log}"

entries swarm-dev@swarm-dev; update "${C}"
check "no user entry: exits 0" 0 "${rc}"
check "no user entry: no wrapper run" "${STABLE}" "${log}"
one_line "no user entry"

entries swarm-dev@swarm-dev "${OLD}" "${NEW}"; update "${C}"
check "two user entries: exits 0" 0 "${rc}"
check "two user entries: no wrapper run" "${STABLE}" "${log}"
one_line "two user entries"

entries swarm-dev@swarm-dev "${ROOT}/empty"; mkdir -p "${ROOT}/empty"; update "${C}"
check "no swarm.sh at installPath: exits 0" 0 "${rc}"
check "no swarm.sh at installPath: no wrapper run" "${STABLE}" "${log}"
one_line "no swarm.sh at installPath"

P="${CACHE}/swarm-dev-pre/swarm-dev/1.0.0"   # the -pre copy, from the cases above
entries swarm-dev@swarm-dev "${NEW}"; update "${P}"
check "-pre copy, only swarm-dev@swarm-dev listed: exits 0" 0 "${rc}"
check "-pre copy, only swarm-dev@swarm-dev listed: no wrapper run" \
  "plugin marketplace update swarm-dev-pre|plugin update swarm-dev@swarm-dev-pre" "${log}"
one_line "-pre copy, only swarm-dev@swarm-dev listed"

S="${ROOT}/slow/swarm-dev/3.0.0"; new_copy "${S}" 60; entries swarm-dev@swarm-dev "${S}"
export SWARM_UPDATE_WAIT=2
start="$(date +%s)"; update "${C}"; took=$(( $(date +%s) - start ))
unset SWARM_UPDATE_WAIT
check "sleeping wrapper: exits 0" 0 "${rc}"
check "sleeping wrapper: update returns within 10 s" yes "$([[ ${took} -le 10 ]] && echo yes || echo "no (${took} s)")"
one_line "sleeping wrapper"

# A new copy whose swarm.sh version runs the lib's own binary_within, as its fetch bounds gh: the inner
# command writes its pid, then sleeps in its own process group.
N="${ROOT}/nested/swarm-dev/4.0.0"; mkdir -p "${N}/bin"
cat > "${N}/bin/swarm.sh" <<STUB
source "${REPO}/bin/lib/binary.sh"
binary_within 60 sh -c 'echo \$\$ > "${ROOT}/inner.pid"; exec sleep 60'
STUB
entries swarm-dev@swarm-dev "${N}"
export SWARM_UPDATE_WAIT=2
update "${C}"
unset SWARM_UPDATE_WAIT
check "nested binary_within: exits 0" 0 "${rc}"
one_line "nested binary_within"
check "nested binary_within: the inner command ran and is gone once update returns" gone \
  "$(p="$(cat "${ROOT}/inner.pid" 2>/dev/null)"
    if [[ -z "${p}" ]]; then echo "no pid written"; elif kill -0 "${p}" 2>/dev/null; then echo alive; else echo gone; fi)"
rm -f "${ROOT}/next.json"

echo
if [[ ${fails} -eq 0 ]]; then echo "all update tests passed"; else echo "${fails} update test(s) failed"; exit 1; fi
