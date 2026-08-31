#!/bin/zsh
# The broadcast. Lives in the repo, not in a scratchpad -- the scratchpad ate
# the first version of this file mid-session.
export PATH=/opt/homebrew/bin:/usr/bin:/bin
cd "${0:h}/.." || exit 1
while true; do
  /opt/homebrew/bin/ruby live/synth.rb
  sleep 0.2
done
