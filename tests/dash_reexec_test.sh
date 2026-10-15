#!/usr/bin/env bash
# dash_reexec_test.sh — `dash --watch` re-execs the newly installed swarm.sh when the plugin's version
# in installed_plugins.json changes. Two installed copies, 0.1.0 and 0.2.0 (whose frame carries a
# marker), a throwaway project with a board, and stub claude, herdr and gh on PATH.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
pids=()
cleanup() { for p in "${pids[@]+"${pids[@]}"}"; do kill "${p}" 2>/dev/null || true; done; rm -rf "${ROOT}"; }
trap cleanup EXIT
fails=0
check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
MARK="REEXEC-MARKER-0.2.0"
T="${ROOT}/cache"
for v in 0.1.0 0.2.0 dev; do mkdir -p "${T}/${v}" && cp -R "${SRC}/bin" "${SRC}/.claude-plugin" "${T}/${v}/"; done
sed -i.bak "s/^dash_render() {\$/&\\
  echo \"${MARK} project=\${SWARM_PROJECT:-}\"/" "${T}/0.2.0/bin/swarm.sh" && rm "${T}/0.2.0/bin/swarm.sh.bak"
grep -qF "${MARK}" "${T}/0.2.0/bin/swarm.sh" || { echo "FAIL the marker went into 0.2.0's swarm.sh"; exit 1; }

export CLAUDE_CONFIG_DIR="${ROOT}/config" TMPDIR="${ROOT}/tmp" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
mkdir -p "${CLAUDE_CONFIG_DIR}/plugins" "${TMPDIR}" "${CLAUDE_PROJECTS_DIR}"
installed() { # <version> <others' version>: dash runs from proj's project install; another
  # project's install (listed first, in the same scope) and the user install are someone else's
  cat > "${CLAUDE_CONFIG_DIR}/plugins/installed_plugins.json.tmp" <<JSON
{"version": 2, "plugins": {"swarm-dev@swarm-dev": [
  {"scope": "project", "projectPath": "${ROOT}/other", "installPath": "${T}/$2", "version": "$2"},
  {"scope": "user", "installPath": "${T}/$2", "version": "$2"},
  {"scope": "project", "projectPath": "${ROOT}/proj", "installPath": "${T}/$1", "version": "$1", "installedAt": "2026-10-01T00:00:00Z"}
]}}
JSON
  mv "${CLAUDE_CONFIG_DIR}/plugins/installed_plugins.json.tmp" "${CLAUDE_CONFIG_DIR}/plugins/installed_plugins.json"
}

# A project with a board, and stubs: claude, herdr and gh answer nothing, stty and tput fail.
P="${ROOT}/proj"
mkdir -p "${P}/board/stories" "${P}/.claude/swarm" "${ROOT}/bin"
echo "# Stories" > "${P}/board/stories/README.md"
echo "board_dir = board" > "${P}/.claude/swarm/config"
git -C "${P}" init -q
cp "${SRC}/tests/claude_stub.sh" "${ROOT}/bin/claude"
for b in herdr gh stty tput; do printf '#!/bin/sh\nexit 1\n' > "${ROOT}/bin/${b}"; done
chmod +x "${ROOT}/bin/"*
unset COLUMNS LINES
export PATH="${ROOT}/bin:${PATH}"

watch() { # <copy> <out> [<dir>]: dash --watch 1 --tree from that copy, off a terminal, in the
  # background, started in <dir> (default the project)
  (cd "${3:-${P}}" && exec env -u HERDR_ENV "${T}/$1/bin/swarm.sh" dash --watch 1 --tree > "$2" 2>&1) &
  WPID=$!; pids+=("${WPID}")
}
within() { # <seconds> <test...>: true once the test passes, checked every 0.2 seconds
  local n=$(($1 * 5)); shift
  while ((n-- > 0)); do "$@" && return 0; sleep 0.2; done
  return 1
}
marked() { grep -qF "${MARK}" "$1"; }
alive() { kill -0 "$1" 2>/dev/null; }

# The installed copy, 0.1.0: no marker until its own install's version becomes 0.2.0.
installed 0.1.0 0.1.0
# It starts in a subdirectory that is then removed: the new script must still find the project.
mkdir "${P}/sub"
watch 0.1.0 "${ROOT}/a.out" "${P}/sub"; A="${WPID}"
sleep 3
check "0.1.0's watch draws its frame" grep -qF "agents by workspace and tab" "${ROOT}/a.out"
check "0.1.0's watch shows no marker" bash -c "! grep -qF '${MARK}' '${ROOT}/a.out'"
# Another project's install and the user install moving to 0.2.0 are not this copy's: no re-exec.
installed 0.1.0 0.2.0
sleep 3
check "another install's version change does not re-exec" bash -c "! grep -qF '${MARK}' '${ROOT}/a.out'"
rmdir "${P}/sub"
installed 0.2.0 0.2.0
check "the version swap re-execs 0.2.0's swarm.sh within 10s" within 10 marked "${ROOT}/a.out"
check "the re-exec'd frame still shows the tree" bash -c "sed -n '/${MARK}/,\$p' '${ROOT}/a.out' | grep -qF 'agents by workspace and tab'"
check "the re-exec'd script watches the same project, its start directory gone" grep -qF "${MARK} project=${P}" "${ROOT}/a.out"
check "the re-exec keeps the PID" alive "${A}"
check "the PID runs 0.2.0's swarm.sh" bash -c "ps -o args= -p '${A}' | grep -qF '${T}/0.2.0/bin/swarm.sh'"
kill "${A}" 2>/dev/null || true

# A copy that is not the installPath (a dev checkout) never jumps to the installed copy.
installed 0.1.0 0.1.0
watch dev "${ROOT}/b.out"; B="${WPID}"
sleep 3
installed 0.2.0 0.2.0
sleep 10
check "a dev copy's watch draws its frame" grep -qF "agents by workspace and tab" "${ROOT}/b.out"
check "a dev copy shows no marker 10s after the swap" bash -c "! grep -qF '${MARK}' '${ROOT}/b.out'"
check "a dev copy is still watching" alive "${B}"
kill "${B}" 2>/dev/null || true

# A missing or unreadable file: no re-exec, and the loop carries on.
installed 0.1.0 0.1.0
watch 0.1.0 "${ROOT}/c.out"; C="${WPID}"
sleep 2
echo 'not json' > "${CLAUDE_CONFIG_DIR}/plugins/installed_plugins.json"
sleep 2
rm "${CLAUDE_CONFIG_DIR}/plugins/installed_plugins.json"
sleep 2
check "an unreadable or missing file does not stop the watch" alive "${C}"
check "an unreadable or missing file does not re-exec" bash -c "! grep -qF '${MARK}' '${ROOT}/c.out'"
kill "${C}" 2>/dev/null || true

if [ "${fails}" -gt 0 ]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
