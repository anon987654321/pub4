# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../../shared/app/services/shared/cache_policy"
require_relative "../../../shared/app/services/shared/cache_health"
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
end
