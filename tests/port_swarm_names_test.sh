#!/usr/bin/env bash
# port_swarm_names_test.sh — docs/port/swarm-names.tsv lists every SWARM_* name the code names, as the Go port's
# inventory. It scans every file under bin/, hooks/, cmd/ and internal/ (skipping *_test.go, __pycache__ and
# *.pyc) for SWARM_[A-Z0-9_]+, whatever the file's type, so it stays live once the bash is gone. It lists the
# files with find, not git, so it runs the same on a copy of the checkout without .git. It fails on a name
# with no row, a row no scanned file names, a row whose files differ from the files that name it, a row
# with a kind outside setting, handoff, seam and internal, and a name with two rows. Each FAIL line names
# docs/port/swarm-names.tsv and the row to add, change or delete.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIST=docs/port/swarm-names.tsv
KINDS="setting handoff seam internal"
SCANNED="bin/, hooks/, cmd/ or internal/"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, as every test's is (sleep_scale_test.sh)
cd "${ROOT}" || exit 1
[[ -f "${LIST}" ]] || { echo "FAIL ${LIST} is missing"; exit 1; }

fails=0
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

# found: <name><TAB><file>, one line for each file that names a name. -I skips a binary, such as a built
# swarm, which is no code a port reads.
roots=()
for d in bin hooks cmd internal; do [[ ! -d "${d}" ]] || roots+=("${d}"); done
files=()
while IFS= read -r f; do files+=("${f}"); done < <(find "${roots[@]}" -type f ! -path '*/__pycache__/*' \
  ! -name '*.pyc' ! -name '*_test.go' | LC_ALL=C sort)
{ grep -IoHE 'SWARM_[A-Z0-9_]+' -- "${files[@]}" || true; } \
  | awk '{ i = match($0, /:SWARM_[A-Z0-9_]+$/); print substr($0, i + 1) "\t" substr($0, 1, i - 1) }' \
  | LC_ALL=C sort -u > "${dir}/found"
cut -f1 "${dir}/found" | LC_ALL=C sort -u > "${dir}/names"
# A positive control: a scan that found nothing (a wrong directory, a broken find) must not read as a
# list with nothing to add.
grep -qx SWARM_PROJECT "${dir}/names" || fail "the scan of ${SCANNED} found no SWARM_PROJECT, which bin/swarm.sh reads"

# The rows: every line that is not a # comment or blank.
grep -v -e '^#' -e '^[[:space:]]*$' "${LIST}" > "${dir}/rows" || true
while IFS= read -r line; do
  IFS=$'\t' read -r name kind list extra <<< "${line}"
  if [[ -z "${name}" || -z "${kind}" || -z "${list}" || -n "${extra}" ]]; then
    fail "${LIST}: the row '${line}' is not <name><TAB><kind><TAB><files>: fix it"
  elif [[ " ${KINDS} " != *" ${kind} "* ]]; then
    fail "${LIST}: ${name}'s kind '${kind}' is none of ${KINDS}: fix its row"
  fi
done < "${dir}/rows"
cut -f1 "${dir}/rows" | LC_ALL=C sort | uniq -d | while IFS= read -r name; do
  echo "FAIL ${LIST}: ${name} has more than one row: delete all but one"
done > "${dir}/dups"
[[ ! -s "${dir}/dups" ]] || { cat "${dir}/dups"; fails=$((fails + $(wc -l < "${dir}/dups"))); }
cut -f1 "${dir}/rows" | LC_ALL=C sort -u > "${dir}/listed"
# listed_pairs: <name><TAB><file> for each file a row names.
awk -F'\t' '{ n = split($3, f, " "); for (i = 1; i <= n; i++) print $1 "\t" f[i] }' "${dir}/rows" \
  | LC_ALL=C sort -u > "${dir}/listed_pairs"

# A name the code has and the list lacks.
while IFS= read -r name; do
  where="$(awk -F'\t' -v n="${name}" '$1 == n { printf "%s%s", s, $2; s = " " }' "${dir}/found")"
  fail "${LIST} has no row for ${name}, which ${where} names: add the row '${name}<TAB><kind><TAB>${where}'"
done < <(LC_ALL=C comm -23 "${dir}/names" "${dir}/listed")
# A row whose name no scanned file has any more.
while IFS= read -r name; do
  fail "${LIST}: no file under ${SCANNED} names ${name}: delete its row"
done < <(LC_ALL=C comm -13 "${dir}/names" "${dir}/listed")
# A row whose files are not the files that name it.
while IFS= read -r name; do
  want="$(awk -F'\t' -v n="${name}" '$1 == n { printf "%s%s", s, $2; s = " " }' "${dir}/found")"
  got="$(awk -F'\t' -v n="${name}" '$1 == n { printf "%s%s", s, $2; s = " " }' "${dir}/listed_pairs")"
  [[ "${want}" == "${got}" ]] || fail "${LIST}: ${name}'s files are '${got}', but '${want}' name it: change its row's files to '${want}'"
done < <(LC_ALL=C comm -12 "${dir}/names" "${dir}/listed")

if (( fails == 0 )); then
  echo "ok   ${LIST} has a row for each of the $(wc -l < "${dir}/names" | tr -d ' ') SWARM_* names under ${SCANNED}, with its files"
fi
(( fails == 0 ))
