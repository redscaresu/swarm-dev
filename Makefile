.PHONY: hooks test

# Install the gitleaks pre-commit hook into .git/hooks.
hooks:
	cp scripts/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	@echo "Installed .git/hooks/pre-commit"

# Run TESTS (every tests/*_test.sh) JOBS at a time (one per CPU), each file's output kept until it
# ends: a "run" line as a file starts, then ok or FAIL with its seconds (a failing file's output
# first). Fails if any file fails. swarm.sh's fixed sleeps run at a hundredth (SWARM_SLEEP_SCALE).
TESTS ?= tests/*_test.sh
JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
test:
	@printf '%s\n' $(TESTS) | SWARM_SLEEP_SCALE=0.01 xargs -P $(JOBS) -n 1 bash -c '\
	  echo "run  $$1"; \
	  if out="$$(bash "$$1" 2>&1)"; then echo "ok   $$1 $${SECONDS}s"; \
	  else printf "%s\n" "$$out"; echo "FAIL $$1 $${SECONDS}s"; exit 1; fi' _
