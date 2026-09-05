#!/bin/zsh
# The broadcast. Lives in the repo, not in a scratchpad -- the scratchpad ate
# the first version of this file mid-session.
#
# Three sets in rotation. Pass one as an argument to hold it:
#   live/broadcast.sh                       # all three, in turn
#   live/broadcast.sh ambient_pads          # that one, all night
#
# scan: intentional — no strict mode. This is an all-night rotation: set -e
# would end the broadcast on the first render that exits non-zero instead of
# moving to the next set, and set -u breaks the documented no-argument form,
# where $1 is unset by design. Same argument as redo_nine.sh.
export PATH=/opt/homebrew/bin:/usr/bin:/bin
cd "${0:h}/.." || exit 1

# Beats twice as often as pads: a pad block is 180 seconds against their 96, so
# an even rotation would spend half the night on the quiet one.
sets=(sampled_based_beats chord_based_beats sampled_based_beats ambient_pads)
[[ -n "$1" ]] && sets=("$1")

i=1
while true; do
  set_name=${sets[$i]}
  /opt/homebrew/bin/ruby "live/${set_name}.als.rb"
  i=$(( i % ${#sets[@]} + 1 ))
  sleep 0.2
done
