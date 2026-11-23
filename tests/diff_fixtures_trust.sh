# shellcheck shell=bash
# diff_fixtures_trust.sh — tests/diff_run.sh's fixtures for swarm.sh _trusted <cwd>: whether Claude
# Code trusts a folder, as bin/lib/require_trusted.py reads ${ROOT}/claude-config/.claude.json (the
# CLAUDE_CONFIG_DIR diff_run.sh sets). Each runs on diff_fixtures_cmds.sh's empty project and makes no
# gh or herdr call, so FX_CALLS names none. diff_run.sh sources this file, and every other
# tests/diff_fixtures_*.sh, by a glob; its header says what a fixture sets.
# shellcheck disable=SC2034 # diff_run.sh reads the FX_ settings

# trust_project <cwd> — the empty project, an empty claude-config/, and the command the tree's
# swarm.sh _trusted <cwd>. TRUST_REAL is ROOT with its symlinks resolved, as require_trusted keys on.
trust_project() {
  diff_empty_project
  mkdir -p "${ROOT}/claude-config" "${ROOT}/plain/sub"
  TRUST_REAL="$(cd "${ROOT}" && pwd -P)"
  FX_CMD=(bash "${TREE}/bin/swarm.sh" _trusted "$1")
}

# trust_file <text> — write <text> as .claude.json, raw.
trust_file() { printf '%s' "$1" > "${ROOT}/claude-config/.claude.json"; }

# trust_nested <n> — arrays nested <n> deep under "x", before a "projects" that trusts the plain folder.
trust_nested() {
  python3 -c 'import sys; n = int(sys.argv[1]); print("{\"x\": " + "[" * n + "]" * n + ", \"projects\": {\"" + sys.argv[2] + "\": {\"hasTrustDialogAccepted\": true}}}")' \
    "$1" "${TRUST_REAL}/plain" > "${ROOT}/claude-config/.claude.json"
}

# A worktree is trusted through its main checkout.
fx_trusted_git() {
  local g=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c commit.gpgsign=false)
  trust_project "${ROOT}/repo-wt"
  "${g[@]}" init -q "${ROOT}/repo"
  "${g[@]}" -C "${ROOT}/repo" commit -q --allow-empty -m init
  "${g[@]}" -C "${ROOT}/repo" worktree add -q "${ROOT}/repo-wt" -b story
  trust_file "{\"projects\": {\"${TRUST_REAL}/repo\": {\"hasTrustDialogAccepted\": true}}}"
}
# A folder no entry trusts: refused, naming it.
fx_trusted_refused() { trust_project "${ROOT}/plain"; trust_file '{"projects": {}}'; }
# Outside git, a trusted ancestor covers a folder.
fx_trusted_ancestor() { trust_project "${ROOT}/plain/sub"; trust_file "{\"projects\": {\"${TRUST_REAL}/plain\": {\"hasTrustDialogAccepted\": true}}}"; }
# No .claude.json: the start goes ahead.
fx_trusted_no_file() { trust_project "${ROOT}/plain"; }
# Text that is not JSON (cut off): goes ahead.
fx_trusted_bad_json() { trust_project "${ROOT}/plain"; trust_file '{"projects": {'; }  # vacuous-test: ok, cut off on purpose
# projects a list: Python's AttributeError is not caught, so it exits 1 with a traceback, and is refused.
fx_trusted_not_object() { trust_project "${ROOT}/plain"; trust_file '{"projects": []}'; }
# NaN elsewhere in a file that trusts nothing: json.load reads it, so refused.
fx_trusted_nan() { trust_project "${ROOT}/plain"; trust_file '{"x": NaN, "projects": {}}'; }
# Arrays nested 500 deep, inside every python3's limit: trusted.
fx_trusted_nested() { trust_project "${ROOT}/plain"; trust_nested 500; }
# Arrays nested 200000 deep, past every python3's limit: the RecursionError is not caught, so it exits
# 1 with a traceback, and is refused.
fx_trusted_deep() { trust_project "${ROOT}/plain"; trust_nested 200000; }
