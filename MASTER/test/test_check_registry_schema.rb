# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"

class CheckRegistrySchemaTest < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  RUNNER = File.join(REPO_ROOT, "MASTER", "checks", "runner.rb")

  def test_headless_registry_row_is_rejected_before_checks_run
    Dir.mktmpdir("check-registry-") do |dir|
      registry = File.join(dir, "checks.yml")
      File.write(registry, "headless:\n  pass: \"this must not be reported as checked\"\n")

      output, status = Open3.capture2e(
        { "CHECKS_FILE" => registry },
        RbConfig.ruby, RUNNER, "--all",
        chdir: REPO_ROOT
      )

      refute status.success?, output
      assert_equal 1, status.exitstatus, output
      assert_includes output, "checks: invalid registry"
      assert_includes output, "headless must declare class: or script:"
      refute_includes output, "headless passed"
    end
  end

  def test_registry_root_must_be_a_mapping
    Dir.mktmpdir("check-registry-") do |dir|
      registry = File.join(dir, "checks.yml")
      File.write(registry, "- not-a-registry-mapping\n")

      output, status = Open3.capture2e(
        { "CHECKS_FILE" => registry },
        RbConfig.ruby, RUNNER, "--all",
        chdir: REPO_ROOT
      )

      refute status.success?, output
      assert_equal 1, status.exitstatus, output
      assert_includes output, "checks: invalid registry root"
    end
  end
end
