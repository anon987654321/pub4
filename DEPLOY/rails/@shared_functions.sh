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
    log_ok "gem ${gem} added"
  else
    log_ok "gem ${gem} already present"
  fi
  bundle check 2>/dev/null || bundle install --quiet
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

// ==================== NAV ====================
nav {
  display: flex;
  align-items: center;
  gap: var(--space-md);
  padding: var(--space-sm) var(--space-md);
  border-bottom: 1px solid var(--color-extra-light-grey);

  a { color: inherit; }
  a:hover { text-decoration: underline; }
  .brand { font-weight: 700; margin-right: auto; }
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
write_layout()     { write_full_layout "$@"; }

install_rcd() {
  local svc=$1 app_dir=$2 port=$3 user=$4
  local rcd="/etc/rc.d/${svc}"
  [[ -f $rcd ]] && { log_ok "rc.d/${svc} already exists"; return 0; }
  local secret
  secret=$(ruby34 -e 'require "securerandom"; print SecureRandom.hex(64)')
  $_PRIV tee "$rcd" > /dev/null << EOS
#!/bin/ksh
daemon="/usr/local/bin/bundle"
daemon_flags="exec env RAILS_ENV=production SECRET_KEY_BASE=${secret} falcon serve --bind http://127.0.0.1:${port}"
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

# ── Stimulus + Importmap ────────────────────────────────────────────────────

setup_stimulus() {
  log "Setting up Stimulus"
  bin/importmap pin @hotwired/stimulus --download 2>/dev/null || true
  mkdir -p app/javascript/controllers
  cat > app/javascript/controllers/application.js << 'JS'
import { Application } from "@hotwired/stimulus"
const application = Application.start()
application.debug = false
window.Stimulus = application
export { application }
JS
  cat > app/javascript/controllers/index.js << 'JS'
import { application } from "./application"
// controllers are auto-imported via eagerLoadControllersFrom in application.js
// or listed here explicitly:
JS
  cat >> app/javascript/application.js << 'JS'

import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
JS
  log_ok "Stimulus ready"
}

write_stimulus_controller() {
  local name=$1
  mkdir -p app/javascript/controllers
  cat > "app/javascript/controllers/${name}_controller.js"
  log_ok "Stimulus ${name}_controller.js written"
}

# ── Pagy ───────────────────────────────────────────────────────────────────

setup_pagy() {
  add_gem pagy '"~> 9.3"'
  mkdir -p config/initializers
  cat > config/initializers/pagy.rb << 'RUBY'
require "pagy/extras/overflow"
Pagy::DEFAULT[:items]    = 25
Pagy::DEFAULT[:overflow] = :last_page
RUBY
  cat >> app/helpers/application_helper.rb << 'RUBY'

  include Pagy::Frontend
RUBY
  log_ok "Pagy 9.x configured"
}

# ── Shared partials ─────────────────────────────────────────────────────────

write_shared_partials() {
  mkdir -p app/views/shared
  cat > app/views/shared/_flash.html.erb << 'ERB'
<% flash.each do |type, msg| %>
  <div class="flash flash--<%= type %>"><%= msg %></div>
<% end %>
ERB

  cat > app/views/shared/_errors.html.erb << 'ERB'
<% if object.errors.any? %>
  <div class="errors">
    <% object.errors.full_messages.each do |msg| %>
      <p class="error-msg"><%= msg %></p>
    <% end %>
  </div>
<% end %>
ERB

  cat > app/views/shared/_pagination.html.erb << 'ERB'
<%= pagy_nav(pagy) if pagy.pages > 1 %>
ERB
  log_ok "Shared partials written"
}

# ── Auth views ──────────────────────────────────────────────────────────────

write_auth_views() {
  mkdir -p app/views/sessions app/views/passwords
  cat > app/views/sessions/new.html.erb << 'ERB'
<div class="auth-form">
  <h1>Sign in</h1>
  <%= form_with url: session_path do |f| %>
    <%= render "shared/errors", object: f.object if f.object.respond_to?(:errors) %>
    <div class="field">
      <%= f.label :email_address, "Email" %>
      <%= f.email_field :email_address, autofocus: true, autocomplete: "email" %>
    </div>
    <div class="field">
      <%= f.label :password %>
      <%= f.password_field :password, autocomplete: "current-password" %>
    </div>
    <div class="actions">
      <%= f.submit "Sign in", class: "btn btn--primary" %>
    </div>
    <p><%= link_to "Forgot password?", new_password_path %></p>
  <% end %>
</div>
ERB

  cat > app/views/passwords/new.html.erb << 'ERB'
<div class="auth-form">
  <h1>Reset password</h1>
  <%= form_with url: passwords_path do |f| %>
    <div class="field">
      <%= f.label :email_address, "Email" %>
      <%= f.email_field :email_address, autofocus: true, autocomplete: "email" %>
    </div>
    <div class="actions">
      <%= f.submit "Send reset link", class: "btn btn--primary" %>
    </div>
  <% end %>
</div>
ERB

  cat > app/views/passwords/edit.html.erb << 'ERB'
<div class="auth-form">
  <h1>New password</h1>
  <%= form_with model: @user, url: password_path(params[:token]), method: :put do |f| %>
    <div class="field">
      <%= f.label :password, "New password" %>
      <%= f.password_field :password, autocomplete: "new-password" %>
    </div>
    <div class="field">
      <%= f.label :password_confirmation, "Confirm password" %>
      <%= f.password_field :password_confirmation, autocomplete: "new-password" %>
    </div>
    <div class="actions">
      <%= f.submit "Set password", class: "btn btn--primary" %>
    </div>
  <% end %>
</div>
ERB
  log_ok "Auth views written"
}

# ── Registration (sign-up) ───────────────────────────────────────────────────

write_registration() {
  mkdir -p app/views/registrations
  cat > app/controllers/registrations_controller.rb << 'RUBY'
class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  def new = render

  def create
    user = User.new(registration_params)
    if user.save
      start_new_session_for user
      redirect_to root_path, notice: "Welcome!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end
end
RUBY
  cat > app/views/registrations/new.html.erb << 'ERB'
<div class="auth-form">
  <h1>Create account</h1>
  <%= form_with model: User.new, url: registration_path do |f| %>
    <%= render "shared/errors", object: f.object %>
    <div class="field">
      <%= f.label :email_address, "Email" %>
      <%= f.email_field :email_address, autofocus: true, autocomplete: "email" %>
    </div>
    <div class="field">
      <%= f.label :password %>
      <%= f.password_field :password, autocomplete: "new-password" %>
    </div>
    <div class="field">
      <%= f.label :password_confirmation, "Confirm password" %>
      <%= f.password_field :password_confirmation, autocomplete: "new-password" %>
    </div>
    <div class="actions">
      <%= f.submit "Create account", class: "btn btn--primary" %>
    </div>
    <p><%= link_to "Sign in instead", new_session_path %></p>
  <% end %>
</div>
ERB
  log_ok "Registration written"
}

# ── Enhanced layout ─────────────────────────────────────────────────────────

write_full_layout() {
  local app_title=${1:-App}
  local nav_links=${2:-}
  mkdir -p app/views/layouts
  cat > app/views/layouts/application.html.erb << LAYOUT
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="turbo-cache-control" content="no-preview">
  <title><%= content_for?(:title) ? yield(:title) + " – ${app_title}" : "${app_title}" %></title>
  <%= csrf_meta_tags %>
  <%= csp_meta_tag %>
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
  <%= javascript_importmap_tags %>
</head>
<body>
<nav>
  <%= link_to "${app_title}", root_path, class: "brand" %>
  ${nav_links}
  <% if authenticated? %>
    <%= link_to "Sign out", session_path, data: { turbo_method: :delete } %>
  <% else %>
    <%= link_to "Sign in", new_session_path %>
  <% end %>
</nav>
<%= render "shared/flash" %>
<main><%= yield %></main>
</body>
</html>
LAYOUT
  log_ok "Full layout written"
}
