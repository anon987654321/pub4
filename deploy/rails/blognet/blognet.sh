```zsh
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Blognet: Multi-blog platform with AI content generation

APP_NAME="blognet"

BASE_DIR="/home/dev/rails"

SERVER_IP="185.52.176.18"

# Efficient port finding using multiple methods for compatibility
find_available_port() {
  local port=3000
  local max_port=3999

  # Try ss first, fall back to netstat, then lsof
  local used_ports
  if command -v ss >/dev/null 2>&1; then
    used_ports=$(ss -tuln 2>/dev/null | awk 'NR>1 {split($5, a, ":"); print a[length(a)]}' | sort -un)
  elif command -v netstat >/dev/null 2>&1; then
    used_ports=$(netstat -tuln 2>/dev/null | awk '$1 ~ /^(tcp|udp)/ {split($4, a, ":"); print a[length(a)]}' | sort -un)
  elif command -v lsof >/dev/null 2>&1; then
    used_ports=$(lsof -i -P -n 2>/dev/null | grep LISTEN | awk '{print $9}' | awk -F: '{print $NF}' | sort -un)
  else
    # Fallback: use a simple test approach
    while (( port <= max_port )); do
      if ! (echo >/dev/tcp/localhost/$port) 2>/dev/null; then
        echo $port
        return 0
      fi
      ((port++))
    done
    echo "No available ports found in range 3000-3999" >&2
    return 1
  fi

 # Double check port is actually available
      if ! (echo >/dev/tcp/localhost/$port) 2>/dev/null; then
        echo $port
        return 0
      fi
    fi
    ((port++))
  done

  echo "No available ports
}

SCRIPT_DIR="${0:a:h}"

source "${SCRIPT_DIR}/ >&2; exit 1; }

# Define missing setup function
setup_full_app() {
  echo "Setting up full application configuration..."

  # Check and setup database
  if ! check_database_configured; then
    setup_database
  fi

  # Check environment variables
  if ! check_environment_variables; then
    setup_environment
  fi

  # Run additional setup tasks
  run_setup_tasks
}

# Enhanced idempotency check with comprehensive validation
check_app_configured() {
  local missing_config=0
  local checks=(
    "app/models/blog.rb:File"
    "app/models/database.yml:File"
    ".env:File"
    "app/controllers/application_controller.rb:PagyBackend"
    "app/ for check in $checks; do
    local target=${check% in
      File)
        if [[ ! -f "$target" ]]; then
          echo "Missing: $target" >&2
          if [[ -f "$target" ]] && ! grep -q "include Pagy::Backend" "$target" 2>/dev/null; then
          echo "Missing: Pagy::Backend include in $target" -q "include Pagy::Frontend" "$target" 2>/dev/null; then
          echo "Missing: Pagy::Frontend include in $target" >&2
          missing_config=1
        fi
        ;;
      Gem)
        if ! bundle list | grep -q "$target" >/dev/null 2>&1; then
          echo "Missing: $target gem" >&2
          missing_config=1
        fi
        ;;
    esac
  done

  # Additional database connectivity check
  if ! check_database_connection; then
    echo "Database connection failed" >&2
    missing_config=1
  fi

  return $missing_config
}

# Helper functions for comprehensive setup
check_database_configured() {
  [[ -f "config/database.yml" ]] && \
  [[ -f ".env" ]] && \
  grep -q "DATABASE_URL\|DB_" .env 2>/dev/null
}

check_database_connection() {
  if command -v rails >/dev/null 2>&1; then
    rails db:version >/dev/null 2>&1
    return $?
  fi
  return 1
}

check_environment_variables() {
  [[ -f ".env" ]] && \
  { grep -q "SECRET_KEY_BASE\|RAILS_ENV\|DATABASE_URL" .env 2>/dev/null || \
    export | grep -q "SECRET_KEY_BASE\|RAILS_ENV\|DATABASE_URL"; }
}

setup_database() {
  echo "Configuring database..."
  # Add database setup logic here
}

setup_environment() {
  echo "Setting up environment variables..."
  # Add environment setup logic here
}

run_setup_tasks() {
  echo "Running additional setup tasks..."
  # Add any additional setup tasks here
}

# Fixed model generation function with proper arguments
generate_model_if_missing() {
  local model_name=$1
  local model_file="app/models/${model_name}.rb"

  if [[ ! -f "$model_file" ]]; then
    echo "Generating model: $model_name"
    if command -v rails >/dev/null 2>&1; then
      rails generate model $model_name
    else
      echo "Error: Rails not available to generate model $model_name" >&2
      return 1
    fi
  fi
}
```
