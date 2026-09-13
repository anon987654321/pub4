#!/bin/zsh
# The broadcast. Lives in the repo, not in a scratchpad -- the scratchpad ate
# the first version of this file mid-session.
#
# Three sets in rotation. Pass one as an argument to hold it:
#   live/broadcast.sh                       # all three, in turn
#   live/broadcast.sh ambient_pads          # that one, all night
#
# Hard cuts between sets. A set that crossfades into the next is CATALOGUE.md
# item 11, a set of its own, not this script's job.
#
# scan: intentional — no strict mode. This is an all-night rotation: set -e
# would end the broadcast on the first render that exits non-zero instead of
# moving to the next set, and set -u breaks the documented no-argument form,
# where $1 is unset by design.
export PATH=/opt/homebrew/bin:/usr/bin:/bin
export RBENV_VERSION=3.4.9
cd "${0:h}/.." || exit 1

# Beats twice as often as pads: a pad block is 180 seconds against their 96, so
# an even rotation would spend half the night on the quiet one.
sets=(sampled_based_beats chord_based_beats sampled_based_beats ambient_pads)
[[ -n "$1" ]] && sets=("$1")

# A misspelt set would otherwise fail every 0.2 seconds all night.
for set_name in $sets; do
  if [[ ! -f "live/${set_name}.als.rb" ]]; then
    print -u2 "broadcast: no set named ${set_name} -- the sets are live/*.als.rb"
    exit 1
  fi
done

i=1
while true; do
  set_name=${sets[$i]}
  ruby "live/${set_name}.als.rb"
  i=$(( i % ${#sets[@]} + 1 ))
  sleep 0.2
done
