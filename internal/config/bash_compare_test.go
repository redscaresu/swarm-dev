package config

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"testing"
	"time"
)

// This file runs bin/swarm.sh's own load_config, cut from the file, over every fixture in testdata/
// and checks that Parse prints the same bytes. It reaches inside bin/swarm.sh, so the port deletes it
// with the bash (docs/port/tests.tsv).
//
// A fixture is one file: its first line is a comment, `# <where the text comes from>; loads` or
// `# <where>; site: <site>`, and the rest of the file is the config text.

// swarmScript is bin/swarm.sh from this package's directory. The test reads it with os.ReadFile, so
// go test's cache keys on it.
var swarmScript = filepath.Join("..", "..", "bin", "swarm.sh")

const (
	fixtureDir = "testdata"
	// compareHome is $HOME on both sides, for a leading ~ in board_dir and repos_dir.
	compareHome = "/home/swarm-compare"
	// noFile names a config file that does not exist: load_config then leaves the defaults.
	noFile = "no-file"
	// bashTimeout bounds the one bash run over every fixture.
	bashTimeout = 2 * time.Minute
)

// The cut's anchors in bin/swarm.sh: die and the two variables it reads, and the settings block
// through load_config's closing brace.
const (
	dieStart        = "\ndie() {\n"
	dieEnd          = "\nDIE_LEVEL=-1\n"
	settingsStart   = "\nCFG_board_dir=docs\n"
	loadConfigStart = "\nload_config() {\n"
	functionEnd     = "\n}\n"
)

// compareDriver runs load_config once per config path it is given, each in a subshell so a die ends
// only that case. For each it prints what load_config printed on stderr, each key's CFG_ and SRC_ in
// CONFIG_KEYS' order when it loads, then `exit <status>` and a NUL. It writes no file: on a Mac whose
// virus scanner checks each new file, a few files per case made the run take a minute.
const compareDriver = `
set +e
for f in "$@"; do
  (
    set -e
    CONFIG_FILE="${f}"
    load_config
    for _key in ${CONFIG_KEYS}; do
      _cfg="CFG_${_key}"; _src="SRC_${_key}"
      printf 'CFG_%s=%s\nSRC_%s=%s\n' "${_key}" "${!_cfg}" "${_key}" "${!_src}"
    done
  ) 2>&1
  printf 'exit %d\n\0' "$?"
done
`

// site is one of load_config's die and warning sites: the name a fixture's comment gives it, and
// words its message always prints.
type site struct {
	name  string
	words string
}

// sites lists every die and warning site in load_config. TestLoadConfigMatchesBash fails when
// load_config has more or fewer, when a site has no fixture, and when a fixture that names a site
// prints no line with its words.
var sites = []site{
	{"key-value", "expected 'key = value'"},
	{"removed", "was removed and is ignored; delete the line"},
	{"expansion", "$ and backticks are not expanded"},
	{"empty-path", " is empty"},
	{"board_dir-quotes", `board_dir: " and \ are refused`},
	{"base_branches", "base_branches must be branch names"},
	{"sign_commits", "sign_commits must be true or false"},
	{"merge", "merge must be human or agent"},
	{"positive", "must be a positive whole number"},
	{"top_rung_rounds", "top_rung_rounds must be a whole number of 2 or more"},
	{"non-negative", "must be a non-negative whole number"},
	{"risky_effort", "risky_effort must be xhigh or high"},
	{"escalate_ladder", "escalate_ladder must be models separated by commas"},
	{"model-name", "must be a model name such as haiku"},
	{"goal", "goal must be off or a positive whole number of turns"},
	{"lead", "lead must be off or session"},
	{"merge_admin-merge_protected", "must be off or on"},
	{"review_verify", "review_verify must be ci or full"},
	{"demote_kinds", "is not a finding kind"},
	{"lead_epics", "lead_epics must be off or on"},
	{"commit_trailers", "commit_trailers must be trailers"},
	{"usage_warn_percent", "usage_warn_percent must be a whole number from 1 to 100"},
	{"agent_env", "is not a variable name"},
	{"unknown-key", "unknown key '"},
}

// fixture is one testdata file: its name, its comment and its config text.
type fixture struct {
	name, comment string
	body          []byte
}

const loadsSuffix = "; loads"

var siteSuffixRE = regexp.MustCompile(`; site: (\S+)$`)

// expectation reads a fixture's comment: the site it names, or "" when it says the text loads.
func (f fixture) expectation() (string, error) {
	if strings.HasSuffix(f.comment, loadsSuffix) {
		return "", nil
	}
	if m := siteSuffixRE.FindStringSubmatch(f.comment); m != nil {
		return m[1], nil
	}
	return "", fmt.Errorf("%s: its comment ends neither %q nor \"; site: <site>\": %q", f.name, loadsSuffix, f.comment)
}

func readFixtures(t *testing.T) []fixture {
	t.Helper()
	entries, err := os.ReadDir(fixtureDir)
	if err != nil {
		t.Fatal(err)
	}
	var fixtures []fixture
	for _, e := range entries {
		data, err := os.ReadFile(filepath.Join(fixtureDir, e.Name()))
		if err != nil {
			t.Fatal(err)
		}
		comment, body, ok := strings.Cut(string(data), "\n")
		if !ok || !strings.HasPrefix(comment, "# ") {
			t.Fatalf("%s: the first line must be a comment, `# <where it comes from>; ...`", e.Name())
		}
		fixtures = append(fixtures, fixture{name: e.Name(), comment: comment[2:], body: []byte(body)})
	}
	if len(fixtures) == 0 {
		t.Fatalf("no fixtures in %s", fixtureDir)
	}
	return fixtures
}

// cut returns text from start (without its leading newline) through the first end after it.
func cut(t *testing.T, text, start, end string) string {
	t.Helper()
	i := strings.Index(text, start)
	if i < 0 {
		t.Fatalf("%s has no %q: the cut's anchor moved", swarmScript, strings.TrimSpace(start))
	}
	j := strings.Index(text[i:], end)
	if j < 0 {
		t.Fatalf("%s: nothing ends %q after %q", swarmScript, strings.TrimSpace(end), strings.TrimSpace(start))
	}
	return text[i+1 : i+j+len(end)]
}

// loadConfigText is load_config's definition in bin/swarm.sh, from its first line to its closing brace.
func loadConfigText(t *testing.T, script string) string {
	t.Helper()
	return cut(t, script, loadConfigStart, functionEnd)
}

// compareScript is the bash that runs load_config: die as bin/swarm.sh has it, the settings block and
// load_config, then the driver. It never sources the whole of bin/swarm.sh, whose top level looks for
// a project.
func compareScript(t *testing.T, script string) string {
	t.Helper()
	// From the settings block's first line through load_config's closing brace.
	settings := cut(t, script, settingsStart, loadConfigText(t, script))
	return "set -euo pipefail\n" + cut(t, script, dieStart, dieEnd) + settings + compareDriver
}

// bashEnv is the test's environment with HOME set, and none of the variables that make bash read a
// file at start or change its options.
func bashEnv() []string {
	var env []string
	for _, kv := range os.Environ() {
		name, _, _ := strings.Cut(kv, "=")
		if name != "HOME" && name != "BASH_ENV" && name != "ENV" && name != "SHELLOPTS" && name != "BASHOPTS" {
			env = append(env, kv)
		}
	}
	return append(env, "HOME="+compareHome)
}

// runBash runs load_config over each path in one bash process, the bash found on PATH, and returns
// each path's output as compareDriver prints it, without the NUL.
func runBash(t *testing.T, script string, paths []string) map[string]string {
	t.Helper()
	file := filepath.Join(t.TempDir(), "compare.sh")
	if err := os.WriteFile(file, []byte(compareScript(t, script)), 0o600); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), bashTimeout)
	defer cancel()
	var stdout, stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, "bash", append([]string{file}, paths...)...)
	cmd.Env, cmd.Stdout, cmd.Stderr = bashEnv(), &stdout, &stderr
	if err := cmd.Run(); err != nil || stderr.Len() != 0 {
		t.Fatalf("bash %s: %v, with stderr %q", file, err, stderr.String())
	}
	outs := strings.Split(stdout.String(), "\x00")
	if last := len(outs) - 1; outs[last] != "" || last != len(paths) {
		t.Fatalf("bash printed %d cases for %d config paths:\n%s", len(outs)-1, len(paths), stdout.String())
	}
	results := make(map[string]string, len(paths))
	for i, p := range paths {
		results[p] = outs[i]
	}
	return results
}

// render prints Parse's result as compareDriver prints load_config's: the warnings, then `swarm: `
// and the error or each key's CFG_ and SRC_, then `exit <status>`.
func render(cfg Config, warnings []string, err error) string {
	var b strings.Builder
	for _, w := range warnings {
		b.WriteString(w + "\n")
	}
	if err != nil {
		b.WriteString("swarm: " + err.Error() + "\nexit 1\n")
		return b.String()
	}
	for _, s := range cfg.Settings {
		fmt.Fprintf(&b, "CFG_%s=%s\nSRC_%s=%s\n", s.Name, s.Value, s.Name, s.Source)
	}
	b.WriteString("exit 0\n")
	return b.String()
}

func firstLine(s string) string {
	line, _, _ := strings.Cut(s, "\n")
	return line
}

// If Parse prints any byte other than load_config does for a fixture (a message, a warning, a value,
// a source, the exit status), or Defaults differs from bash's defaults, this goes red naming the
// fixture and both outputs. It also goes red when a die or warning site is added to load_config, or a
// fixture's comment names a site its output does not reach.
func TestLoadConfigMatchesBash(t *testing.T) {
	data, err := os.ReadFile(swarmScript)
	if err != nil {
		t.Fatal(err)
	}
	script := string(data)
	fn := loadConfigText(t, script)
	if n := strings.Count(fn, `die "`) + strings.Count(fn, `"swarm: warning: `); n != len(sites) {
		t.Fatalf("load_config has %d die and warning sites, and sites lists %d: give a new one a fixture and a row", n, len(sites))
	}
	fixtures := readFixtures(t)
	dir := t.TempDir()
	paths := []string{filepath.Join(dir, noFile)}
	for _, f := range fixtures {
		p := filepath.Join(dir, f.name)
		if err := os.WriteFile(p, f.body, 0o600); err != nil {
			t.Fatal(err)
		}
		paths = append(paths, p)
	}
	bash := runBash(t, script, paths)

	t.Run(noFile, func(t *testing.T) {
		if got, want := render(Defaults(), nil, nil), bash[paths[0]]; got != want {
			t.Errorf("Defaults():\n%s\nbash's defaults:\n%s", got, want)
		}
	})
	// The comments and the site coverage are checked over every fixture's bash output, outside the
	// subtests, so a -run that picks one fixture still checks them all.
	reached := map[string]bool{}
	for i, f := range fixtures {
		expect, err := f.expectation()
		if err != nil {
			t.Error(err)
			continue
		}
		checkSite(t, f, expect, bash[paths[i+1]], reached)
	}
	for _, s := range sites {
		if !reached[s.name] {
			t.Errorf("no fixture names site %s (%q)", s.name, s.words)
		}
	}
	t.Run("fixture", func(t *testing.T) {
		for i, f := range fixtures {
			want := bash[paths[i+1]]
			t.Run(f.name, func(t *testing.T) {
				t.Log(firstLine(want))
				cfg, warnings, err := Parse(paths[i+1], f.body, compareHome)
				if got := render(cfg, warnings, err); got != want {
					t.Errorf("Parse:\n%s\nload_config:\n%s", got, want)
				}
			})
		}
	})
}

// checkSite fails a fixture whose comment says it loads when load_config stops, or names a site whose
// words load_config did not print, and records the site it reaches.
func checkSite(t *testing.T, f fixture, expect, out string, reached map[string]bool) {
	t.Helper()
	if expect == "" {
		if !strings.HasSuffix(out, "\nexit 0\n") {
			t.Errorf("%s: its comment says it loads, and load_config printed:\n%s", f.name, out)
		}
		return
	}
	i := slices.IndexFunc(sites, func(s site) bool { return s.name == expect })
	if i < 0 {
		t.Errorf("%s: its comment names site %q, which sites does not list", f.name, expect)
		return
	}
	if !strings.Contains(out, sites[i].words) {
		t.Errorf("%s: its comment names site %s, and load_config printed no %q:\n%s", f.name, expect, sites[i].words, out)
		return
	}
	reached[expect] = true
}

var (
	configKeysRE  = regexp.MustCompile(`(?m)^CONFIG_KEYS="([^"]*)"$`)
	removedKeysRE = regexp.MustCompile(`(?m)^REMOVED_KEYS="([^"]*)"$`)
)

// If someone adds, drops or reorders a key in CONFIG_KEYS or REMOVED_KEYS without the same change to
// Keys or RemovedKeys (or the other way round), this goes red with both lists.
func TestKeyListsMatchBash(t *testing.T) {
	data, err := os.ReadFile(swarmScript)
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct {
		name string
		re   *regexp.Regexp
		got  []string
	}{
		{"CONFIG_KEYS", configKeysRE, Keys()},
		{"REMOVED_KEYS", removedKeysRE, RemovedKeys()},
	} {
		m := c.re.FindAllSubmatch(data, -1)
		if len(m) != 1 {
			t.Errorf("%s sets %s on %d lines; want 1", swarmScript, c.name, len(m))
			continue
		}
		if want := strings.Fields(string(m[0][1])); !slices.Equal(c.got, want) {
			t.Errorf("the Go list for %s:\n%q\nbin/swarm.sh's:\n%q", c.name, c.got, want)
		}
	}
}
