# frozen_string_literal: true

module Master
  module Rails
    class HotwireRefactorPolicy
      Rule = Data.define(:id, :signal, :replace_with, :severity, :guide)

      # Common upgrade gaps after jQuery → Hotwire adoption.
      JS_RULES = [
        Rule.new(
          id: :dom_content_loaded,
          signal: /DOMContentLoaded/,
          replace_with: "turbo:load or turbo:frame-load event listener",
          severity: :high,
          guide: "DOMContentLoaded does not fire on Turbo navigations after the first page load",
        ),
        Rule.new(
          id: :jquery_present,
          signal: /\$\(|\bjQuery\b/,
          replace_with: "Stimulus controller with targets and data-action",
          severity: :high,
          guide: "jQuery selectors are incompatible with Turbo — Turbo replaces DOM nodes on navigation",
        ),
        Rule.new(
          id: :remote_true,
          signal: /remote:\s*true|data-remote/,
          replace_with: "Turbo Frame wrapping the target + standard form/link",
          severity: :high,
          guide: "data-remote is rails-ujs; Turbo handles AJAX forms natively",
        ),
        Rule.new(
          id: :ujs_confirm,
          signal: /data:\s*\{\s*confirm:|data-confirm=/,
          replace_with: "Stimulus confirm controller (stimulus-components/confirm)",
          severity: :low,
          guide: "data-confirm is rails-ujs — use a Stimulus controller for modal confirmation",
        ),
        Rule.new(
          id: :turbo_disabled,
          signal: /data-turbo=["']false["']|turbo:\s*false/,
          replace_with: "investigate and re-enable Turbo unless form has file upload or third-party SDK",
          severity: :low,
          guide: "data-turbo=false disables Hotwire navigation — usually a crutch for unresolved JS errors",
        ),
        Rule.new(
          id: :full_page_link_in_frame,
          signal: /turbo_frame_tag.*src:|<turbo-frame/,
          replace_with: "add data-turbo-frame='_top' to links inside frames that should navigate the full page",
          severity: :low,
          guide: "Links inside Turbo Frames target the frame by default — add _top for full page navigation",
        ),
      ].freeze

      ERB_RULES = [
        Rule.new(
          id: :render_partial_ajax_candidate,
          signal: /render\s+partial:.*locals:/,
          replace_with: "Turbo Frame with lazy src: for independently navigable sections",
          severity: :low,
          guide: "Partials rendered with locals that power AJAX tabs/panels are better as turbo_frame_tag with src:",
        ),
        Rule.new(
          id: :respond_to_js,
          signal: /format\.js\s*\{|\.js\.erb/,
          replace_with: "respond_to(&:turbo_stream) with turbo_stream.replace/append/prepend",
          severity: :high,
          guide: "format.js with RJS/JS.ERB templates should become Turbo Stream responses",
        ),
      ].freeze

      SW_UPGRADE = {
        id: :cache_strategy_upgrade,
        current: "cache-first for all GET requests",
        recommended: {
          "static assets (*.js, *.css, images)" => "CacheFirst with versioned cache name",
          "navigation (HTML pages)" => "NetworkFirst with 10s timeout, fallback to cache",
          "API / user data" => "NetworkFirst — never serve stale user content",
          "auth routes (/login, /session)" => "NetworkOnly — never cache",
        },
        severity: :medium,
      }.freeze

      def violations_in(source, path: nil, type: :js)
        rules = type == :erb ? ERB_RULES : JS_RULES
        rules.filter_map do |rule|
          next unless source.match?(rule.signal)
          { rule: rule.id, path:, severity: rule.severity, replace_with: rule.replace_with, guide: rule.guide }
        end
      end

      def plan_for(app_state)
        steps = js_signal_steps(app_state) + missing_dependency_steps(app_state) + pwa_manifest_steps(app_state)
        steps.sort_by { |s| s[:priority] }
      end

      def js_signal_steps(app_state)
        steps = []
        signals = app_state.dig(:js_signals)
        if signals&.include?(:dom_content_loaded)
          steps << { priority: 1, action: "Replace DOMContentLoaded with document.addEventListener('turbo:load', ...)" }
        end
        if signals&.include?(:jquery_present)
          steps << { priority: 2, action: "Identify jQuery selectors — convert to Stimulus targets + data-action wiring" }
        end
        if signals&.include?(:cache_first_sw)
          steps << { priority: 3, action: "Upgrade service worker: split strategy by resource type (see SW_UPGRADE)" }
        end
        steps
      end

      def missing_dependency_steps(app_state)
        steps = []
        missing = Array(app_state[:missing])
        if missing.include?("solid_queue")
          steps << { priority: 4, action: "bundle add solid_queue && bin/rails solid_queue:install" }
        end
        if missing.include?("solid_cache")
          steps << { priority: 4, action: "bundle add solid_cache && bin/rails solid_cache:install" }
        end
        if missing.include?("propshaft")
          steps << { priority: 3, action: "bundle add propshaft && bundle remove sprockets sprockets-rails — Propshaft is the Rails 8 default asset pipeline" }
        end
        steps
      end

      def pwa_manifest_steps(app_state)
        return [] unless app_state.dig(:pwa, :manifest) && !app_state.dig(:pwa, :manifest_has_192)

        [{ priority: 5, action: "Add 192x192 icon to manifest — required for Lighthouse installability" }]
      end

      def sw_upgrade_plan = SW_UPGRADE
    end
  end
end
