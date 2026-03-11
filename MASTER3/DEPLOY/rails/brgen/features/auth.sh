#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/brgen/app"

echo "==> [auth] Acts-as-votable, Solid stack, Devise"
cd "$APP_DIR"

echo "Installing acts_as_votable"
bin/rails generate acts_as_votable:migration
bin/rails db:migrate

echo "Installing Solid Stack"
bin/rails generate solid_queue:install
bin/rails generate solid_cache:install
bin/rails generate solid_cable:install

echo "Installing Rails 8 authentication"
[[ ! -f "app/models/session.rb" ]] && bin/rails generate authentication

echo "Configuring PostgreSQL"
config=$(<config/database.yml)
config=${config//database: app_/database: brgen_}
config=${config//username: brgen/username: brgen_user}
print -r -- "$config" > config/database.yml

echo "==> [auth] done"
