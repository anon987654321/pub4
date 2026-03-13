#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/brgen/app"
typeset -r PORT=11006

echo "==> [setup] Rails 8 app creation + gems"

[[ -d "$APP_DIR" ]] || { echo "ERROR: $APP_DIR missing. Run: doas zsh openbsd.sh --pre-point"; exit 1 }
cd "$APP_DIR"

if [[ ! -f "config/application.rb" ]]; then
  echo "Creating Rails 8 application"
  rails new . --database=postgresql --skip-git --css=tailwind --javascript=esbuild
fi

echo "Appending gems to Gemfile"
grep -q "solid_queue" Gemfile || cat >> Gemfile << 'GEMFILE'

# Rails 8 Solid Stack
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"

# Authentication
gem "bcrypt", "~> 3.1"

# Voting
gem "acts_as_votable"

# Real-time
gem "stimulus_reflex", "~> 3.5"
gem "cable_ready", "~> 5.0"

# Multi-tenancy
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

GEMFILE

bundle install
echo "==> [setup] done"
