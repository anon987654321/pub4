#!/bin/zsh
# demo.mp3, rebuilt from the livestream as it accumulates.
#
# The demo is not a second render path -- that one drifted within an hour and was
# mastering a different chain than the speakers were playing. This is the stream
# itself, joined and encoded, so the file and the sound can never disagree.
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH
S=/Users/mac/Music/dilla_sines
while true; do
  [[ -f $S/STOP ]] && break
  /opt/homebrew/bin/ruby $S/demo_from_stream.rb >> $S/demo_daemon.log 2>&1
  sleep 45
done
