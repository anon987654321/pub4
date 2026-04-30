#!/usr/bin/env zsh
# @shared_functions.sh — shared helpers for DEPLOY/rails/* scripts
# Source this file; do not execute directly.
# Requires: zsh, ruby34, bundle, rails, doas
set -euo pipefail

PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}"

if command -v doas >/dev/null 2>&1; then
  _PRIV=doas
else
  _PRIV=sudo
fi

: "${APP_PORT:=3000}"

log()      { print -P "%F{cyan}==>%f $*"; }
log_ok()   { print -P "%F{green}ok%f $*"; }
log_warn() { print -P "%F{yellow}WARN%f $*" >&2; }
log_err()  { print -P "%F{red}ERR%f $*" >&2; }

need_cmd() {
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || { log_err "Required: $cmd"; exit 1; }
    log_ok "$cmd found"
  done
}

already_done() {
  local sentinel=$1
  [[ -f $sentinel ]] && { log_warn "Already set up ($sentinel exists). Skipping."; return 0; }
  return 1
}

create_rails_app() {
  local app_dir=$1
  mkdir -p "${app_dir:h}"
  if [[ ! -f "${app_dir}/config/application.rb" ]]; then
    log "Creating Rails 8 app at $app_dir"
    rails new "$app_dir" \
      --database=sqlite3 \
      --asset-pipeline=propshaft \
      --javascript=importmap \
      --skip-git \
      --skip-test
  fi
  cd "$app_dir"
  log_ok "Working in: $app_dir"
}

add_gem() {
  local gem=$1 ver=${2:-}
  if ! grep -q "\"${gem}\"" Gemfile 2>/dev/null; then
    if [[ -n $ver ]]; then
      print "gem \"${gem}\", \"${ver}\"" >> Gemfile
    else
      print "gem \"${gem}\"" >> Gemfile
    fi
    bundle install --quiet
    log_ok "gem ${gem} added"
  else
    log_ok "gem ${gem} already present"
  fi
}

add_gem_group() {
  local groups=$1; shift
  local -a gems=("$@")
  if ! grep -q "gem \"${gems[1]}\"" Gemfile 2>/dev/null; then
    {
      print "group :${groups//,/, :} do"
      for g in "${gems[@]}"; do print "  gem \"$g\""; done
      print "end"
    } >> Gemfile
    bundle install --quiet
  fi
}

install_solid_stack() {
  log "Installing Solid Cache / Queue / Cable"
  add_gem solid_cache
  add_gem solid_queue
  add_gem solid_cable
  bin/rails solid_cache:install 2>/dev/null || true
  bin/rails solid_queue:install 2>/dev/null || true
  bin/rails solid_cable:install 2>/dev/null || true
  log_ok "Solid stack installed"
}

install_auth() {
  if [[ ! -f app/models/session.rb ]]; then
    log "Generating Rails 8 authentication"
    bin/rails generate authentication
    bin/rails db:migrate
  else
    log_ok "Authentication already generated"
  fi
}

install_active_storage() {
  if [[ -z $(print db/migrate/*create_active_storage*(N)) ]]; then
    log "Installing Active Storage"
    bin/rails active_storage:install
    bin/rails db:migrate
  else
    log_ok "Active Storage already installed"
  fi
}

install_action_text() {
  if [[ -z $(print db/migrate/*create_action_text*(N)) ]]; then
    log "Installing Action Text"
    bin/rails action_text:install
    bin/rails db:migrate
  else
    log_ok "Action Text already installed"
  fi
}

db_setup() {
  log "Setting up database"
  RAILS_ENV=production bin/rails db:create db:migrate
  log_ok "Database ready"
}

db_migrate() {
  RAILS_ENV=${RAILS_ENV:-production} bin/rails db:migrate
  log_ok "Migrations complete"
}

configure_production() {
  local cfg=config/environments/production.rb
  grep -q 'force_ssl' "$cfg" || print '  config.force_ssl = true' >> "$cfg"
  grep -q 'solid_cache' "$cfg" || print '  config.cache_store = :solid_cache_store' >> "$cfg"
  log_ok "Production config updated"
}

install_security_tools() {
  add_gem_group "development,test" brakeman rubocop-rails-omakase
  log_ok "Security tools added"
}

write_base_css() {
  mkdir -p app/assets/stylesheets
  cat > app/assets/stylesheets/application.css << 'CSS'
:root {
  --bg: #0a0a0a; --surface: #1a1a1a; --text: #e8eaed;
  --text-dim: #9aa0a6; --primary: #8ab4f8; --accent: #ff4500;
  --radius: 8px; --space: 8px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: system-ui, sans-serif; background: var(--bg); color: var(--text); line-height: 1.6; }
main { max-width: 1200px; margin: 0 auto; padding: calc(var(--space)*2); }
a { color: var(--primary); text-decoration: none; }
a:hover { text-decoration: underline; }
.card { background: var(--surface); border-radius: var(--radius); padding: calc(var(--space)*2); margin-bottom: calc(var(--space)*2); }
.btn { display: inline-block; padding: .4rem 1rem; border-radius: var(--radius); border: none; cursor: pointer; font-size: .9rem; }
.btn-primary { background: var(--primary); color: #000; }
.btn-danger  { background: #c62828; color: #fff; }
.flash-notice { background: #1a3a1a; color: #81c784; padding: .75rem 1rem; border-radius: var(--radius); margin-bottom: 1rem; }
.flash-alert  { background: #3a1a1a; color: #e57373; padding: .75rem 1rem; border-radius: var(--radius); margin-bottom: 1rem; }
@media (max-width: 768px) { main { padding: var(--space); } }
CSS
  log_ok "Base CSS written"
}

write_layout() {
  local app_title=${1:-App}
  mkdir -p app/views/layouts
  cat > app/views/layouts/application.html.erb << LAYOUT
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title><%= content_for?(:title) ? yield(:title) + " – ${app_title}" : "${app_title}" %></title>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>
</head>
<body>
<% if notice %><div class="flash-notice"><%= notice %></div><% end %>
<% if alert  %><div class="flash-alert"><%= alert  %></div><% end %>
<main><%= yield %></main>
</body>
</html>
LAYOUT
  log_ok "Layout written"
}

install_rcd() {
  local svc=$1 app_dir=$2 port=$3 user=$4
  local rcd="/etc/rc.d/${svc}"
  [[ -f $rcd ]] && { log_ok "rc.d/${svc} already exists"; return 0; }
  $_PRIV tee "$rcd" > /dev/null << EOS
#!/bin/ksh
daemon="${app_dir}/bin/puma"
daemon_flags="-C ${app_dir}/config/puma.rb -e production"
daemon_user="${user}"
. /etc/rc.d/rc.subr
rc_cmd \$1
EOS
  $_PRIV chmod 755 "$rcd"
  $_PRIV rcctl enable "$svc"
  log_ok "rc.d/${svc} installed"
}

relayd_add_relay() {
  local host=$1 port=$2
  local table="${host%%.*}"
  local conf=/etc/relayd.conf
  grep -q "table <${table}>" "$conf" 2>/dev/null && { log_ok "relayd <${table}> exists"; return 0; }
  $_PRIV tee -a "$conf" > /dev/null << EOS

table <${table}> { 127.0.0.1 }
relay "${table}_http" {
  listen on 0.0.0.0 port 80
  forward to <${table}> port ${port} check tcp
}
EOS
  log_ok "relayd table <${table}> -> :${port} added"
}

write_puma_config() {
  local port=${1:-3000}
  cat > config/puma.rb << PUMA
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count
worker_timeout 3600 if ENV.fetch("RAILS_ENV", "development") == "development"
port ENV.fetch("PORT") { ${port} }
environment ENV.fetch("RAILS_ENV") { "development" }
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }
plugin :tmp_restart
PUMA
  log_ok "Puma config written"
}

install_thruster() {
  add_gem thruster
  log_ok "Thruster added"
}
