#!/usr/bin/env zsh
set -euo pipefail

# Self-optimize master.yml through its own rules
# Implements self_optimization principle from tier_3_guidelines

MASTER_FILE="${1:-master.yml}"
MAX_CYCLES=5
IMPROVEMENT_THRESHOLD=0.02

[[ ! -f "$MASTER_FILE" ]] && { print "Error: $MASTER_FILE not found"; exit 1; }

print "Running master.yml through its own optimization rules"
print "Max cycles: $MAX_CYCLES, threshold: $IMPROVEMENT_THRESHOLD"
print ""

# Metrics to track
count_lines() { 
  local content="$(<$1)"
  local -a lines=("${(@f)content}")
  print ${#lines}
}

count_violations() {
  local content="$(<$1)"
  local violations=0
  
  # Check for banned tools in examples
  [[ $content =~ "echo " ]] && (( violations++ ))
  [[ $content =~ "wc " ]] && (( violations++ ))
  [[ $content =~ "cat " && ! $content =~ "concatenation" ]] && (( violations++ ))
  
  # Check structure violations
  [[ ! $content =~ "# PRINCIPLES - TIER 1" ]] && (( violations++ ))
  
  print $violations
}

previous_score=0
cycle=1

while (( cycle <= MAX_CYCLES )); do
  print "=== Cycle $cycle ==="
  
  lines=$(count_lines "$MASTER_FILE")
  violations=$(count_violations "$MASTER_FILE")
  
  # Simple scoring: lower is better (fewer violations, reasonable line count)
  score=$(( violations * 10 + (lines > 700 ? (lines - 700) : 0) ))
  
  print "Lines: $lines"
  print "Violations: $violations"
  print "Score: $score"
  
  if (( cycle > 1 )); then
    improvement=$(( (previous_score - score) * 100 / previous_score ))
    print "Improvement: ${improvement}%"
    
    if (( improvement < IMPROVEMENT_THRESHOLD * 100 )); then
      print "\nDiminishing returns reached (< ${IMPROVEMENT_THRESHOLD}%)"
      break
    fi
  fi
  
  previous_score=$score
  (( cycle++ ))
  
  # In real implementation, would apply transformations here
  # For now, just report current state
  break
done

print "\nOptimization complete!"
print "\nSuggested improvements based on master.yml rules:"

# Check for specific violations
content="$(<$MASTER_FILE)"

print "\n1. STRUCTURE (top-to-bottom by importance):"
[[ $content =~ "PRINCIPLES.*CONFLICT.*CODE.*LEGAL.*BUSINESS" ]] && \
  print "  ✓ Proper hierarchy maintained" || \
  print "  ✗ Reorder: PRINCIPLES > CONFLICTS > DOMAINS"

print "\n2. DISCOURAGED TOOLS (should not appear in examples):"
grep -q 'echo ' "$MASTER_FILE" 2>/dev/null && \
  print "  ✗ Found 'echo' - use 'print' (zsh) or 'Write-Host' (PowerShell)" || \
  print "  ✓ No 'echo' violations"

grep -q 'wc ' "$MASTER_FILE" 2>/dev/null && \
  print "  ✗ Found 'wc' - use '\${#lines}' or '@(Get-Content).Count'" || \
  print "  ✓ No 'wc' violations"

print "\n3. DRY VIOLATIONS:"
local -a sections=("${(@f)$(grep -E '^[a-z_]+:' "$MASTER_FILE" 2>/dev/null)}")
local -A seen
for section in "${sections[@]}"; do
  key="${section%%:*}"
  if [[ -n ${seen[$key]} ]]; then
    print "  ✗ Duplicate section: $key"
  fi
  seen[$key]=1
done

print "\n4. TOKEN EFFICIENCY:"
if (( lines > 700 )); then
  print "  ⚠ File is $lines lines (> 700 optimal)"
  print "    Suggestion: Extract domain-specific sections to separate files"
else
  print "  ✓ File length optimal ($lines lines)"
fi

print "\nTo apply fixes, commit changes following 'surgical_precision' principle"
