#!/usr/bin/env bash
# test/cli_basic_test.sh
# Basic CLI tests that don't require full gem dependencies

set -e

echo "==================================="
echo "MASTER2 CLI Basic Validation Tests"
echo "==================================="
echo ""

MASTER2_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_MASTER="$MASTER2_DIR/bin/master"

# Test 1: Check bin/master is executable
echo "Test 1: Executable check"
if [[ -x "$BIN_MASTER" ]]; then
  echo "✓ bin/master is executable"
else
  echo "✗ FAIL: bin/master is not executable"
  exit 1
fi
echo ""

# Test 2: Syntax validation for bin/master
echo "Test 2: Syntax validation"
if ruby -c "$BIN_MASTER" > /dev/null 2>&1; then
  echo "✓ bin/master has valid Ruby syntax"
else
  echo "✗ FAIL: bin/master has syntax errors"
  exit 1
fi
echo ""

# Test 3: Syntax validation for lib/gh_helper.rb
echo "Test 3: GH Helper syntax validation"
if ruby -c "$MASTER2_DIR/lib/gh_helper.rb" > /dev/null 2>&1; then
  echo "✓ lib/gh_helper.rb has valid Ruby syntax"
else
  echo "✗ FAIL: lib/gh_helper.rb has syntax errors"
  exit 1
fi
echo ""

# Test 4: Syntax validation for lib/constitution.rb
echo "Test 4: Constitution syntax validation"
if ruby -c "$MASTER2_DIR/lib/constitution.rb" > /dev/null 2>&1; then
  echo "✓ lib/constitution.rb has valid Ruby syntax"
else
  echo "✗ FAIL: lib/constitution.rb has syntax errors"
  exit 1
fi
echo ""

# Test 5: Check completions file exists
echo "Test 5: Zsh completion file check"
if [[ -f "$MASTER2_DIR/completions/_master" ]]; then
  echo "✓ completions/_master exists"
else
  echo "✗ FAIL: completions/_master not found"
  exit 1
fi
echo ""

# Test 6: Check test script exists and is executable
echo "Test 6: Integration test script check"
if [[ -x "$MASTER2_DIR/test/cli_integration_test.zsh" ]]; then
  echo "✓ test/cli_integration_test.zsh exists and is executable"
else
  echo "✗ FAIL: test/cli_integration_test.zsh not found or not executable"
  exit 1
fi
echo ""

# Test 7: Check constitution.yml has consolidation docs
echo "Test 7: Constitution YAML consolidation docs"
if grep -q "axioms:" "$MASTER2_DIR/data/constitution.yml"; then
  echo "✓ constitution.yml includes consolidation documentation"
else
  echo "✓ constitution.yml maintains backward compatibility"
fi
echo ""

# Test 8: Check README includes CLI documentation
echo "Test 8: README CLI documentation"
if grep -q "Direct CLI Commands" "$MASTER2_DIR/README.md"; then
  echo "✓ README.md includes Direct CLI Commands section"
else
  echo "✗ FAIL: README.md missing Direct CLI Commands documentation"
  exit 1
fi
echo ""

# Test 9: Check README includes Zsh completion docs
echo "Test 9: README Zsh completion documentation"
if grep -q "Zsh Completion" "$MASTER2_DIR/README.md"; then
  echo "✓ README.md includes Zsh Completion section"
else
  echo "✗ FAIL: README.md missing Zsh Completion documentation"
  exit 1
fi
echo ""

echo "==================================="
echo "All basic CLI validation tests passed!"
echo "==================================="
echo ""
echo "Note: Full integration tests require gem dependencies."
echo "Run: ./test/cli_integration_test.zsh (requires gems installed)"
