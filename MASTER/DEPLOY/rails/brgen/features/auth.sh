#!/usr/bin/env sh
set -eu
set -o pipefail

#--- Configuration -----------------------------------------------------------
APP_DIR="/home/brgen/app"
DB_CONFIG="${APP_DIR}/config/database.yml"

#--- Helpers -----------------------------------------------------------------
replace_db_config() {
	# Transform placeholder values in database.yml.
	# stdin → stdout
	sed -e 's|database: app_|database: brgen_|' \
	    -e 's|username: brgen|username: brgen_user|'
}

#--- Main --------------------------------------------------------------------
printf '==> [auth] acts_as_votable solid_stack rails_auth\n'

if [ ! -d "$APP_DIR" ]; then
	printf 'Error: APP_DIR does not exist: %s\n' "$APP_DIR" >&2
	exit 1
fi

cd "$APP_DIR"

printf 'Installing acts_as_votable\n'
bin/rails generate acts_as_votable:migration
bin/rails db:migrate

printf 'Installing solid stack\n'
bin/rails generate solid_queue:install
bin/rails generate solid_cache:install
bin/rails generate solid_cable:install

printf 'Installing rails 8 authentication\n'
if [ ! -f "app/models/session.rb" ]; then
	bin/rails generate authentication
fi

# Update DB config atomically, preserving mode
if [ -f "$DB_CONFIG" ]; then
	tmp="$(mktemp -p "$(dirname "$DB_CONFIG")" tmp.XXXXXX)"
	trap 'rm -f "$tmp"' EXIT
	replace_db_config < "$DB_CONFIG" > "$tmp"
	chmod --reference="$DB_CONFIG" "$tmp"
	mv -f "$tmp" "$DB_CONFIG"
	trap - EXIT
fi

printf '==> [auth] done\n'