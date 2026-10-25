# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"

class ProviderHealthCacheTest < Minitest::Test
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
