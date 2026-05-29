#!/usr/bin/env sh
set -eu
set -o pipefail

APP_DIR="/home/brgen/app"
PORT=11006

printf '==> [setup] Rails 8 app creation + gems\n'

# Ensure prerequisite directory exists
if [ ! -d "$APP_DIR" ]; then
  printf 'ERROR: %s missing. Run: doas sh openbsd.sh --pre-point\n' "$APP_DIR" >&2
  exit 1
fi

cd "$APP_DIR"

# Verify Rails is available
if ! command -v rails >/dev/null 2>&1; then
  printf 'ERROR: rails executable not found in PATH\n' >&2
  exit 1
fi

# Initialise Rails app if missing
if [ ! -f "config/application.rb" ]; then
  printf 'Creating Rails 8 application\n'
  rails new . \
    --database=postgresql \
    --skip-git \
    --css=tailwind \
    --javascript=esbuild
fi

printf 'Appending gems to Gemfile\n'

# Append required gems once
if ! grep -q "solid_queue" Gemfile; then
  cat >> Gemfile <<'EOF'

# Rails 8 Solid Stack
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"

# Authentication
gem "bcrypt", "~> 3.1"

# Voting
gem "acts_as_votable"

# Real‑time
gem "stimulus_reflex", "~> 3.5"
gem "cable_ready", "~> 5.0"

# Multi‑tenancy
gem "devise"
gem "devise-guests"
gem "acts_as_tenant"

# Features
gem "pagy"
gem "image_processing"
gem "geocoder"
gem "langchainrb"
gem "ruby-openai"
gem "serviceworker-rails"

group :development, :test do
  gem "brakeman"
  gem "rubocop-rails-omakase"
  gem "faker"
end
EOF
fi

# Install missing gems quietly
if ! bundle check >/dev/null 2>&1; then
  bundle install --quiet
fi

printf '==> [setup] done\n'
