#!/usr/bin/env zsh
set -euo pipefail
setopt nullglob extendedglob

# Lints Ruby/ERB files using bundler-scoped rubocop + reek.
# Run from any directory; resolves MASTER bundle automatically.
# Usage: ./lint.sh [path]

MASTER_ROOT="${HOME}/pub4/MASTER"
TARGET="${1:-.}"

bundle_exec() {
  (cd "$MASTER_ROOT" && bundle exec "$@")
}

lint_ruby() {
  local file="$1"
  print "→ $file"

  if ! bundle_exec reek --no-color "$file" 2>/dev/null; then
    print "  reek: smells found"
  fi

  if ! bundle_exec rubocop --autocorrect --config "${MASTER_ROOT}/.rubocop.yml" --no-color "$file" 2>/dev/null; then
    print "  rubocop: offenses remain after autocorrect"
  fi
}

for file in ${TARGET}/**/*.{rb,erb}(.N); do
  [[ "$file" == */.gem/* || "$file" == */vendor/* ]] && continue
  lint_ruby "$file"
done

print "lint done"
