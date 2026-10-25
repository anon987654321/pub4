# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"

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
