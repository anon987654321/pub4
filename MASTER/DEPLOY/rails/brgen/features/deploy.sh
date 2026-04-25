#!/usr/bin/env sh
set -euo pipefail

# Deploy script for brgen Rails application
# Follows OpenBSD-first principles and Master project axioms

APP_DIR="/var/www/brgen"
REPO_URL="git@github.com:brgen/brgen.git"
BRANCH="main"
SERVICE_NAME="master"

# Ensure we're running as root (adjust if needed)
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Change to application directory
cd "$APP_DIR"

# Fetch latest code
git fetch origin "$BRANCH"
git reset --hard "origin/$BRANCH"

# Install dependencies
bundle install --deployment --without development test

# Database migration
bundle exec rails db:migrate RAILS_ENV=production

# Precompile assets
bundle exec rails assets:precompile RAILS_ENV=production

# Restart service
rcctl restart "$SERVICE_NAME"

echo "Deployment completed successfully"