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

      [ "ENOSYS", "EPERM" ].each do |denied_errno|
        output, status = Open3.capture2e(executable, denied_errno)
        skip output if status.exitstatus == 77
        assert status.success?, output
      end

      if ENV["MASTER_RUBY_STATX_PATCHED"] == "1"
      path = File.join(directory, "ruby-statx-target")
      link = "#{path}.link"
      File.binwrite(path, "pub4-statx")
      File.symlink(path, link)
      ruby_probe = <<~'RUBY'
        path, link = ARGV
        file_stat = File.stat(path)
        raise "File.stat size mismatch" unless file_stat.size == 10
        File.open(path, "rb") do |file|
          raise "IO#stat size mismatch" unless file.stat.size == 10
        end
        link_stat = File.lstat(link)
        raise "File.lstat followed the symbolic link" unless link_stat.symlink?
        begin
          File.birthtime(path)
          raise "fallback fabricated birthtime support"
        rescue NotImplementedError
          # A portable stat fallback cannot provide STATX_BTIME.
        end
        begin
          File.stat("#{path}.missing")
          raise "missing path unexpectedly existed"
        rescue Errno::ENOENT
          # Preserve the underlying filesystem error.
        end
        puts "PASS: patched Ruby stat/lstat/fstat fallback"
      RUBY

      [ "ENOSYS", "EPERM" ].each do |denied_errno|
        output, status = Open3.capture2e(executable, "--exec", denied_errno,
                                         RbConfig.ruby, "-e", ruby_probe, path, link)
        skip output if status.exitstatus == 77
        assert status.success?, output
      end
      end
    end
  end
end
