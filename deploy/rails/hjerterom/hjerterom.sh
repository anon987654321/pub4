

#!/usr/bin/env zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Hjerterom - Mental health and food redistribution platform

readonly APP_NAME="hjerterom"
readonly BASE_DIR="/home/dev/rails"
readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SERVER_IP="185.52.176.18"
readonly APP_PORT=$((10000 + RANDOM % 10000))

source "${SCRIPT_DIR}/@shared_functions.sh"

setup_environment() {
  command_exists "ruby" || exit 1
  command_exists "node" || exit 1
  command_exists "psql" || exit 1
}

install_dependencies() {
  install_gem "faker"
  install_gem "omniauth-vipps"
  install_gem "ahoy_matey"
  install_gem "blazer"
  install_gem "chartkick"
  grep -q "Pagy::Backend" app/controllers/application_controller.rb || \
    sed -i 's/class ApplicationController < ActionController::Base/class ApplicationController < ActionController::Base\n  include Pagy::Backend/' \
    app/controllers/application_controller.rb
  grep -q "Pagy::Frontend" app/helpers/application_helper.rb || \
    sed -i 's/module ApplicationHelper/module ApplicationHelper\n  include Pagy::Frontend/' \
    app/helpers/application_helper.rb
}

generate_models() {
  bin/rails generate model Distribution \
    location:string schedule:datetime capacity:integer \
    lat:decimal lng:decimal
  bin/rails generate model Giveaway \
    title:string description:text quantity:integer \
    pickup_time:datetime location:string lat:decimal lng:decimal \
    user:references status:string anonymous:boolean
  bin/rails generate migration AddVippsToUsers \
    vipps_id:string citizenship_status:string claim_count:integer
}

setup_initializers() {
  write_ahoy_initializer
  write_blazer_initializer
}

generate_controllers() {
  write_application_controller
  write_home_controller
  write_distributions_controller
  write_giveaways_controller
}

guest_user_allowed?() {
  local user=$1
  [[ "$user" == "guest" ]] || return 1
  return 0
}
