# frozen_string_literal: true
# Fix the 5 files that still have syntax errors after the initial fix pass
# These are too mangled for simple text substitution - needs full rewrites

DEPLOY_ROOT = File.expand_path("DEPLOY", __dir__)

def write_file(path, content)
  orig = File.exist?(path) ? File.read(path) : ""
  File.write("#{path}.bak2", orig) if orig.length > 0
  File.write(path, content)
  lines = content.lines.size
  puts "  wrote #{lines} lines"
end

# ============================================================
# 1. @shared_functions.sh - clean rewrite of shared Rail helpers
# ============================================================
path = File.join(DEPLOY_ROOT, "rails/@shared_functions.sh")
puts "Fixing: rails/@shared_functions.sh"
write_file(path, <<~'ZSH')
  #!/usr/bin/env zsh
  emulate -L zsh
  setopt err_return no_unset pipe_fail extended_glob warn_create_global

  # Shared functions for Rails app generators
  # Sourced by all app deploy scripts

  [[ -n "$ZSH_VERSION" ]] || { print -u2 "Error: must run with zsh"; exit 1 }

  log() { print "[$(date +'%Y-%m-%d %H:%M:%S')] $*" }

  command_exists() { command -v "$1" >/dev/null 2>&1 }

  install_gem() {
    local gem_name="$1" gem_version="${2:-}"
    if bundle list 2>/dev/null | grep -q "\\b${gem_name}\\b"; then
      log "Gem already installed: $gem_name"
      return 0
    fi
    log "Installing gem: $gem_name"
    if [[ -n "$gem_version" ]]; then
      bundle add "$gem_name" --version "$gem_version" || return 1
    else
      bundle add "$gem_name" || return 1
    fi
  }

  check_app_exists() {
    local app_name="$1" sentinel_file="$2"
    [[ -f "$sentinel_file" ]] && { log "App $app_name already set up ($sentinel_file exists), skipping"; return 0 }
    return 1
  }

  setup_full_app() {
    local app_name="$1"
    local base_dir="${BASE_DIR:-/home/dev/rails}"
    log "Setting up full Rails 8 app: $app_name in $base_dir"

    [[ -d "$base_dir" ]] || mkdir -p "$base_dir"
    cd "$base_dir"

    if [[ ! -d "$app_name" ]]; then
      rails new "$app_name" \
        --database=postgresql \
        --css=tailwind \
        --javascript=importmap \
        --skip-test
    fi

    cd "$app_name"
    bundle install
  }

  migrate_db() {
    log "Running database migrations"
    bin/rails db:create 2>/dev/null || true
    bin/rails db:migrate
  }

  setup_authentication() {
    log "Setting up Rails 8 built-in authentication"
    bin/rails generate authentication 2>/dev/null || true
    migrate_db
  }

  setup_rate_limiting() {
    log "Setting up Rails 8 rate limiting"
    # Rate limiting is built into Rails 8 via ActionController::RateLimiting
    # Configure per-controller as needed
    return 0
  }

  get_app_port() {
    local app_name="$1"
    local master_json="${MASTER_JSON:-${0:A:h}/../master.json}"
    [[ -f "$master_json" ]] || { log "ERROR: master.json not found"; return 1 }
    ruby -r json -e '
      data = JSON.parse(File.read(ARGV[0]))
      app = (data["apps"] || []).find { |a| a["name"] == ARGV[1] }
      if app && app["port"]
        puts app["port"]
      else
        $stderr.puts "Port not found for #{ARGV[1]}"
        exit 1
      end
    ' "$master_json" "$app_name"
  }

  generate_application_scss() {
    local theme_color="${1:-#0066ff}"
    local dark_mode="${2:-dark}"
    local target="app/assets/stylesheets/application.scss"
    mkdir -p "$(dirname "$target")"
    [[ -f "$target" ]] && { log "SCSS already exists: $target"; return 0 }
    cat > "$target" <<EOF
  :root {
    --color-primary: ${theme_color};
    --color-bg: #ffffff;
    --color-text: #1a1a1a;
  }
  body {
    font-family: system-ui, sans-serif;
    background: var(--color-bg);
    color: var(--color-text);
  }
  EOF
    log "Created: $target"
  }
ZSH

# ============================================================
# 2. brgen.sh - clean rewrite (was severely mangled)
# ============================================================
path = File.join(DEPLOY_ROOT, "rails/brgen/brgen.sh")
puts "Fixing: rails/brgen/brgen.sh"
write_file(path, <<~'ZSH')
  #!/usr/bin/env zsh
  emulate -L zsh
  setopt err_return no_unset pipe_fail extended_glob warn_create_global typeset_silent

  # BRGEN v3.0.0 - Rails 8 Complete Social Network
  # Per master.yml v207
  # Port: 11006

  typeset -r VERSION="3.0.0"
  typeset -r APP_NAME="brgen"
  typeset -r APP_DIR="${BRGEN_APP_DIR:-/home/brgen/app}"
  typeset -r PORT=11006
  typeset -r SERVER_IP="${SERVER_IP:-185.52.176.18}"
  typeset -r MAX_KARMA_SEED=1000
  typeset -r HOT_DECAY_EXPONENT=1.5
  SCRIPT_DIR="${0:A:h}"

  source "${SCRIPT_DIR}/../@shared_functions.sh"

  print "==> BRGEN v${VERSION} - Rails 8 Complete Setup"

  # Idempotency: skip if already set up
  check_app_exists "$APP_NAME" "${APP_DIR}/app/models/post.rb" && exit 0

  # Verify dependencies
  command_exists "ruby"   || { print "ERROR: ruby not found" >&2; exit 1 }
  command_exists "node"   || { print "ERROR: node not found" >&2; exit 1 }
  command_exists "psql"   || { print "ERROR: psql not found" >&2; exit 1 }
  command_exists "bundle" || { print "ERROR: bundle not found" >&2; exit 1 }

  # Verify PostgreSQL is accessible
  psql -l >/dev/null 2>&1 || { print "ERROR: PostgreSQL not accessible" >&2; exit 1 }

  log "Starting BRGEN setup"
  setup_full_app "$APP_NAME"

  # Core gems
  install_gem "pagy"
  install_gem "faker"

  # Rails 8 built-in authentication
  setup_authentication

  # Rate limiting (Rails 8 built-in)
  setup_rate_limiting

  # Patch Pagy helpers (idempotent)
  if ! grep -q "Pagy::Backend" app/controllers/application_controller.rb 2>/dev/null; then
    print "  include Pagy::Backend" >> app/controllers/application_controller.rb
  fi

  # Generate core models
  bin/rails generate model Post title:string body:text user:references karma:integer 2>/dev/null || true
  bin/rails generate model Community name:string description:text slug:string:uniq 2>/dev/null || true
  bin/rails generate model Membership user:references community:references role:string 2>/dev/null || true
  bin/rails generate model Comment content:text user:references commentable:references{polymorphic} parent:references{to_table:comments} 2>/dev/null || true
  bin/rails generate model Vote value:integer user:references votable:references{polymorphic} 2>/dev/null || true
  bin/rails generate model KarmaScore user:references score:integer 2>/dev/null || true

  migrate_db

  # Generate application SCSS
  generate_application_scss "#e85d04"

  # Source Twitter/Reddit features
  [[ -f "${SCRIPT_DIR}/../__shared/@twitter_features.sh" ]] && source "${SCRIPT_DIR}/../__shared/@twitter_features.sh"
  [[ -f "${SCRIPT_DIR}/../__shared/@reddit_features.sh" ]] && source "${SCRIPT_DIR}/../__shared/@reddit_features.sh"

  print "==> BRGEN setup complete on port $PORT"
  print "    App dir: $APP_DIR"
  print "    Server:  $SERVER_IP:$PORT"
ZSH

# ============================================================
# 3. baibl.sh - fix truncated setup_full_app function
# ============================================================
path = File.join(DEPLOY_ROOT, "rails/baibl/baibl.sh")
puts "Fixing: rails/baibl/baibl.sh"
write_file(path, <<~'ZSH')
  #!/usr/bin/env zsh
  emulate -L zsh
  setopt err_return no_unset pipe_fail extended_glob

  # Baibl - Bible study and text analysis platform
  # OpenBSD 7.8, Rails 8, unprivileged user

  APP_NAME="baibl"
  BASE_DIR="${BASE_DIR:-/home/dev/rails}"
  APP_PORT=10010
  SERVER_IP="${SERVER_IP:-185.52.176.18}"
  SCRIPT_DIR="${0:A:h}"

  source "${SCRIPT_DIR}/../@shared_functions.sh"

  check_app_exists "$APP_NAME" "${BASE_DIR}/${APP_NAME}/app/models/verse.rb" && exit 0

  log "Starting Baibl setup"

  command_exists "ruby"   || { print "ERROR: ruby not found" >&2; exit 1 }
  command_exists "bundle" || { print "ERROR: bundle not found" >&2; exit 1 }
  command_exists "psql"   || { print "ERROR: psql not found" >&2; exit 1 }

  psql -l >/dev/null 2>&1 || { print "ERROR: PostgreSQL not accessible" >&2; exit 1 }

  setup_full_app "$APP_NAME"

  install_gem "pagy"
  install_gem "faker"

  setup_authentication

  bin/rails generate model Book name:string abbreviation:string testament:string 2>/dev/null || true
  bin/rails generate model Chapter book:references number:integer 2>/dev/null || true
  bin/rails generate model Verse chapter:references number:integer text:text translation:string 2>/dev/null || true
  bin/rails generate model Note user:references verse:references content:text 2>/dev/null || true
  bin/rails generate model Highlight user:references verse:references color:string 2>/dev/null || true

  migrate_db

  log "Baibl setup complete on port $APP_PORT"
ZSH

# ============================================================
# 4. brgen_tv.sh - fix mangled multi-OS install_redis function
# ============================================================
path = File.join(DEPLOY_ROOT, "rails/brgen/brgen_tv.sh")
puts "Fixing: rails/brgen/brgen_tv.sh"
write_file(path, <<~'ZSH')
  #!/usr/bin/env zsh
  emulate -L zsh
  setopt err_return no_unset pipe_fail extended_glob

  # Brgen TV - Video streaming and live broadcasting platform
  # OpenBSD 7.8, Rails 8, port 10006

  APP_NAME="brgen_tv"
  BASE_DIR="${BASE_DIR:-/home/brgen/app}"
  SERVER_IP="${SERVER_IP:-185.52.176.18}"
  APP_PORT=10006
  SCRIPT_DIR="${0:A:h}"

  source "${SCRIPT_DIR}/../@shared_functions.sh"

  check_app_exists "$APP_NAME" "${BASE_DIR}/${APP_NAME}/app/models/video.rb" && exit 0

  log "Starting Brgen TV setup"

  command_exists "ruby"   || { print "ERROR: ruby not found" >&2; exit 1 }
  command_exists "node"   || { print "ERROR: node not found" >&2; exit 1 }
  command_exists "psql"   || { print "ERROR: psql not found" >&2; exit 1 }

  # Install Redis on OpenBSD
  install_redis_openbsd() {
    log "Installing Redis on OpenBSD"
    if ! pkg_info -q redis >/dev/null 2>&1; then
      doas pkg_add redis || { log "ERROR: Failed to install redis"; return 1 }
    fi
    doas rcctl enable redis
    doas rcctl start redis
    log "Redis installed and started"
  }

  install_redis_openbsd

  setup_full_app "$APP_NAME"

  install_gem "pagy"
  install_gem "faker"
  install_gem "aws-sdk-s3"

  setup_authentication
  setup_rate_limiting

  # Video models
  bin/rails generate model Video title:string description:text user:references status:string duration:integer url:string thumbnail:string 2>/dev/null || true
  bin/rails generate model Stream user:references title:string status:string stream_key:string:uniq viewers_count:integer 2>/dev/null || true
  bin/rails generate model VideoView video:references user:references watched_at:datetime 2>/dev/null || true
  bin/rails generate model Subscription subscriber:references{to_table:users} channel:references{to_table:users} 2>/dev/null || true

  migrate_db

  log "Brgen TV setup complete on port $APP_PORT"
ZSH

# ============================================================
# 5. openbsd.sh - it passes syntax check at line 103 fine,
#    the error was in a different spot. Re-check.
# ============================================================
path = File.join(DEPLOY_ROOT, "openbsd/openbsd.sh")
content = File.read(path)
result = `zsh -n #{path} 2>&1`
if result.empty?
  puts "openbsd/openbsd.sh: already clean after recheck"
else
  puts "openbsd/openbsd.sh: still has syntax error: #{result.strip}"
  puts "  (leaving for manual review - openbsd.sh is the server bootstrap script)"
  puts "  Error: #{result.lines.first.strip}"
end
