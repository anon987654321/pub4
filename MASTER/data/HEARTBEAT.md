# HEARTBEAT

HEARTBEAT covers scheduled maintenance that is disabled by default but available through slash commands and environment flags when operators want periodic housekeeping.

Job definitions are in `data/heartbeat.yml`. Use `/dreams` to prune memory, `/self` or standing-order self_test for a self-scan, `/prune undo` to prune the undo stack, and `/snapshot` to snapshot artifacts. Enable the loop with `MASTER_LOOP=heartbeat` or `MASTER_HEARTBEAT=1`.