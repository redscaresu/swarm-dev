# shellcheck shell=bash
# binary.sh — find the swarm binary a command runs, run it, and download a release's binary. A hook
# sources it on its own, and bin/swarm.sh before its version case, not with its other libs: it needs no other bin/lib file, sets no
# shell option and starts no process when sourced, and binary_find and is_ported start none either.
# binary_path and binary_run are swarm.sh's alone. Only binary_build builds, and only binary_path calls
# it, in a git checkout. Only binary_download downloads: with gh, into a folder its caller gives, and it
# checks the file against the release's checksum file. It never writes <root>/swarm.
# binary_gh_path and binary_present start no process either. binary_fetch and binary_ensure are
# swarm.sh's alone too: binary_ensure reads the version with swarm.sh's plugin_version. Only binary_fetch
# writes that file, in an installed copy: it calls binary_download into a folder of its own, checks the
# build attestation with binary_attest, then renames the file over <root>/swarm. binary_ensure, which
# swarm.sh runs on every call but version and update, calls it when that file is missing, so the checks
# run once, at download.

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

# BINARY_GH_MIN: the oldest gh whose `gh attestation verify` takes every flag binary_attest passes, as
# X.Y.Z to compare with the `gh version X.Y.Z` line of `gh --version`. Two releases set it:
#   v2.51.0 added the signer flag. Its release note (https://github.com/cli/cli/releases/tag/v2.51.0):
#     "Add `signer-repo` and `signer-workflow` flags to `gh attestation verify`"
#     (https://github.com/cli/cli/pull/9137).
#   v2.57.0 added --hostname to the command. Its release note
#     (https://github.com/cli/cli/releases/tag/v2.57.0): "Added tenancy aware attestation commands"
#     (https://github.com/cli/cli/pull/9542), whose diff adds the flag to `gh attestation verify`. gh
#     2.51.0 to 2.56.0 have no --hostname on it, so they refuse the call.
# Before gh 2.102.0, --signer-workflow matched only the start of the signing certificate's identity
# (https://github.com/cli/cli/security/advisories/GHSA-wjmr-j3rp-mh2g), and before 2.97.0 a . in it
# matched any character (https://github.com/cli/cli/security/advisories/GHSA-mm27-mwq9-fr5g). Both
# advisories say --repo is not affected, so on such a gh the attestation still comes from <repo>, and
# only which of its workflows signed is checked less strictly.
BINARY_GH_MIN=2.57.0

# BINARY_ATTEST_SECONDS: how long binary_attest lets `gh attestation verify` run before it KILLs it.
# Nothing in gh bounds the call. Its HTTP client comes from go-gh, whose ClientOptions.Timeout says
# "Default is no timeout" (cli/go-gh v2.16.1, the one gh 2.101.0 pins), and gh sets none. So on a
# network that drops packets, the call can wait for ever, and the swarm.sh call behind it with it.
BINARY_ATTEST_SECONDS=60

# binary_within <seconds> <command>... — the command in its own process group, the group KILLed after
# <seconds> (at least 1) with exit 142; else the command's own status (128+N for a signal). gh, a Go
# program, ignores SIGALRM, so the alarm goes to perl, which KILLs the group. A HUP, INT or TERM to perl
# KILLs the command too and exits 128+N: in a group of its own, the command would run on with no alarm.
# Each KILL is followed by a waitpid, so the command is reaped and gone when binary_within returns,
# not a zombie left for init. It is merge.sh's within in whole seconds, plus that reap, copied as
# hooks/lead-stop.sh copies it: this file needs no other bin/lib file.
binary_within() {
  perl -e 'my $t = shift; $t = 1 if $t < 1;
    defined(my $p = fork) or exit 127;
    if (!$p) { setpgrp; exec @ARGV or exit 127 }
    # The parent sets the group too, before the alarm: one that fires first would KILL no group.
    setpgrp $p, $p;
    sub stop { kill "KILL", -$p, $p; waitpid $p, 0; exit shift }
    my %n = (HUP => 1, INT => 2, TERM => 15);
    for my $s (keys %n) { $SIG{$s} = sub { stop(128 + $n{$s}) } }
    $SIG{ALRM} = sub { stop(142) };
    alarm $t; waitpid $p, 0;
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' -- "$@"
}

# binary_attest <file> <repo> <signer> — return 0 when gh verifies <file>'s build attestation: built in
# <repo> (<owner>/<name>) on github.com, and signed by its workflow at <signer>, a path in <repo> such as
# .github/workflows/release.yml. gh comes from PATH and needs BINARY_GH_MIN or newer. It prints none of
# gh's output. Any failure prints one line on stderr saying what to do and returns 1: an empty argument,
# gh's own failure, or no answer within BINARY_ATTEST_SECONDS, when binary_within KILLs gh. There is no
# fallback, so the caller never runs <file>. An empty <signer> stops before gh: an older gh would read
# github.com/<repo>/ as a prefix that every workflow in <repo> matches.
# Two runs at once are safe. gh reads <file> and never writes it. It writes only its sigstore cache
# under its cache dir, through go-tuf v2.4.2 (the one gh 2.101.0 pins): metadata through a temp file and
# a rename, and a target in place, but a cached target is used only once its length and hashes match,
# so a half-written one is fetched again, never trusted.
binary_attest() {
  local file="${1:-}" repo="${2:-}" signer="${3:-}" rc=0 why=""
  if [[ -z "${file}" || -z "${repo}" || -z "${signer}" ]]; then
    echo "binary: binary_attest needs a file, a repo and a signer workflow, and was given '${file}' '${repo}' '${signer}', so nothing was verified or run" >&2
    return 1
  fi
  binary_within "${BINARY_ATTEST_SECONDS}" gh attestation verify "${file}" --hostname github.com \
    --repo "${repo}" --signer-workflow "github.com/${repo}/${signer}" </dev/null >/dev/null 2>&1 || rc=$?
  [[ "${rc}" -ne 0 ]] || return 0
  [[ "${rc}" -ne 142 ]] || why=" (no answer within ${BINARY_ATTEST_SECONDS} s)"
  echo "binary: gh attestation verify failed for ${file}${why}, so its build attestation from ${repo}'s ${signer} is not proven and it was not run: check that gh is ${BINARY_GH_MIN} or newer, logged in (gh auth status) and online, then run the command again" >&2
  return 1
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

# BINARY_FETCH_TMP: the prefix of the folder binary_fetch downloads into, in the plugin root; the PID of
# the swarm.sh that runs it follows it, so two calls never share one. The folder is on the root's own
# filesystem, so the last step is a rename over <root>/BINARY_BUILD_PATH, and a call started meanwhile
# never runs half a file.
BINARY_FETCH_TMP=.fetch-
# BINARY_REINSTALL: what a stop line of binary_fetch or binary_ensure says to do about a broken copy.
BINARY_REINSTALL="reinstall swarm-dev (claude plugin uninstall swarm-dev@swarm-dev, then claude plugin install swarm-dev@swarm-dev)"

# binary_gh_path — PATH with every empty entry and every folder whose name ends /gh-shim taken out, as
# bin/gh-shim/gh skips them when it looks for the real gh, so the download runs no version's shim and
# gh-calls.tsv does not log it. The other folders keep their order. Builtins only, no fork.
binary_gh_path() {
  local rest="${PATH}:" d out=""
  while [[ -n "${rest}" ]]; do
    d="${rest%%:*}"; rest="${rest#*:}"
    [[ -n "${d}" && "${d%/}" != */gh-shim ]] || continue
    out="${out:+${out}:}${d}"
  done
  printf '%s\n' "${out}"
}

# binary_present <root> — true when <root>/BINARY_BUILD_PATH is an executable file, the binary an
# earlier call fetched. Builtins only, no fork: swarm.sh asks it on every call in an installed copy.
binary_present() { [[ -f "${1%/}/${BINARY_BUILD_PATH}" && -x "${1%/}/${BINARY_BUILD_PATH}" ]]; }

# binary_fetch_stop <pid> — send TERM to <pid> and to every process under it, the deepest first, as one
# ps listing shows them. binary_fetch's traps call it: gh runs inside a $( ) of binary_download, and the
# subshell's own trap would wait for gh to end before it ran. It runs only on a signal.
binary_fetch_stop() {
  local tree=" $1 " order=("$1") list p pp grew=1 i
  list="$(ps -A -o pid= -o ppid= 2>/dev/null)" || list=""
  while [[ ${grew} == 1 ]]; do
    grew=0
    while read -r p pp; do
      [[ "${tree}" == *" ${pp} "* && "${tree}" != *" ${p} "* ]] || continue   # loose-match: ok whole-number pids, each between spaces
      tree+="${p} "; order+=("${p}"); grew=1
    done <<< "${list}"
  done
  for ((i = ${#order[@]} - 1; i >= 0; i--)); do kill -TERM "${order[i]}" 2>/dev/null || true; done
}

# binary_fetch_steps <root> <version> <dir> — binary_fetch's steps, in its subshell, with the PATH it
# gives: mkdir <dir>; binary_download into it; binary_attest on the asset, with binary_repo and the
# signer line of `scripts/build.sh --list`; chmod +x; mv -f over <root>/BINARY_BUILD_PATH. The asset is
# the one asset name of --list that is a file in <dir>. Returns 0, or prints one `binary: ` line on
# stderr and returns binary_download's code for its failures, else 1. It never removes <dir>: the
# subshell's EXIT trap does.
binary_fetch_steps() {
  local root="$1" version="$2" dir="$3" build="$1/scripts/build.sh" target="$1/${BINARY_BUILD_PATH}"
  local list kind f2 f3 asset="" n_asset=0 signer="" n_signer=0 repo
  # -p: the folder is this call's alone, by its PID, and is no lock. One a KILLed call left under the
  # same PID goes first.
  rm -rf "${dir}" 2>/dev/null
  if ! mkdir -p "${dir}" 2>/dev/null; then
    echo "binary: could not make ${dir} to download swarm-dev's binary into: check that ${root} is writable, or set SWARMDEV_BIN to a swarm binary" >&2
    return 1
  fi
  binary_download "${root}" "${version}" "${dir}" || return
  if ! list="$("${BASH}" "${build}" --list 2>/dev/null)"; then
    echo "binary: ${build} --list failed after the download, so the binary's signer is not known and it was not installed: ${BINARY_REINSTALL}" >&2
    return 1
  fi
  while IFS=$'\t' read -r kind f2 f3 _; do
    case "${kind}" in
      asset) [[ "${f3}" =~ ${BINARY_NAME_RE} && -f "${dir}/${f3}" ]] || continue   # loose-match: ok BINARY_NAME_RE is a fixed regex
        asset="${dir}/${f3}"; n_asset=$((n_asset + 1)) ;;
      signer) signer="${f2}"; n_signer=$((n_signer + 1)) ;;
    esac
  done <<< "${list}"
  if [[ "${n_signer}" -ne 1 || -z "${signer}" ]]; then
    echo "binary: ${build} --list has no one signer line, so the binary's build attestation cannot be checked and it was not installed: ${BINARY_REINSTALL}" >&2
    return 1
  fi
  repo="$(binary_repo)"
  if [[ "${n_asset}" -ne 1 ]]; then
    echo "binary: ${dir} holds ${n_asset} of the asset files ${build} --list names, where the download leaves one, so none was installed: run it again, and if it fails the same way report it at https://github.com/${repo}/issues" >&2
    return 1
  fi
  binary_attest "${asset}" "${repo}" "${signer}" || return 1
  if ! chmod +x "${asset}" 2>/dev/null; then
    echo "binary: could not make ${asset} executable: check that ${root} is writable, or set SWARMDEV_BIN to a swarm binary" >&2
    return 1
  fi
  if [[ -d "${target}" ]]; then
    echo "binary: ${target} is a folder, so the checked binary cannot be installed there: remove it and run the command again" >&2
    return 1
  fi
  if ! mv -f "${asset}" "${target}" 2>/dev/null; then
    echo "binary: could not move the checked binary to ${target}: check that ${root} is writable, or set SWARMDEV_BIN to a swarm binary" >&2
    return 1
  fi
}

# binary_fetch <root> <version> — download release v<version>'s binary for this platform, check it, and
# install it as <root>/BINARY_BUILD_PATH. It returns 0, or prints one `binary: ` line on stderr and
# returns binary_fetch_steps' code.
#   The steps (binary_fetch_steps) run in a background subshell, with PATH from binary_gh_path and the
#     subshell's own EXIT, INT, TERM and HUP trap, which removes their folder, <dir>:
#     <root>/BINARY_FETCH_TMP<pid>.
#   While they run, binary_fetch traps INT, TERM and HUP in the caller's shell: the trap sends TERM to
#     the subshell and every process under it (binary_fetch_stop), so gh ends at once. Then the caller's
#     own traps go back as they were, and the signal is sent again, to the caller's shell, which ends as
#     it would have without the fetch.
#   A KILL leaves <dir>, holding a file that is not executable yet: no call runs it, and the next call
#   fetches again. Two calls at once each use a folder of their own, then rename, so both end with one
#   whole binary and need no lock.
binary_fetch() {
  local root="${1%/}" version="${2:-}" dir saved pid="" sig="" cut=0 rc=0 code
  dir="${root}/${BINARY_FETCH_TMP}$$"
  saved="$(trap -p INT TERM HUP)"
  trap 'sig=INT; cut=1; [[ -z "${pid}" ]] || binary_fetch_stop "${pid}"' INT
  trap 'sig=TERM; cut=1; [[ -z "${pid}" ]] || binary_fetch_stop "${pid}"' TERM
  trap 'sig=HUP; cut=1; [[ -z "${pid}" ]] || binary_fetch_stop "${pid}"' HUP
  (
    trap 'rm -rf "${dir}" 2>/dev/null' EXIT
    trap 'exit 130' INT; trap 'exit 143' TERM; trap 'exit 129' HUP
    PATH="$(binary_gh_path)" binary_fetch_steps "${root}" "${version}" "${dir}"
  ) &
  pid=$!
  [[ -z "${sig}" ]] || binary_fetch_stop "${pid}"   # a signal before $! was known
  wait "${pid}" || rc=$?
  # A trapped signal cuts the wait short (over 128): wait again, for the subshell's own code.
  while [[ ${cut} == 1 && ${rc} -gt 128 ]]; do cut=0; rc=0; wait "${pid}" || rc=$?; done
  trap - INT TERM HUP
  eval "${saved}"
  [[ -n "${sig}" ]] || return "${rc}"
  case "${sig}" in INT) code=130 ;; TERM) code=143 ;; *) code=129 ;; esac
  kill -s "${sig}" "$$"
  return "${code}"   # the caller's own trap took the signal and went on
}

# binary_ensure <root> — make sure the plugin copy at <root> has its binary, and export SWARMDEV_BIN
# naming it, so a ported command, and a helper entry that a command's bash calls, finds it. swarm.sh
# runs it on every call but version and update, before it looks for a project.
#   SWARMDEV_BIN set, even empty: nothing; binary_find runs that file.
#   <root>/.git there (a git checkout): nothing; binary_path builds from the tree for a ported command.
#   Otherwise (an installed copy): binary_present, else binary_fetch for the version in
#     <root>/.claude-plugin/plugin.json. Then SWARMDEV_BIN=<root>/BINARY_BUILD_PATH, exported.
# With the binary present it starts no process. On failure it exports nothing, leaves binary_fetch's one
# line on stderr (or its own, when the version cannot be read) and returns binary_fetch's code (else 1).
# It never dies, so its caller can go on.
binary_ensure() {
  local root="${1%/}" version
  [[ -z "${SWARMDEV_BIN+set}" ]] || return 0
  if [[ -z "${root}" ]]; then echo "binary: binary_ensure was given no plugin root" >&2; return 1; fi
  [[ ! -e "${root}/.git" ]] || return 0
  if ! binary_present "${root}"; then
    version="$(plugin_version 2>/dev/null < "${root}/.claude-plugin/plugin.json")" || version=""
    if [[ -z "${version}" ]]; then
      echo "binary: cannot read this copy's version from ${root}/.claude-plugin/plugin.json, so it cannot tell which release's binary to download: ${BINARY_REINSTALL}" >&2
      return 1
    fi
    binary_fetch "${root}" "${version}" || return
  fi
  export SWARMDEV_BIN="${root}/${BINARY_BUILD_PATH}"
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
