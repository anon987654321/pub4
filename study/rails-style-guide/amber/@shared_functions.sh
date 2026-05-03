#!/usr/bin/env sh
# @shared_functions.sh — shared helpers for DEPLOY/rails/* scripts
# Source this file; do not execute directly.
#
# Conventions:
#   APP_DIR  — full path to the Rails app (caller must set, e.g. /home/brgen/app)
#   APP_PORT — TCP port Falcon listens on (default 3000)

: "${APP_PORT:=3000}"
readonly APP_PORT

# Ensure required environment variables are present
: "${APP_DIR:?APP_DIR must be set before sourcing}"

set -eu
set -o pipefail
IFS=$'\n\t'

# ── Logging ──────────────────────────────────────────────────────────────────

log()      { printf '%b\n' "$(printf '\033[36m==>\033[0m %s' "$*")"; }
log_ok()   { printf '%b\n' "$(printf '\033[32m✔\033[0m %s' "$*")"; }
log_warn() { printf '%b\n' "$(printf '\033[33mWARN\033[0m %s' "$*")" >&2; }
log_err()  { printf '%b\n' "$(printf '\033[31mERR\033[0m %s' "$*")" >&2; }

# ── Precondition checks ───────────────────────────────────────────────────────

command_exists() {
  cmd=$1
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log_err "Required command not found: $cmd"
    exit 1
  fi
  log_ok "$cmd found"
}

check_app_exists() {
  sentinel=$1
  if [ -f "$sentinel" ]; then
    log_warn "Already set up ($sentinel exists). Skipping."
    return 0
  fi
  return 1
}

# ── App scaffolding ───────────────────────────────────────────────────────────

setup_full_app() {
  app_dir=$1
  mkdir -p "$(dirname "$app_dir")"

  if [ ! -f "$app_dir/config/application.rb" ]; then
    log "Creating Rails 8 app at $app_dir"
    rails new "$app_dir" \
      --database=sqlite3 \
      --skip-git \
      --asset-pipeline=propshaft \
      --javascript=importmap \
      --skip-test
  fi

  cd "$app_dir"

  # Ensure Falcon is the server adapter
  if ! grep -q '"falcon"' Gemfile; then
    printf '%s\n' 'gem "falcon"' >> Gemfile
    bundle install --quiet
  fi

  log_ok "Working in: $app_dir"
}

# ── Gem helpers ───────────────────────────────────────────────────────────────

install_gem() {
  gem=$1 version=${2:-}
  if ! grep -q "\"$gem\"" Gemfile 2>/dev/null; then
    if [ -n "$version" ]; then
      printf '%s\n' "gem \"$gem\", \"$version\"" >> Gemfile
    else
      printf '%s\n' "gem \"$gem\"" >> Gemfile
    fi
    bundle install --quiet
    log_ok "gem $gem installed"
  else
    log_ok "gem $gem already present"
  fi
}

# ── Database helpers ──────────────────────────────────────────────────────────

db_setup() {
  RAILS_ENV=production bin/rails db:create db:migrate 2>&1 |
    grep -E "Created|migrated|error" || :
  log_ok "database ready"
}

# ── relayd helpers ────────────────────────────────────────────────────────────

relayd_add_relay() {
  host=$1 port=$2
  table_name=${host%%.*}
  conf=/etc/relayd.conf

  if grep -q "table <${table_name}>" "$conf" 2>/dev/null; then
    return 0
  fi

  sudo sh -c "cat >> $conf <<'EOF'
table <${table_name}> { 127.0.0.1 }
EOF"
  log_ok "relayd table <${table_name}> → :${port} added (reload relayd to apply)"
}

# ── rc.d helpers ──────────────────────────────────────────────────────────────

install_rcd() {
  svc=$1 app_dir=$2 port=$3 user=$4
  rcd="/etc/rc.d/${svc}"

  [ -f "$rcd" ] && return 0

  sudo sh -c "cat > $rcd <<'EOF'
#!/bin/ksh
daemon_execdir='${app_dir}'
daemon='${app_dir}/bin/rails'
daemon_flags='server -b 0.0.0.0 -p ${port} -e production'
daemon_user='${user}'
. /etc/rc.d/rc.subr
rc_cmd \$1
EOF"

  sudo chmod 755 "$rcd"
  sudo rcctl enable "$svc"
  log_ok "rc.d/${svc} installed"
}

# ── Asset helpers ─────────────────────────────────────────────────────────────

generate_default_css() {
  mkdir -p app/assets/stylesheets
  cat > app/assets/stylesheets/application.css <<'CSS'
:root {
  --bg: #0a0a0a;
  --surface: #1a1a1a;
  --text: #e8eaed;
  --text-dim: #9aa0a6;
  --primary: #8ab4f8;
  --accent: #ff4500;
  --radius: 8px;
  --space: 8px;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: system-ui, sans-serif; background: var(--bg); color: var(--text); line-height: 1.6; }
main { max-width: 1200px; margin: 0 auto; padding: calc(var(--space) * 2); }
a { color: var(--primary); text-decoration: none; }
.card { background: var(--surface); border-radius: var(--radius); padding: calc(var(--space) * 2); margin-bottom: calc(var(--space) * 2); }
@media (max-width: 768px) { main { padding: var(--space); } }
CSS
  log_ok "default CSS written"
}

generate_all_stimulus_controllers() {
  mkdir -p app/javascript/controllers
  cat > app/javascript/controllers/index.js <<'JS'
import { application } from "controllers/application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)
JS
  log_ok "Stimulus controllers index written"
}