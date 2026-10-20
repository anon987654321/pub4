#!/usr/bin/env zsh
set -euo pipefail
# _database.sh — app secrets, migrate/prepare, seeding for copy-tree deploy.
# Source this file; do not execute directly. Requires _core.sh sourced first.

# app_secret_for APP_NAME — read or create SECRET_KEY_BASE in /etc/<app>.env
app_secret_for() {
  local app_name=${1:-} secret
  case "$app_name" in master|brgen|bsdports) ;; *) log_err "app_secret_for: refused unknown app: $app_name"; return 2 ;; esac

  [[ -x /usr/local/sbin/pub4-admin ]] || {
    log_err "app_secret_for: pub4-admin is missing; run OPERATOR.sh before deploying"
    return 1
  }
  secret=$("${_PRIV}" /usr/local/sbin/pub4-admin ensure-secret "$app_name") || return 1
  case "$secret" in
    ""|*[!0123456789abcdefABCDEF]*)
      log_err "app_secret_for: broker returned an invalid secret for $app_name"
      return 1
      ;;
  esac
  (( ${#secret} >= 64 && ${#secret} <= 256 )) || {
    log_err "app_secret_for: broker returned an invalid secret length for $app_name"
    return 1
  }
  print -r -- "$secret"
}
# db_create_migrate_as_app APP_NAME APP_DIR
db_create_migrate_as_app() {
  local app_name=$1 app_dir=$2
  run_rails_as_app "$app_name" "$app_dir" "db-prepare" \
    || { log_err "db:prepare failed for ${app_name}"; return 1; }
  rails_prepare_secondary_dbs_as_app "$app_name" "$app_dir" \
    || return 1
  log_ok "Database ready"
}

# rails_prepare_secondary_dbs_as_app APP_NAME APP_DIR — initialise cache/queue/cable
# databases on copy-tree deploy, once.
#
# A schema loads only when the database does not already carry its tables. Rails
# schema files create tables with `force: :cascade`, so db:schema:load DROPS each
# table and recreates it empty: run on every deploy, it empties all three
# secondary databases, and for queue that destroys every enqueued job, the
# password-reset emails queued while the deploy runs included. `rails db:prepare`
# on the line above already creates and migrates every configured database
# (DatabaseTasks.prepare_all walks each_current_configuration, not just primary);
# this loop is the explicit backstop for a queue schema that never loaded.
rails_prepare_secondary_dbs_as_app() {
  local app_name=$1
  local app_dir=$2
  local db
  for db in cache queue cable; do
    local schema="${app_dir}/db/${db}_schema.rb"
    [[ -f $schema ]] || continue
    grep -q 'define(version: 0)' "$schema" 2>/dev/null && continue

    if secondary_db_initialized "$app_name" "$app_dir" "$db"; then
      log_ok "${db} db already initialised for ${app_name} — not reloading its schema"
      continue
    fi

    log "db:schema:load:${db} for ${app_name}"
    run_rails_as_app "$app_name" "$app_dir" "schema-load" "$db" \
      || { log_err "db:schema:load:${db} failed for ${app_name}"; return 1; }
  done
}

# secondary_db_initialized APP_NAME APP_DIR DB — true when the database file
# exists and holds the first table its schema declares.
#
# Deliberately fails to "not initialised" whenever it cannot tell: a missing
# sqlite3, an unreadable file, a database.yml that stops using the
# storage/production_<db>.sqlite3 convention all three apps share today. Being
# wrong that way reloads a schema that did not need reloading, which is what
# this code did on every deploy until now. Being wrong the other way would skip
# the load that makes the app boot.
secondary_db_initialized() {
  local app_name=$1 app_dir=$2 db=$3
  run_rails_as_app "$app_name" "$app_dir" "secondary-db-check" "$db" >/dev/null 2>&1
}

# migrate_sqlite_db_to_storage_if_needed APP_NAME APP_DIR — one-time brgen db/ → storage/ move (R7).
migrate_sqlite_db_to_storage_if_needed() {
  local app_name=$1 app_dir=$2
  case "$app_name" in master|brgen|bsdports) ;; *) log_err "storage migration: refused app: $app_name"; return 2 ;; esac
  [[ $app_dir == "/home/${app_name}/app" ]] || {
    log_err "storage migration: refused app path: $app_dir"
    return 2
  }
  [[ -x /usr/local/sbin/pub4-admin ]] || {
    log_err "storage migration: pub4-admin is missing; run OPERATOR.sh before deploying"
    return 1
  }
  run_rails_as_app "$app_name" "$app_dir" "db-storage-migrate"
}

# db_seed_as_app APP_NAME APP_DIR
db_seed_as_app() {
  local app_name=$1 app_dir=$2
  run_rails_as_app "$app_name" "$app_dir" "db-seed" \
    || log_warn "db:seed skipped for ${app_name}"
}

# seed_demo_as_app APP_NAME APP_DIR — the guest-facing demo content each app
# publishes: brgen's credible city feed (no Faker flood), amber's public capsule
# wardrobe. Both are idempotent rake tasks named <app>:demo_seed, and the app
# name is also the unix user and the /etc/<app>.env owner, so one argument fixes
# all three. A failure is a warning: demo content missing is worse than the
# deploy stopping, but not much worse.
seed_demo_as_app() {
  local app_name=$1 app_dir=$2
  run_rails_as_app "$app_name" "$app_dir" "demo-seed" \
    || log_warn "${app_name}:demo_seed skipped"
}
