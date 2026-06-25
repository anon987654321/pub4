# HEARTBEAT

Schedule-based maintenance is disabled. Heartbeat jobs live in `data/heartbeat.yml`.

Use slash commands instead:

- `/dreams` — prune memory (was @hourly prune_memory)
- `/self` or standing-order self_test — periodic self-scan
- `/prune undo` — prune undo stack
- `/snapshot` — write snapshot artifacts

Enable the heartbeat loop with `MASTER_LOOP=heartbeat` or `MASTER_HEARTBEAT=1`.