#!/bin/zsh
# Pre-commit hook to check Ruby syntax
# 
# To install: 
#   cp scripts/pre-commit-syntax-check.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit

echo "🔍 Checking Ruby syntax..."
errors=0

# Find all staged Ruby files
for file in $(git diff --cached --name-only --diff-filter=ACM | grep '\.rb$'); do
  if [[ -f "$file" ]]; then
    ruby -c "$file" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
      echo "❌ Syntax error in: $file"
      ruby -c "$file"
      errors=1
    else
      echo "✅ $file"
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
