# frozen_string_literal: true

require "test_helper"

class JobConcurrencyTest < ActiveSupport::TestCase
  test "one ports import at a time, whatever its arguments" do
    assert_equal 1, PortsImportJob.concurrency_limit
    assert_equal :discard, PortsImportJob.concurrency_on_conflict
    assert_equal PortsImportJob.new.concurrency_key,
                 PortsImportJob.new(platform_slug: "openbsd", tree_path: "/usr/ports").concurrency_key
  end

  test "one advisory refresh at a time" do
    assert_equal 1, SecurityAdvisoryRefreshJob.concurrency_limit
    assert_equal :discard, SecurityAdvisoryRefreshJob.concurrency_on_conflict
    assert_equal SecurityAdvisoryRefreshJob.new.concurrency_key,
                 SecurityAdvisoryRefreshJob.new(batch_size: 10).concurrency_key
  end
end
