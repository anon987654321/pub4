#!/bin/zsh
# The beep, in its own supervised process, forever.
#
# It is not a gap-filler. It is the signal that the pipeline is alive and it is
# required to be continuous, so it shares nothing with the generator or the
# player and neither can take it down. Eight variants, rotated, so a long
# session does not hear one sound at three-second intervals.
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH
S=/Users/mac/Music/dilla_sines
i=0
while true; do
  [[ -f $S/STOP_BEEP ]] && break
  t=$(/opt/homebrew/bin/ruby -e 'a=Dir["/Users/mac/Music/dilla_sines/ticks/*.wav"].sort; puts a.empty? ? "/Users/mac/Music/dilla_sines/tick.wav" : a[ARGV[0].to_i % a.size]' $i)
  /usr/bin/afplay "$t" 2>/dev/null
  i=$((i+1))
  sleep 3
done
