import collections, datetime, os, sys
from report import *
meta = {f[0]: f[1:] for f in (l.split("\t") for l in os.environ["SWARM_META"].splitlines()) if len(f) == 6}

NO_PR = ("", "", "", "", "")

def parsed(prs):
    # The (url, state, mergedAt, createdAt, main_merges) of each PR in the meta column; a stub may
    # leave out the last three.
    return [tuple((p.split(" ") + [""] * 4)[:5]) for p in prs.split(",") if " " in p]

def pr_of(prs, pulls):
    # The parsed PR of a build, or NO_PR: see outcomes_report. pulls is the first python's column: "-"
    # for no log.
    prs = parsed(prs)
    if pulls == "-":
        return prs[0] if len(prs) == 1 else NO_PR
    keyed = {pr_key(p[0]): p for p in prs}
    return next((keyed[pr_key(u)] for u in reversed(pulls.split()) if pr_key(u) in keyed), NO_PR)

def minutes(start, end):
    # Whole minutes from one UTC time to a later one; empty when either is empty or does not parse, or
    # end comes first (a retry started after the PR it took over was created).
    try:
        t = lambda s: datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
        d = t(end) - t(start)
    except ValueError:
        return ""
    return str(round(d / 60)) if d >= 0 else ""

rows = []
for line in os.environ["SWARM_ROWS"].splitlines():
    f = line.split("\t")
    kind, risk, prs, story_epic, asked = meta.get(f[1], ("", "", "", "", ""))
    rows.append((f, kind, risk, story_epic, asked, prs) + tuple(pr_of(prs, f[12])))
# Each finding goes to the latest build on its PR that started on or before the finding (both are
# local dates), so a PR two builds share counts each finding once.
found = [collections.Counter() for _ in rows]
for day, _, pr, _, outcome, reviewer in finding_rows(sys.argv[1]):
    on = [i for i, r in enumerate(rows) if r[6] and pr_key(r[6]) == pr_key(pr) and r[0][0] <= day]
    if on:
        found[on[-1]][(outcome, reviewer)] += 1

def by(c, outcome):
    return " ".join(f"{who}:{n}" for (o, who), n in sorted(c.items()) if o == outcome)

# Columns are only ever appended, never inserted or reordered: review-yield and flow read them by name,
# and a saved report or a script that cuts by position still lines up with a new one.
print("date\tslug\tkind\trisk\trole\tmodel\teffort\tcost_usd\ttokens\ttells_findings\ttells_nudge\ttells_resume\tcloses\tfindings_fixed\tpr\tpr_state\tattempts"
      "\tstarted\ttokens_input\ttokens_cache_write\ttokens_cache_read\ttokens_output\tclose_cause"
      "\tescalate_at\tdialog_at\tdialog\tescalated_at\treset_at\tdrop_at"
      "\tepic\tmerged_at\tstory_merged\tfindings_declined\tfindings_fixed_by\tfindings_declined_by"
      "\tpr_created_at\tstart_to_pr_min\tpr_to_merge_min\tmain_merges")
for (f, kind, risk, story_epic, asked, prs, pr, state, merged, created, main_merges), c in zip(rows, found):
    day, slug, role, model, effort, cost, tokens, tf, tn, tr, closes, attempts = f[:12]
    # Unknown (empty) unless gh answered for a story it could read: then true when any PR of its head merged.
    story_merged = ("true" if any(p[1] == "MERGED" for p in parsed(prs)) else "false") if asked else ""
    fixed, declined = (sum(n for (o, _), n in c.items() if o == k) for k in ("fixed", "declined"))
    merged = merged if asked and state == "MERGED" else ""
    print("\t".join([day, slug, kind, risk, role, model, effort, cost, tokens, tf, tn, tr, closes,
                     str(fixed), pr, state, attempts] + f[13:]
                     + [story_epic, merged, story_merged, str(declined), by(c, "fixed"), by(c, "declined"),
                        created, minutes(f[13], created), minutes(created, merged), main_merges]))
