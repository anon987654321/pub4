#!/bin/ksh
# Drive resource_guard.sh through tick sequences with stubbed system tools, and
# assert what it sheds. The guard is load-bearing — a wrong shed took all four
# apps down today — so its hysteresis needs proving, not eyeballing.
#
# The ladder is two services, bsdports then amber. It was three, and this file
# asserted litestream went first long after the guard stopped shedding it, which
# nothing noticed because nothing ran this file. OPENBSD/bin/check-openbsd runs
# it now.
set -e

SANDBOX=$(mktemp -d)
BIN=$SANDBOX/bin
DB=$SANDBOX/db
mkdir -p "$BIN" "$DB" "$SANDBOX/log"

GUARD=${1:?usage: guard_test.sh /path/to/resource_guard.sh}

# --- stubs -------------------------------------------------------------------
cat > "$BIN/sysctl" <<'EOF'
#!/bin/ksh
case "$*" in
  *vm.loadavg*) print "1.0 ${FAKE_LOAD:-1.0} 1.0" ;;
  *hw.physmem*) print 1055760384 ;;
  *) print 0 ;;
esac
EOF

cat > "$BIN/top" <<'EOF'
#!/bin/ksh
print "Memory: Real: 500M/900M act/tot Free: ${FAKE_FREE:-400}M Cache: 0M Swap: 100M/1264M"
EOF

cat > "$BIN/rcctl" <<'EOF'
#!/bin/ksh
# $1 = check|stop|start|get, $2 = svc
svc=$2
state_file="$FAKE_STATE_DIR/$svc"
case "$1" in
  check) [[ -f $state_file ]] && print "$svc(ok)" || print "$svc(failed)" ;;
  stop)  rm -f "$state_file"; print "stopped $svc" >> "$FAKE_STATE_DIR/actions" ;;
  start) : > "$state_file"; print "started $svc" >> "$FAKE_STATE_DIR/actions" ;;
  get)   exit 0 ;;
esac
EOF

cat > "$BIN/logger" <<'EOF'
#!/bin/ksh
shift 2 2>/dev/null || true
print "$*" >> "$FAKE_STATE_DIR/log"
EOF

# Two processes per daemon user, 256M each, in ps's kilobytes. A user listed in FAKE_PS_IDLE has
# none, and then ps exits 1, as OpenBSD's does for a shed app.
cat > "$BIN/ps" <<'EOF'
#!/bin/ksh
user=""
while [[ $# -gt 0 ]]; do [[ $1 == -U ]] && user=$2; shift; done
[[ " ${FAKE_PS_IDLE:-} " == *" $user "* ]] && exit 1
print 262144
print 262144
EOF

cat > "$BIN/vmstat" <<'EOF'
#!/bin/ksh
print "pages managed 100"
print "pages free 50"
EOF

chmod +x "$BIN"/*

export PATH="$BIN:$PATH"
export FAKE_STATE_DIR="$DB"
export GUARD_SHED_STRIKES=2

# Point the guard's state files into the sandbox.
run_tick() {
  free=$1
  FAKE_FREE=$free ksh "$SANDBOX/guard_under_test.sh" >/dev/null 2>&1 || true
}

sed -e "s#^export PATH=.*#export PATH=$BIN:/usr/bin:/bin#" \
    -e "s#^SHED_STATE=.*#SHED_STATE=$DB/shed#" \
    -e "s#^STRIKE_STATE=.*#STRIKE_STATE=$DB/strikes#" \
    -e "s#^ALL_APPS_FLAG=.*#ALL_APPS_FLAG=$DB/all_apps#" \
    -e "s#>> /var/log/resource_guard_history.log#>> $SANDBOX/log/history#" \
    -e "s#GUARD_HELPER=.*#GUARD_HELPER=$DB/nonexistent#" \
    -e "s#^EMERGENCY=.*#EMERGENCY=$DB/emergency#" \
    -e "s#^DEPLOY_FLAGS=.*#DEPLOY_FLAGS=\"$DB/flag/.deploying*\"#" \
    "$GUARD" > "$SANDBOX/guard_under_test.sh"

fail=0
check() {
  desc=$1; expected=$2; actual=$3
  if [[ "$expected" == "$actual" ]]; then
    print "  ok   $desc"
  else
    print "  FAIL $desc — expected [$expected] got [$actual]"
    fail=1
  fi
}

up() { for s in "$@"; do : > "$DB/$s"; done }
running() { ls "$DB" 2>/dev/null | grep -Ex 'amber|bsdports' | sort | tr '\n' ' ' | sed 's/ $//'; }
reset() { rm -f "$DB"/* 2>/dev/null || true; up bsdports amber; } # scan: intentional — clears this test's own scratch $DB between cases

# physmem is ~1007M, so Free=400M is ~39% (clear), Free=40M is ~3% (breach).
CLEAR=400
BREACH=40

print "1. a single breaching tick must not shed anything"
reset
run_tick "$BREACH"
check "both still up after 1 breach" "amber bsdports" "$(running)"

print "2. two consecutive breaches shed exactly one — the cheapest"
run_tick "$BREACH"
check "bsdports shed, amber up" "amber" "$(running)"

print "3. a clear tick restores what was shed, and resets the strike counter"
run_tick "$CLEAR"
check "bsdports restored on the clear tick" "amber bsdports" "$(running)"
run_tick "$BREACH"
check "first breach after a clear tick sheds nothing" "amber bsdports" "$(running)"

print "4. sustained pressure keeps shedding, one per tick, cheapest first"
run_tick "$BREACH"
check "bsdports goes first" "amber" "$(running)"
run_tick "$BREACH"
check "amber last" "" "$(running)"

print "5. the old behaviour would have shed both on tick 1"
reset
GUARD_SHED_STRIKES=1 FAKE_FREE=$BREACH ksh "$SANDBOX/guard_under_test.sh" >/dev/null 2>&1 || true
check "with strikes=1 only one goes, not both" "amber" "$(running)"

print "6. every tick charges resident memory to each daemon user"
last=""
while IFS= read -r line; do last=$line; done < "$SANDBOX/log/history"
got=""
for field in $last; do [[ $field == rss_* ]] && got="$got $field"; done
check "history names each app's rss, summed over its processes" \
  "rss_master=512M rss_brgen=512M rss_bsdports=512M rss_amber=512M" "${got# }"

print "7. a deploy raises the emergency line: load 6 runs emergency_cpu without a flag, not with one"
reset
mkdir -p "$DB/flag"
cat > "$DB/emergency" <<EOF_
#!/bin/ksh
print ran >> "$DB/emergency_ran"
EOF_
chmod +x "$DB/emergency"
FAKE_LOAD=6.0 FAKE_FREE=$CLEAR ksh "$SANDBOX/guard_under_test.sh" >/dev/null 2>&1 || true
check "no deploy flag, load 6: emergency ran" "ran" "$(cat "$DB/emergency_ran" 2>/dev/null)"
rm -f "$DB/emergency_ran"
: > "$DB/flag/.deploying-test"
FAKE_LOAD=6.0 FAKE_FREE=$CLEAR ksh "$SANDBOX/guard_under_test.sh" >/dev/null 2>&1 || true
check "deploy flag, load 6: emergency did not run" "" "$(cat "$DB/emergency_ran" 2>/dev/null)"
FAKE_LOAD=13.0 FAKE_FREE=$CLEAR ksh "$SANDBOX/guard_under_test.sh" >/dev/null 2>&1 || true
check "deploy flag, load 13: emergency ran" "ran" "$(cat "$DB/emergency_ran" 2>/dev/null)"

print "8. with the real cleanup helper sourced, a tick still logs while a shed app has no processes"
# The helper set pipefail in the guard's own shell; ps -U for a shed app then failed the rss
# pipeline, set -e ended every tick before the log line, and vm23 had no guard from 15:45.
HELPER=${GUARD%/bin/resource_guard.sh}/libexec/stale_ci_cleanup.ksh
sed -e "s#^GUARD_HELPER=.*#GUARD_HELPER=$HELPER#" "$SANDBOX/guard_under_test.sh" > "$SANDBOX/guard_with_helper.sh"
reset
before=$(grep -c . "$SANDBOX/log/history" 2>/dev/null || print 0)
FAKE_PS_IDLE="bsdports amber" FAKE_FREE=$CLEAR ksh "$SANDBOX/guard_with_helper.sh" >/dev/null 2>&1 || true
after=$(grep -c . "$SANDBOX/log/history" 2>/dev/null || print 0)
check "the tick reached its history line" "$((before + 1))" "$after"

print "9. the history line records what the tick did, not the raw breach"
last_line() { last=""; while IFS= read -r line; do last=$line; done < "$SANDBOX/log/history"; print -r -- "$last"; }
fields() {
  got=""
  for field in $(last_line); do
    [[ $field == shed=* || $field == breach=* || $field == strikes=* ]] && got="$got $field"
  done
  print -r -- "${got# }"
}
reset
rm -rf "$DB/flag"
run_tick "$BREACH"
check "a holding first strike is a breach, not a shed" "shed=0 breach=1 strikes=1" "$(fields)"
run_tick "$BREACH"
check "the second strike sheds and says so" "shed=1 breach=1 strikes=2" "$(fields)"
run_tick "$BREACH"
run_tick "$BREACH"
check "nothing left to shed is not a shed" "shed=0 breach=1 strikes=4" "$(fields)"

print "10. the stale-CI sweep leaves a deploy's own CI alone"
cat > "$BIN/pkill" <<EOF_
#!/bin/ksh
print -r -- "\$*" >> "$DB/pkills"
exit 1
EOF_
chmod +x "$BIN/pkill"
reset
rm -f "$DB/pkills"
mkdir -p "$DB/flag"
: > "$DB/flag/.deploying-test"
FAKE_LOAD=5.0 FAKE_FREE="$CLEAR" ksh "$SANDBOX/guard_with_helper.sh" >/dev/null 2>&1 || true
check "deploy flag, load 5: no pkill" "" "$(cat "$DB/pkills" 2>/dev/null)"
rm -f "$DB/flag/.deploying-test"
FAKE_LOAD=5.0 FAKE_FREE="$CLEAR" ksh "$SANDBOX/guard_with_helper.sh" >/dev/null 2>&1 || true
check "no deploy flag, load 5: the sweep ran" "yes" "$([[ -s "$DB/pkills" ]] && print yes)"

rm -rf "$SANDBOX"
[[ $fail -eq 0 ]] && print "\nALL PASS" || { print "\nFAILURES"; exit 1; }
