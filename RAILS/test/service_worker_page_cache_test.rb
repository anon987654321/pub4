# frozen_string_literal: true

require "minitest/autorun"

# The source worker and the three built copies must agree on how long a page
# waits for the network and which responses it is willing to cache. The built
# files are minified, so each is checked for the minified spelling.
class ServiceWorkerPageCacheTest < Minitest::Test
  RAILS = File.expand_path("..", __dir__)
  APPS = %w[amber brgen bsdports].freeze

  def test_source_worker_falls_back_after_four_seconds_and_caches_only_200
    worker = File.read(File.join(RAILS, "__shared/pwa/service_worker.js"))

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

  # A cache outlives a session, so a person's own pages are never written to
  # one, signing in or out empties the page caches, and only new posts,
  # comments and messages wait offline to be replayed. Checked in the source
  # and in every built copy, which is what a phone actually runs.
  def test_private_pages_stay_out_of_every_cache_and_only_new_content_replays
    source = File.read(File.join(RAILS, "__shared/pwa/service_worker.js"))
    %w[/conversations /messages /notifications /session /checkout].each do |path|
      assert_includes source, %("#{path}"), "#{path} must be a private prefix"
    end
    assert_includes source, "const REPLAYABLE_POST = /(^|\\/)(posts|comments|replies|messages)$/"

    APPS.each do |app|
      built = File.read(File.join(RAILS, app, "app/views/pwa/service-worker.js"))
      assert_includes built, '"/conversations"', "#{app}: rebuild with npm run build:pwa"
      assert_includes built, "clear-private-caches", "#{app}: rebuild with npm run build:pwa"
      assert_includes built, "(posts|comments|replies|messages)$", "#{app}: rebuild with npm run build:pwa"
      assert_includes built, "navigationPreload", "#{app}: rebuild with npm run build:pwa"
      refute_includes built, '"revision":"shell-v1"', "#{app}: the home page is precached"
    end
  end

end
