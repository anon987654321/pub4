# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

class DependencyCommandTest < Minitest::Test
  MASTER_ROOT = File.expand_path("..", __dir__)

  def test_dependency_check_handles_its_boolean_result
    out, status = Open3.capture2e(
      RbConfig.ruby,
      File.join(MASTER_ROOT, "bin", "deps"),
      "check",
      chdir: MASTER_ROOT,
    )

    assert status.success?, out
    refute_match(/NoMethodError|undefined method.*\[\]/, out)
  end
end
