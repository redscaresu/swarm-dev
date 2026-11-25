// Package config reads a project's .claude/swarm/config as bin/swarm.sh's load_config reads it:
// `key = value` lines, parsed and never sourced, with the same keys, defaults, rules and messages.
// It reads no file: the caller reads it, and takes Defaults when there is no regular file to read.
package config

import (
	"errors"
	"fmt"
	"regexp"
	"slices"
	"strconv"
	"strings"
)

// defaultSource is a setting's Source when no line of the file set it.
const defaultSource = "default"

// The patterns load_config matches, written as its [[ =~ ]] tests write them. Go's [[:space:]] is
// the C locale's: space, \t, \n, \v, \f and \r.
const (
	keyValuePattern     = `^[[:space:]]*([a-z_]+)[[:space:]]*=[[:space:]]*(.*[^[:space:]])?[[:space:]]*$`
	branchesPattern     = `^[A-Za-z0-9._/[:space:]-]*$`
	positivePattern     = `^[1-9][0-9]*$`
	nonNegativePattern  = `^(0|[1-9][0-9]*)$`
	ladderPattern       = `^([a-z0-9.-]+(,[a-z0-9.-]+)*)?$`
	modelPattern        = `^[A-Za-z0-9._-]*(\[1m\])?$`
	findingKindPattern  = `^[a-z0-9]+(-[a-z0-9]+)*$`
	trailerPattern      = `[A-Za-z][A-Za-z0-9-]*: [^;]*[^;[:space:]]`
	trailersPattern     = `^` + trailerPattern + `([[:space:]]*;[[:space:]]*` + trailerPattern + `)*$`
	variableNamePattern = `^[A-Z_][A-Z0-9_]*$`
)

var (
	keyValueRE     = regexp.MustCompile(keyValuePattern)
	branchesRE     = regexp.MustCompile(branchesPattern)
	positiveRE     = regexp.MustCompile(positivePattern)
	nonNegativeRE  = regexp.MustCompile(nonNegativePattern)
	ladderRE       = regexp.MustCompile(ladderPattern)
	modelRE        = regexp.MustCompile(modelPattern)
	findingKindRE  = regexp.MustCompile(findingKindPattern)
	trailersRE     = regexp.MustCompile(trailersPattern)
	variableNameRE = regexp.MustCompile(variableNamePattern)
)

// findingKindMax is the most characters a finding kind may have, as FINDING_KIND_MAX sets it.
const findingKindMax = 32

// percentMaxDigits and percentMax bound usage_warn_percent.
const (
	percentMaxDigits = 3
	percentMax       = 100
)

// topRungMin is the least top_rung_rounds may be.
const topRungMin = 2

// Setting is one key's value and where it came from: "<path>:<n>" for the line that set it, or
// "default".
type Setting struct {
	Name   string
	Value  string
	Source string
}

// Config is every key's Setting, in CONFIG_KEYS' order.
type Config struct {
	Settings []Setting
}

// Get returns the Setting for name, and false when name is no key.
func (c Config) Get(name string) (Setting, bool) {
	for _, s := range c.Settings {
		if s.Name == name {
			return s, true
		}
	}
	return Setting{}, false
}

// set gives the key name its value from the line at where. name is always a key: check refuses
// any other.
func (c *Config) set(name, value, where string) {
	for i := range c.Settings {
		if c.Settings[i].Name == name {
			c.Settings[i].Value, c.Settings[i].Source = value, where
		}
	}
}

// Defaults returns every key at its default, as load_config leaves them with no config file.
func Defaults() Config {
	settings := make([]Setting, len(keys))
	for i, k := range keys {
		settings[i] = Setting{Name: k.name, Value: k.def, Source: defaultSource}
	}
	return Config{Settings: settings}
}

// Parse reads content, the text of the config file at path, as load_config reads it, with home as
// $HOME for a leading ~ in board_dir and repos_dir. It returns each key's Setting, the warnings
// in the order load_config prints them, each as it prints it, and the first error, whose text is
// die's message without the `swarm: ` that die adds. On an error the Config is the zero Config:
// load_config stops the script there, after the warnings before it.
func Parse(path string, content []byte, home string) (Config, []string, error) {
	cfg := Defaults()
	var warnings []string
	for i, line := range lines(content) {
		where := path + ":" + strconv.Itoa(i+1)
		line, _, _ = strings.Cut(line, "#")
		if isBlank(line) {
			continue
		}
		m := keyValueRE.FindStringSubmatch(line)
		if m == nil {
			return Config{}, warnings, errors.New(where + ": expected 'key = value'")
		}
		name, value := m[1], m[2]
		if name == silentKey {
			continue
		}
		if slices.Contains(removedKeys, name) {
			warnings = append(warnings, "swarm: warning: "+where+": "+name+" was removed and is ignored; delete the line")
			continue
		}
		if strings.ContainsAny(value, "$`") {
			return Config{}, warnings, errors.New(where + ": " + name + ": $ and backticks are not expanded; write the value out")
		}
		value, msg := check(name, value, home)
		if msg != "" {
			return Config{}, warnings, errors.New(where + ": " + msg)
		}
		cfg.set(name, value, where)
	}
	return cfg, warnings, nil
}

// lines splits content as `while IFS= read -r line || [[ -n "${line}" ]]` reads it: at each
// newline, with a last line that has no newline read too when it is not empty. bash 3.2's read
// ends a line's text at its first NUL byte, so each line is cut there. (bash 5 drops each NUL and
// keeps the rest; the plugin runs on macOS's bash 3.2.)
func lines(content []byte) []string {
	parts := strings.Split(string(content), "\n")
	for i, p := range parts {
		parts[i], _, _ = strings.Cut(p, "\x00")
	}
	if last := len(parts) - 1; parts[last] == "" {
		parts = parts[:last]
	}
	return parts
}

// isBlank reports whether line is only C-locale whitespace, as ^[[:space:]]*$ matches it.
func isBlank(line string) bool {
	return strings.Trim(line, " \t\n\v\f\r") == ""
}

// check applies load_config's case arm for name to value. It returns the value to store (board_dir
// and repos_dir with a leading ~ made home), and the message after `<where>: ` when the arm
// refuses it, or "" when it passes. A name no arm takes is an unknown key.
func check(name, value, home string) (string, string) {
	bad := func(rule string) string { return fmt.Sprintf("%s must be %s, not '%s'", name, rule, value) }
	switch name {
	case "board_dir", "repos_dir":
		if value == "" {
			return value, name + " is empty"
		}
		// init writes board_dir into quoted strings in CI's gate and the pre-commit hook.
		if name == "board_dir" && strings.ContainsAny(value, `"\`) {
			return value, `board_dir: " and \ are refused; name a plain path`
		}
		if value == "~" || strings.HasPrefix(value, "~/") {
			value = home + value[1:]
		}
	case "base_branches":
		if !branchesRE.MatchString(value) {
			return value, bad("branch names separated by spaces, such as dev main")
		}
	case "sign_commits":
		if value != "true" && value != "false" {
			return value, bad("true or false")
		}
	case "merge":
		if value != "human" && value != "agent" {
			return value, bad("human or agent")
		}
	case "stall_minutes", "queue_minutes", "codex_minutes", "step_up_findings":
		if !positiveRE.MatchString(value) {
			return value, bad("a positive whole number")
		}
	case "top_rung_rounds":
		// 1 would hold the first findings round after the lead's reset too, so no findings ever
		// reach the builder.
		if !positiveRE.MatchString(value) || bashInt(value) < topRungMin {
			return value, bad("a whole number of 2 or more") +
				": at 1, every findings round after the lead lifts a top-rung hold would hold it again"
		}
	case "sonnet_share", "escalate_after":
		if !nonNegativeRE.MatchString(value) {
			return value, bad("a non-negative whole number")
		}
	case "risky_effort":
		if value != "xhigh" && value != "high" {
			return value, bad("xhigh or high")
		}
	case "escalate_ladder":
		// Its models are checked outside load_config, once the ladder's models are known.
		if !ladderRE.MatchString(value) {
			return value, bad("models separated by commas, such as sonnet,opus,fable")
		}
	case "builder_subagent_model", "fallback_reviewer":
		if !modelRE.MatchString(value) {
			return value, bad("a model name such as haiku")
		}
	case "goal":
		if value != "off" && !positiveRE.MatchString(value) {
			return value, bad("off or a positive whole number of turns")
		}
	case "lead":
		if value != "off" && value != "session" {
			return value, bad("off or session")
		}
	case "merge_admin", "merge_protected":
		if value != "off" && value != "on" {
			return value, bad("off or on")
		}
	case "review_verify":
		if value != "ci" && value != "full" {
			return value, bad("ci or full")
		}
	case "demote_kinds":
		return value, checkKinds(value)
	case "lead_epics":
		if value != "off" && value != "on" {
			return value, bad("off or on")
		}
	case "commit_trailers":
		if value != "" && !trailersRE.MatchString(value) {
			return value, bad("trailers such as Co-Authored-By: Name <email>, ; between several") +
				" (a # starts a comment, so no trailer can hold one)"
		}
	case "usage_warn_percent":
		if value != "" && !isPercent(value) {
			return value, bad("a whole number from 1 to 100, or empty for off")
		}
	case "agent_env":
		// Reserved names are refused outside load_config, once they are known.
		return value, checkNames(value)
	default:
		return value, fmt.Sprintf("unknown key '%s' (known: %s)", name, strings.Join(Keys(), " "))
	}
	return value, ""
}

// checkKinds refuses a demote_kinds value unless each of its comma-separated kinds is a finding
// kind as log-finding takes it. It splits as `IFS=, read -r -a` does, with the empty kind after a
// trailing comma that load_config adds back: spaces stay inside a kind.
func checkKinds(value string) string {
	if value == "" {
		return ""
	}
	for _, w := range strings.Split(value, ",") {
		if !findingKindRE.MatchString(w) || len(w) > findingKindMax {
			return fmt.Sprintf("demote_kinds: '%s' is not a finding kind; name kinds separated by commas, "+
				"each short kebab-case (%d characters at most), such as duplicate-code,efficiency, not '%s'",
				w, findingKindMax, value)
		}
	}
	return ""
}

// checkNames refuses an agent_env value unless each of its words is a variable name. It splits as
// `read -r -a` does with the default IFS: at runs of spaces, tabs and newlines.
func checkNames(value string) string {
	words := strings.FieldsFunc(value, func(r rune) bool { return r == ' ' || r == '\t' || r == '\n' })
	for _, w := range words {
		if !variableNameRE.MatchString(w) {
			return fmt.Sprintf("agent_env: '%s' is not a variable name ([A-Z_][A-Z0-9_]*)", w)
		}
	}
	return ""
}

// isPercent reports whether value is a whole number from 1 to 100, as usage_warn_percent's arm
// tests it: digits with no leading 0, at most three of them, then -le 100.
func isPercent(value string) bool {
	return positiveRE.MatchString(value) && len(value) <= percentMaxDigits && bashInt(value) <= percentMax
}

// bashInt is the decimal digits as bash's arithmetic reads them: into a 64-bit signed integer that
// wraps past 2^64, with no overflow check. So 18446744073709551618 is 2, and 9223372036854775808
// is negative.
func bashInt(digits string) int64 {
	var v uint64
	for i := 0; i < len(digits); i++ {
		v = v*10 + uint64(digits[i]-'0')
	}
	return int64(v)
}
