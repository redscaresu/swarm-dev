---
status: active
---

# Split bin/swarm.sh by command group before safer-faster-swarm builds on it

Every other safer-faster-swarm story touches bin/swarm.sh (6929 lines, 19 Python heredocs), and 55% of story PRs needed main merged in. This epic moves the code without changing it, so the rest of safer-faster-swarm builds on small files. It is its own epic so that safer-faster-swarm's dependency chains stay at most 3 deep.

**Done when:**
- The Python heredocs live in bin/lib/*.py and the bash in bin/lib/<group>.sh, with no file over 1500 lines, and the whole-line check shows nothing was lost or duplicated.
- Every test passes, and each test that reads swarm.sh's text also reads bin/lib.
- AGENTS.md's shellcheck, py_compile and layout lines cover bin/lib, and safer-faster-swarm is set active.

**Your part:** none.
