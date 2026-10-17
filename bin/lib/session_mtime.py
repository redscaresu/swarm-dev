import os, sys
from panes import *; from report import *
sid = session_id(sys.argv[1], sys.argv[2])
path = session_log(sys.argv[3], sid) if sid else ""
try:
    print(int(os.path.getmtime(path)) if path else "")
except OSError:   # removed since the glob: no sign
    print("")
