# Strategy to Prevent Syntax Errors in Ruby Code

## The Issue That Was Fixed
The file `MASTER2/lib/llm.rb` had a syntax error on line 84:
```ruby
model_id = model.is_a?(String) ? model : (model&.id || return :cheap)
```

This is invalid because `return` cannot be used as part of an expression in Ruby. It was refactored to:
```ruby
if model.is_a?(String)
  model_id = model
else
  return :cheap unless model&.id
  model_id = model.id
end
```

## Prevention Strategies

### 1. Pre-Commit Syntax Validation (Recommended - Quick Win)
Add a git pre-commit hook to validate Ruby syntax before commits:

**Create `.git/hooks/pre-commit`:**
```zsh
#!/bin/zsh
# Pre-commit hook to check Ruby syntax

echo "Checking Ruby syntax..."
errors=0

# Find all staged Ruby files
for file in $(git diff --cached --name-only --diff-filter=ACM | grep '\.rb$'); do
  if [[ -f "$file" ]]; then
    ruby -c "$file" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      echo "❌ Syntax error in: $file"
      ruby -c "$file"
      errors=1
    fi
  fi
done

if [[ $errors -eq 1 ]]; then
  echo ""
  echo "❌ Commit rejected due to syntax errors. Please fix and try again."
  exit 1
fi

echo "✅ All Ruby files passed syntax check"
exit 0
```

Make it executable:
```zsh
chmod +x .git/hooks/pre-commit
```

### 2. GitHub Actions CI Workflow (Recommended for Teams)
Create `.github/workflows/ruby-syntax-check.yml`:

```yaml
name: Ruby Syntax Check

on: [push, pull_request]

jobs:
  syntax-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
      
      - name: Check Ruby syntax
        run: |
          echo "Checking Ruby syntax for all files..."
          find . -name "*.rb" -type f -exec ruby -c {} \; | grep -v "Syntax OK" || true
          
          # Fail if any syntax errors found
          errors=$(find . -name "*.rb" -type f -exec ruby -c {} \; 2>&1 | grep -v "Syntax OK" | wc -l)
          if [ $errors -gt 0 ]; then
            echo "❌ Found $errors syntax errors"
            find . -name "*.rb" -type f -exec ruby -c {} \; 2>&1 | grep -v "Syntax OK"
            exit 1
          fi
          echo "✅ All Ruby files have valid syntax"
```

### 3. RuboCop Linting (Comprehensive Solution)
Add RuboCop to catch not just syntax errors but style issues too.

**Add to Gemfile:**
```ruby
group :development do
  gem 'rubocop', require: false
  gem 'rubocop-performance', require: false
end
```

**Create `.rubocop.yml`:**
```yaml
AllCops:
  NewCops: enable
  TargetRubyVersion: 3.2
  Exclude:
    - 'vendor/**/*'
    - 'tmp/**/*'
    - 'node_modules/**/*'

# This catches syntax errors automatically
Lint/Syntax:
  Enabled: true

# Enable performance cops
Performance:
  Enabled: true
```

**Run RuboCop:**
```bash
bundle install
bundle exec rubocop
```

### 4. Editor Integration (For Individual Developers)
Configure your editor to show syntax errors in real-time:

**VS Code:**
- Install "Ruby" extension by Peng Lv
- Install "Ruby Solargraph" for language server support
- Syntax errors will be highlighted immediately

**RubyMine/IntelliJ:**
- Built-in Ruby support with real-time syntax checking

**Vim/Neovim:**
- Install `ale` or `syntastic` plugin
- Configure for Ruby syntax checking

### 5. Make Syntax Check Part of Your Test Suite
Add to your Rakefile or test runner:

```ruby
# Rakefile
task :syntax_check do
  puts "Checking Ruby syntax..."
  errors = []
  
  Dir.glob("**/*.rb").each do |file|
    next if file.include?("vendor/") || file.include?("node_modules/")
    
    result = `ruby -c "#{file}" 2>&1`
    unless result.include?("Syntax OK")
      errors << file
      puts "❌ #{file}"
      puts result
    end
  end
  
  if errors.any?
    puts "\n❌ Found syntax errors in #{errors.size} file(s)"
    exit 1
  else
    puts "✅ All Ruby files have valid syntax"
  end
end

# Add to default test task
task test: :syntax_check
```

### 6. Quick Manual Check Script
Create `scripts/check_syntax.sh`:

```zsh
#!/bin/zsh
# Quick syntax check for all Ruby files

echo "Checking Ruby syntax in all .rb files..."
find . -name "*.rb" -type f \
  -not -path "*/vendor/*" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -exec ruby -c {} \; 2>&1 | grep -v "Syntax OK"

if [[ ${pipestatus[1]} -eq 0 ]]; then
  echo "✅ All Ruby files have valid syntax"
  exit 0
else
  echo "❌ Syntax errors found"
  exit 1
fi
```

## Recommended Immediate Actions

1. **Immediate (0-5 minutes):** Add the git pre-commit hook to your local repository
2. **Short-term (1 hour):** Add GitHub Actions workflow for CI
3. **Medium-term (1-2 hours):** Add RuboCop with configuration
4. **Long-term:** Ensure all team members have editor integration

## Testing the Fix

```zsh
# Test the specific file
ruby -c MASTER2/lib/llm.rb

# Test all Ruby files
find . -name "*.rb" -type f -exec ruby -c {} \; | grep -v "Syntax OK"
```

## Scan Results

✅ **Good News:** Scanned the entire codebase for similar patterns:
- No other instances of `|| return` in expressions found
- No other instances of `return` in ternary operators found
- No other instances of safe navigation operator with `return` found

The bug was isolated to this single location and has been fixed.
