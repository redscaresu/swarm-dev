#!/usr/bin/env bash
# swarm-dev's board-only gate, which .github/workflows/ci.yml runs from the base commit. It writes
# board_only=true to $GITHUB_OUTPUT when every path changed since BASE_SHA (a PR's base, or the commit
# before a push) is one of the board's own files, else board_only=false: with no base, or a failed
# diff (a new branch's all-zero base fails it) too.
set -uo pipefail
BOARD="@BOARD@"
only=false
if [[ "${BASE_SHA:-}" =~ ^[0-9a-f]{40}$ ]] \
   && paths="$(git diff --name-only --no-renames "${BASE_SHA}...HEAD")" && [[ -n "${paths}" ]]; then
  only=true
  while IFS= read -r p; do
    case "${p}" in "${BOARD}"stories/*|"${BOARD}"epics/*|"${BOARD}"hld/*|"${BOARD}"Board.base|"${BOARD}".obsidian/*) ;; *) only=false ;; esac
  done <<< "${paths}"
fi
echo "board-only: ${only}"
echo "board_only=${only}" >> "${GITHUB_OUTPUT:-/dev/null}"
