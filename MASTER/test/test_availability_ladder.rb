# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class AvailabilityLadderTest < Minitest::Test
  def policy(overrides = {})
    Master::CLI::Routing::AvailabilityPolicy.new(
      config: Master::CLI::Routing::AvailabilityPolicy::DEFAULTS.merge(overrides),
    )
  end

  def test_defaults_preserve_measured_dispatch_ceiling_and_floors
    subject = policy

    assert_equal 120, subject.health_freshness_s
    assert_equal 300, subject.dispatch_deadline_s
    assert_equal "L2", subject.ladder_floor(:interactive)
    assert_equal "L1", subject.ladder_floor(:batch_scan)
    assert_equal %w[7 3 1], subject.council_sizes.map(&:to_s)
    assert_equal 7, subject.council_target(current: 20, local_posture: true, scarce: false, local_only: false)
    assert_equal 3, subject.council_target(current: 20, local_posture: false, scarce: false, local_only: true)
    assert_equal 1, subject.council_target(current: 20, local_posture: false, scarce: true, local_only: true)
  end

  def test_model_levels_do_not_call_cloud_ollama_local
    subject = policy

    assert_equal "L4", subject.level_for("claude-cli:opus")
    assert_equal "L3", subject.level_for("web-chat:grok")
    assert_equal "L3", subject.level_for("ollama:qwen3-cloud")
    assert_equal "L2", subject.level_for("ollama:qwen3")
    assert_equal "L2", subject.level_for("local:qwen3")
  end

  def test_provider_health_marks_old_evidence_stale
    Dir.mktmpdir do |dir|
      now = Time.utc(2026, 9, 28, 13, 0, 0)
      health = Master::CLI::Routing::ProviderHealth.new(
        path: File.join(dir, "provider_health.ndjson"),
        now: -> { now },
      )
      health.record(model: "cloud-model", status: :success, at: now - 121)

      assert health.observed?("cloud-model")
      assert_in_delta 121, health.age_seconds("cloud-model"), 0.01
      refute health.fresh?("cloud-model", max_age_s: 120)
      assert health.stale?("cloud-model", max_age_s: 120)
      assert_equal :unknown, health.freshness("never-seen", max_age_s: 120)
    end
  end

  def test_custom_config_can_tighten_dispatch_deadline
    subject = policy("dispatch_deadline_s" => 90)

    assert_equal 90, subject.dispatch_deadline_s
    assert subject.meets_floor?("ollama:qwen3", operation: :interactive)
  end
end
