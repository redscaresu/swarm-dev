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
# review_agent's fast waits against a timeout, and wait_pr's --timeout 0 against one whole second.
TESTS ?= tests/*_test.sh
SERIAL ?= tests/dash_watch_test.sh tests/dash_wait_test.sh tests/review_agent_test.sh tests/wait_pr_test.sh
JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
export SWARM_SLEEP_SCALE ?= 0.01
test:
	@JOBS="$(JOBS)" SERIAL="$(SERIAL)" bash scripts/test.sh $(TESTS)
