#!/bin/zsh
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH
S=/Users/mac/Music/dilla_sines
while true; do
  [[ -f $S/STOP ]] && break
  /opt/homebrew/bin/ruby $S/player.rb >> $S/play.log 2>&1
  [[ -f $S/STOP ]] && break
  sleep 1
done
