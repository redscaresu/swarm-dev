---
kind: code
status: blocked
epic: go-layers
depends_on: [go-layer-walk]
needs: go-layer-walk (the walk's records in internal/layers/walk_test.go)
touches: [internal/layers/names_test.go, internal/layers/testdata/names/]
estimate_lines: 160
---

# Fail a Go package outside the four adapters that uses an os, filepath or fmt name that reaches a file, a process or the standard streams

Uses the walk's records in internal/layers/walk_test.go from go-layer-walk; it does not edit that file. The rule, for rules, interfaces, clock and wiring packages: a selector on os, path/filepath or fmt must be on that package's allowed names, so a name not listed fails, called or only passed, under any import name. os: Getenv, LookupEnv, Environ, Expand, ExpandEnv, the Err* values, IsExist, IsNotExist, IsPermission, FileMode, FileInfo, the Mode* constants, PathSeparator and PathListSeparator. path/filepath: the functions that read no file (Base, Clean, Dir, Ext, FromSlash, IsAbs, IsLocal, Join, Match, Rel, Split, SplitList, ToSlash, VolumeName), its separators and its error values; so Abs, EvalSymlinks, Glob, Walk and WalkDir fail. fmt: Append*, Errorf, Fprint*, Fscan*, FormatString, Sprint*, Sscan* and its interface types; Print* and Scan* use the standard streams and fail. Wiring (cmd/) may also use os.Args, os.Exit, os.Stdin, os.Stdout and os.Stderr, and fmt's Print* and Scan*. The test logs each package's allowed names. Fixtures follow go-layer-walk's limits (no SWARM_ name, no lock primitive). Break: add ReadFile to os's names; the fixture test must go red.

**Done when:**
- For fixture trees under internal/layers/testdata/names/ the test asserts the exact findings by file:line, for a rules package that calls os.ReadFile, passes os.ReadFile as a value, calls ReadFile on an aliased os, and uses os.Remove, os.Getwd, os.Setenv, os.Exit, fmt.Println, filepath.Abs, filepath.Glob and filepath.WalkDir. Wiring's os.Exit, os.Args and fmt.Println pass, and so do a rules package's os.Getenv, os.ErrNotExist, filepath.Join and fmt.Sprintf. On the real tree it passes, with cmd/swarm's os.Exit, os.Args and os.Stderr allowed as wiring. A throwaway tmp/ branch PR whose rules package calls os.ReadFile turns go-checks red, and is closed unmerged. The story PR links it. tests/port_swarm_names_test.sh and tests/port_locks_test.sh pass.
- scripts/select-tests.sh --run passes
