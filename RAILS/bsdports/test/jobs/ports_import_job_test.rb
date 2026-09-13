# frozen_string_literal: true

require "test_helper"

class PortsImportJobTest < ActiveJob::TestCase
  test "imports fixture tree for openbsd platform" do
    tree_path = Rails.root.join("test/fixtures/ports/openbsd")

    assert_difference -> { Port.count }, 2 do
      PortsImportJob.perform_now(platform_slug: "openbsd", tree_path:, use_ftp_fallback: false)
    end
  end

  test "an inactive platform is refused before anything is imported" do
    Platform.create!(name: "FreeBSD", slug: "freebsd", active: false)
    tree_path = Rails.root.join("test/fixtures/ports/openbsd")

    assert_no_difference -> { Port.count } do
      assert_raises(ActiveRecord::RecordNotFound) do
        PortsImportJob.perform_now(platform_slug: "freebsd", tree_path:, use_ftp_fallback: false)
      end
    end
  end
end
