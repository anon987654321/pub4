# frozen_string_literal: true

require "minitest/autorun"

# The source worker and the three built copies must agree on how long a page
# waits for the network and which responses it is willing to cache. The built
# files are minified, so each is checked for the minified spelling.
class ServiceWorkerPageCacheTest < Minitest::Test
  RAILS = File.expand_path("..", __dir__)
  APPS = %w[amber brgen bsdports].freeze

  def test_source_worker_falls_back_after_four_seconds_and_caches_only_200
    worker = File.read(File.join(RAILS, "shared/pwa/service_worker.js"))

    assert_includes worker, "networkTimeoutSeconds: 4,"
    refute_match(/statuses: \[[^\]]*\b0\b/, worker)
  end

  def test_every_built_worker_matches_the_source
    APPS.each do |app|
      worker = File.read(File.join(RAILS, app, "app/views/pwa/service-worker.js"))

      assert_includes worker, "networkTimeoutSeconds:4,", "#{app}: rebuild with npm run build:pwa"
      assert_equal 3, worker.scan("statuses:[200]").size, "#{app}: a cache still accepts opaque responses"
      refute_includes worker, "statuses:[0,200]", app
    end
  end
end
