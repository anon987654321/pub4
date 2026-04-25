#!/usr/bin/env bash
set -euo pipefail

# Deployment script for Rails voting system
# Usage: ./DEPLOY/rails/voting_system.sh [environment]

# Default environment
ENVIRONMENT=${1:-production}

# Application directory
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIR"

# Load environment variables if file exists
if [[ -f ".env.$ENVIRONMENT" ]]; then
  export $(grep -v '^#' ".env.$ENVIRONMENT" | xargs)
fi

# Function to display status
status() {
  echo -e "\033[1;34m[DEPLOY] $*\033[0m"
}

# Function to display error and exit
error() {
  echo -e "\033[1;31m[ERROR] $*\033[0m" >&2
  exit 1
}

# Check required commands
for cmd in ruby bundle rails; do
  command -v "$cmd" >/dev/null 2>&1 || error "Required command not found: $cmd"
done

status "Starting deployment for environment: $ENVIRONMENT"

# Install dependencies
status "Installing Ruby dependencies"
bundle check || bundle install --jobs 4 --retry 3

# Database setup
status "Preparing database"
bundle exec rails db:create db:migrate

# Asset compilation
status "Precompiling assets"
bundle exec rails assets:precompile

# Start server (adjust for your production server)
case "$ENVIRONMENT" in
  production)
    status "Starting Puma server in production"
    bundle exec puma -C config/puma.rb
    ;;
  staging)
    status "Starting Puma server in staging"
    bundle exec puma -C config/puma_staging.rb
    ;;
  development|test)
    status "Starting Rails server in $ENVIRONMENT"
    bundle exec rails server -b 0.0.0.0
    ;;
  *)
    error "Unknown environment: $ENVIRONMENT"
    ;;
esac

status "Deployment completed successfully"