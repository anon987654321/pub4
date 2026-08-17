# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"
require_relative "../../support/geometry_probe"

module Deploy
  # Three apps mount one shared engine. Nothing currently asserts that the
  # shared parts still render the same way in all three.
  #
  # This is not hypothetical drift: per-app copies of the compose/save/upload
  # Stimulus controllers existed until they were deleted in favour of
  # shared/frontend, and nothing prevents that divergence returning. Source
  # gates check the shared files are *registered*; this checks they are
  # actually *rendered*, and that the shared chrome has the same shape
  # everywhere.
  class CrossAppEquivalenceGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    SHARED_FRONTEND = File.join(RAILS_ROOT, "shared", "frontend")

    # The contract every app's layout owes the shared engine, as rendered.
    CHROME = <<~JS
      (() => {
        const skip = document.querySelector('a.skip-link, a[href="#main-content"]');
        const main = document.querySelector('#main-content, main');
        const nav = document.querySelector('nav[aria-label], nav');
        const controllers = new Set();
        document.querySelectorAll('[data-controller]').forEach(el => {
          String(el.getAttribute('data-controller') || '').split(/\\s+/)
            .filter(Boolean).forEach(c => controllers.add(c));
        });
        return {
          skip_href: skip ? skip.getAttribute('href') : null,
          skip_text: skip ? (skip.textContent || '').trim() : null,
          main_id: main ? main.id : null,
          main_tag: main ? main.tagName.toLowerCase() : null,
          nav_aria: nav ? nav.getAttribute('aria-label') : null,
          has_footer: !!document.querySelector('footer'),
          lang: document.documentElement.getAttribute('lang'),
          viewport_meta: (document.querySelector('meta[name=viewport]') || {}).content || null,
          color_scheme: (document.querySelector('meta[name=color-scheme]') || {}).content || null,
          controllers: Array.from(controllers).sort()
        };
      })()
    JS

    def self.run = new.run

    def run
      @result = GateResult.new
      unless GeometryProbe.available?
        @result.inconclusive!("cross_app: no Chrome/Chromium — shared chrome not compared")
        return @result
      end

      surfaces = GeometryProbe.surfaces
                              .select { |s| s.viewport == "desktop" }
                              .group_by(&:app)
                              .transform_values(&:first)
                              .values
      GeometryProbe.unreachable_apps(surfaces).each { |app| @result.skipped_live("cross_app: #{app} port closed — skipped") }
      live = GeometryProbe.reachable(surfaces)
      if live.size < 2
        @result.inconclusive!("cross_app: need at least two apps running to compare (have #{live.size})")
        return @result
      end

      chrome = {}
      GeometryProbe.with_browser do |cdp|
        live.each do |surface|
          payload = GeometryProbe.walk(cdp, surface)
          unless GeometryProbe.ok?(payload)
            @result.fail("cross_app: #{surface.app} unreachable (#{payload["error"] || "HTTP #{payload["status"]}"})")
            next
          end
          chrome[surface.app] = cdp.evaluate(CHROME)
        end
      end
      return @result if chrome.size < 2

      compare_chrome(chrome)
      compare_controllers(chrome)
      @result.warn("cross_app: compared shared chrome across #{chrome.keys.sort.join(', ')}")
      @result
    end

    private

    # Fields where the shared engine dictates one answer for every app. Nav
    # labels and lang are deliberately excluded — those are per-app content.
    INVARIANT = {
      "skip_href" => "the shared skip link target",
      "main_id" => "the shared main landmark id",
      "main_tag" => "the shared main landmark element",
      "viewport_meta" => "the shared viewport meta",
    }.freeze

    def compare_chrome(chrome)
      INVARIANT.each do |field, description|
        values = chrome.transform_values { |c| c[field] }
        distinct = values.values.uniq
        next if distinct.size <= 1

        detail = values.map { |app, value| "#{app}=#{value.inspect}" }.join(", ")
        @result.fail(
          "cross_app chrome: #{description} differs between apps — #{detail}. " \
          "These render from shared/frontend/layouts and must agree."
        )
      end

      missing = chrome.reject { |_app, c| c["skip_href"] }.keys
      unless missing.empty?
        @result.fail("cross_app chrome: #{missing.join(', ')} render no skip link at all (principle=accessibility)")
      end

      no_footer = chrome.reject { |_app, c| c["has_footer"] }.keys
      return if no_footer.empty? || no_footer.size == chrome.size

      @result.fail(
        "cross_app chrome: #{no_footer.join(', ')} render no footer while #{(chrome.keys - no_footer).join(', ')} do — " \
        "the shared footer partial is not reaching every app",
        severity: :soft
      )
    end

    # Two distinct questions, and conflating them produces noise:
    #
    #   "Does every app instantiate every shared controller?" — No, and it
    #   should not. bsdports has no feed, so feed-compose legitimately never
    #   renders there. Asserting that is a false positive factory.
    #
    #   "Does every app instantiate the controllers the *shared layout* mounts?"
    #   — Yes, necessarily: those come from shared/frontend/layouts, which all
    #   three apps render. A divergence there is real drift.
    #
    # Only the second is a contract. The first is reported as an inventory
    # warning: a shared controller nobody mounts anywhere is dead code.
    def compare_controllers(chrome)
      rendered = chrome.transform_values { |c| Array(c["controllers"]) }
      anywhere = rendered.values.reduce(:|) || []

      layout_mounted = layout_controller_names
      layout_mounted.each do |name|
        has = rendered.select { |_app, list| list.include?(name) }.keys
        next if has.size == rendered.size || has.empty?

        @result.fail(
          "cross_app stimulus: #{name.inspect} is mounted by the shared layout but renders only in " \
          "#{has.join(', ')} — missing from #{(rendered.keys - has).join(', ')}",
          severity: :soft
        )
      end

      unused = shared_controller_names - anywhere
      return if unused.empty?

      @result.warn(
        "cross_app stimulus inventory: #{unused.size} shared controller(s) in shared/frontend are not instantiated " \
        "by any running app — #{unused.sort.join(', ')}. Not a contract violation (a controller may serve a surface " \
        "not probed here), but each is dead code until some view attaches data-controller."
      )
    end

    def shared_controller_names
      return [] unless File.directory?(SHARED_FRONTEND)

      Dir.children(SHARED_FRONTEND)
         .select { |f| f.end_with?("_controller.js") }
         .map { |f| f.sub(/_controller\.js\z/, "").tr("_", "-") }
         .sort
    end

    # Controllers the shared layout itself mounts — these every app renders.
    def layout_controller_names
      dir = File.join(SHARED_FRONTEND, "layouts")
      return [] unless File.directory?(dir)

      Dir.glob(File.join(dir, "*.erb")).flat_map do |path|
        File.read(path).scan(/data-controller="([a-z0-9 _-]+)"/i).flatten
      end.flat_map { |value| value.split(/\s+/) }.map { |c| c.tr("_", "-") }.uniq.sort
    end
  end
end
