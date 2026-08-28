#!/usr/bin/env zsh
set -euo pipefail
# _database.sh — app secrets, migrate/prepare, seeding for copy-tree deploy.
# Source this file; do not execute directly. Requires _core.sh sourced first.

# app_secret_for APP_NAME — read or create SECRET_KEY_BASE in /etc/<app>.env
app_secret_for() {
  local app_name=$1 env_file secret

  for env_file in /etc/${app_name}.env /etc/rails/${app_name}.env; do
    if ${_PRIV} test -r "$env_file"; then
      secret=$(${_PRIV} grep '^SECRET_KEY_BASE=' "$env_file" | head -1 | cut -d= -f2-)
      [[ -n $secret ]] && { print -r -- "$secret"; return 0; }
    fi
  done

  secret=$(ruby34 -e "require 'securerandom'; puts SecureRandom.hex(64)")
  ${_PRIV} sh -c "print -r 'SECRET_KEY_BASE=${secret}' > /etc/${app_name}.env && chmod 640 /etc/${app_name}.env && chown root:${app_name} /etc/${app_name}.env 2>/dev/null || chown root:wheel /etc/${app_name}.env"
  log_ok "created /etc/${app_name}.env" >&2
  print -r -- "$secret"
}

# db_create_migrate_as_app APP_NAME APP_DIR
db_create_migrate_as_app() {
  local app_name=$1 app_dir=$2 secret
  secret=$(app_secret_for "$app_name")
  ${_PRIV} sh -c "su -m ${app_name} -c 'cd ${app_dir} && SECRET_KEY_BASE=${secret} RAILS_ENV=production bundle34 exec rails db:prepare'" \
    || { log_err "db:prepare failed for ${app_name}"; return 1; }
  rails_prepare_secondary_dbs_as_app "$app_name" "$app_dir" \
    || return 1
  log_ok "Database ready"
}

# rails_prepare_secondary_dbs_as_app APP_NAME APP_DIR — initialise cache/queue/cable
# databases on copy-tree deploy, once.
#
# This used to run db:schema:load:<db> unconditionally on every deploy. Rails
# schema files create their tables with `force: :cascade` — schema:load DROPS
# each table and recreates it — so every deploy silently emptied all three
# secondary databases. For cache and cable that is survivable. For queue it
# means every enqueued job is destroyed at deploy time: brgen was carrying 1670
# of them on 2026-08-13 and had 0 an hour later, deleted rather than run.
#
# It was invisible because no Solid Queue worker has ever run on this box (see
# OPENBSD/DECISIONS.md, "Falcon Only"), so nothing was going to execute those
# jobs anyway. That changes the moment a worker exists, and a deploy that
# discards the password-reset emails enqueued while it was running is a worse
# bug than the one this loop was added to fix.
#
# The loop was added because the queue schema was not being loaded at all. That
# was a real gap; the verb was wrong. So it now loads a schema only when the
# database does not already carry its tables, and otherwise leaves the data
# alone. `rails db:prepare` on the line above already handles both creation and
# migration of every configured database (DatabaseTasks.prepare_all walks
# each_current_configuration, not just primary) — this stays as the explicit
# backstop it was meant to be.
rails_prepare_secondary_dbs_as_app() {
  local app_name=$1
  local app_dir=$2
  local secret
  secret=$(app_secret_for "$app_name")
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
    run_rails_as_app "$app_name" "$app_dir" \
      "SECRET_KEY_BASE=${secret} DISABLE_DATABASE_ENVIRONMENT_CHECK=1 RAILS_ENV=production bundle34 exec rails db:schema:load:${db}" \
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
  local file="${app_dir}/storage/production_${db}.sqlite3"
  local table

  whence sqlite3 >/dev/null 2>&1 || return 1
  ${_PRIV} test -s "$file" || return 1

  table=$(ruby34 -e 'm = File.read(ARGV[0], encoding: "UTF-8").match(/create_table "([^"]+)"/); print(m ? m[1] : "")' \
    "${app_dir}/db/${db}_schema.rb")
  [[ -n $table ]] || return 1

  # Exit status is the whole answer: sqlite3 fails with "no such table" when the
  # schema was never loaded, and succeeds with no output when the table is there
  # and empty. Reading the output instead would call a freshly loaded, still
  # empty queue "not initialised" and reload it every deploy.
  ${_PRIV} sh -c "su -m ${app_name} -c 'sqlite3 \"${file}\" \"select 1 from ${table} limit 1;\"'" >/dev/null 2>&1
}

# migrate_sqlite_db_to_storage_if_needed APP_NAME APP_DIR — one-time brgen db/ → storage/ move (R7).
migrate_sqlite_db_to_storage_if_needed() {
  local app_name=$1 app_dir=$2
  local db_dir="${app_dir}/db" storage_dir="${app_dir}/storage"
  [[ -d $db_dir ]] || return 0
  ${_PRIV} mkdir -p "$storage_dir"
  local moved=0 base
  for f in ${db_dir}/production*.sqlite3(N); do
    base=${f:t}
    [[ -f ${storage_dir}/${base} ]] && continue
    ${_PRIV} mv "$f" "${storage_dir}/${base}"
    moved=1
    log_ok "moved db/${base} → storage/${base}"
  done
  if [[ $moved -eq 1 ]]; then
    ${_PRIV} chown -R "${app_name}:${app_name}" "$storage_dir"
  fi
}

# db_seed_as_app APP_NAME APP_DIR
db_seed_as_app() {
  local app_name=$1 app_dir=$2 secret
  secret=$(app_secret_for "$app_name")
  ${_PRIV} sh -c "su -m ${app_name} -c 'cd ${app_dir} && SECRET_KEY_BASE=${secret} RAILS_ENV=production bundle34 exec rails db:seed'" \
    || log_warn "db:seed skipped for ${app_name}"
}

# seed_demo_as_app APP_NAME APP_DIR — the guest-facing demo content each app
# publishes: brgen's credible city feed (no Faker flood), amber's public capsule
# wardrobe. Both are idempotent rake tasks named <app>:demo_seed, and the app
# name is also the unix user and the /etc/<app>.env owner, so one argument fixes
# all three. A failure is a warning: demo content missing is worse than the
# deploy stopping, but not much worse.
seed_demo_as_app() {
  local app_name=$1 app_dir=$2 secret
  secret=$(app_secret_for "$app_name")
  ${_PRIV} sh -c "su -m ${app_name} -c 'cd ${app_dir} && SECRET_KEY_BASE=${secret} RAILS_ENV=production bundle34 exec rails ${app_name}:demo_seed'" \
    || log_warn "${app_name}:demo_seed skipped"
}
