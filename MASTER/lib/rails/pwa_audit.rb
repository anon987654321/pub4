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

      # Current OPERATOR apps use plain cache-first (cached || fetch)
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
          Finding.new(field: :manifest, message: "no manifest found (expected app/views/pwa/manifest.json.erb)", severity: :critical),
        ]
        sw_findings = sw_rel ? audit_sw(app_path, sw_rel) : [
          Finding.new(field: :service_worker, message: "no service worker found (expected app/views/pwa/service-worker.js)", severity: :high),
        ]

        csrf_findings = audit_csrf(app_path)
        all = manifest_findings + sw_findings + csrf_findings
        {
          manifest: manifest_rel,
          service_worker: sw_rel,
          installable: manifest_rel && sw_rel && all.none? { |f| f.severity == :critical },
          findings: all,
          violations: all.map(&:message),
          recommendations: recommendations(all),
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
        missing_fields(source, MANIFEST_REQUIRED, :critical, "required") +
          missing_fields(source, MANIFEST_RECOMMENDED, :low, "recommended") +
          missing_icons(source) + display_findings(source) + related_application_findings(source)
      rescue StandardError => e
        [Finding.new(field: :manifest, message: "could not read manifest: #{e.message}", severity: :critical)]
      end

      def audit_sw(root, rel)
        source = File.read(File.join(root, rel))
        private_cache_findings(source) + strategy_findings(source) + resilience_findings(source)
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
          severity: :medium,
        )]
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "pwa_audit.audit_csrf", path:)
        []
      end

      def missing_fields(source, fields, severity, kind)
        fields.filter_map do |field|
          next if source.match?(/["']#{Regexp.escape(field)}["']/)

          Finding.new(field: field.to_sym, message: "manifest missing #{kind} field: #{field}", severity:)
        end
      end

      def missing_icons(source)
        ICON_SIZES_REQUIRED.filter_map do |size|
          next if source.include?(size)

          Finding.new(field: :icons, message: "manifest missing #{size} icon", severity: :high)
        end
      end

      def display_findings(source)
        modes = Regexp.union(INSTALLABLE_DISPLAY_MODES)
        return [] if source.match?(modes)

        [Finding.new(field: :display, message: "display mode must be installable", severity: :high)]
      end

      def related_application_findings(source)
        return [] unless source.match?(/prefer_related_applications.*true/)

        [Finding.new(field: :prefer_related_applications,
                     message: "prefer_related_applications: true blocks installability", severity: :critical)]
      end

      def private_cache_findings(source)
        PRIVATE_PATTERNS.filter_map do |pattern|
          next unless source.match?(/["']#{Regexp.escape(pattern)}/)

          Finding.new(field: :cache_policy, message: "service worker caches private path #{pattern}", severity: :critical)
        end
      end

      def strategy_findings(source)
        cache_only = source.match?(CACHE_FIRST_ONLY_SIGNAL) && !source.match?(/network.?first|NetworkFirst/i)
        return [] unless cache_only

        [Finding.new(field: :strategy, message: "cache-first applied to all GET requests", severity: :medium)]
      end

      def resilience_findings(source)
        findings = []
        unless source.match?(/offline|fallback/i)
          findings << Finding.new(field: :offline, message: "no offline fallback page", severity: :low)
        end
        unless source.match?(/sync|background.?sync/i)
          findings << Finding.new(field: :background_sync, message: "no background sync", severity: :low)
        end
        findings
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
