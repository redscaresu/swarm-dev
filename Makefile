.PHONY: hooks test

# Install the gitleaks pre-commit hook into .git/hooks.
hooks:
	cp scripts/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	@echo "Installed .git/hooks/pre-commit"

# Run TESTS (every tests/*_test.sh) JOBS at a time (one per CPU), each file's output kept until it
# ends: a "run" line as a file starts, then ok or FAIL with its seconds (a failing file's output
# first). swarm.sh's fixed sleeps run at a hundredth (SWARM_SLEEP_SCALE). A file that failed is run
# once more, alone: "flaky" when it then passes (its timing does not hold up beside the others),
# and make fails only on a file that fails alone too.
TESTS ?= tests/*_test.sh
JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
export SWARM_SLEEP_SCALE := 0.01
test:
	@failed="$$(mktemp)"; trap 'rm -f "$$failed" "$$failed.out"' EXIT; \
	printf '%s\n' $(TESTS) | FAILED="$$failed" xargs -P $(JOBS) -n 1 bash -c '\
	  echo "run  $$1"; \
	  if out="$$(bash "$$1" 2>&1)"; then echo "ok   $$1 $${SECONDS}s"; \
	  else printf "%s\n" "$$out"; echo "FAIL $$1 $${SECONDS}s"; echo "$$1" >> "$$FAILED"; fi' _; \
	rc=0; while read -r t; do \
	  if bash "$$t" > "$$failed.out" 2>&1; then echo "flaky $$t: failed beside the others, passed alone"; \
	  else cat "$$failed.out"; echo "FAIL $$t, alone too"; rc=1; fi; \
	done < "$$failed"; exit $$rc
