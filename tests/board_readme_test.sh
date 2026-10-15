#!/usr/bin/env bash
# board_readme_test.sh — swarm-dev's own board/stories/README.md and board/epics/README.md match the
# templates a project copies under templates/docs/. A change to one without the other fails here.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO}"
same() { cmp -s "$1" "$2"; }

# Self-check: the compare must tell two files one line apart, or the real check passes vacuously.
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
cp templates/docs/stories/README.md "${tmp}/a"
cp templates/docs/stories/README.md "${tmp}/b"
echo "one more line" >> "${tmp}/b"
if same "${tmp}/a" "${tmp}/b"; then
  echo "FAIL the compare reports a match for two files that differ by one line"; exit 1
fi
echo "ok   the compare tells two files one line apart"

for kind in stories epics; do
  board="board/${kind}/README.md" template="templates/docs/${kind}/README.md"
  if ! same "${board}" "${template}"; then
    echo "FAIL ${board} and ${template} differ; change both:"
    diff "${board}" "${template}" || true
    exit 1
  fi
  echo "ok   ${board} matches ${template}"
done
echo "all passed"
