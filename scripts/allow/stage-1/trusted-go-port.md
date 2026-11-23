---
story: trusted-go-port
pr: 1169
kind: stage
---

# require_trusted runs on the Go, and loses Python's tracebacks

require_trusted (bin/lib/agents.sh) runs the binary's `_require-trusted` entry in place of the Python helper.
The exit codes and the die line stay the same.
Two fixtures made the Python raise an error it did not catch, so it exited 1 with a traceback on stderr.
The Go exits 1 there too and prints nothing, so swarm.sh's die line is all that is left on stderr (P14).
The fixtures are in tests/diff_fixtures_trust.sh.
The tracebacks are those of the diff-run job's python3, Ubuntu's 3.14, whose json module is under `/usr/lib/python3.14/`.
fx_trusted_deep masks the stack figure in the RecursionError line as `<n>`.

`projects` a list: the AttributeError's traceback goes.

## trusted_not_object stderr

```diff
-Traceback (most recent call last):
-  File "<tree>/bin/lib/require_trusted.py", line 10, in <module>
-    sys.exit(0 if any(projects.get(p, {}).get("hasTrustDialogAccepted") is True for p in paths) else 1)
-                  ^^^
-  File "<tree>/bin/lib/require_trusted.py", line 10, in <genexpr>
-    sys.exit(0 if any(projects.get(p, {}).get("hasTrustDialogAccepted") is True for p in paths) else 1)
-                      ^^^^^^^^^^^^
-AttributeError: 'list' object has no attribute 'get'
```

Arrays nested 200000 deep: the RecursionError's traceback goes.

## trusted_deep stderr

```diff
-Traceback (most recent call last):
-  File "<tree>/bin/lib/require_trusted.py", line 4, in <module>
-    projects = json.load(open(config)).get("projects", {})
-               ~~~~~~~~~^^^^^^^^^^^^^^
-  File "/usr/lib/python3.14/json/__init__.py", line 298, in load
-    return loads(fp.read(),
-        cls=cls, object_hook=object_hook,
-        parse_float=parse_float, parse_int=parse_int,
-        parse_constant=parse_constant, object_pairs_hook=object_pairs_hook, **kw)
-  File "/usr/lib/python3.14/json/__init__.py", line 352, in loads
-    return _default_decoder.decode(s)
-           ~~~~~~~~~~~~~~~~~~~~~~~^^^
-  File "/usr/lib/python3.14/json/decoder.py", line 345, in decode
-    obj, end = self.raw_decode(s, idx=_w(s, 0).end())
-               ~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^
-  File "/usr/lib/python3.14/json/decoder.py", line 361, in raw_decode
-    obj, end = self.scan_once(s, idx)
-               ~~~~~~~~~~~~~~^^^^^^^^
-RecursionError: Stack overflow (used <n> kB) while decoding a JSON array from a unicode string
```
