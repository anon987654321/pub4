```zsh
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Blognet: Multi-blog platform with AI content generation

APP_NAME="blognet"

BASE_DIR="/home/dev/rails"

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

  # Find first available port in range
  while (( port <= max_port )); do
    if ! echo "$used_ports" | grep -q "^$port$"; then
      # Double check port is actually available
      if ! (echo >/dev/tcp/localhost/$port) 2>/dev/null; then
        echo $port
        return 0
      fi
    fi
    ((port++))
  done

  echo "No available ports found in range 3000-3999" >&2
  return 1
}

SCRIPT_DIR="${0:a:h}"

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
    "app/controllers/blogs_controller.rb:File"
    "config/database.yml:File"
    ".env:File"
  )

  for check in $checks; do
    local file=${check%%:*}
    local type=${check#*:}

    case $type in
      File)
        if [[ ! -f $file ]]; then
          echo "Missing required file: $file" >&2
          missing_config=1
        fi
        ;;
      Directory)
        if [[ ! -d $file ]]; then
          echo "Missing required directory: $file" >&2
          missing_config=1
        fi
        ;;
    esac
  done

  return $missing_config
}

# Database connection check using rails runner
check_database_connection() {
  if ! rails runner "ActiveRecord::Base.connection; puts 'Database connection successful'" 2>/dev/null; then
    echo "Database connection failed" >&2
    return 1
  fi
  return 0
}

# Environment variable check using simple validation
check_environment_variables() {
  local required_vars=(
    "DATABASE_URL"
    "REDIS_URL"
    "SECRET_KEY_BASE"
  )

  for var in $required_vars; do
    if [[ -z ${(P)var} ]]; then
      echo "Missing environment variable: $var" >&2
      return 1
    fi
  done
  return 0
}

# Placeholder functions for setup tasks
setup_database() {
  echo "Setting up database..."
  rails db:create db:migrate
}

setup_environment() {
  echo "Setting up environment variables..."
  # Generate secret key base if not set
  if [[ -z $SECRET_KEY_BASE ]]; then
    export SECRET_KEY_BASE=$(rails secret)
    echo "Generated SECRET_KEY_BASE"
  fi
}

run_setup_tasks() {
  echo "Running additional setup tasks..."
  # Add any additional setup tasks here
}

# Generate model if missing
generate_model_if_missing() {
  local model_file="app/models/$1.rb"
  if [[ ! -f $model_file ]]; then
    echo "Generating model $1..."
    rails generate model $1
  fi
}
```
