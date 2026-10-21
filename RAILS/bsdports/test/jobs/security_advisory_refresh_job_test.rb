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

  test "refreshes only OpenBSD ports in a mixed-platform catalogue" do
    openbsd = Platform.find_or_create_by!(slug: "openbsd") { |p| p.name = "OpenBSD" }
    freebsd = Platform.find_or_create_by!(slug: "freebsd") { |p| p.name = "FreeBSD" }
    openbsd_category = Category.find_or_create_by!(platform: openbsd, slug: "devel") { |c| c.name = "devel" }
    freebsd_category = Category.find_or_create_by!(platform: freebsd, slug: "devel") { |c| c.name = "devel" }
    openbsd_port = Port.create!(platform: openbsd, category: openbsd_category,
                                name: "openbsd-only", version: "1.0", pkgpath: "devel/openbsd-only")
    Port.create!(platform: freebsd, category: freebsd_category,
                 name: "freebsd-only", version: "1.0", pkgpath: "devel/freebsd-only")

    calls = []
    NvdCveCrossrefJob.stub(:enqueue_for, ->(**arguments) { calls << arguments[:port_id] }) do
      SecurityAdvisoryRefreshJob.perform_now(batch_size: 10)
    end

    assert_equal [ openbsd_port.id ], calls
    assert_equal openbsd_port.id, @memory_cache.read(SecurityAdvisoryRefreshJob::CURSOR_KEY)
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

    calls = []
    NvdCveCrossrefJob.stub(:enqueue_for, ->(**arguments) { calls << arguments[:port_id] }) do
      SecurityAdvisoryRefreshJob.perform_now(batch_size: 2)
    end

    assert_equal 2, calls.size
    assert_equal ports.map(&:id).sort, calls.sort
    assert_equal ports.last.id, @memory_cache.read(SecurityAdvisoryRefreshJob::CURSOR_KEY)
  end
  test "a queue failure keeps the cursor at the last successfully queued port" do
    platform = Platform.find_or_create_by!(slug: "openbsd") { |record| record.name = "OpenBSD" }
    category = Category.find_or_create_by!(platform:, slug: "refresh-failure") do |record|
      record.name = "refresh-failure"
    end
    ports = 2.times.map do |index|
      Port.create!(
        platform:, category:, name: "refresh-failure-#{index}",
        version: "1", pkgpath: "devel/refresh-failure-#{index}"
      )
    end
    attempted = []

    NvdCveCrossrefJob.stub(:enqueue_for, lambda { |port_id:|
      attempted << port_id
      raise "queue unavailable" if port_id == ports.last.id
    }) do
      SecurityAdvisoryRefreshJob.perform_now(batch_size: 2)
    end

    assert_equal ports.map(&:id), attempted
    assert_equal ports.first.id, @memory_cache.read(SecurityAdvisoryRefreshJob::CURSOR_KEY)
  end
end
