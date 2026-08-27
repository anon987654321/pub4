#!/bin/zsh
# A watchdog over the beep, because the beep stopping is treated as a fault.
#
# The heartbeat has been killed three times tonight -- by a pkill aimed at
# something else, and by process-group cleanup when a tool call timed out. It is
# the signal the pipeline is alive and it is not allowed to stop, so something
# has to notice when it does. This checks every five seconds and restarts it.
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH
S=/Users/mac/Music/dilla_sines
while true; do
  [[ -f $S/STOP_BEEP ]] && break
  if ! pgrep -f "heartbeat.sh" > /dev/null; then
    setsid nohup $S/heartbeat.sh > $S/heartbeat.out 2>&1 < /dev/null &
    echo "$(date '+%H:%M:%S') restarted heartbeat" >> $S/watchdog.log
  fi
  sleep 5
done
