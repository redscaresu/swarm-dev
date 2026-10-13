#!/usr/bin/env bash
# claude_stub.sh — a stand-in for the `claude` binary. The tests copy it to <root>/stub-bin/claude and
# put that folder first on PATH. `--version` prints $CLAUDE_STUB_VERSION (default `2.1.296 (Claude
# Code)`). `agents --json` prints the file $CLAUDE_STUB_AGENTS names, or `[]` when it is unset. Any
# other call exits 1 and names the call. The entry shape is from a real `claude agents --json`
# (cwd, kind, name, pid, sessionId, startedAt, status); `waitingFor` is unverified until a real
# waiting entry is captured.
set -euo pipefail

case "$*" in
  --version) printf '%s\n' "${CLAUDE_STUB_VERSION:-2.1.296 (Claude Code)}" ;;
  "agents --json")
    if [[ -n "${CLAUDE_STUB_AGENTS:-}" ]]; then cat "${CLAUDE_STUB_AGENTS}"; else echo '[]'; fi ;;
  *) echo "claude stub: unexpected call: $*" >&2; exit 1 ;;
esac
