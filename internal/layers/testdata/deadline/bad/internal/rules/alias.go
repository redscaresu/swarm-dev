package rules

import run "os/exec"

// aliased starts gh through an alias of os/exec.
var aliased = run.Command("gh", "pr", "list")
