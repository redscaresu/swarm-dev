package events

import (
	"bytes"
	"context"
	"encoding/json"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/redscaresu/swarm-dev/internal/adapter/store"
)

// The bash this test runs beside the Go, from this package's folder: append_event's file, the
// swarm.sh that plugin_version lives in, and the sample tests/events_tail_agents_test.sh writes back.
const (
	agentsSh   = "../../bin/lib/agents.sh"
	swarmSh    = "../../bin/swarm.sh"
	sampleFile = "../../tests/fixtures/events/v0.29.1-sample.tsv"
)

// caseDir holds one JSON file per compared case.
const caseDir = "testdata"

// The first and last lines of plugin_version in bin/swarm.sh, as tests/events_test.sh's evv cuts it.
const (
	fnFirst = "plugin_version() {"
	fnLast  = "}"
)

// fixedEpoch is the one instant both sides write, 2026-01-01T00:00:00Z, the clock
// tests/diff_fixtures_go_paths.sh's date stub pins (GO_PATHS_EPOCH).
const fixedEpoch = 1767225600

// dateStub is bash's date, first on PATH: it prints fixedEpoch in append_event's format and fails
// on any other call, so a change to the date call shows on stderr.
const dateStub = `#!/bin/sh
[ "$*" = '-u +%Y-%m-%dT%H:%M:%SZ' ] || { echo "date stub: unexpected arguments: $*" >&2; exit 2; }
echo 2026-01-01T00:00:00Z
`

// caseTimeout bounds one case's bash run: a loop that never ends, such as append_event's with its cut
// broken, fails the case rather than hanging go test.
const caseTimeout = time.Minute

// sampleTimeout bounds the sample's bash run, a date fork per row: on a machine whose process starts
// are slow and busy with every package's tests, 400 rows have taken over a minute.
const sampleTimeout = 5 * time.Minute

// sampleVersion is the plugin.json version the sample is written under.
const sampleVersion = `{"version": "0.32.0"}`

// caseRunner defines plugin_version from $1 and sources $2 (agents.sh), then makes each call
// <$3>/args.<n>, its arguments NUL-ended, first copying <$3>/manifest.<n> over plugin.json when there
// is one. Each call's stderr goes to <$3>/err.<n> and its exit status to <$3>/rc.<n>. The call sits
// left of ||, so errexit is off inside it, as at record_event's call.
const caseRunner = `set -uo pipefail
eval "$1"; source "$2"; dir="$3"; n=0
while [[ -e "${dir}/args.${n}" ]]; do
  [[ ! -e "${dir}/manifest.${n}" ]] || cp "${dir}/manifest.${n}" "${SWARM_HOME}/.claude-plugin/plugin.json"
  args=(); while IFS= read -r -d '' x; do args+=("${x}"); done < "${dir}/args.${n}"
  rc=0; append_event "${args[@]}" 2> "${dir}/err.${n}" || rc=$?
  printf '%s\n' "${rc}" > "${dir}/rc.${n}"; n=$((n + 1))
done`

// sampleRunner is tests/events_tail_agents_test.sh's writer over the sample in $3, after
// plugin_version from $1 and agents.sh from $2: each row's command, target and outcome, and k=v. Each
// call's exit status is a line on stdout.
const sampleRunner = `set -uo pipefail
eval "$1"; source "$2"
while IFS=$'\t' read -r _ c t _ o; do
  rc=0; append_event "${c}" "${t}" "${o}" k=v || rc=$?; printf '%s\n' "${rc}"
done < "$3"`

// The project a case starts from: .swarm a folder (the default), no .swarm, .swarm a regular file,
// or events.tsv a folder. The last two are writes that fail.
const (
	setupSwarmDir  = ""
	setupNoSwarm   = "no-swarm"
	setupSwarmFile = "swarm-file"
	setupLogDir    = "log-dir"
)

// swarmFileText is what .swarm holds when it is a regular file.
const swarmFileText = "not a folder\n"

// compareCase is one file under testdata/.
type compareCase struct {
	Comment  string          `json:"comment"`  // the check the case stands for
	Pane     *string         `json:"pane"`     // HERDR_PANE_ID; absent is unset
	Manifest json.RawMessage `json:"manifest"` // plugin.json's text, verbatim; absent is no plugin.json
	Project  string          `json:"project"`  // one of the setup constants
	Calls    []compareCall   `json:"calls"`
}

// compareCall is one append_event call in a case's process.
type compareCall struct {
	Args     []string        `json:"args"`     // append_event's arguments: command, then target, outcome and fields
	Manifest json.RawMessage `json:"manifest"` // plugin.json's new text, written before this call; absent leaves it
}

// result is what one side did on one call: its stderr and its exit status.
type result struct{ stderr, rc string }

// bashEnv is where one bash run happens: the date stub's folder, the plugin root, the project, the
// pane (nil is unset) and the run's time limit.
type bashEnv struct {
	stubs, root, project string
	pane                 *string
	timeout              time.Duration
}

// TestBashCompare runs bash's append_event and the Go Appender over every case under testdata/ and
// over the sample's rows, each side into its own temp project, and compares the project's files
// (events.tsv's bytes among them), each call's stderr and each call's exit status, an Append error
// counting as 1. Both sides write at fixedEpoch, with the same pane and plugin root. If either side
// changes a rule the other keeps, the case for it goes red. It reads agents.sh, swarm.sh, the sample
// and every case with os.ReadFile, so go test's cache keys on them; a child's reads are not tracked.
func TestBashCompare(t *testing.T) {
	fn := cutFunction(t, string(readFile(t, swarmSh)))
	readFile(t, agentsSh)
	stubs := t.TempDir()
	if err := os.WriteFile(filepath.Join(stubs, "date"), []byte(dateStub), 0o755); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(caseDir)
	if err != nil {
		t.Fatal(err)
	}
	files := 0
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		files++
		name := e.Name()
		t.Run(strings.TrimSuffix(name, ".json"), func(t *testing.T) {
			runCase(t, fn, stubs, name)
		})
	}
	if files == 0 {
		t.Fatalf("no case files under %s", caseDir)
	}
	rows := runSample(t, fn, stubs)
	t.Logf("compared bash's append_event and the Go Appender on %d cases: the %d case files in %s/ and the %d rows of %s",
		files+rows, files, caseDir, rows, sampleFile)
}

// runCase compares the two sides on one case file.
func runCase(t *testing.T, fn, stubs, name string) {
	var c compareCase
	dec := json.NewDecoder(bytes.NewReader(readFile(t, filepath.Join(caseDir, name))))
	dec.DisallowUnknownFields() // a misspelt key would otherwise drop its setting and still pass
	if err := dec.Decode(&c); err != nil {
		t.Fatalf("%s: %v", name, err)
	}
	if c.Comment == "" || len(c.Calls) == 0 {
		t.Fatalf("%s: a case needs a comment and at least one call", name)
	}
	root := t.TempDir()
	bashDir, goDir := setUp(t, c.Project), setUp(t, c.Project)
	before := snapshot(t, bashDir)

	resetManifest(t, root, c.Manifest)
	bashRes := bashCase(t, fn, stubs, root, bashDir, c)
	resetManifest(t, root, c.Manifest)
	goRes := goCase(t, root, goDir, c)

	for i := range c.Calls {
		if bashRes[i] != goRes[i] {
			t.Errorf("%s, call %d %q: bash wrote %q on stderr and exited %s; Go wrote %q and exited %s",
				c.Comment, i, c.Calls[i].Args, bashRes[i].stderr, bashRes[i].rc, goRes[i].stderr, goRes[i].rc)
		}
	}
	bashTree, goTree := snapshot(t, bashDir), snapshot(t, goDir)
	if bashTree != goTree {
		t.Errorf("%s: the projects differ\nbash:\n%s\nGo:\n%s", c.Comment, bashTree, goTree)
	}
	if c.Project == setupSwarmFile || c.Project == setupLogDir {
		for i, r := range bashRes {
			if r.rc == "0" {
				t.Errorf("%s: call %d succeeded on bash, but the write cannot happen", c.Comment, i)
			}
		}
		if bashTree != before {
			t.Errorf("%s: the failed write changed the project\nbefore:\n%s\nafter:\n%s", c.Comment, before, bashTree)
		}
	}
}

// bashCase runs the case's calls in one bash process and reads back each call's stderr and status.
func bashCase(t *testing.T, fn, stubs, root, project string, c compareCase) []result {
	work := t.TempDir()
	for i, call := range c.Calls {
		var args bytes.Buffer
		for _, a := range call.Args {
			args.WriteString(a + "\x00")
		}
		writeFile(t, filepath.Join(work, "args."+strconv.Itoa(i)), args.Bytes())
		if len(call.Manifest) > 0 {
			writeFile(t, filepath.Join(work, "manifest."+strconv.Itoa(i)), call.Manifest)
		}
	}
	env := bashEnv{stubs: stubs, root: root, project: project, pane: c.Pane, timeout: caseTimeout}
	if _, stderr := runBash(t, env, caseRunner, fn, agentsSh, work); stderr != "" {
		t.Fatalf("bash wrote %q on stderr outside the calls", stderr)
	}
	res := make([]result, len(c.Calls))
	for i := range c.Calls {
		n := strconv.Itoa(i)
		res[i] = result{string(readFile(t, filepath.Join(work, "err."+n))), strings.TrimSpace(string(readFile(t, filepath.Join(work, "rc."+n))))}
	}
	return res
}

// goCase makes the case's calls on one Appender, as one process, with the pane set as on the bash side.
func goCase(t *testing.T, root, project string, c compareCase) []result {
	setPane(t, c.Pane)
	var stderr bytes.Buffer
	a := New(store.Files{}, project, root, &stderr)
	res := make([]result, len(c.Calls))
	for i, call := range c.Calls {
		if len(call.Manifest) > 0 {
			writeManifest(t, root, string(call.Manifest))
		}
		stderr.Reset()
		err := a.Append(time.Unix(fixedEpoch, 0), call.Args[0], arg(call.Args, 1), arg(call.Args, 2), tail(call.Args, 3)...)
		res[i] = result{stderr.String(), exitStatus(err)}
	}
	return res
}

// runSample writes the sample's rows on both sides and compares them, returning how many rows it
// compared.
func runSample(t *testing.T, fn, stubs string) int {
	text := string(readFile(t, sampleFile))
	lines := strings.Split(strings.TrimSuffix(text, "\n"), "\n")
	root := t.TempDir()
	resetManifest(t, root, json.RawMessage(sampleVersion))
	pane := "w:me"
	bashDir, goDir := setUp(t, setupSwarmDir), setUp(t, setupSwarmDir)
	env := bashEnv{stubs: stubs, root: root, project: bashDir, pane: &pane, timeout: sampleTimeout}
	bashOut, bashErr := runBash(t, env, sampleRunner, fn, agentsSh, sampleFile)

	setPane(t, &pane)
	var goErr bytes.Buffer
	a := New(store.Files{}, goDir, root, &goErr)
	var goOut strings.Builder
	for i, line := range lines {
		cols := strings.Split(line, "\t")
		if len(cols) != 5 {
			t.Fatalf("%s row %d has %d columns, not 5", sampleFile, i+1, len(cols))
		}
		goOut.WriteString(exitStatus(a.Append(time.Unix(fixedEpoch, 0), cols[1], cols[2], cols[4], "k=v")) + "\n")
	}
	if bashOut != goOut.String() {
		t.Errorf("the sample's exit statuses differ\nbash: %q\nGo:   %q", bashOut, goOut.String())
	}
	if bashErr != goErr.String() {
		t.Errorf("the sample's stderr differs\nbash: %q\nGo:   %q", bashErr, goErr.String())
	}
	if b, g := snapshot(t, bashDir), snapshot(t, goDir); b != g {
		t.Errorf("the sample's projects differ\nbash:\n%s\nGo:\n%s", b, g)
	}
	return len(lines)
}

// runBash runs script under bash in e: the plugin root, project and pane set, SWARM_FORBID_PROJECT
// unset, the C locale and the date stub first on PATH. It returns its stdout and stderr.
func runBash(t *testing.T, e bashEnv, script string, args ...string) (string, string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), e.timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "bash", append([]string{"-c", script, "_"}, args...)...)
	env := []string{"PATH=" + e.stubs + ":" + os.Getenv("PATH"), "PROJECT_DIR=" + e.project, "SWARM_HOME=" + e.root, "LC_ALL=C"}
	if e.pane != nil {
		env = append(env, paneVar+"="+*e.pane)
	}
	for _, kv := range os.Environ() {
		k, _, _ := strings.Cut(kv, "=")
		if k != "PATH" && k != "PROJECT_DIR" && k != "LC_ALL" && !strings.HasPrefix(k, "SWARM_") && !strings.HasPrefix(k, "HERDR_") {
			env = append(env, kv)
		}
	}
	cmd.Env = env
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("bash: %v\n%s", err, stderr.String())
	}
	return stdout.String(), stderr.String()
}

// setUp is a fresh project in the state setup names.
func setUp(t *testing.T, setup string) string {
	t.Helper()
	dir := t.TempDir()
	swarm := filepath.Join(dir, ".swarm")
	switch setup {
	case setupSwarmDir:
		mkdir(t, swarm)
	case setupNoSwarm:
	case setupSwarmFile:
		writeFile(t, swarm, []byte(swarmFileText))
	case setupLogDir:
		mkdir(t, filepath.Join(dir, LogFile))
	default:
		t.Fatalf("unknown project %q", setup)
	}
	return dir
}

// snapshot is every path under dir, a line each: d and the path for a folder, f, the path and its
// bytes quoted for a file.
func snapshot(t *testing.T, dir string) string {
	t.Helper()
	var b strings.Builder
	err := filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil || p == dir {
			return err
		}
		rel, _ := filepath.Rel(dir, p)
		if d.IsDir() {
			b.WriteString("d " + rel + "\n")
			return nil
		}
		data, rerr := os.ReadFile(p)
		if rerr != nil {
			return rerr
		}
		b.WriteString("f " + rel + " " + strconv.Quote(string(data)) + "\n")
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return b.String()
}

// resetManifest makes root's plugin.json text, or takes it away when text is empty, leaving
// .claude-plugin/ for the bash's copy.
func resetManifest(t *testing.T, root string, text json.RawMessage) {
	t.Helper()
	mkdir(t, filepath.Join(root, ".claude-plugin"))
	if len(text) == 0 {
		if err := os.Remove(root + manifest); err != nil && !os.IsNotExist(err) {
			t.Fatal(err)
		}
		return
	}
	writeManifest(t, root, string(text))
}

// setPane sets paneVar to *pane, or unsets it when pane is nil, and unsets forbidVar, for the Go side.
func setPane(t *testing.T, pane *string) {
	t.Helper()
	t.Setenv(forbidVar, "") // t.Setenv restores both after the test
	if err := os.Unsetenv(forbidVar); err != nil {
		t.Fatal(err)
	}
	if pane != nil {
		t.Setenv(paneVar, *pane)
		return
	}
	t.Setenv(paneVar, "")
	if err := os.Unsetenv(paneVar); err != nil {
		t.Fatal(err)
	}
}

// cutFunction is plugin_version's text in src: from its first line to the next line that is "}".
func cutFunction(t *testing.T, src string) string {
	t.Helper()
	var out []string
	for _, line := range strings.Split(src, "\n") {
		if out == nil && line != fnFirst {
			continue
		}
		out = append(out, line)
		if line == fnLast {
			return strings.Join(out, "\n") + "\n"
		}
	}
	t.Fatalf("%s has no %q ... %q block", swarmSh, fnFirst, fnLast)
	return ""
}

// exitStatus is an Append's error as bash's exit status: 1 for an error, else 0.
func exitStatus(err error) string {
	if err != nil {
		return "1"
	}
	return "0"
}

// arg is args[i], or empty when the call has no such argument, as bash's ${i:-} reads it.
func arg(args []string, i int) string {
	if i < len(args) {
		return args[i]
	}
	return ""
}

// tail is args from i on, or none.
func tail(args []string, i int) []string {
	if i < len(args) {
		return args[i:]
	}
	return nil
}

func readFile(t *testing.T, path string) []byte {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func writeFile(t *testing.T, path string, data []byte) {
	t.Helper()
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
}

func mkdir(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(path, 0o755); err != nil {
		t.Fatal(err)
	}
}
