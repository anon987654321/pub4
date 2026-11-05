# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../app/services/shared/cache_policy"
require_relative "../../app/services/shared/cache_health"
require_relative "../../app/services/shared/cable_health"
require_relative "../../app/services/shared/queue_failure_summary"

# The thresholds the daily and hourly health jobs alert on, and the TTLs the
# cache writes with. Each is a number an operator reads off a mail, so each is
# pinned where it is computed.
class HealthChecksTest < Minitest::Test
  def test_cache_policy_exposes_explicit_ttls
    assert_equal 900, Shared::CachePolicy.ttl_for(:search_results)
    assert_raises(KeyError) { Shared::CachePolicy.ttl_for(:static_page) }
  end

  # A TTL nobody writes with is a number that looks like policy and is not.
  # feed_fragment and user_profile sat here with no caller in any app.
  def test_every_cache_policy_ttl_has_a_reader
    rails = File.expand_path("../../..", __dir__)
    sources = Dir[File.join(rails, "*", "app", "**", "*.rb")].map { |path| File.read(path) }.join("\n")
    keys = Shared::CachePolicy::TTL.keys
    unread = keys.reject { |key| sources.match?(/ttl_for\(:#{key}\)/) }

    assert_empty unread, "CachePolicy TTLs no app reads"
  end

  def test_cache_health_alert_trips_above_eighty_percent
    assert Shared::CacheHealth.alert?(bytes_used: 81, max_size_bytes: 100)
    refute Shared::CacheHealth.alert?(bytes_used: 79, max_size_bytes: 100)
    assert_equal 81.0, Shared::CacheHealth.usage_percent(bytes_used: 81, max_size_bytes: 100)
    assert_match(/brgen cache at 81.0%/, Shared::CacheHealth.message(app: "brgen", bytes_used: 81, max_size_bytes: 100))
  end

  def test_cable_health_alert_trips_above_one_thousand_connections
    assert Shared::CableHealth.alert?(connection_count: 1_001, max_connections: 1_000)
    refute Shared::CableHealth.alert?(connection_count: 999, max_connections: 1_000)
    assert_equal "brgen cable at 1001/1000 connections",
                 Shared::CableHealth.message(app: "brgen", connection_count: 1_001, max_connections: 1_000)
  end

  def test_queue_failure_summary_names_each_failing_job
    rows = [
      { class_name: "ExampleJob", queue_name: "bulk", failures: 3, last_failed_at: "2026-01-01 04:00:00" },
    ]
    summary = Shared::QueueFailureSummary.call(rows, app: "brgen")

    assert_includes summary, "ExampleJob (bulk): 3 failure(s)"
    assert_includes summary, "brgen queue dead letters"
  end
end
