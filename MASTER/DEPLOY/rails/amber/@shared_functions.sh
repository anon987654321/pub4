#!/usr/bin/env zsh
# @shared_functions.sh — shared helpers for DEPLOY/rails/* scripts
# Source this file; do not execute directly.
#
# Conventions:
#   APP_DIR  — full path to app (caller sets this, e.g. /home/brgen/app)
#   APP_PORT — TCP port Falcon listens on

typeset -r APP_PORT="${APP_PORT:-3000}"

# ── Logging ──────────────────────────────────────────────────────────────────

log()      { print -P "%F{cyan}==>%f $*" }
log_ok()   { print -P "%F{green}✔%f $*" }
log_warn() { print -P "%F{yellow}WARN%f $*" >&2 }
log_err()  { print -P "%F{red}ERR%f $*" >&2 }

# ── Precondition checks ───────────────────────────────────────────────────────

command_exists() {
  local cmd="$1"
  command -v "$cmd" &>/dev/null || { log_err "Required command not found: $cmd"; exit 1 }
  log_ok "$cmd found"
}

# check_app_exists SENTINEL_FILE — returns 0 if already set up
check_app_exists() {
  local sentinel="$1"
  if [[ -f "$sentinel" ]]; then
    log_warn "Already set up ($sentinel exists). Skipping."
    return 0
  fi
  return 1
}

# ── App scaffolding ───────────────────────────────────────────────────────────

# setup_full_app APP_DIR — creates Rails 8 app with SQLite + Falcon
setup_full_app() {
  local app_dir="$1"

  mkdir -p "$(dirname "$app_dir")"

  if [[ ! -f "${app_dir}/config/application.rb" ]]; then
    log "Creating Rails 8 app at $app_dir"
    rails new "$app_dir" --database=sqlite3 --skip-git \
      --asset-pipeline=propshaft --javascript=importmap --skip-test
  fi

  cd "$app_dir"

  # Ensure Falcon is the server adapter
  grep -q '"falcon"' Gemfile || { echo 'gem "falcon"' >> Gemfile; bundle install --quiet }

  log_ok "Working in: $app_dir"
}

# ── Gem helpers ───────────────────────────────────────────────────────────────

install_gem() {
  local gem="$1" version="${2:-}"
  if ! grep -q "\"${gem}\"" Gemfile 2>/dev/null; then
    if [[ -n "$version" ]]; then
      echo "gem \"${gem}\", \"${version}\"" >> Gemfile
    else
      echo "gem \"${gem}\"" >> Gemfile
    fi
    bundle install --quiet
    log_ok "gem ${gem} installed"
  else
    log_ok "gem ${gem} already present"
  fi
}

# ── Database helpers ──────────────────────────────────────────────────────────

db_setup() {
  RAILS_ENV=production bin/rails db:create db:migrate 2>&1 | grep -E "Created|migrated|error" || true
  log_ok "database ready"
}

# ── relayd helpers ────────────────────────────────────────────────────────────

# relayd_add_relay HOSTNAME PORT — appends a relay entry to /etc/relayd.conf
relayd_add_relay() {
  local host="$1" port="$2"
  local table_name="${host%%.*}"  # e.g. "brgen" from "brgen.no"
  local conf=/etc/relayd.conf

  grep -q "table <${table_name}>" "$conf" 2>/dev/null && return 0

  doas tee -a "$conf" << RELAYD

table <${table_name}> { 127.0.0.1 }
RELAYD

  log_ok "relayd table <${table_name}> → :${port} added (reload relayd to apply)"
}

# ── rc.d helpers ──────────────────────────────────────────────────────────────

# install_rcd SERVICE_NAME APP_DIR PORT USER
install_rcd() {
  local svc="$1" app_dir="$2" port="$3" user="$4"
  local rcd="/etc/rc.d/${svc}"

  [[ -f "$rcd" ]] && return 0

  doas tee "$rcd" << RCD
#!/bin/ksh
daemon_execdir="${app_dir}"
daemon="${app_dir}/bin/rails"
daemon_flags="server -b 0.0.0.0 -p ${port} -e production"
daemon_user="${user}"
. /etc/rc.d/rc.subr
rc_cmd \$1
RCD

  doas chmod 755 "$rcd"
  doas rcctl enable "$svc"
  log_ok "rc.d/${svc} installed"
}

# ── Asset helpers ─────────────────────────────────────────────────────────────

generate_default_css() {
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
.card { background: var(--surface); border-radius: var(--radius); padding: calc(var(--space)*2); margin-bottom: calc(var(--space)*2); }
@media (max-width: 768px) { main { padding: var(--space); } }
CSS
  log_ok "default CSS written"
}

generate_all_stimulus_controllers() {
  mkdir -p app/javascript/controllers
  cat > app/javascript/controllers/index.js << 'JS'
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
JS
  log_ok "Stimulus controllers index written"
}
