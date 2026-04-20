#!/usr/bin/env zsh
emulate -L zshsetopt err_return no_unset pipe_fail extended_glob warn_create_global

# constants
app_dir="/home/brgen/app"
db_config_path="${app_dir}/config/database.yml"

# function to replace database name and credentials
replace_db_config() {
    local input="$1"
    # original inline edits (commented for reference)
    # local replaced="${input//database: app_/database: brgen_}"
    # replaced="${replaced//username: brgen/username: brgen_user}"
    # echo -r -- "$replaced"
    printf '%s' "$input" |
        sed -e 's|database: app_|database: brgen_|' \
            -e 's|username: brgen|username: brgen_user|'
}

echo "==> [auth] acts_as_votable solid_stack devise"
cd "$app_dir"

echo "Installing acts_as_votable"
bin/rails generate acts_as_votable:migration
bin/rails db:migrate

echo "Installing solid stack"
bin/rails generate solid_queue:install
bin/rails generate solid_cache:install
bin/rails generate solid_cable:install

echo "Installing rails 8 authentication"
[[ ! -f "app/models/session.rb" ]] && bin/rails generate authentication

# update database configuration
if [[ -f "$db_config_path" ]]; then
    original_config=$(<"$db_config_path")
    # keep original logic in sub-shell
    (
        # commented original inline edits
        # config="${original_config//database: app_/database: brgen_}"
        # config="${config//username: brgen/username: brgen_user}"
        # print -r -- "$config" > "$db_config_path"
        new_config=$(replace_db_config "$original_config")
        print -r -- "$new_config" > "$db_config_path"
    )
fi

echo "==> [auth] done"