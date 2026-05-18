# frozen_string_literal: true

module Master
  module Rails
  class Rails8AppAudit
    DEPLOY_RAILS = File.expand_path("../../DEPLOY/rails", Master::ROOT).freeze

    # Rails 8 defaults — all should be present in modern apps
    GEMS_WANTED = %w[turbo-rails stimulus-rails importmap-rails propshaft solid_queue solid_cache solid_cable].freeze

    # Legacy — presence signals migration work needed
    GEMS_LEGACY = %w[jquery-rails rails-ujs sprockets sprockets-rails].freeze

    # Rails 8 serves PWA files via controller from app/views/pwa/
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
      gems    = gemfile_gems(app_path)
      js_src  = read_js(app_path)

      {
        app:           File.basename(app_path),
        path:          app_path,
        rails_version: detect_rails_version(app_path),
        hotwire: {
          turbo:     gems.include?("turbo-rails"),
          stimulus:  gems.include?("stimulus-rails"),
          importmap: gems.include?("importmap-rails"),
          jsbundling: gems.include?("jsbundling-rails")
        },
        assets: {
          propshaft: gems.include?("propshaft"),
          sprockets: gems.any? { |g| g.start_with?("sprockets") }
        },
        app_server: {
          falcon: gems.include?("falcon"),
          puma:   gems.include?("puma")
        },
        solid_adapters: subset(gems, %w[solid_queue solid_cache solid_cable]),
        legacy_gems:    subset(gems, GEMS_LEGACY),
        missing:        GEMS_WANTED - gems,
        pwa: {
          manifest:       find_file(app_path, PWA_MANIFEST_CANDIDATES),
          service_worker: find_file(app_path, SW_CANDIDATES)
        },
        js_signals:    js_signals(js_src, app_path),
        partial_count: count_partials(app_path),
        shared_layout: shared_layout?(app_path)
      }
    end

    def scan_all_deploy
      self.class.deploy_apps.map do |name|
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
    rescue StandardError
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
      signals << :turbo_lifecycle     if source.match?(/turbo:load|turbo:frame-load/)
      signals << :jquery_present      if source.match?(/\$\(|\bjQuery\b/)
      signals << :sw_registered       if source.match?(/serviceWorker\.register/)
      signals << :cache_first_sw      if cache_first_sw?(path)
      signals
    end

    # cache-first pattern: serve cached unconditionally; network only for misses
    def cache_first_sw?(path)
      sw_rel = find_file(path, SW_CANDIDATES)
      return false unless sw_rel
      src = File.read(File.join(path, sw_rel)) rescue return false
      src.match?(/caches\.match.*\|\|.*fetch/m)
    end

    def count_partials(path)
      Dir.glob(File.join(path, "app", "views", "**", "_*.html.erb")).size
    rescue StandardError
      0
    end

    def shared_layout?(path)
      Dir.exist?(File.join(File.dirname(path), "__shared"))
    end

    def subset(gems, wanted) = wanted & gems
  end
  end
end
