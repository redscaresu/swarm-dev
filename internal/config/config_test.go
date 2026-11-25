package config

import (
	"fmt"
	"slices"
	"testing"
)

// path is the config path every test parses under; each message names it.
const path = "/p/.claude/swarm/config"

// validSample is a value each key's case arm passes. A key added to keys with no sample here fails
// TestEveryKeyHasAParseCase, so the test cannot skip it.
var validSample = map[string]string{
	"board_dir":              "board",
	"repos_dir":              "/r",
	"base_branches":          "dev main",
	"sign_commits":           "true",
	"merge":                  "agent",
	"stall_minutes":          "45",
	"queue_minutes":          "15",
	"sonnet_share":           "4",
	"risky_effort":           "high",
	"escalate_after":         "0",
	"escalate_ladder":        "sonnet,opus,fable",
	"step_up_findings":       "4",
	"top_rung_rounds":        "3",
	"builder_subagent_model": "haiku",
	"goal":                   "20",
	"codex_minutes":          "12",
	"fallback_reviewer":      "opus[1m]",
	"lead":                   "session",
	"merge_admin":            "on",
	"merge_protected":        "on",
	"review_verify":          "full",
	"demote_kinds":           "duplicate-code,efficiency",
	"lead_epics":             "on",
	"commit_trailers":        "Co-Authored-By: A <a@b>; Signed-off-by: B <b@c>",
	"agent_env":              "FOO_KEY BAR",
	"usage_warn_percent":     "80",
}

// If someone adds a key to keys without a case arm in check, or drops a key from an arm, its line
// comes back as an unknown key and this goes red naming it.
func TestEveryKeyHasAParseCase(t *testing.T) {
	if len(Keys()) == 0 {
		t.Fatal("Keys() is empty")
	}
	for _, name := range Keys() {
		sample, ok := validSample[name]
		if !ok {
			t.Errorf("%s: no valid sample in validSample; add one", name)
			continue
		}
		cfg, warnings, err := Parse(path, []byte(name+" = "+sample+"\n"), "/home/u")
		if err != nil {
			t.Errorf("%s: %q did not load: %v", name, sample, err)
			continue
		}
		got, _ := cfg.Get(name)
		if got.Value != sample || got.Source != path+":1" || len(warnings) != 0 {
			t.Errorf("%s: got %+v, warnings %q; want value %q from %s:1", name, got, warnings, sample, path)
		}
	}
}

// If someone reorders keys or changes the unknown-key message, this goes red.
func TestUnknownKeyListsKeysInOrder(t *testing.T) {
	_, _, err := Parse(path, []byte("# a comment\nnosuchkey = 1\n"), "/home/u")
	want := path + ":2: unknown key 'nosuchkey' (known: board_dir repos_dir base_branches sign_commits merge " +
		"stall_minutes queue_minutes sonnet_share risky_effort escalate_after escalate_ladder step_up_findings " +
		"top_rung_rounds builder_subagent_model goal codex_minutes fallback_reviewer lead merge_admin " +
		"merge_protected review_verify demote_kinds lead_epics commit_trailers agent_env usage_warn_percent)"
	if err == nil || err.Error() != want {
		t.Fatalf("got %v\nwant %s", err, want)
	}
}

// If a removed key stops warning, warns with other words or another line, or stops the load, this
// goes red. Each value would fail a live key's arm, a $ and a backtick among them, so a key that lost
// its removed status fails too. The names come from RemovedKeys: tests/removed_test.sh allows them in
// keys.go's list alone, and config-compare's test checks that list against REMOVED_KEYS.
func TestRemovedKeysWarnAndLoadOn(t *testing.T) {
	removed := RemovedKeys()
	if len(removed) == 0 {
		t.Fatal("RemovedKeys() is empty")
	}
	values := []string{"epic", "$x", "`y`", "whatever"}
	content := "# old settings\n"
	var want []string
	for i, name := range removed {
		content += name + " = " + values[i%len(values)] + "\n"
		want = append(want, fmt.Sprintf("swarm: warning: %s:%d: %s was removed and is ignored; delete the line", path, i+2, name))
	}
	content += "merge = agent\n"
	cfg, warnings, err := Parse(path, []byte(content), "/home/u")
	if err != nil {
		t.Fatalf("the config did not load: %v", err)
	}
	if !slices.Equal(warnings, want) {
		t.Errorf("warnings:\n got %q\nwant %q", warnings, want)
	}
	if got, _ := cfg.Get("merge"); got.Value != "agent" || got.Source != fmt.Sprintf("%s:%d", path, len(removed)+2) {
		t.Errorf("merge after the removed keys: got %+v", got)
	}
}

// If a warning before an error is lost, the user sees the error alone where bash showed both.
func TestWarningsBeforeAnErrorAreKept(t *testing.T) {
	name := RemovedKeys()[0]
	_, warnings, err := Parse(path, []byte(name+" = 1\nmerge = auto\n"), "/home/u")
	wantErr := path + ":2: merge must be human or agent, not 'auto'"
	if err == nil || err.Error() != wantErr {
		t.Errorf("got %v, want %s", err, wantErr)
	}
	wantWarn := "swarm: warning: " + path + ":1: " + name + " was removed and is ignored; delete the line"
	if !slices.Equal(warnings, []string{wantWarn}) {
		t.Errorf("got warnings %q, want %q", warnings, wantWarn)
	}
}

// If lessons_file starts warning, failing or setting anything, an old config changes how it loads.
func TestLessonsFileIsSkippedSilently(t *testing.T) {
	cfg, warnings, err := Parse(path, []byte("lessons_file = $HOME/`x`\n"), "/home/u")
	if err != nil || len(warnings) != 0 {
		t.Fatalf("got err %v, warnings %q; want neither", err, warnings)
	}
	if !slices.Equal(cfg.Settings, Defaults().Settings) {
		t.Errorf("got %+v, want the defaults", cfg.Settings)
	}
}

// If the $ or backtick refusal goes, or its words change, this goes red.
func TestDollarAndBacktickAreRefused(t *testing.T) {
	for content, want := range map[string]string{
		"board_dir = $HOME/b\n":  path + ":1: board_dir: $ and backticks are not expanded; write the value out",
		"agent_env = `whoami`\n": path + ":1: agent_env: $ and backticks are not expanded; write the value out",
	} {
		if _, _, err := Parse(path, []byte(content), "/home/u"); err == nil || err.Error() != want {
			t.Errorf("%q: got %v, want %s", content, err, want)
		}
	}
}

// If the key = value regex loosens or its message changes, this goes red.
func TestExpectedKeyValue(t *testing.T) {
	for _, content := range []string{"\n\nmerge agent\n", "\n\nMerge = agent\n", "\n\n= agent\n"} {
		_, _, err := Parse(path, []byte(content), "/home/u")
		if want := path + ":3: expected 'key = value'"; err == nil || err.Error() != want {
			t.Errorf("%q: got %v, want %s", content, err, want)
		}
	}
}

// If top_rung_rounds' test stops wrapping as bash 3.2's arithmetic does, one of these flips.
func TestTopRungRoundsWrapsAsBash(t *testing.T) {
	cfg, _, err := Parse(path, []byte("top_rung_rounds = 18446744073709551618\n"), "/home/u")
	if got, _ := cfg.Get("top_rung_rounds"); err != nil || got.Value != "18446744073709551618" {
		t.Errorf("2^64+2: got %+v, %v; want it to load", got, err)
	}
	_, _, err = Parse(path, []byte("top_rung_rounds = 9223372036854775808\n"), "/home/u")
	want := path + ":1: top_rung_rounds must be a whole number of 2 or more, not '9223372036854775808': " +
		"at 1, every findings round after the lead lifts a top-rung hold would hold it again"
	if err == nil || err.Error() != want {
		t.Errorf("2^63: got %v, want %s", err, want)
	}
}

// If a line rule drifts from load_config's (the # cut, blank lines, CRLF, a last line with no
// newline, a later line winning, ~ made home), the value or source here changes.
func TestLineRules(t *testing.T) {
	content := "  # only a comment\n\t\r\nmerge = human\r\nboard_dir\t=\t~/b # a comment\nrepos_dir = ~\nmerge = agent"
	cfg, warnings, err := Parse(path, []byte(content), "/home/u")
	if err != nil || len(warnings) != 0 {
		t.Fatalf("got err %v, warnings %q", err, warnings)
	}
	for _, want := range []Setting{
		{Name: "merge", Value: "agent", Source: path + ":6"},
		{Name: "board_dir", Value: "/home/u/b", Source: path + ":4"},
		{Name: "repos_dir", Value: "/home/u", Source: path + ":5"},
		{Name: "goal", Value: "off", Source: "default"},
	} {
		if got, _ := cfg.Get(want.Name); got != want {
			t.Errorf("got %+v, want %+v", got, want)
		}
	}
}

// If demote_kinds or agent_env split their lists differently from bash's read, the word the error
// names changes.
func TestListSplits(t *testing.T) {
	for content, want := range map[string]string{
		"demote_kinds = a,b,\n": path + ":1: demote_kinds: '' is not a finding kind; name kinds separated by commas, " +
			"each short kebab-case (32 characters at most), such as duplicate-code,efficiency, not 'a,b,'",
		"demote_kinds = a, b\n": path + ":1: demote_kinds: ' b' is not a finding kind; name kinds separated by commas, " +
			"each short kebab-case (32 characters at most), such as duplicate-code,efficiency, not 'a, b'",
		"agent_env = A \t b\n": path + ":1: agent_env: 'b' is not a variable name ([A-Z_][A-Z0-9_]*)",
		"agent_env = A,B\n":    path + ":1: agent_env: 'A,B' is not a variable name ([A-Z_][A-Z0-9_]*)",
	} {
		if _, _, err := Parse(path, []byte(content), "/home/u"); err == nil || err.Error() != want {
			t.Errorf("%q: got %v\nwant %s", content, err, want)
		}
	}
}

// If Defaults drifts from bin/swarm.sh's settings block, a no-file project gets another value.
func TestDefaults(t *testing.T) {
	want := map[string]string{
		"board_dir": "docs", "sign_commits": "false", "merge": "human", "stall_minutes": "30",
		"queue_minutes": "30", "sonnet_share": "0", "risky_effort": "xhigh", "escalate_after": "2",
		"step_up_findings": "3", "top_rung_rounds": "2", "goal": "off", "codex_minutes": "10",
		"lead": "off", "merge_admin": "off", "merge_protected": "off", "review_verify": "ci", "lead_epics": "off",
	}
	for _, s := range Defaults().Settings {
		if s.Value != want[s.Name] || s.Source != "default" {
			t.Errorf("%s: got %q from %s, want %q from default", s.Name, s.Value, s.Source, want[s.Name])
		}
	}
}
