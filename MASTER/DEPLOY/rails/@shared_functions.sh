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

install_dartsass() {
  add_gem dartsass-rails
  bin/rails dartsass:install 2>/dev/null || true
  log_ok "Dart Sass installed"
}

write_base_scss() {
  mkdir -p app/assets/stylesheets
  rm -f app/assets/stylesheets/application.css
  cat > app/assets/stylesheets/application.scss << 'SCSS'
// ==================== VARIABLES ====================
:root {
  // Colors
  --color-black: #000;
  --color-white: #fff;
  --color-extra-light-grey: #f0f0f0;

  // Spacing
  --space-xs: 0.25rem;
  --space-sm: 0.5rem;
  --space-md: 1rem;
  --space-lg: 1.5rem;
  --space-xl: 2rem;

  // Typography
  --font-size-base: 14px;
  --line-height-base: 1.5;
}

// ==================== RESET & BASE ====================
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html,
body {
  height: 100%;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
  font-size: var(--font-size-base);
  line-height: var(--line-height-base);
  color: var(--color-black);
  background-color: var(--color-white);
  display: flex;
  flex-direction: column;
}

img { max-width: 100%; display: block; }

a {
  color: #4285f4;
  text-decoration: none;
  cursor: pointer;

  &:hover { text-decoration: underline; }
  &:focus { outline: 2px solid #4285f4; outline-offset: 2px; }
}

// ==================== HEADER ====================
.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: var(--space-md);
  border-bottom: 1px solid var(--color-extra-light-grey);

  &__tabs {
    display: flex;
    gap: var(--space-md);
  }

  &__tab {
    padding: var(--space-xs) var(--space-md);
    cursor: pointer;
    border: none;
    background: transparent;
    font-size: inherit;
    font-family: inherit;

    &:hover { background-color: var(--color-extra-light-grey); }
  }
}

// ==================== MAIN ====================
main {
  flex: 1;
  display: grid;
  grid-template-columns: 1fr;
  gap: var(--space-md);
  padding: var(--space-md);
}

// ==================== FLASH ====================
.flash {
  padding: var(--space-sm) var(--space-md);
  border-bottom: 1px solid var(--color-extra-light-grey);

  &--error, &--alert { color: #c00; }
  &--notice { color: #060; }
}

// ==================== RESPONSIVE ====================
@media (max-width: 768px) {
  .header {
    flex-direction: column;
    gap: var(--space-md);
    padding: var(--space-sm);

    &__tabs {
      gap: var(--space-sm);
      flex-wrap: wrap;
      justify-content: center;
    }
  }
}

@media (max-width: 480px) {
  html, body { font-size: 12px; }

  .header__tabs { gap: var(--space-xs); }
  .header__tab { padding: var(--space-xs) var(--space-sm); font-size: 0.9em; }
}
SCSS
  log_ok "application.scss written"
}

write_base_css() { write_base_scss; }

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
daemon="/usr/local/bin/bundle"
daemon_flags="exec env RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 falcon serve --bind http://127.0.0.1:${port}"
daemon_user="${user}"
daemon_execdir="${app_dir}"
daemon_timeout="60"
. /etc/rc.d/rc.subr
pexp="ruby.*${port}"
rc_bg=YES
rc_reload=NO
rc_cmd \$1
EOS
  $_PRIV chmod 755 "$rcd"
  $_PRIV rcctl enable "$svc"
  log_ok "rc.d/${svc} installed (falcon on :${port})"
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

write_falcon_config() {
  local port=${1:-3000}
  add_gem falcon
  cat > config/falcon.rb << FALCON
#!/usr/bin/env -S falcon host
# frozen_string_literal: true

load :rack, :supervisor

hostname = File.basename(__dir__)
port = ENV.fetch("PORT", ${port}).to_i

rack hostname do
  endpoint Async::HTTP::Endpoint.parse("http://0.0.0.0:\#{port}")
end
FALCON
  log_ok "Falcon config written (:${port})"
}

install_thruster() {
  add_gem thruster
  log_ok "Thruster added"
}
