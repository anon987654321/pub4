# frozen_string_literal: true

module Master
  module Rails
    class Rails8AppAudit
      DEPLOY_RAILS = Master::DEPLOY_RAILS

      DOCTRINE = Master::Ground::Axioms::RailsDoctrine::PILLARS
      SOLID_TRIFECTA = Master::Ground::Axioms::RailsDoctrine::SOLID_TRIFECTA

      GEMS_WANTED = %w[turbo-rails stimulus-rails importmap-rails propshaft solid_queue solid_cache solid_cable falcon].freeze
      GEMS_LEGACY = %w[jquery-rails rails-ujs sprockets sprockets-rails].freeze

      PWA_MANIFEST_CANDIDATES = %w[
        app/views/pwa/manifest.json.erb
        app/views/pwa/manifest.webmanifest.erb
        public/manifest.json
        public/manifest.webmanifest
      ].freeze

      SW_CANDIDATES = %w[
        app/views/pwa/service-worker.js
        public/service-worker.js
        app/javascript/service_worker.js
      ].freeze

      def initialize(root: Master::ROOT)
        @root = root
      end

      def self.deploy_apps
        return [] unless Dir.exist?(DEPLOY_RAILS)
        Dir.entries(DEPLOY_RAILS)
           .reject { |e| e.start_with?(".", "_") }
           .select { |e| Dir.exist?(File.join(DEPLOY_RAILS, e, "app")) }
           .sort
      end

      def scan(app_path = @root)
        gems = gemfile_gems(app_path)
        js_src = read_js(app_path)

        {
          app: File.basename(app_path),
          path: app_path,
          rails_version: detect_rails_version(app_path),
        }.merge(hotwire_and_assets_summary(gems)).merge(gem_and_pwa_summary(app_path, gems, js_src))
      end

      def hotwire_and_assets_summary(gems)
        {
          hotwire: {
            turbo: gems.include?("turbo-rails"),
            stimulus: gems.include?("stimulus-rails"),
            importmap: gems.include?("importmap-rails"),
            jsbundling: gems.include?("jsbundling-rails"),
          },
          assets: {
            propshaft: gems.include?("propshaft"),
            sprockets: gems.any? { |g| g.start_with?("sprockets") },
          },
          app_server: {
            falcon: gems.include?("falcon"),
          },
        }
      end

      def gem_and_pwa_summary(app_path, gems, js_src)
        {
          solid_adapters: subset(gems, SOLID_TRIFECTA),
          trifecta_complete: SOLID_TRIFECTA.all? { |g| gems.include?(g) },
          legacy_gems: subset(gems, GEMS_LEGACY),
          missing: GEMS_WANTED - gems,
          doctrine_gaps: doctrine_gaps(gems),
          pwa: {
            manifest: find_file(app_path, PWA_MANIFEST_CANDIDATES),
            service_worker: find_file(app_path, SW_CANDIDATES),
          },
          js_signals: js_signals(js_src, app_path),
          partial_count: count_partials(app_path),
          shared_layout: shared_layout?(app_path),
        }
      end

      def scan_all_deploy
        apps = self.class.deploy_apps
        apps.map do |name|
          scan(File.join(DEPLOY_RAILS, name))
        rescue StandardError => e
          { app: name, error: e.message }
        end
      end

      private

      def gemfile_gems(path)
        gemfile = File.join(path, "Gemfile")
        return [] unless File.exist?(gemfile)
        File.readlines(gemfile, chomp: true).filter_map do |line|
          m = line.match(/^\s*gem\s+['"]([^'"]+)['"]/)
          m[1] if m
        end
      end

      def detect_rails_version(path)
        File.readlines(File.join(path, "Gemfile"), chomp: true)
            .find { |l| l.match?(/gem\s+['"]rails['"]/) }
            &.scan(/\d+\.\d+/)&.first
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rails8_app_audit.detect_rails_version", path:)
        nil
      end

      def find_file(root, candidates)
        candidates.map { |r| File.join(root, r) }.find { |p| File.exist?(p) }
                  &.sub("#{root}/", "")
      end

      def read_js(path)
        Dir.glob(File.join(path, "app", "javascript", "**", "*.js")).first(20)
           .map { |f| File.read(f) rescue "" }.join("\n")
      end

      def js_signals(source, path)
        signals = []
        signals << :dom_content_loaded if source.match?(/DOMContentLoaded/)
        signals << :turbo_lifecycle if source.match?(/turbo:load|turbo:frame-load/)
        signals << :jquery_present if source.match?(/\$\(|\bjQuery\b/)
        signals << :sw_registered if source.match?(/serviceWorker\.register/)
        signals << :cache_first_sw if cache_first_sw?(path)
        signals
      end

      # cache-first pattern: serve cached unconditionally; network only for misses
      def cache_first_sw?(path)
        sw_rel = find_file(path, SW_CANDIDATES)
        return false unless sw_rel
        src = File.read(File.join(path, sw_rel))
        src.match?(/caches\.match.*\|\|.*fetch/m)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rails8_app_audit.cache_first_sw", path:)
        false
      end

      def count_partials(path)
        Dir.glob(File.join(path, "app", "views", "**", "_*.html.erb")).size
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "rails8_app_audit.count_partials", path:)
        0
      end

      def shared_layout?(path)
        Dir.exist?(File.join(File.dirname(path), "__shared"))
      end

      def subset(gems, wanted) = wanted & gems

      # Maps missing gems to the doctrine pillar that motivates adding them.
      def doctrine_gaps(gems)
        gaps = []
        unless SOLID_TRIFECTA.all? { |g| gems.include?(g) }
          missing = SOLID_TRIFECTA - gems
          gaps << { pillar: DOCTRINE[:integrated], gap: "Solid Trifecta incomplete — missing: #{missing.join(', ')} (Redis dependency not yet eliminated)" }
        end
        unless gems.include?("propshaft")
          gaps << { pillar: DOCTRINE[:convention], gap: "propshaft not present — Rails 8 default asset pipeline, replaces Sprockets" }
        end
        unless gems.include?("falcon")
          gaps << { pillar: DOCTRINE[:integrated], gap: "falcon not present — expected app server for relayd/OpenBSD stack" }
        end
        if gems.any? { |g| GEMS_LEGACY.include?(g) }
          gaps << { pillar: DOCTRINE[:progress], gap: "legacy gems present: #{(gems & GEMS_LEGACY).join(', ')} — migrate to Hotwire/Propshaft equivalents" }
        end
        gaps
      end
    end
  end
end
