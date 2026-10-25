# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"

class ProviderHealthCacheTest < Minitest::Test
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
