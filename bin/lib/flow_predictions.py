# Predictions, a flow section (flow_report.py gives its globals): how well the planner's labels held,
# from swarm.sh dataset's .swarm/dataset.jsonl over the stories merged in the window (by merged_at's
# local day). One TSV row per planner model (the story's inputs.planner_model, - when dataset found
# none), then `all`: its stories; easy_precision, of the stories labelled easy, the share that
# was_easy; easy_recall, of the stories that was_easy, the share labelled easy (a story whose easy or
# was_easy is null is left out of both, and each prints as hits/of share, - when of is 0); estimated,
# the stories with both estimate_lines and diff_lines; and the median and mean of their size-estimate
# error, |diff_lines - estimate_lines|. With no dataset file, a line saying to run swarm.sh dataset.
# --epic does not narrow it: a dataset line holds no epic.
import collections, json, os, statistics, sys
from report import local_day, merge_time
path = os.path.join(os.path.dirname(os.path.dirname(findings)), ".swarm", "dataset.jsonl")
if not os.path.exists(path):
    print("no .swarm/dataset.jsonl: run swarm.sh dataset to score the planner's easy labels and size estimates")
    sys.exit(0)

def count(v):
    # A line count as dataset writes it: an int, never a bool (JSON true is no count).
    return v if isinstance(v, int) and not isinstance(v, bool) else None

by_model = collections.defaultdict(list)
for line in open(path, encoding="utf-8", errors="replace"):
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if not isinstance(d, dict) or not isinstance(d.get("inputs"), dict) or not isinstance(d.get("results"), dict):
        continue   # a line from before dataset wrote inputs and results
    merged = merge_time(d["results"].get("merged_at"))
    if merged and since <= str(local_day(merged)) <= until:
        by_model[d["inputs"].get("planner_model") or "-"].append(d)

def share(hits, of):
    return f"{hits}/{of} {100 * hits / of:.0f}%" if of else "-"

def row(model, ds):
    labelled = [(d["inputs"].get("easy"), d.get("was_easy")) for d in ds]
    labelled = [(e, w) for e, w in labelled if isinstance(e, bool) and isinstance(w, bool)]
    errors = [abs(n - e) for d in ds
              for e, n in [(count(d["inputs"].get("estimate_lines")), count(d["results"].get("diff_lines")))]
              if e is not None and n is not None]
    return "\t".join([model, str(len(ds)),
                      share(sum(1 for e, w in labelled if e and w), sum(1 for e, _ in labelled if e)),
                      share(sum(1 for e, w in labelled if e and w), sum(1 for _, w in labelled if w)),
                      str(len(errors)),
                      f"{statistics.median(errors):.0f}" if errors else "-",
                      f"{statistics.mean(errors):.0f}" if errors else "-"])

if not by_model:
    print("no story in .swarm/dataset.jsonl merged in the window")
    sys.exit(0)
print("planner_model\tstories\teasy_precision\teasy_recall\testimated\test_err_median\test_err_mean")
for model in sorted(by_model):
    print(row(model, by_model[model]))
print(row("all", [d for ds in by_model.values() for d in ds]))
