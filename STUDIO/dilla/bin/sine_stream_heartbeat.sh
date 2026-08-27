#!/bin/zsh
# The beep. It runs in its own process, supervised, forever.
#
# It was a gap-filler at first and it is not that any more -- it is the signal
# that the pipeline is alive and working, and it is required to be continuous.
# Nothing about the generator or the player can stop it, because it shares
# nothing with them.
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH
S=/Users/mac/Music/dilla_sines
while true; do
  [[ -f $S/STOP_BEEP ]] && break
  /usr/bin/afplay $S/tick.wav 2>/dev/null
  sleep 3
done
