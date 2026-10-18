# Predictions, a flow section (flow_report.py gives its globals): how the planner's labels held, from
# .swarm/dataset.jsonl (swarm.sh dataset writes it) over the stories merged in the window (with --epic,
# that epic's). One TSV row per planner model ("-" for a story dataset names none for): its stories, the
# precision and recall of easy against was_easy, and the median and mean of diff_lines less
# estimate_lines (above 0, the story came out bigger than planned). A ratio with nothing to count is "".
import json, os, statistics, sys

path = os.path.join(os.path.dirname(agents), "dataset.jsonl")
if not os.path.exists(path):
    print("no .swarm/dataset.jsonl: run swarm.sh dataset first")
    sys.exit()

def ratio(hit, of):
    return f"{hit / of:.2f}" if of else ""

by = {}
for line in open(path, errors="ignore"):
    d = json.loads(line)
    if since <= d["merged_at"][:10] <= until and (not epic or d["epic"] == epic):
        by.setdefault(d["inputs"]["planner_model"] or "-", []).append(d)

print("planner\tstories\teasy_precision\teasy_recall\testimate_err_median\testimate_err_mean")
for model, ds in sorted(by.items()):
    pairs = [(d["inputs"]["easy"], d["was_easy"]) for d in ds if None not in (d["inputs"]["easy"], d["was_easy"])]
    hits = sum(1 for e, w in pairs if e and w)
    errs = [d["results"]["diff_lines"] - d["inputs"]["estimate_lines"] for d in ds
            if None not in (d["results"]["diff_lines"], d["inputs"]["estimate_lines"])]
    print("\t".join([model, str(len(ds)), ratio(hits, sum(1 for e, _ in pairs if e)), ratio(hits, sum(1 for _, w in pairs if w)),
                     f"{statistics.median(errs):g}" if errs else "", f"{statistics.mean(errs):.1f}" if errs else ""]))
