```bash
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Privcam setup: Private video sharing platform with live search, infinite scroll, and anonymous features on OpenBSD 7.8, unprivileged user

APP_NAME="privcam"

BASE_DIR="/home/dev/rails"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SERVER_IP="185.52.176.18"

APP_PORT=3000

source "${SCRIPT_DIR}/@shared_functions.sh"

# Idempotency: comprehensive check
check_app_exists "$APP_NAME" "app/models/video.rb" "app/models/comment.rb" "app/reflexes/videos_infinite_scroll_reflex.rb" && exit 0

log "Starting Privcam setup"

setup_full_app "$APP_NAME"

command_exists "ruby" || { log "Ruby not found"; exit 1; }
command_exists "node" || { log "Node.js not found"; exit 1; }
command_exists "psql" || { log "PostgreSQL not found"; exit 1; }

# Install required gems
install_gem "faker" || { log "Failed to install faker"; exit 1; }
install_gem "pagy" || { log "Failed to install pagy"; exit 1; }

# Patch ApplicationController with Pagy::Backend (idempotent)
if ! grep -q "Pagy::Backend" app/controllers/application_controller.rb 2>/dev/null; then
  sed -i '' 's/class ApplicationController < ActionController::Base/class ApplicationController < ActionController::Base\
  include Pagy::Backend/' \
  app/controllers/application_controller.rb || { log "Failed to patch ApplicationController"; exit 1; }
fi

if ! grep -q "Pagy::Frontend" app/helpers/application_helper.rb 2>/dev/null; then
  sed -i '' 's/module ApplicationHelper/module ApplicationHelper\
  include Pagy::Frontend/' \
  app/helpers/application_helper.rb || { log "Failed to patch ApplicationHelper"; exit 1; }
fi

# Setup Rails 8 authentication
if [[ ! -f "app/models/session.rb" ]]; then
  bin/rails generate authentication || { log "Authentication generation failed"; exit 1; }
  bin/rails db:migrate || { log "Authentication migration failed"; exit 1; }
fi

bin/rails generate scaffold Video title:string description:text user:references file:attachment || { log "Video scaffold generation failed"; exit 1; }
bin/rails generate scaffold Comment video:references user:references content:text || { log "Comment scaffold generation failed"; exit 1; }
```
