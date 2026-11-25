package config

// key is one setting: its name in the config file and its default, as bin/swarm.sh's settings
// block sets them.
type key struct {
	name string
	def  string
}

// keys is every setting, in CONFIG_KEYS' order. Each sits on a line of its own, so a check can read
// the names with a line regex.
var keys = []key{
	{name: "board_dir", def: "docs"},
	{name: "repos_dir", def: ""},
	{name: "base_branches", def: ""},
	{name: "sign_commits", def: "false"},
	{name: "merge", def: "human"},
	{name: "stall_minutes", def: "30"},
	{name: "queue_minutes", def: "30"},
	{name: "sonnet_share", def: "0"},
	{name: "risky_effort", def: "xhigh"},
	{name: "escalate_after", def: "2"},
	{name: "escalate_ladder", def: ""},
	{name: "step_up_findings", def: "3"},
	{name: "top_rung_rounds", def: "2"},
	{name: "builder_subagent_model", def: ""},
	{name: "goal", def: "off"},
	{name: "codex_minutes", def: "10"},
	{name: "fallback_reviewer", def: ""},
	{name: "lead", def: "off"},
	{name: "merge_admin", def: "off"},
	{name: "merge_protected", def: "off"},
	{name: "review_verify", def: "ci"},
	{name: "demote_kinds", def: ""},
	{name: "lead_epics", def: "off"},
	{name: "commit_trailers", def: ""},
	{name: "agent_env", def: ""},
	{name: "usage_warn_percent", def: ""},
}

// removedKeys are the keys an older swarm-dev read, in REMOVED_KEYS' order: a config that sets one
// still loads, with a warning, whatever its value.
var removedKeys = []string{"pr_per", "finished", "review_bot", "keep_panes"}

// silentKey was removed with lessons; a config that sets it loads with no warning, whatever its value.
const silentKey = "lessons_file"

// Keys returns every setting's name, in CONFIG_KEYS' order.
func Keys() []string {
	names := make([]string, len(keys))
	for i, k := range keys {
		names[i] = k.name
	}
	return names
}

// RemovedKeys returns the removed keys, in REMOVED_KEYS' order.
func RemovedKeys() []string {
	return append([]string(nil), removedKeys...)
}
