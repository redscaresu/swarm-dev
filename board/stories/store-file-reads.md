---
kind: code
status: later
epic: board-store
depends_on: []
touches: [internal/iface/iface.go:Store, internal/adapter/store/store.go:Files, internal/adapter/store/store_test.go (new)]
estimate_lines: 160
easy: true
---

# The store reads, stats and resolves files, and appends a line making its folder, for the board-store readers

Needs no other story. iface.Store (internal/iface/iface.go:20-28) and store.Files (internal/adapter/store/store.go) gain five methods. ReadFile(path) ([]byte, error). Stat and Lstat (fs.FileInfo), whose errors wrap fs.ErrNotExist and fs.ErrPermission so callers use errors.Is. RealPath(dir) (string, error): the physical path `cd <dir> && pwd -P` prints, failing for a missing path or a file. AppendLine(path, line) error: makes the parent folders as `mkdir -p` does, then adds line plus a newline in one O_APPEND write, and returns the error when either step fails; a new file is 0666 before the umask, as bash's >> makes it (fileMode's 0600 stays for the frame's own files). WriteLine and AppendLines do not change. The frontmatter and events stories reach files only through these (P5). helpers-shared's go-store-files also adds ReadFile (contradictions: Store clash). port: true, no stage: line (P1).

**Done when:**
- A new internal/adapter/store/store_test.go over t.TempDir(): ReadFile and Stat of a missing path return errors with errors.Is(err, fs.ErrNotExist); Lstat of a dangling symlink succeeds where Stat fails; ReadFile of a chmod 000 file gives errors.Is(err, fs.ErrPermission), the case skipped when the test runs as root.
- RealPath of a symlink to a folder equals what `cd <link> && pwd -P` prints, run once through bash in the test; RealPath of a regular file fails.
- AppendLine to <tmp>/p/.swarm/events.tsv with no .swarm makes the folder and the file; two calls leave exactly two lines; the new file's mode is 0666 with the test's umask cleared from it. With <tmp>/q/.swarm a regular file, AppendLine to <tmp>/q/.swarm/events.tsv returns an error and that file's bytes are unchanged.
- Mutation, on a copy without .git: make AppendLine skip making the folder and its check goes red; make it return nil when the folder cannot be made and the regular-file check goes red; make RealPath return its argument unresolved and the symlink check goes red.
- gofmt -l . prints nothing; go vet ./... and go test ./... pass, the layer checks among them.
- scripts/select-tests.sh --run passes.
- scripts/select-tests.sh --run passes
