#!/usr/bin/env zsh
# watch_tests.sh — auto-run MASTER tests on lib/ or test/ file change.
# Uses zsh-native patterns (ZSH_NATIVE_PATTERNS.md): no grep/awk/sed forks.
#
# Usage: zsh sh/watch_tests.sh [test_file]
# Default test: test/test_agent.rb

set -euo pipefail

MASTER_ROOT=${0:a:h:h:h}/MASTER
TEST_FILE=${1:-test/test_agent.rb}
WATCH_DIRS=( lib test )
DELAY=2
LAST_RUN=0

cd "$MASTER_ROOT"
print "watch_tests: watching ${(j:, :)WATCH_DIRS} → $TEST_FILE"
print "watch_tests: press Ctrl-C to stop"
print ""

run_tests() {
  print "\n$(date '+%H:%M:%S') running $TEST_FILE"
  bundle exec ruby "$TEST_FILE" 2>&1
  print ""
}

# Run once immediately
run_tests

while true; do
  sleep "$DELAY"

  NOW=$(date +%s)

  # zsh-native: find .rb files modified in last DELAY+1 seconds
  # Glob qualifier: N=nullglob, m=modification, s=seconds, -N = less than N seconds ago
  typeset -a changed
  changed=()
  for dir in $WATCH_DIRS; do
    [[ -d $dir ]] || continue
    # (Nms-3) = modified less than 3 seconds ago, N = no error if empty
    changed+=( $dir/**/*.rb(Nms-3) )
  done

  # zsh-native unique (no sort|uniq fork)
  typeset -aU unique_changed=( $changed )

  if (( ${#unique_changed} > 0 )); then
    # zsh-native: strip MASTER_ROOT prefix for display
    typeset -a display
    display=( ${unique_changed//$MASTER_ROOT\//} )
    print "changed: ${(j:, :)display}"
    run_tests
  fi
done
