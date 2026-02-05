# Principle Enforcement System

The MASTER system includes comprehensive tooling to enforce the 43 principles at multiple levels: development, commit time, and CI/CD.

## Table of Contents

- [Overview](#overview)
- [Enforcement Mechanisms](#enforcement-mechanisms)
- [Git Hooks](#git-hooks)
- [Validation Tools](#validation-tools)
- [Port Consistency Checker](#port-consistency-checker)
- [CI/CD Integration](#cicd-integration)
- [Auto-Fix Capabilities](#auto-fix-capabilities)
- [Configuration](#configuration)

## Overview

Principle enforcement operates at three levels:

1. **Development Time**: IDE integration, linters, real-time feedback
2. **Commit Time**: Git hooks that prevent bad commits
3. **CI/CD Time**: Pipeline checks that gate deployments

All enforcement is configurable via `lib/config/principle_enforcement.yml`.

## Enforcement Mechanisms

### Literal Violation Detection

Pattern-based detection using regular expressions:

```ruby
# From lib/violations.rb
MASTER::Violations.check_literal(code)
```

Detects:
- Method chains (Law of Demeter): `user.account.subscription.plan`
- Long methods (Small Functions): Methods over 20 lines
- Magic numbers (DRY): Hardcoded numeric literals
- Deep nesting (KISS): More than 3 nesting levels
- God classes (Single Responsibility): Classes with 10+ public methods

### Conceptual Violation Detection

LLM-based semantic analysis for subtle violations:

```ruby
MASTER::Violations.check_conceptual(code, principles)
```

Detects:
- Hidden coupling between modules
- Abstraction leaks
- Unclear naming
- Architectural violations
- Design pattern misuse

### Dual Detection Strategy

Both methods run in parallel for comprehensive coverage:

```ruby
def check_file(path)
  code = File.read(path)
  
  # Fast literal checks
  literal_violations = MASTER::Violations.check_literal(code)
  
  # Deep conceptual checks (when needed)
  if literal_violations.empty? && deep_check?
    conceptual_violations = MASTER::Violations.check_conceptual(code)
  end
  
  literal_violations + conceptual_violations
end
```

## Git Hooks

Pre-commit hooks prevent principle violations from entering the repository.

### Installation

Install hooks with:

```bash
bin/install-hooks
```

This enables the pre-commit hook at `.git/hooks/pre-commit`.

### Pre-Commit Hook Behavior

The hook runs automatically on `git commit`:

```bash
$ git commit -m "Add feature"
Running principle enforcement...
Checking 3 staged Ruby files...
✓ All validations passed
[main abc123] Add feature
```

If violations are found:

```bash
$ git commit -m "Add feature"
Running principle enforcement...
Checking 5 staged Ruby files...

Violations found in lib/user.rb:
  [high] Single Responsibility: Class has 15 public methods
  [medium] Law of Demeter: user.account.subscription.plan.price

❌ Commit rejected: Fix violations before committing

To bypass this check temporarily, use:
  git commit --no-verify
```

### Hook Implementation

The pre-commit hook at `.git/hooks/pre-commit`:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../lib/master'

puts "Running principle enforcement..."

# Get staged files
staged_files = `git diff --cached --name-only --diff-filter=ACM`.split("\n")
ruby_files = staged_files.select { |f| f.end_with?('.rb') }

if ruby_files.empty?
  puts "No Ruby files staged. Skipping checks."
  exit 0
end

violations = []

# Check each file
ruby_files.each do |file|
  next unless File.exist?(file)
  
  code = File.read(file)
  file_violations = MASTER::Violations.check_literal(code)
  
  if file_violations.any?
    violations << { file: file, violations: file_violations }
  end
end

# Report and exit
if violations.any?
  puts "\nViolations found:\n"
  
  violations.each do |item|
    puts "\n#{item[:file]}:"
    item[:violations].each do |v|
      puts "  [#{v[:severity]}] #{v[:principle]}"
      puts "    #{v[:suggestion]}" if v[:suggestion]
    end
  end
  
  puts "\n❌ Commit rejected"
  puts "\nTo bypass: git commit --no-verify"
  exit 1
else
  puts "✓ All validations passed"
  exit 0
end
```

### Bypassing Hooks

Temporarily skip checks when necessary:

```bash
git commit --no-verify -m "WIP: debugging"
```

**Warning**: Use sparingly. Bypassed commits still run in CI.

### Disabling Hooks

Remove or make non-executable:

```bash
chmod -x .git/hooks/pre-commit
```

Or uninstall completely:

```bash
rm .git/hooks/pre-commit
```

## Validation Tools

### bin/validate_principles

Comprehensive validation tool for principle enforcement.

#### Basic Usage

```bash
# Check all Ruby files in lib/
bin/validate_principles

# Check specific file
bin/validate_principles lib/user.rb

# Check multiple files
bin/validate_principles lib/user.rb lib/order.rb

# Verbose output
bin/validate_principles --verbose

# Show violations with fix suggestions
bin/validate_principles --fix
```

#### Output Format

Standard run:

```bash
$ bin/validate_principles
============================================================
               Validating 45 files against principles              
============================================================

.............................................

============================================================
                    Validation Summary                     
============================================================

Files checked: 45
Clean files: 43
Files with violations: 2

Violations by severity:
  High: 3
  Medium: 5

Total violations: 8

⚠ Validation passed with warnings
```

Verbose mode:

```bash
$ bin/validate_principles --verbose
============================================================
               Validating 45 files against principles              
============================================================

lib/user.rb
  [high] Single Responsibility
    Pattern: Class has 15 public methods
    Suggestion: Extract concerns into focused classes
  [medium] Law of Demeter
    Pattern: user.account.subscription.plan
    Suggestion: Add delegation methods

lib/order.rb
  [high] KISS
    Pattern: Cyclomatic complexity of 15
    Suggestion: Break into smaller methods

============================================================
                    Validation Summary                     
============================================================

Files checked: 45
Files with violations: 2

Violations by severity:
  High: 3
  Medium: 5

Total violations: 8

⚠ Validation passed with warnings
```

#### Exit Codes

- `0`: Success (no violations or only low/medium)
- `1`: Failure (critical or high severity violations)

Use in scripts:

```bash
if bin/validate_principles; then
  echo "Code quality checks passed"
else
  echo "Fix violations before deploying"
  exit 1
fi
```

#### Severity Levels

- **Critical**: Security vulnerabilities, data loss risks
- **High**: Major design flaws, performance problems
- **Medium**: Code smells, maintainability issues
- **Low**: Style preferences, minor improvements

Configure thresholds in `lib/config/principle_enforcement.yml`:

```yaml
enforcement:
  severity_threshold: medium  # Block on medium and above
```

## Port Consistency Checker

Validates deployment port configuration.

### bin/check_ports

Checks `lib/config/deployment.yml` for port conflicts.

#### Usage

```bash
bin/check_ports
```

#### Output

Success:

```bash
============================================================
                   Port Consistency Check                  
============================================================

✓ Port configuration is valid

Apps configured: 3
Port range: 3000 - 5000

Port assignments:
  3000   → web_app
  4000   → api_server
  5000   → websocket_server
```

Port conflict detected:

```bash
============================================================
                   Port Consistency Check                  
============================================================

❌ Port conflicts detected:

  Port 3000:
    - web_app
    - admin_panel

Exit code: 1
```

Reserved port warning:

```bash
============================================================
                   Port Consistency Check                  
============================================================

⚠ Warning: Apps using reserved ports:

  web_app: 80
  database: 3306
```

#### Validation Rules

1. **No Conflicts**: Each port used by only one app
2. **Valid Range**: Ports between 1024-65535 (non-privileged)
3. **Reserved Ports**: Warning for common service ports (80, 443, 3306, 5432, etc.)

#### Configuration

Edit `lib/config/deployment.yml`:

```yaml
apps:
  - name: web_app
    port: 3000
    
  - name: api_server
    port: 4000
    
  - name: websocket_server
    port: 5000
```

## CI/CD Integration

### GitHub Actions

Add to `.github/workflows/quality.yml`:

```yaml
name: Code Quality

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
          bundler-cache: true
      
      - name: Validate principles
        run: bin/validate_principles
      
      - name: Check port configuration
        run: bin/check_ports
```

### GitLab CI

Add to `.gitlab-ci.yml`:

```yaml
validate:
  stage: test
  script:
    - bundle install
    - bin/validate_principles
    - bin/check_ports
  only:
    - merge_requests
    - main
```

### Jenkins

Add to `Jenkinsfile`:

```groovy
stage('Validate Principles') {
  steps {
    sh 'bundle install'
    sh 'bin/validate_principles'
    sh 'bin/check_ports'
  }
}
```

### Pre-Push Hook

Validate before pushing to remote:

Create `.git/hooks/pre-push`:

```bash
#!/bin/bash

echo "Running principle validation..."

if ! bin/validate_principles; then
  echo "❌ Validation failed. Push rejected."
  exit 1
fi

if ! bin/check_ports; then
  echo "❌ Port check failed. Push rejected."
  exit 1
fi

echo "✓ All checks passed"
exit 0
```

Make executable:

```bash
chmod +x .git/hooks/pre-push
```

## Auto-Fix Capabilities

Some violations can be automatically corrected.

### Available Auto-Fixes

Currently supported:

- **Single Responsibility**: Extract long methods
- **DRY**: Remove duplicate code blocks
- **KISS**: Simplify complex expressions
- **Meaningful Names**: Expand abbreviations

### Using Auto-Fix

```bash
# Dry run (show what would be fixed)
bin/validate_principles --fix --dry-run

# Apply fixes
bin/validate_principles --fix

# Fix specific file
bin/validate_principles --fix lib/user.rb
```

### Example

Before:

```ruby
class User
  def proc_usr_data(u)
    if u.valid?
      if u.email.present?
        if u.confirmed?
          u.save
        end
      end
    end
  end
end
```

After `bin/validate_principles --fix`:

```ruby
class User
  def process_user_data(user)
    return unless user.valid?
    return unless user.email.present?
    return unless user.confirmed?
    
    user.save
  end
end
```

### Safety

Auto-fix creates backups:

```bash
lib/user.rb          # Fixed version
lib/user.rb.backup   # Original
```

Review and test changes before committing.

## Configuration

### Enforcement Configuration

Edit `lib/config/principle_enforcement.yml`:

```yaml
version: 1
enforcement:
  enabled: true
  auto_fix: false
  severity_threshold: medium

principles:
  01-kiss:
    checks:
      - type: complexity
        metric: cyclomatic
        threshold: 10
        severity: high
      - type: file_size
        threshold: 20480  # 20KB
        severity: medium
    auto_fix: true
    
  02-dry:
    checks:
      - type: duplication
        tool: flay
        threshold: 0.05  # 5%
        severity: high
    auto_fix: true
    
  05-single-responsibility:
    checks:
      - type: class_methods
        threshold: 15
        severity: high
    auto_fix: true
```

### Global Settings

```yaml
enforcement:
  # Enable/disable all enforcement
  enabled: true
  
  # Enable auto-fix by default
  auto_fix: false
  
  # Minimum severity to enforce
  # Options: low, medium, high, critical
  severity_threshold: medium
  
  # Exclude patterns
  exclude:
    - test/**/*
    - tmp/**/*
    - vendor/**/*
```

### Per-Principle Configuration

```yaml
principles:
  principle-name:
    # Enable this principle
    enabled: true
    
    # Checks to run
    checks:
      - type: complexity
        threshold: 10
        severity: high
    
    # Allow auto-fix
    auto_fix: false
    
    # Exclude files
    exclude:
      - lib/legacy/**/*
```

### Environment Overrides

Override configuration via environment variables:

```bash
export MASTER_ENFORCE_STRICT=true        # Fail on medium severity
export MASTER_ENFORCE_AUTO_FIX=true      # Enable auto-fix
export MASTER_ENFORCE_EXCLUDE="test/**"  # Exclude patterns
```

---

For more information:
- See `bin/validate_principles` source code
- See `bin/check_ports` source code
- See `lib/violations.rb` for detection logic
- See `docs/PRINCIPLES.md` for principle descriptions
