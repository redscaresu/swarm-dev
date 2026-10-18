.PHONY: hooks test

# Install the gitleaks pre-commit hook into .git/hooks.
hooks:
	cp scripts/pre-commit .git/hooks/pre-commit
	chmod +x .git/hooks/pre-commit
	@echo "Installed .git/hooks/pre-commit"

# Run TESTS (every tests/*_test.sh) JOBS at a time (one per CPU), each file with a TMPDIR of its own
# and its output kept until it ends: a "run" line as a file starts, then ok or FAIL with its seconds
# (a failing file's output first). swarm.sh's fixed sleeps run at a hundredth (SWARM_SLEEP_SCALE,
# unless set). A file that failed is run once more, alone: "flaky" when it then passes (its timing
# does not hold up beside the others), and make fails on a file that fails alone too, or when xargs
# stops before every file has run.
TESTS ?= tests/*_test.sh
JOBS ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
export SWARM_SLEEP_SCALE ?= 0.01
test:
	@failed="$$(mktemp)"; trap 'rm -f "$$failed" "$$failed.out"' EXIT; \
	printf '%s\n' $(TESTS) | FAILED="$$failed" xargs -P $(JOBS) -n 1 bash -c '\
	  echo "run  $$1"; tmp="$$(mktemp -d)"; \
	  if out="$$(TMPDIR="$$tmp" bash "$$1" 2>&1)"; then echo "ok   $$1 $${SECONDS}s"; \
	  else printf "%s\n" "$$out"; echo "FAIL $$1 $${SECONDS}s"; echo "$$1" >> "$$FAILED"; fi; \
	  rm -rf "$$tmp"' _; \
	xrc=$$?; [ $$xrc -eq 0 ] || [ $$xrc -eq 123 ] || { echo "FAIL xargs stopped (exit $$xrc): not every file ran"; exit 1; }; \
	rc=0; while read -r t; do \
	  tmp="$$(mktemp -d)"; \
	  if TMPDIR="$$tmp" bash "$$t" < /dev/null > "$$failed.out" 2>&1; then echo "flaky $$t: failed beside the others, passed alone"; \
	  else cat "$$failed.out"; echo "FAIL $$t, alone too"; rc=1; fi; \
	  rm -rf "$$tmp"; \
	done < "$$failed"; exit $$rc
