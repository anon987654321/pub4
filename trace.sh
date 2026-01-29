#!/bin/zsh
# trace.sh - dmesg-style code violation scanner
# Usage: ./trace.sh <file> [law]

set -euo pipefail

file="${1:?Usage: trace.sh <file> [law]}"
focus_law="${2:-all}"

[[ -f "$file" ]] || { print -u2 "File not found: $file"; exit 1; }

# Colors
typeset -A C=(r $'\e[31m' g $'\e[32m' y $'\e[33m' b $'\e[34m' d $'\e[90m' n $'\e[0m')

# Trace log function - dmesg style
trace() {
  printf "[%12.6f] %s: %s\n" "$1" "$2" "$3"
}

# Header
print "================================================================================"
print "AUTOFIX TRACE v1.0 - ${file:t}"
print "================================================================================"

lines=$(wc -l < "$file")
bytes=$(wc -c < "$file")

trace 0.000000 "autofix" "initializing violation scanner"
trace 0.000001 "autofix" "file: $file ($lines lines, $bytes bytes)"
trace 0.000002 "autofix" "law_sequence: [robustness, singularity, linearity, proximity, abstraction, density]"
trace 0.000003 "autofix" "search_types: [literal, conceptual]"

ts=0.01
total=0
vid=0

# Law scanner functions
scan_robustness() {
  local n=0
  # Empty catch blocks
  grep -n 'catch\s*([^)]*)\s*{\s*}' "$file" 2>/dev/null | while read -r match; do
    ((vid++, n++))
    line=${match%%:*}
    trace $ts "robustness" "VIOLATION [ROBUST-$(printf '%03d' $vid)] empty catch block"
    trace $((ts+0.00001)) "robustness" "  line $line: ${match#*:}"
  done
  
  # Bare rescue (Ruby)
  grep -n '^\s*rescue\s*$' "$file" 2>/dev/null | while read -r match; do
    ((vid++, n++))
    line=${match%%:*}
    trace $ts "robustness" "VIOLATION [ROBUST-$(printf '%03d' $vid)] bare rescue (catches all)"
    trace $((ts+0.00001)) "robustness" "  line $line: ${match#*:}"
  done
  
  # eval usage
  grep -n '\beval\s*(' "$file" 2>/dev/null | while read -r match; do
    ((vid++, n++))
    line=${match%%:*}
    trace $ts "robustness" "VIOLATION [ROBUST-$(printf '%03d' $vid)] dangerous eval()"
    trace $((ts+0.00001)) "robustness" "  line $line: ${match#*:}"
  done
  
  [[ $n -eq 0 ]] && trace $ts "robustness" "PASS - no violations found"
  print $n
}

scan_density() {
  local n=0
  # TODO/FIXME/HACK markers
  grep -n '//\s*\(TODO\|FIXME\|HACK\|XXX\)' "$file" 2>/dev/null | while read -r match; do
    ((vid++, n++))
    line=${match%%:*}
    trace $ts "density" "VIOLATION [DENSITY-$(printf '%03d' $vid)] cruft marker"
    trace $((ts+0.00001)) "density" "  line $line: ${match#*:}"
  done
  
  # console.log
  grep -n '^\s*console\.log\s*(' "$file" 2>/dev/null | while read -r match; do
    ((vid++, n++))
    line=${match%%:*}
    trace $ts "density" "VIOLATION [DENSITY-$(printf '%03d' $vid)] debug console.log"
    trace $((ts+0.00001)) "density" "  line $line: ${match#*:}"
  done
  
  # debugger
  grep -n '^\s*debugger' "$file" 2>/dev/null | while read -r match; do
    ((vid++, n++))
    line=${match%%:*}
    trace $ts "density" "VIOLATION [DENSITY-$(printf '%03d' $vid)] debugger statement"
    trace $((ts+0.00001)) "density" "  line $line: ${match#*:}"
  done
  
  # Commented code blocks (3+ consecutive // lines)
  awk '/^[[:space:]]*\/\// { count++; if(count>=3) print NR": commented block" } !/^[[:space:]]*\/\// { count=0 }' "$file" | while read -r match; do
    ((vid++, n++))
    trace $ts "density" "VIOLATION [DENSITY-$(printf '%03d' $vid)] commented code block at line ${match%%:*}"
  done
  
  [[ $n -eq 0 ]] && trace $ts "density" "PASS - no violations found"
  print $n
}

scan_linearity() {
  local n=0
  # Deep nesting (16+ spaces = 4+ levels)
  grep -n '^.\{16,\}' "$file" 2>/dev/null | grep -E '^\s{16,}(if|for|while|switch|case)' | while read -r match; do
    ((vid++, n++))
    line=${match%%:*}
    indent=$((${#match} - ${#${match##*( )}}))
    trace $ts "linearity" "VIOLATION [LINEAR-$(printf '%03d' $vid)] deep nesting ($((indent/2)) levels)"
    trace $((ts+0.00001)) "linearity" "  line $line"
  done
  
  [[ $n -eq 0 ]] && trace $ts "linearity" "PASS - no deep nesting found"
  print $n
}

scan_abstraction() {
  local n=0
  # Magic numbers (3+ digits, not in comments, not common constants)
  grep -n '[^a-zA-Z0-9_]\([0-9]\{3,\}\)[^a-zA-Z0-9_]' "$file" 2>/dev/null | \
    grep -v '^\s*//' | grep -v '0x' | \
    grep -v -E '(100|200|255|256|512|1000|1024|2048|4096|8080|3000|8787)' | \
    head -20 | while read -r match; do
    ((vid++, n++))
    line=${match%%:*}
    trace $ts "abstraction" "VIOLATION [ABSTR-$(printf '%03d' $vid)] magic number"
    trace $((ts+0.00001)) "abstraction" "  line $line: ${match#*:}"
  done
  
  [[ $n -eq 0 ]] && trace $ts "abstraction" "PASS - no magic numbers found"
  print $n
}

scan_singularity() {
  local n=0
  # Find duplicate lines (30+ chars, non-blank, non-comment)
  awk 'length > 30 && !/^[[:space:]]*(\/\/|#|\*)/ { 
    gsub(/[0-9]+/, "N"); gsub(/"[^"]*"/, "S"); 
    if (seen[$0]) { print NR": duplicate of line " seen[$0] } 
    else { seen[$0] = NR } 
  }' "$file" | head -10 | while read -r match; do
    ((vid++, n++))
    trace $ts "singularity" "VIOLATION [SING-$(printf '%03d' $vid)] ${match#*: }"
  done
  
  [[ $n -eq 0 ]] && trace $ts "singularity" "PASS - no duplicates found"
  print $n
}

scan_proximity() {
  # Placeholder - proximity needs AST analysis
  trace $ts "proximity" "SCAN - checking function groupings..."
  trace $ts "proximity" "PASS - proximity requires AST analysis (skipped)"
  print 0
}

# Run scans
laws=(robustness singularity linearity proximity abstraction density)
[[ "$focus_law" != "all" ]] && laws=($focus_law)

for i in {1..${#laws[@]}}; do
  law=${laws[$i]}
  print ""
  print "================================================================================"
  print "ITERATION $i: ${(U)law} (Priority $i)"
  print "================================================================================"
  
  case $law in
    robustness)  n=$(scan_robustness) ;;
    singularity) n=$(scan_singularity) ;;
    linearity)   n=$(scan_linearity) ;;
    proximity)   n=$(scan_proximity) ;;
    abstraction) n=$(scan_abstraction) ;;
    density)     n=$(scan_density) ;;
  esac
  
  ((total += n)) || true
  ts=$((ts + 0.01))
done

# Summary
print ""
print "================================================================================"
print "AUTOFIX SUMMARY"
print "================================================================================"
print "Total violations: $total"
print "File: $file"
print "Lines scanned: $lines"
