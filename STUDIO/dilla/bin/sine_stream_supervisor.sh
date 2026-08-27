#!/bin/zsh
# Supervisor: if the stream dies for any reason it comes straight back. The one
# rule this stream has is that it does not stop.
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH
cd /Users/mac/Documents/GitHub/pub4/STUDIO/dilla
S=/Users/mac/Music/dilla_sines
while true; do
  [[ -f $S/STOP ]] && break
  /opt/homebrew/bin/ruby $S/sine_stream.rb >> $S/stream.log 2>&1
  [[ -f $S/STOP ]] && break
  echo "--- stream exited, restarting ---" >> $S/stream.log
  sleep 1
done
