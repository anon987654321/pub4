# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"
require "digest"

class ProviderHealthCacheTest < Minitest::Test
  def test_provider_telemetry_log_rotates_without_exceeding_shared_cap
    Dir.mktmpdir("provider-health-rotation-") do |dir|
      path = File.join(dir, "health.ndjson")
      8.times do |index|
        Master::CLI::Routing::ProviderHealth.append_json_line(
          path,
          { "model" => "provider-a", "status" => "provider_error", "detail" => "x" * 80, "n" => index },
          max_bytes: 400,
        )
      end

      assert_operator File.size(path), :<=, 400
      assert_operator File.size("#{path}.1"), :<=, 400
      File.readlines(path, chomp: true).each { |line| JSON.parse(line) }
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal 0o600, File.stat("#{path}.lock").mode & 0o777
    end
  end

  def test_provider_telemetry_rejects_a_single_record_over_the_cap
    Dir.mktmpdir("provider-health-oversize-") do |dir|
      path = File.join(dir, "health.ndjson")

      assert_raises(ArgumentError) do
        Master::CLI::Routing::ProviderHealth.append_json_line(
          path, { "detail" => "x" * 200 }, max_bytes: 40
        )
      end
      refute File.exist?(path)
    end
  end

  def test_concurrent_provider_outcomes_remain_valid_ndjson
    Dir.mktmpdir("provider-health-concurrency-") do |dir|
      path = File.join(dir, "provider-health.ndjson")
      health = Master::CLI::Routing::ProviderHealth.new(path:)
      threads = 8.times.map do |worker|
        Thread.new do
          25.times do |index|
            health.record(
              model: "provider-#{worker}",
              status: :provider_error,
              error: "outcome-#{index}",
            )
          end
        end
      end
      threads.each(&:value)

      lines = File.readlines(path, chomp: true)
      assert_equal 200, lines.size
      records = lines.map { |line| JSON.parse(line) }
      assert_equal 200, records.size
      assert_equal 25, records.count { |record| record["model"] == "provider-0" }
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal 0o700, File.stat(dir).mode & 0o777
    end
  end

  def test_retained_rotated_generation_still_contributes_to_health_score
    Dir.mktmpdir("provider-health-generation-") do |dir|
      path = File.join(dir, "provider-health.ndjson")
      now = Time.utc(2026, 10, 26, 12, 0, 0)
      File.write("#{path}.1", JSON.generate(
        "ts" => now.iso8601,
        "model" => "provider-a",
        "status" => "provider_error",
      ) + "\n")
      File.write(path, JSON.generate(
        "ts" => now.iso8601,
        "model" => "provider-a",
        "status" => "success",
      ) + "\n")

      health = Master::CLI::Routing::ProviderHealth.new(path:, now: -> { now })

      assert_in_delta 0.78, health.score("provider-a"), 0.001,
                      "score should replay the older rotated failure before the active success"
    end
  end

  def test_provider_health_persists_error_digest_instead_of_raw_error
    Dir.mktmpdir("provider-health-redaction-") do |dir|
      path = File.join(dir, "provider-health.ndjson")
      health = Master::CLI::Routing::ProviderHealth.new(path:)
      private_error = "authorization failed at https://private.example/path?token=secret"

      returned = health.record(
        model: "provider-a", status: :provider_error, error: private_error
      )
      serialized = File.read(path)
      persisted = JSON.parse(serialized.lines.last)

      assert_equal Digest::SHA256.hexdigest(private_error), persisted["error_digest"]
      assert_equal private_error.bytesize, persisted["error_bytes"]
      refute persisted.key?("error")
      refute_includes serialized, private_error
      refute_includes returned.inspect, private_error
    end
  end

  def test_missing_model_and_dispatch_failures_penalize_health
    Dir.mktmpdir("provider-health-outcomes-") do |dir|
      now = Time.utc(2026, 10, 26, 12, 0, 0)
      health = Master::CLI::Routing::ProviderHealth.new(
        path: File.join(dir, "health.ndjson"), now: -> { now }
      )

      %i[model_missing llm_call_failure].each do |status|
        health.record(model: status.to_s, status:)
        assert_in_delta 0.75, health.score(status.to_s), 0.001
        assert health.recently_failed?(status.to_s, max_age_s: 60)
      end
    end
  end

  def test_appended_event_invalidates_cache_even_when_mtime_is_unchanged
    Dir.mktmpdir("provider-health-cache-") do |dir|
      path = File.join(dir, "provider-health.ndjson")
      health = Master::CLI::Routing::ProviderHealth.new(path:)

      health.record(model: "provider-a", status: :provider_error)
      assert_in_delta 0.75, health.score("provider-a"), 0.001
      original_mtime = File.mtime(path)

      health.record(model: "provider-a", status: :provider_error)
      File.utime(original_mtime, original_mtime, path)

      assert_in_delta 0.5, health.score("provider-a"), 0.001,
                      "appended bytes must invalidate cached telemetry when mtime is unchanged"
    end
  end
end
