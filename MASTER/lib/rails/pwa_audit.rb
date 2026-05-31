# frozen_string_literal: true

require "json"

module Master
  module Rails
    class PwaAudit
      # Lighthouse 11 installability — all 5 required
      MANIFEST_REQUIRED = %w[name start_url display icons].freeze
      MANIFEST_RECOMMENDED = %w[short_name description theme_color background_color scope].freeze

      # Lighthouse requires 192x192 AND 512x512 for installability
      ICON_SIZES_REQUIRED = %w[192x192 512x512].freeze

      INSTALLABLE_DISPLAY_MODES = %w[standalone minimal-ui fullscreen].freeze

      # Never cache — auth, session, checkout, user-specific routes
      PRIVATE_PATTERNS = %w[/auth /login /logout /session /account /checkout /payment /admin].freeze

      # Current DEPLOY apps use plain cache-first (cached || fetch)
      # This is fine for static assets but wrong for dynamic content
      CACHE_FIRST_ONLY_SIGNAL = /caches\.match.*\|\|.*fetch(?!\s*\(request,\s*\{)/m

      # Rails 8.1: new Sec-Fetch-Site CSRF strategy; apps using null_session default should migrate
      CSRF_LEGACY_SIGNAL = /protect_from_forgery.*:null_session/

      Finding = Data.define(:field, :message, :severity)

      def initialize(root: Master::ROOT)
        @root = root
      end

      def audit(app_path = @root)
        manifest_rel = find_manifest(app_path)
        sw_rel = find_sw(app_path)

        manifest_findings = manifest_rel ? audit_manifest(app_path, manifest_rel) : [
          Finding.new(field: :manifest, message: "no manifest found (expected app/views/pwa/manifest.json.erb)", severity: :critical)
        ]
        sw_findings = sw_rel ? audit_sw(app_path, sw_rel) : [
          Finding.new(field: :service_worker, message: "no service worker found (expected app/views/pwa/service-worker.js)", severity: :high)
        ]

        csrf_findings = audit_csrf(app_path)
        all = manifest_findings + sw_findings + csrf_findings
        {
          manifest: manifest_rel,
          service_worker: sw_rel,
          installable: manifest_rel && sw_rel && all.none? { |f| f.severity == :critical },
          findings: all,
          violations: all.map(&:message),
          recommendations: recommendations(all)
        }
      end

      private

      def find_manifest(root)
        %w[
          app/views/pwa/manifest.json.erb
          app/views/pwa/manifest.webmanifest.erb
          public/manifest.json
          public/manifest.webmanifest
        ].map { |r| File.join(root, r) }.find { |p| File.exist?(p) }
         &.sub("#{root}/", "")
      end

      def find_sw(root)
        %w[
          app/views/pwa/service-worker.js
          public/service-worker.js
          app/javascript/service_worker.js
        ].map { |r| File.join(root, r) }.find { |p| File.exist?(p) }
         &.sub("#{root}/", "")
      end

      def audit_manifest(root, rel)
        source = File.read(File.join(root, rel))
        findings = []

        MANIFEST_REQUIRED.each do |field|
          unless source.match?(/["']#{Regexp.escape(field)}["']/)
            findings << Finding.new(field: field.to_sym, message: "manifest missing required field: #{field}", severity: :critical)
          end
        end

        MANIFEST_RECOMMENDED.each do |field|
          unless source.match?(/["']#{Regexp.escape(field)}["']/)
            findings << Finding.new(field: field.to_sym, message: "manifest missing recommended field: #{field}", severity: :low)
          end
        end

        ICON_SIZES_REQUIRED.each do |size|
          unless source.include?(size)
            findings << Finding.new(field: :icons, message: "manifest missing #{size} icon (Lighthouse installability requires both 192x192 and 512x512)", severity: :high)
          end
        end

        unless source.match?(/#{INSTALLABLE_DISPLAY_MODES.map { |m| Regexp.escape(m) }.join("|")}/)
          findings << Finding.new(field: :display, message: "display mode must be standalone, minimal-ui, or fullscreen", severity: :high)
        end

        if source.match?(/prefer_related_applications.*true/)
          findings << Finding.new(field: :prefer_related_applications, message: "prefer_related_applications: true blocks installability", severity: :critical)
        end

        findings
      rescue StandardError => e
        [Finding.new(field: :manifest, message: "could not read manifest: #{e.message}", severity: :critical)]
      end

      def audit_sw(root, rel)
        source = File.read(File.join(root, rel))
        findings = []

        PRIVATE_PATTERNS.each do |pattern|
          if source.match?(/["']#{Regexp.escape(pattern)}/)
            findings << Finding.new(field: :cache_policy, message: "service worker caches private path #{pattern} — never cache auth/session routes", severity: :critical)
          end
        end

        # Cache-first for all requests is wrong for dynamic content; network-first required.
        if source.match?(CACHE_FIRST_ONLY_SIGNAL) && !source.match?(/network.?first|NetworkFirst|networkFirst/i)
          findings << Finding.new(
            field: :strategy,
            message: "cache-first applied to all GET requests — dynamic content (feeds, profiles) should use network-first or stale-while-revalidate",
            severity: :medium
          )
        end

        unless source.match?(/offline|fallback/i)
          findings << Finding.new(field: :offline, message: "no offline fallback page — add a /offline route and cache it at SW install time", severity: :low)
        end

        unless source.match?(/sync|background.?sync/i)
          findings << Finding.new(field: :background_sync, message: "no background sync — consider queuing form submissions for offline resilience", severity: :low)
        end

        findings
      rescue StandardError => e
        [Finding.new(field: :service_worker, message: "could not read service worker: #{e.message}", severity: :high)]
      end

      def audit_csrf(path)
        controller_base = File.join(path, "app", "controllers", "application_controller.rb")
        return [] unless File.exist?(controller_base)
        source = File.read(controller_base)
        return [] unless source.match?(CSRF_LEGACY_SIGNAL)
        [Finding.new(
          field: :csrf,
          message: "protect_from_forgery with: :null_session is deprecated in Rails 8.1 — migrate to Sec-Fetch-Site header strategy",
          severity: :medium
        )]
      rescue StandardError
        []
      end

      def recommendations(findings)
        findings.sort_by { |f| severity_rank(f.severity) }.map do |f|
          "[#{f.severity.upcase}] #{f.field}: #{f.message}"
        end
      end

      def severity_rank(s)
        { critical: 0, high: 1, medium: 2, low: 3 }.fetch(s, 9)
      end
    end
  end
end
