# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../shared/app/services/shared/cache_policy"
require_relative "../../../shared/app/services/shared/cache_health"
require_relative "../../../shared/app/services/shared/cable_health"
require_relative "../../../shared/app/services/shared/queue_failure_summary"

class DeployBacklogTest < Minitest::Test
  ROOT = File.expand_path("../../..", __dir__)

  def test_shared_cache_policy_exposes_explicit_ttls
    assert_equal 300, Shared::CachePolicy.ttl_for(:feed_fragment)
    assert_equal 3600, Shared::CachePolicy.ttl_for(:user_profile)
    assert_equal 900, Shared::CachePolicy.ttl_for(:search_results)
    assert_equal 86_400, Shared::CachePolicy.ttl_for(:static_page)
  end

  def test_admin_jobs_route_is_mounted_in_app_routes
    %w[
      amber/config/routes.rb
      baibl/config/routes.rb
      blognet/config/routes.rb
      brgen/config/routes.rb
      bsdports/config/routes.rb
      hjerterom/config/routes.rb
    ].each do |relative|
      source = File.read(File.join(ROOT, relative))
      assert_includes source, 'mount SolidQueue::Engine, at: "/admin/jobs"'
      assert_match(/jobs_constraint = ->\(request\) \{ request\.cookies\["session_id"\]\.present\? \}/, source)
    end
  end

  def test_cache_health_alert_trips_above_eighty_percent
    assert Shared::CacheHealth.alert?(bytes_used: 81, max_size_bytes: 100)
    refute Shared::CacheHealth.alert?(bytes_used: 79, max_size_bytes: 100)
    assert_equal 81.0, Shared::CacheHealth.usage_percent(bytes_used: 81, max_size_bytes: 100)
    assert_match(/brgen cache at 81.0%/, Shared::CacheHealth.message(app: "brgen", bytes_used: 81, max_size_bytes: 100))
  end

  def test_cache_health_job_is_scheduled
    source = File.read(File.join(ROOT, "brgen/config/recurring.yml"))
    assert_includes source, "cache_health_check:"
    assert_includes source, "class: CacheHealthJob"
    assert_includes source, "schedule: every day at 4am"
  end

  def test_queue_failure_summary_and_digest_schedule
    rows = [
      { class_name: "ExampleJob", queue_name: "bulk", failures: 3, last_failed_at: "2026-01-01 04:00:00" }
    ]
    summary = Shared::QueueFailureSummary.call(rows, app: "brgen")
    assert_includes summary, "ExampleJob (bulk): 3 failure(s)"
    assert_includes summary, "brgen queue dead letters"

    source = File.read(File.join(ROOT, "brgen/config/recurring.yml"))
    assert_includes source, "queue_failure_digest:"
    assert_includes source, "class: QueueFailureDigestJob"
    assert_includes source, "schedule: every day at 5am"

    job_source = File.read(File.join(ROOT, "brgen/app/jobs/queue_failure_digest_job.rb"))
    assert_includes job_source, "solid_queue_failed_executions"
    assert_includes job_source, "QueueFailureMailer.daily_digest"
  end

  def test_cable_health_alert_trips_at_one_thousand_connections
    assert Shared::CableHealth.alert?(connection_count: 1_001, max_connections: 1_000)
    refute Shared::CableHealth.alert?(connection_count: 999, max_connections: 1_000)
    assert_equal "brgen cable at 1001/1000 connections", Shared::CableHealth.message(app: "brgen", connection_count: 1_001, max_connections: 1_000)
  end

  def test_turbo_navigation_and_cache_controls_are_explicit
    %w[
      amber/app/javascript/application.js
      baibl/app/javascript/application.js
      blognet/app/javascript/application.js
      bsdports/app/javascript/application.js
      hjerterom/app/javascript/application.js
      brgen/app/assets/face.js
    ].each do |relative|
      source = File.read(File.join(ROOT, relative))
      assert_includes source, "Turbo.config.drive.progressBarDelay = 100"
    end

    %w[
      amber/app/views/layouts/application.html.erb
      baibl/app/views/layouts/application.html.erb
      blognet/app/views/layouts/application.html.erb
      bsdports/app/views/layouts/application.html.erb
      hjerterom/app/views/layouts/application.html.erb
      brgen/app/views/layouts/application.html.erb
    ].each do |relative|
      source = File.read(File.join(ROOT, relative))
      assert_includes source, 'data-turbo-permanent'
      assert_includes source, 'turbo_prefetch: false'
      assert_includes source, 'turbo-cache-control", content: "no-cache"'
    end

    %w[
      amber/app/controllers/application_controller.rb
      baibl/app/controllers/application_controller.rb
      blognet/app/controllers/application_controller.rb
      brgen/app/controllers/application_controller.rb
      bsdports/app/controllers/application_controller.rb
      hjerterom/app/controllers/application_controller.rb
    ].each do |relative|
      source = File.read(File.join(ROOT, relative))
      assert_includes source, "turbo_refreshes_with :morph, scroll: :preserve"
    end

    source = File.read(File.join(ROOT, "shared/frontend/layouts/_nav.html.erb"))
    assert_includes source, 'data-turbo-permanent'
    assert_includes source, 'turbo_prefetch: false'

    pagy_source = File.read(File.join(ROOT, "shared/config/initializers/pagy.rb"))
    assert_includes pagy_source, 'data-turbo-prefetch="false"'
    assert_includes pagy_source, 'rel="prefetch"'
  end

  def test_sqlite_wal_and_shared_stimulus_components_are_present
    %w[
      amber/config/database.yml
      baibl/config/database.yml
      blognet/config/database.yml
      brgen/config/database.yml
      bsdports/config/database.yml
      hjerterom/config/database.yml
    ].each do |relative|
      source = File.read(File.join(ROOT, relative))
      assert_includes source, "journal_mode: WAL"
    end

    %w[
      amber/config/environments/development.rb
      baibl/config/environments/development.rb
      blognet/config/environments/development.rb
      brgen/config/environments/development.rb
      bsdports/config/environments/development.rb
      hjerterom/config/environments/development.rb
    ].each do |relative|
      source = File.read(File.join(ROOT, relative))
      assert_includes source, "strict_loading_by_default = true"
    end

    source = File.read(File.join(ROOT, "shared/frontend/stimulus_components.js"))
    %w[
      Clipboard
      Dialog
      Dropdown
      Hotkey
      Notification
      Reveal
      Sortable
      toast
      TextareaAutogrow
      Timeago
    ].each do |component|
      assert_includes source, component
    end

    assert_includes File.read(File.join(ROOT, "shared/app/views/shared/_toast.html.erb")), 'data-controller="toast"'
    assert_includes File.read(File.join(ROOT, "shared/frontend/examples.html.erb")), 'data-controller="toast"'

    assert_includes File.read(File.join(ROOT, "amber/app/views/wardrobe_items/_form.html.erb")), 'controller: "textarea-autogrow"'
    assert_includes File.read(File.join(ROOT, "brgen/app/views/posts/show.html.erb")), 'textarea-autogrow'
    assert_includes File.read(File.join(ROOT, "brgen/app/views/posts/_post.html.erb")), "cache [post, Current.user&.id]"
    assert_includes File.read(File.join(ROOT, "amber/app/views/posts/_post.html.erb")), "cache [post, Current.user&.id]"
    assert_includes File.read(File.join(ROOT, "brgen/app/views/posts/_post.html.erb")), 'data-controller="clipboard"'
    assert_includes File.read(File.join(ROOT, "shared/app/views/shared/_copyable.html.erb")), 'data-controller="clipboard"'

    helper_source = File.read(File.join(ROOT, "amber/app/helpers/application_helper.rb"))
    assert_includes helper_source, "content_tag(:picture)"
    assert_includes helper_source, 'type: "image/webp"'
    assert_includes helper_source, 'loading: "lazy"'
    assert_includes helper_source, "responsive_image_url"
    assert_includes File.read(File.join(ROOT, "amber/app/views/items/show.html.erb")), "responsive_image_tag photo"
    assert_includes File.read(File.join(ROOT, "amber/app/views/outfits/dressing_room.html.erb")), "responsive_image_url(item.photos.first"

    %w[
      brgen/app/views/pwa/manifest.json.erb
      amber/app/views/pwa/manifest.json.erb
      blognet/app/views/pwa/manifest.json.erb
      bsdports/app/views/pwa/manifest.json.erb
    ].each do |relative|
      source = File.read(File.join(ROOT, relative))
    assert_includes source, '"shortcuts"'
  end

    assert_includes File.read(File.join(ROOT, "brgen/app/views/pwa/manifest.json.erb")), "New listing"
    assert_includes File.read(File.join(ROOT, "brgen/app/views/pwa/manifest.json.erb")), '"protocol_handlers"'
    assert_includes File.read(File.join(ROOT, "brgen/app/views/pwa/manifest.json.erb")), "web+brgen"
    assert_includes File.read(File.join(ROOT, "brgen/app/javascript/controllers/push_controller.js")), "navigator.setAppBadge"
    assert_includes File.read(File.join(ROOT, "brgen/app/javascript/controllers/push_controller.js")), "navigator.clearAppBadge"
    assert_includes File.read(File.join(ROOT, "brgen/public/pwa/workbox-sw.js")), "navigator.setAppBadge"
    assert_includes File.read(File.join(ROOT, "brgen/app/views/pwa/service-worker.js")), "importScripts"
    assert_includes File.read(File.join(ROOT, "brgen/app/views/layouts/application.html.erb")), 'data-push-unread-value='
    assert_includes File.read(File.join(ROOT, "amber/app/views/pwa/manifest.json.erb")), "Create outfit"
    assert_includes File.read(File.join(ROOT, "blognet/app/views/pwa/manifest.json.erb")), "New post"
    assert_includes File.read(File.join(ROOT, "bsdports/app/views/pwa/manifest.json.erb")), "Search ports"
    assert_includes File.read(File.join(ROOT, "amber/app/views/pwa/manifest.json.erb")), '"file_handlers"'
    assert_includes File.read(File.join(ROOT, "blognet/app/views/pwa/manifest.json.erb")), '"file_handlers"'
    assert_includes File.read(File.join(ROOT, "amber/app/views/pwa/manifest.json.erb")), "image/*"
    assert_includes File.read(File.join(ROOT, "blognet/app/views/pwa/manifest.json.erb")), "text/markdown"

    ports_controller = File.read(File.join(ROOT, "bsdports/app/controllers/ports_controller.rb"))
    assert_includes ports_controller, "expires_in 10.minutes, public: true"
    assert_includes ports_controller, "fresh_when(@port, public: true)"

    source = File.read(File.join(ROOT, "brgen/config/recurring.yml"))
    assert_includes source, "cable_health_check:"
    assert_includes source, "class: CableHealthJob"
    assert_includes source, "schedule: every hour at minute 7"
  end
end
