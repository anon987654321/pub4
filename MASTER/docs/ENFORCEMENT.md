# Principle Enforcement System

MASTER provides multiple layers of enforcement to ensure code quality and adherence to the 45 principles.

## Overview

The enforcement system includes:

1. **Git Hooks** - Pre-commit validation
2. **Validation Tools** - `bin/validate_principles`
3. **Port Checker** - `bin/check_ports`
4. **Hook Installer** - `bin/install-hooks`
5. **CLI Integration** - Real-time enforcement during development

---

## Enforcement Layers

### Layer 1: Real-Time (CLI)

Immediate feedback during development:

```bash
# Scan with enforcement
bin/cli scan lib/ --enforce

# Review file with principle checking
bin/cli review app/models/user.rb

# Refactor with principle validation
bin/cli refactor src/ --validate
```

### Layer 2: Pre-Commit (Git Hook)

Blocks commits that violate principles:

```bash
# Install hooks (one-time)
bin/install-hooks

# Now all commits are validated
git commit -m "Add feature"
# -> Validates against all principles
# -> Blocks if violations found
```

### Layer 3: Manual Validation

Explicit validation runs:

```bash
# Validate all principles
bin/validate_principles

# Validate specific file
bin/validate_principles app/models/user.rb

# Validate with auto-fix
bin/validate_principles --fix

# Verbose output
bin/validate_principles --verbose
```

### Layer 4: CI/CD Integration

Automated validation in pipelines:

```yaml
# .github/workflows/quality.yml
name: Quality Check

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.2
      - name: Install dependencies
        run: |
          cd MASTER
          bundle install
      - name: Validate principles
        run: bin/validate_principles --ci
      - name: Check ports
        run: bin/check_ports
```

---

## Git Hooks

### Pre-Commit Hook

Location: `.git/hooks/pre-commit`

The pre-commit hook validates:
- Principle violations in changed files
- File size limits
- Code complexity metrics
- Naming conventions
- Documentation completeness

#### Installation

```bash
# Install hooks
cd MASTER
bin/install-hooks

# Verify installation
ls -la .git/hooks/pre-commit
```

#### Manual Hook Creation

If `bin/install-hooks` doesn't work:

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Get list of staged files
FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(rb|js|py|ts)$')

if [ -z "$FILES" ]; then
  exit 0
fi

# Run validation
echo "Validating principles..."
bin/validate_principles $FILES

if [ $? -ne 0 ]; then
  echo ""
  echo "❌ Principle violations detected!"
  echo "Fix violations or use 'git commit --no-verify' to skip."
  exit 1
fi

echo "✓ All principles validated"
exit 0
```

Make executable:
```bash
chmod +x .git/hooks/pre-commit
```

#### Bypassing Hook

For emergencies only:

```bash
# Skip validation (NOT RECOMMENDED)
git commit --no-verify -m "Emergency fix"

# Better: Fix violations first
bin/validate_principles --fix
git commit -m "Fixed violations"
```

---

## Validation Tool

### bin/validate_principles

Comprehensive principle validation script.

#### Basic Usage

```bash
# Validate all files
bin/validate_principles

# Validate specific files
bin/validate_principles app/models/*.rb

# Validate directory
bin/validate_principles lib/

# Validate with pattern
bin/validate_principles **/*.rb
```

#### Options

```bash
# Auto-fix violations
bin/validate_principles --fix

# Verbose output
bin/validate_principles --verbose

# CI mode (machine-readable)
bin/validate_principles --ci

# JSON output
bin/validate_principles --format json

# Specific principles only
bin/validate_principles --principles kiss,dry,yagni

# Exclude principles
bin/validate_principles --exclude squint-test,prose-over-lists

# Set severity threshold
bin/validate_principles --min-severity error

# Fail fast (stop on first violation)
bin/validate_principles --fail-fast
```

#### Output Format

```
🔍 Validating principles...

app/models/user.rb:
  ✗ KISS (Keep It Simple, Stupid)
    Line 45: Method 'calculate_total' is too complex (15 branches)
    Severity: error
    Fix: Extract conditional logic into smaller methods
    
  ⚠ Small Functions
    Line 78: Method 'process_order' is 35 lines (max: 20)
    Severity: warning
    Fix: Extract order validation and persistence
    
lib/services/payment.rb:
  ✓ All principles passed

Summary:
  Files checked: 12
  Violations: 2 errors, 1 warning
  Auto-fixable: 1
  Principles validated: 45

Exit code: 1 (violations found)
```

#### CI Integration

```bash
# Run in CI mode
bin/validate_principles --ci --format json > violations.json

# Check exit code
if [ $? -ne 0 ]; then
  echo "Quality gate failed"
  exit 1
fi
```

Example JSON output:

```json
{
  "summary": {
    "files_checked": 12,
    "violations": 3,
    "errors": 2,
    "warnings": 1,
    "infos": 0
  },
  "violations": [
    {
      "file": "app/models/user.rb",
      "line": 45,
      "principle": "KISS",
      "severity": "error",
      "message": "Method too complex",
      "auto_fixable": false
    }
  ]
}
```

---

## Port Consistency Checker

### bin/check_ports

Validates port assignments across deployment configurations.

#### Usage

```bash
# Check all configurations
bin/check_ports

# Check specific environment
bin/check_ports --env production

# Verbose output
bin/check_ports --verbose

# Generate port map
bin/check_ports --map > ports.txt
```

#### Port Validation Rules

1. **No Conflicts**: Same port not used by multiple services
2. **Range Compliance**: Ports within allowed ranges
3. **Consistency**: Development/staging/production use same relative offsets
4. **Documentation**: All ports documented in `ports.yml`

#### Configuration

Create `config/ports.yml`:

```yaml
services:
  web:
    dev: 3000
    staging: 8000
    production: 80
    
  api:
    dev: 3001
    staging: 8001
    production: 81
    
  websocket:
    dev: 3002
    staging: 8002
    production: 82

ranges:
  development: [3000, 3999]
  staging: [8000, 8999]
  production: [80, 999]

reserved:
  - 22    # SSH
  - 80    # HTTP
  - 443   # HTTPS
  - 5432  # PostgreSQL
  - 6379  # Redis
```

#### Example Output

```
🔍 Checking port configurations...

✓ Web server
  Dev: 3000 ✓
  Staging: 8000 ✓
  Production: 80 ✓

✗ API server
  Dev: 3001 ✓
  Staging: 8001 ✓
  Production: 443 ✗ (conflicts with HTTPS)

⚠ Database
  Production: 5432 ⚠ (using standard port - security risk)

Summary:
  Services checked: 8
  Conflicts: 1
  Warnings: 1

Recommendations:
  - Move API production to port 81
  - Use non-standard database port for security
```

---

## Hook Installer

### bin/install-hooks

Installs all git hooks with proper permissions.

#### Usage

```bash
# Install all hooks
bin/install-hooks

# Install specific hook
bin/install-hooks pre-commit

# Force reinstall
bin/install-hooks --force

# Dry run (show what would be installed)
bin/install-hooks --dry-run
```

#### What Gets Installed

```
.git/hooks/
├── pre-commit       # Principle validation
├── pre-push         # Run tests before push
├── commit-msg       # Validate commit message format
└── post-checkout    # Update dependencies on branch switch
```

#### Hook Templates

Templates are in `hooks/`:

```
MASTER/hooks/
├── pre-commit.template
├── pre-push.template
├── commit-msg.template
└── post-checkout.template
```

#### Verification

```bash
# Check if hooks are installed
test -x .git/hooks/pre-commit && echo "✓ Pre-commit hook installed"

# Test hook manually
.git/hooks/pre-commit
```

---

## Configuration

### principle_enforcement.yml

Location: `lib/config/principle_enforcement.yml`

```yaml
enforcement:
  # Enforcement mode
  mode: strict  # strict, lenient, advisory
  
  # Auto-fix violations when possible
  auto_fix: true
  
  # Block commits on violations
  fail_on_error: true
  fail_on_warning: false
  
  # Git hook integration
  pre_commit: true
  pre_push: true
  
  # Validation scope
  validate_on_commit: true
  validate_staged_only: true
  
  # Performance
  parallel: true
  max_workers: 4
  
  # Reporting
  verbose: false
  show_context: 3  # lines of context
  
severity_weights:
  error: 10
  warning: 5
  info: 1

# Principle-specific overrides
overrides:
  squint-test:
    auto_fixable: true
    severity: warning
    
  kiss:
    complexity_threshold: 10
    
  small-functions:
    max_lines: 20
    max_complexity: 10

# File exclusions
exclude:
  - "vendor/**"
  - "node_modules/**"
  - "*.min.js"
  - "db/schema.rb"
  - "test/fixtures/**"
```

### Environment Variables

```bash
# Override enforcement mode
export MASTER_ENFORCEMENT_MODE=lenient

# Disable hooks
export MASTER_HOOKS_DISABLED=true

# Validation workers
export MASTER_VALIDATION_WORKERS=8

# Debug mode
export MASTER_VALIDATION_DEBUG=true
```

---

## Enforcement Modes

### Strict Mode

```yaml
enforcement:
  mode: strict
```

- All violations block commits
- No auto-fix without confirmation
- Comprehensive validation
- Best for production codebases

### Lenient Mode

```yaml
enforcement:
  mode: lenient
```

- Warnings don't block
- Auto-fix enabled by default
- Faster validation
- Good for development

### Advisory Mode

```yaml
enforcement:
  mode: advisory
```

- Nothing blocks commits
- Reports violations only
- No auto-fix
- Good for learning

---

## Best Practices

### 1. Install Hooks Early

```bash
# Day 1 of project
git init
cd MASTER
bin/install-hooks
```

### 2. Run Validation Before Commits

```bash
# Check before staging
bin/validate_principles app/models/user.rb

# Fix violations
bin/validate_principles --fix app/models/user.rb

# Then commit
git add app/models/user.rb
git commit -m "Refactor User model"
```

### 3. CI Integration

```yaml
# Always validate in CI
- name: Validate principles
  run: bin/validate_principles --ci --format json
```

### 4. Team Onboarding

```bash
# New developer checklist
cd MASTER
bin/install-hooks                    # Install hooks
bin/validate_principles --help       # Learn tool
bin/cli principles                   # Review principles
```

### 5. Regular Audits

```bash
# Weekly principle audit
bin/validate_principles > audit.txt

# Check for trends
grep "^  ✗" audit.txt | sort | uniq -c | sort -rn
```

---

## Troubleshooting

### Hook Not Running

```bash
# Check if hook is installed
ls -la .git/hooks/pre-commit

# Check if executable
chmod +x .git/hooks/pre-commit

# Test manually
.git/hooks/pre-commit
```

### Validation Too Slow

```yaml
# Enable parallel validation
enforcement:
  parallel: true
  max_workers: 8

# Validate staged files only
enforcement:
  validate_staged_only: true
```

### False Positives

```yaml
# Adjust thresholds
overrides:
  small-functions:
    max_lines: 30  # Increase from 20
    
  kiss:
    complexity_threshold: 15  # Increase from 10
```

### Bypass for Emergency

```bash
# Skip validation (emergency only)
git commit --no-verify -m "Hotfix"

# Then fix violations after
bin/validate_principles --fix
git commit --amend --no-edit
```

---

## Examples

### Example 1: Full Validation Workflow

```bash
# 1. Make changes
vim app/models/user.rb

# 2. Validate changes
bin/validate_principles app/models/user.rb

# 3. Auto-fix if possible
bin/validate_principles --fix app/models/user.rb

# 4. Commit (hooks run automatically)
git add app/models/user.rb
git commit -m "Refactor User model"

# 5. Push (pre-push hook runs)
git push
```

### Example 2: CI Pipeline

```yaml
# .github/workflows/quality.yml
name: Quality Gate

on: [push, pull_request]

jobs:
  enforce:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install MASTER
        run: cd MASTER && bundle install
        
      - name: Validate principles
        run: |
          cd MASTER
          bin/validate_principles --ci --format json > violations.json
          
      - name: Check ports
        run: cd MASTER && bin/check_ports
        
      - name: Upload violations
        if: failure()
        uses: actions/upload-artifact@v3
        with:
          name: violations
          path: MASTER/violations.json
```

### Example 3: Pre-Commit Configuration

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: validate-principles
        name: Validate MASTER principles
        entry: MASTER/bin/validate_principles
        language: system
        pass_filenames: true
        files: \.(rb|js|py|ts)$
```

---

## Further Reading

- [PRINCIPLES.md](PRINCIPLES.md) - All 45 principles explained
- [FRAMEWORK_INTEGRATION.md](FRAMEWORK_INTEGRATION.md) - Framework modules
- [README.md](README.md) - Main documentation

---

**Version**: MASTER v52.0 REFLEXION  
**Last Updated**: 2024-02-05  
**Tools**: `bin/validate_principles`, `bin/check_ports`, `bin/install-hooks`
