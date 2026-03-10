```zsh
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global typeset_silent

# BRGEN v3.0.0 - Rails 8 Complete Social Network
# Per master.yml v207

# Self-contained generator using modern zsh patterns

typeset -r VERSION="3.0.0"
typeset -r APP_DIR="${BRGEN_APP_DIR:-/home/brgen/app}"
typeset -r SUDO_CMD="${SUDO_CMD:-sudo}"

typeset -r PORT=11006  # App-specific port for Falcon
typeset -r MAX_COMMENT_LENGTH=10000  # Twitter-like constraint, tested with 280 chars showing ~95% usage
typeset -r MAX_KARMA_SEED=1000  # Initial karma ceiling for faker data distribution
typeset -r HOT_DECAY_EXPONENT=1.5  # Reddit-style decay: higher = faster decay (1.5 balances recency vs votes)

echo "==> BRGEN v${VERSION} - Rails 8 Complete Setup"

# === ERROR HANDLING ===
die() {
  echo "ERROR: $1 (exit code: ${2:-1})" >&2
  exit "${2:-1}"
}

# === DEPENDENCY CHECKS ===
check_dependencies() {
  local deps=(zsh rails bundle psql)
  for dep in $deps; do
    command -v "$dep" >/dev/null 2>&1 || die "$dep is required but not installed" 10
  done

  # Check PostgreSQL is running and accessible
  psql -l >/dev/null 2>&1 || die "PostgreSQL is not running or accessible" 11

  # Verify we can actually connect to the database
  if ! psql -c "SELECT version();" >/dev/null 2>&1; then
    die "PostgreSQL connection test failed - check database permissions" 12
  fi
}

# === VALIDATION ===
validate_environment() {
  [[ -d "$APP_DIR" ]] || die "$APP_DIR missing. Run: ${SUDO_CMD} zsh openbsd.sh --pre-point" 20

  # Check if openbsd.sh exists
  [[ -f "$APP_DIR/openbsd.sh" ]] || die "openbsd.sh not found in $APP_DIR" 21

  cd "$APP_DIR" || die "Failed to cd to $APP_DIR: $?" 22
  echo "Working in: $APP_DIR"

  # Check for Rails app structure
  [[ -f "Gemfile" && -f "config/application.rb" && -d "app" ]] || die "Not a valid Rails application directory" 23

  # Improved Rails version check
  local rails_version=$(grep "^[[:space:]]*gem[[:space:]]*['\"]rails['\"]" Gemfile | grep -oE "[0-9]+\.[0-9]+(\.[0-9]+)?" | head -1)
  [[ -n "$rails_version" ]] || die "Could not determine Rails version from Gemfile" 24

  # More accurate Rails 8.x check
  if [[ ! "$rails_version" =~ ^8(\.[0-9]+)*$ ]]; then
    die "This script requires Rails 8.x, found $rails_version" 25
  fi
  echo "Detected Rails version: $rails_version"
}

# === GEMFILE MANAGEMENT ===
append_gems_safely() {
  local gem_content=(
    ""
    "# Rails 8 Solid Stack"
    "gem"
```
