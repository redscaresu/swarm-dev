import json, os, sys
root, config, in_git = sys.argv[1], sys.argv[2], sys.argv[3] == "git"
try:
    projects = json.load(open(config)).get("projects", {})
except (OSError, ValueError):
    sys.exit(0)
paths = [root]
while not in_git and os.path.dirname(paths[-1]) != paths[-1]:
    paths.append(os.path.dirname(paths[-1]))
sys.exit(0 if any(projects.get(p, {}).get("hasTrustDialogAccepted") is True for p in paths) else 1)
