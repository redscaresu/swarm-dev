import os, sys
from stall import *
events, mode, args = sys.argv[1], sys.argv[2], sys.argv[3:]
if mode == "story":
    rows = [l.split("\t") for l in os.environ["SWARM_STORY_ROWS"].splitlines() if l.count("\t") >= 2]
    print(story_for(args[0], rows) or "")
else:
    a = stall_age(last_seen(events), args[0], args[1], args[2:])
    print("" if a is None else a)
