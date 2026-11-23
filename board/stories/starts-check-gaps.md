---
kind: code
status: later
touches: [internal/layers/starts_test.go:startFindings, internal/layers/walk_test.go]
estimate_lines: 80
easy: true
---

# Close two gaps in the Go process-start check

From the v0.32.0 retro (#1165). The starts check (internal/layers/starts_test.go `startFindings`) misses a conversion from a local type, `exec.Cmd(rawCmd{...})`, and an `exec.Cmd` literal with its type elided, `[]exec.Cmd{{Path: "gh"}}`. Record both in the walk and report them as starts.

**Done when:**
- A fixture with each form fails the check, and passes once the form is removed.
- `go test ./internal/layers/` passes on main's tree.
