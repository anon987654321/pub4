```bash
#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

# Privcam setup: Private video sharing platform with live search, infinite scroll, and anonymous features on OpenBSD 7.8, unprivileged user

APP_NAME="privcam"

BASE_DIR="/home/dev/rails"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SERVER_IP="185.52.176.18"

APP_PORT=$((10000 + RANDOM % 10000))

source "${SCRIPT_DIR}/@shared_functions.sh"

# Idempotency: skip if already generated
check_app_exists "$APP_NAME" "app/models/video.rb" && exit 0

log "Starting Privcam setup"

setup_full_app "$APP_NAME"

command_exists "ruby"

command_exists "node"

command_exists "psql"

# Redis optional - using Solid Cable for ActionCable (Rails 8 default)
install_gem "faker"

# Patch ApplicationController with Pagy::Backend (idempotent)
grep -q "Pagy::Backend" app/controllers/application_controller.rb 2>/dev/null || \
  sed -i 's/class ApplicationController < ActionController::Base/class ApplicationController < ActionController::Base\n  include Pagy::Backend/' \
  app/controllers/application_controller.rb
grep -q "Pagy::Frontend" app/helpers/application_helper.rb 2>/dev/null || \
  sed -i 's/module ApplicationHelper/module ApplicationHelper\n  include Pagy::Frontend/' \
  app/helpers/application_helper.rb

# Setup Rails 8 authentication
[[ -f "app/models/session.rb" ]] || bin/rails generate authentication && bin/rails db:migrate

bin/rails generate scaffold Video title:string description:text user:references file:attachment

bin/rails generate scaffold Comment video:references user:references content:text

cat <<'EOF' > app/reflexes/videos_infinite_scroll_reflex.rb
class VideosInfiniteScrollReflex < InfiniteScrollReflex
  def load_more
    @pagy, @collection = pagy(Video.all.order(created_at: :desc), page: page)
    super
  end
end
EOF

cat <<'EOF' > app/reflexes/comments_infinite_scroll_reflex.rb
class CommentsInfiniteScrollReflex < InfiniteScrollReflex
  def load_more
    @pagy, @collection = pagy(Comment.all.order(created_at: :desc), page: page)
    super
  end
end
EOF

# Cleanup and validation
log "Privcam setup completed successfully"
exit 0
```
