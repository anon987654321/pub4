# frozen_string_literal: true

require_relative "test_helper"

class TestSystemInfo < Minitest::Test
  class HwRenderer < Master::Voice::Renderer
    def sysctl_value(key)
      {
        "hw.model" => "Mac14,9",
        "machdep.cpu.brand_string" => "Apple M2 Pro",
        "hw.memsize" => "17179869184",
        "kern.ostype" => "Darwin",
        "kern.osrelease" => "25.5.0",
        "hw.machine" => "arm64",
      }[key]
    end

    def available_memory_bytes
      4_294_967_296
    end
  end

  def test_macos_hw_lines_read_like_a_dmesg
    lines = HwRenderer.new(config: {}).send(:macos_hw_lines)

    assert_equal [
      "real mem = 17179869184 (16384MB)",
      "avail mem = 4294967296 (4096MB)",
      "mainbus0 at root: Mac14,9",
      "cpu0 at mainbus0: Apple M2 Pro",
      "kern0 at mainbus0: Darwin 25.5.0 arm64",
    ], lines
  end

  # A Linux host is told in the same grammar, never pasted: no "[    0.000000]"
  # timestamps and no kernel command line.
  def test_linux_hw_lines_read_like_a_dmesg
    skip "needs /proc" unless File.readable?("/proc/meminfo") && File.readable?("/proc/cpuinfo")

    lines = Master::Voice::Renderer.new(config: {}).send(:linux_hw_lines)

    assert_match(/\Areal mem = \d+ \(\d+MB\)\z/, lines.first)
    assert_includes lines, "mainbus0 at root"
    assert_match(/\Acpu0 at mainbus0: \S/, lines.find { |line| line.start_with?("cpu0 ") })
    refute(lines.any? { |line| line.start_with?("[") || line.include?("Command line") }, lines.inspect)
  end

  # The banner named "now loop judge reach ok" for a release after those
  # directories were renamed, because the list was a literal.
  def test_module_names_are_read_from_the_tree
    names = Master::Voice::Renderer.new(config: {}).send(:module_names)

    assert_includes names, "voice"
    assert_includes names, "ground"
    names.each do |name|
      assert_path_exists File.join(Master::ROOT, "lib", name)
    end
  end
end
