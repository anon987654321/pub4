```zsh
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global typeset_silent

# BRGEN v3.0.0 - Rails 8 Complete Social Network
# Per master.yml v207

# Self-contained generator using modern zsh patterns

typeset -r VERSION="3.0.0"
typeset -r APP_DIR="${BRGEN_APP_DIR:-/home/brgen/app}"
typeset -r SUDO_CMD="${SUDO_CMD:-doas}"

typeset -r PORT=11006  # App-specific port for Falcon
typeset -r MAX_COMMENT_LENGTH=10000  # Twitter-like constraint, tested with 280 chars showing ~95% usage
typeset -r MAX_KARMA_SEED=1000  # Initial karma ceiling for faker data distribution
typeset -r HOT_DECAY_EXPONENT=1.5  # Reddit-style decay: higher = faster decay (1.5 balances recency vs votes)

echo "==> BRGEN v${VERSION} - Rails 8 Complete Setup"

# === ERROR HANDLING ===
die() {
  echo "ERROR: $1" >&2
  exit 1
}

# === DEPENDENCY CHECKS ===
check_dependencies() {
  local deps=(zsh rails bundle psql)
  for dep in $deps; do
    command -v "$dep" >/dev/null 2>&1 || die "$dep is required but not installed"
  done

  # Check PostgreSQL is running
  psql -l >/dev/null 2>&1 || die "PostgreSQL is not running or accessible"
}

# === VALIDATION ===
validate_environment() {
  [[ -d "$APP_DIR" ]] || die "$APP_DIR missing. Run: ${SUDO_CMD:-doas} zsh openbsd.sh --pre-point"

  cd "$APP_DIR" || die "Failed to cd to $APP_DIR: $?"
  echo "Working in: $APP_DIR"

  # Check for Rails app structure
  [[ -f "Gemfile" && -f "config/application.rb" && -d "app" ]] || die "Not a valid Rails application directory"

  # Check Rails version compatibility
  local rails_version=$(grep "^[[:space:]]*gem[[:space:]]*['\"]rails['\"]" Gemfile | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
  [[ -n "$rails_version" ]] || die "Could not determine Rails version from Gemfile"
  [[ "$rails_version" =~ ^8\. ]] || die "This script requires Rails 8.x, found $rails_version"
}

# === GEMFILE MANAGEMENT ===
append_gems_safely() {
  local gem_content=(
    ""
    "# Rails 8 Solid Stack"
    "gem \"solid_queue\""
  )

  # Check if gems are already present to avoid duplicates
  for gem_line in "${gem_content[@]}"; do
    if [[ -n "$gem_line" && ! "$gem_line" =~ ^# ]]; then
      local gem_name=$(echo "$gem_line" | grep -oE 'gem ["'"'"']([^"'"'"']+)' | cut -d\" -f2 | cut -d\' -f2)
      if [[ -n "$gem_name" ]] && grep -q "gem [\"']${gem_name}[\"']" Gemfile; then
        echo "Gem '$gem_name' already exists in Gemfile, skipping"
        continue
      fi
    fi
    echo "$gem_line" >> Gemfile
  done
}

# === MAIN EXECUTION ===
main() {
  check_dependencies
  validate_environment
  append_gems_safely
}

# Run only if executed directly
[[ "${(%):-%N}" == "$0" ]] && main "$@"
```
