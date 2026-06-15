#!/bin/sh
set -eu

BASE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SHARED="$BASE/shared"
APPS="amber brgen baibl blognet bsdports hjerterom"

copy_one() {
  app="$1"
  src="$2"
  dst="$3"
  [ -f "$SHARED/$src" ] || return 0
  mkdir -p "$(dirname "$BASE/$app/$dst")"
  cp "$SHARED/$src" "$BASE/$app/$dst"
  printf '%s: %s\n' "$app" "$dst"
}

for app in ${1:-$APPS}; do
  copy_one "$app" frontend/stimulus_components.js app/javascript/stimulus_components.js
  copy_one "$app" frontend/register_stimulus_components.js app/javascript/register_stimulus_components.js
  copy_one "$app" frontend/controllers/scroll_progress_controller.js app/javascript/controllers/scroll_progress_controller.js
  copy_one "$app" frontend/controllers/toast_controller.js app/javascript/controllers/toast_controller.js
  copy_one "$app" frontend/controllers/map_controller.js app/javascript/controllers/map_controller.js
  copy_one "$app" frontend/controllers/pwa_install_controller.js app/javascript/controllers/pwa_install_controller.js
  copy_one "$app" frontend/controllers/pwa_standalone_controller.js app/javascript/controllers/pwa_standalone_controller.js
  copy_one "$app" frontend/controllers/offline_feed_controller.js app/javascript/controllers/offline_feed_controller.js
  copy_one "$app" frontend/controllers/offline_feed_cache_controller.js app/javascript/controllers/offline_feed_cache_controller.js
  copy_one "$app" frontend/controllers/offline_draft_controller.js app/javascript/controllers/offline_draft_controller.js
  copy_one "$app" frontend/controllers/offline_sync_controller.js app/javascript/controllers/offline_sync_controller.js
  copy_one "$app" frontend/controllers/sw_update_controller.js app/javascript/controllers/sw_update_controller.js
  copy_one "$app" frontend/controllers/wake_lock_controller.js app/javascript/controllers/wake_lock_controller.js
  copy_one "$app" frontend/controllers/orientation_lock_controller.js app/javascript/controllers/orientation_lock_controller.js
  copy_one "$app" frontend/pwa/offline_store.js app/javascript/pwa/offline_store.js
  copy_one "$app" frontend/pwa/bootstrap.js app/javascript/pwa/bootstrap.js
  copy_one "$app" app/views/pwa/service-worker.js.erb app/views/pwa/service-worker.js.erb
  copy_one "$app" app/controllers/offline_controller.rb app/controllers/offline_controller.rb
  copy_one "$app" app/views/offline/show.html.erb app/views/offline/show.html.erb
  copy_one "$app" app/views/shared/_pwa_install_banner.html.erb app/views/shared/_pwa_install_banner.html.erb
  copy_one "$app" app/views/shared/_pwa_shell.html.erb app/views/shared/_pwa_shell.html.erb
  copy_one "$app" public/styles/pwa.css public/styles/pwa.css
  copy_one "$app" app/controllers/concerns/shared/live_searchable.rb app/controllers/concerns/shared/live_searchable.rb
  copy_one "$app" app/controllers/concerns/shared/structured_events.rb app/controllers/concerns/shared/structured_events.rb
  copy_one "$app" app/controllers/concerns/shared/media_guard.rb app/controllers/concerns/shared/media_guard.rb
  copy_one "$app" app/jobs/shared/media_processing_job.rb app/jobs/shared/media_processing_job.rb
  copy_one "$app" app/services/shared/live_search.rb app/services/shared/live_search.rb
  copy_one "$app" app/services/shared/search_analytics.rb app/services/shared/search_analytics.rb
  copy_one "$app" app/services/shared/search_suggestions.rb app/services/shared/search_suggestions.rb
  copy_one "$app" frontend/live_search_controller.js app/javascript/controllers/live_search_controller.js
  copy_one "$app" app/views/shared/_search_form.html.erb app/views/shared/_search_form.html.erb
  copy_one "$app" app/views/shared/_search_results.html.erb app/views/shared/_search_results.html.erb
  copy_one "$app" app/views/shared/_search_empty.html.erb app/views/shared/_search_empty.html.erb
  copy_one "$app" app/views/shared/_search_loading.html.erb app/views/shared/_search_loading.html.erb
  copy_one "$app" app/views/shared/_search_suggestions.html.erb app/views/shared/_search_suggestions.html.erb
  copy_one "$app" app/services/shared/event_emitter.rb app/services/shared/event_emitter.rb
  copy_one "$app" app/views/shared/_copyable.html.erb app/views/shared/_copyable.html.erb
done
