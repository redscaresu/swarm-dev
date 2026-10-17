#!/usr/bin/env bash
# dash_golden_test.sh — the two-project fixture (tests/fixtures/dash/two_projects.sh), drawn by
# `dash --project alpha --project bravo` at 60, 100 and 200 columns with its fixed clock, against the
# committed frames tests/fixtures/dash/golden-<cols>.txt. Any difference fails and prints the diff.
# UPDATE_GOLDEN=1 rewrites the three files from this run instead: commit them with the change.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
fails=0
check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

# shellcheck source=fixtures/dash/two_projects.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
source "${HERE}/fixtures/dash/two_projects.sh" "${ROOT}"
frame() { (cd "${FIXTURE_A}" && DASH_W="$1" "${FIXTURE_SWARM}" dash --project "${FIXTURE_A}" --project "${FIXTURE_B}"); }

for w in 60 100 200; do
  g="${HERE}/fixtures/dash/golden-${w}.txt"
  frame "${w}" > "${ROOT}/frame-${w}.txt"
  if [[ "${UPDATE_GOLDEN:-}" == 1 ]]; then
    cp "${ROOT}/frame-${w}.txt" "${g}"; echo "wrote ${g}"
  else
    check "the frame at ${w} columns matches golden-${w}.txt" diff -u "${g}" "${ROOT}/frame-${w}.txt"
  fi
done
# The clock is fixed: a later run, past the wall clock's next second and with no cache, is the same.
sleep 1; rm -f "${TMPDIR}"/swarm-dash-*
check "a later run draws the same frame" diff -u "${ROOT}/frame-100.txt" <(frame 100)

if [ "${fails}" -gt 0 ]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
