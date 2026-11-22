# shellcheck shell=bash
# binary_fetch_stubs.sh — the fakes every binary-fetch test sources: a fake release, a gh stub that
# serves it, and a uname stub that can report another platform. Nothing here reaches the network or a
# real gh. The fake release's binary is a copy of make test's SWARMDEV_BIN, so a test that runs the
# downloaded file runs this tree's own build, wrapper-fixture included.
#
#   fetch_stubs <dir> <version>   the gh and uname stubs in <dir>/bin, each logging one line a call to
#                                 <dir>/log/<name>; the gh stub serves release v<version>
#   fetch_release <dir> <asset> <checksums>
#                                 the fake release in <dir>/release: <asset>, a copy of SWARMDEV_BIN, and
#                                 <checksums>, the one line `<its SHA-256>  <asset>` as sha256sum writes it;
#                                 and the two names the gh stub serves. A second call replaces the first.
#   fetch_uname <dir> [<s> <m>]   the uname stub prints <s> for -s and <m> for -m; with neither, it runs
#                                 the real uname, as it does for any other argument
#   fetch_sum <file>              the SHA-256 of <file>, in hex
#
# The gh stub logs `GH_HOST=<its value> <arguments>` for every call, then serves only
#   release download v<version> --repo github.com/<FETCH_REPO> --pattern <asset> --pattern <checksums> --dir <folder>
# with the arguments in that order and <folder> an existing folder: it copies the release's two files
# there and exits 0. With <dir>/stub/download.stderr present it prints that file on stderr and exits 1
# instead. Any other arguments: one line on stderr, exit 1.

# FETCH_REPO: the repository the gh stub serves, copied from binary_repo in bin/lib/binary.sh, so a change
# there is a change to these tests too.
FETCH_REPO=redscaresu/swarm-dev

fetch_stubs() {
  local real_cp real_cat real_uname
  if ! { real_cp="$(command -v cp)" && real_cat="$(command -v cat)" && real_uname="$(command -v uname)"; }; then
    echo "FAIL fetch_stubs: cp, cat or uname is not on PATH"; return 1
  fi
  mkdir -p "$1/bin" "$1/log" "$1/stub" "$1/release" || return 1
  printf '%s\n' "$2" > "$1/stub/version"
  printf "#!/bin/sh\nD='%s' CP='%s' CAT='%s' REPO='%s'\n" "$1" "${real_cp}" "${real_cat}" "${FETCH_REPO}" > "$1/bin/gh"
  cat >> "$1/bin/gh" <<'GH_STUB'
printf 'GH_HOST=%s %s\n' "${GH_HOST-}" "$*" >> "$D/log/gh"
v= a= s=
{ read -r v < "$D/stub/version"; read -r a < "$D/stub/asset"; read -r s < "$D/stub/checksums"; } 2>/dev/null
if [ "$#" -eq 11 ] && [ "$1" = release ] && [ "$2" = download ] && [ "$3" = "v$v" ] && [ "$4" = --repo ] &&
   [ "$5" = "github.com/$REPO" ] && [ "$6" = --pattern ] && [ -n "$a" ] && [ "$7" = "$a" ] &&
   [ "$8" = --pattern ] && [ -n "$s" ] && [ "$9" = "$s" ] && [ "${10}" = --dir ] && [ -d "${11}" ]; then
  if [ -f "$D/stub/download.stderr" ]; then "$CAT" "$D/stub/download.stderr" >&2; exit 1; fi
  "$CP" "$D/release/$a" "$D/release/$s" "${11}/" || exit 1
  exit 0
fi
echo "gh stub: no form matches: $*" >&2
exit 1
GH_STUB
  printf "#!/bin/sh\nD='%s' U='%s'\n" "$1" "${real_uname}" > "$1/bin/uname"
  cat >> "$1/bin/uname" <<'UNAME_STUB'
printf '%s\n' "$*" >> "$D/log/uname"
if [ "$#" -eq 1 ] && { [ "$1" = -s ] || [ "$1" = -m ]; } && [ -f "$D/stub/uname$1" ]; then
  read -r v < "$D/stub/uname$1"; printf '%s\n' "$v"; exit 0
fi
exec "$U" "$@"
UNAME_STUB
  chmod +x "$1/bin/gh" "$1/bin/uname"
}

fetch_release() {
  if [[ -z "${SWARMDEV_BIN:-}" || ! -x "${SWARMDEV_BIN}" ]]; then
    echo "FAIL fetch_release: SWARMDEV_BIN names no executable binary ('${SWARMDEV_BIN:-}'): run this test through make test, which builds it"
    return 1
  fi
  rm -rf "$1/release" && mkdir -p "$1/release" || return 1
  cp "${SWARMDEV_BIN}" "$1/release/$2" || return 1
  printf '%s  %s\n' "$(fetch_sum "$1/release/$2")" "$2" > "$1/release/$3"
  printf '%s\n' "$2" > "$1/stub/asset"; printf '%s\n' "$3" > "$1/stub/checksums"
}

fetch_uname() {
  if [[ $# -ge 3 ]]; then
    printf '%s\n' "$2" > "$1/stub/uname-s"; printf '%s\n' "$3" > "$1/stub/uname-m"
  else
    rm -f "$1/stub/uname-s" "$1/stub/uname-m"
  fi
}

fetch_sum() {
  local out
  if command -v sha256sum >/dev/null 2>&1; then out="$(sha256sum "$1")" || return 1
  else out="$(shasum -a 256 "$1")" || return 1; fi
  printf '%s\n' "${out%% *}"
}
