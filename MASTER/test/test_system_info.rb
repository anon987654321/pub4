# frozen_string_literal: true

require_relative "test_helper"

class TestSystemInfo < Minitest::Test
  class HwRenderer < Master::Voice::Renderer
    def sysctl_value(key)
      {
        "hw.model" => "Mac14,9",
        "machdep.cpu.brand_string" => "Apple M2 Pro",
        "hw.memsize" => "17179869184",
        "kern.version" => "Darwin Kernel Version 25.0.0\nmore",
      }[key]
    end
  end

  def test_macos_hw_lines_use_device_tree_shape
    renderer = HwRenderer.new(config: {})
    lines = renderer.send(:macos_hw_lines)

    assert_includes lines, "hw0 at mainbus0: Mac14,9"
    assert_includes lines, "cpu0 at mainbus0: Apple M2 Pro"
    assert_includes lines, "mem0: 16384MB avail"
    assert_equal "Darwin Kernel Version 25.0.0", lines.last
  end
end
