#!/bin/zsh
# Quick syntax check for all Ruby files in the repository
# Usage: ./scripts/check_all_syntax.sh

echo "🔍 Checking Ruby syntax in all .rb files..."
errors=0

while read -r file; do
  ruby -c "$file" > /dev/null 2>&1
  if [[ $? -ne 0 ]]; then
    echo "❌ $file"
    ruby -c "$file"
    errors=1
  else
    echo "✅ $file"
  fi
done < <(find . -name "*.rb" -type f \
  -not -path "*/vendor/*" \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/tmp/*")

if [[ $errors -eq 1 ]]; then
  echo ""
  echo "❌ Syntax errors found"
  exit 1
else
  echo ""
  echo "✅ All Ruby files have valid syntax"
  exit 0
fi
