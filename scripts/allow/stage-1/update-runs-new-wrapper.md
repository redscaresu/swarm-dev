---
story: update-runs-new-wrapper
pr: 1147
kind: stage
---

# usage names update's run of the new version's swarm.sh version

#1147 made `swarm.sh update` run the newly installed copy's `swarm.sh version` once, within 5 minutes, after `claude plugin update`.
Its line in swarm.sh's usage now says so.
The fixture is in tests/diff_fixtures_cmds.sh.

## usage stdout

```diff
 #   swarm.sh version                                        the installed version, and a warning when a newer one is out
-#   swarm.sh update                                         update the plugin to the newest version
+#   swarm.sh update                                         update the plugin to the newest version, then run that version's swarm.sh version once, within 5 minutes
```
