.PHONY: hooks test check lint

# Install the gitleaks pre-commit hook into .git/hooks.
hooks:
	cp scripts/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	@echo "Installed .git/hooks/pre-commit"

# Run TESTS (every tests/*_test.sh) through scripts/test.sh: JOBS at a time (one per CPU), then the
# files in SERIAL one at a time, each with a TMPDIR of its own. It prints a "run" line as a file starts,
# ok or FAIL with its seconds as it ends, each failed file's output after its phase, and fails if any
# file failed. swarm.sh's fixed sleeps run at a hundredth (SWARM_SLEEP_SCALE, unless set).
# SERIAL: files whose timing does not hold up beside the others: dash_watch's pty frames and
# dash_wait's millisecond slices are timed against a render or a poll that slows under load,
# review_agent's fast waits and dash_stalls' stall times against a timeout, and sleep_scale's own
# make test runs against a 5 s bound.
TESTS ?= tests/*_test.sh
SERIAL ?= tests/dash_watch_test.sh tests/dash_wait_test.sh tests/review_agent_test.sh \
  tests/dash_stalls_test.sh tests/sleep_scale_test.sh
# SLOW: the files long enough to need a CI shard of their own: dash_check, queue, wait_pr, and merge_test
# with the files split from it or built on it (merge_rules, merge_queue, board_pr_kinds; all on
# tests/merge_fixture.sh). They start first, CI's SHARD=i/N split gives each SLOW and SERIAL file a shard
# of its own, so ci.yml's shard count is at least the two lists' length (tests/test_shard_test.sh), and a
# SLOW file has three times the TEST_FILE_TIMEOUT. A file joins SLOW when the shard it shares runs longer than the SLOW shards do.
SLOW ?= tests/merge_test.sh tests/merge_rules_test.sh tests/merge_queue_test.sh tests/dash_check_test.sh \
  tests/queue_test.sh tests/wait_pr_test.sh tests/board_pr_kinds_test.sh
JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
export SWARM_SLEEP_SCALE ?= 0.01
test:
	@JOBS="$(JOBS)" SERIAL="$(SERIAL)" SLOW="$(SLOW)" bash scripts/test.sh $(TESTS)

SHELLCHECK_FILES ?= bin/swarm.sh bin/lib/*.sh bin/gh-shim/gh hooks/*.sh scripts/pre-commit scripts/demo-dash.sh \
  scripts/board-only.sh scripts/test.sh scripts/select-tests.sh tests/*.sh
# Run shellcheck over SHELLCHECK_FILES, the files CI's shellcheck step covers.
lint:
	@shellcheck $(SHELLCHECK_FILES)

# Run scripts/lint over LINT_FILES (every tests/*_test.sh): it prints file:line: for each finding and
# fails if there is one. CI runs it beside shellcheck.
LINT_FILES ?= tests/*_test.sh
check:
	@python3 scripts/lint $(LINT_FILES)
