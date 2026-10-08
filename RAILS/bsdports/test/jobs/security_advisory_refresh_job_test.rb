# frozen_string_literal: true

require "test_helper"

class SecurityAdvisoryRefreshJobTest < ActiveJob::TestCase
  parallelize(workers: 1)

  setup do
    @original_cache = Rails.cache
    @memory_cache = ActiveSupport::Cache.lookup_store(:memory_store)
    Rails.cache = @memory_cache
    Rails.application.config.cache_store = @memory_cache
    @memory_cache.delete(SecurityAdvisoryRefreshJob::CURSOR_KEY)
  end

  teardown do
    Rails.application.config.cache_store = @original_cache
    Rails.cache = @original_cache
  end

  test "refreshes advisories in batches and advances cursor" do
    platform = Platform.find_or_create_by!(slug: "openbsd") { |p| p.name = "OpenBSD" }
    category = Category.first || Category.create!(platform: platform, name: "devel")
    ports = 2.times.map do |i|
      Port.create!(
        platform: platform,
        category: category,
        name: "test-port-#{i}",
        version: "1.0",
        pkgpath: "devel/test-port-#{i}"
      )
    end

    advisories = [ SecurityAdvisory.new(identifier: "CVE-TEST-1") ]
    calls = []
    Kernel.stub(:sleep, nil) do
      NvdCve.stub(:crossref, ->(port, limit: 5) { calls << [ port.id, limit ]; advisories }) do
        SecurityAdvisoryRefreshJob.perform_now(batch_size: 2)
      end
    end

    assert_equal 2, calls.size
    assert_equal ports.map(&:id).sort, calls.map(&:first).sort
    assert_equal ports.last.id, @memory_cache.read(SecurityAdvisoryRefreshJob::CURSOR_KEY)
  end
end
