"""events_outcome — read events.tsv's outcome column (row[4]), which may end in a key=value tail.

append_event (bin/lib/agents.sh) writes the outcome, then SEP and the fields, space-separated, when it
has any. It strips SEP from the outcome first, so the first SEP in the column starts the tail. Rows
written before the tail existed have none and read back whole.
  outcome(row) -> the outcome text without the tail (row[4] for a row with none; '' for a short row).
  fields(row)  -> the tail's fields as a dict ({} for a row with none); a later key wins.
SEP must equal agents.sh's EVENT_SEP, and outcome() its EVENT_OUTCOME_AWK; tests/events_test.sh pins both.
"""

SEP = " ~~ "


def _split(row):
    col = row[4] if len(row) > 4 else ""
    i = col.find(SEP)
    return (col, "") if i < 0 else (col[:i], col[i + len(SEP):])


def outcome(row):
    return _split(row)[0]


def fields(row):
    out = {}
    for pair in _split(row)[1].split(" "):
        key, eq, value = pair.partition("=")
        if eq and key:
            out[key] = value
    return out
