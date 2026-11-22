# shellcheck shell=bash
# binary.sh — find the swarm binary a command runs, run it, and download a release's binary. A hook
# sources it on its own, and bin/swarm.sh with its other libs: it needs no other bin/lib file, sets no
# shell option and starts no process when sourced, and binary_find and is_ported start none either.
# binary_path and binary_run are swarm.sh's alone. Only binary_path builds, and only in a git checkout.
# Only binary_download downloads: with gh, into a folder its caller gives, and it checks the file
# against the release's checksum file. It never writes <root>/swarm.

# BINARY_BUILD_PATH: where a git checkout of the plugin keeps the binary built from its tree, relative to
# the plugin root. It is the file `go build ./cmd/swarm` writes at the root, which .gitignore already
# ignores, and it is outside bin/, which several tests scan file by file.
BINARY_BUILD_PATH=swarm
# BINARY_BUILD_TMP: the suffix of the file binary_path builds into beside BINARY_BUILD_PATH, before its
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

# binary_path <plugin root> — binary_find, and in a git checkout with SWARMDEV_BIN unset, the binary
# built from the checkout's tree. It prints the path to run and returns 0, or prints why there is none
# on stderr, its first line one line of its own, and returns 1.
#   SWARMDEV_BIN set, or the root no git checkout: binary_find's answer, unchanged. It builds nothing.
#   A git checkout: it builds ./cmd/swarm into <root>/BINARY_BUILD_PATH when there is no executable file
#     there, or when binary_stale says the tree is newer. go builds into a file of its own beside it,
#     which is then renamed over it, so a call started at the same time never runs half a file. With no
#     go on PATH it stops in one line. A failed build stops with a line and Go's error, removes its own
#     file and leaves the old binary as it was; the caller never runs the old one.
# Only binary_run calls it, for a marked command, so no other command starts a find. A hook that
# needs the binary uses binary_find, which never builds.
binary_path() {
  local root="${1:-}" built tmp out
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
  tmp="${built}${BINARY_BUILD_TMP}$$"
  if ! out="$(cd "${root}" && go build -o "${tmp}" ./cmd/swarm 2>&1)"; then
    rm -f "${tmp}"
    printf 'binary: go build ./cmd/swarm failed in %s, so the ported command did not run:\n%s\n' "${root}" "${out}" >&2
    return 1
  fi
  mv -f "${tmp}" "${built}" || { rm -f "${tmp}"; echo "binary: could not move the build to ${built}" >&2; return 1; }
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

# binary_repo — the GitHub repository whose releases hold the swarm binaries, as <owner>/<repo>.
binary_repo() { printf '%s\n' redscaresu/swarm-dev; }

# BINARY_CANNOT: binary_download's return code when the download cannot work here: this platform has no
# release binary, gh is not on PATH, or gh release download failed (no network, no login, no such
# release). Its caller builds from source on it and on nothing else. Every other failure returns 1: a
# broken install, or a download that failed its check, which a build from source must not hide.
BINARY_CANNOT=3
# BINARY_NAME_RE: an asset or checksum file name binary_download takes from scripts/build.sh --list.
# gh's --pattern is a glob, so a name with *, ? or [ could fetch more than one file, and a / could name
# a file outside the folder.
BINARY_NAME_RE='^[A-Za-z0-9][A-Za-z0-9._-]*$'
# BINARY_SUM_RE: a checksum file's line in sha256sum's format: the hex sum, a space, then a space (text
# mode) or a * (binary mode), then the file's name.
BINARY_SUM_RE='^([^ ]+) [ *](.*)$'

# binary_download <root> <version> <dir> — download release v<version>'s binary for this platform, and
# its checksum file, from github.com/<binary_repo> into <dir>, an existing folder, and check the
# binary's SHA-256. On success it prints nothing and returns 0, with both files in <dir>; it does not
# make the binary executable or move it. On failure it prints one `binary: ` line on stderr that says
# what failed and what to do, and returns BINARY_CANNOT or 1 (BINARY_CANNOT's comment says which). A
# failed check can leave both files in <dir>, and the caller removes <dir>.
#   The names: the asset line for this platform and the checksums line of `scripts/build.sh --list`
#     under <root>, the release contract. No copy of them is kept here.
#   The platform: uname -s and uname -m, as --list's <os>/<arch>: Darwin darwin, Linux linux, x86_64
#     amd64, arm64 and aarch64 arm64. Any other value is looked up as it is.
#   gh: from PATH, with the host named in --repo, so GH_HOST never sends the call to another host. Of
#     gh's output, only its first non-empty stderr line is ever shown.
#   The check: the one line of the checksum file whose name field is exactly the asset's name. No such
#     line, two of them, or another sum fails.
# It writes only inside <dir>, and runs no python3 or curl.
binary_download() {
  local root="${1:-}" version="${2:-}" dir="${3:-}" build list s m os arch kind f2 f3 why=""
  local asset="" n_asset=0 n_all=0 sums="" n_sums=0 repo report err line file got want="" n=0 sum_cmd=()
  local fix="reinstall swarm-dev (claude plugin uninstall swarm-dev@swarm-dev, then claude plugin install swarm-dev@swarm-dev)"
  if [[ -z "${root}" || -z "${version}" || ! -d "${dir}" ]]; then
    echo "binary: binary_download needs a plugin root, a version and an existing folder; it got '${root}' '${version}' '${dir}'" >&2
    return 1
  fi
  root="${root%/}"; build="${root}/scripts/build.sh"
  if [[ ! -f "${build}" ]]; then
    why="${build} is missing"
  elif ! list="$("${BASH}" "${build}" --list 2>/dev/null)"; then
    why="${build} --list failed"
  fi
  if [[ -n "${why}" ]]; then
    echo "binary: cannot tell which release files are this copy's binary: ${why}: ${fix}" >&2; return 1
  fi
  s="$(uname -s)"; m="$(uname -m)"
  case "${s}" in Darwin) os=darwin ;; Linux) os=linux ;; *) os="${s}" ;; esac
  case "${m}" in x86_64) arch=amd64 ;; arm64|aarch64) arch=arm64 ;; *) arch="${m}" ;; esac
  while IFS=$'\t' read -r kind f2 f3 _; do
    case "${kind}" in
      asset) n_all=$((n_all + 1))
        [[ "${f2}" == "${os}/${arch}" ]] || continue
        asset="${f3}"; n_asset=$((n_asset + 1)) ;;
      checksums) [[ "${f3}" == sha256 ]] || continue
        sums="${f2}"; n_sums=$((n_sums + 1)) ;;
    esac
  done <<< "${list}"
  if [[ "${n_sums}" -ne 1 ]]; then why="${build} --list has no one sha256 checksums line"
  elif [[ "${n_all}" -eq 0 ]]; then why="${build} --list has no asset line"
  elif [[ "${n_asset}" -gt 1 ]]; then why="${build} --list has ${n_asset} asset lines for ${os}/${arch}"
  elif ! [[ "${sums}" =~ ${BINARY_NAME_RE} ]]; then why="${build} --list names '${sums}', which is not a plain file name"   # loose-match: ok BINARY_NAME_RE is a fixed regex
  elif [[ "${n_asset}" -eq 1 ]] && ! [[ "${asset}" =~ ${BINARY_NAME_RE} ]]; then   # loose-match: ok BINARY_NAME_RE is a fixed regex
    why="${build} --list names '${asset}', which is not a plain file name"
  fi
  if [[ -n "${why}" ]]; then
    echo "binary: cannot tell which release files are this copy's binary: ${why}: ${fix}" >&2; return 1
  fi
  if [[ "${n_asset}" -eq 0 ]]; then
    echo "binary: swarm-dev publishes no binary for ${os}/${arch} (uname: ${s} ${m}): set SWARMDEV_BIN to a swarm binary built for it (go build ./cmd/swarm)" >&2
    return "${BINARY_CANNOT}"
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "binary: gh is not on PATH, so swarm-dev cannot download its binary: install the GitHub CLI (https://cli.github.com) and run gh auth login, or set SWARMDEV_BIN to a swarm binary" >&2
    return "${BINARY_CANNOT}"
  fi
  repo="$(binary_repo)"
  report="run it again, and if it fails the same way report it at https://github.com/${repo}/issues"
  if ! err="$(gh release download "v${version}" --repo "github.com/${repo}" --pattern "${asset}" --pattern "${sums}" \
      --dir "${dir}" 2>&1 > /dev/null < /dev/null)"; then
    while IFS= read -r line; do [[ "${line}" =~ [^[:space:]] ]] && break; line=""; done <<< "${err}"
    echo "binary: gh release download v${version} --repo github.com/${repo} failed: '${line%$'\r'}': fix what gh says and run again, or set SWARMDEV_BIN to a swarm binary" >&2
    return "${BINARY_CANNOT}"
  fi
  file="${dir}/${asset}"
  if [[ ! -f "${file}" || ! -f "${dir}/${sums}" ]]; then
    echo "binary: gh release download v${version} left no ${asset} and ${sums} in ${dir}: ${report}" >&2; return 1
  fi
  if command -v sha256sum >/dev/null 2>&1; then sum_cmd=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then sum_cmd=(shasum -a 256); fi
  got=""
  [[ ${#sum_cmd[@]} -eq 0 ]] || got="$("${sum_cmd[@]}" "${file}" 2>/dev/null)" || got=""
  got="${got%% *}"
  if ! [[ "${got}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "binary: could not take the SHA-256 of ${file} (no sha256sum or shasum on PATH, or it failed), so the download cannot be checked: install coreutils, or set SWARMDEV_BIN to a swarm binary" >&2
    return 1
  fi
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" =~ ${BINARY_SUM_RE} ]] || continue   # loose-match: ok BINARY_SUM_RE is a fixed regex
    [[ "${BASH_REMATCH[2]}" == "${asset}" ]] || continue
    n=$((n + 1)); want="${BASH_REMATCH[1]}"
  done < "${dir}/${sums}"
  if [[ "${n}" -eq 0 ]]; then
    echo "binary: v${version}'s ${sums} has no line naming ${asset}, so the download cannot be checked: ${report}" >&2; return 1
  elif [[ "${n}" -gt 1 ]]; then
    echo "binary: v${version}'s ${sums} names ${asset} on ${n} lines, so the download cannot be checked: ${report}" >&2; return 1
  elif [[ "${got}" != "${want}" ]]; then
    echo "binary: the SHA-256 of v${version}'s ${asset} does not match its line in ${sums}: ${report}" >&2; return 1
  fi
}
