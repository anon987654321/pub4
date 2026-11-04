# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "shellwords"
require "tmpdir"

class TestStatxEnosysFallback < Minitest::Test
  def test_stat_family_falls_back_when_seccomp_disables_statx
    skip "Linux only" unless RUBY_PLATFORM.include?("linux")

    compiler = Shellwords.split(ENV.fetch("CC", RbConfig::CONFIG["CC"].to_s))
    skip "C compiler is not configured" if compiler.empty?

    source = File.expand_path("statx_enosys_fallback_test.c", __dir__)
    Dir.mktmpdir("master-statx-fallback") do |directory|
      executable = File.join(directory, "statx-fallback-test")
      output, status = Open3.capture2e(*compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-O2",
                                       source, "-o", executable)
      assert status.success?, output

      [[], ["EPERM"]].each do |arguments|
        output, status = Open3.capture2e(executable, *arguments)
        skip output if status.exitstatus == 77
        assert status.success?, output
      end
    end
  end
end
