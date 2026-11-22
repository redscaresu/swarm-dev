---
kind: code
status: later
epic: helpers-shared
depends_on: []
touches: [internal/iface/iface.go:Store, internal/iface/iface.go:package doc, internal/adapter/store/store.go:ReadFile, internal/adapter/store/store.go:Glob, internal/adapter/store/store.go:IsFile, internal/adapter/store/store.go:MkdirAll, internal/adapter/store/store.go:WriteAtomic, internal/adapter/store/store.go:Remove, internal/adapter/store/store_test.go]
estimate_lines: 220
---

# The store reads, lists, writes whole and removes files

iface.Store has only WriteLine and AppendLines (internal/iface/iface.go:23-27), and the package doc says so (:5-6). report, gh_cache, touches_rows and the resend and declines entries read files, list them by pattern, write one whole and remove one. Add to Store and to the adapter (internal/adapter/store/store.go): ReadFile; Glob of a literal folder plus a pattern, the folder taken literally as glob.escape takes it (bin/lib/report.py:45, bin/lib/gh_cache.py:79); IsFile; MkdirAll; WriteAtomic, a temp file in the target's folder renamed over it and removed when the write fails (bin/lib/gh_cache.py:23-38); Remove. Each returns the os error, so a caller can tell a missing file from an unreadable one. Only the methods this epic's stories call. The package doc's 'Store has the two methods ... the other three have none yet' becomes a sentence that stays true as ports add methods (each port adds the methods it needs), so go-report-git and go-report-gh need not edit it. board-store also adds Store reads: see contradictions.

**Done when:**
- (1) Adapter tests on a real temp folder: Glob takes a folder named with [, ], * and ? literally; WriteAtomic leaves no temp file after a failed write and keeps the old content; ReadFile of a missing file gives an error errors.Is matches to fs.ErrNotExist. (2) Each goes red when its rule is broken (folder not escaped, temp file left, error dropped), shown on a worktree copy without .git. (3) internal/iface's package doc gives no count of any interface's methods. (4) go test ./... passes, and scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes
