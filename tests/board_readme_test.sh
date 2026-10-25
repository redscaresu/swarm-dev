#!/usr/bin/env bash
# board_readme_test.sh — swarm-dev's own board/stories/, board/epics/ and board/hld/ READMEs match the
# templates a project copies under templates/docs/. A change to one without the other fails here.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO}"
same() { cmp -s "$1" "$2"; }

# Self-check: the compare must tell two files one line apart, or the real check passes vacuously.
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
export CLAUDE_CONFIG_DIR="${tmp}/claude-config"   # under its own root, so parallel runs share no ~/.claude
cp templates/docs/stories/README.md "${tmp}/a"
cp templates/docs/stories/README.md "${tmp}/b"
echo "one more line" >> "${tmp}/b"
if same "${tmp}/a" "${tmp}/b"; then
  echo "FAIL the compare reports a match for two files that differ by one line"; exit 1
fi
echo "ok   the compare tells two files one line apart"

for kind in stories epics hld; do
  board="board/${kind}/README.md" template="templates/docs/${kind}/README.md"
  if ! same "${board}" "${template}"; then
    echo "FAIL ${board} and ${template} differ; change both:"
    diff "${board}" "${template}" || true
    exit 1
  fi
  echo "ok   ${board} matches ${template}"
done
# The epics README's front-matter block must show stage:, or a staged HLD's epics have no documented field.
# Goes red if someone drops the stage: line from the block.
if ! awk '/^```$/{n++} n==1 && /^stage:/{f=1} END{exit !f}' board/epics/README.md; then
  echo "FAIL board/epics/README.md front-matter block has no stage: line"; exit 1
fi
echo "ok   board/epics/README.md documents stage:"
echo "all passed"
