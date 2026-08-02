# frozen_string_literal: true

require_relative "../../../OPENBSD/lib/gate_result"
require_relative "../../../OPENBSD/lib/deploy_inventory"

module Deploy
  class GeneratedAssetGate
    ROOT = File.expand_path("../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    WATCHED = [
      "app/assets/stylesheets/application.scss",
      "app/assets/stylesheets/**/*.scss",
      "app/javascript/**/*.js",
      "app/javascript/**/*.ts",
    ].freeze

    # An app's application.css is compiled from its own stylesheets *and* the
    # shared engine's, which is where the design tokens live — so watching only
    # the app tree let a shared change pass as fresh.
    #
    # It did. amber and bsdports shipped builds that predated
    # shared/.../_tokens.scss gaining --text-title and --text-display: 10 KB and
    # 4 KB of missing CSS respectively, with this gate green over both. Rebuilding
    # them was a no-op for the app trees and a visible change to the pages.
    SHARED_WATCHED = [
      "app/assets/stylesheets/**/*.scss",
      "frontend/**/*.js",
    ].freeze

    def self.run
      new.run
    end

    def run
      result = GateResult.new
      inventory = Inventory.new(root: ROOT)
      inventory.apps.each do |app|
        app_dir = File.join(RAILS_ROOT, app.name)
        next unless File.directory?(app_dir)

        stale?(app_dir, result, app.name)
      end
      result
    end

    private

    def source_files(app_dir)
      shared_dir = File.join(RAILS_ROOT, "shared")
      patterns = WATCHED.map { |pattern| File.join(app_dir, pattern) } +
                 SHARED_WATCHED.map { |pattern| File.join(shared_dir, pattern) }
      patterns.flat_map { |pattern| Dir.glob(pattern) }
        .uniq.select { |path| File.file?(path) }
    end

    def stale?(app_dir, result, app_name)
      build = File.join(app_dir, "app", "assets", "builds", "application.css")
      sources = source_files(app_dir)
      return if sources.empty?

      unless File.file?(build)
        result.fail("#{app_name}: missing compiled app/assets/builds/application.css")
        return
      end

      build_mtime = File.mtime(build)
      sources.each do |source|
        next if File.mtime(source) <= build_mtime

        rel = source.sub("#{app_dir}/", "").sub("#{RAILS_ROOT}/", "")
        result.fail("#{app_name}: stale asset build — #{rel} newer than application.css")
      end

      # tools/build_workbox.mjs writes app/views/pwa/service-worker.js — it is
      # served through a route, not from public/. This compared public/, which no
      # app has, so both File.file? guards were false and the whole check was
      # unreachable: shared/pwa/service_worker.js could change and no app's
      # bundle was ever reported stale.
      sw_source = File.join(RAILS_ROOT, "shared", "pwa", "service_worker.js")
      sw_build = File.join(app_dir, "app", "views", "pwa", "service-worker.js")
      return unless File.file?(sw_source)

      unless File.file?(sw_build)
        result.fail("#{app_name}: missing app/views/pwa/service-worker.js — run npm run build:pwa")
        return
      end

      return unless File.mtime(sw_source) > File.mtime(sw_build)

      result.fail("#{app_name}: stale service-worker.js relative to shared/pwa/service_worker.js " \
                  "— run npm run build:pwa")
    end
  end
end
