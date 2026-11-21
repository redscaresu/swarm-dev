# shellcheck shell=bash
# binary.sh — find the swarm binary a command runs. A hook sources it on its own, and so will
# bin/swarm.sh: it needs no other bin/lib file, sets no shell option and starts no process when
# sourced, and binary_find starts none either. It never builds and never downloads.

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
