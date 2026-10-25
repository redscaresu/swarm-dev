# Predictions, a flow section (flow_report.py gives its globals): how well the planner's labels held,
# from swarm.sh dataset's .swarm/dataset.jsonl over the stories merged in the window (by merged_at's
# local day) and, with --epic, in that epic (the epic: of the story text the line holds). One TSV row per planner model (the story's inputs.planner_model, - when dataset found
# none), then `all`: its stories; easy_precision, of the stories labelled easy, the share that
# was_easy; easy_recall, of the stories that was_easy, the share labelled easy (a story whose easy or
# was_easy is null is left out of both, and each prints as hits/of share, - when of is 0); estimated,
# the stories with both estimate_lines and diff_lines; and the median and mean of their size-estimate
# error, |diff_lines - estimate_lines|. Last, a line counting the lines it could not score (not JSON, or
# no inputs and results), when any. With no dataset file, a line saying to run swarm.sh dataset.
import collections, json, os, statistics, sys
from report import local_day, merge_time
from touches_rows import front_text
path = os.path.join(os.path.dirname(os.path.dirname(findings)), ".swarm", "dataset.jsonl")
if not os.path.exists(path):
    print("no .swarm/dataset.jsonl: run swarm.sh dataset to score the planner's easy labels and size estimates")
    sys.exit(0)

def count(v):
    # A line count as dataset writes it: an int, never a bool (JSON true is no count).
    return v if isinstance(v, int) and not isinstance(v, bool) else None

def epic_of(d):
    text = d["inputs"].get("text")
    return front_text(text).get("epic", "").strip() if isinstance(text, str) else ""

by_model, lines, skipped = collections.defaultdict(list), 0, 0
for line in open(path, encoding="utf-8", errors="replace"):
    if not line.strip():
        continue
    lines += 1
    try:
        d = json.loads(line)
    except ValueError:
        d = None
    if not isinstance(d, dict) or not isinstance(d.get("inputs"), dict) or not isinstance(d.get("results"), dict):
        skipped += 1   # not JSON, or a line from before dataset wrote inputs and results
        continue
    merged = merge_time(d["results"].get("merged_at"))
    if merged and since <= str(local_day(merged)) <= until and (not epic or epic_of(d) == epic):
        by_model[d["inputs"].get("planner_model") or "-"].append(d)

def say_skipped():
    if skipped:
        print(f"{skipped} of {lines} lines in .swarm/dataset.jsonl left out: not JSON, or no inputs and results")

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
    print("no story in .swarm/dataset.jsonl merged in the window" + (f" in epic {epic}" if epic else ""))
    say_skipped()
    sys.exit(0)
print("planner_model\tstories\teasy_precision\teasy_recall\testimated\test_err_median\test_err_mean")
for model in sorted(by_model):
    print(row(model, by_model[model]))
print(row("all", [d for ds in by_model.values() for d in ds]))
say_skipped()
