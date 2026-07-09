# frozen_string_literal: true

require "test_helper"

class PortsImportJobTest < ActiveJob::TestCase
  test "imports fixture tree for openbsd platform" do
    tree_path = Rails.root.join("test/fixtures/ports/openbsd")

    assert_difference -> { Port.count }, 2 do
      PortsImportJob.perform_now(platform_slug: "openbsd", tree_path:, use_ftp_fallback: false)
    end
  end
end