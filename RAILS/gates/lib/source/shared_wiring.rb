# frozen_string_literal: true

require_relative "../../../../OPENBSD/lib/gate_result"

module Deploy
  class SharedWiringGate
    ROOT = File.expand_path("../../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    APPS = %w[amber brgen bsdports].freeze

    REQUIRED_ROUTE_FILES = %w[auth.rb fleet.rb social.rb legal.rb].freeze
    REQUIRED_PUBLIC_FILES = %w[404.html 422.html 500.html styles/errors.css].freeze
    REQUIRED_STIMULUS_REGISTRATIONS = %w[
      autosave draft-store media-picker feed-compose scroll-reveal offline-feed pwa-standalone
    ].freeze
    REQUIRED_SHARED_INITIALIZERS = %w[omniauth.rb auth_extensions.rb].freeze
    REQUIRED_SHARED_CONTROLLERS = %w[shared/reactions_controller.rb].freeze
    REQUIRED_ENV_BASELINES = {
      "development.rb" => "shared/config/environments/development.rb",
      "test.rb" => "shared/config/environments/test.rb",
      "production.rb" => "shared/config/environments/production_baseline.rb",
    }.freeze

    # Orphans that must live in shared/ only (not per-app copies).
    FORBIDDEN_APP_JS = %w[
      controllers/hello_controller.js
      idb-keyval.js
      controllers/bottom_sheet_controller.js
      controllers/offline_feed_controller.js
    ].freeze

    def self.run
      new.run
    end

    def run
      result = GateResult.new
      baseline = File.join(RAILS_ROOT, "shared/config/importmap_baseline.rb")
      boot = File.join(RAILS_ROOT, "shared/frontend/stimulus_boot.js")

      result.fail("missing shared importmap baseline") unless File.file?(baseline)
      result.fail("missing stimulus_boot.js") unless File.file?(boot)

      baseline_text = File.read(baseline)
      boot_text = File.read(boot)
      %w[
        pub4/autosave pub4/draft_store pub4/media_picker pub4/feed_compose pub4/scroll_reveal
        pub4/offline_feed pub4/pwa_standalone
      ].each do |pin|
        result.fail("importmap_baseline missing pin #{pin}") unless baseline_text.include?(%("#{pin}"))
      end
      REQUIRED_STIMULUS_REGISTRATIONS.each do |name|
        result.fail("pub4_stimulus_boot must register #{name}") unless boot_text.include?(%("#{name}"))
      end

      REQUIRED_SHARED_INITIALIZERS.each do |file|
        path = File.join(RAILS_ROOT, "shared/config/initializers", file)
        result.fail("missing shared initializer #{file}") unless File.file?(path)
      end

      REQUIRED_SHARED_CONTROLLERS.each do |file|
        path = File.join(RAILS_ROOT, "shared/app/controllers", file)
        result.fail("missing shared controller #{file}") unless File.file?(path)
      end

      APPS.each do |app|
        routes_path = File.join(RAILS_ROOT, app, "config/routes.rb")
        importmap_path = File.join(RAILS_ROOT, app, "config/importmap.rb")
        reactions_path = File.join(RAILS_ROOT, app, "app/controllers/reactions_controller.rb")
        result.fail("#{app}: missing config/routes.rb") unless File.file?(routes_path)
        result.fail("#{app}: missing config/importmap.rb") unless File.file?(importmap_path)

        routes = File.read(routes_path)
        importmap = File.read(importmap_path)

        REQUIRED_ROUTE_FILES.each do |file|
          needle = "shared/config/routes/#{file}"
          result.fail("#{app}: routes must eval #{needle}") unless routes.include?(needle)
        end

        result.fail("#{app}: importmap must eval importmap_baseline.rb") unless importmap.include?("importmap_baseline.rb")

        REQUIRED_ENV_BASELINES.each do |file, needle|
          env_path = File.join(RAILS_ROOT, app, "config/environments", file)
          next unless File.file?(env_path)

          env_source = File.read(env_path)
          result.fail("#{app}: #{file} must require #{needle}") unless env_source.include?(needle)
        end

        if File.file?(reactions_path)
          reactions = File.read(reactions_path)
          result.fail("#{app}: ReactionsController must subclass Shared::ReactionsController") unless reactions.include?("Shared::ReactionsController")
        end

        REQUIRED_PUBLIC_FILES.each do |file|
          path = File.join(RAILS_ROOT, app, "public", file)
          result.fail("#{app}: missing public/#{file}") unless File.file?(path)
        end

        FORBIDDEN_APP_JS.each do |rel|
          path = File.join(RAILS_ROOT, app, "app/javascript", rel)
          result.fail("#{app}: remove local #{rel} — use shared copy") if File.file?(path)
        end
      end

      result
    end
  end
end
