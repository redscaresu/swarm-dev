# shellcheck shell=bash
# binary.sh — find the swarm binary a command runs, and run it. A hook sources it on its own, and
# bin/swarm.sh with its other libs: it needs no other bin/lib file, sets no shell option and starts no
# process when sourced, and binary_find and is_ported start none either. binary_run is swarm.sh's
# alone. It never builds and never downloads.

# BINARY_BUILD_PATH: where a git checkout of the plugin keeps the binary built from its tree, relative to
# the plugin root. It is the file `go build ./cmd/swarm` writes at the root, which .gitignore already
# ignores, and it is outside bin/, which several tests scan file by file.
BINARY_BUILD_PATH=swarm

# binary_find <plugin root> — print the path of the binary to run and return 0, or print one line on
# stderr saying why there is none and return 1. The caller passes the root: a hook its own, swarm.sh
# the plugin root it runs from. It reads no setting of swarm.sh's.
#   SWARMDEV_BIN set, even empty: that file and nothing else. A missing or non-executable file is an
#     error, never a fall-through to the build path.
#   SWARMDEV_BIN unset, the root a git checkout (its .git a directory, or a worktree's file): the
#     executable at <root>/BINARY_BUILD_PATH. It does not check whether that file is older than the tree.
#   Otherwise (an installed copy has no .git): there is no binary.
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
    echo "binary: no swarm binary: SWARMDEV_BIN is unset and ${root} is not a git checkout" >&2; return 1
  fi
  built="${root}/${BINARY_BUILD_PATH}"
  if [[ ! -f "${built}" || ! -x "${built}" ]]; then
    echo "binary: no swarm binary: SWARMDEV_BIN is unset and ${built} is not an executable file" >&2; return 1
  fi
  printf '%s\n' "${built}"
}

# PORTED_NAME_RE: the dispatch names a marker can send to the binary. It holds no / and no leading .,
# so no name reaches a file outside bin/ported/ or a dotfile in it.
PORTED_NAME_RE='^[a-z_][a-z0-9_-]*$'

# is_ported <name> — true when <name> is a ported command: it matches PORTED_NAME_RE and its marker, an
# empty file bin/ported/<name> under SWARM_HOME, exists. Builtins only, no fork: dispatch asks it of
# every command, and a command with no marker must start no more processes than before.
is_ported() { [[ "$1" =~ ${PORTED_NAME_RE} && -f "${SWARM_HOME}/bin/ported/$1" ]]; }   # loose-match: ok PORTED_NAME_RE is a fixed regex

# binary_run <name> [args] — bin/swarm.sh's dispatch of a ported command: run the file binary_find
# names (or die with its line) as `<binary> <name> [args]`, in a subshell, and return its exit
# code. stdin passes through. It hands over the frame (cmd/swarm/frame.go): SWARMDEV_HOME,
# SWARMDEV_PROJECT, SWARMDEV_BOARD, and each CONFIG_KEYS key as SWARMDEV_CFG_<key> and SWARMDEV_SRC_<key>,
# valued as `swarm.sh config` shows them (board_dir and repos_dir resolved). The die file and the fields
# file pass only at the command's own level, as die() and event_fields keep them. Every name is set on
# each run, empty values included, and any other SWARMDEV_CFG_ or SWARMDEV_SRC_ name is unset, so a
# swarm.sh the binary runs never takes its parent's die file or settings. Only swarm.sh calls it: it
# needs die, CONFIG_KEYS and the settings.
binary_run() {
  local bin die_file="" fields_file="" key v n
  bin="$(binary_find "${SWARM_HOME}" 2>&1)" || die "${bin}"
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
