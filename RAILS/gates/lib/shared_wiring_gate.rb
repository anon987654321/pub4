# frozen_string_literal: true

require_relative "../../../OPENBSD/lib/gate_result"

module Deploy
  class SharedWiringGate
    ROOT = File.expand_path("../../..", __dir__)
    RAILS_ROOT = File.join(ROOT, "RAILS")
    APPS = %w[amber brgen bsdports].freeze

    REQUIRED_ROUTE_FILES = %w[auth.rb fleet.rb social.rb].freeze
    REQUIRED_PUBLIC_FILES = %w[404.html 422.html 500.html styles/errors.css].freeze
    REQUIRED_STIMULUS_REGISTRATIONS = %w[autosave draft-store media-picker feed-compose scroll-reveal].freeze

    def self.run
      new.run
    end

    def run
      result = GateResult.new
      baseline = File.join(RAILS_ROOT, "shared/config/importmap_baseline.rb")
      boot = File.join(RAILS_ROOT, "shared/frontend/pub4_stimulus_boot.js")

      result.fail("missing shared importmap baseline") unless File.file?(baseline)
      result.fail("missing pub4_stimulus_boot.js") unless File.file?(boot)

      baseline_text = File.read(baseline)
      boot_text = File.read(boot)
      %w[pub4/autosave pub4/draft_store pub4/media_picker pub4/feed_compose pub4/scroll_reveal].each do |pin|
        result.fail("importmap_baseline missing pin #{pin}") unless baseline_text.include?(%("#{pin}"))
      end
      REQUIRED_STIMULUS_REGISTRATIONS.each do |name|
        result.fail("pub4_stimulus_boot must register #{name}") unless boot_text.include?(%("#{name}"))
      end

      APPS.each do |app|
        routes_path = File.join(RAILS_ROOT, app, "config/routes.rb")
        importmap_path = File.join(RAILS_ROOT, app, "config/importmap.rb")
        result.fail("#{app}: missing config/routes.rb") unless File.file?(routes_path)
        result.fail("#{app}: missing config/importmap.rb") unless File.file?(importmap_path)

        routes = File.read(routes_path)
        importmap = File.read(importmap_path)

        REQUIRED_ROUTE_FILES.each do |file|
          needle = "shared/config/routes/#{file}"
          result.fail("#{app}: routes must eval #{needle}") unless routes.include?(needle)
        end

        result.fail("#{app}: importmap must eval importmap_baseline.rb") unless importmap.include?("importmap_baseline.rb")

        REQUIRED_PUBLIC_FILES.each do |file|
          path = File.join(RAILS_ROOT, app, "public", file)
          result.fail("#{app}: missing public/#{file}") unless File.file?(path)
        end
      end

      result
    end
  end
end