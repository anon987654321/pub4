```sh
#!/bin/sh

APP_NAME="brgen_tv"
BASE_DIR="${HOME}/rails"
SERVER_IP="185.52.176.18"
APP_PORT=$((10000 + RANDOM % 10000))
SCRIPT_DIR=$(dirname "$0")

if [ -f "${SCRIPT_DIR}/shared_functions.sh" ]; then
    . "${SCRIPT_DIR}/shared_functions.sh"
else
    echo "Error: shared_functions.sh not found" >&2
    exit 1
fi

log "Starting Brgen TV setup with video streaming and live broadcasting"

if ! command -v redis-server >/dev/null 2>&1; then
    log "Installing Redis..."
    if ! doas pkg_add redis; then
        log "Failed to install Redis. Please install manually via 'pkg_add redis'"
        exit 1
    fi
fi

setup_full_app "$APP_NAME"

install_gem "faker"
install_gem "pagy"

if ! bin/rails generate authentication; then
    log "Failed to generate authentication"
    exit 1
fi

if ! bin/rails db:migrate; then
    log "Failed to migrate database"
    exit 1
fi

generate_model "Video" "title:string description:text user:references duration:integer views:integer status:string category:string" || exit 1
generate_model "LiveStream" || exit 1
generate_model "Channel" "name:string description:text user:references is_live:boolean" || exit 1
generate_model "Subscription" "user:references channel:references" || exit 1
generate_model "VideoComment" "video:references user:references content:text" || exit 1

if [ -f "app/controllers/application_controller.rb" ] && ! grep -q "include Pagy::Backend" app/controllers/application_controller.rb; then
    printf "include Pagy::Backend\n" >> app/controllers/application_controller.rb || exit 1
fi

if [ -f "app/helpers/application_helper.rb" ] && ! grep -q "include Pagy::Frontend" app/helpers/application_helper.rb; then
    printf "include Pagy::Frontend\n" >> app/helpers/application_helper.rb || exit 1
fi
```
