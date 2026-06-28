# HEARTBEAT

Schedule maintenance disabled. Jobs in `data/heartbeat.yml`. Use slash commands:

- `/dreams` — prune memory
- `/self` or standing-order self_test — self-scan
- `/prune undo` — prune undo stack
- `/snapshot` — snapshot artifacts

Enable loop: `MASTER_LOOP=heartbeat` or `MASTER_HEARTBEAT=1`.