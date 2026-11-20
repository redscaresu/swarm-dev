# shellcheck shell=bash
# diff_fixtures_cmds.sh — tests/diff_run.sh's seed fixtures: swarm.sh's usage, next and status, each
# on an empty project. diff_run.sh sources this file, and every other tests/diff_fixtures_*.sh, by a
# glob; its header says what a fixture sets.
# shellcheck disable=SC2034 # diff_run.sh reads the FX_ settings

# diff_empty_project — a git repo at ${ROOT}/proj with an empty .claude/swarm/config and a .swarm/
# (so next and status log their run-times.tsv rows), and the command's cwd there.
diff_empty_project() {
  mkdir -p "${ROOT}/proj/.claude/swarm" "${ROOT}/proj/.swarm"
  git -C "${ROOT}/proj" init -q
  : > "${ROOT}/proj/.claude/swarm/config"
  FX_CWD="${ROOT}/proj"
}

# swarm.sh with no command: its usage, on stdout, and exit 2.
fx_usage() { diff_empty_project; FX_CMD=(bash "${TREE}/bin/swarm.sh"); }
fx_next() { diff_empty_project; FX_CMD=(bash "${TREE}/bin/swarm.sh" next); }
fx_status() { diff_empty_project; FX_CMD=(bash "${TREE}/bin/swarm.sh" status); }
