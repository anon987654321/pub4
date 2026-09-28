# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"

class TestBootChecks < Minitest::Test
  CHECKS = Master::Ground::BootChecks

  def with_root
    Dir.mktmpdir("master-boot-checks-") do |root|
      FileUtils.mkdir_p(File.join(root, ".master"))
      yield root
    end
  end

  def test_invalid_config_remains_fatal_and_aborts
    with_root do |root|
      File.write(File.join(root, ".master", "config.yml"), "web_port: 0\n")

      result = CHECKS.send(:check_config_valid, root)
      refute result.ok
      assert_equal :fatal, result.severity
      assert_includes result.message, "web_port must be 1-65535"

      assert_raises(SystemExit) { CHECKS.abort_on_fatals([result]) }
    end
  end

  def test_missing_data_file_remains_fatal
    with_root do |root|
      data = File.join(root, "data")
      FileUtils.mkdir_p(data)
      File.write(File.join(data, "soul.yml"), "---\n")
      File.write(File.join(data, "rules.yml"), "---\n")
      result = CHECKS.send(:check_data_dir, root)

      refute result.ok
      assert_equal :fatal, result.severity
      assert_includes result.message, "limits.yml"
    end
  end
end
