```zsh
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Brgen TV setup: Video streaming platform with live streaming, content management, and social viewing features on OpenBSD 7.8, unprivileged user

# Framework v37.3.2 compliant with enhanced video streaming capabilities

APP_NAME="brgen_tv"

BASE_DIR="/home/dev/rails"

SERVER_IP="185.52.176.18"

APP_PORT=$((10000 + RANDOM % 10000))

SCRIPT_DIR="${0:a:h}"

source "${SCRIPT_DIR}/shared_functions.sh"

log "Starting Brgen TV setup with video streaming and live broadcasting"

setup_full_app "$APP_NAME"

if ! command -v redis-server >/dev/null 2>&1; then
  log "Redis server not found. Please install Redis system package before running this script."
  exit 1
fi

install_gem "faker"
install_gem "pagy"

# Setup Rails 8 authentication
[[ -f "app/models/session.rb" ]] || { bin/rails generate authentication || exit 1; bin/rails db:migrate || exit 1; }

# Generate enhanced video streaming models
generate_model "Video" "title:string description:text user:references duration:integer views:integer status:string category:string" || exit 1
generate_model "LiveStream" "title:string description:text user:references status:string viewer_count:integer" || exit 1
generate_model "Channel" "name:string description:text user:references is_live:boolean" || exit 1
generate_model "Subscription" "user:references channel:references" || exit 1
generate_model "VideoComment" "video:references user:references content:text" || exit 1

# Patch ApplicationController with Pagy::Backend (idempotent)
if [[ -f "app/controllers/application_controller.rb" ]] && ! grep -q "include Pagy::Backend" app/controllers/application_controller.rb; then
  sed -i '' '1i\
include Pagy::Backend
' app/controllers/application_controller.rb || exit 1
fi

# Patch ApplicationHelper with Pagy::Frontend (idempotent)
if [[ -f "app/helpers/application_helper.rb" ]] && ! grep -q "include Pagy::Frontend" app/helpers/application_helper.rb; then
  sed -i '' '1i\
include Pagy::Frontend
' app/helpers/application_helper.rb || exit 1
fi

# Validate database schema
bin/rails db:migrate || exit 1
```
