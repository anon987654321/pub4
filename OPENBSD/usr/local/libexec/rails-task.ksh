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
  brgen|amber|bsdports) ;;
  *) echo "rails-task: refused unknown app: $app" >&2; exit 64 ;;
esac
case "$task" in
  bundle-install|bundle-check|db-prepare|db-seed|assets-precompile|ci) [ "$#" -eq 2 ] || exit 64 ;;
  demo-seed) [ "$#" -eq 2 ] && { [ "$app" = brgen ] || [ "$app" = amber ]; } || exit 64 ;;
  schema-load) [ "$#" -eq 3 ] || exit 64; case "$database" in cache|queue|cable) ;; *) exit 64 ;; esac ;;
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
    command="$bundle config set --local frozen false && $bundle config set --local deployment true && $bundle config set --local without \"development test\" && RAILS_ENV=production $bundle install" ;;
  bundle-check)
    command="$bundle check" ;;
  db-prepare)
    command="SECRET_KEY_BASE=$secret RAILS_ENV=production $bundle exec rails db:prepare" ;;
  db-seed)
    command="SECRET_KEY_BASE=$secret RAILS_ENV=production $bundle exec rails db:seed" ;;
  demo-seed)
    command="SECRET_KEY_BASE=$secret RAILS_ENV=production $bundle exec rails ${app}:demo_seed" ;;
  assets-precompile)
    command="SECRET_KEY_BASE=$secret RAILS_ENV=production $bundle exec rails assets:precompile" ;;
  schema-load)
    command="SECRET_KEY_BASE=$secret DISABLE_DATABASE_ENVIRONMENT_CHECK=1 RAILS_ENV=production $bundle exec rails db:schema:load:${database}" ;;
  ci)
    command="SECRET_KEY_BASE=$secret PUB4_RAILS_ROOT=/home/$app/pub4-rails/RAILS RAILS_ENV=test CI=1 PUB4_CI_GUARD=1 $bundle exec bin/ci" ;;
esac

script=$(cat <<EOF
set -eu
export HOME=/home/$app
export PATH=/usr/local/bin:/usr/bin:/bin
export NPM_CONFIG_CACHE=/home/$app/.npm
export XDG_CACHE_HOME=/home/$app/.cache
export BUNDLE_USER_HOME=/home/$app/.bundle
unset RUBYOPT RUBYLIB RUBYPATH RUBYGEMS_GEMDEPS GEM_HOME GEM_PATH
unset BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_WITH BUNDLE_WITHOUT
cd /home/$app/app
$command
EOF
)
exec /usr/bin/su -m "$app" -c "$script"
