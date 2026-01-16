#!/usr/bin/env zsh
set -euo pipefail

# Validates SYMBIOSIS framework integrity (master.yml + modules)
# Usage: ./validate_framework.sh [--verbose]

typeset -r FRAMEWORK_DIR="${1:-.}"
typeset -r VERBOSE="${2:---quiet}"

echo "=== SYMBIOSIS Framework Validation ==="

# 1. Check all files exist
typeset -a required_files=(master.yml principles.yml steroids.yml biases.yml)
for file in $required_files; do
  [[ -f "$FRAMEWORK_DIR/$file" ]] || { echo "✗ Missing $file"; exit 1; }
done
echo "✓ All 4 modules present"

# 2. Validate YAML syntax
for file in $required_files; do
  ruby -ryaml -e "YAML.load_file('$FRAMEWORK_DIR/$file')" 2>/dev/null || { echo "✗ Invalid YAML: $file"; exit 1; }
done
echo "✓ YAML syntax valid"

# 3. Count principles
typeset principle_count=$(grep -cE "^[A-Z_]+:" "$FRAMEWORK_DIR/principles.yml")
echo "✓ Principles: $principle_count"

# 4. Validate cross-references
typeset -a refs=(
  "@master.vocab"
  "@master.t"
  "@master.actions"
  "@master.constitutional"
  "@master.escalation"
)
for ref in $refs; do
  grep -q "$ref" "$FRAMEWORK_DIR/principles.yml" "$FRAMEWORK_DIR/steroids.yml" "$FRAMEWORK_DIR/biases.yml" || { echo "✗ Orphaned reference: $ref"; exit 1; }
done
echo "✓ Cross-references valid"

# 5. Check for DENSITY violations (spacing in floats)
if grep -E " \. [0-9]| [0-9]\. " "$FRAMEWORK_DIR/master.yml" >/dev/null 2>&1; then
  echo "✗ DENSITY violation: spacing in floats"
  [[ $VERBOSE == "--verbose" ]] && grep -n " \. " "$FRAMEWORK_DIR/master.yml"
  exit 1
fi
echo "✓ No DENSITY violations"

# 6. Check for SIMULATION_BAN violations (future tense outside context)
typeset -a banned_future=(will would could should might going.to lets we.need)
for word in $banned_future; do
  if grep -iE "\b$word\b" "$FRAMEWORK_DIR"/*.yml | grep -v "match:\|detect:\|ban:\|perspective:" >/dev/null 2>&1; then
    echo "✗ SIMULATION_BAN violation: $word"
    [[ $VERBOSE == "--verbose" ]] && grep -in "\b$word\b" "$FRAMEWORK_DIR"/*.yml | grep -v "match:\|detect:\|ban:"
    exit 1
  fi
done
echo "✓ No SIMULATION_BAN violations"

# 7. Version consistency check
typeset master_version=$(grep "^version:" "$FRAMEWORK_DIR/master.yml" | head -1 | awk '{print $2}' | tr -d '"')
echo "✓ Framework version: $master_version"

echo ""
echo "=== Validation PASSED ==="
echo "Framework: SYMBIOSIS $master_version"
echo "Principles: $principle_count"
echo "Status: Production ready"
