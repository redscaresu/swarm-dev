#!/usr/bin/env bash
# binary_fallback_test.sh — an installed copy of the plugin (no .git) whose download cannot work builds
# its binary from the source beside it on its first swarm.sh call, says so, and runs the command
# (binary_ensure, binary_gh_unfit and binary_fallback in bin/lib/binary.sh). Each case runs a new copy's
# swarm.sh config from a project. The copy holds the marker bin/ported/config and a cmd/swarm/main.go of
# the test's own that prints a word, and the stubs of tests/binary_fetch_stubs.sh come first on PATH.
# The ways the download cannot work: the gh stub's release download fails with an offline error, with
# gh's own not-logged-in text, or with what the real gh, logged out, says for v0.31.3 (no assets); a
# uname stub reports Linux riscv64; the gh stub reports a version below BINARY_GH_MIN, or one it cannot
# read, and then no release download is logged; no gh on PATH.
#   Real go behind a logging stub: each way exits 0, prints the word, prints one stderr line saying it
#     built from source and why, and leaves an executable <copy>/swarm and no .fetch-* folder.
#   go a stub that logs and fails, and no go on PATH: each way exits 1 with one stderr line naming why
#     the download could not work and go.mod's Go version, nothing on stdout and no <copy>/swarm.
#   A wrong checksum and a failing attestation, with real go: the fetch's one-line stop, and go never runs.
#   A gh too old to download, in a copy with no scripts/build.sh: the broken-copy stop, as with a fit gh,
#   and go never runs. A folder at <copy>/swarm: one line naming why and the folder, and go never runs.
#   A KILL to the call's group while the go stub holds mid-build: no <copy>/swarm, and a swarm.build-<pid>
#     file that is not executable. The next call builds and exits 0.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
# shellcheck source=tests/binary_fetch_stubs.sh
source "$(dirname "${BASH_SOURCE[0]}")/binary_fetch_stubs.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_GO="$(command -v go)" || { echo "FAIL go is not on PATH, and make test needs it"; exit 1; }
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[[ -d "${tmp}" ]] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'stop_groups "${ROOT}/groups"; stop_test_group; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, as every test file

WORD=fallback-built
SUMS=SHA256SUMS
WAIT_S=60   # how long a read on a fifo waits for the go stub
VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "${REPO}/.claude-plugin/plugin.json")"
GO_WANT="$(sed -n 's/^go \([0-9.]*\)$/\1/p' "${REPO}/go.mod")"
[[ -n "${GO_WANT}" ]] || { echo "FAIL ${REPO}/go.mod has no go line"; exit 1; }
# The stderr texts the gh stub's release download fails with. LOGIN is what gh 2.101.0 prints, exit 4,
# for a command that needs a login (gh api, gh attestation verify) with an empty GH_CONFIG_DIR and no
# token. NO_ASSETS is what it prints, exit 1, for `gh release download v0.31.3 --pattern x` logged out:
# a public release downloads with no login. Both were run against the real gh (see the PR).
OFFLINE='Get "https://api.github.com/repos/redscaresu/swarm-dev/releases/tags/v0": dial tcp: lookup api.github.com: no such host'
LOGIN=$'To get started with GitHub CLI, please run:  gh auth login\nAlternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.'
NO_ASSETS='no assets to download'

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
lines() { # <text>: its number of lines, 0 for none
  if [[ -z "$1" ]]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi
}
# has <pattern> <text> — yes when a line of <text> matches the grep pattern, else no.
has() { if grep -q -- "$1" <<< "$2"; then echo yes; else echo no; fi; }

case "$(uname -s)" in Darwin) OS=darwin ;; Linux) OS=linux ;; *) OS="" ;; esac
case "$(uname -m)" in x86_64) ARCH=amd64 ;; arm64|aarch64) ARCH=arm64 ;; *) ARCH="" ;; esac
[[ -n "${OS}" && -n "${ARCH}" ]] || { echo "FAIL this test runs on darwin or linux, amd64 or arm64"; exit 1; }
ASSET="swarm-${OS}-${ARCH}"
F="${ROOT}/fetch"; fetch_stubs "${F}" "${VERSION}" || exit 1
fetch_release "${F}" "${ASSET}" "${SUMS}" || exit 1

# without <prog> <path> — <path> with each folder that holds <prog> replaced by one of links to the rest.
without() {
  local d out="" dirs=() i=0 s
  IFS=: read -r -a dirs <<< "$2"
  for d in "${dirs[@]}"; do
    if [[ -n "${d}" && -e "${d}/$1" ]]; then
      i=$((i + 1)); s="${ROOT}/no-$1-${i}"; mkdir -p "${s}"
      ln -s "${d}"/* "${s}/" 2>/dev/null || true
      rm -f "${s}/$1"; d="${s}"
    fi
    out="${out:+${out}:}${d}"
  done
  printf '%s\n' "${out}"
}
BASE_NOGO="$(without go "${PATH}")"        # the system, with no go
BASE_NONE="$(without gh "${BASE_NOGO}")"   # and no gh
check "the bare PATH has bash, and no go or gh" "yes||" \
  "$(PATH="${BASE_NONE}" command -v bash > /dev/null && echo yes)|$(PATH="${BASE_NONE}" command -v go || true)|$(PATH="${BASE_NONE}" command -v gh || true)"

# The go stubs, each first on PATH in a folder of its own. real: logs each call, then runs the real go.
# fail: logs each call and exits 1. hold: on build, writes half a file to its -o path, says so on
# sync/held, and blocks on a fifo no one writes.
LOGS="${ROOT}/logs"; REALGO="${ROOT}/realgo"; FAILGO="${ROOT}/failgo"; HOLDGO="${ROOT}/holdgo"
mkdir -p "${LOGS}" "${REALGO}" "${FAILGO}" "${HOLDGO}" "${ROOT}/sync"
printf '#!/bin/sh\necho "$*" >> "%s/go"\nexec "%s" "$@"\n' "${LOGS}" "${REAL_GO}" > "${REALGO}/go"
printf '#!/bin/sh\necho "$*" >> "%s/go"\nexit 1\n' "${LOGS}" > "${FAILGO}/go"
mkfifo "${ROOT}/sync/held" "${ROOT}/sync/never"
cat > "${HOLDGO}/go" <<EOF
#!/bin/sh
echo "\$*" >> "${LOGS}/go"
[ "\$1" = build ] || exit 1
out= prev=
for a in "\$@"; do [ "\${prev}" = -o ] && out="\${a}"; prev="\${a}"; done
printf '#!/bin/sh\\necho half' > "\${out}"
echo held > "${ROOT}/sync/held"
read -r _ < "${ROOT}/sync/never"
EOF
chmod +x "${REALGO}/go" "${FAILGO}/go" "${HOLDGO}/go"
# log <name> — a log since the last read, then emptied: go's, or the gh stub's.
log() { local f="${LOGS}/$1"; [[ "$1" != gh ]] || f="${F}/log/gh"; cat "${f}" 2>/dev/null || true; rm -f "${f}"; }

# The project: not a git repo.
P="${ROOT}/proj"; mkdir -p "${P}/.claude/swarm"
printf 'board_dir = board\n' > "${P}/.claude/swarm/config"

# copy <dir> — a copy of the plugin as an install leaves it, with no .git: bin/ with the config marker,
# scripts/build.sh, .claude-plugin/, go.mod, and a cmd/swarm/main.go that prints WORD.
copy() {
  mkdir -p "$1/scripts" "$1/cmd/swarm"
  cp -R "${REPO}/bin" "${REPO}/.claude-plugin" "${REPO}/go.mod" "$1/"
  cp "${REPO}/scripts/build.sh" "$1/scripts/"
  mkdir -p "$1/bin/ported"; : > "$1/bin/ported/config"
  printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println("%s") }\n' "${WORD}" > "$1/cmd/swarm/main.go"
}
# sw <copy> <path> — run <copy>'s swarm.sh config from the project with PATH <path>, and SWARMDEV_BIN and
# GH_HOST unset (an exported GH_HOST would reach the gh stub's log). Sets out, err and rc.
sw() {
  rc=0
  (cd "${P}" || exit 1
   env -u HERDR_ENV -u SWARM_PROJECT -u SWARMDEV_BIN -u GH_HOST PATH="$2" bash "$1/bin/swarm.sh" config) \
    < /dev/null > "${ROOT}/out" 2> "${ROOT}/err" || rc=$?
  out="$(cat "${ROOT}/out")"; err="$(cat "${ROOT}/err")"
}
# state <copy> — "executable" when <copy>/swarm is an executable file, "none" when there is none.
state() { if [[ ! -e "$1/swarm" ]]; then echo none; elif [[ -f "$1/swarm" && -x "$1/swarm" ]]; then echo executable; else echo other; fi; }
# temps <copy> — the .fetch-* folders in <copy>, one a line.
temps() { (cd "$1" && find . -maxdepth 1 -name '.fetch-*' | sort); }

# way <name> — set the stubs for one way the download cannot work. Sets GH_PATH, the PATH behind the go
# folder (no go in it), and WHY, how the stderr line's reason starts.
way() {
  rm -f "${F}/stub/download.stderr"; fetch_uname "${F}"
  printf '%s\n' "${FETCH_GH_MIN}" > "${F}/stub/gh-version"
  GH_PATH="${F}/bin:${BASE_NOGO}"
  local dl="gh release download v${VERSION} --repo github.com/${FETCH_REPO} failed:"
  case "$1" in
    offline) printf '%s\n' "${OFFLINE}" > "${F}/stub/download.stderr"; WHY="${dl} '${OFFLINE}'" ;;
    login) printf '%s\n' "${LOGIN}" > "${F}/stub/download.stderr"; WHY="${dl} '${LOGIN%%$'\n'*}'" ;;
    no-assets) printf '%s\n' "${NO_ASSETS}" > "${F}/stub/download.stderr"; WHY="${dl} '${NO_ASSETS}'" ;;
    riscv64) fetch_uname "${F}" Linux riscv64; WHY="swarm-dev publishes no binary for linux/riscv64 (uname: Linux riscv64)" ;;
    old-gh) printf '2.56.9\n' > "${F}/stub/gh-version"; WHY="gh 2.56.9 is older than ${FETCH_GH_MIN}," ;;
    odd-gh) printf 'DEV\n' > "${F}/stub/gh-version"
      WHY="gh --version's first line, 'gh version DEV (2026-09-15)', is not 'gh version X.Y.Z', so this gh counts as older than ${FETCH_GH_MIN}," ;;
    no-gh) GH_PATH="${BASE_NONE}"; WHY="gh is not on PATH," ;;
    works) WHY="" ;;   # the download works, and a check can fail
  esac
}
WAYS="offline login no-assets riscv64 old-gh odd-gh no-gh"

# --- Real go: each way builds from source, says so in one line, and runs the command.
n=0
for w in ${WAYS}; do
  n=$((n + 1)); c="${ROOT}/real-${n}"; copy "${c}"; way "${w}"; log go > /dev/null; log gh > /dev/null
  sw "${c}" "${REALGO}:${GH_PATH}"
  gh_calls="$(log gh)"
  check "${w}, real go: exits 0 and prints the word" "0|${WORD}" "${rc}|${out}"
  check "${w}, real go: one stderr line, saying it built from source and why" "1|yes" \
    "$(lines "${err}")|$([[ "${err}" == "binary: built from source, as ${WHY}"* ]] && echo yes || echo "no: ${err}")"
  check "${w}, real go: an executable <copy>/swarm, and no .fetch-* folder" "executable|" "$(state "${c}")|$(temps "${c}")"
  check "${w}, real go: go built" yes "$(has '^build ' "$(log go)")"
  case "${w}" in
    login) check "login, real go: the line names gh auth login and not the network" yes \
      "$([[ "${err}" == *"gh auth login"* && "${err}" != *network* ]] && echo yes || echo no)" ;;
    old-gh|odd-gh) check "${w}, real go: gh ran --version alone, so no release download was logged" "GH_HOST= --version" "${gh_calls}" ;;
  esac
done

# --- go that fails, and no go: each way stops in one line naming why and go.mod's Go version.
for g in fail none; do
  n=0
  for w in ${WAYS}; do
    n=$((n + 1)); c="${ROOT}/${g}-${n}"; copy "${c}"; way "${w}"; log go > /dev/null
    # GH_PATH holds no go, so with none it is the whole PATH.
    if [[ "${g}" == fail ]]; then sw "${c}" "${FAILGO}:${GH_PATH}"; else sw "${c}" "${GH_PATH}"; fi
    built="$(has '^build ' "$(log go)")"
    check "${w}, go ${g}: exits 1, nothing on stdout" "1|" "${rc}|${out}"
    check "${w}, go ${g}: one stderr line, naming why the download could not work and Go ${GO_WANT}" "1|yes|yes" \
      "$(lines "${err}")|$([[ "${err}" == "binary: ${WHY}"* ]] && echo yes || echo "no: ${err}")|$([[ "${err}" == *"Go ${GO_WANT} or later"* ]] && echo yes || echo no)"
    check "${w}, go ${g}: no <copy>/swarm, and no .fetch-* folder" "none|" "$(state "${c}")|$(temps "${c}")"
    [[ "${g}" == none ]] || check "${w}, go fail: the fail stub was asked to build" yes "${built}"
  done
done

# --- A download that fails its checks stops, with real go on PATH, and builds nothing.
way works
C="${ROOT}/sum"; copy "${C}"; log go > /dev/null
printf '%064d  %s\n' 0 "${ASSET}" > "${F}/release/${SUMS}"
sw "${C}" "${REALGO}:${GH_PATH}"
check "a wrong checksum, real go: exits 1 in the fetch's one line, nothing on stdout" "1|1|yes|" \
  "${rc}|$(lines "${err}")|$([[ "${err}" == "binary: the SHA-256 of v${VERSION}'s ${ASSET} does not match"* ]] && echo yes || echo "no: ${err}")|${out}"
check "a wrong checksum, real go: go never ran, and no <copy>/swarm" "|none" "$(log go)|$(state "${C}")"
fetch_release "${F}" "${ASSET}" "${SUMS}"
C="${ROOT}/attest"; copy "${C}"; : > "${F}/stub/attest.fail"
sw "${C}" "${REALGO}:${GH_PATH}"
check "a failing attestation, real go: exits 1 in the fetch's one line, nothing on stdout" "1|1|yes|" \
  "${rc}|$(lines "${err}")|$([[ "${err}" == "binary: gh attestation verify failed for ${C}/.fetch-"*"/${ASSET}, so"* ]] && echo yes || echo "no: ${err}")|${out}"
check "a failing attestation, real go: go never ran, and no <copy>/swarm" "|none" "$(log go)|$(state "${C}")"
rm -f "${F}/stub/attest.fail"

# --- A broken copy stops with an old gh too, and a folder at <copy>/swarm is never built into.
way old-gh; C="${ROOT}/broken"; copy "${C}"; rm -f "${C}/scripts/build.sh"; log go > /dev/null; log gh > /dev/null
sw "${C}" "${REALGO}:${GH_PATH}"
check "old gh, no scripts/build.sh: exits 1 in the broken-copy line, nothing on stdout" "1|1|yes|" \
  "${rc}|$(lines "${err}")|$([[ "${err}" == "binary: cannot tell which release files are this copy's binary: ${C}/scripts/build.sh is missing: reinstall swarm-dev"* ]] && echo yes || echo "no: ${err}")|${out}"
check "old gh, no scripts/build.sh: go never ran, gh ran --version alone, and no <copy>/swarm" "|GH_HOST= --version|none" \
  "$(log go)|$(log gh)|$(state "${C}")"
way offline; C="${ROOT}/folder"; copy "${C}"; mkdir "${C}/swarm"; log go > /dev/null
sw "${C}" "${REALGO}:${GH_PATH}"
check "a folder at <copy>/swarm: exits 1 in one line naming why and the folder, nothing on stdout" "1|1|yes|yes|" \
  "${rc}|$(lines "${err}")|$([[ "${err}" == "binary: ${WHY}"* ]] && echo yes || echo "no: ${err}")|$([[ "${err}" == *"${C}/swarm is a folder"* ]] && echo yes || echo no)|${out}"
check "a folder at <copy>/swarm: go never ran, and the folder is still empty" "|" "$(log go)|$(ls -A "${C}/swarm")"

# --- A KILL to the call's group while the build holds, then a call that builds.
way offline; K="${ROOT}/kill"; copy "${K}"
exec 7<>"${ROOT}/sync/held"
(cd "${P}" || exit 1
 in_new_group env -u HERDR_ENV -u SWARM_PROJECT -u SWARMDEV_BIN -u GH_HOST PATH="${HOLDGO}:${GH_PATH}" bash "${K}/bin/swarm.sh" config) \
  < /dev/null > "${ROOT}/kill.out" 2> "${ROOT}/kill.err" &
kill_pid=$!
group_record "${kill_pid}" "${ROOT}/groups"
if read -r -t "${WAIT_S}" -u 7 _; then
  stop_group "${kill_pid}" "${ROOT}/groups"
  left="$(cd "${K}" && find . -maxdepth 1 -name 'swarm.build-*')"
  check "KILL mid-build: no <copy>/swarm" none "$(state "${K}")"
  check "KILL mid-build: one swarm.build-<pid> file is left, not executable" "1|" \
    "$(lines "${left}")|$(cd "${K}" && find . -maxdepth 1 -name 'swarm.build-*' -perm -u+x)"
  log go > /dev/null
  sw "${K}" "${REALGO}:${GH_PATH}"
  check "KILL, the next call: builds, exits 0 and prints the word" "0|${WORD}|executable|yes" \
    "${rc}|${out}|$(state "${K}")|$(has '^build ' "$(log go)")"
else
  check "KILL: the go stub held mid-build" yes no
  stop_group "${kill_pid}" "${ROOT}/groups" || true
fi
exec 7>&-

[[ "${fails}" -eq 0 ]] || { echo "${fails} check(s) failed"; exit 1; }
echo "all binary_fallback checks passed"
