#!/bin/sh
set -eu

BASE="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SHARED="$BASE/shared"
APPS="amber brgen baibl blognet bsdports hjerterom"

# DEPRECATED (engine-ize complete): use Gemfile 'gem "pub4-shared", path: "../../shared"' + bundle.
# This script kept only for one-off bootstrap. Update all deploys/openbsd to pure bundle. See WIRING_NOTES.md.

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
  copy_one "$app" app/controllers/concerns/shared/live_searchable.rb app/controllers/concerns/shared/live_searchable.rb
  copy_one "$app" app/controllers/concerns/shared/structured_events.rb app/controllers/concerns/shared/structured_events.rb
  copy_one "$app" app/controllers/concerns/shared/media_guard.rb app/controllers/concerns/shared/media_guard.rb
  copy_one "$app" app/jobs/shared/media_processing_job.rb app/jobs/shared/media_processing_job.rb
  copy_one "$app" app/services/shared/live_search.rb app/services/shared/live_search.rb
  copy_one "$app" app/services/shared/event_emitter.rb app/services/shared/event_emitter.rb
  copy_one "$app" app/views/shared/_copyable.html.erb app/views/shared/_copyable.html.erb
done
