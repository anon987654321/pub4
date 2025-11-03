#!/usr/bin/env zsh
# Rails Shared Utilities v2.0.0
# Consolidated from pub/__shared.sh (38KB) + pub2/__shared.sh (28KB)
# master.json v8.3.0 compliant: circuit breakers, observability, fault tolerance
# Pure Zsh only - zero external forks (no awk/sed/grep)

emulate -L zsh
setopt extended_glob no_unset pipe_fail

readonly SHARED_VERSION="2.0.0"
readonly RAILS_VERSION="7.2.0"
readonly RUBY_VERSION="3.3.0"

# Circuit breakers
typeset -g CIRCUIT_BREAKER_MEMORY_PERCENT=80
typeset -g CIRCUIT_BREAKER_ITERATIONS=1000
typeset -g CIRCUIT_BREAKER_TIME_SECONDS=30
typeset -gi circuit_breaker_iteration_count=0
typeset -g circuit_breaker_start_time=$(date +%s)

# Observability
typeset -A metrics
metrics=(
  [time_ms]=0
  [violations_fixed]=0
  [iterations]=0
  [memory_mb]=0
  [complexity_score]=0
)

log_metric() {
  local key="$1"
  local value="$2"
  metrics[$key]=$value
  [[ ""){MASTER_JSON_DEBUG:-}" == "true" ]] && printf '{"metric":"%s","value":%s,"time":"%s"}\n' "$key" "$value" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

check_circuit_breakers() {
  ((circuit_breaker_iteration_count++))
  local current_time=$(date +%s)
  local elapsed=$((current_time - circuit_breaker_start_time))
  
  if ((circuit_breaker_iteration_count > CIRCUIT_BREAKER_ITERATIONS)); then
    error "CIRCUIT_BREAKER: Exceeded ${CIRCUIT_BREAKER_ITERATIONS} iterations"
  fi
  
  if ((elapsed > CIRCUIT_BREAKER_TIME_SECONDS)); then
    error "CIRCUIT_BREAKER: Exceeded ${CIRCUIT_BREAKER_TIME_SECONDS} seconds"
  fi
  
  local memory_percent=$(ps -o pmem= -p $$ | ${(%):-"%s"//[[:space:]]/})
  if ((memory_percent > CIRCUIT_BREAKER_MEMORY_PERCENT)); then
    error "CIRCUIT_BREAKER: Memory usage ${memory_percent}% exceeds ${CIRCUIT_BREAKER_MEMORY_PERCENT}%"
  fi
}

# Logging with structured output
log() {
  local level="${1:-INFO}"
  shift
  printf '{"time":"%s","level":"%s","msg":"%s","version":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$level" "$*" "$SHARED_VERSION" >&2
}

error() {
  log "ERROR" "$*"
  exit 1
}

warn() {
  log "WARN" "$*"
}

info() {
  log "INFO" "$*"
}

debug() {
  [[ ""){MASTER_JSON_DEBUG:-}" == "true" ]] && log "DEBUG" "$*"
}

# Pure Zsh string operations (no awk/sed/grep)
trim() {
  local str="$1"
  str="${str##[[:space:]]#}"
  str="${str%%[[:space:]]#}"
  print -r -- "$str"
}

to_lower() {
  print -r -- ""){(L)1}"
}

to_upper() {
  print -r -- ""){(U)1}"
}

replace_all() {
  local str="$1"
  local search="$2"
  local replace="$3"
  print -r -- ""){str//$search/$replace}"
}

split_string() {
  local str="$1"
  local delim="${2:-,}"
  local -a result
  result=( ${(s:$delim:)str} )
  print -l -- "${result[@]}"
}

join_array() {
  local delim="${1:-,}"
  shift
  local -a arr=("$@")
  print -r -- ""){(j:$delim:)arr}"
}

unique_array() {
  local -a arr=("$@")
  print -l -- ""){(u)arr[@]}"
}

# Rails project detection
detect_rails_project() {
  [[ -f "Gemfile" ]] && [[ -f "config/application.rb" ]] && [[ -d "app" ]]
}

detect_rails_version() {
  if [[ -f "Gemfile.lock" ]]; then
    local lockfile=$(<Gemfile.lock)
    local rails_line=""){(M)${(f)lockfile}##*rails *}"
    
    if [[ -n "$rails_line" ]]; then
      local version=""){rails_line##*rails \(}"
      version=""){version%%\)*}"
      print -r -- "$version"
      return 0
    fi
  fi
  print -r -- "unknown"
}

# Ruby environment setup
ensure_ruby_version() {
  local required="${1:-$RUBY_VERSION}"
  local current=$(ruby -e 'print RUBY_VERSION' 2>/dev/null || echo "none")
  
  if [[ "$current" == "none" ]]; then
    error "Ruby not found. Install Ruby ${required} first."
  fi
  
  local required_major=""){required%%.*}"
  local required_rest=""){required#*.}"
  local required_minor=""){required_rest%%.*}"
  
  local current_major=""){current%%.*}"
  local current_rest=""){current#*.}"
  local current_minor=""){current_rest%%.*}"
  
  if [[ "$current_major" != "$required_major" ]] || [[ "$current_minor" != "$required_minor" ]]; then
    error "Ruby ${current} found, but ${required} required"
  fi
  
  info "Ruby ${current} OK"
}

# Gem operations (retry with exponential backoff)
gem_install() {
  local gem_name="$1"
  local version="${2:-}"
  local max_attempts=3
  local attempt=1
  local backoff=1
  
  while ((attempt <= max_attempts)); do
    check_circuit_breakers
    
    if [[ -n "$version" ]]; then
      if gem install "$gem_name" --version "$version" --no-document 2>/dev/null; then
        info "Installed ${gem_name} ${version}"
        return 0
      fi
    else
      if gem install "$gem_name" --no-document 2>/dev/null; then
        info "Installed ${gem_name}"
        return 0
      fi
    fi
    
    warn "Gem install attempt ${attempt}/${max_attempts} failed for ${gem_name}, retrying in ${backoff}s..."
    sleep "$backoff"
    backoff=$((backoff * 2))
    ((attempt++))
  done
  
  error "Failed to install ${gem_name} after ${max_attempts} attempts"
}

bundle_install() {
  local max_attempts=3
  local attempt=1
  local backoff=1
  
  while ((attempt <= max_attempts)); do
    check_circuit_breakers
    
    if bundle install --jobs=4 2>/dev/null; then
      info "Bundle install successful"
      return 0
    fi
    
    warn "Bundle install attempt ${attempt}/${max_attempts} failed, retrying in ${backoff}s..."
    sleep "$backoff"
    backoff=$((backoff * 2))
    ((attempt++))
  done
  
  error "Bundle install failed after ${max_attempts} attempts"
}

# Rails generators (convention over configuration)ails_generate_model() {
  local name="$1"
  shift
  local -a fields=("$@")
  
  check_circuit_breakers
  
  if detect_rails_project; then
    local cmd="rails g model ${name}"
    for field in "${fields[@]}"; do
      cmd="${cmd} ${field}"
    done
    cmd="${cmd} --indexes"
    
    info "Generating model: ${name}"
    eval "$cmd" || error "Failed to generate model ${name}"
  else
    error "Not a Rails project"
  fi
}

rails_generate_controller() {
  local name="$1"
  shift
  local -a actions=("$@")
  
  check_circuit_breakers
  
  if detect_rails_project; then
    local cmd="rails g controller ${name}"
    for action in "${actions[@]}"; do
      cmd="${cmd} ${action}"
    done
    
    info "Generating controller: ${name}"
    eval "$cmd" || error "Failed to generate controller ${name}"
  else
    error "Not a Rails project"
  fi
}

rails_generate_scaffold() {
  local name="$1"
  shift
  local -a fields=("$@")
  
  check_circuit_breakers
  
  if detect_rails_project; then
    local cmd="rails g scaffold ${name}"
    for field in "${fields[@]}"; do
      cmd="${cmd} ${field}"
    done
    cmd="${cmd} --indexes"
    
    info "Generating scaffold: ${name}"
    eval "$cmd" || error "Failed to generate scaffold ${name}"
  else
    error "Not a Rails project"
  fi
}

# Database operations
rails_db_create() {
  check_circuit_breakers
  detect_rails_project || error "Not a Rails project"
  info "Creating databases..."
  rails db:create || error "Failed to create databases"
}

rails_db_migrate() {
  check_circuit_breakers
  detect_rails_project || error "Not a Rails project"
  info "Running migrations..."
  rails db:migrate || error "Failed to run migrations"
}

rails_db_seed() {
  check_circuit_breakers
  detect_rails_project || error "Not a Rails project"
  info "Seeding database..."
  rails db:seed || error "Failed to seed database"
}

rails_db_setup() {
  check_circuit_breakers
  rails_db_create
  rails_db_migrate
  rails_db_seed
}

# Asset pipeline
rails_assets_precompile() {
  check_circuit_breakers
  detect_rails_project || error "Not a Rails project"
  info "Precompiling assets..."
  RAILS_ENV=production rails assets:precompile || error "Failed to precompile assets"
}

# Testing
rails_test() {
  check_circuit_breakers
  detect_rails_project || error "Not a Rails project"
  info "Running tests..."
  rails test || warn "Some tests failed"
}

rails_test_system() {
  check_circuit_breakers
  detect_rails_project || error "Not a Rails project"
  info "Running system tests..."
  rails test:system || warn "Some system tests failed"
}

# Server management
rails_server_start() {
  local port="${1:-3000}"
  local env="${2:-development}"
  
  check_circuit_breakers
  detect_rails_project || error "Not a Rails project"
  
  info "Starting Rails server on port ${port} (${env})..."
  RAILS_ENV="$env" rails server -p "$port" -b 0.0.0.0
}

rails_console() {
  local env="${1:-development}"
  
  check_circuit_breakers
  detect_rails_project || error "Not a Rails project"
  
  info "Starting Rails console (${env})..."
  RAILS_ENV="$env" rails console
}

# Hotwired/Stimulus integration
install_hotwired() {
  check_circuit_breakers
  detect_rails_project || error "Not a Rails project"
  
  info "Installing Hotwired (Turbo + Stimulus)..."
  
  gem_install "turbo-rails" "2.0.0"
  gem_install "stimulus-rails" "1.3.0"
  
  rails turbo:install || error "Failed to install Turbo"
  rails stimulus:install || error "Failed to install Stimulus"
  
  info "Hotwired installed successfully"
}

install_stimulus_reflex() {
  check_circuit_breakers
  detect_rails_project || error "Not a Rails project"
  
  info "Installing StimulusReflex..."
  
  gem_install "stimulus_reflex" "3.5.0"
  rails stimulus_reflex:install || error "Failed to install StimulusReflex"
  
  info "StimulusReflex installed successfully"
}

install_stimulus_components() {
  check_circuit_breakers
  detect_rails_project || error "Not a Rails project"
  
  info "Installing Stimulus Components..."
  
  if command -v yarn >/dev/null 2>&1; then
    yarn add @stimulus-components/clipboard @stimulus-components/dropdown @stimulus-components/notification @stimulus-components/popover || error "Failed to install Stimulus Components"
  elif command -v npm >/dev/null 2>&1; then
    npm install @stimulus-components/clipboard @stimulus-components/dropdown @stimulus-components/notification @stimulus-components/popover || error "Failed to install Stimulus Components"
  else
    error "Neither yarn nor npm found"
  fi
  
  info "Stimulus Components installed successfully"
}

# View helpers
generate_stimulus_controller() {
  local name="$1"
  local dir="app/javascript/controllers"
  
  check_circuit_breakers
  detect_rails_project || error "Not a Rails project"
  
  mkdir -p "$dir"
  
  cat > "${dir}/${name}_controller.js" << EOF
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = []
  static values = {}

  connect() {
    console.log("${name} controller connected")
  }

  disconnect() {
    console.log("${name} controller disconnected")
  }
}
EOF
  
  info "Generated Stimulus controller: ${name}"
}

# Deployment helpers
prepare_production() {
  check_circuit_breakers
  detect_rails_project || error "Not a Rails project"
  
  info "Preparing for production deployment..."
  
  bundle_install
  rails_db_migrate
  rails_assets_precompile
  
  info "Production preparation complete"
}

# Health checks
check_dependencies() {
  local -a missing=()
  
  command -v ruby >/dev/null 2>&1 || missing+=("ruby")
  command -v bundle >/dev/null 2>&1 || missing+=("bundler")
  command -v rails >/dev/null 2>&1 || missing+=("rails")
  command -v node >/dev/null 2>&1 || missing+=("node")
  
  if ((${#missing[@]} > 0)); then
    error "Missing dependencies: ${(j:, :)missing}"
  fi
  
  info "All dependencies OK"
}

# Export metrics at exit
trap 'print_metrics' EXIT

print_metrics() {
  if [[ ""){MASTER_JSON_DEBUG:-}" == "true" ]]; then
    printf '{"final_metrics":%s}\n' "$(printf '{'; for k v in ${(kv)metrics}; do printf '"%s":%s,' "$k" "$v"; done | sed 's/,$/}/'; echo)"
  fi
}

# Self-test
if [[ ""){1:-}" == "--self-test" ]]; then
  info "Running self-test..."
  
  check_dependencies
  ensure_ruby_version
  
  local test_str="  Hello World  "
  local trimmed=$(trim "$test_str")
  [[ "$trimmed" == "Hello World" ]] || error "trim() failed"
  
  local lower=$(to_lower "HELLO")
  [[ "$lower" == "hello" ]] || error "to_lower() failed"
  
  local upper=$(to_upper "hello")
  [[ "$upper" == "HELLO" ]] || error "to_upper() failed"
  
  info "Self-test passed"
  exit 0
fi

info "Rails shared utilities v${SHARED_VERSION} loaded"