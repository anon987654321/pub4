# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "time"

class CapabilityStampTest < Minitest::Test
  def health_at(dir, at:, status: :success, model: "claude-cli:opus")
    health = Master::CLI::Routing::ProviderHealth.new(
      path: File.join(dir, "runtime", "telemetry", "provider_health.ndjson"),
      now: -> { at },
    )
    health.record(model:, status:, at:)
    health
  end

  def test_stamp_reports_fresh_cloud_model
    Dir.mktmpdir do |dir|
      now = Time.utc(2026, 9, 28, 13, 0, 0)
      health = health_at(dir, at: now - 41, model: "claude-cli:opus")
      policy = Master::CLI::Routing::AvailabilityPolicy.new(root: dir)

      assert_equal(
        "model0 at master0: served claude-cli:opus, level L4, health fresh 41s, degraded no",
        Master::CLI::CapabilityStamp.render(model: "claude-cli:opus", root: dir, provider_health: health, policy:),
      )
    end
  end

  def test_stamp_reports_stale_evidence_without_calling_it_healthy
    Dir.mktmpdir do |dir|
      now = Time.utc(2026, 9, 28, 13, 0, 0)
      health = health_at(dir, at: now - 180, model: "web-chat:grok")
      health_now = Master::CLI::Routing::ProviderHealth.new(
        path: health.path,
        now: -> { now },
      )
      policy = Master::CLI::Routing::AvailabilityPolicy.new(root: dir)

      assert_equal(
        "model0 at master0: served web-chat:grok, level L3, health stale 180s, degraded yes",
        Master::CLI::CapabilityStamp.render(model: "web-chat:grok", root: dir, provider_health: health_now, policy:),
      )
    end
  end

  def test_stamp_marks_unobserved_model_as_unknown
    Dir.mktmpdir do |dir|
      policy = Master::CLI::Routing::AvailabilityPolicy.new(root: dir)

      assert_equal(
        "model0 at master0: served ollama:qwen3, level L2, health unknown, degraded unknown",
        Master::CLI::CapabilityStamp.render(model: "ollama:qwen3", root: dir, policy:),
      )
    end
  end
end
