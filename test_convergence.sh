#!/usr/bin/env bash
# Test script for convergence analyzers (bash-compatible)
# Use this when zsh is not available

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib/converge"

echo "=== Testing Convergence Analyzers ==="
echo

# Test Ruby analyzer
echo "Testing Ruby analyzer..."
ruby "${LIB_DIR}/analyzer.rb" "rails/**/*.rb" "openbsd/**/*.rb" 2>/dev/null | head -20 || echo "No Ruby files to analyze"
echo

# Test Shell analyzer
echo "Testing Shell analyzer..."
ruby "${LIB_DIR}/shell_analyzer.rb" "openbsd/openbsd.sh" "rails/_batch_generate.sh" 2>/dev/null | jq '.summary' || {
  echo "Running without jq:"
  ruby "${LIB_DIR}/shell_analyzer.rb" "openbsd/openbsd.sh" "rails/_batch_generate.sh" 2>/dev/null | grep -A5 '"summary"'
}
echo

echo "=== Summary ==="
echo "Analyzing openbsd/openbsd.sh..."
violations_openbsd=$(ruby "${LIB_DIR}/shell_analyzer.rb" "openbsd/openbsd.sh" 2>/dev/null | grep -c '"type":' || echo "0")
echo "  Violations: $violations_openbsd"

echo "Analyzing rails/_batch_generate.sh..."
violations_rails=$(ruby "${LIB_DIR}/shell_analyzer.rb" "rails/_batch_generate.sh" 2>/dev/null | grep -c '"type":' || echo "0")
echo "  Violations: $violations_rails"

total=$((violations_openbsd + violations_rails))
echo
echo "Total violations: $total"

if [ "$total" -gt 0 ]; then
  echo "❌ Violations found - convergence needed"
  exit 1
else
  echo "✓ No violations - converged!"
  exit 0
fi
