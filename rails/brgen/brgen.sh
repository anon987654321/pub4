#!/usr/bin/env zsh
set -euo pipefail

log() { print -r -- "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

readonly APP_NAME="brgen"
readonly APP_PORT=11006
readonly BASE_DIR="/home/dev/rails"
readonly APP_DIR="${BASE_DIR}/${APP_NAME}"

log "Starting BRGEN Rails 8 setup"

[[ -d "$APP_DIR" ]] && log "App exists, skipping" && exit 0

mkdir -p "$APP_DIR"
cd "$APP_DIR"

log "Creating Rails 8 app"
rails new . --skip-git --database=sqlite3 --css=propshaft --javascript=importmap

log "Configuring Gemfile"
cat >> Gemfile << 'EOF'
gem "solid_queue"
gem "solid_cache"
gem "solid_cable"
gem "falcon"
gem "falcon-rails"
gem "devise"
gem "devise-guests"
gem "stimulus_reflex"
gem "pagy"
gem "acts_as_tenant"
gem "faker"
EOF

bundle install

log "Installing Solid Stack"
bin/rails generate solid_queue:install
bin/rails generate solid_cache:install
bin/rails generate solid_cable:install

log "Installing authentication"
bin/rails generate authentication

log "Setting up Devise"
bin/rails generate devise:install
bin/rails generate devise User
bin/rails generate devise:guests

log "Installing StimulusReflex"
yarn add stimulus_reflex

log "Creating models"
bin/rails generate model Community name:string subdomain:string
bin/rails generate model Post title:string body:text user:references community:references
bin/rails generate model Comment body:text user:references post:references

log "Running migrations"
bin/rails db:migrate

log "Creating Falcon config"
cat > config/falcon.rb << 'FALCONEOF'
load :rack, :supervisor

hostname = File.basename(__dir__)
port = ENV.fetch("PORT", "11006")

supervisor

rack hostname do
  endpoint Async::HTTP::Endpoint.parse("http://0.0.0.0:#{port}")
end
FALCONEOF

log "Creating rc.d service"
cat | doas tee /etc/rc.d/brgen << 'RCEOF'
#!/bin/ksh
daemon="/usr/local/bin/bundle"
daemon_user="dev"
daemon_flags="exec falcon host"
. /etc/rc.d/rc.subr
rc_bg=YES
rc_reload=NO
pexp="falcon.*brgen"
rc_cmd $1
RCEOF

doas chmod +x /etc/rc.d/brgen
doas rcctl enable brgen

log "BRGEN setup complete"
log "Start with: doas rcctl start brgen"
