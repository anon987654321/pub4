# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class TestBootBanner < Minitest::Test
  def test_print_is_silent_by_default
    ENV.delete("MASTER_BOOT_STATUS")
    io = StringIO.new
    Master::CLI::BootBanner.print(io:)
    assert_empty io.string
  end

  def test_print_emits_banner_lines_when_enabled
    ENV["MASTER_BOOT_STATUS"] = "1"
    io = StringIO.new
    Master::CLI::BootBanner.print(io:)
    assert_includes io.string, "master: boot safe="
    assert_includes io.string, "master: ready dmesg=preserved"
  ensure
    ENV.delete("MASTER_BOOT_STATUS")
  end

  def test_banner_lines_reflect_env_flags
    lines = Master::CLI::BootBanner.banner_lines
    assert(lines.any? { |line| line.start_with?("master: boot safe=") })
    assert(lines.any? { |line| line.start_with?("master: aesthetic=") })
  end

  # Regression: bin/cli's --boot-status flag set MASTER_BOOT_STATUS=1 but
  # nothing ever called BootBanner.print, so the flag was completely inert.
  def test_master_boot_calls_boot_banner
    source = File.read(File.join(Master::ROOT, "lib", "boot", "master_boot.rb"))
    assert_includes source, "CLI::BootBanner.print"
  end
end
