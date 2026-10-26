.PHONY: hooks test

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
# SLOW: files that take minutes on their own. In a CI test-shard job (2026-10-26) merge_test took about
# 250 s, most of it the CPU of its few hundred swarm.sh merge calls; dash_check about 200 s; and wait_pr
# about 125 s, most of it waiting out deadlines, graces and pauses with seconds of room. They start first, and
# CI's SHARD=i/N split gives each SLOW and SERIAL file a shard of its own.
SLOW ?= tests/merge_test.sh tests/dash_check_test.sh tests/wait_pr_test.sh
JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
export SWARM_SLEEP_SCALE ?= 0.01
test:
	@JOBS="$(JOBS)" SERIAL="$(SERIAL)" SLOW="$(SLOW)" bash scripts/test.sh $(TESTS)
