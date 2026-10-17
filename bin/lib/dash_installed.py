import json, os, sys
path, plugin, home, project, inst = sys.argv[1:]
real = os.path.realpath
try:
    entries = [(f"{e['scope']}:{e.get('projectPath', '')}", e) for e in json.load(open(path))["plugins"][plugin]]
    if inst:
        found = [(k, e) for k, e in entries if k == inst]
    else:
        def rank(ke):
            where = ke[1].get("projectPath")
            return 1 if not where else 0 if real(where) == real(project) else 2
        found = sorted(((k, e) for k, e in entries if real(e["installPath"]) == real(home)), key=rank)
    if found:
        print(found[0][0], found[0][1]["installPath"], found[0][1]["version"], sep="\t")
except Exception:
    pass
