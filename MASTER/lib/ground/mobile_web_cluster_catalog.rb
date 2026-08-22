# frozen_string_literal: true

module Master
  module Ground
    class MobileWebClusterCatalog
      Entry = Data.define(:repo, :pattern, :why, :risk, :tags)

      CATALOG = [
        Entry.new(
          repo: "hotwired/turbo",
          pattern: :turbo_core,
          why: "Authoritative source for Turbo Frame/Stream semantics and _top targeting",
          risk: :low,
          tags: %i[turbo hotwire rails_8 navigation],
        ),
        Entry.new(
          repo: "hotwired/stimulus",
          pattern: :stimulus_lifecycle,
          why: "connect/disconnect/initialize lifecycle — reference for DOMContentLoaded migration",
          risk: :low,
          tags: %i[stimulus hotwire lifecycle],
        ),
        Entry.new(
          repo: "excid3/jumpstart",
          pattern: :rails_8_pwa_starter,
          why: "Rails 8 omakase template with Hotwire, importmap, PWA manifest, mobile layout out of the box",
          risk: :low,
          tags: %i[rails_8 hotwire pwa mobile importmap],
        ),
        Entry.new(
          repo: "mattbrictson/rails-template",
          pattern: :rails_baseline_a11y,
          why: "Importmap + Hotwire baseline with accessibility defaults and mobile-first HTML structure",
          risk: :low,
          tags: %i[rails_8 importmap accessibility mobile_first],
        ),
        Entry.new(
          repo: "stimulus-components/stimulus-components",
          pattern: :stimulus_component_library,
          why: "Drop-in Stimulus controllers: dialog, dropdown, clipboard, confirm — removes custom jQuery patterns",
          risk: :low,
          tags: %i[stimulus components accessibility jquery_replacement],
        ),
        Entry.new(
          repo: "lazaronixon/css-zero",
          pattern: :css_zero_mobile_first,
          why: "Rails-native CSS reset: mobile-first, no JS, system fonts, 44px touch targets, focus-visible baked in",
          risk: :low,
          tags: %i[css mobile_first touch_targets focus_visible minimal],
        ),
        Entry.new(
          repo: "rails/solid_queue",
          pattern: :solid_queue,
          why: "DB-backed background jobs replacing Redis/Sidekiq for simpler Rails 8 stacks",
          risk: :low,
          tags: %i[solid_queue rails_8 jobs simplification],
        ),
        Entry.new(
          repo: "rails/solid_cache",
          pattern: :solid_cache,
          why: "DB-backed cache store — eliminates Redis dependency for most caching needs",
          risk: :low,
          tags: %i[solid_cache rails_8 simplification],
        ),
        Entry.new(
          repo: "rails/solid_cable",
          pattern: :solid_cable,
          why: "DB-backed Action Cable adapter — replaces Redis for ActionCable in Rails 8",
          risk: :low,
          tags: %i[solid_cable rails_8 action_cable],
        ),
        Entry.new(
          repo: "rossta/serviceworker-rails",
          pattern: :service_worker_rails,
          why: "Routes service-worker.js through Rails asset pipeline with cache-busting helpers",
          risk: :low,
          tags: %i[pwa service_worker rails cache],
        ),
      ].freeze

      INTENT_TAG_MAP = {
        refactor_existing: %i[jquery_replacement stimulus components hotwire lifecycle],
        audit_rails_pwa: %i[pwa service_worker cache mobile_first touch_targets],
        generate_rails_pwa: %i[rails_8 hotwire pwa mobile importmap],
        redesign_mobile_pwa: %i[css mobile_first focus_visible accessibility minimal],
      }.freeze

      def top(n = 5, tags: nil)
        filtered = tags ? CATALOG.select { |e| (e.tags & Array(tags)).any? } : CATALOG
        filtered.first(n)
      end

      def for_intent(intent)
        tags = INTENT_TAG_MAP.fetch(intent.to_sym, [])
        top(5, tags:)
      end

      def by_pattern(pattern)
        CATALOG.select { |e| e.pattern == pattern.to_sym }
      end
    end
  end
end
