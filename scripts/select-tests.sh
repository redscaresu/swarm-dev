#!/usr/bin/env bash
# select-tests.sh [--run] — the tests/*_test.sh files to run for this branch's changes, one per line,
# from scripts/test-map.tsv; every test when it is unsure (scripts/select_tests.py has the rules).
# select-tests.sh --known — the tests for the paths it is sure of and the row floor of the rest, and on
# stderr a line naming each path it is unsure of, which CI's full run covers.
# --run runs --known's list through make test, 4 at a time, or says there is none to run
# (select_tests.py says why on stderr). It never runs the full suite; make test with no TESTS does.
# select-tests.sh --check-map < <paths> — names each path under bin/, scripts/, commands/, hooks/ or
# docs/ that the map leaves out, and fails when there is one.
# select-tests.sh --functions — the bin/ functions this branch's changes reach, one per line
# (<file>:<function>, or bin/swarm.sh:arm <cmd> for an arm of its dispatch case), or `full`; --run
# takes none of these options.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" != --run ]]; then
  exec python3 "${here}/select_tests.py" "$@"
fi
shift
if [[ $# -gt 0 ]]; then
  echo "select-tests: --run takes no other option, so it cannot run --functions' or --check-map's output" >&2
  exit 2
fi
tests="$(python3 "${here}/select_tests.py" --known)"
if [[ -z "${tests}" ]]; then
  echo "select-tests: nothing to run"
  exit 0
fi
cd "$(git rev-parse --show-toplevel)" || exit 1
unset SHARD   # a SHARD from the caller would run only part of the selection
exec make test TESTS="${tests//$'\n'/ }" JOBS=4
