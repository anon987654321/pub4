# DEPLOY Snapshot (engine-ize + Rails family for LLM eval)
Generated: 2026-06-15T03:14:02Z
Root: pub4/DEPLOY

## rails/shared/lib/shared/engine.rb (terse Unixy 10L)
```ruby
# frozen_string_literal: true
module Shared
  class Engine < ::Rails::Engine
    isolate_namespace Shared
    config.autoload_paths += %W[#{root}/app/models/concerns #{root}/app/services #{root}/app/controllers/concerns]
    config.eager_load_paths += config.autoload_paths
    config.active_record.schema_format = :ruby if config.respond_to?(:active_record)
    def self.concern(n); const_get("Shared::#{n.to_s.camelize}") rescue (require "shared/#{n}"; const_get("Shared::#{n.to_s.camelize}")) end
  end
end
```

## 6x Gemfile pub4-shared lines (all apps)
### brgen/Gemfile (engine line)
46:gem 'pub4-shared', path: '../../shared'
### amber/Gemfile (engine line)
61:gem 'pub4-shared', path: '../../shared'
### hjerterom/Gemfile (engine line)
59:gem 'pub4-shared', path: '../../shared'
### bsdports/Gemfile (engine line)
58:gem 'pub4-shared', path: '../../shared'
### baibl/Gemfile (engine line)
59:gem 'pub4-shared', path: '../../shared'
### blognet/Gemfile (engine line)
59:gem 'pub4-shared', path: '../../shared'

## WIRING_NOTES (engine section head)
```md
# Shared Rails wiring notes

**Current model (engine-ize 2026):** `shared/` is a real Rails engine gem (pub4-shared) loaded via local path in each app Gemfile.
`bundle install` + `gem 'pub4-shared', path: '../../shared'` (relative from rails/<app>) wires everything.
Engine (shared/lib/shared/engine.rb, 10 terse lines): isolate_namespace, autoloads concerns/services, provides `Shared.concern(n)` helper for lazy require+const.
No more per-app copies for core concerns; install_*.sh deprecated (kept only for legacy bootstrap).

See engine.rb for autoload + concern(n). All 6 apps (brgen+5) wired. Root snapshots capture state for eval.

## Engine wiring (preferred)

All apps declare in Gemfile (bo```

## Prune + deprecate status
- Stray "amber brgen baibl..." dir: rm -rf done
- install_*.sh + openbsd.sh: DEPRECATED annotations added
- install scripts no longer primary; bundle is truth

## Rails apps ls (post-prune)
amber
apps.yml
ARCHITECTURE_NOTES.md
baibl
blognet
brgen
bsdports
check_ports.sh
check_production_gate.rb
env.sample
hjerterom
LIVE_SEARCH_STANDARD.md
marketplace
PRODUCTION_READINESS.md
README.md
shared
test_check_ports.sh

See DEPLOY/TODO.md (AN1-17 PWA/Rails8/Auth/Solid/Hotwire + AP design system) + PRODUCTION_READINESS for remaining.
Engine rollout + snapshots + NN ARIA + cleanup: advancing to perfect.
