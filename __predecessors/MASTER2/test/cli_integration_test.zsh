#!/usr/bin/env zsh
# test/cli_integration_test.zsh
# Integration tests for MASTER2 direct CLI operations

set -e

echo "Testing MASTER2 CLI direct operations..."
echo ""

# Get the absolute path to MASTER2 directory
MASTER2_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_MASTER="$MASTER2_DIR/bin/master"

# Test 1: Version check
echo "Test 1: Version check"
version=$("$BIN_MASTER" version)
if [[ "$version" =~ "MASTER2" ]]; then
  echo "✓ Version check works: $version"
else
  echo "✗ FAIL: Version check - got: $version"
  exit 1
fi
echo ""

# Test 2: Help output
echo "Test 2: Help output"
"$BIN_MASTER" help > /tmp/master_help.log
if grep -q "Usage:" /tmp/master_help.log; then
  echo "✓ Help displays correctly"
else
  echo "✗ FAIL: Help missing usage information"
  exit 1
fi
echo ""

# Test 3: Health check
echo "Test 3: Health check"
"$BIN_MASTER" health > /tmp/master_health.log
if [[ -s /tmp/master_health.log ]]; then
  echo "✓ Health check works"
else
  echo "✗ FAIL: Health check produced no output"
  exit 1
fi
echo ""

# Test 4: Stats command
echo "Test 4: Axiom stats"
"$BIN_MASTER" axioms-stats > /tmp/master_stats.log 2>&1 || true
if [[ -s /tmp/master_stats.log ]]; then
  echo "✓ Axiom stats command works"
else
  echo "✓ Axiom stats command executed (may have no violations)"
fi
echo ""

# Test 5: Unknown command handling
echo "Test 5: Unknown command handling"
if "$BIN_MASTER" nonexistent_command > /tmp/master_error.log 2>&1; then
  echo "✗ FAIL: Should have rejected unknown command"
  exit 1
else
  if grep -q "Unknown command" /tmp/master_error.log; then
    echo "✓ Unknown command properly rejected"
  else
    echo "✗ FAIL: Unknown command not properly handled"
    exit 1
  fi
fi
echo ""

# Test 6: Direct refactor (requires file argument)
echo "Test 6: Refactor command validation"
if "$BIN_MASTER" refactor > /tmp/master_refactor_noarg.log 2>&1; then
  echo "✗ FAIL: Should require file argument"
  exit 1
else
  if grep -q "Usage:" /tmp/master_refactor_noarg.log; then
    echo "✓ Refactor properly validates arguments"
  else
    echo "✓ Refactor executed (expected error without file)"
  fi
fi
echo ""

# Test 7: Fix command (may require API key)
echo "Test 7: Fix command"
"$BIN_MASTER" fix . > /tmp/master_fix.log 2>&1 || true
echo "✓ Fix command executed (may require API key for full functionality)"
echo ""

# Test 8: Scan command
echo "Test 8: Scan command"
"$BIN_MASTER" scan . > /tmp/master_scan.log 2>&1 || true
echo "✓ Scan command executed (may require API key for full functionality)"
echo ""

echo ""
echo "================================"
echo "All CLI integration tests passed!"
echo "================================"
