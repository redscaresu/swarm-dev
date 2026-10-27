#!/usr/bin/env bash
# pane_prompt_test.sh — panes.py's stuck_kind over the pane screens in tests/fixtures/panes.
# Each kind is named on its own screen: a permission prompt (under an older esc to interrupt line) and
# a dialog, plain and framed (╭─ … ╰─), are prompt, then login, api-error (under an older esc to
# interrupt line) and manual. These are none:
#   a pane mid-command (one printing a menu, one in manual mode);
#   a menu a command printed, under a later reply;
#   an empty input box under a prompt, sent after an API error, that quotes a menu;
#   a reply that only mentions /login and quotes a menu, with `❯ 1. Yes` typed on the box's second line;
#   the usage-limit dialog, which wait answers.
# The fixtures are short screens written by hand from Claude Code's prompt text, with only the lines
# the reader needs.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${HERE}/../bin/lib"
FX="${HERE}/fixtures/panes"

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }

# kind <fixture> — stuck_kind's answer for the fixture's screen, or `none`.
kind() {
  SWARM_LIB="${LIB}" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from panes import stuck_kind
print(stuck_kind(sys.stdin.read()) or "none")' < "${FX}/$1"
}

check "a permission prompt (Do you want to proceed?), under an older esc to interrupt, is prompt" test "$(kind prompt.txt)" = prompt
check "the Teach auto mode dialog is prompt" test "$(kind dialog.txt)" = prompt
check "a framed dialog (╭─ … ╰─) is prompt" test "$(kind framed-dialog.txt)" = prompt
check "a turn ended on Login expired · Please run /login is login" test "$(kind login.txt)" = login
check "a turn ended on an API Error: line, under an older esc to interrupt, is api-error" test "$(kind api-error.txt)" = api-error
check "an empty input box over a manual mode footer is manual" test "$(kind manual.txt)" = manual
check "a pane mid-command whose command prints a menu is none" test "$(kind mid-command.txt)" = none
check "a pane mid-command, in manual mode, is none" test "$(kind mid-command-manual.txt)" = none
check "a menu a command printed, under a later reply, is none" test "$(kind reply-after-menu.txt)" = none
check "an empty input box under a prompt, sent after an API error, quoting a menu is none" test "$(kind empty-box.txt)" = none
check "a reply mentioning Please run /login and quoting a menu, with ❯ 1. Yes typed in the box, is none" test "$(kind typed-box.txt)" = none
check "the usage-limit dialog, which wait answers, is none" test "$(kind usage-dialog.txt)" = none

[ "${fails}" -eq 0 ] || { echo "${fails} check(s) failed"; exit 1; }
echo "all checks passed"
