---
status: active
agreed: 2026-11-24
hld: 2026-11-18-swarm-dev-v0-32-go-rewrite
parent: helpers-shared
depends_on: [foundation-exit]
---

# The Go pieces every shared module needs, the copies list and the gh_cache decision

Store's file methods, the Python JSON and text decoders, per-file entry registration, the clock comparison, and the list of Python copies with its test. The two lead stories also live here: the gh_cache decision and the patch cuts.

A child of [helpers-shared](helpers-shared.md), split on 2026-11-23. The parent's constraints and its shared rules (L2, the P rules) apply here unchanged.

**Done when:** Store has ReadFile, Glob, IsFile, MkdirAll, WriteAtomic and Remove with adapter tests. internal/pyjson, internal/pytext and internal/clock each have a comparison test against the Python (clock.py for the clock) that runs both over the same fixtures, the malformed cases among them, compares the output byte for byte, and fails when either side alone is changed. A cmd/swarm entry registers from its own file. docs/port/copies.tsv names, for each of the five modules, what still imports its Python copy, inline sites included. tests/port_copies_test.sh fails when a copy outlives its last importer or is deleted before it. shared-gh-cache-call records your answer on gh_cache.

**Stories:**
- [go-store-files](../stories/go-store-files.md)
- [go-py-json](../stories/go-py-json.md)
- [go-py-decode](../stories/go-py-decode.md)
- [go-entries-per-file](../stories/go-entries-per-file.md)
- [go-clock-compare](../stories/go-clock-compare.md)
- [shared-copies-list](../stories/shared-copies-list.md)
- shared-gh-cache-call: answered by the user on 2026-11-24 (a sixth module; non-fix-cache-binary cleared), so it left the board
- [shared-patches](../stories/shared-patches.md)

**Out of scope:**
- Any module's own Go (the other children)

**Your part:**
- You: shared-gh-cache-call's You: step. Agree gh_cache as a sixth module under exception 3, or have it bridged with one live implementation.
- Lead: shared-patches (shared step L2).

**Areas:**
- go-store-files: [internal/iface/iface.go:Store, internal/iface/iface.go:package doc, internal/adapter/store/store.go:ReadFile, internal/adapter/store/store.go:Glob, internal/adapter/store/store.go:IsFile, internal/adapter/store/store.go:MkdirAll, internal/adapter/store/store.go:WriteAtomic, internal/adapter/store/store.go:Remove, internal/adapter/store/store_test.go:ReadFile, Glob, IsFile, MkdirAll, WriteAtomic and Remove tests]
- go-py-json: [internal/pyjson/json.go, internal/pyjson/compare_test.go]
- go-py-decode: [internal/pytext/decode.go, internal/pytext/compare_test.go]
- go-entries-per-file: [cmd/swarm/frame.go:entries, cmd/swarm/frame_test.go:TestRegister, docs/port/README.md:§ Two forms, AGENTS.md:§ Working on this repository]
- go-clock-compare: [internal/clock/compare_test.go]
- shared-copies-list: [docs/port/copies.tsv, tests/port_copies_test.sh, docs/port/tests.tsv:port_copies row, docs/port/README.md:§ What each list holds, scripts/test-map.tsv:port_copies row]
- shared-patches: []
