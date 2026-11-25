package report

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"github.com/redscaresu/swarm-dev/internal/adapter/git"
)

// pythonBound bounds one run of the Python side, and setupBound one git call that sets a case up.
const (
	pythonBound = 60 * time.Second
	setupBound  = 30 * time.Second
)

// pyGit runs each step of argv[2] through report.py (argv[1] is bin/lib) and prints the results as one
// JSON list. A step that reads output that is not UTF-8 gives {"error": "not UTF-8"}.
const pyGit = `import json, subprocess, sys
sys.path.insert(0, sys.argv[1])
import report
out = []
for s in json.loads(sys.argv[2]):
    try:
        if s["op"] == "ssh":
            out.append(report.batch_ssh(s["root"]))
        elif s["op"] == "quiet":
            got = report.quiet_git(s["root"], *s["args"], seconds=s["seconds"])
            out.append([got.returncode, got.stdout, got.stderr])
        elif s["op"] == "fetch":
            out.append(report.git_fetch(s["root"], *s["args"]))
        elif s["op"] == "config":
            subprocess.run(["git", "-C", s["root"], "config", *s["args"]], check=True)
            out.append(None)
    except UnicodeDecodeError:
        out.append({"error": "not UTF-8"})
print(json.dumps(out))
`

// gitStep is one call a case makes, on both sides: ssh (BatchSSH), quiet (QuietGit), fetch (GitFetch)
// or config, which sets root's git config to args with the real git and gives null.
type gitStep struct {
	Op      string   `json:"op"`
	Root    string   `json:"root"`
	Args    []string `json:"args"`
	Seconds int      `json:"seconds"`
}

// stubScript is a git that answers by its last argument, run as git -C <root> <args>. A config call
// prints $STUB_SSH with CRLF, or fails when it is empty. env prints only the variables it names, never
// the whole environment, which holds the session's credentials.
const stubScript = `#!/bin/sh
last=
for a; do last=$a; done
if [ "$3" = config ]; then
  [ -n "$STUB_SSH" ] || exit 1
  printf '%s\r\n' "$STUB_SSH"
  exit 0
fi
case $last in
env)
  printf 'args:'; printf ' [%s]' "$@"; printf '\n'
  if IFS= read -r line; then printf 'stdin: %s\n' "$line"; else echo 'stdin: none'; fi
  for v in GIT_TERMINAL_PROMPT GIT_SSH_COMMAND STUB_INHERITED; do
    eval "set=\${$v+set} val=\${$v-}"
    printf '%s %s=%s\n' "${set:-unset}" "$v" "$val"
  done
  printf 'crlf\r\nlone\rend' >&2 ;;
sleep) exec sleep 5 ;;
linger) (sleep 4; echo late) & exit 0 ;;
late) (sleep 2; echo late) & exit 0 ;;
spaces)
  printf 'first line\n\302\205 second \342\200\250\037third\037 \035\n\v\n' >&2
  exit 1 ;;
silent) exit 3 ;;
signal) kill -TERM $$ ;;
latin) printf 'caf\351\n' >&2; exit 1 ;;
esac
`

// runPython runs steps through report.py and gives its JSON, decoded. Its stdin carries a line, so a
// quiet_git that let git read stdin shows it.
func runPython(t *testing.T, steps []gitStep) []any {
	t.Helper()
	lib, err := filepath.Abs(filepath.Join("..", "..", "bin", "lib"))
	if err != nil {
		t.Fatal(err)
	}
	arg, err := json.Marshal(steps)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), pythonBound)
	defer cancel()
	cmd := exec.CommandContext(ctx, "python3", "-c", pyGit, lib, string(arg))
	cmd.Stdin = strings.NewReader("leak\n")
	out, err := cmd.Output()
	if err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) {
			t.Fatalf("report.py: %v\n%s", err, exit.Stderr)
		}
		t.Fatalf("report.py: %v", err)
	}
	var got []any
	if err := json.Unmarshal(out, &got); err != nil {
		t.Fatalf("report.py's output %q: %v", out, err)
	}
	return got
}

// runGo runs steps through the Go, with a fresh Git, and gives the results as JSON decodes them, so
// they compare with runPython's.
func runGo(t *testing.T, steps []gitStep) []any {
	t.Helper()
	g := NewGit(git.Repo{})
	var out []any
	for _, s := range steps {
		var got any
		var err error
		switch s.Op {
		case "ssh":
			got, err = g.BatchSSH(s.Root)
		case "quiet":
			var c Completed
			c, err = g.QuietGit(s.Root, s.Seconds, s.Args...)
			got = []any{c.Code, c.Stdout, c.Stderr}
		case "fetch":
			got, err = g.GitFetch(s.Root, s.Args...)
		case "config":
			realGit(t, s.Root, append([]string{"config"}, s.Args...)...)
		default:
			t.Fatalf("unknown step %q", s.Op)
		}
		if errors.Is(err, ErrNotUTF8) {
			got, err = map[string]any{"error": "not UTF-8"}, nil
		}
		if err != nil {
			t.Fatalf("%s %v: %v", s.Op, s.Args, err)
		}
		out = append(out, got)
	}
	b, err := json.Marshal(out)
	if err != nil {
		t.Fatal(err)
	}
	var decoded []any
	if err := json.Unmarshal(b, &decoded); err != nil {
		t.Fatal(err)
	}
	return decoded
}

// realGit runs the git on PATH in dir for a case's setup, and fails the test if it fails.
func realGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), setupBound)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", dir}, args...)...)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git -C %s %v: %v\n%s", dir, args, err, out)
	}
}

// compare runs steps on both sides and fails on any difference, naming the case.
func compare(t *testing.T, name string, steps []gitStep) {
	t.Helper()
	py, goes := runPython(t, steps), runGo(t, steps)
	t.Logf("%s: %#v", name, py)
	if !reflect.DeepEqual(py, goes) {
		t.Errorf("%s: report.py and the Go differ\n  py %#v\n  go %#v", name, py, goes)
	}
}

// repoVars are the variables that point git at a repository other than -C's. A test run from a git
// hook inherits GIT_DIR and GIT_INDEX_FILE, which would aim the setup's init and commit at the real
// repository.
var repoVars = []string{
	"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_COMMON_DIR",
	"GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_CEILING_DIRECTORIES",
}

// isolate keeps the user's and the system's git config and any repository the caller points git at out,
// and reads text as UTF-8 on both sides, as every UTF-8 locale does. It sets GIT_TERMINAL_PROMPT to 1,
// so a QuietGit that dropped its own 0 shows.
func isolate(t *testing.T) {
	for _, v := range repoVars {
		t.Setenv(v, "") // puts the caller's value back after the test
		if err := os.Unsetenv(v); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("GIT_TERMINAL_PROMPT", "1")
	t.Setenv("GIT_CONFIG_GLOBAL", os.DevNull)
	t.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	t.Setenv("PYTHONUTF8", "1")
	t.Setenv(sshCommand, "")
	t.Setenv("STUB_SSH", "")
	t.Setenv("STUB_INHERITED", "from the test") // shows git gets the caller's own environment too
}

// If report.py's git_fetch gave the first stderr line, the missing remote's would differ. If
// BatchSSH dropped core.sshCommand or its cache, or QuietGit dropped the batch ssh, the ssh steps
// would differ. Every case runs the real git.
func TestGitCompareRealRepo(t *testing.T) {
	isolate(t)
	tmp := t.TempDir()
	upstream, clone, ssh := filepath.Join(tmp, "upstream"), filepath.Join(tmp, "clone"), filepath.Join(tmp, "fake-ssh")
	realGit(t, tmp, "init", "-q", upstream)
	realGit(t, upstream, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-q", "--allow-empty", "-m", "one")
	realGit(t, tmp, "clone", "-q", upstream, clone)
	if err := os.WriteFile(ssh, []byte("#!/bin/sh\necho \"fake ssh: $*\" >&2\nexit 255\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	overSSH := []string{"fetch", "-q", "ssh://git@example.invalid/x.git"}

	compare(t, "a missing remote", []gitStep{{Op: "fetch", Root: clone, Args: []string{"nosuch"}}})
	compare(t, "a fetch that works", []gitStep{{Op: "fetch", Root: clone, Args: []string{"origin"}}})
	compare(t, "no ssh set", []gitStep{{Op: "ssh", Root: clone}})
	compare(t, "core.sshCommand set, then changed", []gitStep{
		{Op: "config", Root: clone, Args: []string{"core.sshCommand", ssh + " -v"}},
		{Op: "ssh", Root: clone},
		{Op: "quiet", Root: clone, Args: overSSH, Seconds: FetchSeconds},
		{Op: "config", Root: clone, Args: []string{"core.sshCommand", "other-ssh"}},
		{Op: "ssh", Root: clone},
		{Op: "config", Root: clone, Args: []string{"--unset", "core.sshCommand"}},
	})
	t.Setenv(sshCommand, ssh+" -x")
	compare(t, "GIT_SSH_COMMAND set", []gitStep{
		{Op: "ssh", Root: clone},
		{Op: "quiet", Root: clone, Args: overSSH, Seconds: FetchSeconds},
		{Op: "fetch", Root: clone, Args: overSSH[2:]},
	})
}

// If QuietGit dropped GIT_TERMINAL_PROMPT=0 or the batch ssh, or the adapter gave git a stdin, the
// env step's output would differ; if QuietGit dropped the bound, the sleep would run out its 5 s and
// exit 0. If BatchSSH tried core.sshCommand before GIT_SSH_COMMAND, the env step with both set would
// name the wrong ssh. If the adapter stopped reading when git exited, late would lose the line git's
// child writes after; if it read on past the bound, linger would give git's 0, not report.py's 124.
// The other steps pin GitFetch's last line, its "exit N" and Python's text mode, newlines and errors.
func TestGitCompareStub(t *testing.T) {
	isolate(t)
	stubs := t.TempDir()
	if err := os.WriteFile(filepath.Join(stubs, "git"), []byte(stubScript), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", stubs+string(os.PathListSeparator)+os.Getenv("PATH"))
	root := t.TempDir()
	quiet := func(arg string, seconds int) gitStep {
		return gitStep{Op: "quiet", Root: root, Args: []string{arg}, Seconds: seconds}
	}
	fetch := func(arg string) gitStep { return gitStep{Op: "fetch", Root: root, Args: []string{arg}} }

	compare(t, "no ssh set", []gitStep{quiet("env", FetchSeconds)})
	t.Setenv("STUB_SSH", "  cfg-ssh -v ")
	compare(t, "core.sshCommand set", []gitStep{quiet("env", FetchSeconds)})
	t.Setenv(sshCommand, "user-ssh -x")
	compare(t, "GIT_SSH_COMMAND set", []gitStep{quiet("env", FetchSeconds)})
	compare(t, "past the bound", []gitStep{quiet("sleep", 1)})
	compare(t, "a child holds the output past the bound", []gitStep{quiet("linger", 2)})
	compare(t, "a child writes after git exits, inside the bound", []gitStep{quiet("late", FetchSeconds)})
	compare(t, "output", []gitStep{
		fetch("spaces"), fetch("silent"), fetch("signal"), fetch("latin"), quiet("latin", FetchSeconds),
	})
}

// If gitIsSpace or gitIsLineBreak missed a character Python's str.isspace or str.splitlines takes,
// or took one it does not, GitFetch's lines would differ from git_fetch's on that character.
func TestGitComparePythonSpace(t *testing.T) {
	const script = `import json
cs = range(0x110000)
print(json.dumps([[c for c in cs if chr(c).isspace()], [c for c in cs if len(("a" + chr(c) + "b").splitlines()) == 2]]))
`
	ctx, cancel := context.WithTimeout(context.Background(), pythonBound)
	defer cancel()
	out, err := exec.CommandContext(ctx, "python3", "-c", script).Output()
	if err != nil {
		t.Fatal(err)
	}
	var py [2][]rune
	if err := json.Unmarshal(out, &py); err != nil {
		t.Fatal(err)
	}
	var space, breaks []rune
	for r := rune(0); r <= utf8.MaxRune; r++ {
		if gitIsSpace(r) {
			space = append(space, r)
		}
		if gitIsLineBreak(r) {
			breaks = append(breaks, r)
		}
	}
	if !reflect.DeepEqual(space, py[0]) {
		t.Errorf("gitIsSpace holds for %U, Python's isspace for %U", space, py[0])
	}
	if !reflect.DeepEqual(breaks, py[1]) {
		t.Errorf("gitIsLineBreak holds for %U, Python's splitlines breaks at %U", breaks, py[1])
	}
}
