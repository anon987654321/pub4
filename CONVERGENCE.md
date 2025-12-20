# Convergence System

Auto-iterative code quality enforcement system for pub4 repository.

## Overview

The convergence system implements an assess → detect → fix → verify → repeat loop that automatically identifies and helps fix violations of design principles defined in `master.yml`.

## Components

### 1. Main Script: `converge.sh`
Zsh-based orchestration script that runs the convergence loop.

**Usage:**
```bash
./converge.sh                    # Run with defaults
./converge.sh --ci-mode          # CI mode (no fixes, fail on violations)
./converge.sh --dry-run          # Show what would be fixed
./converge.sh --no-fix           # Only detect violations
./converge.sh --max-iterations 5 # Limit iterations
```

### 2. Analyzers

#### Ruby Code Analyzer (`lib/converge/analyzer.rb`)
Analyzes Ruby files for:
- **File size**: Files > 200 lines
- **Method length**: Methods > 20 lines
- **Complexity**: Cyclomatic complexity > 10
- **Variable names**: Single-letter variables (except i,j,k in loops)
- **Duplication**: Code repeated 3+ times

**Usage:**
```bash
ruby lib/converge/analyzer.rb "rails/**/*.rb"
```

#### Shell Script Analyzer (`lib/converge/shell_analyzer.rb`)
Analyzes shell scripts for:
- **File size**: Files > 200 lines
- **Function length**: Functions > 20 lines
- **Banned tools**: python, bash, sed, awk, tr, wc, head, tail, cut, find, sudo
- **Shell type**: Must use zsh, not bash
- **Parameter expansion**: Suggests zsh alternatives to banned tools

**Usage:**
```bash
ruby lib/converge/shell_analyzer.rb "openbsd/**/*.sh"
```

### 3. Reporter (`lib/converge/reporter.rb`)
Merges violation reports and formats output.

**Usage:**
```bash
ruby lib/converge/reporter.rb violations1.json violations2.json
```

### 4. Fixer (`lib/converge/fixer.rb`)
Attempts automatic fixes for violations. Currently supports:
- Shebang replacement (bash → zsh)
- Tool replacement suggestions
- Manual fix logging for complex violations

**Usage:**
```bash
ruby lib/converge/fixer.rb violations.json
ruby lib/converge/fixer.rb violations.json --dry-run
```

## Configuration

Configuration is in `master.yml`:

```yaml
convergence:
  enabled: true
  max_iterations: 10
  auto_fix: true
  stop_on_error: false
  targets:
    - "rails/**/*.rb"
    - "rails/**/*.sh"
    - "openbsd/**/*.sh"

constraints:
  thresholds:
    max_method_lines: 20
    max_file_lines: 200
    max_complexity: 10
    duplication_trigger: 3
  
  banned_tools: [python, bash, sed, awk, wc, head, tail, find, sudo]
  allowed_tools: [ruby, zsh, git, grep, cat, sort]
```

## State Tracking

The system tracks convergence state in `.convergence_state.json`:

```json
{
  "timestamp": "2025-12-20T01:38:24Z",
  "iterations": 5,
  "violations": 24,
  "converged": false,
  "auto_fix": true,
  "ci_mode": false
}
```

## GitHub Actions Integration

The system runs automatically on push/PR via `.github/workflows/converge.yml`:

```yaml
name: Auto-Converge
on: [push, pull_request]
jobs:
  converge:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
      - run: ./converge.sh --ci-mode
```

## Testing

For environments without zsh, use the test script:

```bash
./test_convergence.sh
```

This runs the analyzers and reports violation counts.

## Current Status

As of 2025-12-20:
- ✅ Analyzers implemented and working
- ✅ Main convergence loop created
- ✅ GitHub Actions workflow configured
- ✅ Major functions refactored in openbsd.sh
- ✅ Banned tool usage eliminated
- ⚠️ 24 violations remaining (mostly large files/functions in configuration scripts)

## Violations by File

### openbsd/openbsd.sh (15 violations)
- File size: 1035 lines (threshold: 200)
- Multiple functions > 20 lines (configuration-heavy)

### rails/_batch_generate.sh (9 violations)
- File size: 449 lines (threshold: 200)
- Multiple functions > 20 lines (Rails generation logic)

## Design Principles Enforced

From `master.yml`:
- **small_functions**: Methods under 20 lines
- **file_size_lines**: Files under 200 lines
- **dry**: Don't repeat yourself
- **meaningful_names**: Descriptive variable names
- **max_complexity**: Cyclomatic complexity ≤ 10
- **consolidate**: Prefer fewer, well-organized files

## Future Enhancements

1. **Smart refactoring**: Automatically extract long methods
2. **Module splitting**: Auto-split large files by responsibility
3. **Duplication extraction**: Identify and extract common patterns
4. **Complexity reduction**: Automated guard clause extraction
5. **Name suggestions**: AI-powered variable renaming
6. **Progressive thresholds**: Start strict, relax for legacy code

## Philosophy

The convergence system embodies these principles:
- **Automated quality**: Machines enforce consistency
- **Iterative improvement**: Small steps toward better code
- **Fail-safe defaults**: Don't break working code
- **Evidence-based**: Measure violations objectively
- **Self-applying**: The system improves itself
