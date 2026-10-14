#!/bin/ksh
# Root-owned fixed production bundle launcher. The bundle process itself runs as
# the allowlisted app account and receives no caller-supplied command or path.
set -eu
PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
export PATH

app=\${1:-}
timeout=\${2:-}
case "$app" in
  brgen|amber|bsdports) ;;
  *) echo "rails-bundle: refused unknown app: $app" >&2; exit 64 ;;
esac
case "$timeout" in
  ""|*[!0-9]*) echo "rails-bundle: timeout must be an integer from 1 to 7200" >&2; exit 64 ;;
esac
[ "$timeout" -ge 1 ] && [ "$timeout" -le 7200 ] || {
  echo "rails-bundle: timeout must be an integer from 1 to 7200" >&2
  exit 64
}
[ "$(id -u)" -eq 0 ] || { echo "rails-bundle: must run as root through pub4-admin" >&2; exit 77; }

app_home="/home/$app"
app_dir="$app_home/app"
[ -d "$app_home" ] && [ ! -L "$app_home" ] || {
  echo "rails-bundle: app home is not a real directory" >&2
  exit 1
}
[ -d "$app_dir" ] && [ ! -L "$app_dir" ] || {
  echo "rails-bundle: app directory is not a real directory" >&2
  exit 1
}
[ "$(stat -f %u "$app_home")" = "$(id -u "$app")" ] &&
[ "$(stat -f %u "$app_dir")" = "$(id -u "$app")" ] || {
  echo "rails-bundle: app home and app tree must be app-owned" >&2
  exit 1
}

bundle=/usr/local/bin/bundle
found_ruby=0
for ruby_path in /usr/local/bin/ruby4.0 /usr/local/bin/ruby40 \
                 /usr/local/bin/ruby3.4 /usr/local/bin/ruby34 \
                 /usr/local/bin/ruby3.3 /usr/local/bin/ruby33 \
                 /usr/local/bin/ruby; do
  if [ -x "$ruby_path" ]; then
    found_ruby=1
    base=\${ruby_path##*/}
    suffix=\${base#ruby}
    candidate="/usr/local/bin/bundle$suffix"
    [ ! -x "$candidate" ] || bundle=$candidate
    break
  fi
done
[ "$found_ruby" -eq 1 ] || { echo "rails-bundle: no supported system Ruby found" >&2; exit 127; }
[ -x "$bundle" ] || { echo "rails-bundle: no supported system Bundler found" >&2; exit 127; }

script=$(cat <<EOF
set -eu
export HOME=/home/$app
export NPM_CONFIG_CACHE=/home/$app/.npm
export XDG_CACHE_HOME=/home/$app/.cache
unset RUBYOPT RUBYLIB RUBYPATH RUBYGEMS_GEMDEPS GEM_HOME GEM_PATH
unset BUNDLE_GEMFILE BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_WITH BUNDLE_WITHOUT
cd /home/$app/app
mkdir -p .bundle
printf '%s\\n' '---' 'BUNDLE_PATH: "/home/$app/.bundle/gems"' > .bundle/config
$bundle config set --local frozen false
$bundle config set --local deployment true
$bundle config set --local without "development test"
RAILS_ENV=production $bundle install
EOF
)
exec /usr/bin/su -m "$app" -c "$script"
