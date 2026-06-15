#!/bin/sh
set -eu

BASE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SHARED="$BASE/shared"
APPS="amber brgen baibl blognet bsdports hjerterom"

# DEPRECATED (engine-ize): shared concerns/jobs now via pub4-shared engine gem (autoload + Shared.concern(n)).
# Legacy copies removed from primary path. Bundle is source of truth. Prune after verify.

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
  # AN2 Auth
  copy_one "$app" app/controllers/concerns/shared/auth_rate_limiting.rb app/controllers/concerns/shared/auth_rate_limiting.rb
  copy_one "$app" app/controllers/concerns/shared/remember_me.rb app/controllers/concerns/shared/remember_me.rb
  copy_one "$app" app/controllers/concerns/shared/device_fingerprinting.rb app/controllers/concerns/shared/device_fingerprinting.rb
  copy_one "$app" app/controllers/concerns/shared/suspicious_login_detection.rb app/controllers/concerns/shared/suspicious_login_detection.rb
  copy_one "$app" app/controllers/concerns/shared/pundit_authorization.rb app/controllers/concerns/shared/pundit_authorization.rb
  copy_one "$app" app/controllers/concerns/shared/passwordless_auth.rb app/controllers/concerns/shared/passwordless_auth.rb
  copy_one "$app" app/controllers/concerns/shared/two_factor_auth.rb app/controllers/concerns/shared/two_factor_auth.rb
  copy_one "$app" app/controllers/concerns/shared/account_deletion.rb app/controllers/concerns/shared/account_deletion.rb
  copy_one "$app" app/policies/application_policy.rb app/policies/application_policy.rb
  copy_one "$app" app/models/device_login.rb app/models/device_login.rb

  # AN3 Jobs
  copy_one "$app" app/jobs/concerns/shared/external_api_retry.rb app/jobs/concerns/shared/external_api_retry.rb
  copy_one "$app" app/jobs/shared/notification_delivery_job.rb app/jobs/shared/notification_delivery_job.rb
  copy_one "$app" app/jobs/shared/auth_email_job.rb app/jobs/shared/auth_email_job.rb
  copy_one "$app" app/jobs/shared/search_index_rebuild_job.rb app/jobs/shared/search_index_rebuild_job.rb
  copy_one "$app" app/jobs/shared/analytics_rollup_job.rb app/jobs/shared/analytics_rollup_job.rb
  copy_one "$app" app/jobs/shared/dead_letter_digest_job.rb app/jobs/shared/dead_letter_digest_job.rb
  copy_one "$app" app/jobs/shared/account_hard_delete_job.rb app/jobs/shared/account_hard_delete_job.rb
  copy_one "$app" app/jobs/shared/account_export_job.rb app/jobs/shared/account_export_job.rb
  copy_one "$app" app/services/shared/account_exporter.rb app/services/shared/account_exporter.rb
  copy_one "$app" app/services/shared/search_index.rb app/services/shared/search_index.rb
  copy_one "$app" config/recurring.yml config/recurring.yml
  copy_one "$app" config/queue.yml config/queue.yml

  # AN4 Turbo
  copy_one "$app" app/controllers/concerns/shared/turbo_frames.rb app/controllers/concerns/shared/turbo_frames.rb
  copy_one "$app" app/controllers/concerns/shared/turbo_streamable.rb app/controllers/concerns/shared/turbo_streamable.rb
  copy_one "$app" app/controllers/concerns/shared/turbo_morphing.rb app/controllers/concerns/shared/turbo_morphing.rb
  copy_one "$app" app/controllers/turbo_sse_updates_controller.rb app/controllers/turbo_sse_updates_controller.rb
  copy_one "$app" app/views/shared/_turbo_frame_list.html.erb app/views/shared/_turbo_frame_list.html.erb
  copy_one "$app" app/views/shared/_turbo_permanent_nav.html.erb app/views/shared/_turbo_permanent_nav.html.erb
  copy_one "$app" public/styles/turbo.css public/styles/turbo.css

  # AN5 Stimulus
  copy_one "$app" frontend/controllers/infinite_scroll_controller.js app/javascript/controllers/infinite_scroll_controller.js
  copy_one "$app" frontend/controllers/pull_to_refresh_controller.js app/javascript/controllers/pull_to_refresh_controller.js
  copy_one "$app" frontend/controllers/swipe_controller.js app/javascript/controllers/swipe_controller.js
  copy_one "$app" frontend/controllers/bottom_sheet_controller.js app/javascript/controllers/bottom_sheet_controller.js
  copy_one "$app" frontend/controllers/lazy_image_controller.js app/javascript/controllers/lazy_image_controller.js
  copy_one "$app" frontend/controllers/autosave_controller.js app/javascript/controllers/autosave_controller.js
  copy_one "$app" frontend/controllers/toggle_controller.js app/javascript/controllers/toggle_controller.js
  copy_one "$app" frontend/controllers/tabs_controller.js app/javascript/controllers/tabs_controller.js
  copy_one "$app" frontend/controllers/optimistic_ui_controller.js app/javascript/controllers/optimistic_ui_controller.js
  copy_one "$app" frontend/controllers/turbo_form_validation_controller.js app/javascript/controllers/turbo_form_validation_controller.js
  copy_one "$app" frontend/controllers/turbo_native_bridge_controller.js app/javascript/controllers/turbo_native_bridge_controller.js
  copy_one "$app" frontend/controllers/datepicker_controller.js app/javascript/controllers/datepicker_controller.js
  copy_one "$app" frontend/controllers/blur_hash_controller.js app/javascript/controllers/blur_hash_controller.js

  # Initializers
  copy_one "$app" config/initializers/session_fixation.rb config/initializers/session_fixation.rb
  copy_one "$app" config/initializers/solid_cache.rb config/initializers/solid_cache.rb
  copy_one "$app" config/initializers/solid_cable_monitor.rb config/initializers/solid_cable_monitor.rb
  copy_one "$app" config/initializers/turbo.rb config/initializers/turbo.rb
  copy_one "$app" config/initializers/pundit.rb config/initializers/pundit.rb
done

echo "AN stack installed to: ${1:-$APPS}"