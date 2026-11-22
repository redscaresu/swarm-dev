# shellcheck shell=bash
# binary.sh — find the swarm binary a command runs, and run it. A hook sources it on its own, and
# bin/swarm.sh with its other libs: it needs no other bin/lib file, sets no shell option and starts no
# process when sourced, and binary_find and is_ported start none either. binary_path and binary_run are
# swarm.sh's alone. Only binary_build builds, and only binary_path calls it, in a git checkout; nothing
# here downloads.

# BINARY_BUILD_PATH: where a git checkout of the plugin keeps the binary built from its tree, relative to
# the plugin root. It is the file `go build ./cmd/swarm` writes at the root, which .gitignore already
# ignores, and it is outside bin/, which several tests scan file by file.
BINARY_BUILD_PATH=swarm
# BINARY_BUILD_TMP: the suffix of the file binary_build builds into beside BINARY_BUILD_PATH, before its
# rename; the caller's PID follows it. .gitignore ignores it too, so a build cut short leaves no
# untracked file.
BINARY_BUILD_TMP=.build-

# binary_find <plugin root> — print the path of the binary to run and return 0, or print one line on
# stderr saying why there is none and return 1. The caller passes the root: a hook its own, swarm.sh
# the plugin root it runs from. It reads no setting of swarm.sh's.
#   SWARMDEV_BIN set, even empty: that file and nothing else. A missing or non-executable file is an
#     error, never a fall-through to the build path.
#   SWARMDEV_BIN unset, the root a git checkout (its .git a directory, or a worktree's file): the
#     executable at <root>/BINARY_BUILD_PATH. It does not check whether that file is older than the tree.
#   Otherwise (an installed copy has no .git): the executable at <root>/BINARY_BUILD_PATH, where an
#     installed copy keeps its binary. With no executable file there, one line saying the root is not a
#     git checkout.
binary_find() {
  local root="${1:-}" built
  if [[ -n "${SWARMDEV_BIN+set}" ]]; then
    if [[ ! -f "${SWARMDEV_BIN}" ]]; then
      echo "binary: SWARMDEV_BIN names '${SWARMDEV_BIN}', which is not a file" >&2; return 1
    elif [[ ! -x "${SWARMDEV_BIN}" ]]; then
      echo "binary: SWARMDEV_BIN names '${SWARMDEV_BIN}', which is not executable" >&2; return 1
    fi
    printf '%s\n' "${SWARMDEV_BIN}"; return 0
  fi
  if [[ -z "${root}" ]]; then
    echo "binary: no swarm binary: binary_find was given no plugin root" >&2; return 1
  fi
  root="${root%/}"
  if [[ ! -e "${root}/.git" ]]; then
    built="${root}/${BINARY_BUILD_PATH}"
    if [[ -f "${built}" && -x "${built}" ]]; then printf '%s\n' "${built}"; return 0; fi
    echo "binary: no swarm binary: SWARMDEV_BIN is unset and ${root} is not a git checkout" >&2; return 1
  fi
  built="${root}/${BINARY_BUILD_PATH}"
  if [[ ! -f "${built}" || ! -x "${built}" ]]; then
    echo "binary: no swarm binary: SWARMDEV_BIN is unset and ${built} is not an executable file" >&2; return 1
  fi
  printf '%s\n' "${built}"
}

# binary_stale <root> <binary> — true when a file the binary is built from is newer than <binary>: a .go
# file under <root>/cmd or <root>/internal (each when it exists), or <root>/go.mod or go.sum. It looks
# nowhere else under the root, whose .swarm/ can hold hundreds of MB. find's -newer and -print -quit
# are BSD's and GNU's both.
binary_stale() {
  local root="$1" bin="$2" dirs=() d
  [[ "${root}/go.mod" -nt "${bin}" || "${root}/go.sum" -nt "${bin}" ]] && return 0
  for d in cmd internal; do [[ -d "${root}/${d}" ]] && dirs+=("${root}/${d}"); done
  [[ ${#dirs[@]} -gt 0 ]] || return 1
  [[ -n "$(find "${dirs[@]}" -type f -name '*.go' -newer "${bin}" -print -quit 2>/dev/null)" ]]
}

# binary_go_want <root> — print the Go version <root>/go.mod's `go` line names (1.27.1), read with
# builtins, and return 0; print nothing and return 1 when it has no such line.
binary_go_want() {
  local k v rest
  while read -r k v rest || [[ -n "${k}" ]]; do
    if [[ "${k}" == go && -n "${v}" ]]; then printf '%s\n' "${v}"; return 0; fi
  done < "$1/go.mod"
  return 1
}

# binary_go_older <have> <want> — true when Go version <have> (`go env GOVERSION`: go1.25.3, and any
# word after the first ignored) is older than <want> (go.mod's: 1.27.1), by a numeric compare of the
# dotted fields, a missing field counting as 0. Returns 1 when it is not older, or when either is not
# all dotted numbers once a leading go is dropped (a devel build, an rc): the caller then says nothing
# about versions, as it cannot tell.
binary_go_older() {
  local have="${1%% *}" want="${2%% *}" re='^[0-9]+(\.[0-9]+)*$' h=() w=() i a b
  have="${have#go}"; want="${want#go}"
  [[ "${have}" =~ ${re} && "${want}" =~ ${re} ]] || return 1   # loose-match: ok re is a fixed regex
  IFS=. read -r -a h <<< "${have}"; IFS=. read -r -a w <<< "${want}"
  for ((i = 0; i < ${#h[@]} || i < ${#w[@]}; i++)); do
    a="${h[i]:-0}"; b="${w[i]:-0}"
    if ((10#${a} != 10#${b})); then ((10#${a} < 10#${b})); return; fi
  done
  return 1
}

# binary_build <root> — build ./cmd/swarm from the source at <root> into <root>/BINARY_BUILD_PATH and
# return 0, printing nothing. <root> may be a git checkout or an installed copy with no .git. go builds
# into a file of its own beside the binary, <root>/swarm.build-<pid> (BINARY_BUILD_PATH, BINARY_BUILD_TMP
# and the caller's PID), which is then renamed over it, so a call started at the same time never runs
# half a file. A KILL mid-build leaves that file, which no call runs.
# Each stop prints one `binary: ` line on stderr (a failed build's then has Go's error after it), returns
# 1 and leaves any old binary as it was:
#   <root> has no go.mod or no cmd/swarm (an installed 0.31.x has no source);
#   no go on PATH: the line names go.mod's Go version;
#   a failed build: when the installed Go (GOTOOLCHAIN=local go env GOVERSION, run from /, so the probe
#     never tries to fetch a newer Go) is older than go.mod's by binary_go_older, the line names both and
#     says to install go.mod's or reconnect so Go can fetch it. Otherwise, or with a GOVERSION it cannot
#     read, the line says only that the build failed.
# Only binary_path calls it.
binary_build() {
  local root="${1%/}" built tmp out want have
  built="${root}/${BINARY_BUILD_PATH}"
  if [[ ! -f "${root}/go.mod" ]]; then
    echo "binary: ${root} has no go.mod, so it holds no source to build the swarm binary from" >&2; return 1
  fi
  if [[ ! -d "${root}/cmd/swarm" ]]; then
    echo "binary: ${root} has no cmd/swarm, so it holds no source to build the swarm binary from" >&2; return 1
  fi
  want="$(binary_go_want "${root}")" || want=""
  if ! command -v go >/dev/null 2>&1; then
    echo "binary: go is not on PATH, and the swarm binary builds from the source in ${root}: install Go${want:+ ${want} or later, the version ${root}/go.mod names}" >&2
    return 1
  fi
  tmp="${built}${BINARY_BUILD_TMP}$$"
  if ! out="$(cd "${root}" && go build -o "${tmp}" ./cmd/swarm 2>&1)"; then
    rm -f "${tmp}"
    have="$(cd / && GOTOOLCHAIN=local go env GOVERSION 2>/dev/null)" || have=""
    if binary_go_older "${have}" "${want}"; then
      printf 'binary: go build ./cmd/swarm failed in %s, and the installed Go is %s, older than the %s go.mod names: install Go %s or later, or reconnect so Go can fetch it:\n%s\n' \
        "${root}" "${have}" "${want}" "${want}" "${out}" >&2
    else
      printf 'binary: go build ./cmd/swarm failed in %s, so the ported command did not run:\n%s\n' "${root}" "${out}" >&2
    fi
    return 1
  fi
  mv -f "${tmp}" "${built}" || { rm -f "${tmp}"; echo "binary: could not move the build to ${built}" >&2; return 1; }
}

# binary_path <plugin root> — binary_find, and in a git checkout with SWARMDEV_BIN unset, the binary
# built from the checkout's tree. It prints the path to run and returns 0, or prints why there is none
# on stderr, its first line one line of its own, and returns 1.
#   SWARMDEV_BIN set, or the root no git checkout: binary_find's answer, unchanged. It builds nothing.
#   A git checkout: binary_build builds ./cmd/swarm into <root>/BINARY_BUILD_PATH when there is no
#     executable file there, or when binary_stale says the tree is newer. With no go on PATH it stops in
#     one line of its own, naming SWARMDEV_BIN, before binary_build runs. A failed build stops with
#     binary_build's line and Go's error, and leaves the old binary as it was; the caller never runs
#     the old one.
# Only binary_run calls it, for a marked command, so no other command starts a find. A hook that
# needs the binary uses binary_find, which never builds.
binary_path() {
  local root="${1:-}" built
  if [[ -n "${SWARMDEV_BIN+set}" || -z "${root}" || ! -e "${root%/}/.git" ]]; then
    binary_find "${root}"; return
  fi
  root="${root%/}"; built="${root}/${BINARY_BUILD_PATH}"
  if [[ -f "${built}" && -x "${built}" ]] && ! binary_stale "${root}" "${built}"; then
    printf '%s\n' "${built}"; return 0
  fi
  if ! command -v go >/dev/null 2>&1; then
    echo "binary: ${root} is a git checkout, which builds the ported command's binary from its tree, and go is not on PATH: install Go, or set SWARMDEV_BIN to a swarm binary" >&2
    return 1
  fi
  binary_build "${root}" || return 1
  printf '%s\n' "${built}"
}

# PORTED_NAME_RE: the dispatch names a marker can send to the binary. It holds no / and no leading .,
# so no name reaches a file outside bin/ported/ or a dotfile in it.
PORTED_NAME_RE='^[a-z_][a-z0-9_-]*$'

# is_ported <name> — true when <name> is a ported command: it matches PORTED_NAME_RE and its marker, an
# empty file bin/ported/<name> under SWARM_HOME, exists. Builtins only, no fork: dispatch asks it of
# every command, and a command with no marker must start no more processes than before.
is_ported() { [[ "$1" =~ ${PORTED_NAME_RE} && -f "${SWARM_HOME}/bin/ported/$1" ]]; }   # loose-match: ok PORTED_NAME_RE is a fixed regex

# binary_run <name> [args] — bin/swarm.sh's dispatch of a ported command: run the file binary_path
# names (or die with its line, and any Go error after it) as `<binary> <name> [args]`, in a subshell,
# and return its exit code. stdin passes through. It hands over the frame (cmd/swarm/frame.go): SWARMDEV_HOME,
# SWARMDEV_PROJECT, SWARMDEV_BOARD, and each CONFIG_KEYS key as SWARMDEV_CFG_<key> and SWARMDEV_SRC_<key>,
# valued as `swarm.sh config` shows them (board_dir and repos_dir resolved). The die file and the fields
# file pass only at the command's own level, as die() and event_fields keep them. Every name is set on
# each run, empty values included, and any other SWARMDEV_CFG_ or SWARMDEV_SRC_ name is unset, so a
# swarm.sh the binary runs never takes its parent's die file or settings. Only swarm.sh calls it: it
# needs die, CONFIG_KEYS and the settings.
binary_run() {
  local bin die_file="" fields_file="" key v n
  bin="$(binary_path "${SWARM_HOME}" 2>&1)" || die "${bin}"
  # A bare name (SWARMDEV_BIN=swarm) is the file binary_find checked in the cwd, never a PATH lookup.
  [[ "${bin}" == */* ]] || bin="./${bin}"
  if [[ -n "${DIE_FILE}" && "${BASH_SUBSHELL}" == "${DIE_LEVEL}" ]]; then
    die_file="${DIE_FILE}"
    [[ -z "${EV_FIELDS_FILE}" || "${DIE_FILE}" != "${EV_ERR}" ]] || fields_file="${EV_FIELDS_FILE}"
  fi
  (
    for n in $(compgen -e); do
      case "${n}" in SWARMDEV_CFG_*|SWARMDEV_SRC_*) unset "${n}" ;; esac
    done
    export SWARMDEV_HOME="${SWARM_HOME}" SWARMDEV_PROJECT="${PROJECT_DIR}" SWARMDEV_BOARD="${BOARD}" \
      SWARMDEV_DIE_FILE="${die_file}" SWARMDEV_FIELDS_FILE="${fields_file}"
    for key in ${CONFIG_KEYS}; do
      # As show_config gives them.
      case "${key}" in board_dir) v=BOARD ;; repos_dir) v=REPOS_DIR ;; *) v="CFG_${key}" ;; esac
      export "SWARMDEV_CFG_${key}=${!v}"
      v="SRC_${key}"; export "SWARMDEV_SRC_${key}=${!v}"
    done
    exec "${bin}" "$@"
  )
}
