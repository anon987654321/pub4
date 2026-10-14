#!/bin/ksh
# Root-owned dispatcher for a closed set of Rails tasks; application code runs as the app user.
set -eu
PATH=/usr/local/bin:/usr/bin:/bin
export PATH
unset RUBYOPT RUBYLIB RUBYPATH RUBYGEMS_GEMDEPS GEM_HOME GEM_PATH
unset BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_WITH BUNDLE_WITHOUT

app=${1:-}
task=${2:-}
database=${3:-}
case "$app" in
  master|brgen|amber|bsdports) ;;
  *) echo "rails-task: refused unknown app: $app" >&2; exit 64 ;;
esac
case "$task" in
  bundle-install|bundle-check|ci-bundle-install|db-prepare|db-seed|assets-precompile|ci|db-storage-migrate|npm-cache|overlay-initializers|overlay-public) [ "$#" -eq 2 ] || exit 64 ;;
  demo-seed) [ "$#" -eq 2 ] && { [ "$app" = brgen ] || [ "$app" = amber ]; } || exit 64 ;;
  schema-load|secondary-db-check) [ "$#" -eq 3 ] || exit 64; case "$database" in cache|queue|cable) ;; *) exit 64 ;; esac ;;
  *) echo "rails-task: refused task: $task" >&2; exit 64 ;;
esac
[ "$(id -u)" -eq 0 ] || { echo "rails-task: must run as root through pub4-admin" >&2; exit 77; }

app_uid=$(/usr/bin/id -u "$app")
app_home="/home/$app"
app_dir="$app_home/app"
[ -d "$app_home" ] && [ ! -L "$app_home" ] && [ "$(stat -f %u "$app_home")" = "$app_uid" ] || {
  echo "rails-task: app home must be a real app-owned directory: $app_home" >&2
  exit 1
}
[ -d "$app_dir" ] && [ ! -L "$app_dir" ] && [ "$(stat -f %u "$app_dir")" = "$app_uid" ] || {
  echo "rails-task: app directory must be a real app-owned directory: $app_dir" >&2
  exit 1
}
for cache_dir in "$app_home/.npm" "$app_home/.cache"; do
  if [ -e "$cache_dir" ] || [ -L "$cache_dir" ]; then
    [ -d "$cache_dir" ] && [ ! -L "$cache_dir" ] &&
      [ "$(stat -f %u "$cache_dir")" = "$app_uid" ] || {
        echo "rails-task: cache path must be a real app-owned directory: $cache_dir" >&2
        exit 1
      }
  fi
done
# Database tasks must not follow a symlinked db/storage path into another
# application or a root-managed location. Missing storage is allowed only for
# the one-time db-storage-migrate operation, which may create it as the app.
if [ -e "$app_dir/db" ] || [ -L "$app_dir/db" ]; then
  [ -d "$app_dir/db" ] && [ ! -L "$app_dir/db" ] &&
    [ "$(stat -f %u "$app_dir/db")" = "$app_uid" ] || {
      echo "rails-task: db must be a real app-owned directory" >&2
      exit 1
    }
fi
if [ -e "$app_dir/storage" ] || [ -L "$app_dir/storage" ]; then
  [ -d "$app_dir/storage" ] && [ ! -L "$app_dir/storage" ] &&
    [ "$(stat -f %u "$app_dir/storage")" = "$app_uid" ] || {
      echo "rails-task: storage must be a real app-owned directory" >&2
      exit 1
    }
fi

bundle=/usr/local/bin/bundle
found_ruby=0
for ruby_path in /usr/local/bin/ruby4.0 /usr/local/bin/ruby40 /usr/local/bin/ruby3.4 /usr/local/bin/ruby34 /usr/local/bin/ruby3.3 /usr/local/bin/ruby33 /usr/local/bin/ruby; do
  if [ -x "$ruby_path" ]; then
    found_ruby=1
    base=${ruby_path##*/}
    suffix=${base#ruby}
    candidate="/usr/local/bin/bundle$suffix"
    [ ! -x "$candidate" ] || bundle=$candidate
    break
  fi
done
[ "$found_ruby" -eq 1 ] || { echo "rails-task: no supported system Ruby found" >&2; exit 127; }
[ -x "$bundle" ] || { echo "rails-task: no supported system Bundler found" >&2; exit 127; }

secret=
case "$task" in
  db-prepare|db-seed|demo-seed|assets-precompile|schema-load|ci)
    for env_file in "/etc/$app.env" "/etc/rails/$app.env"; do
      if [ -f "$env_file" ] && [ ! -L "$env_file" ] && [ "$(stat -f %u "$env_file")" -eq 0 ]; then
        secret=$(/usr/bin/awk -F= '$1 == "SECRET_KEY_BASE" { print substr($0, index($0, "=") + 1); exit }' "$env_file")
        [ -n "$secret" ] && break
      fi
    done
    case "$secret" in
      ''|*[!0123456789abcdefABCDEF]*) echo "rails-task: no valid SECRET_KEY_BASE for $app" >&2; exit 1 ;;
    esac
    [ "${#secret}" -ge 64 ] && [ "${#secret}" -le 256 ] || { echo "rails-task: invalid SECRET_KEY_BASE length" >&2; exit 1; }
    ;;
esac

case "$task" in
  bundle-install)
    command="mkdir -p .bundle && printf '%s\\n' '---' 'BUNDLE_PATH: /home/$app/.bundle/gems' > .bundle/config && $bundle config set --local frozen false && $bundle config set --local deployment true && $bundle config set --local without \"development test\" && RAILS_ENV=production $bundle install" ;;
  bundle-check)
    command="$bundle check" ;;
  ci-bundle-install)
    command="$bundle config unset without && $bundle install --jobs=2" ;;
  db-storage-migrate)
    command='if [ ! -d db ]; then exit 0; fi
[ ! -L db ] || { echo "rails-task: refusing db symlink" >&2; exit 1; }
[ ! -L storage ] || { echo "rails-task: refusing storage symlink" >&2; exit 1; }
mkdir -p storage
for file in db/production*.sqlite3; do
  [ -f "$file" ] && [ ! -L "$file" ] || continue
  base=${file##*/}
  target="storage/$base"
  if [ -e "$target" ] || [ -L "$target" ]; then continue; fi
  mv "$file" "$target"
  printf "moved %s -> %s\\n" "$file" "$target"
done' ;;
  db-prepare)
    command="RAILS_ENV=production $bundle exec rails db:prepare" ;;
  db-seed)
    command="RAILS_ENV=production $bundle exec rails db:seed" ;;
  demo-seed)
    command="RAILS_ENV=production $bundle exec rails ${app}:demo_seed" ;;
  assets-precompile)
    command="RAILS_ENV=production $bundle exec rails assets:precompile" ;;
  schema-load)
    command="DISABLE_DATABASE_ENVIRONMENT_CHECK=1 RAILS_ENV=production $bundle exec rails db:schema:load:${database}" ;;
  secondary-db-check)
    schema="/home/$app/app/db/${database}_schema.rb"
    db_file="/home/$app/app/storage/production_${database}.sqlite3"
    [ -f "$schema" ] && [ ! -L "$schema" ] && [ -s "$db_file" ] && [ ! -L "$db_file" ] || exit 1
    table=$("$ruby_path" -e 'm = File.read(ARGV.fetch(0), encoding: "UTF-8").match(/create_table "([A-Za-z_][A-Za-z0-9_]*)"/); print(m ? m[1] : "")' "$schema")
    case "$table" in
      ''|*[!A-Za-z0-9_]*|[!A-Za-z_]*) echo "rails-task: invalid schema table for $database" >&2; exit 1 ;;
    esac
    command="/usr/local/bin/sqlite3 $db_file \"select 1 from $table limit 1;\"" ;;
  ci)
    command="PUB4_RAILS_ROOT=/home/$app/pub4-rails/RAILS RAILS_ENV=test CI=1 PUB4_CI_GUARD=1 $bundle exec bin/ci" ;;
  overlay-initializers)
    command=$(cat <<'EOF'
shared=/home/dev/pub4/RAILS/__shared/config/initializers
target=/home/$PUB4_TASK_APP/app/config/initializers
[ -d "$shared" ] && [ ! -L "$shared" ] || exit 0
[ -d "/home/$PUB4_TASK_APP/app/config" ] && [ ! -L "/home/$PUB4_TASK_APP/app/config" ] || exit 1
if [ -e "$target" ] || [ -L "$target" ]; then
  [ -d "$target" ] && [ ! -L "$target" ] && [ "$(stat -f %u "$target")" = "$PUB4_TASK_UID" ] || exit 1
else
  mkdir -p "$target"
fi
for entry in "$shared"/* "$shared"/.[!.]*; do
  [ -e "$entry" ] || continue
  cp -R "$entry" "$target/"
done
EOF
) ;;
  overlay-public)
    command=$(cat <<'EOF'
shared=/home/dev/pub4/RAILS/__shared/public
target=/home/$PUB4_TASK_APP/app/public
[ -d "$shared" ] && [ ! -L "$shared" ] || exit 0
if [ -e "$target" ] || [ -L "$target" ]; then
  [ -d "$target" ] && [ ! -L "$target" ] && [ "$(stat -f %u "$target")" = "$PUB4_TASK_UID" ] || exit 1
else
  mkdir -p "$target"
fi
for entry in "$shared"/* "$shared"/.[!.]*; do
  [ -e "$entry" ] || continue
  base=${entry##*/}
  case "$base" in
    icon.svg|icon.png|icon-192.png|apple-touch-icon.png|favicon.ico|manifest.json|manifest.webmanifest)
      [ -e "$target/$base" ] && continue
      ;;
  esac
  cp -R "$entry" "$target/"
done
shared_bin=/home/dev/pub4/RAILS/__shared/bin
target_bin=/home/$PUB4_TASK_APP/app/bin
if [ -d "$shared_bin" ] && [ ! -L "$shared_bin" ]; then
  if [ -e "$target_bin" ] || [ -L "$target_bin" ]; then
    [ -d "$target_bin" ] && [ ! -L "$target_bin" ] && [ "$(stat -f %u "$target_bin")" = "$PUB4_TASK_UID" ] || exit 1
  else
    mkdir -p "$target_bin"
  fi
  for tool in rubocop brakeman bundler-audit; do
    if [ -f "$shared_bin/$tool" ] && [ ! -L "$shared_bin/$tool" ]; then
      cp "$shared_bin/$tool" "$target_bin/$tool"
      chmod 755 "$target_bin/$tool"
    fi
  done
fi
rubocop_config=/home/dev/pub4/RAILS/__shared/.rubocop.yml
if [ -f "$rubocop_config" ] && [ ! -L "$rubocop_config" ]; then
  cp "$rubocop_config" "/home/$PUB4_TASK_APP/app/.rubocop.yml"
fi
EOF
) ;;
esac

script=$(cat <<EOF
set -eu
export HOME=/home/$app
export PATH=/usr/local/bin:/usr/bin:/bin
export NPM_CONFIG_CACHE=/home/$app/.npm
export XDG_CACHE_HOME=/home/$app/.cache
export BUNDLE_USER_HOME=/home/$app/.bundle
export PUB4_TASK_APP=$app
export PUB4_TASK_UID=$app_uid
export SECRET_KEY_BASE
unset RUBYOPT RUBYLIB RUBYPATH RUBYGEMS_GEMDEPS GEM_HOME GEM_PATH
unset BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_WITH BUNDLE_WITHOUT
cd /home/$app/app
$command
EOF
)
exec /usr/bin/su -m "$app" -c "$script"
