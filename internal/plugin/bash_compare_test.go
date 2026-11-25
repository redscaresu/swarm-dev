package plugin

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

// swarmSh is the bash that plugin_version lives in, from this package's folder.
const swarmSh = "../../bin/swarm.sh"

// The first and last lines of plugin_version in bin/swarm.sh, as tests/config_test.sh's PV_SED
// cuts it.
const (
	fnFirst = "plugin_version() {"
	fnLast  = "}"
)

// bashTimeout bounds the one bash run over every case.
const bashTimeout = time.Minute

// runner defines plugin_version from $1, then runs it on each case file after $2, under set -u and
// pipefail as swarm.sh runs. Each stdout goes to <$2>/<n>; each exit status is a line on stdout. The
// call sits left of ||, so errexit is off inside it, as at swarm.sh's own call sites.
const runner = `set -uo pipefail
eval "$1"; dir="$2"; shift 2; n=0
for f in "$@"; do
  rc=0; plugin_version < "$f" > "${dir}/${n}" || rc=$?
  printf '%s\n' "${rc}"; n=$((n + 1))
done`

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

// TestBashCompare runs bash's plugin_version and Version over every case and compares the bytes on
// stdout and the exit status: Version prints its value and a LF and exits 0, or prints nothing and
// exits 1. If either side changes a rule the other keeps, the case for it goes red. It reads
// swarm.sh itself with os.ReadFile, so go test's cache keys on it; a child's reads are not tracked.
func TestBashCompare(t *testing.T) {
	src, err := os.ReadFile(swarmSh)
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	args := []string{"-c", runner, "_", cutFunction(t, string(src)), dir}
	for _, c := range cases {
		args = append(args, filepath.Join(testdata, c.file))
	}
	ctx, cancel := context.WithTimeout(context.Background(), bashTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, "bash", args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("bash: %v\n%s", err, stderr.String())
	}
	codes := strings.Fields(string(out))
	if len(codes) != len(cases) {
		t.Fatalf("bash printed %d exit statuses for %d cases: %q\n%s", len(codes), len(cases), out, stderr.String())
	}
	for i, c := range cases {
		bashOut, err := os.ReadFile(filepath.Join(dir, strconv.Itoa(i)))
		if err != nil {
			t.Fatal(err)
		}
		goOut, goCode := goSide(readCase(t, c.file))
		if !bytes.Equal(bashOut, goOut) || codes[i] != goCode {
			t.Errorf("%s (%s): bash printed %q and exited %s; Version printed %q and exited %s",
				c.file, c.why, bashOut, codes[i], goOut, goCode)
		}
	}
	t.Logf("compared bash's plugin_version and Version on %d cases, the files in testdata/", len(cases))
}

// goSide is what Version prints for b and its exit status, as the bash's.
func goSide(b []byte) ([]byte, string) {
	v, ok := Version(b)
	if !ok {
		return nil, "1"
	}
	return []byte(v + "\n"), "0"
}
