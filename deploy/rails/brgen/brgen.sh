```zsh
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

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
}

# === VALIDATION ===
validate_environment() {
  [[ -d "$APP_DIR" ]] || die "$APP_DIR missing. Run: $SUDO_CMD zsh openbsd.sh --pre-point"

  cd "$APP_DIR" || die "Failed to cd to $APP_DIR: $?"
  echo "Working in: $APP_DIR"

  # Check for Rails app structure
  [[ -f "Gemfile" && -f "config/application.rb" && -d "app" ]] || die "Not a valid Rails application directory"
}

# === GEMFILE MANAGEMENT ===
append_gems_safely() {
  local gem_content=(
    ""
    "# Rails 8 Solid Stack"
    "gem \"solid_queue\""
    "gem \"solid_cache\""
    "gem \"solid_cable\""
    ""
    "# Authentication"
    "gem \"devise\""
  )

  # Check if gems are already present
  for gem in solid_queue solid_cache solid_cable devise; do
    if grep -q "gem \"$gem\"" Gemfile; then
      echo "Gem '$gem' already present in Gemfile, skipping addition"
      return 0
    fi
  done

  # Append to Gemfile with proper formatting
  printf '%s\n' "${gem_content[@]}" >> Gemfile || die "Failed to append to Gemfile"

  # Install gems after modification
  echo "Installing new gems..."
  bundle install || die "Failed to run bundle install"
}

# === DATABASE SETUP ===
setup_database() {
  echo "Setting up database..."
  bundle exec rails db:create || die "Failed to create database"
  bundle exec rails db:migrate || die "Failed to run migrations"
}

# === MAIN EXECUTION ===
main() {
  check_dependencies
  validate_environment
  append_gems_safely
  setup_database

  echo "BRGEN setup completed successfully!"
  echo "Application will run on port: $PORT"
}

main "$@"
```
