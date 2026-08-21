#!/bin/ksh
# Drive resource_guard.sh through tick sequences with stubbed system tools, and
# assert what it sheds. The guard is load-bearing — a wrong shed took all four
# apps down today — so its hysteresis needs proving, not eyeballing.
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
running() { ls "$DB" 2>/dev/null | grep -Ex 'amber|bsdports|litestream' | sort | tr '\n' ' ' | sed 's/ $//'; }
reset() { rm -f "$DB"/* 2>/dev/null || true; up litestream bsdports amber; }

# physmem is ~1007M, so Free=400M is ~39% (clear), Free=40M is ~3% (breach).
CLEAR=400
BREACH=40

print "1. a single breaching tick must not shed anything"
reset
run_tick "$BREACH"
check "all three still up after 1 breach" "amber bsdports litestream" "$(running)"

print "2. two consecutive breaches shed exactly one — the cheapest"
run_tick "$BREACH"
check "litestream shed, others up" "amber bsdports" "$(running)"

print "3. a clear tick restores what was shed, and resets the strike counter"
run_tick "$CLEAR"
check "litestream restored on the clear tick" "amber bsdports litestream" "$(running)"
run_tick "$BREACH"
check "first breach after a clear tick sheds nothing" "amber bsdports litestream" "$(running)"

print "4. sustained pressure keeps shedding, one per tick, cheapest first"
run_tick "$BREACH"
check "litestream goes first" "amber bsdports" "$(running)"
run_tick "$BREACH"
check "bsdports next" "amber" "$(running)"
run_tick "$BREACH"
check "amber last" "" "$(running)"

print "5. the old behaviour would have shed all three on tick 1"
reset
GUARD_SHED_STRIKES=1 FAKE_FREE=$BREACH ksh "$SANDBOX/guard_under_test.sh" >/dev/null 2>&1 || true
check "with strikes=1 only one goes, not all three" "amber bsdports" "$(running)"

rm -rf "$SANDBOX"
[[ $fail -eq 0 ]] && print "\nALL PASS" || { print "\nFAILURES"; exit 1; }
